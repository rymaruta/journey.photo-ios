# バグ探し 2026-09-27: 落ちる・競合・Xcode だけで落ちる書き方・資源・画面が勝手に閉じる

- 対象: `claude/ios-bughunt-crash`（HEAD 499ca9b）の `Sources/JourneyPhoto` 全体。Shims・Tests は除いた
- 方法: 観点ごとに監査を4本並列で流した。**指摘は全部コードで筋を追い直した**。この文書では、追い直しで確かめられたものを「コードで確認済み」と書く
- **直していない**（このセッションは探すだけ）。実機・本物の Xcode では何も動かしていない
- 「実機が要る」は、SwiftUI の出現・消失の順番や通信のタイミングに左右されるもの

## 要約

| 重さ | 件数 | 中身 |
|---|---|---|
| 高 | 7 | 画面が勝手に閉じる 6件、前の人のマイページが次の人に出る 1件 |
| 中 | 10 | 保存中に打った分が消える・動画のストーリーが止まる・同期がいいねやブロックを上書きする・通知の解除の競合 など |
| 低 | 24 | 取り消しの後に古い値が書かれる・二重送信・壊れたデータでだけ落ちる所 など |
| 誤報・問題なし | 多数 | 末尾にまとめた |

**アプリが落ちる（クラッシュする）もの:** ふつうに使って落ちると確かめられたものは **0件**。
残ったのは、壊れたデータや設定ミスのときに落ちうる「低」5件（C-1〜C-5）。

**本物の Xcode でだけ落ちる書き方:** **0件**。監査が CI の記録を見ていて、run 150（c46a445、
Xcode 26.3）は test と archive の両方が通っていた（この記録はこちらでは開いていない）。c46a445 から
HEAD までの差分は 8 ファイル・+65/-15 行で、その差分にも落ちる形は無かった。
事故と同じ系統の `catch … where` は4か所に残っているが、どれも catch の中に `await` が無い（X-1）。

**共通の原因（2つ）。直すならここから:**
1. **取り消しが「通信できません」に化ける。** `Core/Networking/APIClient.swift:131-135` の
   `catch { throw APIError.unreachable }` は、`URLError.cancelled` も `unreachable` に変える。
   `.task` は詳細から戻ると走り直し、すぐ次の詳細を開くと取り消される。そのとき受け手が
   「失敗」として一覧の枝を差し替え、開いたばかりの詳細が閉じる（H-5・H-6・M-9）。
   → APIClient で取り消しを `CancellationError` として投げ直す。受け手は書く前に `Task.isCancelled` を見る
2. **一覧を「描くたびに」絞るので、詳細の中で行った操作で元の行が消える。** ブロック・通報・
   「行きたい」を外す、のどれでも起きる（H-2・H-3・H-4・M-7）。Gallery・Favorites・
   「お気に入り」タブではもう直っている形（写しを取る、または `isOnScreen` と `needsReload` で遅らせる）を、ほかの画面にも入れる

---

## 高

### H-1 ハイライトの編集シートを開いていても時計が進み、編集シートごと戻される
- 場所: `Features/Stories/StoryViewerView.swift:104`（`let holds`）、`:126-139`（`frozen`）、`:292`（`.task(id: story.id) { await runClock(for: story) }`）、`:724-741`（`runClock`）、`Features/Profile/HighlightPlayerView.swift:31-33`（`holds: showEditor`）
- 再現: 自分のハイライトで写真のストーリーを開く → 「編集」でシートを開いてそのまま待つ → 最後の1本なら画面ごと戻る。途中の1本なら、裏で次の1本へ進む
- 筋: `runClock` は、始めた時点の View の写しを持ったまま回り続ける。`@State` は入れ物を指しているので、写しからでも今の値が読める。しかし `holds` はただの `let` なので、始めた時点の `false` のまま固まる。同じ理由で `scenePhase` を `@State isForeground` に写した注記（`:23-30`）があるが、`holds` にはそれが無い。`HighlightPlayerView:32` の「時間切れで画面ごと戻されない」は効いていない
- 確認: **コードで確認済み**。見え方は実機が要る
- 直し方: `holds` を `@State` に写す（`onChange(of: holds)` で更新）

