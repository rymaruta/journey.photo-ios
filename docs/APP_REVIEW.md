# 審査メモ（App Review Notes）

App Store Connect の「App Review に関する情報」に入れる文と、その根拠。
**審査で落ちる典型を、どこで満たしているか**を1か所にまとめてある。
2026-11-15 に 1.1.91（main a65201d）の中身で書き、2026-11-22 に 1.1.118（main 84807f3、`testflight/1.1.118`）に合わせて見直した（札 #604）。
2026-11-22 owner 決定: **審査用アカウントは1つ（A）だけ**。相手役は owner の今のアカウント（審査の人には渡さない）。
押す所の絵は App Store の Artifact（https://claude.ai/artifact/DViFKiSAyfKaQiW1ayZ1TT）。

---

## Notes に貼る文面

審査官は英語を読むので、**貼るのは英語**（3,895字。上限 4,000 字。Python の `len()` で数えた）。日本語は owner が中身を確かめる用。
2026-11-23 に AI の行を同意の画面（1.1.119）に合わせ、2026-11-24 にログインの行を Apple と Google のある 1.2.x に合わせた。
2026-11-26 に、申請し直す前に直した: 通知の尋ね方（初めての投稿かフォローのあとに説明とボタン1つ）、Sandbox ではサポーターのバッジが付かないこと、
Sandbox の Apple ID の定期購入が買ったアカウントに残ること、曲の試聴（iTunes Search API の30秒と Apple Music へのリンク）、
AI の答えと旅行プランの「この答えを報告」。字数を空けるため、ほかの行を短くした（言っていることは同じ）。
🔴 曲の試聴の行と「この答えを報告」の行は、iOS の別の担当が今足している機能。**その版が出る前に貼らない**（出す版に入っているかを確かめてから）。
ID とパスワードはここに書かず、「サインイン情報」の欄に入れる（下の「審査用アカウント」）。Notes に書き足すものは無い。

### 英語（貼る）

```
Journey Photo is a social network for travel photos with a guide to about 4,600 sightseeing spots. Browsing, search and the map need no account; posting, stories, likes, comments and messages need an account (email, Apple or Google). The demo account is in the sign-in fields. It has one public photo and mutually follows an account run by our team, which sent it a message and is in its trip plan (one chat message). Feel free to report or block that account.

USER-GENERATED CONTENT (1.2)
- Terms banning objectionable content are accepted on first launch.
- Photos and comments: "..." > Report (8 reasons + note) or Block. Reported or blocked content disappears for the reporter at once. Unblock: Settings > Blocked people.
- Stories: Report and Block in the viewer; "..." on each story reply.
- Profiles: "..." > Report or Block.
- Messages (1:1, Home top right): in a conversation, "..." > Report or Block. Reports include the latest 20 messages. Before a request is accepted: 3 text messages max, no links or photos.
- Trip plan chat (members invited by link): long-press a message > Report or Block. Members can leave.
- Pass cards: Report, Block and Remove on each card.
- Reports reach journey.photo.official@gmail.com; we review them within 24 hours and remove violations.

ACCOUNT
- Delete account: My Page > Settings > Delete account. You may delete the demo account.
- Sign-in: email, Google, or Sign in with Apple, shown next to Google (4.8).

PERMISSIONS (asked in context)
- Camera: posts, stories, composition overlay, profile QR codes.
- Microphone: story video sound only, asked when recording.
- Photos: add-only to save; read to pick photos and for "trips from photos" (asked after an explanation). Only date, rounded place and ID are read on device; images are not uploaded.
- Location (When In Use): current position on the map, never sent to us. EXIF/GPS is stripped before upload; places are rounded to ~1 km.
- Notifications: After the first post or follow, a short explanation appears with one button that leads to the iOS prompt; declining keeps the app fully usable.

BACKGROUND BLUETOOTH FOR "PASS" (bluetooth-central, bluetooth-peripheral)
- Optional, OFF by default. Starts only after My Page > Settings > Pass, an explanation with a single "Continue" button and the iOS prompt. While on, swapping continues with the app closed. Turning it off stops it.
- Only swaps a small card with nearby users of this app (one service UUID): id of one chosen public photo, a short note, from/to text, ticket design, prefecture on/off. No location, contacts or device IDs.
- Swapping needs two iPhones and two accounts; one iPhone shows the explanation and prompt. A screen recording of two iPhones swapping cards can be sent on request.

MUSIC IN STORIES
- Song search and 30-second previews use the iTunes Search API; each song links to Apple Music. Full tracks are never played.

AI (TRIP PLANS, ASK AI)
- On device with Apple Intelligence where supported. Otherwise, for Pro users, text goes to our servers and an AI provider acting for us, only after explicit permission before the first send (withdraw in Settings). Daily and monthly limits apply.
- Every AI answer and AI trip plan has "Report this answer".

IN-APP PURCHASE (3.1.2)
- Subscription group "Journey Photo Pro": monthly (com.journeyphoto.JourneyPhoto.pro.monthly, 500 JPY) and yearly (com.journeyphoto.JourneyPhoto.pro.yearly, 5,000 JPY). No free trial.
- Test: My Page > Settings > Pro > pick a plan > "Start Pro" (Sandbox). Restore is under the plans.
- Supporter badge is granted for production purchases only; in Sandbox, Pro features work but the badge is not shown.
- A subscription bought with a sandbox Apple ID stays with the account that bought it; after deleting the demo account, please use a different sandbox Apple ID to test Pro.
- Coins and trunk parts cannot be bought (earned by posting).
```

