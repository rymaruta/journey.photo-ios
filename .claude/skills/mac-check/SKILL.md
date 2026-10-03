---
name: mac-check
description: 枝を Mac の CI（本物の Xcode でビルド・テスト・画面写真）で確かめる。push した枝を確かめたいとき、Mac が落ちた理由を調べるとき、画面写真を見たいときに使う。
---

# Mac で確かめる

この環境（Linux）では本物の Xcode でコンパイルできない。最初の本物の確認は
`ios-testflight.yml` の `submit=false`（TestFlight には出さない）。

## 流す

```bash
gh api -X POST repos/rymaruta/journey.photo-ios/actions/workflows/ios-testflight.yml/dispatches \
  -f ref=<枝> -f 'inputs[submit]=false'
```

待つのは `bash Tools/wait-mac-run.sh <sha7>` を **Bash の run_in_background（timeout 7200000）** で。
`sleep` を繋いで待たない（止められる）。終わると通知が来る。

## 緑なら

- 画面写真は `screenshots` 枝に置かれる（700px の JPEG）。名前は `NN-画面名_…`。
  ```bash
  git fetch -q origin screenshots
  git ls-tree --name-only origin/screenshots            # 一覧
  f=$(git ls-tree --name-only -z origin/screenshots | tr '\0' '\n' | grep '^13f')
  git show "origin/screenshots:$f" > <scratchpad>/shot.jpg   # Read で見る・SendUserFile で渡す
  ```
- owner に見せるときは「Mac のシミュレーターで自動撮影（モックではない）」と書く。

## 赤なら

1. どの段で落ちたか: `gh api repos/rymaruta/journey.photo-ios/actions/runs/<run id>/jobs --jq '.jobs[] | .name, (.steps[] | select(.conclusion=="failure") | "  " + .name)'`
2. ログは **`mcp__github__get_job_logs`**（`return_content: true`）で読む。`gh api …/logs` はリダイレクトで読めない。
   全文は数千行あるので、自分で読まず**担当（Agent）に読ませ**、`error:`・`failed`・`** TEST FAILED **` の行と原因だけ返させる。
3. UI テスト（ScreenshotTests）は「出なければ撮らずに抜ける」が決まり。撮れないのを失敗にしない。
4. 「不安定」は原因ではない。落ちた理由を突き止めて直す。テストを無効化・削除しない。

## 注意

- Mac は順番待ちが長い（30分〜1時間）。複数の枝は**統合ブランチ**にまとめて1回で流すと早い。
- 同じ枝で新しい push をしたら、古い回の結果は使わない（sha で見分ける）。
