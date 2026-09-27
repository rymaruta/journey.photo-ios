# 作業記録 2026-09-27: F1・G2 の統合（`claude/ios-integrate-f1-g2`）

- 起点: `532523c`（`claude/design-current-state-comparison-q8w0zp`。A・B・C・D・E・G1 を併合済み）
- 併合した枝（この順に1本ずつ）:
  1. `origin/claude/ios-bugs-races`（G2: H1 監査 M-1・M-2・M-5・M-8 と低）`0a90c76` まで
  2. `origin/claude/ios-bugs-contract-auth`（F1: 契約監査 #1 #2 #6 #10 #21 #22 #25）`ba3a1e5` まで
- **併合しなかった枝:** `origin/claude/ios-bugs-contract-errors`（F2）。着手時（05:30 UTC）に
  終わっていなかった——担当の #7〜#23 のうち **#11・#18・#23 が作業記録に一度も出てこない**、
  最後のコミット `38417df`（05:02）のレビューの結果が未記録、作業記録は「以下、コミットごとに
  追記する」で終わっている。終わってから別に併合する
- 検査: 併合ごとに `PHOTO_GALLERY=<photo-gallery の develop> bash Tools/verify.sh` が rc=0
  （突き合わせ NG 0件）。photo-gallery は `593b67e`（develop）。
  **実機・Xcode では1件も確かめていない**（`swift build` は `Shims/` の模型に向けたもの）
- 併合ごとに subagent のレビューを1本かけ、指摘は自分で確かめてから直した

## 1. G2（races）の併合 `fe9f24a`

| ファイル | 本線（C） | G2 | 解き方 |
|---|---|---|---|
| FavoritesStore / SavedPhotosStore / ModerationStore | `replace(with:for:)`: 取りに行った人と違えば書かない | `replace(with:since:)`: 印の後に押した分は残す（`LocalEdits`） | 1つにまとめた: `replace(with:for:since:)`・`replaceBlocked(with:for:since:)`。持ち主の照合は必須、印は任意 |
| JourneyPhotoApp | 取り消し・いまのログインとの照合、確認中は通知の宛先に触らない | 最初の await の前に印を取る | 両方 |
| RootView `refreshUnread` | `unreadGeneration`（最後に始めた1本・取れなかった回は前の数を残す） | `unreadRuns` | 本線が G2 を包含するので本線。説明だけ取り込んだ |

- SyncRaceTests は新しい引数に合わせて `for:` を足した。「別の人」の2本は `for:` に**いまの人**を渡し、
  印の照合だけで弾かれることを見る形にした（G2 の仕組みそのものを試し続けるため）

### レビューで見つけた意味の衝突 → `f0c4564`

G2 の「印の後に押した分は残す」が、C の「前の人のいいね・ブロックを次の人の控えに書かない」をすり抜けていた。

1. A がいいね・保存・ブロックを押し、答えを待っている
2. ログアウトして B がログイン（`use(b)`・B の同期の印）
3. A の答えが届き `favorites.set` / `savedPhotos.set` / `hidden.block` が B の控えに書く。
   `LocalEdits` はそれを「B の印より後に押した分」と記録する
4. B の同期が返っても、その分は残る（本線だけなら同期の入れ替えで消えていた）

直し方: 各控えに `owner` と持ち主つきの書き込み（`set(_:favorite:for:)`・`set(_:saved:for:)`・
`block(_:for:)`・`unblock(_:for:)`）を足し、**答えを待った後に書く所**（ホームのカード・写真詳細3か所と保存・
人のページ・ストーリー・通報シート・ブロックした人・`blockAndHide`）は待つ前に持ち主を取って渡す。
試験 `SyncRaceTests.testLateAnswerForThePreviousPersonIsNotKeptBySync` は、照合を外すと3つとも落ちる。

直していないもの（本線からある・G2 とは無関係）:
- 退会の直後（控えを消してから `use(nil)` までの間）に同じ人の答えが届くと、消した鍵へ書き戻す
  （持ち主が同じなので照合を通る）
- 通報（`markReported`）は答えの後に持ち主を照らさず書く
- `BlockedUsersView` の読み込みは印（`since:`）を渡していない（一覧を読んでいる間に別の画面で
  ブロックした分が入れ替えで消える。重なりはまれ）

## 2. F1（contract-auth）の併合 `3d123cc`

### PushCenter（#6: ログアウト後に前の人あての通知が届く）

C と F1 が同じ問題を別の設計で直していた。両方のコミット文と試験を読み、場面ごとに並べた:

