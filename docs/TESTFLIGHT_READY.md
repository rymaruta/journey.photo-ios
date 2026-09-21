# TestFlight を回す前の最終確認（2026-09-21）

## 確かめたこと（推測ではなく、CI の記録）

**本物の SwiftUI でコンパイルが通り、シミュレータ上でテストが全部通りました。**
`Run #9`（`c352654`）の記録:

    Test Suite 'All tests' passed
      Executed 166 tests, with 0 failures (0 unexpected)
    ** TEST SUCCEEDED **

iPhone 17 Pro Max / iOS 26.2 のシミュレータ。114ファイル。
**実 SwiftUI 固有のコンパイルエラーは1件も出ていません。**

それまでの `Run #1`〜`#8` は全部**プロジェクト設定側の関門**で止まっていて、
Swift のコードは1行もコンパイルされていませんでした。潰した順:

| 関門 | 直し方 |
|---|---|
| `xcode-project run-tests` がエラー本文を伏せる | `xcodebuild` を直に叩く |
| SwiftPM プラグインの「Trust & Enable」を CI で押せない | `-skipPackagePluginValidation` |
| テストの的に Info.plist が無い | `GENERATE_INFOPLIST_FILE: YES` |
| arm64 ランナーで x86_64 も組もうとする | `-sdk` を外し `ARCHS=arm64` |
| 依存の組み直しで60分の上限に当たる | 上限120分＋依存の控え |

---

## ⚠️ プッシュ通知は、いま出しても動かない

アプリは `POST /user/devices` に端末を預けるが、**その口は
`photo-gallery` の feature ブランチにしか無い**。確かめた:

    origin/main        api-user/src/devices.ts: 無い
    origin/develop     api-user/src/devices.ts: 無い
    claude/journey-photo-ios-app-ffos85: ある

このまま TestFlight に出すと、設定の「プッシュ通知を受け取る」を押した
ときに **404** になる（画面には赤字で理由が出るので、黙っては壊れない）。

**直すには `photo-gallery` 側を出す必要がある**——CLAUDE.md の決まりで
`develop` に入れて staging で確かめてから `main`。これは owner の判断で、
私からは触れない（指定ブランチ以外に push しない）。

通知以外の機能は、この有無に関係なく動く。

---

## 1. owner がやること（これだけ）

| # | やること | 状態 |
|---|---|---|
| 1 | リポジトリを **public** にする | ✅ 済み（API で `"private": false` を確認） |
| 2 | App Store Connect で**アプリの枠**を作る | ✅ 済み（Journey Photo — 旅の写真） |
| 3 | **App Store Connect API キー**を作る | ⚠️ 作成済みだが `.p8` を落とせていない |
| 4 | **Secrets を4つ**入れる（下） | 2/4（`ISSUER_ID`・`KEY_ID` は入った） |
| 5 | **Actions → TestFlight → Run workflow**（ブランチ **main**） | 残り2つが揃ってから |

### 3 でつまずいたときの手（実際につまずいた）

iPhone の Safari だと `.p8` のダウンロードが「エラーが発生しました」で
止まることがある。**失敗してもキーは消費されない**（ダウンロードの
リンクは残る）ので、落ち着いて次を順に試す:

1. **ポップアップブロックを切る**（設定 → アプリ → Safari）。
   ダウンロードは新しいウィンドウを開く実装なので、ここで止まる
2. **Chrome を入れて、そこから落とす**
3. **PC か iPad を1回だけ借りる**（Mac である必要は無い）

落ちた `.p8` は iOS では中身が見られない。**ファイル App で長押し →
名称変更 → 拡張子を `.txt` にする**と、タップしてテキストとして開ける。
それも駄目なら、ショートカット App で「ファイルを取得 → 入力から
テキストを取得 → クリップボードにコピー」の3手を作る。

### Secrets（journey.photo-ios）

