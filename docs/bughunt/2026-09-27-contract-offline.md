# バグ探し 2026-09-27: サーバーとの約束・圏外・データの形・見える範囲・時刻

**探しただけで、直していない。** 画面ごとに直しているセッションへの振り分け用。

- アプリ: `claude/ios-bughunt-contract`（`499ca9b` 時点）
- サーバー: `rymaruta/photo-gallery` develop `a35f269`（clone した直後の最新）。
  経路の登録は `api-user/serverless.yml`（`index.ts` には upload の2本しか無い）
- 確かめ方: 4本の監査の指摘を、**本書の筆者がアプリ側・サーバー側の該当行を読み直して**筋を確かめた。
  「コードで確認済み」＝両側の該当行を読んで再現の筋が通ることを確かめた。
  **実機・Xcode では1件も確かめていない**（この環境ではコンパイルできない）
- 行番号は `Sources/JourneyPhoto/` からの相対（アプリ）と `api-user/src/` からの相対（サーバー）

## 一覧（重い順）

| # | 重さ | 要旨 | 確かめ方 |
|---|---|---|---|
| 1 | 高 | ログアウト → 別の人でログインしても、検索タブに前の人あての「フォロワーのみ／親しい友達」の写真が残る | コード |
| 2 | 中 | サーバーが本文つきで返す 403（上限・返信不可など）が全部「権限がありません…お問い合わせください」にすり替わる | コード |
| 3 | 中 | 写真編集の撮影日が `photo.date` ではなく EXIF から入り、保存のたびに送られる（巻き戻り・1980年 EXIF で保存不能・消せない） | コード |
| 4 | 中 | ストーリーの `allowReplies: false` を読まず、返信欄と ♡ を出す（送ると 403 → #2 の文言） | コード |
| 5 | 中 | 写真の投稿・ストーリーの「もう一度送る」で二重投稿になる（応答だけ落ちた回） | コード（応答落ちは実機） |
| 6 | 中 | ログインの期限切れ・圏外でのログアウトのあと、端末に前の人あての通知が届き続ける | コード（到達は実機） |
| 7 | 中 | ホームの「フォロー中」: フォロー一覧の取得失敗が「フォロー中の人の写真はまだありません」になる | コード |
| 8 | 中 | 人の検索: 通信失敗が「見つかりませんでした」になる | コード |
| 9 | 中 | ハイライト編集: 中身の読み込みだけ失敗すると空の選択で開き、保存で既存の並びを上書きする | コード（部分失敗は実機） |
| 10 | 中 | ホーム・地図でメニューからログアウトしても、前の人あての限定写真が残る | コード＋実機要 |
| 11 | 低 | 写真の差し替えで EXIF が1990年前／未来だと 400 で差し替え不能 | コード |
| 12 | 低 | 本文に `saved: true` / `liked: true` を載せた 404、解除済みの 404 を失敗として巻き戻す | コード |
| 13 | 低 | 写真の削除・コメントの削除が 404（既に無い）だと画面に残ったままエラー | コード |
| 14 | 低 | 退会した人の公開プロフィールは 200 `{userId}` で来るのに、アプリは 404 を待っている | コード |
| 15 | 低 | ハイライト編集がサーバーの断り文（400/403/404）を全部捨てる | コード |
| 16 | 低 | 写真編集で題・説明を毎回送り、`{ja,en}` の題・説明が ja の平文になり英語が消える | コード |
| 17 | 低 | 「フォローバック」の判定と親しい友達の候補が、先頭50人しか入らない一覧で決まる | コード |
| 18 | 低 | マイページ／人のページ: 読み直しや操作の失敗で写真の格子ごとエラーに置き換わる | コード |
| 19 | 低 | 失敗を 0 件／空で出す小さい所（ストーリーの反応・ハイライト一覧・タグ一覧・未読の印）と再試行の出口が無い画面 | コード |
| 20 | 低 | フォローの失敗を黙って捨てる所（写真詳細・お知らせのフォローバック） | コード |
| 21 | 低 | 取り消された通信（`URLError.cancelled`）を「通信できません」と出す | コード＋実機要 |
| 22 | 低 | ID トークンの取得失敗が `APIError` に包まれない（圏外で更新できない回の文言・ログアウト扱い） | 実機要 |
| 23 | 低 | 今日のテーマが端末の暦（和暦・仏暦など）で変わる | コード |
| 24 | 低 | アプリが送る `exif.dateTimeOriginal`（`yyyy:MM:dd HH:mm:ss`）を Web が読めない | コード |
| 25 | 低 | `/user/photos`・`/feed/restricted` を `[Photo]` で厳しく読み、1行壊れると一覧ごと落ちる | コード（壊れた行は未発見） |
| 26 | 低 | EXIF の日時を端末のタイムゾーンで読むので、夏時間の切り替わりの時刻が落ちうる | 実機要 |
| 27 | 低・サーバー | `restrictedFeed` がブロックの読み取りに失敗すると何も隠さず、ブロックした相手に「親しい友達」の写真が漏れうる | コード |

