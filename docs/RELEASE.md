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

> 1〜3 は `bash Tools/mac-release.sh` で一度に走る。

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

> ⚠️ **ここまでに Linux で確かめてあること**（`Tools/verify.sh`）:
> 全 70 ファイルのコンパイル（`Shims/` の模型に向けて）・テスト60件・
> `xcodegen generate` の成功・`api-user` との突き合わせ（50/50）・設定の整合。
>
> ⚠️ **確かめていないこと**: 本物の SwiftUI での型検査と、実機での挙動。
> 模型の修飾子は素通しなので、ViewBuilder の枝の数・`some View` の同一性・
> 修飾子の順序・レイアウト・実行時の挙動は見ていない。
> **最初の `xcodebuild` で SwiftUI 固有のエラーが出る前提**で読むこと
> （自分たちのコードの綴り違いや型の取り違えは、もう出ないはず）。

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
- [ ] 版を上げた。**リリースのたびに必ず上げる**（2026-09-26 owner のルール）
      - **GitHub Actions（`ios-testflight.yml`）で上げるなら何もしなくてよい。**
        表に出る版（`MARKETING_VERSION`）の最後の数字は毎回自動で +1
        （1.0.0 → 1.0.1 …・`Tools/next-marketing-version.sh`）、ビルド番号は
        TestFlight の最新 +1。出した版は `testflight/<版>` のタグで覚える
      - **手元の Xcode から上げるときだけ**、`bash Tools/bump-build.sh 1.0.1` の
        ように版とビルド番号を自分で上げる。同じ番号は受け付けられない
      - 真ん中・先頭の数字（1.1.0・2.0.0）を上げるのは、大きく変わる版のときに
        人が決める：`bash Tools/bump-build.sh 1.1.0` でコミットしてから流す
- [ ] アイコンが入っている（`Assets.xcassets/AppIcon`）

Organizer → **Distribute App → App Store Connect → Upload**。

## 4. 実機で確かめる

**はじめてなら `docs/DEVICE_TEST.md` を見ること。** 無料の Apple ID で
自分の iPhone に入れられる（有料の Developer Program は TestFlight と
提出にだけ要る）。

## 4b. TestFlight で確かめる

**手順は `docs/TESTFLIGHT.md`。** 加入・App Store Connect でのアプリ作成・
Archive・配布まで書いてある。ビルド番号は `bash Tools/bump-build.sh` で上げる
（同じ番号は受け付けられない）。

### 以前の記述

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
