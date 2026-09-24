# TestFlight で配る

owner:「TestFlight にしよう」

実機に直接入れる（`docs/DEVICE_TEST.md`）との違いは3つ:

| | 直接入れる | TestFlight |
|---|---|---|
| お金 | 無料 | **年 12,980円**（Apple Developer Program） |
| 期限 | 7日で切れる | **90日** |
| 繋がる先 | staging（Debug ビルド） | **本番**（Release ビルド） |

**TestFlight は提出の予行演習でもある。** ここを通ったビルドが、そのまま
審査に出せる（同じ Archive を「配信」に回すだけ）。

---

## ⚠️ 先に読む: 本番に繋がる

TestFlight のビルドは **Release ＝ 本番の API とデータ**を向く。
つまり**試しに投稿したものが、本物のサイトに出る**。

- 試すときは **「すぐ公開する」をオフ**にして投稿する（下書きになる）
- 公開して試したら、**あとで消す**（写真の「…」→ 削除）
- アカウントの削除を試すなら、**捨てアカウントを本番に作ってから**

staging で一通り確かめてから TestFlight に上げると、事故が減る。

## 1. Apple Developer Program に入る（初回だけ）

1. <https://developer.apple.com/programs/> → Enroll
2. 個人（Individual）で申し込む。**年 12,980円**
3. 支払いと本人確認で**1〜2日かかることがある**。ここは待つしかない

> 法人名義で出したい場合は D-U-N-S 番号が要り、数週間かかる。
> 個人名義でよければ Individual が早い。

## 2. App Store Connect にアプリを作る（初回だけ）

<https://appstoreconnect.apple.com> → **マイ App** → **＋** → 新規 App

| 欄 | 入れるもの |
|---|---|
| プラットフォーム | iOS |
| 名前 | Journey Photo — 旅の写真 |
| 主要言語 | 日本語 |
| バンドル ID | `com.journeyphoto.JourneyPhoto`（一覧に出ないときは次の節） |
| SKU | `journey-photo-ios`（自分用の管理番号。何でもよい） |
| ユーザアクセス | 制限なし |

### バンドル ID が一覧に出ないとき

先に登録が要る。<https://developer.apple.com/account/resources/identifiers/>
→ **＋** → App IDs → App → Description に `Journey Photo`、
Bundle ID は **Explicit** で `com.journeyphoto.JourneyPhoto`。

> **Capability は何も足さなくてよい。** このアプリはプッシュ通知も
> Sign in with Apple も使っていない。

> ⚠️ 誰かに取られていたら、`Config/Production.xcconfig` の `JP_BUNDLE_ID` を
> 変えて `xcodegen generate` をやり直す（例: `com.rymaruta.journeyphoto`）。
> App Store Connect 側もその ID で作る。

## 3. Xcode から上げる

```bash
cd journey.photo-ios
bash Tools/mac-release.sh     # 先に緑にする
open JourneyPhoto.xcodeproj
```

1. 左の一覧で **JourneyPhoto** → **Signing & Capabilities** →
   **Team** を、加入した有料のチームにする
2. Xcode 上部の機種を **Any iOS Device (arm64)** にする
   （シミュレータのままだと Archive が押せない）
3. メニュー **Product → Archive**
4. 終わると Organizer が開く → **Distribute App**
   → **App Store Connect** → **Upload** → そのまま進む

> ⚠️ **ビルド番号は毎回上げる。** 同じ番号は受け付けられない。
> `project.yml` の `CURRENT_PROJECT_VERSION`（と `CFBundleVersion`）を
> 1 → 2 → 3 と増やして `xcodegen generate`。
> 表に出るバージョン（`MARKETING_VERSION` / `0.1.0`）は据え置きでよい。

### コマンドで上げる（2回目以降はこちらが楽）

```bash
# App 用のパスワードを先に作る（appleid.apple.com → サインインとセキュリティ →
# App 用パスワード）。Apple ID のパスワードそのものは使えない
export APPLE_ID="あなたの@apple.id"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
bash Tools/testflight.sh
```

## 4. TestFlight で配る

