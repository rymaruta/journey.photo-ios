# 審査メモ（App Review Notes）

App Store Connect の「App Review Information → Notes」に貼る文面と、その根拠。
**審査で落ちる典型を、どこで満たしているか**を1か所にまとめてある。

---

## Notes に貼る文面（2026-11-07 更新・1.1.72 向け）

審査官は英語を読むので、**英語の基本の文面＋Pass の A か B を1つ**を貼る（合わせて 4000 字以内。基本 2446 字・A 710 字・B 1422 字）。
日本語は内容を確かめる用。**審査用アカウントの ID・パスワードはここに書かず**、Demo Account 欄に入れる（【owner が入れる】）。
全体（名前・説明・プライバシー・チェックリスト・返答の下書き）は、別紙の提出パッケージ `appstore-submission-1.1.72` にある。

**背景**: `UIBackgroundModes`（bluetooth-central / bluetooth-peripheral）と `NSBluetoothAlwaysUsageDescription` は
App Store の 1.0.87 に無く、1.1.72 で初めて入る。owner の iPhone は 1 台で、2 台の動画は用意できない。
動画があれば A、無ければ B を貼る。B の根拠は下の表「Pass」の行と `PassRadio.swift` ほか。

### 基本の文面（英語）

> Journey Photo is a personal travel-photo gallery with photo-spot guides for Japan. Browsing, search and the map need no account; posting, stories, likes and comments need an email sign-up. Sign-in info: see the Demo Account fields [OWNER TO FILL IN].
>
> UGC (1.2)
> - Terms prohibiting objectionable content must be accepted on first launch.
> - Photos: "..." menu > Report (7 reasons + note) or Block. Reported/blocked content disappears from that user's screens at once. Unblock: My Page > Settings > Blocked people.
> - Stories: same Report/Block menu in the viewer. Story replies: "..." on each reply > Block / Report (opens an email to our contact address).
> - Reports reach journey.photo.official@gmail.com; we remove violating content.
>
> ACCOUNT
> - Delete account in-app: My Page > Settings > Delete account.
> - No third-party login (own Amazon Cognito, email + password), so Sign in with Apple does not apply (4.8).
>
> PERMISSIONS (asked in context, with purpose strings)
> - Photos: save shots (add-only); choose photos to post; "Trips from photos on this iPhone" (My Page > Trips) shows an explanation card and asks only after "Continue". It reads only capture date, rounded location and identifier; image data is never read or uploaded; the summary stays on device and is deleted on sign-out, account deletion or revoked access. To test: My Page > Trips > Continue (needs geotagged photos taken 50 km+ from home).
> - Location (When In Use): current position on the map only; never sent to our server.
> - Notifications: asked after an explanation; toggle in My Page > Settings > Receive push notifications.
> - Bluetooth: Pass only (see below). Embedded EXIF/GPS is stripped on device before upload; a photo's place is stored rounded to ~1 km.
>
> MUSIC / WEATHER
> - Song stickers and the profile song: search via our server (Apple iTunes Search); playback is a 30-second preview streamed from Apple. No Apple Music sign-in, no MusicKit, no downloads.
> - Pro weather alerts: our server sends only a spot's coordinates (~1 km) to Apple WeatherKit.
>
> IN-APP PURCHASE (3.1.2)
> - "Journey Photo Pro" subscription group: monthly (com.journeyphoto.JourneyPhoto.pro.monthly, 500 JPY) and yearly (...pro.yearly, 5,000 JPY). No free trial. Composition-overlay shooting is free for everyone.
> - Test: My Page > Settings > Pro > Journey Photo Pro > plan > "Start Pro" (Sandbox). Restore is under the plans.
> - Camper coins and parts are earned by posting and cannot be bought.

### 基本の文面（日本語・内容の確認用）

