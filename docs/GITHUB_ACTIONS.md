# GitHub Actions で TestFlight に上げる

owner の選択（2026-09-21）:「Actions にしよう！」

`codemagic.yaml` も残してあります（どちらでも回せます）。

---

## ⚠️ 最初に: リポジトリを **public** にする

macOS ランナーは **private だと分数が10倍**で課金され、枠は owner の
アカウント共通です。`photo-gallery` のデプロイ（毎回18分）が何回分も消え、
CLAUDE.md が書いている「枠切れ＝何も出せなくなる」状態に直行します
（2026-08 に実際に20日間止まっています）。

**public なら標準ランナーは無料**（分数を消費しません）。

- GitHub → `journey.photo-ios` → **Settings** → 最下部 **Danger Zone** →
  **Change repository visibility** → **Public**

このリポジトリに秘密はありません（Cognito の ID などは公開識別子で、
アプリのバイナリからも読めるもの）。**Secrets は公開されません**。

> public にしたくない場合は Codemagic を使ってください（`docs/NO_MAC.md`）。
> そちらは無料枠が別勘定で、photo-gallery の枠に影響しません。

## 手順1: App Store Connect の API キー

<https://appstoreconnect.apple.com/access/integrations/api> →
**チームキー** → **＋** → 名前 `GitHubActions` / アクセス **App Manager**

控えるもの（`.p8` は一度しか落とせません）:

| もの | Secrets の名前 |
|---|---|
| Issuer ID | `APP_STORE_CONNECT_ISSUER_ID` |
| Key ID | `APP_STORE_CONNECT_KEY_ID` |
| `AuthKey_XXXX.p8` の**中身**（全文・`-----BEGIN` から `-----END` まで） | `APP_STORE_CONNECT_PRIVATE_KEY` |

## 手順2: 署名用の秘密鍵（`CERTIFICATE_PRIVATE_KEY`）

**これが無いと、実行のたびに新しい配布証明書が作られます**——Apple の上限
（配布証明書は2枚）にすぐ当たり、そこから先は毎回落ちます。

RSA の鍵を1つ作って Secrets に入れます。Mac は要りません:

```bash
ssh-keygen -t rsa -b 2048 -m PEM -f jp-signing-key -q -N ""
cat jp-signing-key   # この全文を Secrets へ
```

手元に端末が無ければ、この会話で「署名用の鍵を作って」と言ってください
（私が作ってファイルで渡します。**チャットには貼りません**）。

## 手順3: Secrets を入れる

GitHub → `journey.photo-ios` → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret** で4つ:

- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `CERTIFICATE_PRIVATE_KEY`

## 手順4: 流す

GitHub → **Actions** → **TestFlight** → **Run workflow** →
ブランチ `claude/journey-photo-ios-app-ffos85` → **Run**

- 「ビルドだけ試す」なら `submit` を **false** に（TestFlight へは上げません）
- 所要 20〜40分（初回は道具の取得ぶん長め）
- 落ちたらログをそのまま貼ってください

## この構成の中身

| 段 | すること |
|---|---|
| 設定の検査 | `Tools/check-config.py`（Bundle ID の食い違い・版番号の二重管理などを先に弾く） |
| 道具 | `xcodegen` と `codemagic-cli-tools`（Codemagic が公開している CLI。**Mac も Keychain も要らない**署名の要） |
| テスト | 実機の SDK で `xcode-project run-tests`。**本物の SwiftUI に当たる最初の機会** |
| 署名 | API キーから証明書とプロファイルを**作って**取り込む |
| ビルド番号 | **TestFlight にある最大 + 1**（上げ忘れではねられない） |
| ビルド | `xcode-project build-ipa` |
| 提出 | `app-store-connect publish --testflight`（**審査には自動で出さない**） |