### 日本語（確かめる用）

```
Journey Photo は、約4,600か所の観光スポットの案内がついた、旅の写真の SNS です。閲覧、検索、地図はログイン不要。投稿、ストーリー、いいね、コメント、メッセージはアカウントが必要です（メールアドレス、Apple、Google のどれかでの登録）。審査用アカウントはサインイン情報の欄にあります。公開の写真が1枚あり、運営のアカウントと互いにフォローしています。運営のアカウントからメッセージが1通届いていて、審査用アカウントの旅行プランに仲間として入り、会話に1通あります。そのアカウントは通報やブロックを試してかまいません。

ユーザー生成コンテンツ（1.2）
- 初回起動で、不適切な内容を認めない旨を含む規約への同意を求めます。
- 写真とコメント：「…」から通報（理由8種と補足）、ブロック。通報、ブロックした内容は、その人の画面からその場で消えます。解除は設定 → ブロックした人。
- ストーリー：閲覧画面に通報とブロック。ストーリーへの返信は各行の「…」。
- プロフィール：「…」から通報、ブロック。
- メッセージ（1対1、ホームの右上）：会話の「…」から通報、ブロック。通報には直近20通が付きます。承認されるまでは、文字3通までで、リンクと写真は送れません。
- 旅行プランの会話（招待リンクで加わった人）：1通を長押しして通報、ブロック。仲間はプランから抜けられます。
- すれちがいのカード：各カードに通報、ブロック、帳から外す。
- 通報の宛先は journey.photo.official@gmail.com。24時間以内に確かめ、違反した内容とアカウントを消します。

アカウント
- 削除：マイページ → 設定 → アカウントの削除。審査用アカウントは消してかまいません。
- ログイン：メールアドレス、Google、Apple でサインイン。Apple は Google の隣に出しています（4.8）。

権限（使う場面で尋ねます）
- カメラ：投稿、ストーリー、作例を重ねた撮影、プロフィールの QR。
- マイク：ストーリーの動画の音声だけ。撮るときに尋ねます。
- 写真：撮った写真の保存（追加のみ）。読み取りは、投稿する写真の選択と「端末の写真から旅」（説明のあとで尋ねる）。端末の中で撮影日時、丸めた位置、識別子だけを読み、画像は送りません。
- 位置情報（使用中のみ）：地図の現在地。サーバーへは送りません。写真の EXIF と GPS は送る前に取り除き、場所は約1kmに丸めます。
- 通知：初めて投稿したとき、またはフォローしたときに、短い説明とボタン1つを出し、押すと iOS の確認が出ます。断ってもアプリはすべて使えます。

すれちがい乗車券の背景の Bluetooth（bluetooth-central、bluetooth-peripheral）
- 任意で、初期設定はオフ。マイページ → 設定 → すれちがい乗車券で説明を読み、ボタン1つの「続ける」と iOS の確認のあとで初めて動きます。オンの間は、アプリを閉じていても交換します。オフにすると止まります。
- 同じアプリの近くの端末と小さなカードを交換するだけ（専用のサービス UUID）。中身は、選んだ公開写真1枚の id、ひとこと、発と着の字、券面の種類、都道府県を出すかの印。位置、連絡先、端末の識別子は送りません。
- 交換には iPhone が2台とアカウントが2つ要ります。1台で、説明と確認は見られます。2台で交換する画面収録は、求められたら送ります。

ストーリーの曲
- 曲の検索と30秒の試聴は iTunes Search API を使います。各曲に Apple Music へのリンクを出します。曲の全体は流しません。

AI（旅行プラン、AI に頼む）
- 対応する iPhone では端末の AI（Apple Intelligence）で動きます。それ以外の iPhone の Pro の人は、初めて送る前にはっきり許可を求め、許した人だけ文をサーバーと委託先の AI に送ります（設定で取り消せます）。1日と月の回数の上限があります。
- AI の答えと AI の旅行プランのそれぞれに「この答えを報告」があります。

App 内課金（3.1.2）
- 定期購入「Journey Photo Pro」：月額（com.journeyphoto.JourneyPhoto.pro.monthly、500円）、年額（com.journeyphoto.JourneyPhoto.pro.yearly、5,000円）。無料の試用なし。
- 試し方：マイページ → 設定 → Pro → プランを選び「Pro をはじめる」（Sandbox）。購入を復元はプランの下。
- サポーターのバッジは本番の購入だけに付きます。Sandbox では Pro の機能は使えますが、バッジは出ません。
- Sandbox の Apple ID で買った定期購入は、買ったアカウントに残ります。審査用アカウントを消したあとに Pro を試すときは、別の Sandbox の Apple ID を使ってください。
- 旅のトランクの硬貨と部品は購入できません（投稿で配られます）。
```