---

## 1.【高】ログアウトしても検索タブに前の人の限定公開写真が残る

- **アプリ**:
  - `Features/Search/SearchView.swift:57` の `.task { await model.loadPhotos(environment:) }` だけで読み込んでいる
  - `:709` は `guard allPhotos.isEmpty else { return }` なので、一度読んだら二度と読まない
  - 読み直しの合図は `hidden.revision`（`:64`）と引き下げ更新だけ。`auth.userId` を見ていない
  - `App/JourneyPhotoApp.swift:124` はログイン状態にかかわらず `RootView` を出したままにする。そのため `SearchView` の `@StateObject`（`:14`）が生き残る
  - `ModerationStore.use(userId:)`（`Core/Storage/ModerationStore.swift:48-58`）は、ブロック・通報の集合が変わったときだけ `revision` を進める（`bumpIfChanged`）。前の人も次の人も0件なら進まない
- **サーバー**: 限定写真は `restrictedFeed.ts` がその人にだけ返す。アプリは `PublicGalleryService.merged`（`:215-219`）で公開一覧に混ぜている。ログアウト時の `setRestrictedLoader(nil)`（`JourneyPhotoApp.swift:88-92`）はサービス側の控えしか捨てない
- **再現**:
  1. A でログインする（A がフォローしている人に `audience: followers` の写真がある）
  2. 検索タブを一度開く
  3. 設定からログアウトし、B でログインする（A も B もブロック・通報が0件）
  4. 検索タブの発見・タグ・検索結果に、A あての限定写真が出たままになる。引き下げるまで消えない
- **直し方の案**: `SearchView` に `.task(id: auth.userId)` を足し、`reloadPhotos(force: true)` を呼ぶ。または `ModerationStore.use` で人が替わったら必ず `revision` を進める（後者は他の画面にも効く）

## 2.【中】本文つきの 403 が「権限がありません…お問い合わせください」にすり替わる

- **アプリ**: `Core/Networking/APIError.swift:37-40` は 403 なら `message` を捨てて固定の文を返す。包み直しているのは `TripPlanService.refusing`（`:51`）だけ
- **サーバー**（すべて本文 `{error}` つきの 403）:
  - 写真の上限: `photoLimit.ts:40-45`「アップロード上限（N枚）に達しています」。`upload.ts:62`（presign）と `:291`（save）から呼ぶので、**上限の人は差し替えもできない**。`storyKeep.ts:110` の「写真として残す」も同じ
  - `albums.ts:150`（アルバムの個数）、`:479`（アルバムの人数）
  - `highlights.ts:299,319`（ハイライト20個）
  - `block.ts:114`（ブロック上限）
  - `storyReplies.ts:208-209`「この投稿は返信を受け付けていません」
- **再現**: 写真1000枚の人が投稿する／51個目のアルバムを作る／21個目のハイライトを作る。どれも「権限がありません…お問い合わせください（ログインし直しても直りません）」と出て、上限だとは伝わらない
- **直し方の案**: `APIError.errorDescription` で「403 で `message` が空でなければ本文を出す。空のとき（API Gateway が門前払いした 403）だけ今の文」にする

