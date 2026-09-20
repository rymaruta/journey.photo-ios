# journey.photo-ios

[journey-photo.com](https://journey-photo.com)（リポジトリ: `rymaruta/photo-gallery`）の
iOS アプリ版。SwiftUI のネイティブアプリで、既存の `api-user`（AWS Lambda +
API Gateway）をそのまま叩く。

---

## ⚠️ 最初に読むこと

**全ファイルがコンパイルでき、テストも走っている。ただし SwiftUI は模型。**

| 何 | 状態 |
|---|---|
| 全 70 ファイル | `swift build` が通る（`Shims/` の模型に向けて） |
| テスト 60件 | `swift test` が通る |
| `project.yml` | **Linux で `xcodegen generate` が通る**（設定の書き間違いはここで消える） |
| 本物の SwiftUI での検査 | **していない**（iOS SDK が要る＝Mac が要る） |

`Shims/` は **Linux で型検査するためだけの模型**で、SwiftUI・UIKit・PhotosUI・
MapKit・AVFoundation・ImageIO・Combine・Amplify の「使っている口の形」だけを
宣言してある。実機のビルドには一切入らない（Xcode は `project.yml` から作られ、
`Package.swift` を見ない）。

**模型の修飾子は素通し**なので、SwiftUI 側の制約（ViewBuilder の枝の数・
`some View` の同一性・修飾子の順序・実行時の挙動）は見ていない。
見えるのは**自分たちのコードの誤り**——綴り違い・無いプロパティ・
引数ラベルの不一致・型の取り違え・分離（`@MainActor`）の誤り。

> これを入れた時点で、**Xcode でも落ちる誤りが実際に8ファイル見つかった**
> ——`ObservableObject` と `@Published` を使うのに `Combine` も `SwiftUI` も
> import していなかった（`Foundation` だけでは通らない）。

```bash
bash Tools/verify.sh
```

- `Tools/check-swift-syntax.js` … tree-sitter で全 Swift の**構文**
- `Tools/check-swift-refs.js` … 配られていない `@EnvironmentObject`・型の重複・
  `@MainActor` の静的メンバをテストから呼んでいないか
- `Tools/check-api-parity.py` … Web 版の `api-user` と**叩く口の突き合わせ**
- `Tools/check-config.py` … plist・JSON・YAML と、ファイルをまたいだ約束
- Swift があれば `swift build` と `swift test`
- Mac なら続けて `xcodegen generate` と `xcodebuild build test`

### Linux に XcodeGen を入れる（`project.yml` の検証用）

```bash
bash Tools/install-xcodegen-linux.sh   # 素の Swift パッケージなので Linux で動く
```

生成した `.xcodeproj` を**開ける**のは Mac だけだが、**生成が通るか**は
ここで分かる。

### Linux に Swift を入れる

公式の配布元（`download.swift.org`）が塞がれた環境でも、**公式の Docker
イメージの中身は取り出せる**（docker は要らない）:

```bash
sudo bash Tools/install-swift-linux.sh
export PATH=/opt/swift/bin:$PATH
```

入るのは Linux 用の Swift。**iOS SDK は入らない**ので、SwiftUI に触る
ファイルは Mac でしかビルドできない。

## 動かし方

```bash
brew install xcodegen
xcodegen generate
open JourneyPhoto.xcodeproj
```

- **Debug ビルド = staging**（`Config/Staging.xcconfig`）
- **Release ビルド = 本番**（`Config/Production.xcconfig`）

`.xcodeproj` はコミットしない。定義は `project.yml` と `Config/*.xcconfig`
の2つだけ。依存は Swift Package Manager で
[Amplify Swift](https://github.com/aws-amplify/amplify-swift) が1つ
（Cognito の SRP 認証・トークン更新・Keychain 保存のため）。

staging には写真もユーザーも入っていない（本番からコピーしていない）ので、
動作を見るには staging 側で新規登録する。

## 入っているもの

| 面 | 中身 |
|---|---|
| 見る | ギャラリー（カテゴリ絞り込み）・写真詳細・関連写真・タグ/撮影地/カテゴリの一覧・地図・年表・検索 |
| 書く | カメラ撮影・ライブラリから投稿・写真の編集・下書き（非公開）・プロフィール編集（アイコン/カバー） |
| つながる | いいね・コメント・フォロー（一覧つき）・お知らせ（未読バッジ）・ストーリー（投稿/閲覧/返信/見た人/残す）・アルバム（作成・招待リンクの発行と参加） |
| 安全 | 規約への同意・通報・ブロックと解除・アカウント削除 |
| 支える | オフライン表示・お気に入り・曲の30秒試聴 |

まだ無いもの:

- **プッシュ通知**。サーバー側（APNs 証明書・デバイストークンの保管・送信）が
  無いため。4.2 はカメラで満たしているので審査には要らない
- **英語の画面**。写真の題と説明は言語ごとの値を出し分けるが、**画面の文字は
  日本語だけ**。Web 版は ja / en を持っている
- 動画のストーリー投稿（API は `video/mp4` などを受ける）

## 設計で決めたこと

### Capacitor で Web を包まない

- `photo-gallery` は `output: export` の静的サイトで、価値の中心は
  **SEO・先読み削減・Service Worker**。これらはアプリの中では1つも効かない
- ガイドライン 4.2 は「Web サイトを包んだだけ」を弾く。Capacitor でも結局
  カメラ・オフラインをネイティブで足すことになる
- 再利用できる資産は **UI ではなく API**。`api-user` は 60 本超の
  エンドポイントが Cognito 認証付きで揃っている

### 公開写真の一覧は静的 JSON を読む（暫定）

`api-user` に**公開の写真一覧エンドポイントが無い**（公開で叩けるのは
`/profile/{userId}`・`/users/search`・いいね数・コメント取得だけ）。
デプロイ時にサイト直下へ置かれる `app/data/photos.json` を読む。

- 非公開フィールド（GPS 入りの原本 `srcOriginal`・`key`）は
  `lib/server/photos.ts` の `PRIVATE_FIELDS` で落とし済み
- **公開されていることは deploy の経路で確かめた**——
  `scripts/deploy-static-site.js` が `out/app/data/photos.json` へコピーし、
  `out/` を丸ごと公開バケットへ上げ、`NO_CACHE_KEYS` にも入れている。
  ただし**実際の応答は未確認**（作成環境から `journey-photo.com` へ出られない）
- **最新とは限らない**。反映はサイト再ビルド待ち（投稿時に
  `repository_dispatch` が走るので通常は数分）
- **ページングが無い**。30枚規模では問題ないが、数百枚を超えたら
  `GET /feed` を api-user に足すこと
- 取れたときだけ端末に控え、**圏外ではそれを出す**。壊れた応答は控えない
  （キャプティブポータルのログイン HTML を「写真一覧」として覚えないため）

### EXIF は端末で落とす（`ImagePreparer`）

Web 版は、再エンコードに失敗した経路が**原本を素通し**していて、
GPS 入りの HEIC が公開 URL で配信されていた（`lib/utils/image.ts` の
`toUploadSafeFile` の経緯）。同じ轍を踏まないよう、

1. 原本から撮影情報と GPS を**読んでから**
2. 1920px / JPEG 0.85 に焼き直し（メタデータは引き継がない）
3. **出力を読み直して EXIF / GPS が残っていないことを確かめる**
4. 残っていたら投稿を断る（素通ししない）

座標は端末側でも約1km（小数第2位）に丸めてから送る。

### そのほか

- **ID トークンを送る。** アクセストークンだと `audience` が合わず全部 401
- **アイコン・カバーは控えない。** `profiles/<uid>` は固定キーで中身が
  差し替わる側（サーバーもアップロードも `no-store`）。読み直すときは `?v=`
- **URL はサイトのドメインに揃える。** CloudFront の既定ドメインを直接指すと
  別オリジンになり、Web 側が 2026-09-13 に揃えた状態から逆戻りする
- **お気に入りの鍵はアカウントごと。** Web で共有キー1本だった頃、同じ端末の
  別の人にハート一覧が見え、初回押下が取り消しに化けていた
- **日付を `Date` に変換しない。** `"2024-10-12"` を UTC 0時として読んで端末の
  ゾーンに直すと、西側の利用者には1日前に見える

## CI を置いていない

**macOS ランナーは分数が10倍で課金される。** GitHub Actions の枠は
アカウント共通で、2026-09 時点で残り約193分。iOS のビルド1回で
`photo-gallery` のデプロイを止めかねない。検証は手元の Xcode で行う。

## Web 版との同期

`docs/WEB_SYNC.md`。**契約は API、意匠は追う、SEO は追わない**。

```bash
git -C ../photo-gallery fetch origin main
bash Tools/web-changes.sh ../photo-gallery   # 変わったところと突き合わせ
```

## リリース

- `docs/RELEASE.md` … 手順（Developer Program の加入から提出まで）
- `docs/APP_REVIEW.md` … 審査メモ。**落ちやすい条項と、どこで満たしているか**
- `docs/APP_STORE_METADATA.md` … 掲載文の下書き

## 次にやること（順番）

1. **Mac で一度ビルドを通す。** ここが済むまで他は積まない
2. staging で `docs/RELEASE.md` の確認項目をひと通り
3. TestFlight（カメラは実機でしか確かめられない）
4. スクリーンショットを撮って提出