### 入ったら足す文

サーバーの別の担当が、投稿の前に言葉を判定する仕組みを足している（2026-11-26 時点で本番に無い）。
**本番に出たら**、上の「英語（貼る）」の「USER-GENERATED CONTENT (1.2)」の1行目の下に、次の1行を足す
（日本語の方にも同じ意味の行を足す）。判定するのが投稿とコメントのどちらまでかは、入った仕組みに合わせて直す。
足しても 4,000 字に収まることは `Tools/test_asc_submit.py` が確かめる。

```
- Post and comment text is checked on our server before publishing; abusive words are blocked.
```

日本語: 「投稿とコメントの文は、載せる前にサーバーで確かめ、ひどい言葉は載せません。」
足したら、下の「ガイドライン別の対応」の「不適切な内容を出さない仕組み」の行の「事前の審査は無い」も直す。

### すれちがいの動画

すれちがいの交換は iPhone が2台要り、審査の人は試せない。**owner が2台で交換する画面収録を撮って、URL を入れる。**
撮ったら、「英語（貼る）」の「A screen recording of two iPhones swapping cards can be sent on request.」を
「A screen recording of two iPhones swapping cards: <video URL>」（<video URL> は撮った動画の URL）に替える（日本語の方も同じように替える）。
URL が入るまでは今の一文のままにする（無い URL を貼らない）。

**「24時間以内に確かめる」は owner の運用の約束になる**（ガイドライン 1.2 は通報への速い対応を求める）。
守れないなら、貼る前にこの一文を「promptly」「速やかに」に直す。

## 審査用アカウント

**owner が本番で作る。** このリポジトリ、Artifact、札、会話には、メールアドレスもパスワードも書かない。
入れる先は App Store Connect の「サインイン情報」の欄だけ。

### 用意する（1つ。A。2026-11-22 owner 決定）

- **A は、owner が持っている本番のテスト用アカウントを使う。新しく作らない。** パスワードはどこにも書かない
  （App Store Connect のサインイン情報の欄に owner が入れる）
- **相手役は owner の今のアカウント。** 審査の人には渡さない（ID もパスワードも Notes に書かない）
- 審査官はアカウントの削除も試すことがある。A は消されてもよいアカウントにしておく（owner の今のアカウントは渡さないので消されない）

1. A で公開の写真を1枚投稿する（自分で撮った風景。人の顔、他社のロゴは写さない）。空のマイページだと「投稿を確かめられない」と差し戻されることがある
2. A と owner のアカウントで互いにフォローする（メッセージは、相手をフォローしている人だけが始められる）
3. owner のアカウントから A へメッセージを1通送る（A の側で承認しておくと、写真とリンクも試せる）
4. A で旅行プランを1つ作り、招待リンクで owner のアカウントを仲間にして、会話に1通書く（旅行プランの会話の通報を試せるように）

### App Store Connect に入れる

