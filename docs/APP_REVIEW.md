# 審査メモ（App Review Notes）

App Store Connect の「App Review に関する情報」に入れる文と、その根拠。
**審査で落ちる典型を、どこで満たしているか**を1か所にまとめてある。
2026-11-15 に、申請する 1.1.91（main a65201d、`testflight/1.1.91`）の中身で書き直した（札 #604）。
押す所の絵は App Store の Artifact（https://claude.ai/artifact/DViFKiSAyfKaQiW1ayZ1TT）。

---

## Notes に貼る文面

審査官は英語を読むので、**貼るのは英語**（3,550字ほど。B の行を足しても上限 4,000 に収まる）。日本語は owner が中身を確かめる用。
ID とパスワードはここに書かず、「サインイン情報」の欄に入れる（下の「審査用アカウント」）。

### 英語（貼る）

```
Journey Photo is a social network for travel photos with a guide to about 3,900 sightseeing spots. Browsing, search and the map need no account; posting, stories, likes, comments and messages need an email sign-up. Demo account A is in the sign-in fields; demo account B is at the end of these notes. A and B follow each other, so you can test Messages, trip plan chat and Pass.

USER-GENERATED CONTENT (1.2)
- Terms prohibiting objectionable content must be accepted on first launch.
- Photos and comments: "..." > Report (8 reasons + note) or Block. Reported or blocked content disappears from the reporter's screens at once. Unblock: My Page > Settings > Blocked people.
- Stories: Report and Block in the viewer. Story replies: "..." on each reply.
- Profiles: "..." > Report or Block.
- Messages (1:1, with people you follow): open from the chat bubble at the top right of Home, or "Message" on a profile. In a conversation, "..." > Report or Block. A report sends us a copy of the latest 20 messages. Until accepted, a sender can send only 3 text messages and no links or photos.
- Trip plan chat (people invited by link): long-press a message > Report or Block. A report sends us a copy of the latest 20 messages. Any member can leave the plan.
- Pass cards: Report, Block and Remove on each card.
- Reports reach journey.photo.official@gmail.com. We review them within 24 hours and remove violating content and accounts.

ACCOUNT
- Delete account in-app: My Page > Settings > Delete account. You may delete the demo accounts.
- No third-party or social login. Sign-in is our own Amazon Cognito with email and password only, so Sign in with Apple (4.8) does not apply.

PERMISSIONS (asked in context, with purpose strings)
- Camera: posting, story capture, composition overlay, scanning profile QR codes.
- Microphone: sound for story videos only, asked when recording a video.
- Photos: add-only to save shots; read access to pick photos and for "trips from photos on this iPhone" (My Page > Trips, asked only after an explanation and "Continue"). Only capture date, rounded location and identifier are read on device; image data is never uploaded.
- Location (When In Use): current position on the photo map. Never sent to our server. EXIF/GPS is stripped on device before upload; a photo's place is stored rounded to about 1 km.
- Notifications: asked only after the user taps to turn them on.

BACKGROUND BLUETOOTH FOR "PASS" (bluetooth-central, bluetooth-peripheral)
- Optional and OFF by default. It starts only after My Page > Settings > Pass, an explanation, "Turn on" and the iOS Bluetooth prompt. Turning it off stops advertising and scanning.
- Used only to swap a small card with nearby devices running this app (one app-specific service UUID). Payload: id of one public photo the user chose, a short note, from/to text, ticket design, and whether to show the prefecture from the profile. No location, contacts or device identifiers.
- Testing needs two iPhones: sign in with A and B, turn Pass on in both, keep them close. One iPhone shows the explanation, prompt and off-by-default switch. A screen recording (video URL) can be provided on request.

IN-APP PURCHASE (3.1.2)
- Subscription group "Journey Photo Pro": monthly (com.journeyphoto.JourneyPhoto.pro.monthly, 500 JPY) and yearly (com.journeyphoto.JourneyPhoto.pro.yearly, 5,000 JPY). No free trial.
- Test: My Page > Settings > Pro > pick a plan > "Start Pro" (Sandbox). Restore is under the plans.
- Travel trunk coins and parts are earned by posting and cannot be bought.
```

