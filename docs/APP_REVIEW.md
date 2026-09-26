# 審査メモ（App Review Notes）

App Store Connect の「App Review Information → Notes」に貼る文面と、その根拠。
**審査で落ちる典型を、どこで満たしているか**を1か所にまとめてある。

---

## Notes に貼る文面（日本語／英語）

> このアプリは旅の写真を投稿・閲覧できる個人運営のギャラリーです。
> 閲覧はログイン不要、投稿にはメールアドレスでのアカウント登録が必要です。
>
> ・不適切な投稿は各写真の「…」メニューから通報でき、同じ場所で投稿者を
>   ブロックできます。**通報・ブロックした内容は、その場で一覧から消えます。**
>   ブロックの解除は「マイページ → 設定 → ブロックした人」。
> ・審査用アカウントには写真を投稿済みです。「投稿」タブから新しい写真を投稿できます。
> ・初回起動時に、不適切な内容を認めない旨を含む利用規約への同意を求めます。
> ・プッシュ通知は「マイページ → 設定 → プッシュ通知を受け取る」でオンにできます。
> ・アカウントは「マイページ → 設定 → アカウントの削除」でアプリ内から削除できます。
>   審査用アカウントは削除していただいて構いません。
> ・通報の宛先は journey.photo.official@gmail.com です。
> ・写真の撮影情報（EXIF）は端末側で取り除いてから送信し、位置は約1kmに
>   丸めて保存します。精細な位置情報は保存していません。

> This app is a personal travel photo gallery. Browsing requires no account;
> posting requires an email sign-up.
>
> - Objectionable content can be reported from the "…" menu on any photo, and
>   the poster can be blocked from the same menu. Reported and blocked content
>   disappears from that user's feeds immediately. Blocks can be lifted under
>   My Page → Settings → Blocked people.
> - The demo account already has a photo posted. New photos can be posted from the "Post" tab.
> - On first launch the user must accept terms that prohibit objectionable content.
> - Push notifications can be turned on under My Page → Settings → Receive push notifications.
> - Accounts can be deleted in-app under My Page → Settings → Delete account.
>   Feel free to delete the demo account.
> - Reports reach journey.photo.official@gmail.com.
> - EXIF is stripped on device before upload; coordinates are rounded to ~1km.

## 審査用アカウント

**owner が用意する。** 本番の Cognito にテスト用のメールアドレスで登録し、
App Store Connect の Demo Account に入れる。

- 登録は「投稿」タブ →「アカウントを作る」。確認コードがメールで届く
- **owner 本人のアカウントは渡さない。** 審査官はアカウント削除も試す
- **写真を1枚は投稿しておく**。空のマイページだけだと、審査官が
  「投稿機能を確かめられない」として差し戻すことがある
- 審査官に消されたら、次の提出の前に作り直す
- App Store Connect の「App Review に関する情報」→「サインインが必要です」に入れる。
  連絡先の電話番号は国番号から（`+81 90 1234 5678`。先頭の 0 を取る）

## ガイドライン別の対応

| 条項 | 要求 | このアプリでの答え | 実装 |
|---|---|---|---|
| 4.2 Minimum Functionality | Web サイトを包んだだけは不可 | カメラからの直接投稿、端末側での EXIF 除去、オフライン表示 | `CameraPicker.swift` / `ImagePreparer.swift` / `PhotoSnapshotStore.swift` |
| 1.2 UGC | 規約への同意 | 初回起動時の同意画面 | `LegalGateView.swift` |
| 1.2 UGC | 不適切な内容の通報 | 写真ごとの「…」→ 通報（理由7種＋補足）。**通報した写真はその場で一覧から消える** | `ReportSheet.swift` / `ModerationStore.swift` |
| 1.2 UGC | 不適切な内容を出さない仕組み | ブロックした相手の写真を、ギャラリー・検索・地図・関連写真から**端末側で落とす**。公開の写真一覧はビルド時に焼いた静的 JSON なのでサーバー側では絞れない | `PublicGalleryService.setHidden` |
| 1.2 UGC | 迷惑な利用者のブロック | 通報と同じ場所＋プロフィールから。解除は設定 | `ModerationService.swift` / `BlockedUsersView.swift` |
| 1.2 UGC | 連絡先の公開 | 設定に「問い合わせ」。サイトの規約ページと同じ宛先 | `LegalConsent.contactEmail` |
| 5.1.1(v) | アプリ内でのアカウント削除 | 設定 → アカウントの削除（確認語の入力つき） | `DeleteAccountView.swift` |
| 5.1.1 | 必要のないログイン要求は不可 | 閲覧・検索・地図はログイン不要 | `RootView.swift` |
| 5.1.2 | 位置情報の最小化 | 精細な位置は保存しない（約1kmに丸める） | `ImagePreparer.readCoords` |
| 2.1 | プライバシーマニフェスト | 収集項目と UserDefaults の理由を申告 | `Resources/PrivacyInfo.xcprivacy` |
| 2.5.1 | 非公開 API 不使用 | 依存は Amplify Swift 1本のみ | `project.yml` |
| 4.8 Sign in with Apple | **対象外** | 第三者ログイン（Google・Facebook 等）を使っていない。認証は自前の Cognito でメール＋パスワードのみ | `AuthGateway.swift` |

## App Store Connect の「App のプライバシー」

