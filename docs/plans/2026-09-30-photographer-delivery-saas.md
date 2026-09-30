# 写真家向け納品・ギャラリー SaaS への転用: 何が流用できて、何を新しく作るか

2026-09-30。`journey.photo-ios`（Swift 227 ファイル・33,167 行）と `photo-gallery`（Next.js + api-user、develop `a35f269`）を
読んで見立てたもの。**実機・本番環境では何も試していない。** 市場（写真家が払うか・競合の強さ）は確かめていない。

## 先に結論

- **流用できるのは土台で、納品の中心は全部新しく作る。** 「半分以上がそのまま効く」という先の見立ては誤り。
  そのまま使えるのは認証・通信・アップロードの安全対策・招待トークン・署名配信の部品・CI と環境分離で、
  iOS の行数で言えば 2,000〜2,500 行（約 7%）。
- **今の設計と真正面からぶつかる点が3つ**ある。ここを直さない限り納品には使えない。
  1. **原本を持たない。** Web も iOS も長辺 1920px・JPEG 品質 0.85 に縮めて EXIF を消し、縮めた物しか保存しない
     （`lib/utils/image.ts` の `toUploadSafeFile`、iOS の `ImagePreparer.maxPixelSize = 1920`）。`srcOriginal` を書く経路は無い。
  2. **公開が既定で、画像 URL は誰でも取れる。** `published !== false` なら公開一覧（`photos.json`・`GET /photos`）に全員分が混ざる。
     `/uploads/**` は1年キャッシュの公開 URL。署名配信のコード（`signedUrl.ts`・`privateMove.ts`）はあるが本番は未設定。
  3. **反映が「静的サイトの再ビルド」。** 公開・削除のたびに GitHub Actions が 6〜18 分回り、月次上限とクールダウンがある。
     テナントが増えると成り立たない。
- **無いもの**: 課金（Stripe・プラン・容量の計量）、ダウンロード（単体・ZIP・原寸）、クライアントの選別（枚数上限・確定・提出）、
  透かし、有効期限つきギャラリー、メール送信（SES）、パスワード保護、ログイン不要の閲覧、Deep link / Universal Links。
- **推奨する進め方**: 既存のリポジトリを改造するのではなく、**新しいバックエンドを別リポジトリで起こし、部品を移す。**
  SNS 専用のコード（iOS の約 57%、サーバーのストーリー・フォロー・地図・音楽ほか）を剥がす作業は、新しく書くより高くつく。

## 流用の見立て（サーバー・Web）

| 部品 | 場所 | 見立て |
|---|---|---|
| Cognito 認証・JWT オーソライザー・admin/user グループ | `api-user/serverless.yml`、`src/http.ts` | そのまま |
| presign の安全対策（Content-Type/Length を署名・拡張子の許可・本人領域の検証） | `src/upload.ts`、`src/uploadPolicy.ts` | そのまま |
| 招待トークン（192bit・失効・期限） | `src/invite.ts` | そのまま〜手直し |
| 署名付き URL・`private/` への移動 | `src/signedUrl.ts`、`src/privateMove.ts` | 手直し（本番の CloudFront 設定が要る） |
| 環境分離（prod/staging）・`requireEnv`・deploy-api の流れ | `.github/workflows/deploy-api.yml`、`src/env.ts` | そのまま |
| グリッド・モーダル・コメント | `app/components/GalleryGrid.tsx`、`GalleryModal/*`、`CommentSection.tsx` | 手直し |
| 共同アルバム | `src/albums.ts` | 手直し寄りの作り直し（「同行者が写真を足す」→「写真家が持ち主・クライアントは見る」に権限を変える。`photoIds` 配列は Query できない） |
| テーブル設計（単一 PK・GSI 3本・TTL 無し） | `scripts/provision-env.js` | 作り直し（テナント／案件／写真のキー設計） |
| 画像処理（ブラウザで 1920px に縮小） | `lib/utils/image.ts` | 作り直し（S3 起点の Lambda で原寸保存・派生・透かし） |
| 静的サイト生成・再ビルド | `scripts/sync-photos-from-ddb.js`、`src/rebuild.ts` | 捨てる（API＋署名 URL の動的描画に） |
| 多言語（ja 固定・切替 UI 廃止） | `app/i18n/*` | 手直し |
| 課金・メール・ダウンロード・選別・透かし・期限 | — | **無い。新規** |

## 流用の見立て（iOS）