### H-2 探す画面：詳細の中で通報・ブロックすると、見ている詳細が閉じる
- 場所: `Features/Search/SearchView.swift:64-72`（`onChange(of: hidden.revision)` に `isOnScreen` の確認が無い）、`:522-530`（人の結果を描くたびに `BlockFilter.users(model.users, blocked: hidden.blockedUserIds)` で絞る）
- 再現: 探す → 写真 → 「…」→ 通報（またはブロック）。人の場合は、探す → 人 → そのページでブロック
- 筋: `revision` が進む → `reloadPhotos` と `search` → 押した元の写真・人が一覧から消える → NavigationLink が消えて詳細が閉じる。ReportSheet も一緒に消えるので、ブロックに失敗したときの文言も見えない。`GalleryView.swift:95-111` には直した形がある
- 確認: **コードで確認済み**
- 直し方: GalleryView と同じ `isOnScreen` と `needsReload` の形にする。人の結果は写し（snapshot）で絞る

### H-3 写真の詳細：入れ子の詳細・コメントから開いたページ・スポットが閉じる
- 場所: `Features/PhotoDetail/PhotoDetailView.swift:140`（`onChange(of: hidden.revision) { refilterHidden() }`）、`:893-899`（`refilterHidden` が `nearby` と `spotLead` を絞り直す）、`:826`（コメントを描くたびに `BlockFilter.comments` で絞る）
- 再現:
  - 写真A → 「この近くで撮られた写真」の写真B → 通報またはブロック → B が閉じる
  - A → コメントした人 → そのページでブロック → そのページが閉じる
  - A → 撮影スポット → 中で通報して2枚を割る → `spotLead` が nil になり、スポットの画面が閉じる
- 確認: **コードで確認済み**
- 直し方: 絞り直しは戻ってきたとき（`onAppear`）まで遅らせる。コメントも写しで絞る

### H-4 マイページ「行きたい場所」：♥を外すと、開いているスポットの画面が閉じる
- 場所: `Features/Profile/MyPageView.swift:533`（`wanted = places.filter { wishlist.contains($0.slug) }`）、`:537`（`officialRows`）、`:559` / `:568`（その ForEach の NavigationLink）。押す側は `SpotDetailView.swift:179`、`OfficialSpotView.swift:191`
- 再現: マイページ → 行きたい場所 → スポット → ♥（行きたい）を外す
- 筋: 行を `wishlist` から描くたびに作っているので、外した瞬間に行が消えて閉じる。「お気に入り」タブは `savedIds` の写しで直してあるが、こちらには無い
- 確認: **コードで確認済み**
- 直し方: `@State wishIds` に写しを取り、`onAppear` とタブを切り替えたときだけ取り直す

### H-5 人のページ：戻ってすぐ次の写真（またはハイライト）を開くと閉じる
- 場所: `Features/Profile/UserProfileView.swift:77-79`（`.task(id: userId)`）、`:353-381`（`load`）、`:150-153`（`errorMessage` があると格子が ErrorBanner に替わる）、`:100`（`HighlightsRow` の `.id(highlightsKey(isFollowing:))`）
- 再現: 人のページ → 写真 → 戻る → 読み込みが終わる前（1秒以内）に別の写真かハイライトを押す
- 筋: 戻ると `.task` が走り直す。次の画面を開くと取り消され、`publicProfile` が `unreachable` を投げる（共通原因1）。`errorMessage` が入り、格子が ErrorBanner に替わって詳細が閉じる。取り消しが後の段で起きた場合は `isFollowing = ids?.contains(userId) ?? false`（`:381`）が `false` を書く。すると `HighlightsRow` の `.id` が変わって作り直され、開いたハイライトが閉じる
- 確認: 経路は**コードで確認済み**。戻ったときに `.task` が走り直すことと、押せる時間の長さは実機が要る
- 直し方: 各 await の後に `guard !Task.isCancelled else { return }`。取れなかった回は前の値を残す（`?? false` にしない）