`PrivacyInfo.xcprivacy` と**同じ内容**を答える。食い違うと差し戻される。

| データ | 収集する | 用途 | 本人と紐づく | トラッキング |
|---|---|---|---|---|
| メールアドレス | はい | アプリの機能 | はい | いいえ |
| 名前（表示名） | はい | アプリの機能 | はい | いいえ |
| 写真 | はい | アプリの機能 | はい | いいえ |
| その他のユーザーコンテンツ（コメント） | はい | アプリの機能 | はい | いいえ |
| おおよその位置 | はい | アプリの機能 | はい | いいえ |
| ユーザーID | はい | アプリの機能 | はい | いいえ |
| デバイスID（プッシュ通知の宛先） | はい | アプリの機能 | はい | いいえ |

**精細な位置（Precise Location）は「いいえ」。** 保存前に約1kmへ丸めている。

**デバイスID を落とさない。** 以前この表から抜けていたが、`PrivacyInfo.xcprivacy`
は申告している（APNs の端末トークン・通知を許可した人だけ）。食い違うと
差し戻される（2026-09-26 に表を直した）。

## 年齢制限の質問票（App Store Connect でそのまま答える）

**「なし」以外を選ぶのは、ユーザー生成コンテンツと（聞かれたら）メッセージの2問。**
ストーリーには返信でき、相手に届くので、メッセージ／チャットの問いには「はい」。

| 質問 | 答え |
|---|---|
| 暴力的な内容（漫画・空想／現実的） | なし |
| 性的な内容・ヌード | なし |
| 冒涜的・下品なユーモア | なし |
| アルコール・タバコ・薬物 | なし |
| 恐怖・ホラー | なし |
| 賭博 | なし |
| 医療・医学情報 | なし |
| コンテスト | なし |
| **ユーザー生成コンテンツ（UGC）** | **あり（頻繁でない／軽度）** |
| **メッセージ／チャット**（質問票にある場合） | **はい**（ストーリーへの返信） |
| 無制限のウェブアクセス | なし |
| 賭博とコンテスト | なし |

**UGC を「あり」にする理由と、そのときに聞かれること**——このアプリは
利用者が写真とコメントを投稿する。通報・ブロック・規約への同意があることを
Notes に書いてある（上の文面）。事前審査はしていないが、通報を受けて
owner が消す運用で、押した本人の画面からはその場で消える。

> ⚠️ **ここを「なし」にすると通らない。** 写真とコメントを載せる時点で UGC。
> 隠すと差し戻しでは済まず、信頼を落とす。

## 提出前の最終確認（ここを全部緑にしてから出す）

- [ ] `bash Tools/mac-release.sh` が通る（生成・ビルド・テスト）
- [ ] 実機で一巡（カメラ・ライブラリ・通報・ブロック・退会・機内モード）
- [ ] スクリーンショット 3枚以上（人の顔・他人の投稿・他社のロゴを入れない）。
      寸法は枠ごとに厳密——6.5インチ枠は 1242×2688 / 1284×2778、
      6.9インチ枠は 1290×2796 / 1320×2868。無印・Pro の iPhone（1179×2556）で
      撮ったものはそのままではどの枠にも入らない（拡大して 1284×2778 にする）
- [ ] 審査用アカウントを**本番**に作り、写真を1枚投稿
- [ ] App のプライバシーの回答が `PrivacyInfo.xcprivacy` と一致
- [ ] 年齢制限の質問票（上の表）
- [ ] サポート URL・プライバシーポリシー URL（`docs/APP_STORE_METADATA.md`）
- [ ] App Store Connect の「バージョン」欄と、ビルドの版（`testflight/<版>` のタグ）が一致
      （版は CI が毎回 +1 する。並行して上げると番号が進むので、提出するビルドの版を見る）
- [ ] Notes に上の文面を貼った

### 想定される区分

**12+ を想定。** 利用者が作った内容を載せるため（Infrequent/Mild と回答する
項目は無いが、UGC があることを質問票で申告する）。

投稿の事前審査は行っておらず、**通報を受けてから owner が確認して消す**運用。
ただし通報・ブロックは**押した瞬間に、その人の画面から消える**
（サーバーの判断を待たない）。
質問票の「ユーザー生成コンテンツ」には「はい」と答え、通報・ブロックの
仕組みがあることを Notes に書く（上の文面に含めてある）。

## 提出前に Mac でやること（ここだけ Linux で代替できない）

1. `xcodegen generate` → `xcodebuild build test`（本物の SwiftUI での型検査）
2. 実機で一巡（カメラはシミュレータに無い。やり方: `docs/DEVICE_TEST.md`）
3. スクリーンショット（6.7インチ・最低3枚）
4. 審査用アカウントを本番に作り、写真を1枚投稿しておく

## 落ちやすい点として残っているもの

- **投稿数が少ないと「中身が薄い」と見られることがある。** 公開写真は30枚
  規模。審査前に何枚か足しておくと安全
- ✅ **プッシュ通知の叩き先は本番にある**（2026-09-25）。`photo-gallery` の
  #177 で `POST /user/devices` が本番に入った。未ログインで叩くと 401、
  無い道は 404 で区別できることを確かめた。**実機で届くところまでは未確認**
  （TestFlight で確かめる）。以前ここにあった「押すと 404」は解消済み
