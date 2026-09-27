# セッションの記録（2026-09-21 〜 2026-09-24）

モック5枚の完全再現から始まり、**TestFlight 経由で owner の iPhone に初めて入る**
ところまで進めたセッションの記録。**次に作業する人（人でも Claude でも）が、
同じところで詰まらないため**に書く。

> **認証情報は書いていない。** 鍵・トークン・プール ID などの値は
> `Config/*.xcconfig`（公開識別子）と GitHub の Secrets（秘密）にある。
> ここに出てくるのは**名前だけ**。

---

## 1. どこまで来たか

| | 状態 |
|---|---|
| モック5枚（ホーム / マイページ / 撮影地マップ / ストーリー作成 / 撮影スポット詳細） | ✅ 実機の絵14枚で確認（run 66） |
| TestFlight | ✅ **0.1.0 (1)** が内部テストで配布され、owner の iPhone に入った（run 70） |
| App Store 審査 | ⏳ まだ出していない（下の「次にやること」） |
| プッシュ通知 | ⛔ アプリ側は出来ているが**サーバーの口が無い**（下） |

---

## 2. 決定事項と、その理由

### 2-1. iOS アプリ

**マイページは鍵なしでも描く（Debug のみ）**
- `PreviewSession`（`Core/Auth/PreviewSession.swift`）が `JPPreviewUserId` を読み、
  入っていれば**公開プロフィール＋公開一覧から自分のぶんを絞る**経路へ逃がす
- 理由: CI は資格情報を持たないので、マイページの絵が「ログインが必要です」しか
  撮れていなかった。**Release では必ず nil**（`#if DEBUG`）なので出荷物に口は無い
- 下書き（非公開）は公開一覧に無いので出ない＝**嘘の中身は増えない**

**ストーリーは払って送れる**
- 左＝次・右＝戻る・下＝閉じる。**上と斜めは何もしない**（44pt 未満は捨てる）
- 理由: 上は他のアプリで「詳細を開く」に当たり、同じ動きで違うことが起きる方が悪い。
  斜めを「次」と読むと、閉じようとして進む——**戻れない操作ほど慎重に倒す**
- 判断は `StoryPlayback.swipe`（純粋な関数）。手元の模型では指も画面も動かせない
  ので、View の中に書くと一生確かめられない

**巡回（スクリーンショット）は本番の口を見る**
- 巡回のビルドは Debug＝`Config/Staging.xcconfig` なので、そのままだと
  **写真は本番・プロフィールは staging** という食い違った絵になる
- `ScreenshotTests` で `-JPSiteBaseURL` と `-JPUserApiBaseURL` の両方を本番に向ける。
  **鍵は持たないので叩けるのは公開の GET だけ**

**アプリのアイコンとマークをサイトに揃える**（2026-09-24）
- アイコンは黒地に白いアパーチャ（サイトの favicon と同じ絵）、見出しのマークは
  `BrandMark`。ワードマークの表記の仕様は `docs/BRAND.md`
- 理由: owner がサイトでこの絵を選んでいる（枠なしに直した経緯あり）。
  App Store とサイトで別の顔を名乗らない

**スクリーンショットは App Store 審査には使わない**
- CI の14枚は**本番データ＝他人の写真が写っている**。`APP_STORE_METADATA.md` の
  「人の顔と他人の投稿を入れない」に反する。審査用は owner の写真で撮り直す

### 2-2. TestFlight のワークフロー（`.github/workflows/ios-testflight.yml`）

**「分かるのが遅い」ものは全部、先頭に出して30秒で止める**

| 段 | 何を見るか | 上げる回（`submit=true`） | 上げない回 |
|---|---|---|---|
| 秘密が揃っているか | Secrets 4つ | 足りなければ**赤で止める**（名指し） | 警告のみ |
| Xcode を選ぶ | iOS 26 SDK があるか | 無ければ**赤で止める**（入っている Xcode を列挙） | 警告のみ |

