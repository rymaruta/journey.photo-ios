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

> ⚠️ **ビルド番号は表に出る版ごとに 1 から数える**（2026-10-18 owner の判断:
> TestFlight の表示を「1.1.15 (1)」の形に）。同じ版の中で同じ番号は受け付けられない。
> GitHub Actions ではその版の TestFlight の最新 +1（無ければ 1）を自動で付ける。
> 手で上げるときは `bash Tools/bump-build.sh <版>`（版を変えたら 1・同じ版なら +1）の
> あと `xcodegen generate`。
> Apple の決まりは「版とビルド番号の組み合わせが重ならない」こと（iOS は新しい版で前より小さい番号を使ってよい。Mac は版をまたいでも上がり続ける必要がある）。出典: [Setting the next build number for Xcode Cloud builds](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds)（2026-10-18 確認）。
> 表に出るバージョン（`MARKETING_VERSION`）は、**GitHub Actions で上げるときは
> 毎回自動で最後の数字が1つ上がる**（0.2.0 → 0.2.1 …・`Tools/next-marketing-version.sh`。
> 出した版は `testflight/<版>` のタグで覚える）。大きく変わる版で真ん中の数字を
> 上げたいときは `bash Tools/bump-build.sh 0.3.0` でコミットしてから流す。
> Xcode から手で上げるときは、この自動は働かないので自分で上げる。

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

## 7. 落ちた記録を読む（2026-11-14・札 #596）

実機だけで落ちるときは、実機の落ちた記録から原因を確かめる（CLAUDE.md「推定で直さない」）。

**届くもの。** テスターが落ちたあとの TestFlight の知らせで「共有」を押した記録だけが、App Store Connect の
フィードバックに届く（API の `betaFeedbackCrashSubmissions`）。共有しなかった落ちは API では取れない
（`diagnosticSignatures` が扱うのは `DISK_WRITES`・`HANGS`・`LAUNCHES` だけで、落ちたものは含まない。Apple の文書で確認）。
共有し忘れたときは、iPhone の「設定 → プライバシーとセキュリティ → 解析と改善 → 解析データ」にある
`JourneyPhoto-<日時>.ips` を送ってもらう（項目の名前は iOS の版で変わることがある）。

**取る。** Actions の「TestFlight crashes」（`.github/workflows/testflight-crashes.yml`）を版（例 `1.1.85`）を入れて流す。
本文は画面写真と同じ非公開の S3 に置かれ（3日で消える）、ログには件数と要点（版・ビルド・日時・例外の型・
落ちたスレッドの上の数段の関数名）だけが出る。手元へは
`bash Tools/fetch-shots.sh testflight-crashes-<run 番号>` → scratchpad の `.../crashes/` に
`<番号>-<日時>-b<ビルド>.ips`（または `.crash`）と同じ名前の `.json`（端末・OS・テスターの書いた言葉）、要点の `index.json`。
**見終わったら `--delete`**（端末の識別子・利用者の言葉が入りうる。リポジトリ・Issue・PR に貼らない。貼るのは関数名と行だけ）。

**読む。** `.ips` は1行目が見出しの JSON、2行目からが本体の JSON。本体の `exception`（型と信号）、
`faultingThread`（落ちたスレッドの番号）、`threads[番号].frames`（上から順に `imageIndex`・`imageOffset`・
あれば `symbol`・`sourceFile`・`sourceLine`）、`usedImages`（`name`・`uuid`・`base`）を見る。
Swift の止まり（`fatalError`・配列の範囲外・`!` で nil）は `EXC_BREAKPOINT (SIGTRAP)` になり、
理由の文は本体の `asi` などに入る。

**シンボル化が要るか。** JourneyPhoto の段に `symbol` と `sourceFile` があれば要らない（そのまま落ちた行）。
`+0x…（シンボル無し）` だけならシンボル化が要る。