### H-6 ホーム「フォロー中」：戻ってすぐ次の写真を開くと閉じる
- 場所: `Features/Gallery/GalleryView.swift:72-82`
- 再現: ホームで「フォロー中」を選ぶ → 写真 → 戻る → すぐ別の写真を押す
- 筋: `let ids = (try? await environment.social.myFollowingIds()) ?? []` が、取り消されると空の配列になる → `model.use(viewerId:following: [])` でフォロー中のフィードが0枚になる → 押したタイルが消えて詳細が閉じる。戻ると「まだありません」が出る
- 確認: **コードで確認済み**。`.task(id:)` が戻るたびに走り直すことは実機が要る
- 直し方: `guard let ids = try? await … else { return }` と `guard !Task.isCancelled`

### H-7 マイページ：前の人の読み込みが、次にログインした人の画面に書かれる（非公開の写真を含む）
- 場所: `Features/Profile/MyPageView.swift:872`（`guard !isLoading else { return }`）、`:102-105`（投稿を閉じたときの `Task`）、`:106-114`（`onAppear` の `Task`）、`:139-145`（`onChange(of: auth.userId)` → `forgetPhotos`）。`MyPageViewModel` はタブの根にある `@StateObject` で、ログアウトしても作り直されない
- 再現: 遅い回線で A がマイページを開くか、引き下げて更新する → 終わる前にログアウト → B でログイン
- 筋: `onAppear` や投稿を閉じたときの `Task` は `.task(id:)` の外で動くので、ログアウトしても取り消されない。B の `.task(id: B)` の `load()` は `isLoading == true` なので何もせずに戻る。その後 A の `myProfile` と `myPhotos`（下書きを含む）が戻ってきて書かれる。`forgetPhotos()` はもう済んでいるので、そのまま残る
- 確認: **コードで確認済み**。起きるかどうかはタイミング次第で、実機が要る
- 直し方: `load()` に「誰の分か」と世代番号を持たせ、await の後で照らす。`isLoading` で新しい読み込みを捨てず、前の Task を取り消して新しい方を走らせる。`forgetPhotos()` で世代を進める

---

## 中

### M-1 旅行プランの詳細：保存の返事を待つ間に打った分が黙って消える
- 場所: `Features/Trips/TripPlanDetailView.swift:63`（`onChange(of: plan) { resetIfNeeded() }`）、`:75-81`（`resetIfNeeded` が下書きを丸ごと戻す）、`:95`（保存の `Task`）。`TripPlansView.swift:262-276`（`write` → `plans = list`）
- 再現: 日程を直して「保存」→ 返事が来る前に、もう1か所足すか日付を変える → 返事が来ると、足した分が消える
- 筋: 保存中に止まるのは保存ボタンだけで、編集の欄は止まらない。返事で `plan` が変わると、下書きがサーバーの値に上書きされる
- 確認: **コードで確認済み**
- 直し方: 保存中は編集の欄を止める。または、送った差分と今の下書きが同じときだけ戻す

### M-2 動画のストーリーが、画面を離れて戻ると最後まで再生しても次へ進まない
- 場所: `Features/Stories/StoryMedia.swift:56-82`
- 再現: ハイライトなどで動画のストーリーを再生 → 別のタブへ行く（または `onDisappear` が来る操作をする）→ 戻る → 最後まで再生しても止まったまま
- 筋: `onDisappear` で鳴り終わりの見張り（`endObserver`）を外す。一方、`onAppear` は `player == nil` のときしか見張りを付け直さない。2回目以降は `player` があるので、見張りが無いまま再生される
- 確認: **コードで確認済み**。シートを閉じたときも `onDisappear` と `onAppear` が来るかは実機が要る
- 直し方: 見張りの登録を `if player == nil` の外に出し、`endObserver == nil` のときに付ける