App Store Connect → 作ったアプリ → **TestFlight** タブ。

1. 上げた直後は「処理中」。**10〜30分**かかる
2. 処理が終わったら、ビルドの行に
   **「輸出コンプライアンスがありません」が出ないことを確認**
   （このアプリは `ITSAppUsesNonExemptEncryption: false` を埋めてあるので
   聞かれないはず。聞かれたら「いいえ」）
3. **内部テスト** → グループを作る → 自分を追加 → ビルドを選ぶ
   - 内部（自分と、Connect に登録した人）は**審査なしですぐ入る**
   - 外部（それ以外の人）は **Beta App Review** が要る。1〜2日
4. iPhone に **TestFlight アプリ**（App Store から無料）を入れる
5. 招待のメールが届く → 開く → インストール

## 5. 確かめること

`docs/DEVICE_TEST.md` の「何を確かめるか」と同じ。
**TestFlight でしか見られないもの**を足すとこれ:

- [ ] アイコンが正しく出る（ホーム画面・TestFlight の一覧）
- [ ] 起動画面が白い板になっていない
- [ ] 権限のダイアログの文が読んで分かる（カメラ・写真・位置）
- [ ] 端末を英語にすると、そのダイアログも英語になる
- [ ] **本番のデータが出る**（staging と違い、写真が並ぶ）

## 6. そのまま審査に出す

TestFlight で問題なければ、**同じビルドを提出できる**。
App Store Connect → **配信** タブ →「審査用に提出」。
入力するものは `docs/APP_REVIEW.md` と `docs/APP_STORE_METADATA.md` に
写せる形で置いてある。

## よくある詰まり

| 症状 | 直し方 |
|---|---|
| Archive が灰色で押せない | 機種が **Any iOS Device** になっていない |
| `No profiles for 'com.…' were found` | Team を有料チームにしていない／その Bundle ID を Identifiers に登録していない |
| `The bundle version must be higher than…` | ビルド番号を上げていない（`CURRENT_PROJECT_VERSION`） |
| `Missing Info.plist value CFBundleIconName` | アイコンが読めていない。`Assets.xcassets/AppIcon` に 1024 の PNG が在るか（`python3 Tools/check-config.py`） |
| `Invalid Bundle. ... alpha channel` | アイコンに透明が含まれている。`python3 Tools/make_app_icon.py` で作り直す（透明を持たない形で書いている） |
| 処理中のまま1時間以上 | 稀にある。もう一度ビルド番号を上げて上げ直す |
| テスターに招待が届かない | 内部テストは「App Store Connect ユーザ」に登録された人だけ。外部は Beta App Review 待ち |
| **「利用可能なビルドなし」** と出る | グループに**テスターだけ入れて、ビルドを入れていない**。テスターの招待はビルドが無くても出る。ビルドの画面 →「グループ」→ ＋ で内部グループを足す |
| ビルドを足したのに招待メールが来ない | **ビルドを足す前に出た招待が残っている**。グループ → テスター → 自分の行 →**「招待を再送信」**（2026-09-24 に実際にこれで解決） |
| iPhone の TestFlight に出ない | **「メディアと購入」**のアカウントが招待したアドレスと同じか（設定 → 自分の名前 → メディアと購入）。**TestFlight が見るのは iCloud ではなくこちら** |
| 普段の Apple アカウントと開発者アカウントが別 | **iPhone のアカウントは切り替えない。** 開発者側の「ユーザとアクセス」で普段のアドレスを招待（役割は App Manager か 管理者）→ 内部グループに入れる |
| `Validation failed (409) SDK version issue` | **iOS 26 SDK（Xcode 26）以上でないと受け取られない**（2026-09 時点の Apple の要件）。ワークフローは入っている Xcode の最新を自動で選ぶ（`Xcode を選ぶ` の段） |
| 上がっているのに実行が赤い（`missing required Beta App Information`） | `app-store-connect publish` の **`--testflight` は「外部テストの審査に出す」**。内部テストには要らない。外部に配るときだけ `betaReview: true`（先に「テスト情報」を埋める） |
