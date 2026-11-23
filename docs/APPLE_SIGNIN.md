# 「Apple でサインイン」を出す手順（owner 向け）

札 #601。アプリとサーバーのコードは、枝 `claude/apple-signin-601`（iOS と journey.photo-web の両方）にできています。

**owner の準備は済んでいます（2026-11-23）:**

- App ID `com.journeyphoto.JourneyPhoto` で「Sign In with Apple」を有効にした（staging の App ID は無い。staging の束はシミュレーターだけ）
- 鍵は新しく作らず、今のプッシュ通知の鍵（Key ID `DDYJB5893J`・Secrets の `APNS_PRIVATE_KEY`）に「Sign in with Apple」を足した。
  サーバーはこの鍵を使います（新しい Secrets は要りません）

あとは **鍵を SSM に置くこと（下の 0）と、出すときの設定変更（1〜4・owner の承認が要る）** だけです。お金はかかりません
（SSM の標準のパラメータは無料）。

---

## 0. 鍵を SSM パラメータストアに置く（本線）

サーバーは鍵を **SSM パラメータストアの SecureString から実行時に読みます**（関数の環境変数に鍵を置かない。
環境変数は `lambda:GetFunctionConfiguration` の読み取り権で読めるため・2026-11-23 確かめ役の指摘）。
どちらの置き場を使うかは journey.photo-web の `.github/workflows/deploy-api.yml` の1か所（ジョブ `deploy-user-api` の
`APPLE_SIGNIN_KEY_SOURCE`。今は `ssm`）で決まります。

1. AWS の画面（東京リージョン）で「Systems Manager」→「パラメータストア」→「パラメータの作成」
2. 名前 `/journey-photo/prod/apple-signin/private-key`、種類 **SecureString**（鍵は既定の `aws/ssm` のまま）
3. 値に、プッシュ通知の鍵の `.p8` の中身を `-----BEGIN PRIVATE KEY-----` から `-----END PRIVATE KEY-----` まで丸ごと貼る
   （Secrets の `APNS_PRIVATE_KEY` と同じもの）
4. これが無い間は、サーバーは「使えない」と答え、アプリはボタンを出しません（壊れはしない）

鍵を読むのは「Apple でサインイン」のスタックの関数だけです（サインイン・使えるかの確かめ・退会の取り消し・メールで結んだときの知らせ）。
退会（user API）は取り消しをそのスタックの関数（`photo-gallery-apple-signin-prod-appleRevoke`）に頼み、鍵を持ちません
（呼べるのは退会だけの役 `DeleteAccountRole`）。「Google でログイン」の口も鍵を持たず、知らせは同じスタックの `linkNotice` に頼みます。

取り消しの関数が落ち続けたら鳴るアラーム（`photo-gallery-apple-signin-prod-appleRevoke-errors`）を定義してあります。
知らせ先（SNS の宛先）はまだ無いので、メールなどで受けたいときは owner が SNS の宛先を作り、Deploy の段に
`--param "alarmTopicArn=<ARN>"` を足します（今は CloudWatch の画面に出るだけ）。

### 鍵を入れ替えるとき

プッシュ通知の鍵を作り直す（なくした・漏れた）ときは、**新しい鍵にも「Sign in with Apple」を付けてください**
（Apple Developer の Keys で、作るときに「Apple Push Notifications service (APNs)」と「Sign in with Apple」の両方にチェックし、
「Sign in with Apple」の「Configure」で Primary App ID に `com.journeyphoto.JourneyPhoto` を選ぶ）。付け忘れると、
プッシュは届くのに、Apple でのサインインと退会の取り消しだけが落ちます。

1. 新しい鍵（両方付けたもの）を作り、`.p8` を落とす。Key ID を控える
2. Secrets の `APNS_PRIVATE_KEY` と、SSM の `/journey-photo/prod/apple-signin/private-key` の**両方**を新しい中身にする
3. `deploy-api.yml` の `apnsKeyId`（本番と staging の2か所）を新しい Key ID にして、Deploy API Lambdas を流す
4. 古い鍵を Apple Developer で取り消す（新しい鍵で届くのを確かめてから）

---

## 1. 承認をもらってから、配る切り替えを入れる

サーバーの「Apple でサインイン」の部分（別のスタック `photo-gallery-apple-signin-<環境>`）は、
**journey.photo-web のリポジトリの変数 `APPLE_SIGNIN_ENABLED` が `true` のときだけ**配られます。既定は配りません。
コードをマージしただけでは Cognito のプールは変わりません。

