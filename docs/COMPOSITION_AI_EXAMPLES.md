# AI構図作例の登録手順

構図の詳細画面は画像アセット `composition-ai-<CompositionKind.rawValue>` を検索する。存在すれば写真の上に `CompositionOverlay` を重ね、ラベルを「AI生成の構図作例」にする。存在しない場合は従来の図を表示する。

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

## 2026-10-13 アセット制作状況

- 37個の `.imageset` と `Contents.json` を含む**レビュー専用のZIP**を制作済み（チャットの成果物として保管、GitHubには未アップロード）。
- 元画像は一枚のAIコラージュから切り出した約209×130pxのサムネイルであり、600×800pxキャンバスに配置しても高解像度にはならない。
- 構図の種類と素材は仮対応であり、構図線との一致を保証しない。複数の構図に同じ写真が割り当てられている。
- **本番アプリへの登録・マージは禁止**。各構図ごとの高解像度画像に差し替え、ガイド線との一致を検証すること。
- 現在のGitHubコネクタはUTF-8テキストの書き込みのみをサポートするため、画像バイナリをこのPRへ直接アップロードできない。