- 「App Review に関する情報」→「サインインが必要です」にチェック
- ユーザー名に A のメール、パスワードに A のパスワード（欄は1組。Notes に書き足すものは無い）
- 連絡先の電話番号は国番号から（`+81 90 1234 5678` の形。先頭の 0 を取る）

### 申請のあと

- 審査の人は owner のアカウントを通報、ブロックすることがある（Notes で許している）。
  **審査が終わったら、A でログインし、マイページ → 設定 → ブロックした人 から owner のアカウントのブロックを外す**（通報は運営の宛先に届くので、確かめて閉じる）
- 審査官に消されたら、次の申請の前に A を用意し直す（上の 1〜4）
- 承認されたら、A のパスワードを替える

## ガイドライン別の対応（2026-11-15 に a65201d で確かめた）

重い順。「足りない」は 1.1.91 には無い。この表は a65201d で確かめたもので、1.1.118 では行ごとに確かめ直していない（2026-11-22）。

| 条項 | 要求 | このアプリでの答え | 合否 | 根拠（a65201d） |
|---|---|---|---|---|
| 4.8 Sign in with Apple | 他社のログインを使うなら、同じ水準のログインも出す | **満たす。** 1.2.x から Google のログインがあり、同じ画面に Apple でサインインを並べている。Apple は名前とメール（非公開の中継のアドレスでもよい）だけを頼み、広告のために集めない。本番の `/auth/apple/status` と `/auth/google/status` はどちらも `available: true`（2026-11-24 に curl で確かめた） | 合っている | `Features/Auth/SignInView.swift`、`Services/AppleSignInService.swift`、`Services/GoogleSignInService.swift`、`Services/FederatedSignIn.swift` |
| 1.2 UGC | 規約への同意 | 初回起動時の同意画面 | 合っている | `Features/Legal/LegalGateView.swift`、`App/RootView.swift` |
| 1.2 UGC | 通報 | 写真、コメント、ストーリー、ストーリーへの返信、プロフィール、メッセージ、**旅行プランの会話（1.1.90 で足した、#597）**、すれちがいのカード。理由は8種 | 合っている | `ReportSheet` を使う画面（Gallery、PhotoDetail、StoryViewer、DMConversation、DMRequests、TripShareViews、PassBook、PassViewer）、`ModerationService.ReportReason`。本番の `POST /trip-share/{id}/report` は未ログインで 401（口がある）を 2026-11-15 に確かめた |
| 1.2 UGC | ブロック | 通報と同じ所とプロフィールから。解除は設定 | 合っている | `ModerationService.swift`、`BlockedUsersView.swift` |
| 1.2 UGC | 不適切な内容を出さない仕組み | 通報とブロックをしたものは、押した人の一覧から**端末の側でその場で落とす**。公開の写真一覧はビルド時に焼いた静的 JSON なので、運営が消したものはサイトの作り直しで消える | 合っている（事前の審査は無い） | `PublicGalleryService.setHidden`、`BlockFilter` |
| 1.2 UGC | 連絡先 | 設定の「問い合わせ」。サイトの規約と同じ宛先 | 合っている | `LegalConsent.contactEmail` |
| 5.1.1(v) | アプリの中でアカウントを削除 | 設定 → アカウントの削除（確認語の入力つき）。サーバーの `DELETE /user/account` のあと Cognito の利用者も消す。Pro の解約は App Store でと案内する | 合っている | `DeleteAccountView.swift`、`AuthStore.swift`、`AuthGateway.deleteUser`。本番の口は未ログインで 401 |
| 5.1.1 | 要らないログインを求めない | 閲覧、検索、地図、観光スポットはログイン不要 | 合っている | `RootView.swift` |
| 5.1.2 | App のプライバシーと実際の取り方 | 下の表（`PrivacyInfo.xcprivacy` の10種と同じ）。**判断が分かれる所が1つ**（意見に添える記録） | ほぼ合っている | 下の「判断が分かれる所」 |
| 5.1.2 | プライバシーポリシー | 2026-11-15 版で、メッセージの写真と観光スポット、ストーリーの動画とマイク、旅行プランの会話の通報、意見に添える記録、行った県を足した | 合っている（本番に出したあと） | journey.photo-web #650（本番）、#651（develop） |
| 5.1.1 / 5.1.2 | 写真の権限 | 選ぶ、保存（追加のみ）、端末の写真から旅（説明の札の「続ける」で初めて尋ねる）。説明文は用途を3つとも書いている | 合っている | `project.yml` の `NSPhotoLibraryUsageDescription`、`NSPhotoLibraryAddUsageDescription`、`DeviceTrips.swift` |
| 5.1.1 / 5.1.2 | 位置 | 使用中のみ。撮影地マップの現在地、許可済みのときだけ観光スポットを近い順、すれちがいの市区町村名（約1kmに丸めて Apple の地図へ）。サーバーへは送らない。説明文にこの3つを書いてある | 合っている | `NSLocationWhenInUseUsageDescription`、`CurrentLocation.swift`、`PassRadio.swift` |
| 5.1.1 / 4.5.4 | 通知 | 起動時には尋ねない。初めての投稿かフォローのあとに短い説明とボタン1つを出し（`PushPrimerStore.reachedOut`）、押したときに `requestAuthorization`。通知の画面、設定、すれちがい、光の知らせで「受け取る」を押したときも同じ。断っても使える | 合っている | `PushCenter.enable`、呼ぶのは `PushPrimerView`、`NotificationsView`、`SettingsView`、`PassSettingsView`、`LightAlertSettingsRows` |
| 5.1.1 | マイク | ストーリーの動画を撮るときだけ | 合っている | `StoryCameraView.swift`（`AVCaptureDevice.requestAccess(for: .audio)`）、`NSMicrophoneUsageDescription` |
| 2.5.4 | 背景の Bluetooth | すれちがい乗車券だけ。既定はオフ。差し戻されたときの返答は Artifact の 3-4 | 合っている（差し戻しの心配は残る） | `PassRadio.swift`、`UIBackgroundModes` |
| 3.1.2 | 自動更新の定期購入 | 値段、期間、自動更新の一文、利用規約とプライバシーポリシーのリンク、購入の復元 | 合っている | `PaywallView.swift`、`ProPaywallText` |
| 2.1 | プライバシーマニフェスト | 収集10種と、理由の要る API（UserDefaults: CA92.1、ディスクの空き: 85F4.1、起動からの時間: 35F9.1） | 合っている | `Resources/PrivacyInfo.xcprivacy` |
| 2.3.7 | 名前とキーワードに他社の名前を入れない | 入れていない | 合っている | `docs/APP_STORE_METADATA.md` |
| 2.5.1 | 非公開 API を使わない | 依存は Amplify Swift だけ | 合っている | `project.yml` |