**owner の「いいよ」のあとに**、担当（Claude）か owner が次をします:

1. <https://github.com/rymaruta/journey.photo-web/settings/variables/actions> で、変数 `APPLE_SIGNIN_ENABLED` を `true` にする
2. 付ける前の Cognito のプールの設定を控える（下の 2）
3. Deploy API Lambdas を流す。別のスタックが配られ、**Cognito のプールにトリガーが3つ付きます**（Define・Create・Verify。
   ログイン全体に関わる変更）。同じ回で user API の段に `POST /auth/apple` の流量の制限（秒 5 件・瞬間 10 件）が付きます

## 2. トリガーを付ける前と後に、プールの設定を比べる

serverless の「既にあるプールにトリガーを付ける」仕組みは `UpdateUserPool` を呼びます。`UpdateUserPool` は
**渡さなかった項目を既定に戻す**ことがあるので、付ける前と後で比べます。

```bash
aws cognito-idp describe-user-pool --user-pool-id <プールの ID> --query UserPool > before.json
# ここで Deploy API Lambdas を流す
aws cognito-idp describe-user-pool --user-pool-id <プールの ID> --query UserPool > after.json
diff <(jq -S 'del(.LastModifiedDate, .LambdaConfig)' before.json) <(jq -S 'del(.LastModifiedDate, .LambdaConfig)' after.json)
jq '.LambdaConfig' after.json
```

- 1つ目の `diff` は**何も出ないのが正しい**（トリガー以外は変わらない）。出たら、戻す（下の 5）
- `LambdaConfig` には、今の PostConfirmation に加えて `DefineAuthChallenge`・`CreateAuthChallenge`・`VerifyAuthChallengeResponse` が
  同じ1つの関数（`photo-gallery-apple-signin-<環境>-appleAuthChallenge`）を指していること

## 3. Cognito のアプリのクライアントに `ALLOW_CUSTOM_AUTH` を足す

クライアントは CloudFormation の外にあるので、コマンドで1回だけ変えます。
⚠️ `update-user-pool-client` も**渡さなかった項目を既定に戻す**ので、今の設定を読んでから、同じ値に
`ALLOW_CUSTOM_AUTH` だけを足して渡します（ふだんのメールのログイン `ALLOW_USER_SRP_AUTH`、
更新 `ALLOW_REFRESH_TOKEN_AUTH`、アカウントの有無を教えない設定、更新トークンの期限 3650 日を消さない）。
変えたあと `describe-user-pool-client` で、`ExplicitAuthFlows` に1つ足しただけなのを確かめます。

## 4. 確かめてから、iOS を出す

1. 本番の `GET /auth/apple/status` が `{"available":true}` を返す（curl）
2. 実機（TestFlight の前に Xcode から入れたもの）で: 新しく登録、同じメールのアカウントに結ぶ（持ち主の端末に知らせが届く）、
   メールを非公開にして登録、退会（サーバーが Apple の取り消しをする）
3. iOS の枝を main に入れて TestFlight。**権限（entitlement）のコミットは別にしてある**ので、main に入れるときに外すこともできる

## 5. 戻すとき（順番を守る）

1. アプリのクライアントから `ALLOW_CUSTOM_AUTH` を外す（3 と同じく、今の設定を読んでから1つだけ外す）。
   これで Apple でのログインは止まり、メールのログインはそのまま
2. 変数 `APPLE_SIGNIN_ENABLED` を `false` にする
3. `aws cloudformation delete-stack --stack-name photo-gallery-apple-signin-<環境>`
4. `aws cognito-idp describe-user-pool` で `LambdaConfig` を見る。Define・Create・Verify が残っていたら外す
   （PostConfirmation は残す。外すときも 2 と同じく前後を比べる）
5. 次の Deploy API Lambdas で、user API の段の `POST /auth/apple` の流量の設定も消える

逆の順（スタックを先に消す）だと、クライアントが CUSTOM_AUTH を受けたまま、トリガーの関数が無い時間ができます。

---

## 6. メールで知らせる（SES の準備、owner 向け）