### M-3 マイページ：投稿を閉じると裏で読み直し、開いている旅の一冊が閉じる
- 場所: `Features/Profile/MyPageView.swift:102-105`（`isOnScreen` の確認が無い）、`Core/Text/TripBook.swift:93`（`Trip.id` は写真の id をつないだもの）
- 再現: マイページ → 旅の記録 → 一冊を開く → 下の「投稿」から、その旅の期間の写真を投稿して閉じる
- 筋: 1枚増えると `Trip.id` が変わり、元の行が消えて閉じる。読み込みが失敗した回は ErrorBanner がタブ全体を差し替えるので、どこから開いた画面でも閉じる
- 確認: **コードで確認済み**
- 直し方: 画面に出ていなければ `needsReload` を立て、`onAppear` で読む

### M-4 次にログインした人のホームに、前の人のストーリーの輪が並ぶ（親しい友達限定を含む）
- 場所: `Features/Stories/StoriesRow.swift:63-66`（`userId` が nil のときは何も消さずに戻る）、`:293-303`（`StoriesViewModel.load`）
- 再現: A でストーリーの輪を読む → ログアウト → B でログイン → B の読み込みが返るまで、A の輪が並んで押せる
- 確認: **コードで確認済み**（どのくらいの間見えるかは回線次第）
- 直し方: `userId` が変わったら `stories = []` と `loadedFor = nil` にする。await の後で `viewerId` を照らす

### M-5 起動・ログイン直後の同期が、その間に押したいいね・保存・ブロックを上書きする
- 場所: `App/JourneyPhotoApp.swift:103-119`（`syncLikes` / `syncSaves` → `replace(with:)`）、`:165-171`（`hidden.replaceBlocked`）。`Core/Storage/FavoritesStore.swift:74-77`（`replace` は `ids` を丸ごと入れ替える）
- 再現: 起動した直後にホームのカードでいいね、またはブロックする。同期が押す前の一覧を返すと、ハートが消える。ブロックの場合は、ブロックした人の写真がまた見える（審査 1.2 に関わる）
- 確認: **コードで確認済み**。窓は起動直後の数秒
- 直し方: 同期を始めた後に手元で足した・外した ID を控えておき、合わせるときに残す。`replaceBlocked` は `revision` が変わっていたら捨てる

### M-6 通知をオフにしたのに、サーバーに宛先が残る／ログアウト後に前の人あての通知が届く
- 場所: `Core/Push/PushCenter.swift:141-142`（`enable`）、`:148-163`（`disable`）、`:166-173`（`accept` → 止める仕組みの無い `Task { registerIfPossible() }`）、`:182-186`、`:214-224`
- 筋: APNs のトークンが届くと、`accept` が設定画面の関所（`isApplying`）の外で登録を出す。その登録が飛んでいる間にオフにする。すると、サーバーで「解除 → 登録」の順に処理されることがあり、その場合は登録が残る。さらに `isRegistered = true` が後から書かれる。ログアウトと重なった場合も同じ形になる
- 確認: 経路はコードで追えた。起きるかどうかは実機が要る（APNs の返事のタイミング次第）
- 直し方: 登録と解除を1本の直列の Task か世代番号にまとめる。登録の返事の後で `isEnabled` と `userId` を照らし直す

### M-7 ストーリーの反応：見た人のページでブロックすると、そのページが閉じる
- 場所: `Features/Stories/StoryInsightsView.swift:171-174`（`shownViewers` を描くたびに blocked で絞る）
- 確認: **コードで確認済み**
- 直し方: 写しで絞る

### M-8 ストーリーを見ている最中に裏の送信が終わると、真っ黒で出られない画面になるか、別の1本へずれる
- 場所: `Features/Stories/StoriesRow.swift:68-70`（`uploads.finished` で読み直す）、`:98-102`（`fullScreenCover`）、`:275-280`（`viewer(for:)` が描くたびに束を作り直す）。`StoryViewerView.swift:100-112`（`_index = State(initialValue:)` は最初の1回しか効かない）
- 筋: 読み直しで束が変わっても、`@State index` は前の値のまま残る。開いた1本が消えていると `current` が nil になり、真っ黒な画面から出られなくなる。前の1本だけが消えた場合は、見ている1本が勝手にずれる
- 確認: **コードで確認済み**。起きる機会は稀
- 直し方: 開いた時点の束を `opened` と一緒に持つ。`opened != nil` の間は読み直さない