## App Store Connect の「App のプライバシー」

`PrivacyInfo.xcprivacy` と**同じ内容**を答える（`ReviewPrivacyTests` が表とマニフェストを突き合わせる）。どれも「トラッキング: いいえ」。

| データ | 収集する | 用途 | 本人と紐づく | トラッキング |
|---|---|---|---|---|
| メールアドレス | はい | アプリの機能 | はい | いいえ |
| 名前（表示名） | はい | アプリの機能 | はい | いいえ |
| 写真 | はい | アプリの機能 | はい | いいえ |
| その他のユーザーコンテンツ（コメント、キャプション、プロフィールの文、通報の補足、行きたい場所、旅行プラン、旅のトランク、意見の本文） | はい | アプリの機能 | はい | いいえ |
| メールまたはテキストメッセージ（メッセージ、旅行プランの会話、ストーリーへの返信） | はい | アプリの機能 | はい | いいえ |
| 購入履歴（Pro の定期購入の取引） | はい | アプリの機能 | はい | いいえ |
| おおよその位置 | はい | アプリの機能 | はい | いいえ |
| ユーザーID | はい | アプリの機能 | はい | いいえ |
| デバイスID（プッシュ通知の宛先） | はい | アプリの機能 | はい | いいえ |
| 製品の操作（観光スポットの「行きたい」の数は端末ごとのでたらめな番号で、本人と紐づかない。AI で旅行プランを作った回数と AI に頼んだ回数（日と月）は本人ごと、2026-11-15 札 #621、2026-11-20 札 #652） | はい | アプリの機能 | はい | いいえ |

**写真**にはアイコン、カバー、ストーリーの写真と動画（音声を含む）、意見に添えた写真も入る。
おおよその位置は撮影地（保存前に約1kmへ丸める）。**精細な位置は「いいえ」**。広告 ID は使わない。

