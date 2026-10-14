# AI構図作例の登録手順

構図の詳細画面は画像アセット `composition-ai-<CompositionKind.rawValue>` を検索する。存在すれば写真の上に `CompositionOverlay` を重ね、ラベルを「AI生成の構図作例」にする（実写真の構図は「構図の作例写真」・下の節）。存在しない場合は従来の図を表示する。

## 画像の条件

- 1構図につき独立した、縦3:4比率の写真風画像。ガイド線・文字・ロゴ・透かしを画像に焼き込まない。
- 被写体や消失点の位置は `CompositionGuide.screenMarks(kind, variant: 0, aspect: 0.75, quarterTurns: 0, levelDegrees: 0)` の線に合うよう設計・確認する。
- 構図の説明に適した被写体を選ぶ（`CompositionExample.scene(for:)` を参照）。
- 個々の画像は `Sources/JourneyPhoto/Assets.xcassets/composition-ai-<rawValue>.imageset/` に置き、`Contents.json` に画像ファイル名を指定する。
- アプリへの組み込み前に、全37種類の画像について構図の一致・視認性・AI表記を目視確認する。
- 未登録の画像を完成済みと数えない。

## リリース判定

- PRの静的検査・iOS Xcodeビルド・テストを通す。
- 全37種類の画像登録と目視検証が終わるまで「37種類のAI作例対応」と宣伝しない。
- マージ後、GitHub Actionsの TestFlight ワークフローを `submit=true` で実行し、署名・アップロード・App Store Connect上のビルドを確認する。

## 登録の方針（2026-10-13）

37種類は **1枚ずつ、別の写真として作り、variant 0・縦3:4のガイド線に乗るか見てから** `composition-ai-<rawValue>.imageset` へ置く。

- 一覧画像やコラージュからの切り抜きでは済ませない。
- 低解像度の仮素材を引き伸ばして本番に入れない。短い辺 800px 未満は試験が落とす。
- 原寸は引き伸ばさない。いまの個別生成は 864×1152 のまま置く（画面の作例は幅 270pt まで）。
- 線に乗らなかった枚は台帳の `held` に理由を書き、絵の入れ物には置かない。
- 未登録の構図は、これまでどおり配置図のまま出す。37種類そろったとは数えない。

確認の記録は `docs/composition-ai-review.json`。絵の入れ物と台帳の食い違いは `CompositionAIExampleTests` が落とす。

## 実写真の作例（2026-10-14 owner）

AI の絵が構図を文字どおりの形で描いていて写真の作例になっていなかった12種類（tunnel・zShape・rootRectangle・armature・diagonal45・mizige・tianzige・obliqueThirds・squareGrid・ratio4x5・ratio9x16・ratio16x9）は、**無料で商用に使え、クレジット表記の要らない実写真**に替えた。

- 使える許諾: CC0・パブリックドメイン・Unsplash License・Pexels License。CC BY など表記の要るものは使わない。出典のページで許諾を確かめ、確かめられないものは使わない。
- 生成画像・透かし・文字入りは使わない。人物は後ろ姿や小さな人影まで。
- 出典・作者・許諾・確かめた日・切り抜きは `Tools/composition-examples/photo-sources.json`。台帳では `source: "photo"`。
- アプリの札は `CompositionExample.photoKinds` の構図だけ「構図の作例写真」。台帳・出典の記録・`photoKinds` の食い違いは `CompositionAIExampleTests` が落とす。
