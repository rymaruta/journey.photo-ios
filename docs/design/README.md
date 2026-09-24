# Journey Photo iOS デザインの入口

**現在の採用案: [v1 — 写真から、次の旅へ。](v1/README.md)**（2026-09-25）

次のUI実装では、まず v1 の画像と仕様を参照してください。画像だけを模写せず、操作・データ・空状態・実装順序も合わせて読みます。

1. [全画面の一覧と比較ボード](v1/README.md)
2. [画面仕様・画面間の移動・受け入れ条件](v1/SPEC.md)
3. [photo-gallery から採用する機能と根拠](v1/WEB_FEATURES.md)
4. [実装順序と既存コードの対応](v1/IMPLEMENTATION.md)
5. [色・文字・余白の値](v1/tokens.json)

この資料は将来の実装の基準です。SwiftUIへの反映済みを意味しません。既存の `docs/MOCK_PARITY.md` は過去の実装状況の資料であり、このv1との差分は `IMPLEMENTATION.md` から着手します。

更新は `v2/` のように版を追加し、ここから現在版を指します。CIが上書きする `screenshots` ブランチに設計の正本を置かないでください。
