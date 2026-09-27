# 作業記録 2026-09-27: 開いている画面が勝手に閉じる系の直し

- 入力: `docs/bughunt/2026-09-27-crash-concurrency.md`（`claude/ios-bughunt-crash`・監査の土台は 499ca9b）
- 担当: H-1〜H-6・M-3・M-7・M-10 と、低のうち同じ型（L-12・L-13 を検討）
- 触らない: H-7・M-4・M-6・M-9（別の所で直している）
- 土台: このブランチ `claude/ios-bugs-dismiss`（682e751）。監査の後に 26 コミット入っているので、**1件ずつ今のコードで筋を追い直してから**直した
- 実機・本物の Xcode では何も動かしていない。画面が閉じるかどうかそのものは Linux で試せないので、
  絞り込みを値（`ModerationSnapshot` など）やモデルに出してテストした

## 既にある直し方（使い回したもの）

`NavigationLink` の元の行が一覧から消えると、開いている画面が閉じる。一覧の絞り込みは描くたびに
今の集合で行わず、**表示中は固定した写し**（`ModerationStore.snapshot` → `ModerationSnapshot`）で行い、
`onAppear`（と、画面に出ている間の変化）で取り直す。読み直しが要る画面は `isOnScreen` と
`needsReload` で戻ってくるまで遅らせる。形は `GalleryView`・`UserProfileView`・`MyPageView` の
`savedIds` と同じにした（新しい仕組みは作っていない）。

## 1件ずつ

### H-1 ハイライトの編集シートを開いていても時計が進む — 直した（コミット2）

### H-2 探す: 詳細の中で通報・ブロックすると閉じる — 直した（コミット1）
- 今のコードで確認: `SearchView` の `onChange(of: hidden.revision)` は画面の状態を見ずに読み直し、
  人の結果は描くたびに `hidden.blockedUserIds` で絞っていた。監査のとおり
- 直し: `GalleryView` と同じ `isOnScreen`・`needsReload`・`dropped` の形。上に積んでいる間は印だけ
  付け、戻ったとき（`onAppear`）に読み直す。人の結果は `dropped.users` で絞る
- 残したこと: 戻った直後、読み直しが終わるまでの一瞬はブロックした人の写真が結果に残る
  （写真の結果は `allPhotos` から多くの段を作っていて、描くときに落とす口が無い。公開一覧は
  60秒の控えがあるので読み直しはすぐ返る）。画面の作りを変えないため、ここは広げなかった

### H-3 写真の詳細: 入れ子の詳細・コメントから開いたページ・スポットが閉じる — 一部は既に直っていた。残りを直した（コミット1）
- 既に直っていた: 「この近くで撮られた写真」（`nearby`）とスポットの行き先（`spotLead`）は
  3df1359 で `isOnScreen`・`needsRefilter` の形になっていた
- 残っていた: コメントを描くたびに `BlockFilter.comments(…, blocked: hidden.blockedUserIds)` で絞っていた。
  コメントした人のページでブロックすると元の行が消えてそのページが閉じる
- 直し: `@State dropped` を持ち、`onAppear` と画面に出ている間の変化で取り直す。コメントは `dropped.comments`

### H-4 マイページ「行きたい場所」: ♥を外すと開いているスポットが閉じる — 直した（コミット1）
- 今のコードで確認: 行を `wishlist.contains` / `wishlist.spotIds` から描くたびに作っていた。監査のとおり
- 直し: `@State wishIds` に写しを取り、`onAppear` と、画面に出ている間の `wishlist.spotIds` の変化で
  取り直す（マイページの中で外す操作・人の切り替えは画面に出ている間なので、従来どおりすぐ消える）

### H-5 人のページ: 戻ってすぐ次を開くと閉じる — 一部は既に直っていた。残りを直した（コミット2）

### H-6 ホーム「フォロー中」: 戻ってすぐ次を開くと閉じる — 既に直っていた（記録だけ）
- 4c0779a・b247b88 で `use(viewerId:fetchedFollowing:)` になり、取れなかった回（取り消しを含む）は
  `nil` として前のフォロー一覧を残す（`GalleryViewModel.swift:223-226`）。空の配列で上書きしない

### M-3 マイページ: 投稿を閉じると裏で読み直し、開いている旅の一冊が閉じる — 直した（コミット1）
- 今のコードで確認: `onChange(of: tabRouter.postSheetsClosed)` が `isOnScreen` を見ずに `load` していた
- 直し: 画面に出ている間だけ読む。出ていない回は、戻ってきたときの `onAppear` の読み直し
  （2度目以降は毎回読む作り）が拾うので、`needsReload` は足していない

### M-7 ストーリーの反応: 見た人のページでブロックすると閉じる — 直した（コミット1）
- 今のコードで確認: `shownViewers` が描くたびに `hidden.blockedUserIds` で絞っていた
- 直し: `UserProfileView` と同じく `onAppear` で写しを取り、`dropped.viewers` で絞る

### M-10 地図: 台帳スポットの札から開いた画面が、地図が動くと閉じる — 直した（コミット2）

### L-12・L-13 — 後で書く

## テスト

- コミット1: `BlockFilterTests.testSnapshotKeepsPeopleUntilRetaken`（人・コメント・見た人を写しで落とす口）。
  修正前のソースに戻すと `ModerationSnapshot.users` が無くてコンパイルで落ちることを確かめた。
  **画面が閉じない（`isOnScreen` で遅らせる）こと自体は Linux では試せない**。H-4・M-3 は
  画面の状態だけの直しで、純関数に出せる部分が無いのでテストを足していない

## 検査の記録

- コミット1の1回目の `verify.sh` で、テストの実行体が1回だけ SIGSEGV で止まった。落ちた所は
  テスト基盤の `StubProtocol.startLoading()` の遅延応答（`APIClientTests.swift:238`、
  `DispatchQueue.global().asyncAfter` で後から届ける分）で、今回の差分は触れていない。
  続けて `swift test` を3回、`verify.sh` を1回流して再現せず（973件通過・rc=0）。
  遅れて届いた応答が、試験の後片付けの済んだ URLSession に当たったものとみている（確かめていない）