- 理由: どちらも以前はテスト（7〜18分）の**後ろ**にあり、足りないだけで
  13分待って最後に分かっていた
- **上げない回は止めない**: 絵を撮る用途は古い SDK・秘密なしでも成立し、そちらまで
  赤くすると「本物の SwiftUI で通るか」が読めなくなる

**「上げたのに赤」「上げていないのに緑」を両方なくす**
- run 66 は上げるつもりで流して**緑**、実際は署名から先が飛ばされていた
- run 70 は**上がっていたのに赤**（外部審査への提出で落ちた）
- 既定は**上げるだけ**。外部テスターの審査に出すのは `betaReview: true` のときだけ

**撮れなかった画面は名指しする**（`Tools/export-screenshots.sh`）
- 巡回は「出なければ撮らない」ので、1枚消えても赤くならない。
  README とまとめに「撮れなかった画面: …」を出す（条件つきの `15-マイページ（下）` は除外）
- **macOS のファイル名は NFD**（「プ」＝「フ」＋半濁点）。比べる前に NFC に揃える

### 2-3. サーバー（photo-gallery）側で決めたこと

**公開範囲を絞った写真は `private/` へ移し、配るときに署名する（案A）**
- `uploads/<uid>/…` は公開（署名なし）、`private/<uid>/…` は署名必須の振る舞い
- `/uploads/*` 全体に署名必須を付けると**公開写真が全部 403**（静的サイトの URL に
  期限を載せられない）ので、振る舞いを分ける
- **CloudFront の設定が入るまで署名は不活性**（移動は起きるが表示は壊れない）

**招待リンクの下見から、絞った写真を外す**
- `GET /invites/{token}` は**未認証**。ここで署名付き URL を返すと、招待リンクを
  持つ誰にでも鍵を配ることになる——**判定できない口では出さない**
- 判定は「`audience` を持っていれば一律で絞った扱い」。**知らない綴りも隠す側**に倒す
  （`sanitizeAudience` の「知らない値は公開に倒す」とは**わざと別**）

**Deploy API は変わった側だけ配る**（photo-gallery #159）
- GitHub は**ジョブごとに分単位で切り上げて課金**する。5秒のジョブでも1分
- 9月のコミットの 216/288 が `api-user/` だけだったのに、毎回 admin も配っていた
- **疑わしい回はすべて両方配る**（「API を直したのに反映されない」は実際に踏んだ事故）

---

## 3. 未解決の課題・次にやること

**優先度順。** 🔴 は審査に出す前に要るもの。

| | 課題 | 誰が | メモ |
|---|---|---|---|
| 🔴 | **プッシュ通知が 404** | owner の判断 → Claude | 設定の「プッシュ通知を受け取る」は在るが、`POST /user/devices` が photo-gallery の **main にも develop にも無い**（#63 が未マージ）。**推奨は #63 を入れる**。審査官が触りうる導線 |
| 🔴 | 審査用アカウント | owner | **本番**の Cognito に作り、**写真を1枚は投稿**しておく（空だと差し戻されうる） |
| 🔴 | 審査用スクリーンショット | owner | 6.7インチ・3枚以上・他人の写真と顔を入れない |
| | TestFlight で実機確認 | owner | アイコン / 起動画面 / 権限ダイアログの文 / 英語表示 / カメラ投稿 / 通報・ブロック / 機内モード |
| | 外部テスター | owner | App Store Connect の「テスト情報」（フィードバック用メール・連絡先）を埋めてから `betaReview: true` |
| | CloudFront の署名配信 | owner | `photo-gallery/scripts/setup-private-delivery.sh --apply` ＋ Secrets 2つ。手順は `photo-gallery/docs/restricted-image-delivery.md` |
| | 本番反映（develop → main） | owner の判断 | 「まだ出さない」のまま。#136（署名）・#159（課金）は develop まで |
| | `/user/spots` を使うか | 未定 | サーバーにはあるがアプリは使っていない（下の 4-3）。「行きたい場所」は**端末に保存**していて機種変で消える。**旅行プランの候補もこの端末の「行きたい」から出す**ので、Web で押した場所はアプリの候補に出ない（逆も同じ）。`/user/trips` は 2026-09-26 に使い始めた（キャンバス 17・17b・17c） |