### 日本語（確かめる用）

```
Journey Photo は、約3,900か所の観光スポットの案内がついた、旅の写真の SNS です。閲覧、検索、地図はログイン不要。投稿、ストーリー、いいね、コメント、メッセージはメールアドレスでの登録が必要です。審査用アカウント A はサインイン情報の欄に、B はこのメモの最後にあります。A と B は互いにフォローしているので、メッセージ、旅行プランの会話、すれちがい乗車券を試せます。

ユーザー生成コンテンツ（1.2）
- 初回起動で、不適切な内容を認めない旨を含む規約への同意を求めます。
- 写真とコメント：「…」から通報（理由8種と補足）、ブロック。通報、ブロックした内容は、その人の画面からその場で消えます。解除はマイページ → 設定 → ブロックした人。
- ストーリー：閲覧画面に通報とブロック。ストーリーへの返信は各行の「…」。
- プロフィール：「…」から通報、ブロック。
- メッセージ（1対1、フォローしている人と）：ホームの右上の吹き出し、またはプロフィールの「メッセージ」から。会話の「…」から通報、ブロック。通報すると直近20通の写しが運営に届きます。承認されるまで、送れるのは文字3通までで、リンクと写真は送れません。
- 旅行プランの会話（招待リンクで加わった人）：1通を長押しして通報、ブロック。通報すると直近20通の写しが運営に届きます。誰でもプランから抜けられます。
- すれちがいのカード：各カードに通報、ブロック、帳から外す。
- 通報の宛先は journey.photo.official@gmail.com。24時間以内に確かめ、違反した内容とアカウントを消します。

アカウント
- 削除：マイページ → 設定 → アカウントの削除（アプリ内）。審査用アカウントは消してかまいません。
- 他社のログインやソーシャルログインは無く、自前の Amazon Cognito のメールとパスワードだけなので、Sign in with Apple（4.8）は当たりません。

権限（使う場面で尋ね、利用目的の文を付けています）
- カメラ：投稿、ストーリーの撮影、作例を重ねた撮影、プロフィールの QR の読み取り。
- マイク：ストーリーの動画の音声だけ。動画を撮るときに尋ねます。
- 写真：撮った写真の保存（追加のみ）。読み取りは、投稿する写真の選択と「端末の写真から旅」（マイページ → 旅の記録。説明のあと「続ける」を押したときだけ尋ねる）。端末の中で撮影日時、丸めた位置、識別子だけを読み、画像は送りません。
- 位置情報（使用中のみ）：撮影地マップの現在地。サーバーへは送りません。写真の EXIF と GPS は端末で取り除いてから送り、撮影地は約1kmに丸めて保存します。
- 通知：利用者がオンにする操作をしたときだけ尋ねます。

すれちがい乗車券の背景の Bluetooth（bluetooth-central、bluetooth-peripheral）
- 任意で、初期設定はオフ。マイページ → 設定 → すれちがい乗車券で説明を読み、「オンにする」を押し、iOS の Bluetooth の確認を許可して初めて動きます。オフにすると広告も走査も止まります。
- 目的は、同じアプリの近くの端末と小さなカードを交換することだけ（専用のサービス UUID）。中身は、選んだ公開写真1枚の id、ひとこと、発と着の字、券面の種類、プロフィールの都道府県を出すかの印。位置、連絡先、端末の識別子は送りません。
- 試すには iPhone が2台要ります：A と B でそれぞれサインインし、両方でオンにして近くに置きます。1台でも、説明、許可の確認、初期設定のオフは確かめられます。画面収録（動画の URL）は求められたら送ります。

App 内課金（3.1.2）
- 定期購入「Journey Photo Pro」：月額（com.journeyphoto.JourneyPhoto.pro.monthly、500円）、年額（com.journeyphoto.JourneyPhoto.pro.yearly、5,000円）。無料の試用なし。
- 試し方：マイページ → 設定 → Pro → プランを選び「Pro をはじめる」（Sandbox）。購入を復元はプランの下。
- 旅のトランクの硬貨と部品は投稿で配られ、購入できません。
```