## 3.【中】写真編集の撮影日が EXIF から入り、保存のたびに送られる

- **アプリ**:
  - 初期値: `Features/Profile/EditPhotoView.swift:42`
    `_date = State(initialValue: photo.exif?.dateTimeOriginal.flatMap(Self.isoDay) ?? "")`。`Photo.date`（`Models/Photo.swift:68`）を見ていない
  - 保存: `:209-210` で `patch.date = day.isEmpty ? nil : day` を毎回送る
  - `isoDay`（`:222-231`）は `yyyy:MM:dd HH:mm:ss` しか読めない
- **サーバー**:
  - `photoUpdate.ts:171-173`: 1990年より前・未来の日付なら 400
  - `:375`: `applyMeta("date", ...)`
  - `sanitize.ts:195-198` の `dateWasRejected` は空文字を通し、`applyMeta` が REMOVE する
- **再現**:
  - A（黙って巻き戻る）: アプリで投稿した写真の撮影日を Web で 2024-10-12 に直す → アプリで題だけ直して保存すると、EXIF の 2024-10-11 に戻る
  - B（保存できない）: EXIF が `1980:01:01 00:00:00`（時計が未設定のカメラ）の写真は、投稿は通る（`sanitizeDate` が黙って落とす）。編集画面は「1980-01-01」が入った状態で開くので、**何を直して保存しても 400** になる
  - C（空で出る）: 実データで `date` を持つ8枚（例: `edb09f51` `2024-10-12`、`a5951859` `2024-10-11`）は EXIF の日付を持たないので、欄が空で出る
  - D（消せない）: 欄を空にすると `nil` になり、送らないので消えない。`:209` のコメント「空文字を送ると日付検査に落ちる」は誤り
- **直し方の案**: 初期値は `photo.date` の頭10文字、無ければ EXIF（2つの書き方を両方読む）にする。開いたときから変わった回だけ送り、空にされた回は `""` を送って消す

## 4.【中】ストーリーの「返信を許可しない」を読まない

- **サーバー**:
  - `stories.ts:377,457` が `allowReplies: false` を保存する（Web の投稿画面が送る）
  - `getStories`（`:173-181`）は他人向けの応答から `replyCount`・`keptAs`・`archive` を消すが、`allowReplies` は残す
  - `storyReplies.ts:208-209` は false なら 403 で断る
- **アプリ**: `Services/StoryService.swift:141` の `Story` に `allowReplies` が無い（リポジトリ全体に1箇所も出てこない）。`Features/Stories/StoryViewerView.swift:1074` 周辺は、自分以外のストーリーなら必ず返信欄・一言の候補・♡ を出す
- **再現**: Web で「返信を許可」を切って投稿する → フォロワーが iOS で ♡ か返信を送る → 403 → #2 の誤った文言が出る
- **直し方の案**: `Story` に `allowReplies: Bool?` を足し、`== false` のときは返信欄・候補・♡ を隠す（Web の `StoryViewer.tsx:283` と同じ判定）

## 5.【中】投稿の送り直しで二重投稿になる

- **アプリ**:
  - `Services/UploadService.swift:137-148` の `upload()` は、呼ばれるたびに presign からやり直し、新しい key をもらう。save が失敗したら `discard(key:)` する
  - 投稿画面（`Features/Upload/UploadViewModel.swift:287-345`）で失敗した1枚を「投稿」で押し直すと、新しい key で保存し直す
  - ストーリーは `Core/Storage/StoryUploadCenter.swift:85-89` の `retry()` から送り直す
- **サーバー**:
  - `upload.ts:326-338`: 写真 ID は key から作る（`idFromUploadKey`）。同じ key の再送なら1枚で済むが、key が変わると別の写真になる。コメントに「押し直すと2枚目の行ができる」と書いてあるとおりのことが、アプリでは起きる
  - 使用中の key の discard は 409（`upload.ts:606-607`）なので、1枚目は壊れない
  - ストーリーは `stories.ts:437` で `story-${randomUUID()}` を採番するので、key にかかわらずもう1本できる