**App Store Connect で owner が答えるもの**は `docs/APP_REVIEW.md` に貼れる形である
（Notes の和英文・App のプライバシー・年齢制限の質問票）。

---

## 4. API（photo-gallery）側の仕様で iOS に関係するもの

**出どころ**: `photo-gallery` の develop（2026-09-24 時点）の `api-user/serverless.yml`
と `api-user/src/**`。**変わりうるので、突き合わせは `Tools/check-api-parity.py`**
（`PHOTO_GALLERY=<photo-gallery のパス>` で相手を指定できる）。

### 4-1. 2つの出どころ

| | 何か | 認証 |
|---|---|---|
| **公開一覧** | 静的サイトの `app/data/photos.json`（**API ではない**） | 不要 |
| **api-user** | API Gateway（HTTP API）＋ Lambda | 口ごとに違う（下） |

- 公開一覧は**ビルド時に焼いたスナップショット**。反映は投稿時の再ビルド待ち（通常数分）
- **ページングが無い**。30枚規模では丸ごと読んでよいが、数百枚を超えたら API 側に
  `GET /feed` を足すこと
- **非公開の項目は落としてある**: `srcOriginal`（EXIF 付きの原本＝GPS 入り）・`key`・
  `staticStale`・`publicFeed`・`keptFrom`
- **公開範囲を絞った写真（`audience` あり）は載らない**。見るには `GET /feed/restricted`

### 4-2. 認証

- Cognito の ID トークンを `Authorization: Bearer <token>` で送る（`APIClient.authorized`）
- 公開の口は `APIClient.anonymous`（ヘッダ無し）
- **エラーの形は `{ "error": "<日本語の文>" }`**。画面の扱い（`APIError`）:
  - **401** → 「ログインの有効期限が切れました」（押し直しても直らない）
  - **403** → 「権限がありません」（**ログインし直しても直らない**。401 と混ぜない）
  - **404** → 口ごとに意味が違う（`/profile/{id}` の 404 は**退会済み**）
  - 通信そのものの失敗は `.unreachable`（「ログインしてください」と混ぜない）

### 4-3. 口の一覧（73本・アプリが叩くのは66本）

**公開（鍵なし）**

    GET  /profile/{userId}            公開プロフィール。退会済みは 404
    GET  /users/search                ユーザー検索
    GET  /users/{uid}/follow          フォロー数（数え札はサーバーが持つ）
    GET  /photos/{id}/like            いいね数
    GET  /photos/{id}/comments        コメント一覧
    GET  /invites/{token}             アルバム招待の下見（絞った写真は出ない）

**要ログイン（主なもの）**

    写真      GET  /user/photos               自分の写真（下書き＝非公開を含む）
              PUT  /photos/{id}               中身・公開範囲の変更（送った項目だけ変わる）
              DELETE /photos/{id}
              GET  /feed/restricted           絞った写真のうち「自分に見える」ぶん
    投稿      POST /upload/presigned-url → S3 へ PUT → POST /upload/save
              DELETE /upload/discard          途中でやめたとき
    反応      POST|DELETE /photos/{id}/like   POST|DELETE /photos/{id}/save
              POST /photos/{id}/comments      DELETE /photos/{id}/comments/{commentId}
              POST /photos/{id}/report
    人        POST|DELETE /users/{uid}/follow GET /users/{uid}/followers|following
              POST|DELETE /users/{id}/block   GET /user/blocks
              PUT|DELETE /user/close-friends/{id}   GET /user/close-friends
    自分      GET|PUT /user/profile           POST /profile/avatar/presigned-url
              GET /user/likes  GET /user/likes/{id}  GET /user/saves  GET /user/following
              GET|PUT /user/notifications     DELETE /user/account（退会）
    ストーリー GET|POST /stories  DELETE /stories/{id}  POST /stories/{id}/view|keep
              GET /stories/{id}/viewers  GET|POST /stories/{id}/replies
              GET /stories/archive
    ハイライト POST /highlights  PUT|DELETE /highlights/{id}
              GET /highlights/{userId}  GET /highlights/{userId}/{id}
    アルバム  GET|POST /albums  PATCH|DELETE /albums/{id}
              POST|DELETE /albums/{id}/invite  POST /invites/{token}/join
    その他    GET /geocode/search  GET /geocode/reverse  GET /music/search

