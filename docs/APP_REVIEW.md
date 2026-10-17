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
> ・初回起動時に、不適切な内容を認めない旨を含む利用規約への同意を求めます。
> ・プッシュ通知は「マイページ → 設定 → プッシュ通知を受け取る」でオンにできます。
> ・アカウントは「マイページ → 設定 → アカウントの削除」でアプリ内から削除できます。
>   審査用アカウントは削除していただいて構いません。
> ・通報の宛先は journey.photo.official@gmail.com です。
> ・写真ファイルに埋め込まれた撮影情報（EXIF・GPS）は端末側で取り除いてから
>   送信し、位置は約1kmに丸めて保存します。精細な位置情報は保存していません。
>   カメラの機種・レンズ・撮影日は、写真ページの「撮影情報」に表示します。
> ・ストーリーへの返信は、返信の一覧の各行の「…」から通報（運営の宛先へのメール）と
>   ブロックができます。
> ・**背景での Bluetooth（UIBackgroundModes: bluetooth-central / bluetooth-peripheral）**は
>   「すれちがい」のためだけに使います。「マイページ → 設定 → すれちがい」でオンにした人だけ
>   （既定はオフ）、画面を閉じている間も近くの Journey Photo 利用者と「わたしの乗車券」のカード
>   （本人が選んだ公開写真1枚・ひとこと・乗車券の発・着の字）を交換します。位置・連絡先は送りません。
> ・**すれちがいを試すには iPhone が2台要ります**（2台とも審査用のアカウントでログインし、
>   それぞれで「すれちがい」をオンにして近くに置く。カードはその日の 18 時にまとめて届きます）。
>   2台で動いている様子の動画: 【owner が用意する: 動画の URL】
> ・**Pro（自動更新の定期購入）**: 「Journey Photo Pro」月額（`<束の名前>.pro.monthly`・¥500/月）と
>   年額（`<束の名前>.pro.yearly`・¥5,000/年）。同じサブスクリプショングループ「Journey Photo Pro」。
>   無料の試用はありません。中身は「光と天気の知らせ」「電波なしで使える旅」「名前の横の Pro マーク」。
>   （「作例・構図を重ねて撮る」は 2026-10-17 から全員無料。ログインしていなくても撮れます）
>   試し方: 「マイページ → 設定 → Pro → Journey Photo Pro」で案内を開き、
>   プランを選んで「Pro をはじめる」（Sandbox のアカウントで購入できます）。案内の下の
>   「購入を復元」で復元、解約は App Store の定期購入の管理から。