- **再現**: 回線が不安定な所で投稿する → サーバーは保存したが応答が落ちる（または 5xx）→ 押し直す → 同じ写真が2枚になる（ストーリーは2本）
- **確かめ方**: 流れはコードで確認済み。「応答だけ落ちる」状況は実機か通信を細工した環境が要る
- **直し方の案**: 失敗した1枚ごとに presign の応答と「PUT が済んだか」を控え、送り直しでは同じ key で save だけを送る。ストーリーはサーバー側の冪等キーが要る（アプリだけでは直らない）

## 6.【中】前の人あての通知が届き続ける

- **アプリ**:
  - `Core/Auth/AuthStore.swift:49-54` の `expireSession()` は、`push.signingOut()` を呼ばずに `signOut()` する（ふつうのログアウトは `SettingsView.swift:266`・`SiteMenuView.swift:96` で呼んでいる）
  - `Core/Push/PushCenter.swift:82-85` の「前の人の宛先を外す」は、その時点で前の人の ID トークンが無いので通らない。失敗は `try?` で握りつぶす
  - 圏外でのログアウトも `signingOut()`（`:182-186`）が `try?` で失敗し、外し直しの印（`pendingUnregisterKey`）を残さない
- **サーバー**: `devices.ts` の `unregisterDevice` は JWT の `sub` の集合からしか消さない。前の持ち主を外すのは `registerDevice` の `releasePreviousOwner` だけ（`devices.ts:20-35` のコメントにこの穴が書いてある）
- **再現**: A が通知オンのまま、期限切れ（または圏外でログアウト）で抜ける → B が同じ端末で通知オフのままログインする → A あての「◯◯さんがいいねしました」が届き続ける
- **直し方の案**: 手元に `token` があり、前の人の外しに失敗した（またはできなかった）ときは、次にログインした人で `POST /user/devices` → `DELETE /user/devices` を一度流す。前の持ち主が外れる

## 7.【中】ホームの「フォロー中」: 取得失敗が「まだありません」になる

- **アプリ**: `Features/Gallery/GalleryView.swift:78` の `let ids = (try? await environment.social.myFollowingIds()) ?? []` から `model.use(following: [])` に渡し、`:387` の「フォロー中の人の写真はまだありません」を出す。札を押したとき（`:334-337`）は「空で潰さない」guard があるが、`.task` の方には無い。引き下げ更新でもフォロー一覧は取り直さない
- **再現**: ログイン済みで機内モードにして起動 →「フォロー中」を押す → 「フォロー中の人の写真はまだありません」と出る
- **直し方の案**: 取れなかったことを状態として持ち、「読み込めませんでした」と再試行を出す。引き下げ更新でもフォロー一覧を取り直す

## 8.【中】人の検索: 通信失敗が「見つかりませんでした」になる

- **アプリ**: `Features/Search/SearchView.swift:774` の `let found = (try? await fetchUsers(trimmed)) ?? []` から `:561` の「見つかりませんでした」になる
- **再現**: 機内モード → 探す → 種類を「人」にする → 名前を打つ
- **直し方の案**: 失敗を別の状態にして「読み込めませんでした（引き下げで再試行）」と出す

## 9.【中】ハイライト編集: 中身の読み込み失敗で既存の並びを消しうる

- **アプリ**: `Features/Profile/HighlightEditorView.swift:193-208`。`contents = try? await ...contents(...)` が nil なら `picked` は `[]` のままで、知らせも出ない（`loadFailed` はアーカイブの失敗にしか立たない）
- **サーバー**: `highlights.ts:353` の `SET ... storyIds = :ids` は丸ごと置き換える
- **再現**: 遅い回線でハイライトの編集を開く → アーカイブは取れ、contents がタイムアウトする → 何も選ばれていない画面になる → 1件選んで保存すると、元の並びが消える
- **直し方の案**: 編集で contents が取れなかったら保存を押せなくし、知らせと再試行を出す