メールで自動で結んだとき（Apple、Google）に、そのアカウントのメールアドレスへ知らせのメールを送ります（2026-11-23 owner「メールで知らせる」）。
送るのは AWS SES（Amazon Simple Email Service）です。**準備が済むまでは送りません**（変数 `SIGNIN_EMAIL_ENABLED` が既定で無い＝送らない。
プッシュの知らせは今までどおり届きます）。

**費用:** 1,000 通で約 0.10 ドル（約 15 円）。送るのは「メールで自動で結んだとき」だけなので、1人に一生で数通です。
1万人が全員結んでも約 1 ドル。SES のドメインの登録と DKIM は無料です。

### 6-1. 変数を入れて、SES の登録を作る

1. journey.photo-web の Settings → Secrets and variables → Actions → **Variables** に `SIGNIN_EMAIL_ENABLED` = `true` を足す
   （送り元を変えたいときだけ `SIGNIN_EMAIL_FROM`。既定は `no-reply@journey-photo.com`。差出人の名前は「journey.photo」）
2. Deploy API Lambdas を流す（staging → 本番）。Apple でサインインのスタック（`APPLE_SIGNIN_ENABLED` が true のときだけ配る）が、
   SES の**ドメインの登録（journey-photo.com）と DKIM** を作り、知らせの関数に「その送り元からだけ送れる」権限を付けます
3. スタックの出力（Outputs）に DKIM の CNAME が3組出ます。どちらかで見られます:
   - CloudFormation のコンソール → `photo-gallery-apple-signin-prod` → 出力 → `SigninEmailDkim1`〜`3`
   - `aws sesv2 get-email-identity --email-identity journey-photo.com --region ap-northeast-1`（`DkimAttributes.Tokens` の3つ。
     名前は `<token>._domainkey.journey-photo.com`、値は `<token>.dkim.amazonses.com`）

   ⚠️ staging と本番は同じ AWS アカウントの東京なので、ドメインの登録は1つだけです。**登録を作るのは本番のスタックだけ**で、
   staging は本番が作った登録を使います。だから DKIM の CNAME が出るのは本番の出力だけで、staging でメールを確かめるのは
   本番に一度配って DNS が通ったあとです（それまで staging の送信は失敗し、ログに出るだけ。サインインは止まりません）

### 6-2. DNS に DKIM の CNAME を3つ入れる

- 入れる先は `journey-photo.com` の DNS を持っている所です。**どこにあるかは、リポジトリの設定からは分かりませんでした**
  （Route 53 のホストゾーンは CloudFormation にもコードにも無く、手順書に「Route 53 で登録済みのドメインを入力」と書いた所があるだけ）。
  Route 53 なら、コンソールの「ホストゾーン」→ `journey-photo.com` → レコードを作成 → 種類 CNAME で3つ。ほかの会社なら、その会社の DNS の画面で同じ3つ
- 入れて数分〜72時間で、SES のコンソールの「検証済みの ID」で journey-photo.com が「検証済み」になります（DKIM が通ればドメインの確認も済む）
- 任意（迷惑メールに入りにくくする）: DMARC（`_dmarc.journey-photo.com` に TXT `v=DMARC1; p=none;`）。SPF は SES の既定の
  MAIL FROM（amazonses.com）で通るので、要りません

### 6-3. 送れる宛先の制限を外す申請（本番の利用者に送るため）

SES は最初「サンドボックス」で、**確かめたメールアドレスにしか送れません**。利用者に送るには申請が要ります（無料、ふつう1日以内）。

1. SES のコンソール（東京 ap-northeast-1）→ アカウントダッシュボード → 「本稼働アクセスをリクエスト」
2. メールの種類: **トランザクション**。Web サイトの URL: `https://journey-photo.com`
3. 使い方の説明の例（英語で書く）:
   "We send a one-time security notice to a user's own verified email address when their account is linked with Sign in with Apple
   or Google sign-in. About 1 email per user, only on that event. No marketing. Bounces and complaints are monitored via SES."
4. 通るまでは、SES のコンソールで自分のメールアドレスを「検証済みの ID」に足せば、そのアドレスにだけ送って確かめられます

### 6-4. 確かめる

- staging で、確かめ済みのメールのアカウントを作り、同じメールの Apple ID で「Apple でサインイン」→ メールが届く
  （件名「Apple でサインインできます」、本文「心当たりが無ければ、こちらから連携を解除できます。」とリンク）
