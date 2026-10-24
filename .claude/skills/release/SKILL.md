---
name: release
description: main を TestFlight に出す。「出して」「TestFlight」「リリース」と言われたとき。版は自動で上がる。
---

# TestFlight に出す

CLAUDE.md の「リリースのたびに版を上げる」を守る。版（MARKETING_VERSION）は
ワークフローが自動で +1 し、`testflight/<版>` のタグを付ける。

## 手順

1. 出すものが main に入っていて、それぞれ Mac で緑（`/mac-check`）か確かめる。
2. **owner に「リリースしていいか」を聞き、返事をもらってから**流す（CLAUDE.md）。
3. 流す（**Cursor から完結**・2026-10-24）:
   ```bash
   bash Tools/cursor-dispatch-mac.sh testflight main
   # 出力: <run id> ios-testflight main <sha7>
   ```
   - Cursor の連携トークンは `workflow_dispatch` が 403 なので、`repository_dispatch` を使う。
   - 古い `gh api …/dispatches`（workflow_dispatch）は使わない。
4. `bash Tools/wait-mac-run.sh --run-id <run id>` を run_in_background で待つ。
5. 版を確かめる（推測で言わない）:
   ```bash
   git fetch -q origin --tags
   git tag -l 'testflight/*' --sort=-v:refname | head -1      # 版
   git rev-list -n1 <そのタグ> | cut -c1-7                    # main の sha と一致すること
   ```

## owner への報告（日本語・短く）

- 「TestFlight に 1.0.NN を出しました（main の <sha7>）。Mac のビルドとテストは通っています。」
- **実機で見てほしいところ**を、入った機能ごとに1行ずつ（どの画面で・何を押すと・何が起きるはずか）。
- 確かめていないこと（実機の動き・メモリ等）を1行。
- TestFlight のメールを毎回送らない（owner の希望）。

## やらないこと

- 手元から Archive しない（版のタグが付かない）。どうしても手元から出すときは `bash Tools/bump-build.sh <版>` で上げ、出した版を owner に伝える。
- 真ん中・先頭の数字（1.1.0 など）は自動で上げない。owner が決める。
- owner の許可なしに `testflight` を流さない。