### M-9 取り消しが「通信できませんでした」として出る（共通原因1）
- 場所: `Core/Networking/APIClient.swift:131-135`。出る場所は `GalleryViewModel.swift:67-68`、`UserProfileView.swift:369-371`、`FollowListView.swift:197-198`、`AlbumsView.swift:236-237`、`CloseFriendsView.swift:268-270`、`HighlightEditorView.swift:185-187` など
- 筋: 読み込み中にタブを替えたり詳細を開いたりすると、赤い帯やエラーの状態が一瞬出る。H-5・H-6・L-2 の根っこでもある。`FavoritesView.swift:117` の `error is CancellationError` は、このせいで一度も当たらない（`Task.isCancelled` も見ているので実害は無い）
- 確認: **コードで確認済み**
- 直し方: APIClient で `URLError.cancelled` または `Task.isCancelled` のときは `CancellationError` を投げ直す

### M-10 地図：台帳スポットの札から開いた画面が、地図が動くと閉じる
- 場所: `Features/Map/PhotoMapView.swift:291-296`（`stillShown(official:)` が false なら札を描かない）、札の中の NavigationLink（`:860` 付近）、`PhotoMapViewModel.swift:168-172`
- 筋: OfficialSpotView を開いている間に、遅れて届いた現在地などで地図が動くと、札ごと NavigationLink が消えて閉じる
- 確認: **実機が要る**。上に画面を積んでいる間も `onMapCameraChange` が来るかは確かめていない
- 直し方: 上に積んでいる間は札を固定する

---

## 低