**サーバーにあるが、アプリは使っていない（5本）**——`/user/trips` の4本は
2026-09-26 に使い始めた（`TripPlanService`）

    GET|POST /user/spots   DELETE /user/spots/{slug}     行きたい場所（サーバー保存）
    GET /user/saves/{id}   POST /stories/{id}/vote

**アプリが叩いているが、サーバーに無い（2本）** ⛔

    POST   /user/devices    プッシュ通知の端末登録   → 404
    DELETE /user/devices    同・解除                → 404

### 4-4. 形と制約

**写真（`Photo`）**
- 表紙は `src` とその派生（`thumbSrc`・`srcAvif`・`src256`・`thumbSm`・`thumbAvif`・`thumbSmAvif`）
- **2枚目以降は `extraImages`**＝**オブジェクトの配列**（`{ src, thumbSrc, srcAvif, …, width,
  height, dominantColor, blurDataURL }`）。文字列の配列ではない
- **1投稿の上限は10枚**（表紙＋`extraImages` 9枚）
- 公開範囲 `audience` は `"followers"` か `"closeFriends"`。**無い＝全体に公開**
- 撮影地の座標は**約1kmに丸めて保存**（精細な位置は持たない）

**署名付き URL（`GET /feed/restricted`・`GET /user/photos`）**
- CloudFront の設定が入ると、画像の URL に `Expires`・`Signature`・`Key-Pair-Id` が付く
- **期限は10分**。長く画面を開いたままだと切れるので、**読み直せば新しい URL が来る**
- 設定が無い環境では**素の URL のまま**返る（アプリ側の分岐は要らない）

**その他の上限**

| | 値 | 超えたとき |
|---|---|---|
| ピン留め | 3枚 | **409**。本文に**そのときの一覧**（`pinnedPhotoIds`）が入る——画面はそれに揃える |
| プロフィールの BGM | 5曲 | |
| ストーリーの表示時間 | 3〜15秒 | サーバーが丸める |
| ハイライト | 1人20本 / 1本あたり100件 | |
| 旅行プラン | 50件 | |
| 絞った写真のフィード | 200件 | |
| 招待リンクの下見 | 24枚 | |

**性能の制約**: Lambda の同時実行は**アカウント全体で10本**。人が増えたら AWS に
引き上げを頼むのが先（`photo-gallery/CLAUDE.md`）。

---

## 5. ビルドや TestFlight で詰まった点と対処

### 5-1. TestFlight（2026-09-24・run 66〜70）

| 症状 | 原因 | 対処 |
|---|---|---|
| 上げるつもりで流して**緑**、なのに上がっていない | Secrets が2つ足りず、署名から先が**黙って飛ばされていた** | 秘密の点検を先頭へ。`submit=true` なら赤で止める |
| `Validation failed (409) SDK version issue` | **iOS 26 SDK（Xcode 26）以上でないと受け取られない**（Apple の要件）。ランナーの既定は Xcode 16.4 | ランナーには **Xcode 26.3 が入っている**。一番新しいものを選ぶ段を足した |
| 選ぶ段が **exit 134** で死ぬ | 各 Xcode の `xcodebuild -version` を20回叩き、1つが SIGABRT。`run:` は `bash -e` | **版は名前から読む**（`Xcode_26.3.0.app`）＋ `set +e` |
| **上がっているのに赤**（`missing required Beta App Information`） | `app-store-connect publish` の **`--testflight` は「外部審査に出す」**で、上げるのには要らない | 既定は上げるだけ。外部は `betaReview: true` |
| Xcode を変えた回だけ30分かかる | 依存の控えの鍵に Xcode の版が入っている | **仕様**。2回目から13分に戻る |