- 届かないとき: CloudWatch Logs の `/aws/lambda/photo-gallery-apple-signin-<環境>-linkNotice` に `federated link email:` の行
  （`MessageRejected` ならサンドボックスか未検証。送れなくてもサインインは止まりません）
- 戻すとき: 変数 `SIGNIN_EMAIL_ENABLED` を消して Deploy API Lambdas（SES の登録と権限が消える。DNS の CNAME は残してよい）

### メールのリンクの行き先

リンクは `https://journey-photo.com/signin-methods`（Web の短い案内の頁、`app/signin-methods/page.tsx`）。
アプリでこの道を直に開く（universal link）には、iOS に Associated Domains の権限を足す必要があり、まだ足していません
（App ID で Associated Domains を有効にしてから。今は Web の頁が「アプリの設定の『サインインの方法』」を案内します）。
プッシュの知らせは、押すとアプリの「サインインの方法」が直に開きます。

---

## 仕組み（担当向け・短く）

- アプリは乱数の nonce を作り、**SHA-256 を Apple に、元の値をサーバーに**渡す。サーバーは `sha256(元の値) == token の nonce` を確かめ、
  使った nonce は1回きり（users 表の `nonce#apple#<sha>`。`ttl` を付けるが、users 表の TTL は無効（#295）なので今は消えない）
- `POST /auth/apple` は確かめたあと、使い捨ての券（乱数・5分・行には SHA-256 だけ）を出す。アプリは CUSTOM_AUTH の答えに券を出し、
  Cognito のトリガーが時間差の出ない比べ方で照らして消す
- 退会は、サーバーの退会（`DELETE /user/account`）の中で Apple の更新トークンを取り消す（Apple のスタックの関数に頼む。
  墓石を書く前。Apple が落ちている（5xx・時間切れ）なら 500 で止め、結び付けは残る。Apple が断った（4xx）・鍵が無いときは
  止めずに見張りに出す）。墓石を書いたあとに `apple#<sub>` の行と墓石の番号を消す
- メールで自動で結ぶのは、Cognito で確かめ済みのメールが同じで、`admin` でなく、別の Apple ID とまだ結んでいない人だけ。
  結んだら持ち主に**メール（SES）とプッシュ**で知らせる（下の「6. メールで知らせる」）。
  知らせの文は題「Apple でサインインできます」、本文「心当たりが無ければ、こちらから連携を解除できます。」とリンク1つ
  （2026-11-23 owner。「パスワードを変えてください」はやめた。パスワードを変えても Apple から入れてしまうため。Google は題が「Google でログインできます」）
- 設定の「サインインの方法」（`GET /user/signin-methods`、`DELETE /user/signin-methods/{provider}`、`api-user/src/signinMethods.ts`）で、
  本人が Apple と Google の連携を解除できる。Apple は更新トークンを取り消してから解除する。**最後に残る入り方は解除させない**
  （Apple や Google で新しく作った人はメールのパスワードを知らないため。パスワードを決め直すと `password#<uid>` の印ができ、解除できるようになる）。
  解除した提供元で、同じ確かめ済みのメールのまま入り直すと、新しいアカウントを作らずに断る（409、ログイン画面に
  「この Apple ID の連携は解除されています。メールアドレスでログインしてください」）。結び付けの行や、どう結んだかが
  分からない連携は、安全側に倒して「外の提供元で作った人」と扱う。Apple が取り消しを断った、鍵が無いときは、退会と同じく
  行を消さずに解除の印と `ttl`（30日）を付けて残す（その行では入れない）
- 行・券・トリガーは提供元（`apple`・`google`）の欄で分けてある（`federatedAccount.ts`）。「Google でログイン」（#715）も
  同じトリガーを使う（`docs/GOOGLE_SIGNIN.md`）

## 気をつけること

- サーバーで配っていない環境では、アプリは **ボタンを出しません**（`GET /auth/apple/status` が無い＝404）。今の本番に入れても壊れません
- users 表の TTL（`ttl` の欄）はまだ有効になっていません（#295）。使った nonce の行と、取り消せなかった結び付けの行は、
  TTL を有効にするまで消えずに残ります（中身は SHA-256 と時刻だけ）
- 審査: Apple でサインインは、Google などほかの会社のログインを使うときに必須になるもの（審査指針 4.8）
- 費用: Apple で入った人も、ふつうの月間利用者として数えます（Cognito は月1万人まで無料の段）。Apple 側の追加の費用はありません