**集めないもの**（端末の中だけ）: 端末の写真から作る旅の要約、行った県の記録、すれちがいのカードと場所、現在地、
MetricKit の診断（端末のログに出すだけ）、連絡先、健康、閲覧履歴、検索履歴。
AI で旅行プランを作るとき、AI に頼むときに書いた文も**集めない**（AI に頼むの会話の控えは端末の中だけ、`AskHistoryStore`。端末の AI では端末の外へ出さない。サーバーの AI では読んで答えるだけで残さず、
Amazon Bedrock の記録もしていない。Apple の「集める」は、答えに要る間より長く手にできる形で送ること）。

### 判断が分かれる所（推奨つき）

1. **意見に添える記録（1.1.91）。** 「意見を送る」で、前回途中で終わった記録（段の名前、メモリ量、版、時刻）、MetricKit のクラッシュの要約、
   前回送れなかった理由を本文に添えて送る（既定は添える、送る前に字で見せる、外せる。`ExitTrail`、`FeedbackSheet`）。
   **推奨: 申告しない。** Apple の「任意の開示」の決まり（たまにしか集めない、主な機能ではない、本人が中身を見て自分で送る、追跡や広告に使わない）に当たる、
   意見の欄の添え書きだから。安全側に倒すなら「診断 > クラッシュデータ」を足し、次の版で `PrivacyInfo.xcprivacy` にも同じものを足す（足すのは表とマニフェストを同時に）
2. **ストーリーの動画の音声。** 推奨: 「写真またはビデオ」に含める（Apple の「オーディオデータ」は声や録音を指す）
3. **ストーリーの「見た人」の記録。** 推奨: 「その他のユーザーコンテンツ」の範囲として足さない

## 年齢制限の質問票（App Store Connect でそのまま答える）

Apple の新しい質問票（区分は 4+、9+、13+、16+、18+）。**画面に出る問いが正**。配信中の 1.0.87 は 4+ だった。

| 質問 | 答え |
|---|---|
| 暴力的な内容（漫画、空想、現実的） | なし |
| 性的な内容、ヌード | なし |
| 冒涜的、下品なユーモア | なし |
| アルコール、タバコ、薬物 | なし |
| 恐怖、ホラー | なし |
| 医療、医学情報 | なし |
| 賭博、コンテスト | なし |
| ルートボックス（中身の分からない有料のくじ）が聞かれたら | なし（カプセルの機械は投稿でもらう硬貨だけで回り、お金では買えない） |
| **ユーザー生成コンテンツ** | **あり**（写真、コメント、ストーリー、メッセージ。通報、ブロック、規約の同意あり） |
| **メッセージとチャット** | **あり**（メッセージ、旅行プランの会話、ストーリーへの返信） |
| 無制限のウェブアクセス | なし（アプリの中にブラウザは無い。リンクは外の Safari で開く） |
| 広告 | なし |
| 年齢の確かめ、保護者の機能 | なし |

> ⚠️ **UGC とメッセージを「なし」にすると通らない。** 写真とコメントを載せる時点で UGC。隠すと差し戻しでは済まず、信頼を落とす。
> 最終の区分は画面の結果で分かる（確かめていない）。結果をこの節に書き足す。

## 提出前の最終確認（ここを全部緑にしてから出す）

**審査に出すのは Actions の「App Store submit」（`.github/workflows/asc-submit.yml`・2026-11-25 札 #604）。**
先に `ios-testflight.yml` を `storeShots=true`・`ascVersion=<版>`・`ascApply=true` で流して画面写真を入れ、
`asc-submit.yml` を `apply=false`（下見）→ `apply=true` で流す。新機能の説明・ビルド・上の Notes・段階的リリースを入れて審査に出す。
公開中の版には書かない。審査用のアカウントのパスワードは App Store Connect の値を残す（上書きしない）。
新機能の説明の文は `Tools/asc-submit.py` の `WHATS_NEW`。

