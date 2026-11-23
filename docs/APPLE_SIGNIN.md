# 「Apple でサインイン」を使えるようにする手順（owner 向け）

札 #601。アプリとサーバーのコードは、枝 `claude/apple-signin-601`（iOS と journey.photo-web の両方）にできています。
あとは **Apple Developer での準備（このページの 1〜3）** と、**出すときの設定変更（4・owner の承認が要る）** だけです。

かかる時間はおよそ 15 分。お金はかかりません（Apple Developer Program の年会費の中）。

---

## 1. App ID で「Sign In with Apple」を有効にする（2つ）

1. ブラウザで <https://developer.apple.com/account> を開き、ログインする
2. 左の「Certificates, Identifiers & Profiles」→「Identifiers」
3. 一覧から **`com.journeyphoto.JourneyPhoto`** を押す
4. 「Capabilities」の一覧で **「Sign In with Apple」** にチェックを入れる
   - 右の「Edit」を押すと出る画面は「Enable as a primary App ID」のままでよい
5. 右上の「Save」→ 確かめの画面で「Confirm」
6. 同じことを **`com.journeyphoto.JourneyPhoto.staging`** でもする

> 有効にすると、今の署名のプロファイルが「Invalid（使えない）」になることがあります。
> TestFlight を出す仕組み（`ios-testflight.yml`）は、出すたびにプロファイルを取り直す（無ければ作る）ので、
> 多くの場合このままで大丈夫です。もし次の TestFlight の署名で落ちたら、「Profiles」で
> `com.journeyphoto.JourneyPhoto` の App Store 用のプロファイルを消してから、もう一度流してください（作り直されます）。
> **ここは確かめていません。**

## 2. キー（.p8）を作って落とす

1. 左の「Keys」→ 右上の「＋」
2. 「Key Name」に分かる名前を入れる（例: `journey-photo Sign in with Apple`）
3. 一覧の **「Sign in with Apple」** にチェック → 右の「Configure」
4. 「Primary App ID」で **`com.journeyphoto.JourneyPhoto`** を選んで「Save」
5. 「Continue」→「Register」
6. **「Download」で `.p8` のファイルを落とす**
   - ⚠️ **落とせるのは1回だけ**です。なくしたら、キーを作り直すことになります
   - パソコンの安全な所に置いてください（人に送らない・チャットに貼らない）
7. 同じ画面に出る **Key ID**（10文字の英数字）を控える

## 3. Team ID を確かめる

- 右上の名前の下、または「Membership details」にある **Team ID**（10文字）
- プッシュ通知の鍵と同じチームなら **`5428GX5UM8`** のはずです（サーバーはこの値を使います。違っていたら教えてください）

## 4. GitHub の Secrets に入れる（journey.photo-web のリポジトリ）

1. <https://github.com/rymaruta/journey.photo-web/settings/secrets/actions> を開く
2. 「New repository secret」で、次の2つを作る

| 名前 | 中身 |
|---|---|
| `APPLE_SIGNIN_PRIVATE_KEY` | 2 で落とした `.p8` を開いて、`-----BEGIN PRIVATE KEY-----` の行から `-----END PRIVATE KEY-----` の行まで**丸ごと**貼る |
| `APPLE_SIGNIN_KEY_ID` | 2 で控えた Key ID |

- Web の画面用の「Services ID」は**今回は作りません**（iOS が先。Web で使うときに足します）
- 宛先（Bundle ID）と Team ID はサーバーの設定に入っているので、Secrets には要りません

**Secrets を入れただけでは何も変わりません。** サーバーの「Apple でサインイン」の部分は、
この鍵が入っている環境で、次の 5 の反映をしたときだけ配られます。

---

## 5. 出すときの設定変更（owner の承認が要る・staging で確かめてから本番）

ここからは担当（Claude）が進めます。**owner に「いいよ」をもらってから**です。

1. **サーバー**: journey.photo-web の枝 `claude/apple-signin-601` を develop → staging に反映する。
   鍵が入っていれば、Deploy API Lambdas が別のスタック `photo-gallery-apple-signin-<環境>` を配り、
   **Cognito のプールにトリガーを3つ付けます**（Define・Create・Verify。ログイン全体に関わる変更）
2. **Cognito のアプリのクライアントに `ALLOW_CUSTOM_AUTH` を足す**（staging → 本番）。
   クライアントは CloudFormation の外にあるので、コマンドで1回だけ変えます。
   ⚠️ `update-user-pool-client` は**渡さなかった項目を既定に戻す**ので、今の設定を読んでから、同じ値に
   `ALLOW_CUSTOM_AUTH` だけを足して渡します（ふだんのメールのログイン `ALLOW_USER_SRP_AUTH`、
   更新 `ALLOW_REFRESH_TOKEN_AUTH`、アカウントの有無を教えない設定、更新トークンの期限 3650 日を消さない）
3. staging のアプリ（Xcode から入れた Debug）で確かめる: 新しく登録、同じメールのアカウントに結ぶ、
   メールを非公開にして登録、退会（Apple の取り消し）
4. 本番に同じ 1・2 をする → iOS の枝を main に入れて TestFlight

## 6. 気をつけること

- **iOS の権限（entitlement `com.apple.developer.applesignin`）は、1 が済むまで main に入れません。**
  先に入れると、署名のプロファイルにこの権限が無く、TestFlight の署名が落ちます。今は枝にだけあります
- サーバーの鍵が無い環境・まだ配っていない本番では、アプリは **ボタンを出しません**
  （`GET /auth/apple/status` が無い、または「使えない」と答える）。今の本番に入れても壊れません
- 審査: Apple でサインインは、Google などほかの会社のログインを使うときに必須になるもの（審査指針 4.8）。
  今はメールだけなので必須ではなく、使いやすさのために足します
- 費用: Apple で入った人も、ふつうの月間利用者として数えます（Cognito は月1万人まで無料の段）。
  Apple 側の追加の費用はありません