## 10.【中】ホーム・地図でもログアウト後に限定写真が残る（#1 の兄弟）

- **アプリ**:
  - `GalleryView.swift:72-82` の `.task(id: auth.userId)` は `model.use(viewerId:following:)` と `loadMyPhotos` を呼ぶだけで、`load()` を呼ばない。`GalleryViewModel.use`（`:120-133`）は手元の `all` を絞り直すだけなので、限定写真が残る
  - 地図（`PhotoMapView` の `.task`）も、画面が出たときにしか読み直さない
- **再現**: ホームを見ながら見出しのメニュー（`SiteMenuView.swift:93-97`）でログアウトする。シートを閉じると同じホームに戻り、限定写真が残る。タブを切り替えれば消える
- **確かめ方**: コードの筋は確認済み。シートを閉じたときに `.task` が走り直さないかどうかは実機で確かめる必要がある
- **直し方の案**: `auth.userId` が変わったら `model.load(force: true)` を呼ぶ。#1 と一緒に直す

## 11.【低】写真の差し替えで EXIF が1990年前／未来だと 400

- **アプリ**:
  - `Services/PhotoService.swift:88` が `date: prepared.takenOn` を送る
  - `readTakenOn`（`Services/ImagePreparer.swift` の `:68` から呼ぶ）は年を確かめない。確かめたのは呼んでいる行だけで、関数の中身は読んでいない
- **サーバー**: `photoUpdate.ts:279-281` は「撮影日は1990年以降の日付にしてください」で 400 を返す。投稿（`upload.ts:319` の `sanitizeDate`）は黙って落とすので通り、振る舞いがそろっていない
- **再現**: 時計が未設定のカメラの写真（`1980:01:01`）を差し替えに選ぶ。利用者には手の打ちようがない
- **直し方の案**: 端末側で範囲外の `takenOn` を nil にしてから送る

## 12.【低】「一部成功」の 404 を失敗として巻き戻す

- **サーバー**:
  - `saves.ts:184-197`: 見えなくなった写真では 404 `{error, saved: true}` を返す
  - `likes.ts:243-247`: 404 `{..., liked: true}` を返す
  - `likes.ts:376-381`: 解除はマーカーと数を消した**あと**に 404 を返す
- **アプリ**:
  - `APIClient.errorMessage`（`Core/Networking/APIClient.swift:137-145`）は `error` しか拾わない
  - `PhotoDetailView.swift:941-950`（保存）と `PhotoDetailViewModel.swift:106-116`（いいね）は、どの 404 でも押す前に戻す
- **再現**: いいね済みか保存済みの写真が非公開になる → 手元の控えから解除を押す → サーバーでは外れたのに、画面は付いたままエラーになる（何度押しても同じ）
- **直し方の案**:
  - 解除（DELETE）の 404 は「外れた」として扱う
  - 付ける側は、`APIError.server` に本文を持たせて `saved` / `liked` を読む

## 13.【低】既に無いものの削除（404）で画面に残る

- 写真: `PhotoDetailView.swift:958-966` は 404 もエラーとして扱い、`dismiss()` しない（サーバーは `photoUpdate.ts:756-778` で 404「写真が見つかりません」）
- コメント: `PhotoDetailViewModel.swift:141-147` は成功したときだけ一覧から外す（サーバーは `comments.ts:428-430` で 404）
- **再現**: 別の端末や投稿者が先に消したものを削除する
- **直し方の案**: DELETE の 404 は「もう無い」として成功と同じに扱う

## 14.【低】退会した人のプロフィールを 404 で待っている

- **サーバー**: `userProfile.ts:1053-1054`: 墓石（退会済み）でも 200 `{ userId }` を返す。404 を返すのは ID に `#` があるときだけ
- **アプリ**:
  - `Features/Profile/UserProfileView.swift:362-365` の「退会した可能性があります」は、この経路では出ない
  - `Features/Social/CloseFriendsView.swift:297` の `.deleted` も同じ
