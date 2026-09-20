# リリース手順

**この順番でやる。** 途中で詰まりやすいところに注記を置いた。

---

## 0. 先に済ませること（初回だけ）

| やること | どこで | 備考 |
|---|---|---|
| Apple Developer Program に加入 | developer.apple.com | 年 12,980円（2026年時点）。加入待ちで1〜2日かかることがある |
| App ID の作成 | Developer → Identifiers | `com.journeyphoto.JourneyPhoto`。**Capability は追加不要**（プッシュも Sign in with Apple も使っていない） |
| App の作成 | App Store Connect | 名前・プライマリ言語（日本語）・Bundle ID・SKU |

`project.yml` の `JP_BUNDLE_ID` は `Config/Production.xcconfig` から入る。
別の ID を取ったらそちらを直す（2か所に書かない）。

## 1. 手元でビルドを通す

```bash
brew install xcodegen
xcodegen generate
open JourneyPhoto.xcodeproj
```

**`.xcodeproj` はコミットしない。** 定義は `project.yml` と
`Config/*.xcconfig` だけ。生成物を git に入れるとマージのたびに競合する。

初回は Swift Package（Amplify Swift）の解決に数分かかる。

```bash
bash Tools/verify.sh    # 構文・設定・（Mac なら）ビルドとテスト
```

> ⚠️ **このリポジトリのコードは、作成環境（Linux）で一度もコンパイルされて
> いない。** Swift ツールチェーンを入れられなかったため（`download.swift.org`
> も GitHub のリリース資産もネットワークポリシーで遮断）。
> **最初の `xcodegen generate` でエラーが出る前提**で読むこと。
> `Tools/verify.sh` が見ているのは構文と設定の食い違いまでで、型は見ていない。

## 2. staging で動作を見る

Debug ビルド = staging（`Config/Staging.xcconfig`）。

**staging には写真もユーザーも入っていない**（本番からコピーしていない）。
新規登録から順に触って、次を確かめる:

- [ ] 登録 → 確認コード → ログイン
- [ ] カメラで撮って投稿 → マイページに出る
- [ ] 写真ライブラリから投稿 → EXIF が落ちている（撮影地が勝手に入らない）
- [ ] いいね・コメント・フォロー
- [ ] 通報・ブロック・ブロック解除
- [ ] アカウント削除 → ログアウトされる
- [ ] 機内モードで起動 → 前回の一覧と、一度見た写真が出る

## 3. 本番向けにアーカイブ

Xcode の **Product → Archive**（スキームの Archive は Release ＝本番設定）。

- [ ] `Config/Production.xcconfig` の向き先が本番になっている
- [ ] バージョン（`MARKETING_VERSION`）とビルド番号（`CURRENT_PROJECT_VERSION`）を上げた
      ——**ビルド番号は提出のたびに必ず上げる**。同じ番号は受け付けられない
- [ ] アイコンが入っている（`Assets.xcassets/AppIcon`）

Organizer → **Distribute App → App Store Connect → Upload**。

## 4. TestFlight で自分の端末に入れて確かめる

シミュレータでは確かめられないものがここで初めて見られる:

- **カメラ**（シミュレータにカメラが無いので `CameraPicker.isAvailable` が false）
- 実機の写真ライブラリにある HEIC が通るか
- 通信が細いところでの挙動

## 5. 提出

`docs/APP_REVIEW.md` の内容を App Store Connect に写す:

- App Review Information → Notes（あの文面をそのまま）
- Demo Account（**owner が本番に作る**。写真を1枚は投稿しておく）
- App のプライバシー（`PrivacyInfo.xcprivacy` と**同じ答え**にする）
- 年齢制限の質問票（ユーザー生成コンテンツ＝はい）
- サポート URL / マーケティング URL（`docs/APP_STORE_METADATA.md`）

## 6. 出したあと

- **API を壊す変更を出すときは、アプリの古い版がまだ動いていることを忘れない。**
  Web と違って**利用者は更新しない**。`api-user` の応答から項目を消すときは、
  アプリ側が optional で受けているか確かめる（このアプリのモデルは
  `id` と `src` 以外すべて optional にしてある）
- 静的な写真一覧（`app/data/photos.json`）の形を変えるときも同じ。
  アプリのギャラリーはこれを直接読んでいる

## 費用と枠についての注意

**GitHub Actions に iOS のビルドを載せていない。** macOS ランナーは
**分数が10倍**で課金され、枠はアカウント共通（2026-09 時点で残り約193分）。
1回のビルドで `photo-gallery` のデプロイを止めかねない。
枠に余裕ができるまで、ビルドは手元の Xcode で行う。