| 場面 | C（本線） | F1 | 併合後 |
|---|---|---|---|
| A の登録が残ったまま**誰もログインしない**（期限切れ・圏外） | 端末ごと APNs から外す | 何もしない（次の人を待つ）——**その間 A あての通知が届く** | C: すぐ端末ごと外す。サーバーの持ち主は残す |
| その後 **B がログイン（受け取らない）** | 端末ごと外す（サーバーは 410 まで A の集合に残す） | B で POST（引き取り）→ DELETE | F1: サーバーからも外す |
| B がログイン（受け取る） | 印を残し B の登録で上書き。落ちたら端末ごと外す | B で POST（引き取り）。DELETE しない | 両方 |
| 持ち主を書く前の版から上げた端末 | 対象外 | 次にログインした人で一度引き取る | F1 |
| ふつうのログアウト | 自分の印だけ消す | 自分の持ち主だけ消す | 両方の印から自分だけ消す |
| 登録の通信中に人が替わる | 遅れた失敗で次の人の宛先を外さない | 遅れた失敗を次の人の画面に出さない | 両方 |

**どちらか片方を丸ごと選ぶと、片方の場面が抜ける**（C だけならサーバーに A の宛先が 410 まで残り、
旧版の端末を拾えない。F1 だけなら誰もログインしない間 A あての通知が届き続ける）。
そこで**意味の違う印を2つ**持つ形にした:

- `registeredOwner`（C の鍵）: いま届く形で預けてある人。端末ごと外したら消す
- `owner`／`owner-known`（F1 の鍵）: サーバーの集合にトークンが入っている人。端末ごと外しても残し、
  次にログインした人の POST で引き取る

登録・引き取りの成功で両方をその人に（`noteRegistered`）、その人の認証で外せたら両方からその人だけ消す
（`noteUnregistered`）。`use` の待ちの後の「次の `use` が始まっていたら任せる」は、引き取りの後にも入れた。

試験: 両方の枝の試験がそのまま通る（下の型名の件を除く）。足した
`PushTakeoverTests.testNobodyThenNextUserReleasesBothOnDeviceAndOnServer` は、C だけの形
（端末ごと外すときにサーバーの持ち主も消す）・F1 だけの形（誰もログインしない回に外さない）の
どちらに戻しても落ちることを確かめた。

### そのほかの衝突

| ファイル | 解き方 |
|---|---|
| JourneyPhotoApp | 本線の `.task(id: auth.state)` を2つとも残し、F1 の「限定写真の口は `hidden.use` より先に差し替える」を本体の task の頭に移した（F1 は `.task(id: auth.userId)` だった） |
| PublicGalleryService | 本線の `restrictedEpoch`（替わったら読み直す・回を返す）が F1 の `restrictedGeneration`（空で返す）を包含するので本線 |
| SearchView | 本線の `restrictedChanges` と `isOnScreen`/`needsReload` が F1 の `userRevision` による読み直しを包含するので本線 |
| PhotoMapView | 本線に人の入れ替わりの仕組みが無いので F1 を足し、`isOnScreen` の宣言を1つにまとめた |
| MyPageView | 本線の世代番号・`async let` の上に、F1 の「取り消しを失敗と言わない」catch を足した |
| AlbumsView | 本線の世代番号の上に F1 の catch を足し、取り消しでも（自分の回なら）読み込み中を下ろす |
| AuthGateway | 本線の `isConfigured` の守りと F1 の `tokenFailure` を両方 |

### 自動で混ざった所の意味の衝突

1. **試験の型 `PushReleaseTests` が両方の枝に在った**（C は `AccountLocalDataTests.swift`、F1 は
   `PushTests.swift`）。F1 の方を `PushTakeoverTests` に改名した。C の試験の端末は「持ち主の分かっている
   端末」（`owner-known`）にした——分からない端末ではログインした人で引き取りの POST が走り、C の試験の
   割り込み（トークンを求められた瞬間に人を替える）が `use` の中で起きて前提が崩れる
2. **人のページの初回の取り消し**: F1 は APIClient の取り消しを `CancellationError` で上げるように変え、
   さらに `UserProfileViewModel.load` に「取り消しは常に黙る」catch を足した。本線の「まだ何も出して
   いない初回が取り消されたら失敗を書く」（`keepsShown`、`316625c`）を素通りし、
   `ViewModelTests.testProfileFirstLoadCancelledShowsFailure` が落ちた。その catch も `keepsShown` に従わせた