- [ ] ビルドは、出すときの最新の TestFlight の版（2026-11-23 時点は `testflight/1.1.119`、df0eea4）。App Store Connect の「バージョン」をその版にし、同じ版のビルドを選ぶ
- [ ] TestFlight の実機で一巡（AI で旅行プラン、AI に頼む、投稿、ストーリーの動画、メッセージ、旅行プランの会話の通報、通報、ブロック、退会、機内モード）
- [ ] 画面写真を2組（大型ディスプレイ＝6.9インチ 1320×2868 と、中型ディスプレイ 1206×2622。中型は最低1枚が必須）。Mac の CI の `storeShots` で、見本の表示（`-JPStoreDemo`）だけで撮り、非公開の S3 から取り出す（`docs/APP_STORE_METADATA.md` の「作り方」）。本番の他の利用者の写真と他の作者の作例を1枚も入れない（画像は同梱の CC0 の作例写真だけ）。人の顔、他社のロゴも入れない
- [ ] 審査用アカウント A（owner の本番のテスト用アカウント）で写真を1枚投稿、owner のアカウントと互いにフォロー、owner から A にメッセージ1通、A の旅行プランに owner を仲間に入れて会話に1通（上の手順）
- [ ] App のプライバシーの回答が `PrivacyInfo.xcprivacy` と一致（上の表）
- [ ] 年齢制限の質問票（上の表）
- [ ] 名前、サブタイトル、説明、キーワード、最新情報、サポート URL、プライバシーポリシー URL、カテゴリ（`docs/APP_STORE_METADATA.md`）
- [ ] Web のプライバシーポリシーが 2026年11月15日版になっている（journey.photo-web #650 が本番に出た）
- [ ] Notes に上の英語を貼った（すれちがいの動画を撮ったら、上の「すれちがいの動画」のとおり URL の一文に替える）
- [ ] `asc-submit.yml` の下見（`apply=false`）に、利用規約のリンクか EULA、プライバシーポリシーの URL、定期購入でない課金の商品、販売をやめた定期購入の警告が出ていない
- [ ] 自動更新の定期購入: 説明文か App Store Connect の「使用許諾契約（EULA）」の欄に利用規約のリンク（`https://journey-photo.com/terms`）を入れた（審査 3.1.2）
- [ ] 課金の商品（`pro.monthly`、`pro.yearly`）を**この版と一緒に審査へ出した**（版の「App 内課金とサブスクリプション」に追加。まだ一度も審査を通っていないなら、版と一緒でないと審査されない）
- [ ] 輸出コンプライアンスは `ITSAppUsesNonExemptEncryption: false` なので聞かれない。広告識別子は「いいえ」
- [ ] リリースの方法は**段階的リリース（7日）**を推奨（1.0.87 から大きく変わるため、落ちや重さが出たら止められる）
- [ ] 「審査に出す」は owner が押す

## owner にお願いすること

1. ~~アプリの名前を決める~~ **2026-11-22 決定**（`Journey Photo 旅の写真と観光スポット`、英語 `Journey Photo: Travel Spots`、サブタイトル `旅を見つけて、撮って、みんなと話す`）
2. **審査用アカウント A を用意する**（上の手順。owner の本番のテスト用アカウントを使う。パスワードはどこにも書かない）
3. ~~App Store 用の原寸の画面写真の撮り方を決める~~ **2026-11-22 決定**: Mac の CI で撮り、非公開の S3 に置く（`storeShots`、3日で消える）。
   🔴 ただし、いまの材料は本番の他の利用者の写真で描くので**ストアに使えない**。見本のデータだけで描く仕組みが要る（`docs/APP_STORE_METADATA.md` の「写真の権利」）
4. 「24時間以内に確かめる」の約束でよいか
5. App Store Connect で、掲載情報、App のプライバシー、年齢の質問票、審査の情報を入れて「審査に出す」を押す
6. 審査のあと、A で owner のアカウントのブロックを外す（上の「申請のあと」）

## 落ちやすい点として残っているもの

- **背景の Bluetooth（2.5.4）。** すれちがいの説明を求められることがある。返答の下書きは Artifact の 3-4
- **投稿が少ないと「中身が薄い」と見られることがある。** 審査用アカウントで写真を投稿しておく
- **すれちがいは iPhone が2台ないと試せない。** 審査用アカウントは1つなので、交換は試せない。owner が2台で画面収録を撮り、URL を Notes に入れる（上の「すれちがいの動画」）
- **他社の AI にデータを渡すこと（5.1.2(i)、2025-11 の改定）。** 1.1.119 で、サーバーの AI に初めて送る前に同意の画面（明示の許可）を出す形にした（`AIServerConsent`、PR #702）。設定で取り消せる。2026-11-23 owner 判断で、AI に頼むと旅行プランの画面の注記（「サーバーに送信し、委託先の AI で処理します」）は外した。送ることの知らせはこの同意の画面で行う（画面に常に出る注記は「※AI の回答は間違えることがあります」だけ）
