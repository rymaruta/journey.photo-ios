# 実機で確かめる（はじめての人向け）

owner:「実機の確認の仕方わからない」への答え。**iPhone に自分でアプリを入れて
動かす**までを、詰まりやすいところ込みで書く。

---

## まず結論

**お金はかからない。** Apple ID があれば、自分の iPhone には無料で入れられる
（7日で切れるが、入れ直せばよい）。有料の Developer Program（年 12,980円）が
要るのは **TestFlight と App Store への提出**からで、実機確認だけなら不要。

## 用意するもの

| もの | 備考 |
|---|---|
| Mac | Xcode が動くもの |
| Xcode | App Store から無料。**10GB 以上**あるので先に落としておく |
| iPhone | 普段使っているもので構わない |
| ケーブル | Mac と iPhone を繋ぐ（Wi-Fi でもできるが最初は有線が確実） |
| Apple ID | 普段の Apple ID でよい |

## 手順

### 1. プロジェクトを開く

```bash
brew install xcodegen      # まだなら
cd journey.photo-ios
bash Tools/mac-release.sh  # 生成 → ビルド → テスト
open JourneyPhoto.xcodeproj
```

`mac-release.sh` が赤くなったら、その内容を貼ってください（こちらで直します）。
**緑になってから先へ進む**——実機の設定でつまずいているのか、コードが
悪いのかが混ざると、原因を追えなくなる。

### 2. 署名の設定（初回だけ）

Xcode の左の一覧で **JourneyPhoto**（いちばん上の青いアイコン）を選ぶ →
**Signing & Capabilities** タブ。

1. **Team** の欄で `Add an Account…` → 自分の Apple ID でサインイン
2. Team に自分の名前（Personal Team）が出るので選ぶ
3. **Automatically manage signing** にチェックが入っていることを確認

> ⚠️ **`Failed to register bundle identifier` と出たら**、その ID は世界の誰かが
> 既に使っている。`Config/Production.xcconfig` の `JP_BUNDLE_ID` を
> 自分だけの値に変えて、`xcodegen generate` をやり直す。
> 例: `com.rymaruta.journeyphoto`
>
> ⚠️ **無料の Apple ID は7日で切れる。** 8日目にアプリを開くと
> 「App を検証できません」と出る。Xcode から入れ直せば直る（消さなくてよい）。

### 3. iPhone を繋いで、デベロッパモードを入れる

1. ケーブルで Mac に繋ぐ
2. iPhone に「このコンピュータを信頼しますか？」→ **信頼**
3. iPhone の **設定 → プライバシーとセキュリティ → デベロッパモード** → **オン**
   → 再起動を求められるので再起動

> ⚠️ **デベロッパモードの項目が見当たらない**ときは、一度 Xcode から
> 実行（次の手順）を試すと現れる。iOS 16 以降にだけある項目。

### 4. iPhone に入れて動かす

1. Xcode の上のほう、実行ボタン（▶）の右にある**機種の名前を押す**
2. 一覧から**自分の iPhone**を選ぶ（シミュレータではない）
3. **▶ を押す**

初回は iPhone 側で1つ許可が要る:

**設定 → 一般 → VPN とデバイス管理 → デベロッパ App →（自分の Apple ID）→ 信頼**

これで iPhone のホーム画面にアプリが並ぶ。以後は Xcode を使わずに開ける。

> ⚠️ ここで入るのは **Debug ビルド＝ staging** に繋がる版。
> **本番のデータは入っていない**ので、staging で新規登録して試す。
> 本番で試したいときは Xcode の `Product → Scheme → Edit Scheme… → Run →
> Build Configuration` を `Release` にする。

## 何を確かめるか

**シミュレータでは確かめられないもの**が本番。上から順に。

- [ ] **カメラから投稿**（シミュレータにカメラが無いので、ここが初めて）
      撮る → 説明を書く → 投稿 → マイページに並ぶ
- [ ] **写真ライブラリから投稿**
      **撮影地が勝手に入っていないこと**（EXIF を落としているか）
- [ ] 撮影地の欄に2文字以上打つ → 候補が出る → 選ぶと地図にも載る
- [ ] 曲を付ける → 試し聴きが鳴る → 投稿後、写真の詳細で鳴る
- [ ] 写真を押す → 全画面 → 左右に送れる → つまんで拡大 → 2回叩いて戻る
- [ ] いいね・コメント
- [ ] 他人の写真で「…」→ **通報** → その写真が一覧から消える
- [ ] 「…」→ **ブロック** → その人の写真が消える
      → 設定 → ブロックした人 → **解除すると戻る**
- [ ] 設定 → **アカウントの削除** →「削除」と打って実行 → ログアウトされる
      （staging の捨てアカウントで試すこと）
- [ ] **機内モードにして起動** → 前に見た一覧と写真が出る
- [ ] iPhone の 設定 → 一般 → 言語と地域 で **English** にして起動
      → 画面と、カメラの許可を聞くダイアログが英語になる

見つけたことは、**画面の写真と「何をしたら何が起きたか」**を貼ってください。

## スクリーンショット（申請用）

**実機で撮らなくてよい。** App Store は**シミュレータで撮ったもの**も
受け付ける。必要なのは **6.7インチ**（iPhone 15 Pro Max など）で最低3枚。

```bash
# シミュレータを 15 Pro Max にして実行し、撮る
xcrun simctl boot "iPhone 15 Pro Max"
# Xcode で ▶ → シミュレータのメニュー File → Save Screen
```

実機で撮るなら **サイドボタン＋音量を上げるボタン**を同時押し。

**入れないもの**: 人の顔、他人の投稿。権利の確認を求められることがある。

出す順（`docs/APP_STORE_METADATA.md` と対）:
ギャラリー → 写真の詳細 → 投稿 → 地図 → 年表

## よくある詰まり

| 症状 | 原因と直し方 |
|---|---|
| `Signing for "JourneyPhoto" requires a development team` | 手順2の Team を選んでいない |
| `Failed to register bundle identifier` | ID が取られている。`JP_BUNDLE_ID` を変えて `xcodegen generate` |
| iPhone が一覧に出ない | ケーブルを挿し直す／「信頼」を押していない／デベロッパモードが入っていない |
| 「App を検証できません」 | 無料アカウントの7日が切れた。Xcode から入れ直す |
| 起動してすぐ落ちる | `Config/*.xcconfig` の値が欠けている（`AppConfig` はわざと落とす）。`python3 Tools/check-config.py` |
| 写真が1枚も出ない | staging には写真が無い。自分で投稿するか、Release ビルドにする |
| ログインできない | staging と本番でアカウントは別物。staging で新規登録する |
