# journey.photo-ios

[journey.photo](https://journey-photo.com) の iOS アプリ版。SwiftUI のネイティブアプリです。
旅の写真を見る・撮る・投稿する・つながる、までを iPhone で行います。

- 対応 OS: iOS 17 以上
- 言語: 日本語と英語（端末の言語に従う）
- Web 版: [`rymaruta/journey.photo-web`](https://github.com/rymaruta/journey.photo-web)
  （Web とサーバー側のコード。このリポジトリは iOS アプリだけ）

アプリは Web 版のサーバーの API を使います。契約は API、見た目は追う、SEO は追わない、
という考え方で Web 版に合わせています（`docs/WEB_SYNC.md`）。

## 手元（Linux・Mac）で確かめる

```bash
bash Tools/verify.sh
```

構文・参照・Web 版の API との突き合わせ・設定ファイルの検査に加えて、
Swift が入っていれば `Shims/` の模型に向けてビルドと単体テストまで流れます。
NG が 0 件なら正常です。

- 「Web 版との突き合わせ」は、隣のディレクトリの Web 版の作業ツリーを読みます。
  古い枝のままだと誤った結果になるので、最新の main にそろえるか、
  `PHOTO_GALLERY=<Web 版のパス>` で場所を渡してください
- `Shims/` は **Linux で型検査するためだけの模型**で、実機のビルドには入りません。
  本物の SwiftUI での確認（見た目・レイアウト・実行時の挙動）は Linux ではできません
- 道具の入れ方: `Tools/install-swift-linux.sh`（Swift）・`Tools/install-xcodegen-linux.sh`（XcodeGen）

## Mac の CI で確かめる

本物の Xcode でのビルド・テストは GitHub Actions の macOS ランナーで行います。

- **PR の検証** … `.github/workflows/ios-pr.yml`。静的な検査・Linux の単体テスト・
  Xcode のビルドとシミュレータのテスト。テストの件数は CI の結果で確かめてください
- **TestFlight** … `.github/workflows/ios-testflight.yml`（手動実行）。
  表に出る版は自動で上がります。手順は [`docs/RELEASE.md`](docs/RELEASE.md)・
  [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md)・[`docs/GITHUB_ACTIONS.md`](docs/GITHUB_ACTIONS.md)
- Mac を持っていなくても TestFlight まで出せます（[`docs/NO_MAC.md`](docs/NO_MAC.md)）。
  自分の iPhone だけで試すなら [`docs/DEVICE_TEST.md`](docs/DEVICE_TEST.md)

## 手元の Xcode で動かす

```bash
brew install xcodegen
xcodegen generate
open JourneyPhoto.xcodeproj
```

- Debug ビルドは staging 向け、Release ビルドは本番向け（`Config/*.xcconfig`）
- `.xcodeproj` はコミットしません。定義は `project.yml` と `Config/` だけです
- 依存は Swift Package Manager の
  [Amplify Swift](https://github.com/aws-amplify/amplify-swift)（ログイン周り）

## ディレクトリ構成

| 場所 | 中身 |
|---|---|
| `Sources/JourneyPhoto/App/` | アプリの入口・環境・ルート画面 |
| `Sources/JourneyPhoto/Features/` | 画面ごとの機能（ギャラリー・写真詳細・地図・投稿・ストーリー・アルバム・プロフィール など） |
| `Sources/JourneyPhoto/Core/` | 認証・通信・保存・デザイン部品・文言など、画面をまたぐ土台 |
| `Sources/JourneyPhoto/Services/` | API とのやり取り・画像の加工などの処理 |
| `Sources/JourneyPhoto/Models/` | データの型 |
| `Tests/` | 単体テスト |
| `UITests/` | シミュレータで動かす UI テスト |
| `Shims/` | Linux で型検査するための模型（上記） |
| `Config/` | staging / 本番の設定 |
| `Tools/` | 検査・リリース・ビルド補助のスクリプト |
| `docs/` | 手順書・設計の記録 |

## 設計の方針

- **Web を包まないネイティブアプリ。** 再利用するのは UI ではなく API です
- **EXIF と位置情報は端末で落とす。** 投稿する前に写真を焼き直し、
  結果を読み直して撮影情報が残っていないことを確かめます。残っていれば投稿しません
  （`ImagePreparer`）
- **圏外でも見られる。** 取れた一覧は端末に控え、壊れた応答は控えません

## デザイン

見た目の正は次の 2 か所です。画面を変えるときは先に読んでください。

- [`docs/design/ios-artifact/`](docs/design/ios-artifact/) … 画面ごとのデザインの板
- [`docs/BRAND.md`](docs/BRAND.md) … ブランドの表記

## そのほかの文書

- [`docs/APP_REVIEW.md`](docs/APP_REVIEW.md) … 審査で見られる点と、どこで満たしているか
- [`docs/APP_STORE_METADATA.md`](docs/APP_STORE_METADATA.md) … 掲載文の下書き
- [`docs/WEB_SYNC.md`](docs/WEB_SYNC.md) … Web 版の変更を追う方法

`docs/` の一部は作業中の記録で、日付の古いものは現状と違うことがあります。