- **再現**: 退会した人を開くと「名前未設定」の人として描かれる
- **直し方の案**: 「`{userId}` だけ」の応答を「見つからない」として扱うか、サーバーに印を返してもらう。サーバーは「未設定の人と同じ見え方」を意図しているので、**どちらにするか owner の判断が要る**

## 15.【低】ハイライト編集がサーバーの断り文を捨てる

- **アプリ**: `HighlightEditorView.swift:225-228` は、どんな失敗でも「保存できませんでした。もう一度お試しください。」を出す
- **サーバー**: `highlights.ts:234-273,299` は、選択が空・アーカイブに無い・表紙が並びに無い（400）、見つからない（404）、20個上限（403）を、それぞれ本文つきで返す
- **直し方の案**: `errorDescription` を出す（403 は #2 と一緒に直す）

## 16.【低】写真編集で題・説明を毎回送り、英語が消える

- **アプリ**:
  - `EditPhotoView.swift:190-191` で `patch.title = title` / `patch.description = caption` を毎回送る
  - 初期値は ja だけ（`:37-38`）
- **サーバー**: `photoUpdate.ts:368-369` は文字列のまま保存する
- **再現**: `title: {ja,en}` の写真で公開範囲だけ直して保存すると、en が消え、静的サイトの作り直しも1回走る。元に戻せない
- **直し方の案**: 変わった項目だけ送る（Web の /user/edit と同じ）

## 17.【低】先頭50人しか入らない一覧で「フォロー中か」を決める

- **アプリ**:
  - `Features/Notifications/NotificationsView.swift:429-432` は `social.following(userId:)` の `users` で判定する
  - `CloseFriendsView.swift:263` の候補も同じ一覧
- **サーバー**: `follow.ts:611,713` で `users` は最大50人（新しい順）。上限は2000人
- **再現**: 51人以上フォローしている人に、古くからフォローしている相手からフォローされた通知が来ると、「フォローバック」が出る。押しても冪等なので害は見た目だけ。親しい友達には、51人目より古い相手を**新しく選べない**
- **直し方の案**: `myFollowingIds()`（`GET /user/following`、ID を最大2000件）に替える（`FollowListView.swift:208` は既にこちらを使っている）

## 18.【低】操作や読み直しの失敗で写真の格子ごと消える

- **マイページ**: `Features/Profile/MyPageView.swift:106-114` は `onAppear` のたびに `load()` を呼ぶ。`:912-914` で失敗すると、`:729-730` の ErrorBanner がタブ全体を覆う（端末だけで出せる「行きたい場所」「お気に入り」のタブまで）
- **人のページ**: `UserProfileView.swift:412-424` で、フォローやブロックの失敗が読み込み用の `errorMessage` に入り、`:145-148` で写真の欄ごと置き換わる
- **再現**: 一度読んだあと機内モードにし、写真を開いて戻る（マイページ）か、「フォローする」を押す（人のページ）
- **直し方の案**: 手元に写真があるなら、読み直しや操作の失敗は一覧に添えて出す（`actionMessage` と同じ考え方）

## 19.【低】失敗を 0 件／空で出す所、再試行の出口が無い所

- `Features/Stories/StoryInsightsView.swift:251`: `replies = (try? ...) ?? []` のため、返信だけ失敗すると「返信 0」と出る。引き下げ更新で前の値も消える
- `Features/Profile/HighlightPlayerView.swift:146-150`: 失敗すると「まだハイライトがありません。」になり、`.refreshable` も無い。`:40-44,83-90` の「開けませんでした」にもボタンが無い
- `Features/Gallery/TagPhotosView.swift:30`: `?? []` で「該当する写真がありません。」になる。ただし公開一覧の控えがあれば代わりが出るので、起きるのは控えが無いときだけ
- `App/RootView.swift:71`: `unread = (try? ...) ?? 0` のため、圏外で戻るとベルの印が消える
- `Features/Albums/InviteView.swift:135-144`、`PhotoDetailView.swift:806-811`（コメント）: 失敗の表示はあるが、再試行する手段が無い

## 20.【低】フォローの失敗を黙って捨てる