| 部品 | 場所 | 行数（概算） | 見立て |
|---|---|---|---|
| 通信（actor・3つの口・エラーの分類） | `Core/Networking/APIClient.swift`、`APIError.swift` | 272 | そのまま |
| 認証（Amplify/Cognito・状態・失敗の分類） | `Core/Auth/AuthGateway.swift`、`AuthStore.swift` | 541 | そのまま |
| アップロードの3段階と後片付け | `Services/UploadService.swift` | 225 | そのまま |
| EXIF の関所（消したことを確かめてから上げる） | `Services/ImagePreparer.swift` | 225 | 手直し（原本で送る経路を足す） |
| 設定・多言語・テーマ・部品 | `AppConfig`、`L()`、`WebTheme`、`RemoteImage`、`FormParts`、`ToastCenter` | 〜700 | そのまま（文言とブランドは差し替え） |
| テストの土台・検査・TestFlight の経路 | `Package.swift`＋`Shims/`、`Tools/verify.sh`、`ios-testflight.yml` | — | そのまま（`check-api-parity.py` の向き先を変える） |
| 大きく見る画面 | `Features/PhotoDetail/PhotoViewerView.swift` | 256 | 手直し（ズームは指を離すと戻る・パン無し・ダブルタップはいいね） |
| 共同アルバム・招待 | `Features/Albums/*`、`JoinedAlbumsStore` | 〜550 | 作り直し寄りの手直し（参加先が端末にしか残らない・会員向けの一覧の口が無い） |
| いいね・保存の控え | `FavoritesStore`、`SavedPhotosStore` ほか | 448 | 手直し（「お気に入り選択」の土台） |
| 通知・プッシュ | `Features/Notifications`、`Core/Push` | 1,270 | 半分は手直しで残せる（「納品できました」） |
| 写真詳細・マイページ | `PhotoDetailView.swift`、`MyPageView.swift` ほか | 3,392 | 作り直し |
| SNS 専用（ストーリー・地図・旅・探す・フォロー・音楽・通報・今日のテーマ） | 約 120 ファイル | **18,966（57%）** | 捨てる |
| 公開一覧 `photos.json` を読む画面 | 11 ファイル・13 か所 | — | 捨てる（納品物は非公開） |
| ダウンロード・Deep link・バックグラウンド転送・並列アップロード | — | — | **無い。新規** |

## 新しく作るもの（最小の製品）

写真家が月額を払う理由になる順に並べた。上から順に作る。

1. **原寸の保存と派生**: S3 起点の Lambda で、原本（`original/`）を残し、閲覧用（長辺 2048）・サムネ（512）・透かし付きを作る。
   iOS の `ImagePreparer` は「GPS・シリアルを消す関所」として残し、縮小はサーバーに移す。
2. **案件（ギャラリー）と権限**: `tenant → gallery → photo` のキー設計。写真家＝持ち主、クライアント＝閲覧・選択・ダウンロード。
   ログインなしでトークン（＋任意のパスワード）だけで見られる経路。有効期限。`invite.ts` を土台にする。
3. **配信**: CloudFront の署名 URL（`signedUrl.ts` を本番に載せる）。公開一覧・静的ビルド・SEO は持たない。
4. **クライアント側の閲覧（Web）**: グリッド → 大きく見る（ピンチズーム・パン）→ お気に入り（上限枚数・確定して写真家に提出）→ ダウンロード（単体・ZIP・原寸／SNS 用）。
   `GalleryGrid`・`GalleryModal` を手直し。iOS アプリはこの段では要らない（クライアントはブラウザで足りる）。
5. **写真家側の管理（Web）**: 案件の作成・数百枚のアップロード（並列・再開）・招待リンク・選択結果の閲覧・期限。
6. **課金**: Stripe（サブスク・容量／案件数のプラン・計量）。
7. **メール**: SES（納品・選択完了・期限の予告）。
8. **iOS**（後回し）: 写真家が撮ってその場で上げる用途だけ。`UploadService`・`AuthGateway`・`APIClient` を移す。Universal Links で招待を開く。

## 費用の目安（作る量）

- 新規のバックエンド（1〜7）: 既存の部品を移しても、**新しく書く方が多い**。api-user の骨格（Lambda・DynamoDB・Cognito・CI）の
  型は分かっているので、ゼロから起こすよりは早い。
- Web のクライアント閲覧＋写真家の管理: `GalleryGrid`/`GalleryModal` は流用できるが、ページの大半は新規。
- iOS: 土台 2,000〜2,500 行を移し、画面は新規。**最初の製品には要らない。**

## やらない方がよいこと

- 既存の `photo-gallery` / `journey.photo-ios` を改造して納品 SaaS にすること。SNS 機能を剥がす作業（サーバーの `account.ts` 820 行の退会処理、
  iOS の 57%）が新しく書く量を上回り、公開既定・静的ビルドの前提も残る。
- journey.photo と同じアカウント・同じテーブルに納品物を同居させること。公開一覧に混ざる事故の温床になる。

## 確かめていないこと

- 国内の写真家が納品に何を使い、月いくら払っているか（**作る前にここを10人に聞く**）
- 競合（Pixieset・Pic-Time・国内勢）の価格と、日本語・国内決済・LINE 共有で差が付くか
- S3 起点の Lambda の同時実行（今はアカウント全体で 10）で、数百枚の一括アップロードが詰まらないか
- Apple の Foundation・実機での挙動全般（この文書はコードを読んだだけ）