| 名前 | 中身 |
|---|---|
| `APP_STORE_CONNECT_ISSUER_ID` | API キーのページ上部の UUID |
| `APP_STORE_CONNECT_KEY_ID` | 作ったキーの Key ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | `AuthKey_XXXX.p8` の全文 |
| `CERTIFICATE_PRIVATE_KEY` | 署名用の RSA 鍵（この会話でお渡ししたもの） |

> **なぜ public か**: macOS ランナーは private だと**分数10倍**で、枠は
> photo-gallery と共通。枠切れは「遅くなる」ではなく「**何も出せなくなる**」
> （2026-08 に20日間止まった）。public なら無料。

### プッシュ通知も届かせるなら（任意・あとでもよい）

| 名前 | 中身 | 場所 |
|---|---|---|
| `APNS_PRIVATE_KEY` | `AuthKey_DDYJB5893J.p8` の全文 | **photo-gallery** の Secrets |

そのうえで `api-user/**` の変更が `main`（本番）か `develop`（staging）に
入ると、`Deploy API Lambdas` が配ります（約4.5分）。**鍵が無くても通知は
積まれます**（アプリを開けば読める）——端末に飛ばないだけです。

## 2. こちらで済んでいること

- **アプリの機能は Web と同等**（投稿・複数枚・タグ/カテゴリの固定候補・
  ストーリー（曲・長さ・動画の再生・返信・反応）・アルバムと招待・
  フォロー/いいね/コメント・地図・検索・ピン留め・写真の差し替え・
  プロフィールの色・トップの3タブ・通報とブロック・退会）
- **プッシュ通知**（サーバー＝ api-user、アプリ＝許可・宛先・タップの行き先）
- **審査で見られるところ**: 4.2（ネイティブのカメラ）・1.2（通報・ブロック・
  規約同意・問い合わせ・**持ち主によるコメント削除**）・5.1.1(v)（アプリ内退会・
  **英語の端末でも打てる確認語**）・プライバシーマニフェスト
- **CI**: GitHub Actions（`ios-testflight.yml`）と Codemagic（`codemagic.yaml`）の
  両方。ビルド番号は TestFlight の最大+1、アプリの Apple ID は Bundle ID から自動取得
- **関門**: `Tools/verify.sh`（構文・参照・API の突き合わせ・設定・単体テスト180件＋起動スモーク1本）

## 3. ビルドが通ったあと

1. App Store Connect → アプリ → **TestFlight** → 内部テスト → 自分を追加
2. iPhone の **TestFlight** アプリで受け取る
3. **最初に確かめること**（実機でしか分からない順）
   - 起動してギャラリーが出る（公開の写真が並ぶ）
   - 新規登録 → メールのコードで確認 → ログイン
     （**未確認のまま閉じて開き直す**のも試す。ここは Web で詰んだ経路）
   - 写真を1枚投稿（カメラとライブラリの両方）
   - 設定 →「プッシュ通知を受け取る」→ 別のアカウントからいいね → 届くか
   - 退会（**確認語が端末の言語で出るか**）

## 4. まだ確かめられていないこと（正直に）

**本物の SwiftUI SDK には当たりました**（上の Run #9 / #10）。残るのは
シミュレータでは分からないものだけです。

- **実機の APNs には触れていません。** 署名の形（ES256・生の64バイト）や
  鍵の綴りは本家のソースで確かめましたが、**シミュレータは APNs に繋がらない**
  ので、実際に届くかは実機で初めて分かります
- **カメラ**も同様（シミュレータにカメラが無いので、`CameraPicker` は
  画面に出しても実行されていない）
- **Amplify（Cognito）の往復**——起動はしていますが、実際のログインは
  していません
- **画面の見た目**。CI が見ているのは「落ちずに描けたか」までで、
  ずれや切れは目で見ないと分かりません
- **地図の初期表示**。ピンが画面に入るかは実機で見るしかありません

触って確かめる順は `docs/DEVICE_TEST.md` の末尾に並べてあります。