- `PhotoDetailView.swift:486-497` の `toggleFollow` と、`NotificationsView.swift:438` のフォローバックが `try?` になっている。圏外で押しても何も起きず、知らせも出ない
- `PhotoDetailView.swift:146` と `UserProfileView.swift:380-381` は、フォロー一覧が取れないとフォロー中の相手に「フォロー」と出す。押してもサーバーは状態を返すので、害は見た目だけ

## 21.【低・実機要】取り消された通信を「通信できません」と出す

- **アプリ**: `Core/Networking/APIClient.swift:129-135` の `catch { throw APIError.unreachable }` は、`URLError.cancelled` も「通信できない」に変える
  - 取り消しを弾いている: `TripPlansView`・`NotificationsView`・`FavoritesView`
  - 弾いていない: `MyPageViewModel`・`AlbumsViewModel`・`FollowListView`・`BlockedUsersView`・`UserProfileViewModel`・`StoryInsightsView`
- **起きうること**: `.refreshable` の途中で描画し直すと取り消される、という SwiftUI の挙動に当たると、引き下げ更新のあとに「通信できません」が残る。この挙動は実機で確かめていない
- **直し方の案**: `.cancelled` は `CancellationError` として投げ直し、画面側でまとめて無視する

## 22.【低・実機要】ID トークンの取得失敗が `APIError` に包まれない

- **アプリ**:
  - `APIClient.swift:121` の `try await tokenProvider.idToken()` は do/catch の外にある
  - `Core/Auth/AuthGateway.swift:73` は `notAuthorized` 以外のエラー（圏外で ID トークンを更新できない回など）を Amplify のエラーのまま投げる
  - `GalleryViewModel.swift:68` のように `as? APIError` で読む画面では、汎用の文言になる
- **もっと重いかもしれない点**: `AuthStore.swift:292` は `.sessionExpired` も `.notAuthorized` として扱う。圏外で更新に失敗したときに Amplify 2.x が `.sessionExpired` を返すなら、**圏外なだけでログアウトさせる**ことになる。どちらを返すかは確かめていない
- **実機での確かめ方**: ログインから1時間以上たってから、機内モードで起動し、写真を開く
- **直し方の案**: `idToken()` の Amplify エラーのうち、通信によるものは `APIError.unreachable` に変える

## 23.【低】今日のテーマが端末の暦で変わる

- **アプリ**: `Core/Text/DailyTheme.swift:50-51` の `ordinality(of: .day, in: .era)` は `Calendar.current` を使う。和暦では令和の初日から、タイ仏暦では仏暦の紀元から数えるので、西暦の端末と違うテーマになる。コメントにある「全員が同じ日に同じテーマ」が崩れる
- **似た所**: `DiscoverySections.swift`（季節）と `TextOverlay.swift`（日付のステッカー）の月・日。こちらは和暦・仏暦なら無害で、ずれるのはイスラム暦・ヘブライ暦などのとき
- **直し方の案**: `Calendar(identifier: .gregorian)` に端末のタイムゾーンを入れて使う

## 24.【低】アプリの EXIF 日時を Web が読めない

- **アプリ**: `Services/ImagePreparer.swift:181` は EXIF の生の文字列（`2026:09:13 08:21:05`）をそのまま送る
- **サーバー**: `sanitize.ts:53` はそのまま通す
- **Web**: `lib/utils/photoDate.ts:27` の正規表現 `^(\d{4})-(\d{2})-(\d{2})` に合わないので、アプリから投稿した写真は Web の撮影情報に時刻が出ない
- **直し方の案**: 送る前に `YYYY-MM-DDTHH:mm:ss` に直す（Web の `exifWallClock` と同じ形）

## 25.【低】API の写真一覧を厳しく読む

- **アプリ**:
  - `Services/PhotoService.swift:14,23`（`/user/photos`・`/feed/restricted`）は `[Photo].self` で読む。1行でも型が違えば一覧ごと落ちる
  - 限定写真は `PublicGalleryService.restrictedPhotos` が `catch` して `[]` を返すので、**黙って全部消える**