- **dSYM は CI に残っていない。** `ios-testflight.yml` は Archive を Mac のランナーの `build/ios/xcarchive/` に作るが、
  成果物 `build-logs` に入れるのは ipa と `app-size.txt` だけで、ビルドの控えからも `*.dSYM` を外している。
  同じコミットを組み直しても UUID が変わるので、あとから作った dSYM では読めない
- **App Store Connect にはシンボルが送られているはず。** `xcode-project build-ipa` は `uploadSymbols` を指定せず
  （codemagic-cli-tools 0.70.2 の書き出しの設定で確認）、Xcode の既定（App Store 向けは送る）になる。
  その場合、Mac の Xcode の Organizer（Window → Organizer → Crashes）で版を選ぶと、Apple がシンボル化した記録が見られる。
  **API の `logText` が Apple の側でシンボル化済みかは、まだ確かめていない**（初回に取ったもので確かめる）
- 手元に同じビルドの dSYM があるときだけ（`dwarfdump --uuid` が `usedImages` の `uuid` と同じ）、Mac で
  `atos -arch arm64 -o JourneyPhoto.app.dSYM/Contents/Resources/DWARF/JourneyPhoto -l <base> <base + imageOffset>`
- 今後のために、Archive の dSYM を非公開の S3 に置く段を `ios-testflight.yml` に足すかは別に決める（まだ入れていない）

## よくある詰まり

| 症状 | 直し方 |
|---|---|
| Archive が灰色で押せない | 機種が **Any iOS Device** になっていない |
| `No profiles for 'com.…' were found` | Team を有料チームにしていない／その Bundle ID を Identifiers に登録していない |
| `The bundle version must be higher than…` | 同じ版の中でビルド番号を上げていない（`CURRENT_PROJECT_VERSION`）。手元の番号が TestFlight のその版の最新より低いときは `bash Tools/set-build-number.sh <最新+1>` |
| `Missing Info.plist value CFBundleIconName` | アイコンが読めていない。`Assets.xcassets/AppIcon` に 1024 の PNG が在るか（`python3 Tools/check-config.py`） |
| `Invalid Bundle. ... alpha channel` | アイコンに透明が含まれている。`NODE_PATH=../photo-gallery/node_modules node Tools/make-brand-assets.cjs` で作り直す（透明を持たない形で書く）。`Tools/check-config.py` が手元で先に落とす |
| 処理中のまま1時間以上 | 稀にある。もう一度ビルド番号を上げて上げ直す |
| テスターに招待が届かない | 内部テストは「App Store Connect ユーザ」に登録された人だけ。外部は Beta App Review 待ち |
| **「利用可能なビルドなし」** と出る | グループに**テスターだけ入れて、ビルドを入れていない**。テスターの招待はビルドが無くても出る。ビルドの画面 →「グループ」→ ＋ で内部グループを足す |
| ビルドを足したのに招待メールが来ない | **ビルドを足す前に出た招待が残っている**。グループ → テスター → 自分の行 →**「招待を再送信」**（2026-09-24 に実際にこれで解決） |
| iPhone の TestFlight に出ない | **「メディアと購入」**のアカウントが招待したアドレスと同じか（設定 → 自分の名前 → メディアと購入）。**TestFlight が見るのは iCloud ではなくこちら** |
| 普段の Apple アカウントと開発者アカウントが別 | **iPhone のアカウントは切り替えない。** 開発者側の「ユーザとアクセス」で普段のアドレスを招待（役割は App Manager か 管理者）→ 内部グループに入れる |
| `Validation failed (409) SDK version issue` | **iOS 26 SDK（Xcode 26）以上でないと受け取られない**（2026-09 時点の Apple の要件）。ワークフローは入っている Xcode の最新を自動で選ぶ（`Xcode を選ぶ` の段） |
| 上がっているのに実行が赤い（`missing required Beta App Information`） | `app-store-connect publish` の **`--testflight` は「外部テストの審査に出す」**。内部テストには要らない。外部に配るときだけ `betaReview: true`（先に「テスト情報」を埋める） |