**「24時間以内に確かめる」は owner の運用の約束になる**（ガイドライン 1.2 は通報への速い対応を求める）。
守れないなら、貼る前にこの一文を「promptly」「速やかに」に直す。

## 審査用アカウント

**owner が本番で作る。** このリポジトリ、Artifact、札、会話には、メールアドレスもパスワードも書かない。
入れる先は App Store Connect の「サインイン情報」の欄だけ。

### 作る（2つ。A と B）

1. メールを2つ用意する（例: Gmail の別名 `<owner のアドレス>+review-a@…`、`+review-b@…`。確認コードが届けばよい）。
   **owner 本人のアカウントは渡さない**（審査官はアカウントの削除も試す）
2. パスワードは、パスワード管理のアプリで新しく作る（ほかで使っていないもの）。ここには書かない
3. iPhone の Journey Photo（TestFlight の 1.1.91）で、ログアウトしてから「マイページ → アカウントを作る」→ A のメールで登録 → 届いた確認コードを入れる
4. 表示名を「Review A」、ユーザー名を `review_a` のように、審査用と分かる名前にする
5. **A で公開の写真を1枚投稿する**（自分で撮った風景。人の顔、他社のロゴは写さない）。空のマイページだと「投稿を確かめられない」と差し戻されることがある
6. ログアウトして、同じ手順で B を作り、B でも公開の写真を1枚投稿する
7. B で A をフォロー、A で B をフォロー（メッセージは、相手をフォローしている人だけが始められる）
8. A から B へメッセージを1通送り、B で承認する（承認前は文字3通まで、写真とリンクは送れない）
9. A で旅行プランを1つ作り、招待リンクで B を仲間にして、会話に1通書く（旅行プランの会話の通報を試せるように）

### App Store Connect に入れる

- 「App Review に関する情報」→「サインインが必要です」にチェック
- ユーザー名に A のメール、パスワードに A のパスワード（欄は1組しか無い）
- B は、Notes に貼った英語の**最後に owner がその場で書き足す**（`Demo account B: <メール> / <パスワード>`）。
  Notes は審査の人にだけ見える欄。**このリポジトリ、Artifact、札、会話には書かない**
- 連絡先の電話番号は国番号から（`+81 90 1234 5678` の形。先頭の 0 を取る）

### 申請のあと

- 審査官に消されたら、次の申請の前に作り直す
- 承認されたら、パスワードを替えるか、2つとも消してよい

## ガイドライン別の対応（2026-11-15 に a65201d で確かめた）

重い順。「足りない」は 1.1.91 には無い。

| 条項 | 要求 | このアプリでの答え | 合否 | 根拠（a65201d） |
|---|---|---|---|---|
| 4.8 Sign in with Apple | 他社のログインを使うなら、同じ水準のログインも出す | **当たらない。** ログインは自前の Cognito のメールとパスワードだけ。Amplify で呼ぶのは `signIn`、`signUp`、`confirmSignUp`、`resetPassword` など。`signInWithWebUI`（Hosted UI）も Google、Facebook、LINE の SDK も無い | 合っている | `Core/Auth/AuthGateway.swift`、`project.yml`（依存は Amplify と AWSCognitoAuthPlugin だけ） |
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
| 5.1.1 / 4.5.4 | 通知 | 起動時には尋ねない。通知の画面、設定、すれちがい、光の知らせで「受け取る」を押したときだけ `requestAuthorization` | 合っている | `PushCenter.enable`、呼ぶのは `NotificationsView`、`SettingsView`、`PushPrimerView`、`PassSettingsView`、`LightAlertSettingsRows` |
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
| 製品の操作（観光スポットの「行きたい」の数は端末ごとのでたらめな番号で、本人と紐づかない。AI で旅行プランを作った月の回数は本人ごと、2026-11-15 札 #621） | はい | アプリの機能 | はい | いいえ |

