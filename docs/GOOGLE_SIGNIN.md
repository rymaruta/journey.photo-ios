# 「Google でログイン」を出す手順（owner 向け）

札 #715。アプリとサーバーのコードは、枝 `claude/apple-signin-601`（iOS と journey.photo-web の両方）にできています。
作りは「Apple でサインイン」（`docs/APPLE_SIGNIN.md`）と同じ土台で、Cognito のトリガーも同じものを使います。

**owner の準備は済んでいます（2026-11-23）:** Google Cloud で iOS 用の OAuth クライアントを作った
（クライアント ID `280167931666-24o92d38usbft3ouk3jc4dk8tvgh3t8p.apps.googleusercontent.com`。公開の値で、アプリに書き込んである）。
お金はかかりません（Google のログインは無料。Cognito は今と同じ月間利用者の数え方）。

---

## 1. 出す順番

1. **「Apple でサインイン」を先に（または同じ回に）出す。** 審査指針 4.8 で、Google のログインを置くなら Apple でサインインも要ります。
   サーバーも、Google の口は Apple のスタックのトリガー（CUSTOM_AUTH）を使うので、**Apple を配る環境でだけ**配ります
2. owner の「いいよ」のあとに、<https://github.com/rymaruta/journey.photo-web/settings/variables/actions> で変数
   **`GOOGLE_SIGNIN_ENABLED` を `true`** にする（`APPLE_SIGNIN_ENABLED` も `true` であること）。既定は配りません
3. Deploy API Lambdas を流す。別のスタック `photo-gallery-google-signin-<環境>` が配られ、`POST /auth/google` に
   流量の制限（秒 5 件・瞬間 10 件）が付きます。**Cognito のプールは変わりません**（トリガーは Apple のスタックだけ）
4. 本番の `GET /auth/google/status` が `{"available":true}` を返すのを確かめる（curl）
5. 実機で確かめる: 新しく登録、Gmail のアカウントで同じメールのアカウントに結ぶ（持ち主の端末に知らせが届く）、退会
6. iOS を main に入れて TestFlight（Google の公式の部品 GoogleSignIn-iOS を初めて取り込むので、Mac のビルドの解いた版を報告に書く）

## 2. 戻すとき

変数 `GOOGLE_SIGNIN_ENABLED` を `false` にし、`aws cloudformation delete-stack --stack-name photo-gallery-google-signin-<環境>`。
アプリのクライアントの `ALLOW_CUSTOM_AUTH` とトリガーは Apple と共有なので触りません。アプリは口が無い（404）とボタンを出しません。

## 3. プライバシーポリシーに書き足す文（案・Web の頁は今回は変えない・#696 と一緒に）

> **Google でログイン**
> Google でログインすると、Google から、Google アカウントの番号、メールアドレス（Google が確かめたかどうかを含む）、
> プロフィールの名前を受け取ります。番号は、あなたのアカウントを見分けるためだけに使います。メールアドレスは、
> 同じメールアドレスで登録済みのアカウントに Google でもログインできるようにするためと、ご案内に使います。
> 名前は、最初のログインのときに表示名にします（あとで変えられます）。Google のパスワードや、連絡先、カレンダーなどは受け取りません。
> 退会すると、Google アカウントとのつながりを消します。Google 側でも外すときは、Google アカウントの
> 「サードパーティ製のアプリとサービス」から journey.photo を削除してください。

（同じ形で「Apple でサインイン」の段落も足すと、#601 と #715 を1回で直せます:
Apple から受け取るのは Apple ID の番号、メールアドレス（非公開を選んだ人は Apple の転送用のアドレス）、最初の1回だけの名前。
退会すると、Apple に取り消しを頼み、つながりを消します。）

## 持ち主の端末に届く知らせ（2026-11-23 owner「結ばれました、は日常会話で使わない」「長すぎる」）

メールで同じアカウントに Google でもログインできるようにしたときに届く文（`api-user/src/federatedNotice.ts`）:

> **Google でログインできます**
> 心当たりが無ければ、パスワードを変えてください。

Apple は題が「Apple でサインインできます」。本文は同じです。

## 仕組み（担当向け・短く）

- アプリは乱数の nonce を作り、**SHA-256 を Google に**（GoogleSignIn-iOS 7.1 以上の `nonce`）、**元の値をサーバーに**渡す。
  サーバーは Google の公開鍵（JWKS・取り直しは 60 秒に1回まで）で ID トークンを確かめ（`iss` は `https://accounts.google.com` と
  `accounts.google.com`、`aud` は iOS のクライアント ID、期限）、`sha256(元の値) == token の nonce` を照らし、使った nonce は1回きり
- 確かめたあと、使い捨ての券（5分）を出し、アプリは CUSTOM_AUTH の答えに券を出す（Apple と同じトリガー・`google#<sub>` の行）
- メールで自動で結ぶのは、Google が確かめ済みで、**Google が持ち主を確かめられるメール（Gmail か Google Workspace の組織のメール）**だけ
  （Google の案内どおり）。ほかの会社のメールを Google アカウントに付けた人は、新しいアカウントになり、そのメールはアカウントに入れない
  （確かめ済みとして入れると、そのメールの本当の持ち主が後からメールで登録できなくなるため）
- Google の口は鍵を持たない。メールで結んだときの知らせは、Apple のスタックの知らせだけの関数（`linkNotice`）に頼む
- アプリでログアウト・退会したら、Google の部品の中のログインも外す（`GIDSignIn.signOut`）
- 更新トークンは受け取らない（サーバー用の認可コードを頼まない）ので、退会で取り消すものは無い。行と墓石の番号は退会で消す
- ボタンは Google のブランドの決まりの暗い形（地 #131314・縁 #8E918F・字 #E3E3E3・正式な「G」の印）を、Apple のボタンにそろえて
  高さ 50・カプセルにした。Apple のボタンの下に置く
