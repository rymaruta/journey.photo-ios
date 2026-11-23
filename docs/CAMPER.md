# 写真で作るキャンピングカー「とおまわり号」（消した）

2026-11-23 に iOS から消した（札 #709）。

owner の決定（2026-11-23）: 「消したい理由は、操作めんどいのと部品多いのと、私自身あんまり使ってない。
家具置いたりするのめんどいし、少し本格的にしすぎてしまった」。そのぶん旅のトランクに力を入れる。

## 戻すには

消す前の全部（画面・立体・家具・試験・この頁の前の中身）は、枝 `archive/camper`（1d8dbfc251b0）にある。
戻すときはその枝から `Sources/JourneyPhoto/Features/Camper`、`Sources/JourneyPhoto/Core/Camper`、
`Models/Camper.swift`、`Services/CamperService.swift`、`Tests/JourneyPhotoTests/Camper*.swift` と入口の結びを持ってくる。

## 残したもの

- 端末に残った控えを退会で消す所（`LeftoverCamperData`・`Core/Storage/AccountLocalData.swift`）。前の版で使った人の
  飾り・部屋の家具の配置などを、鍵の名前だけで消す
- ほかの機能が使っていた3つは、中立な名前で引っ越した: 撮影地の文字から県を読む `PrefectureText`（前の
  `CamperCounting.prefecture(in:)`）、CPU とメモリを読む `ProcessUsage`（前の `CamperRenderMeter`）、
  SceneKit の場面の中身を数える `SceneStats`（前の `CamperSceneStats`）

## サーバー（photo-gallery）と DB

触っていない。API（`/user/camper`・`/users/{uid}/camper…`）と、投稿の応答の `camper.added` はサーバーに残っている。
アプリは `camper.added` を読まずに捨てる（害は無い）。API を外すのは、古い TestFlight の版が期限切れ（90日）に
なってから（案の頁「トランクを見やすく」の推奨）。DB の項目は消さない（消すと DB の変更になり、承認が要る）。