**写真**にはアイコン、カバー、ストーリーの写真と動画（音声を含む）、意見に添えた写真も入る。
おおよその位置は撮影地（保存前に約1kmへ丸める）。**精細な位置は「いいえ」**。広告 ID は使わない。

**集めないもの**（端末の中だけ）: 端末の写真から作る旅の要約、行った県の記録、すれちがいのカードと場所、現在地、
MetricKit の診断（端末のログに出すだけ）、連絡先、健康、閲覧履歴、検索履歴。
AI で旅行プランを作るときに書いた文も**集めない**（端末の AI では端末の外へ出さない。サーバーの AI では読んで答えるだけで残さず、
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

- [ ] ビルドは `testflight/1.1.91`（a65201d）。App Store Connect の「バージョン」を 1.1.91 にし、ビルド 1.1.91 を選ぶ
- [ ] TestFlight の実機で一巡（投稿、ストーリーの動画、メッセージ、旅行プランの会話の通報、通報、ブロック、退会、機内モード）
- [ ] 画面写真 6.9インチ（1320×2868）を3枚以上。他の利用者の写真、人の顔、他社のロゴを入れない（`docs/APP_STORE_METADATA.md`）
- [ ] 審査用アカウント A と B を**本番**に作り、それぞれ写真を1枚投稿、互いにフォロー、メッセージを1通（上の手順）
- [ ] App のプライバシーの回答が `PrivacyInfo.xcprivacy` と一致（上の表）
- [ ] 年齢制限の質問票（上の表）
- [ ] 名前、サブタイトル、説明、キーワード、最新情報、サポート URL、プライバシーポリシー URL、カテゴリ（`docs/APP_STORE_METADATA.md`）
- [ ] Web のプライバシーポリシーが 2026年11月15日版になっている（journey.photo-web #650 が本番に出た）
- [ ] Notes に上の英語を貼った（すれちがいの動画を付けるなら video URL の一文を URL に替える）
- [ ] 自動更新の定期購入: 説明文か App Store Connect の「使用許諾契約（EULA）」の欄に利用規約のリンク（`https://journey-photo.com/terms`）を入れた（審査 3.1.2）
- [ ] 課金の商品（`pro.monthly`、`pro.yearly`）を**この版と一緒に審査へ出した**（版の「App 内課金とサブスクリプション」に追加。まだ一度も審査を通っていないなら、版と一緒でないと審査されない）
- [ ] 輸出コンプライアンスは `ITSAppUsesNonExemptEncryption: false` なので聞かれない。広告識別子は「いいえ」
- [ ] リリースの方法は**段階的リリース（7日）**を推奨（1.0.87 から大きく変わるため、落ちや重さが出たら止められる）
- [ ] 「審査に出す」は owner が押す

## owner にお願いすること

1. **アプリの名前を決める**（推奨 `Journey Photo 旅の写真と観光スポット`。商標の確認も）
2. **審査用アカウント A と B を本番に作る**（上の手順。パスワードはどこにも書かない）
3. **App Store 用の原寸の画面写真の撮り方を決める。** 推奨は、`storeShots` の原寸を公開の枝ではなく
   非公開の S3（いまの画面写真と同じ置き場、3日で消える）に置く形に変えることを owner が許すこと。
   2026-11-15 にこの変更を入れようとしたが、公開リポジトリの守りの段（#451）を外す変更なので、この担当は止めた。
   許さないなら、iPhone 17 Pro Max か 16 Pro Max の実機で、審査用アカウントの画面を撮る（原寸で 6.9インチ枠に入る）
4. 「24時間以内に確かめる」の約束でよいか
5. App Store Connect で、掲載情報、App のプライバシー、年齢の質問票、審査の情報を入れて「審査に出す」を押す

## 落ちやすい点として残っているもの

- **背景の Bluetooth（2.5.4）。** すれちがいの説明を求められることがある。返答の下書きは Artifact の 3-4
- **投稿が少ないと「中身が薄い」と見られることがある。** 審査用アカウントで写真を投稿しておく
- **すれちがいは iPhone が2台ないと試せない。** 動画を求められたら、2台で撮った画面収録を送る
