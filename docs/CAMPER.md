# 写真で作るキャンピングカー（札 #307）

板: 「写真で作るキャンピングカー」（Artifact U6zRLR5swQgXTnvzsLc9uF）。部品の一覧は「部品図鑑」（CamperDex）が正。

## 第1段（2026-10-18・この枝）— サーバーと DB は変えない

- 立体: `Core/Camper/CamperBlueprint*.swift` が閉じた立体の部品の並びを作り、`Features/Camper/CamperScene.swift` が
  SceneKit（physicallyBased・clearCoat・SCNFloor の映り込み・太陽の落ち影）に写す。iOS 標準だけ。
- 段: 旅の一冊の数（`TripBook.shelfTrips`）で決める。3 冊でキャンピングカー、10 冊でトレーラーつき。
- 部品: 図鑑の 33 分類・132 個（id は「分類.部品」）。端末で数えられる条件の 98 個だけが届く。
  要サーバーの 33 個と、キャンプ場の焚き火（キャンプ場がまだ無い）は「近日」と出して数（分母）から外す。
- 飾り（付けた部品・オーニング）は人ごとにこの端末へ覚える（`CamperStore`・退会で消す）。

## 第2段（作らない・設計メモ）

### 写真からステッカーと積み荷を作る

- 被写体の切り抜きは iOS 17 の Vision `VNGenerateForegroundInstanceMaskRequest`（標準・無料）。
  景色の写真は丸いステッカー（縁は `sticker_edge.*` の形）、物の写真は切り絵の積み荷（表は絵・裏は紙の 2 枚の板）。
- **人の写った写真は使わない**: `VNDetectHumanRectanglesRequest` で人を見つけたら切り抜かない（入手の数にも数えない）。
- 貼り場所は車体の横の空き枠（板 CamperDecorate の点線）と予備タイヤのカバー。積み荷は屋根の荷台。
- 貼った物は投稿の写真 id で持つ（画像そのものを車の控えに入れない）。

### 飾りをサーバーへ・友達の車を訪ねる

- 口の案: `GET /user/camper`・`PUT /user/camper`（`{ paint, picks: { "<分類>": "<部品>" }, awningOpen, stickers: [...] }`）、
  `GET /users/{id}/camper`（友達の車）、`POST /users/{id}/camper/lantern`（扉の横にランタンを掛ける・1 人 1 つ）。
- 端末の控え（`camper.loadout.<userId>`）は、口ができたら最初の 1 回だけ送って消す。

### 要サーバーの部品（33）の入手の案

- 旅の投稿の数（`wheel.brass_spoke` など 10 個）: サーバーの投稿の束の数で判定。
- 友達（`mirror.brass_oval`・`rug.kilim`・`awning.rust_stripe`・`sticker_edge.signed` など）: 贈る・訪ねる・同じ日の旅・焚き火に薪。
- スポットの種類（水辺・港・自転車道・森・焼き物の町）: 撮影スポットの種類の索引と撮影地の突き合わせ。
- 行事の暦（`window_shape.arched`・`sticker_edge.holo` など）・天気（雨の日・風の強い日）: サーバーの暦と過去の天気。
- 同じ写真で一度に届くのは 3 個まで（届いた画面が続きすぎない）。

## 確かめていないこと

- 本物の Xcode でのビルドと見た目（Linux では SceneKit の模型 `Shims/SceneKitShim` に向けて型検査しただけ）。
- 材質の値は板の艶からの換算。Mac の画面写真で合わせる。
- 山・海辺・湖・植物・街は撮影地と題・タグの言葉で、森・晴れは写真の代表色で、満月は日付から数える。精度は試していない。