### 5-2. App Store Connect と iPhone

| 症状 | 原因 | 対処 |
|---|---|---|
| 開発者アカウントと普段の Apple アカウントが別 | — | **iPhone は切り替えない。**「ユーザとアクセス」で普段のアドレスを招待（役割は App Manager か 管理者） |
| テスターの状態が **「利用可能なビルドなし」** | グループに**テスターだけ入れて、ビルドを入れていない**。テスターの招待はビルドが無くても出る | ビルドの画面 →「グループ」→ ＋ |
| ビルドを入れたのに招待メールが来ない | **ビルドを入れる前に出た招待が残っていた** | テスターの行 →**「招待を再送信」**（これで解決した） |
| TestFlight アプリに出ない | TestFlight が見るのは iCloud ではなく**「メディアと購入」**のアカウント | 設定 → 自分の名前 → メディアと購入 で、招待したアドレスと同じか確かめる |
| Secret の名前が弾かれる | 名前に `.txt` などが混ざっていた | 名前は `CERTIFICATE_PRIVATE_KEY` だけ（英数字と `_` のみ） |
| `.p8` が iPhone で落とせない | Safari のポップアップブロック等 | 長押し →「リンク先のファイルをダウンロード」／Chrome／**キーを取り消して作り直す**（落とせるのは1回だけ） |

**Secrets の名前**（`journey.photo-ios` 側・値はここに書かない）:

    APP_STORE_CONNECT_ISSUER_ID     API キーのページ上部の UUID
    APP_STORE_CONNECT_KEY_ID        作ったキーの Key ID
    APP_STORE_CONNECT_PRIVATE_KEY   AuthKey_XXXX.p8 の全文
    CERTIFICATE_PRIVATE_KEY         署名用の RSA 鍵（Apple と無関係に作れる）

⚠️ **紛らわしいもの**: `photo-gallery/docs/GITHUB_ACTIONS.md` に出てくる Key ID は
**APNs（プッシュ通知）の鍵**のもので、App Store Connect API の鍵とは**別物**。
取り違えて入れると TestFlight の段で認証に落ちる。

### 5-3. 手元（Linux）での検証で踏んだもの

**Linux の検証と、本物の iOS SDK での検証は別物。** 手元の `Shims/` は SwiftUI の
**模型**で、修飾子は素通し（配置も色も再現しない）。**見た目は CI の実機の絵でしか
確かめられない**。

| 見逃し | どう分かったか |
|---|---|
| 同意画面のボタンが白地に白文字 | 実機の絵を**開いて見た**（ファイル名だけ見ていて何回も見逃していた） |
| 巡回を書き直して2枚が黙って消えた | 絵の**枚数を数えた** |
| マイページが「ログインが必要です」だけ | 実機の絵。以前これを「仕様」と書いていたのは誤りだった |
| 名指しの見張りが在る絵を「無い」と言った | macOS の NFD。**Linux の git は NFC なので手元では出ない** |

**だから**: CI の絵は**毎回全部開く**。枚数を数える。手元で緑でも「実機で確かめた」とは言わない。

---

## 6. 検証の手順（このリポジトリ）

```bash
# 手元（Linux）: 構文・参照・API の突き合わせ・設定・swift build/test・xcodegen
PHOTO_GALLERY=<photo-gallery のパス> bash Tools/verify.sh
```

- `check-api-parity.py` は**相手の枝次第で結果が変わる**。develop に無い口を
  叩いていれば NG になる（いまの `/user/devices` がそれ）
- 実機（シミュレータ）での型検査・絵は **GitHub Actions の TestFlight ワークフロー**
  （`submit=false` ならビルドと絵だけ）。macOS ランナーは**公開リポジトリなら無料**
- **絵は `screenshots` 枝**に置かれる（artifact は開発環境から取れないため）
