---
name: review
description: 別の担当がコードを確かめる（読むだけ）ときの決まった手順と報告の形。ship-fix の確かめ役に読ませる。
---

# 確かめ役の決まり

- **読むだけ。** 書き換え・push・PR・GitHub へのコメントはしない。
- **メインの作業ツリー（/home/user/journey.photo-ios）の枝は切り替えない。**
  差分は `git fetch origin <枝> main` → `git diff origin/main...origin/<枝>`。
  テストを流すなら `git worktree add /tmp/claude-0/rv-<名前> origin/<枝>` を作り、終わったら `git worktree remove`。
- 枝が古い main から切られていたら、`git merge-tree --write-tree origin/main origin/<枝>` で衝突を確かめる。
- テストは `/verify` の手順で流す。
- **直しを2つ以上わざと戻して、テストが落ちるか**試す（試したら必ず元に戻す）。
  戻しても通ったものは「テストが守っていない」と書く。

## 見るところ（頼まれた重点に加えて）

1. 回帰: 前は動いていたものが壊れないか（いいね・投稿・ログアウト・人の切り替え・古い応答の上書き）。
2. 安全: 位置情報（EXIF/GPS の関所 `encodeStripped`）、権限、二重送信。
3. CLAUDE.md のデザインの決まり: 真鍮は黒地の上だけ・写真の上は白・本文12pt以上・押せるもの44pt・数字は `JPFont.mono`。
4. iOS 17 で使える書き方か（onChange の2引数など）。

## 報告の形（日本語）

最初に結論（入れてよいか）。続けて:

- **直すべき**: ファイル:行・失敗する場面・直し方
- **直したほうがよい**: 同上
- **問題なし**: 確かめた点を短く
- **確かめていないこと**: 実機・本物の Xcode など