| # | 場所 | 中身 | 確認 | 直し方 |
|---|---|---|---|---|
| L-1 | `PhotoDetailViewModel.swift:65-118`、`PhotoDetailView.swift:141-147` | 開いた直後にいいねすると、先に出ていた `load()` の返事が `liked=false` と古い数で上書きする。フォローも `?? []` で「フォローしていない」に戻る | コード（タイミングは実機） | 世代番号を持ち、`toggleLike` の後なら書かない |
| L-2 | `UserProfileView.swift:374-381, 412-424` | 読み込み中にフォローを押すと、古い数と `isFollowing=false` で戻される | コード | L-1 と同じ |
| L-3 | `Services/PublicGalleryService.swift:52-57, 76-83` | actor が await の間に `setRestrictedLoader` を受け付ける。前の人の「フォロワーのみ」の写真が、60秒のあいだ次の人の一覧に混ざりうる | コード（起きにくい） | 世代番号で、await の後に照らす |
| L-4 | `Features/Settings/BlockedUsersView.swift:91-95, 109-118` | 引き下げて更新しながら解除すると、古い一覧が後から着き、その人がまた手元でブロック扱いになる | コード | 世代番号 |
| L-5 | `App/RootView.swift:66-72, 119, 123` | `refreshUnread` が3か所から同時に走り、古い数が後から着く。ログアウトした後に前の人の数が出ることがある | コード | 世代番号と、await の後で userId を照らす |
| L-6 | `Features/Albums/AlbumsView.swift:230-250`、`TripPlansView.swift:219-233` | 更新と作成が重なると、新しいアルバムが消えるか、**同じ id が2つ並ぶ**（ForEach の id が重なる） | コード | `insert` の前に同じ id が無いか見る。世代番号 |
| L-7 | `StoryViewerView.swift:263-289, 700-716` | 次の1本へ送った後に、前の1本の「見た人」・返事が書かれる。取り消しは失敗扱いになる | コード | 書く前に `guard !Task.isCancelled` |
| L-8 | `ProfileEditView.swift:134, 249-264`、`CloseFriendsView.swift:203, 274` | `.task` が走り直すと、まだ保存していない入力がサーバーの値で上書きされる | 実機が要る | `guard !loaded` |
| L-9 | `AuthStore.swift:230`（`run`）、`SignInView.swift:215, 221`、`ReportSheet.swift:122, 156` | 同じフレームで2回押すと2本走る。登録では未確認のアカウントが2つできうる。通報は2回送られうる | コード（押す速さは実機） | `run` の先頭で `guard !isWorking`。ボタン側も同期で閉じる |
| L-10 | `EditPhotoView.swift:144-218` | 差し替えの途中で撮影地を消して保存すると、差し替えの本体が後から座標を書き戻す | コード | 差し替え中は保存を止める |
| L-11 | `HomeMosaic.swift:249-272` | 連打を止める `pendingDelta` がカードの `@State` にある。LazyVStack がカードを作り直すと 0 に戻り、答えを待っている間に再び押せる | 実機が要る | 押している最中の印をカードの外（ストア）に持つ |
| L-12 | `TripPlanDetailView.swift:407` | 削除すると、親の一覧から行が消えて自動で戻り、そこへさらに `dismiss()` が重なる。2段戻る恐れ | 実機が要る | どちらか一方にする |
| L-13 | `Core/Text/EditorialLayout.swift:32-36`、`GalleryViewModel.load`、`TagPhotosView.load` | 行の id が隣の写真まで含む。遅れて書かれた一覧で並びが少し変わると行が作り直され、詳細が閉じることがある | 実機が要る | 書く前に `Task.isCancelled` を見る |
| L-14 | `Features/Albums/InviteView.swift:133-135` | 戻るたびに `isLoading=true` で丸ごと作り直す。スクロール位置が消える。失敗すると「使えません」と出る | コード | 読み込んだ後は再読込をしない |
| L-15 | `PhotoMapView.swift:83-92`、`PhotoMapViewModel.swift:133-137` | 戻るたびに地図を写真の範囲に寄せ直す。索引が取れなかった回は空で上書きする。前の `indexTask` を取り消していない | コード | `?? []` をやめる。取り消す |
| L-16 | `Features/Upload/SongPickerView.swift:98` | 曲選びを閉じると共有の再生器が止まり、他の画面の BGM まで止まる | コード | 自分が鳴らした曲のときだけ止める |
| L-17 | `StoryViewerView.runClock` | 止まっている間も1秒に20回起きて書き込む（電池だけの問題。漏れは無い） | コード | 止まっている間は待つ |
| C-1 | `Core/Text/PhotoPinning.swift:20` | `pinnedPhotoIds` に同じ id が2つあると、同じ写真が2枚並び、格子の ForEach の id が重なる（`MyPageView.swift:748`、`UserProfileView.swift:161`）。LazyVGrid では落ちる例がある | コード（重複が来るかはサーバー次第で確かめていない） | `Set` で重複を落とす |
| C-2 | `App/JourneyPhotoApp.swift:41-49`、`AuthStore.swift:83` | `AuthGateway.configure()` が失敗しても、起動を続けて `restore()` が Amplify を呼ぶ。Amplify は未初期化だと `preconditionFailure` で止まったはず | 確かめていない（Amplify のソースが手元に無い）。設定ミスのビルドでだけ起きる | `isConfigured` が false なら Amplify を呼ばずに `.signedOut` にする |
| C-3 | `Services/ImagePreparer.swift:170-180` | EXIF の露出・焦点距離が無限大のとき `Int(…)` で落ちる。見ているのは `> 0` だけ | 実機が要る（ImageIO が inf を返すかどうか）。通常の写真では起きない | `isFinite` を足す |
| C-4 | `Features/Upload/UploadView.swift:288` | `ForEach($model.items)` の行で、消した直後に古い添字へ書くと落ちる例が、古い SwiftUI で知られている | 実機が要る（iOS 17 以降では多くが直っている） | id から引き直す Binding にする |
| C-5 | `PhotoMapView.swift:1342`、`MyPhotosMap.swift:76`、`Models/Photo.swift:86` | 緯度・経度の範囲を確かめずに地図の範囲を作る | 実機が要る（SwiftUI の Map で落ちるかは確かめていない） | `abs(lat)<=90 && abs(lng)<=180` で絞る |
| X-1 | `Core/Auth/AuthStore.swift:151` ほか3か所（`TripPlanService.swift:51`、`APIClient.swift:131`、`CloseFriendsView.swift:297`） | 事故と同じ系統の `catch … where`。どれも catch の中に `await` は無く、run 150 で通っている | 通っている記録あり | 急がない。次に触るときに `switch` や `guard` の形に寄せる |
| X-2 | `MusicPreviewPlayer.swift:16-18, 195`、`AuthGateway.swift:19`、`AppConfig.swift:24` | Swift 6 の strict に上げたときに出そうな所（Sendable でない `static let shared`、書き換えられる static）。今は `minimal` なので出ない | 確かめていない | strict に上げるときに見る |