> Journey Photo は日本の撮影スポットの案内つきの、個人運営の旅の写真ギャラリーです。閲覧・検索・地図はログイン不要。投稿・ストーリー・いいね・コメントはメールアドレスでの登録が必要です。審査用のサインイン情報は Demo Account 欄に入れてあります【owner が入れる】。
>
> ユーザー生成コンテンツ（1.2）
> ・初回起動で、不適切な内容を認めない旨を含む規約への同意を求めます。
> ・写真: 各写真の「…」に通報（理由7種＋補足）とブロック。通報・ブロックした内容は、その人の画面からその場で消えます。解除は マイページ→設定→ブロックした人。
> ・ストーリー: 閲覧画面に同じ通報・ブロック。返信は返信の一覧の各行の「…」にブロックと通報（通報は運営の宛先へのメールが開きます）。
> ・通報の宛先は journey.photo.official@gmail.com。運営が確認して消します。設定にも問い合わせ先があります。
>
> アカウント
> ・削除: マイページ→設定→アカウントの削除（アプリ内・確認語の入力つき）。審査用アカウントは削除して構いません。
> ・第三者ログインは無く（自前の Amazon Cognito のメール＋パスワード）、Sign in with Apple は対象外（4.8）。
>
> 権限（いずれも使う場面で尋ね、利用目的の文を付けています）
> ・カメラ: 投稿用の撮影、作例・構図を重ねた撮影。
> ・写真（追加のみ）: 撮った写真を端末に保存。写真の読み取り: 投稿する写真の選択、および「端末の写真から旅の一冊」（マイページ→旅の記録）。先に説明の札を出し、「続ける」を押したときだけ尋ねます（「今はしない」で閉じられ、一部の写真だけの許可でも動きます）。読むのは各写真の撮影日時・位置（丸め）・識別子だけで、画像は読まず送りません。要約は端末の中（iCloud バックアップ外）で、ログアウト・退会・許可の取り消しで消します。試し方: 審査用アカウント→マイページ→旅の記録→続ける→許可（いちばん多く撮った場所から50km以上離れた位置情報つきの写真が要ります）。
> ・位置情報（使用中のみ）: 撮影スポットの地図で現在地と向きを出すためだけ。サーバーへは送りません。
> ・通知: 説明のあとに尋ねます。マイページ→設定→プッシュ通知を受け取る でオン・オフ。
> ・Bluetooth: すれちがい乗車券だけ（別紙の説明）。
> ・写真に埋め込まれた EXIF・GPS は端末で取り除いてから送信し、撮影地は約1kmに丸めて保存します。機種・レンズ・撮影日は写真ページに表示します。
>
> 音楽
> ・ストーリーの曲の札とプロフィールの曲は、題名を当方のサーバー経由で Apple の iTunes Search に問い合わせて探します。再生は Apple から流す30秒の試聴だけで、Apple Music へのログインも MusicKit も使わず、保存もしません。小さな再生器で試聴を操作します。
>
> 天気
> ・Pro の「光と天気の知らせ」は、サーバーが Apple の WeatherKit に撮影スポットの座標（約1km）だけを送って取得します。利用者の現在地は送りません。
>
> App 内課金（3.1.2）
> ・自動更新の定期購入「Journey Photo Pro」: 月額（com.journeyphoto.JourneyPhoto.pro.monthly・500円）、年額（com.journeyphoto.JourneyPhoto.pro.yearly・5,000円）。無料の試用なし。光と天気の知らせ・電波なしで使える旅・Pro マーク・特別な乗車券。構図を重ねて撮る機能は全員無料です。
> ・試し方: マイページ→設定→Pro→Journey Photo Pro→プランを選び「Pro をはじめる」（Sandbox）。復元はプランの下、解約は App Store の定期購入の管理から。案内に値段・期間・自動更新の説明・利用規約とプライバシーポリシーのリンクがあります。
> ・キャンピングカー「とおまわり号」の硬貨・部品は投稿で配られ、購入できません。

### Pass: A（2 台の動画がある場合）

> BACKGROUND BLUETOOTH FOR "PASS" (UIBackgroundModes: bluetooth-central, bluetooth-peripheral)
> Used only for Pass, an optional feature that is OFF by default. Only users who turn it on (My Page > Settings > Pass) exchange a "ticket card" with nearby Journey Photo users, also while the app is in the background: one public photo they chose, a short note, the from/to text and the ticket design. No location or contact details are sent. Turning Pass off stops advertising and scanning.
> Video of Pass working on two iPhones: [OWNER TO FILL IN: video URL]
> Testing needs two iPhones (sign in on both with the two demo accounts, turn Pass on in both, keep them close). Received cards arrive together at 6 PM that day.

### Pass: B（動画が無い場合）

