# 構図の作例写真を作る・入れる

構図の解説（設定 → 構図一覧 → 各構図）と、撮る画面の構図のシートの札に出す作例写真。
全37種類（`CompositionKind`）。**AI で作った写真なので、画面には必ず「AI で作ったイメージ」と出す**
（`CompositionAIExample`・試験 `CompositionAIPromptTests` が見張る）。

登録の決まり（1枚ずつ別に作る・variant 0・縦 3:4 の線に乗るか目で見る・引き伸ばさない）は
`docs/COMPOSITION_AI_EXAMPLES.md`。確かめた記録は `docs/composition-ai-review.json`（台帳）。

| ファイル | 役目 |
|---|---|
| `prompts.json` | 構図ごとの指示（英語）。線の座標・置き場所・場面3つ（日本と海外を混ぜる）・全部に共通の決まり |
| `generate.mjs` | Gemini API で候補を作り `out/<kind>/<n>.png` に保存（`out/` はコミットしない） |
| `install.mjs` | 選んだ1枚を 3:4 に切って 864×1152 の JPEG にし、絵の入れ物と台帳に入れる |

## 使う API（2026-10-14 に公式の文書で確かめた）

- **Imagen は使えない。** https://ai.google.dev/gemini-api/docs/imagen は「Imagen models are shut down.
  Use Nano Banana for image generation.」。
- 代わりに **Nano Banana**（Gemini の画像モデル）。既定は `gemini-nano-banana-2.1`（`--model` で
  `gemini-3-pro-image` などに替えられる）。
- `POST https://generativelanguage.googleapis.com/v1beta/interactions`・見出し `x-goog-api-key`・
  body `{ model, input, response_format: { type: "image", mime_type, aspect_ratio: "3:4", image_size: "2K" } }`
  （出典: https://ai.google.dev/gemini-api/docs/image-generation の curl の例）
- 返事の画像は `steps[]`（`type: "model_output"`）の `content[]`（`type: "image"`）の `data`（base64）。
  **生の JSON の形は文書に無く、SDK の例からの推測。** 初回は1枚だけ（`--kind thirds --only 1`）流して確かめる。
- seed は文書に無いので送らない。候補3枚の違いは場面を3つ書き分けて作る。作り直しは `--retake 1`（言い回しを足す）。
- 生成した画像には全て SynthID の透かし（目に見えない）が入る（文書の記載）。
- 料金（https://ai.google.dev/gemini-api/docs/pricing ・2026-10-14）: `gemini-nano-banana-2.1` の 2K は
  1枚 約 $0.0504（出力の画像のぶん。考える部分のトークンは別に掛かる）。37種類×3枚＝111枚で約 $5.6＋α。
  `gemini-3-pro-image` は 1K/2K で 1枚 約 $0.134（111枚で約 $14.9＋α）。

## 手順

1. **新しいセッションで鍵を入れる。** 環境の秘密に `GEMINI_API_KEY` を置く（値をチャット・ファイル・
   コミットに書かない。道具も表示しない）。
2. 送る中身を見る（鍵は要らない）:
   ```
   node Tools/composition-examples/generate.mjs --dry-run --kind thirds
   ```
3. まず1枚で返事の形を確かめる → 全部:
   ```
   node Tools/composition-examples/generate.mjs --kind thirds --only 1
   node Tools/composition-examples/generate.mjs              # 37×3。あるものは飛ばす（--force で作り直す）
   ```
   1件ごとに 6 秒空け、429・500・503 は待って（`Retry-After` があればそれに従って）5 回までやり直す。
4. **目で見て選ぶ。** `out/<kind>/1.png`〜`3.png` を、アプリと同じ線（variant 0・縦 3:4・
   `CompositionGuide.screenMarks`）を重ねて見る。主題が線・点に乗っているか、顔が主役になっていないか、
   文字・透かし・実在の名所・商標が無いか、加工しすぎていないか。乗らなければ入れない
   （台帳の `held` に理由を書く。既に `held` の4つ——三角・黄金螺旋・3×3＋対角・ダイナミックシンメトリー——は
   `prompts.json` の `pitfall` に前の失敗を書いてある）。
5. 入れる:
   ```
   node Tools/composition-examples/install.mjs --kind triangle --pick 2 --note "3本の木の中心が三角の頂点に乗る"
   ```
   真ん中で 3:4 に切り、864×1152・JPEG（画質 82 から下げて 1枚 250 KB 以下）にして
   `Sources/JourneyPhoto/Assets.xcassets/composition-ai-<kind>.imageset/` に置き、台帳の `accepted` に載せる
   （`held` から外す）。切った後が 864×1152 に届かなければ止める（引き伸ばさない）。
   画像の道具は ImageMagick か Mac の `sips`。
6. 検査: `bash Tools/verify.sh`（`CompositionAIExampleTests` が台帳と絵を、`CompositionAIPromptTests` が
   指示文と AI の表記を見る）。37種類そろったら、全部を目で確かめた上で `CompositionAIExampleTests` の
   「37 未満」の見張りを外す。
7. **Mac で確かめる**（`/mac-check`）: 画面写真「13j2-構図のシート（AI の作例つき）」と
   「84-構図の解説（三分割）」で、写真・線・「AI」の印・「AI で作ったイメージ」を見る。

## 大きさ

いまの33枚は合わせて約 11 MB（1枚 300〜570 KB）。`install.mjs --recompress-all` は、入っている作例を
**同じ寸法のまま**画質を下げて 1枚 250 KB 以下にする（手元の試しで 10.9 MB → 5.7 MB）。見た目の確認をしてから使う。
試験は合計 15 MB を上限にしている。
