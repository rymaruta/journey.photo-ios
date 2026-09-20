# journey.photo-ios

[journey-photo.com](https://journey-photo.com)（リポジトリ: `rymaruta/photo-gallery`）の
iOS アプリ版。SwiftUI のネイティブアプリで、既存の `api-user`（AWS Lambda +
API Gateway）をそのまま叩く。

---

## いまの状態

**土台だけができている。まだ一度もコンパイルしていない。**

作った環境（Linux コンテナ）に Swift ツールチェーンが無く、`download.swift.org` も
ネットワークポリシーで遮断されているため、**この中のコードは型検査も
ビルドもテストも通していない**。最初に Mac で開いたとき、コンパイルエラーが
出る前提で読むこと。

できているもの:

| 層 | 中身 |
|---|---|
| 設定 | `AppConfig` — Info.plist 経由で prod / staging を切り替え。**本番値のフォールバックは置かない** |
| 通信 | `APIClient` — ID トークン付き / 無しの両方。`{ error }` の日本語をそのまま画面に出す |
| 認証 | `AuthGateway` — Amplify の Cognito プラグイン。登録は UUID ユーザー名 ＋ email 属性（Web と同じ） |
| 画像 | `ImagePreparer` — **EXIF / GPS を端末で落としてから上げる**。落とせなければ投稿を断る |
| 投稿 | `UploadService` — presign → S3 に PUT → `/upload/save`。途中で落ちたら S3 の迷子を片付ける |
| 画面 | ギャラリー（公開写真）・写真詳細・投稿・マイページ・ログイン / 新規登録 |

まだ無いもの: アルバム、ストーリー、いいね、コメント、フォロー、通知、
ブロック、通報、退会、オフライン、プッシュ通知、地図。

## 動かし方

Xcode プロジェクト（`.xcodeproj`）は**コミットしていない**。マージのたびに
競合し、どの設定が効いているか読めなくなるため。定義は `project.yml` と
`Config/*.xcconfig` の2つだけ。

```bash
brew install xcodegen
xcodegen generate
open JourneyPhoto.xcodeproj
```

- **Debug ビルド = staging**（`Config/Staging.xcconfig`）
- **Release ビルド = 本番**（`Config/Production.xcconfig`）

staging には写真もユーザーも入っていない（本番からコピーしていない）ので、
動作を見るには staging 側で新規登録する。

依存は Swift Package Manager で [Amplify Swift](https://github.com/aws-amplify/amplify-swift)
が1つだけ。Cognito の SRP 認証・トークン更新・Keychain 保存のためで、
自前で SRP を実装しないための選択。

## 設計で決めたこと

### Capacitor で Web を包まない

- `photo-gallery` は `output: export` の静的サイトで、価値の中心は
  **SEO・先読み削減・Service Worker**。これらはアプリの中では1つも効かない
- App Store のガイドライン 4.2 は「Web サイトを包んだだけ」を弾く。Capacitor でも
  結局カメラ・オフライン・プッシュをネイティブで足すことになる
- 再利用できる資産は **UI ではなく API**。`api-user` は 60 本超の REST
  エンドポイントが Cognito 認証付きで揃っていて、そこは完成している

### 公開写真の一覧は静的 JSON を読む（暫定）

`api-user` に**公開の写真一覧エンドポイントが無い**（公開で叩けるのは
`/profile/{userId}`・`/users/search`・いいね数・コメント取得だけ）。
代わりに、デプロイ時にサイト直下へ置かれる `app/data/photos.json` を読む。

- 非公開フィールド（`srcOriginal` = GPS 入りの原本・`key`）は
  `lib/server/photos.ts` の `PRIVATE_FIELDS` で落とし済み
- **最新とは限らない**。反映はサイト再ビルド待ち（投稿時に
  `repository_dispatch` が走るので通常は数分）
- **ページングが無い**。30枚規模では丸ごと読んで問題ないが、
  数百枚を超えたら `GET /feed` を api-user に足すこと

### EXIF は端末で落とす（`ImagePreparer`）

Web 版は、再エンコードに失敗した経路が**原本を素通し**していて、
GPS 入りの HEIC が公開 URL で配信されていた（`lib/utils/image.ts` の
`toUploadSafeFile` の経緯）。同じ轍を踏まないよう、

1. 原本から撮影情報と GPS を**読んでから**
2. 1920px / JPEG 0.85 に焼き直し（メタデータは引き継がない）
3. **出力を読み直して EXIF / GPS が残っていないことを確かめる**
4. 残っていたら投稿を断る（素通ししない）

座標は端末側でも約1km（小数第2位）に丸めてから送る。サーバーも
`sanitizeCoords` で同じ丸めをするが、丸める前の値を電波に乗せる理由が無い。

### アイコン・カバーは控えない

`profiles/<uid>` は**固定キーで中身が差し替わる**側で、サーバーもアップロードも
`no-store` を付けている（`public/sw.js` が控えないのと同じ理由）。
読み直すときは `?v=` を付けて別 URL にする。

### URL はサイトのドメインに揃える

CloudFront の既定ドメインを直接指すと別オリジンになり、Web 側が
2026-09-13 に揃えた状態（`lib/utils/seo.ts` の `publicImageUrl`）から逆戻りする。

## CI を置いていない

**macOS ランナーは分数が 10 倍で課金される。** GitHub Actions の枠は
アカウント共通で、2026-09-13 時点で 1,807 / 2,000 分（残り約 193 分）。
iOS のビルド1回で実質 100 分以上を食う可能性があり、`photo-gallery` の
デプロイを止めかねない。

枠に余裕ができるまで、検証は手元の Xcode で行う:

```bash
xcodegen generate
xcodebuild -scheme JourneyPhoto -destination 'platform=iOS Simulator,name=iPhone 15' build test
```

## App Store に出すまでに要るもの

- [ ] ネイティブでないと通らない機能（4.2）— **カメラからの直接投稿**が本命。
      `ImagePreparer` はもう撮影データを受けられる形になっている
- [x] アプリ内でのアカウント削除（5.1.1(v)）— `DELETE /user/account` が既にある。
      画面はまだ無い
- [ ] 利用目的の文言（`project.yml` の `NS*UsageDescription`）の見直し
- [ ] アプリアイコンと起動画面
- [ ] プライバシーマニフェスト（`PrivacyInfo.xcprivacy`）
- [ ] 通報・ブロック（`/photos/{id}/report`・`/users/{id}/block`）— UGC アプリの
      審査で見られる。API は既にある

## 次にやること（順番）

1. **Mac で一度ビルドを通す。** ここが済むまで他は積まない
2. カメラからの直接投稿（4.2 の本命）
3. 写真詳細にいいね・コメント（API は既にある）
4. 他人のプロフィール画面とフォロー
5. 通報・ブロック・アカウント削除（審査で要る）
6. オフライン表示（Web の Service Worker がやっていることの相当品）