---

## 誤報・問題なしと判断したもの

- **`fatalError`**（`AppConfig.swift:48-68`）: 設定ミスで意図して止める作り。`verify.sh` が設定を見ている
- **`try!`**（`TravelDistance.swift:90`）は正規表現の定数。`TimeZone(identifier:"UTC")!` は必ずある。`PlaceLookup.swift:22` の `best!` は直前の `best == nil ||` で短絡する
- **`removeFirst()`**: `StoryUploadCenter.swift:118` は世代番号で守られている。`ProfileEditView:213` は `!isEmpty` で、Tag 系は `hasPrefix` の直後
- **添字**: `PhotoGroups.cover`、`IdTokenClaims`、`DominantColor`、`TripBook*`、`StoryViewerView`、`StoryComposerView`、`CloseFriendsView`、`TripPlanDetailView` などは、どれも範囲チェックか id での引き直しがある
- **`Dictionary(uniqueKeysWithValues:)`**: 0件。すべて `uniquingKeysWith` 付き
- **割り算・Int への変換**: 分母はすべて `> 0` か空で守られている。NearbyPhotos の `asin(min(1,…))` は NaN にならない
- **`id: \.self` の ForEach**（`PhotoDetailView.swift:1003` のタグ、`SpotDetailView.swift:145`）: Lazy ではないスタックなので、重なっても警告だけで落ちない
- **Xcode だけで落ちる書き方**:
  - catch の中の `await` は、どれも `where` の無い素の `catch`
  - `defer` の中や `if case` の条件に `await` を書いた所は無い
  - 150行を超える body は無い
  - `.onChange` はすべて iOS 17 の2引数の形
  - `AppDelegate` の `@Published`（`import Combine` が無い）は run 150 で通っている
- **メモリ**:
  - アプリのコードに Timer・CADisplayLink・KVO・Combine の sink・`addPeriodicTimeObserver` は無い
  - `MusicPreviewPlayer` の見張りは weak で、外している
  - `AuthStore` の見張りはアプリと同じ寿命で、weak self
  - `CurrentLocation` は1回取るだけ
  - 画像は上限のある URLCache を使う
- **競合**:
  - 対処済み: `SearchViewModel`・`NotificationsViewModel`・`UploadViewModel`・`StoryUploadCenter`（世代番号や関所がある）、いいね・保存・フォローの連打（`isLiking` などがある）
  - GalleryView で、古い一覧（ブロックした人を含む）が後から着く件は、描くときにもう一度落とすので出ない
  - `@MainActor` の付け忘れ: ObservableObject はすべて付いている。例外の `MusicPreviewPlayer` は main からしか触らない
- **画面が閉じる**:
  - Gallery の `hidden.revision` は `isOnScreen` で守られている
  - Favorites・SavedPhotos・MyPage「お気に入り」は写しで絞っている
  - NotificationsView は `navigationDestination(item:)` で、行とは切り離して値を持っている
  - HighlightPlayerView の `.id(items)` は、編集後にわざと作り直している
  - ログイン状態の枝が切り替わるのは起動時だけ
- **参考（このブランチでは見ていない）**: run 151（`claude/ios-bugfix-1`）は、コンパイルは通ってテストの段で落ちていた（監査による）