- **いまの状況**: 書き込みの経路は sanitize で形をそろえているので、壊れた行はいまは見つかっていない
- **直し方の案**: 公開一覧と同じ `LenientPhotoList` で読む

## 26.【低・実機要】EXIF の日時を端末のタイムゾーンで読む

- **アプリ**: `ImagePreparer.swift:210-217` と `EditPhotoView.swift:223-230`。en_US_POSIX とグレゴリオ暦で固定しているので、和暦や12時間表示では壊れない。ただしタイムゾーンは端末のまま
- **起きうること**: 夏時間の切り替わりで実在しない時刻（米国の 2026-03-08 02:30 など）は `date(from:)` が nil を返し、撮影日が付かない可能性がある
- **直し方の案**: 読むときも書くときも UTC にする

## 27.【低・サーバー】ブロックの読み取りに失敗すると「親しい友達」の写真が漏れうる

- **サーバー**:
  - `restrictedFeed.ts:65` の `hiddenUserIds(userId).catch(() => new Set())` は、失敗したら何も隠さない
  - `block.ts` はブロックのときにフォローを両向きに外すが、「親しい友達」からは外さない
  - `isVisiblePhoto` の closeFriends の判定はフォローを見ない
- **起きうること**: DynamoDB の一時的な失敗で、ブロックした相手に `closeFriends` の写真が返る。アプリは「自分をブロックした人」を知らないので、手元では落とせない
- **直し方の案**: 失敗したら 500 を返して閉じる側に倒す。または、ブロックのときに「親しい友達」からも外す（photo-gallery 側の修正）

---

## 誤報・問題なしと判断したもの

- **経路とメソッド**: アプリが呼ぶ口は、すべて `serverless.yml` に登録があり、メソッドも認証の有無も合っている
- **写真の部分更新で「消す」の表し方**: `""`・`[]`・`audience: ""`・`coords: null`（`clearCoords`）は、どれもサーバーと合っている
- **差し替え・presign・アイコン・旅行プラン・ユーザー検索・端末の登録・退会**: キー・形・状態コードが合っている
- **通知の種類**: `notify.ts:21` の4種とアプリの `Kind` が一致する。知らない種類でも一覧は落ちない。APNs の中身もアプリは読まずにお知らせを開くだけなので、食い違わない
- **フォロー・いいね**: 冪等に 200 を返す（409 は出ない）。アプリ側に連打止めもある
- **ストーリーの期限切れ**: サーバーは 404 を返す（410 ではない）。アプリも 410 を前提にしていない
- **photos.json（30行）**:
  - 全行が今の `Photo` で読める。行ごとに緩く読んでいるので、1行で全体が落ちることもない
  - `title` は28行が `{ja,en}`、2行が文字列（`edb09f51`・`a5951859`）で、どちらも読める
  - `exif.iso` は全行が整数。`date` は8行にあり、すべて `YYYY-MM-DD`。`createdAt` はすべて Z 付きの ISO
- **公開一覧の控え**: 圏外・壊れた応答（キャプティブポータルの HTML など）・空の応答では、良い控えを上書きしない（`PublicGalleryService.swift:167-205`）
- **タイムアウト**: API は20秒、退会だけ個別に延ばしている。アップロードの PUT は無通信120秒で、流れていれば切れない
- **読み込み中のまま戻らない状態**: 見つからなかった（どれも `defer` で戻している）
- **ページ送り**: アプリに無いので、「失敗を一覧の終わりと扱う」型の不具合は無い
- **ブロック**: 公開一覧は端末側で落としている。控えを使う経路も `visible` を通る
- **旅行プランの日付**: グレゴリオ暦・UTC・en_US_POSIX に固定している
- **人が替わったときの控え**: マイページ・ストーリーの列・お気に入り・保存・下書きは、人ごとに分けているか捨てている（検索・ホームは #1・#10）
- **パスの二重エンコード**: ID はどれも UUID か英数字なので、実害は無い
- **CLAUDE.md の注意（古い photo-gallery）**: 今回は develop の最新を clone して突き合わせたので、`/user/devices` と APNs は「在る」と扱った
