# Mac が無いまま TestFlight に上げる

owner:「Mac もってない」

**Mac は要りません。** クラウドの Mac でビルドして、TestFlight まで上げられます。
手を動かすのは全部ブラウザと iPhone です。

---

## 何を使うか

**Codemagic**（CI サービス）を勧めます。

| 案 | Mac | 費用 | 向き不向き |
|---|---|---|---|
| **Codemagic**（推奨） | 不要 | 無料枠あり | ブラウザだけで完結。iOS 向けに作られている |
| GitHub Actions の macOS | 不要 | **枠を食う** | このアカウントの Actions 枠は逼迫していて、**photo-gallery のデプロイが止まる**（macOS は分数が10倍） |
| Xcode Cloud | 不要? | Developer Program に含む | 最初の設定に Xcode が要るという情報があり、未確認 |
| Mac を借りる（MacinCloud 等） | 借りる | 時間課金 | 1回だけなら安い。毎回借りるのは面倒 |
| Mac を買う | 買う | 高い | 長く続けるなら |

> ⚠️ **GitHub Actions は勧めません。** macOS ランナーは**分数が10倍**で課金され、
> 枠はアカウント共通。1回のビルドで `photo-gallery` のデプロイ（毎回18分）が
> 何回分も消えます。CLAUDE.md が「枠切れ＝何も出せなくなる」と書いている
> とおりで、8月に実際に20日間止まっています。

## 手順（全部ブラウザ）

### 1. Apple Developer Program に入る

<https://developer.apple.com/programs/enroll> → Individual → **年 12,980円**。
**ここだけは避けられません**（TestFlight も App Store も、この加入が前提）。
支払いと本人確認で**1〜2日**かかることがあります。

### 2. App Store Connect でアプリの枠を作る

<https://appstoreconnect.apple.com> → **マイ App** → **＋** → 新規 App

| 欄 | 入れるもの |
|---|---|
| プラットフォーム | iOS |
| 名前 | Journey Photo — 旅の写真 |
| 主要言語 | 日本語 |
| バンドル ID | `com.journeyphoto.JourneyPhoto` |
| SKU | `journey-photo-ios` |

バンドル ID が一覧に出なければ、先に
<https://developer.apple.com/account/resources/identifiers/> で
**＋ → App IDs → App → Explicit** で登録（Capability は何も足さない）。

作ったら、**アプリの Apple ID（数字）**を控えます。App Store Connect で
そのアプリを開いたときの URL に出ています:
`…/apps/`**`1234567890`**`/…`

### 3. App Store Connect の API キーを作る

これが**証明書の代わり**になります（Mac も Keychain も要りません）。

<https://appstoreconnect.apple.com/access/integrations/api> →
**チームキー** タブ → **＋**

- 名前: `Codemagic`
- アクセス: **App Manager**

作ると3つ手に入ります。**`.p8` は一度しか落とせません**:

| もの | どこに出るか |
|---|---|
| Issuer ID | ページの上のほう |
| Key ID | 作ったキーの行 |
| `AuthKey_XXXX.p8` | 「ダウンロード」ボタン |

### 4. Codemagic に繋ぐ

1. <https://codemagic.io> → **GitHub でサインアップ**
2. `rymaruta/journey.photo-ios` を選んで追加
3. **Teams → Integrations → App Store Connect → Add key**
   - Name: **`JourneyPhotoASC`**（`codemagic.yaml` に書いてある名前と**同じに**）
   - Issuer ID / Key ID / `.p8` を入れる

### 5. ビルドする前に1か所だけ直す

`codemagic.yaml` の `APP_APPLE_ID` を、**手順2で控えた数字**に変えます。
この会話で「アプリの Apple ID は 1234567890」と伝えてもらえれば、こちらで直します。

### 6. ビルドする

Codemagic の画面でリポジトリを開き、ブランチを
`claude/journey-photo-ios-app-ffos85` にして **Start new build**。

だいたい **10〜20分**。終わると:

- TestFlight に上がる（App Store Connect の TestFlight タブで「処理中」→ 10〜30分）
- 結果がメールで届く

**落ちたら、Codemagic の画面のログをそのまま貼ってください。** 直します。

### 7. iPhone で受け取る

1. App Store Connect → アプリ → **TestFlight** タブ
2. **内部テスト** → グループを作る → 自分を追加 → ビルドを選ぶ
3. iPhone に **TestFlight** アプリ（App Store・無料）を入れる
4. 招待のメールが届く → 開く → インストール

## 何を確かめるか

`docs/TESTFLIGHT.md` の「確かめること」。
⚠️ **TestFlight のビルドは本番に繋がります。** 試しの投稿は
「すぐ公開する」をオフにするか、あとで消してください。

## 提出するとき

TestFlight で問題なければ、App Store Connect → **配信** タブ →
「審査用に提出」。入力するものは `docs/APP_REVIEW.md` と
`docs/APP_STORE_METADATA.md` にそのまま写せる形で置いてあります。

**スクリーンショットだけは絵が要ります。** Mac が無いので、
TestFlight で入れた自分の iPhone で撮ってください
（サイドボタン＋音量を上げるボタンの同時押し）。6.7インチの端末が
無い場合は、**持っている端末で撮ったものを App Store Connect が
引き伸ばして受け付ける**ことがありますが、確実なのは 6.7インチです。
借りるか、ここで詰まったら相談してください。
