# 審査メモ（App Review Notes）

App Store Connect の「App Review Information → Notes」に貼る文面と、その根拠。
**審査で落ちる典型を、どこで満たしているか**を1か所にまとめてある。

---

## Notes に貼る文面（日本語／英語）

> このアプリは旅の写真を投稿・閲覧できる個人運営のギャラリーです。
> 閲覧はログイン不要、投稿にはメールアドレスでのアカウント登録が必要です。
>
> ・不適切な投稿は各写真の「…」メニューから通報でき、同じ場所で投稿者を
>   ブロックできます。ブロックの解除は「マイページ → 設定 → ブロックした人」。
> ・初回起動時に、不適切な内容を認めない旨を含む利用規約への同意を求めます。
> ・アカウントは「マイページ → 設定 → アカウントの削除」でアプリ内から削除できます。
> ・通報の宛先は journey.photo.official@gmail.com です。
> ・写真の撮影情報（EXIF）は端末側で取り除いてから送信し、位置は約1kmに
>   丸めて保存します。精細な位置情報は保存していません。

> This app is a personal travel photo gallery. Browsing requires no account;
> posting requires an email sign-up.
>
> - Objectionable content can be reported from the "…" menu on any photo, and
>   the poster can be blocked from the same menu. Blocks can be lifted under
>   My Page → Settings → Blocked people.
> - On first launch the user must accept terms that prohibit objectionable content.
> - Accounts can be deleted in-app under My Page → Settings → Delete account.
> - Reports reach journey.photo.official@gmail.com.
> - EXIF is stripped on device before upload; coordinates are rounded to ~1km.

## 審査用アカウント

**owner が用意する。** 本番の Cognito にテスト用のメールアドレスで登録し、
App Store Connect の Demo Account に入れる。

- 登録は「投稿」タブ →「アカウントを作る」。確認コードがメールで届く
- **写真を1枚は投稿しておく**。空のマイページだけだと、審査官が
  「投稿機能を確かめられない」として差し戻すことがある

## ガイドライン別の対応

| 条項 | 要求 | このアプリでの答え | 実装 |
|---|---|---|---|
| 4.2 Minimum Functionality | Web サイトを包んだだけは不可 | カメラからの直接投稿、端末側での EXIF 除去、オフライン表示 | `CameraPicker.swift` / `ImagePreparer.swift` / `PhotoSnapshotStore.swift` |
| 1.2 UGC | 規約への同意 | 初回起動時の同意画面 | `LegalGateView.swift` |
| 1.2 UGC | 不適切な内容の通報 | 写真ごとの「…」→ 通報（理由7種＋補足） | `ReportSheet.swift` |
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

**精細な位置（Precise Location）は「いいえ」。** 保存前に約1kmへ丸めている。

## 年齢制限

**12+ を想定。** 利用者が作った内容を載せるため（Infrequent/Mild と回答する
項目は無いが、UGC があることを質問票で申告する）。

投稿の事前審査は行っておらず、**通報を受けてから owner が確認して消す**運用。
質問票の「ユーザー生成コンテンツ」には「はい」と答え、通報・ブロックの
仕組みがあることを Notes に書く（上の文面に含めてある）。

## 落ちやすい点として残っているもの

- **投稿数が少ないと「中身が薄い」と見られることがある。** 公開写真は30枚
  規模。審査前に何枚か足しておくと安全
- **プッシュ通知は入れていない。** サーバー側（APNs 証明書・デバイストークンの
  保管・送信）が無いため。4.2 はカメラで満たしているので必須ではない
