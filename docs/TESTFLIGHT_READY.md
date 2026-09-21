# TestFlight を回す前の最終確認（2026-09-21）

**アプリ側の実装は終わっています。** 残っているのは、私からは触れない
「Apple と GitHub の画面での操作」だけです。

---

## 1. owner がやること（これだけ）

| # | やること | 場所 |
|---|---|---|
| 1 | リポジトリを **public** にする | GitHub → journey.photo-ios → Settings → Danger Zone |
| 2 | App Store Connect で**アプリの枠**を作る（Bundle ID `com.journeyphoto.JourneyPhoto`） | appstoreconnect.apple.com → マイ App → ＋ |
| 3 | **App Store Connect API キー**を作る（App Manager） | appstoreconnect.apple.com/access/integrations/api |
| 4 | **Secrets を4つ**入れる（下） | GitHub → journey.photo-ios → Settings → Secrets → Actions |
| 5 | **Actions → TestFlight → Run workflow** | GitHub |

### Secrets（journey.photo-ios）

| 名前 | 中身 |
|---|---|
| `APP_STORE_CONNECT_ISSUER_ID` | API キーのページ上部の UUID |
| `APP_STORE_CONNECT_KEY_ID` | 作ったキーの Key ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | `AuthKey_XXXX.p8` の全文 |
| `CERTIFICATE_PRIVATE_KEY` | 署名用の RSA 鍵（この会話でお渡ししたもの） |

> **なぜ public か**: macOS ランナーは private だと**分数10倍**で、枠は
> photo-gallery と共通。枠切れは「遅くなる」ではなく「**何も出せなくなる**」
> （2026-08 に20日間止まった）。public なら無料。

### プッシュ通知も届かせるなら（任意・あとでもよい）

| 名前 | 中身 | 場所 |
|---|---|---|
| `APNS_PRIVATE_KEY` | `AuthKey_DDYJB5893J.p8` の全文 | **photo-gallery** の Secrets |

そのうえで `api-user/**` の変更が `main`（本番）か `develop`（staging）に
入ると、`Deploy API Lambdas` が配ります（約4.5分）。**鍵が無くても通知は
積まれます**（アプリを開けば読める）——端末に飛ばないだけです。

## 2. こちらで済んでいること

- **アプリの機能は Web と同等**（投稿・複数枚・タグ/カテゴリの固定候補・
  ストーリー（曲・長さ・動画の再生・返信・反応）・アルバムと招待・
  フォロー/いいね/コメント・地図・検索・ピン留め・写真の差し替え・
  プロフィールの色・トップの3タブ・通報とブロック・退会）
- **プッシュ通知**（サーバー＝ api-user、アプリ＝許可・宛先・タップの行き先）
- **審査で見られるところ**: 4.2（ネイティブのカメラ）・1.2（通報・ブロック・
  規約同意・問い合わせ・**持ち主によるコメント削除**）・5.1.1(v)（アプリ内退会・
  **英語の端末でも打てる確認語**）・プライバシーマニフェスト
- **CI**: GitHub Actions（`ios-testflight.yml`）と Codemagic（`codemagic.yaml`）の
  両方。ビルド番号は TestFlight の最大+1、アプリの Apple ID は Bundle ID から自動取得
- **関門**: `Tools/verify.sh`（構文・参照・API の突き合わせ・設定・単体テスト151件）

## 3. ビルドが通ったあと

1. App Store Connect → アプリ → **TestFlight** → 内部テスト → 自分を追加
2. iPhone の **TestFlight** アプリで受け取る
3. **最初に確かめること**（実機でしか分からない順）
   - 起動してギャラリーが出る（公開の写真が並ぶ）
   - 新規登録 → メールのコードで確認 → ログイン
     （**未確認のまま閉じて開き直す**のも試す。ここは Web で詰んだ経路）
   - 写真を1枚投稿（カメラとライブラリの両方）
   - 設定 →「プッシュ通知を受け取る」→ 別のアカウントからいいね → 届くか
   - 退会（**確認語が端末の言語で出るか**）

## 4. まだ確かめられていないこと（正直に）

- **本物の SwiftUI SDK に当てていません。** この環境は Linux で、iOS の
  ビルドには Mac が要ります。型検査は `Shims/` の模型に向けたもので、
  「模型では通るが Xcode で落ちる」形は初回ビルドで出ます
  （実際に `Section(_:content:footer:)` を1件見つけて直しました）
- **実機の APNs には触れていません。** 署名の形（ES256・生の64バイト）や
  鍵の綴りは本家のソースで確かめましたが、実際に届くかは実機で初めて分かります
- Amplify（Cognito）の応答も同様。**最初のビルドで確かめる**のが最短です