> This app is a personal travel photo gallery. Browsing requires no account;
> posting requires an email sign-up.
>
> - Objectionable content can be reported from the "…" menu on any photo, and
>   the poster can be blocked from the same menu. Reported and blocked content
>   disappears from that user's feeds immediately. Blocks can be lifted under
>   My Page → Settings → Blocked people.
> - On first launch the user must accept terms that prohibit objectionable content.
> - Push notifications can be turned on under My Page → Settings → Receive push notifications.
> - Accounts can be deleted in-app under My Page → Settings → Delete account.
>   Feel free to delete the demo account.
> - Reports reach journey.photo.official@gmail.com.
> - Embedded EXIF/GPS metadata is stripped from the image file on device before
>   upload; coordinates are rounded to ~1km. Camera model, lens and capture date
>   are shown publicly in the photo's "Shooting info" section.
> - Replies to a story can be reported (by email to the address above) and their
>   senders blocked from the "…" on each reply in the replies list.
> - **Background Bluetooth (UIBackgroundModes: bluetooth-central / bluetooth-peripheral)**
>   is used only for "Pass". Only users who turn it on under My Page → Settings → Pass
>   (off by default) swap a "card" (one public photo they chose, a short note and the
>   from/to text on the ticket) with Journey Photo users nearby, also while the app is
>   in the background. No location or contact details are sent.
> - **Testing Pass needs two iPhones** (sign in on both, turn Pass on on both and keep
>   them close; received cards arrive together at 6 PM that day).
>   Video of it working on two devices: [OWNER TO FILL IN: video URL]
> - **Pro (auto-renewable subscription)**: "Journey Photo Pro" monthly
>   (`<bundle id>.pro.monthly`, ¥500/month) and yearly (`<bundle id>.pro.yearly`,
>   ¥5,000/year) in the subscription group "Journey Photo Pro". No free trial.
>   Pro adds light & weather alerts, offline trips and a Pro mark. (Shooting with a
>   composition / example overlay is free for everyone and works without signing in.)
>   To test: My Page → Settings → Pro → Journey Photo Pro, pick a plan and tap
>   "Start Pro" (Sandbox account). "Restore" is under the plans; cancel from
>   the App Store subscription settings.

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
| 1.2 UGC | 不適切な内容を出さない仕組み | ブロックした相手の写真を、ギャラリー・検索・地図・近くの写真から**端末側で落とす**。公開の写真一覧はビルド時に焼いた静的 JSON なのでサーバー側では絞れない | `PublicGalleryService.setHidden` |
| 1.2 UGC | 迷惑な利用者のブロック | 通報と同じ場所＋プロフィールから。解除は設定 | `ModerationService.swift` / `BlockedUsersView.swift` |
| 1.2 UGC | 連絡先の公開 | 設定に「問い合わせ」。サイトの規約ページと同じ宛先 | `LegalConsent.contactEmail` |
| 5.1.1(v) | アプリ内でのアカウント削除 | 設定 → アカウントの削除（確認語の入力つき） | `DeleteAccountView.swift` |
| 5.1.1 | 必要のないログイン要求は不可 | 閲覧・検索・地図はログイン不要 | `RootView.swift` |
| 5.1.2 | 位置情報の最小化 | 精細な位置は保存しない（約1kmに丸める） | `ImagePreparer.readCoords` |
| 5.1.1 / 5.1.2 | Bluetooth（すれちがい・2026-10-16） | **既定はオフ**。オンにする前に説明を出し、そこで初めて Bluetooth を尋ねる。電波で渡すのは版・公開写真の id・ひとこと（20字・80 バイトまで）・乗車券の発・着の字（6字まで）・居住地を出すかの印だけ（出す設定のときは、受け取った端末が公開プロフィールから居住地の都道府県を引いて出す）。**特性は暗号化しておらず、近くの Bluetooth 機器なら誰でも読める**（写真の id から持ち主も分かる・乗車券を変えるまで同じ値・ブロックした相手にも届きうる）——設定とオンにする前の説明にそのまま書いてある（`PassPrivacyText`）。カードの「…」から通報・ブロック・帳から外すができる（審査 1.2）。受け取ったカード・すれちがった場所（市区町村ほど・0.1 度に丸める）は**端末の中だけ**でサーバーへ送らない（＝収集しない）。地名を引くときは約1kmに丸めた座標だけを Apple の地図（`CLGeocoder`）に渡す（`PassExchange.lookupCoords`）。背景の Bluetooth（UIBackgroundModes）はこのためだけ。位置は撮影地マップで許可済みのときだけ使い、すれちがいからは尋ねない | `PassRadio.swift` / `PassStore.swift` / `PassExchange.swift` |
| 1.2 UGC | ストーリーへの返信の通報・ブロック | 返信の一覧の各行の「…」。**通報はメール**（返信を通報するサーバーの口が無く、写真の通報の口は自分のストーリーを受けない＝400）。宛先は問い合わせと同じ。ブロックは既存の口でその場で一覧から消える | `StoryRepliesSheet.swift` / `ModerationService.storyReplyReportURL` |
| 2.1 | プライバシーマニフェスト | 収集項目と、理由の要る API（UserDefaults: CA92.1・ディスクの空き: 85F4.1）を申告 | `Resources/PrivacyInfo.xcprivacy` |
| 3.1.2 | 自動更新の定期購入 | 案内に値段・期間・自動更新の一文（24時間前までに解約しない限り更新・止め方）・利用規約とプライバシーポリシーのリンク・購入の復元 | `PaywallView.swift` / `ProPaywallText` |
| 2.5.1 | 非公開 API 不使用 | 依存は Amplify Swift 1本のみ | `project.yml` |
| 4.8 Sign in with Apple | **対象外** | 第三者ログイン（Google・Facebook 等）を使っていない。認証は自前の Cognito でメール＋パスワードのみ | `AuthGateway.swift` |

## App Store Connect の「App のプライバシー」

`PrivacyInfo.xcprivacy` と**同じ内容**を答える。食い違うと差し戻される。

| データ | 収集する | 用途 | 本人と紐づく | トラッキング |
|---|---|---|---|---|
| メールアドレス | はい | アプリの機能 | はい | いいえ |
| 名前（表示名） | はい | アプリの機能 | はい | いいえ |
| 写真 | はい | アプリの機能 | はい | いいえ |
| その他のユーザーコンテンツ（コメント・キャプション・プロフィールの文・通報の補足・行きたい場所・旅の計画） | はい | アプリの機能 | はい | いいえ |
| メールまたはテキストメッセージ（ストーリーへの返信） | はい | アプリの機能 | はい | いいえ |
| 購入履歴（Pro の定期購入の取引） | はい | アプリの機能 | はい | いいえ |
| おおよその位置 | はい | アプリの機能 | はい | いいえ |
| ユーザーID | はい | アプリの機能 | はい | いいえ |
| デバイスID（プッシュ通知の宛先） | はい | アプリの機能 | はい | いいえ |

**精細な位置（Precise Location）は「いいえ」。** 保存前に約1kmへ丸めている。

**写真**にはアイコン・カバー・ストーリーの写真も入る。**集めないもの**: すれちがいで受け取ったカードと
すれちがった場所（端末の中だけ）・連絡先・健康・閲覧履歴・検索履歴（その場の問い合わせだけで残さない）・
診断（解析やクラッシュの SDK は入れていない）。

**購入履歴を落とさない**（2026-10-16 に足した）。Pro の取引は `POST /user/purchases` でサーバーへ送り、
本人の Pro・サポーターの番号に結びつけて残す（`PurchaseService.swift`）。表と
`PrivacyInfo.xcprivacy` は `ReviewPrivacyTests` が突き合わせる。

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
- [ ] Notes に上の文面を貼った（すれちがいの動画の URL を入れたか）
- [ ] 自動更新の定期購入: App の説明文か、App Store Connect の「使用許諾契約（EULA）」の欄に
      利用規約のリンク（`https://<サイト>/terms`）を入れた（審査 3.1.2）
- [ ] 課金の商品（`pro.monthly`・`pro.yearly`）を**この版と一緒に審査へ出した**
      （版の「App 内課金とサブスクリプション」に追加。初めての商品は版と一緒でないと審査されない）

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