> BACKGROUND BLUETOOTH FOR "PASS" (UIBackgroundModes: bluetooth-central, bluetooth-peripheral)
> We could not record a two-device video, so here is how it works and how to check it.
> - Off by default. It starts only after the user opens My Page > Settings > Pass, reads an explanation card, taps "Turn on", and allows the iOS Bluetooth prompt. Nothing is advertised or scanned before that. Turning it off stops both.
> - Purpose: exchanging a small card with nearby devices running this app, and nothing else (no tracking, analytics, ads or location). One app-specific service UUID; no other accessories.
> - Payload: id of one public photo the user chose, a note (20 chars), from/to text (6 chars), a prefecture-display mark, ticket design. No location, contacts or device identifiers. Not encrypted; this is stated in the Pass screen and Privacy Policy.
> - Received cards and places stay on the device. Each card has Report, Block and Remove.
> Two-iPhone test: sign in with demo account A and B (each has a public photo). On both: My Page > Settings > Pass > pick a ticket > Turn on > allow Bluetooth; keep the phones within a few meters. Cards arrive as one notification at 6 PM that day (allow notifications).
> With one iPhone you can verify the explanation card, the Bluetooth prompt, the off-by-default switch, and that no prompt appears until Pass is turned on. We can also send a single-device screen recording or join a call.

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
| 5.1.1 / 5.1.2 | Bluetooth（すれちがい・2026-10-16） | **既定はオフ**。オンにする前に説明を出し、そこで初めて Bluetooth を尋ねる。電波で渡すのは版・公開写真の id・ひとこと（20字・80 バイトまで）・乗車券の発・着の字（6字まで）・居住地を出すかの印・券面の種類（1 バイト・2026-10-17）だけ（出す設定のときは、受け取った端末が公開プロフィールから居住地の都道府県を引いて出す）。**特性は暗号化しておらず、近くの Bluetooth 機器なら誰でも読める**（写真の id から持ち主も分かる・乗車券を変えるまで同じ値・ブロックした相手にも届きうる）——設定とオンにする前の説明にそのまま書いてある（`PassPrivacyText`）。カードの「…」から通報・ブロック・帳から外すができる（審査 1.2）。受け取ったカード・すれちがった場所（市区町村ほど・0.1 度に丸める）は**端末の中だけ**でサーバーへ送らない（＝収集しない）。地名を引くときは約1kmに丸めた座標だけを Apple の地図（`CLGeocoder`）に渡す（`PassExchange.lookupCoords`）。背景の Bluetooth（UIBackgroundModes）はこのためだけ。位置は撮影地マップで許可済みのときだけ使い、すれちがいからは尋ねない | `PassRadio.swift` / `PassStore.swift` / `PassExchange.swift` |
| 5.1.1 / 5.1.2 | 写真ライブラリ（端末の写真から旅の一冊・2026-10-16） | マイページの旅の記録の説明の札で「続ける」を押したときに初めて尋ねる（ログインしている人だけ読む）。読むのは撮影日時・位置（小数4桁）・識別子だけで画像もサーバーへも送らない。要約は端末の中（バックアップ外）で、ログアウト・退会・許可の取り消しで消す。上限は直近3年・5万枚・500枚ごとに休む。地名は約1kmに丸めて Apple の地図へ一冊1回 | `DeviceTrips.swift` / `DeviceTripLibrary.swift` / `DeviceTripShelf.swift` |
| 1.2 UGC | ストーリー本体の通報・ブロック | ストーリーの閲覧画面の「…」。通報・ブロックした1本はその場で並びから消える | `StoryReelView.swift` / `StoriesRow.swift` |
| 1.2 UGC | ストーリーへの返信の通報・ブロック | 返信の一覧の各行の「…」。**通報はメール**（返信を通報するサーバーの口が無く、写真の通報の口は自分のストーリーを受けない＝400）。宛先は問い合わせと同じ。ブロックは既存の口でその場で一覧から消える | `StoryRepliesSheet.swift` / `ModerationService.storyReplyReportURL` |
| 2.5.4 | 背景で動く機能（Bluetooth・1.1.72 で初めて） | 背景モードは bluetooth-central / bluetooth-peripheral の2つだけで、用途はすれちがい（近くの同じアプリの端末とのカード交換）。既定オフ・説明のあとにオンにした人だけ・オフで広告も走査も止まる。専用のサービス UUID でだけ広告・走査し、他の機器へは接続しない | `PassRadio.swift`（`centralRestoreId`・`startAdvertising`・`scanForPeripherals(withServices:)`）/ `project.yml` |
| 5.1.2 | 曲（ストーリーの曲の札・プロフィールの曲） | 題名を当方のサーバー経由で Apple の iTunes Search に問い合わせ、再生は Apple から流す30秒の試聴だけ。Apple Music のログイン・MusicKit なし | `DiscoveryService.swift` / `MusicPreviewPlayer.swift` |
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
すれちがった場所（端末の中だけ）・端末の写真の一冊の要約（写真の撮影日時と位置・端末の中だけ。旅の名前を引く約1kmの位置は Apple の地図へ渡すだけで、こちらは受け取らない）・連絡先・健康・閲覧履歴・検索履歴（その場の問い合わせだけで残さない）・
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
- [ ] Notes に上の文面を貼った（Pass は A か B のどちらか1つ。A なら動画の URL を入れたか）
- [ ] 自動更新の定期購入: App の説明文か、App Store Connect の「使用許諾契約（EULA）」の欄に
      利用規約のリンク（`https://<サイト>/terms`）を入れた（審査 3.1.2）
- [ ] 課金の商品（`pro.monthly`・`pro.yearly`）を**この版と一緒に審査へ出した**
      （版の「App 内課金とサブスクリプション」に追加。初めての商品は版と一緒でないと審査されない）

### 想定される区分

**12+ を想定（旧基準）。Apple の新しい質問票（4+/9+/13+/16+/18+・2025年）では UGC とメッセージを「あり」にすると 13+ 以上になる見込みで、画面の結果が正（2026-11-07・未確認）。** 利用者が作った内容を載せるため（Infrequent/Mild と回答する
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
