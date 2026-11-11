---
name: release
description: main を TestFlight に出す。「出して」「TestFlight」「リリース」と言われたとき。版は自動で上がる。
---

# TestFlight に出す

CLAUDE.md の「リリースのたびに版を上げる」を守る。版（MARKETING_VERSION）は
ワークフローが自動で +1 し、`testflight/<版>` のタグを付ける。

## 手順

1. 出すものが main に入っていて、それぞれ Mac で緑（`/mac-check`）か確かめる。
   - 出す前に、`Sources/JourneyPhoto/Resources/WhatsNew.json` に今回の版（直近の `testflight/*` の最後の数字 +1）の項目を足したか確かめる（利用者に見える変更が無い版は足さない。`WhatsNew.pending` は見た版より新しい版を全部出すので、足し忘れた分は次の版にまとめて足せる）。
2. 流す:
   ```bash
   gh api -X POST repos/rymaruta/journey.photo-ios/actions/workflows/ios-testflight.yml/dispatches \
     -f ref=main -f 'inputs[submit]=true'
   ```
3. `bash Tools/wait-mac-run.sh <main の sha7> ios-testflight.yml` を run_in_background で待つ。
4. 版を確かめる（推測で言わない）:
   ```bash
   git fetch -q origin --tags
   git tag -l 'testflight/*' --sort=-v:refname | head -1      # 版
   git rev-list -n1 <そのタグ> | cut -c1-7                    # main の sha と一致すること
   ```

## owner への報告（日本語・短く）

- 「TestFlight に 1.0.NN を出しました（main の <sha7>）。（上げる回は Archive と上げるだけ。テストは PR の毎回の（ios-quick.yml）で通っています）」
- **実機で見てほしいところ**を、入った機能ごとに1行ずつ（どの画面で・何を押すと・何が起きるはずか）。
- 確かめていないこと（実機の動き・メモリ等）を1行。
- TestFlight のメールを毎回送らない（owner の希望）。

## やらないこと

- 手元から Archive しない（版のタグが付かない）。どうしても手元から出すときは `bash Tools/bump-build.sh <版>` で上げ、出した版を owner に伝える。
- 真ん中・先頭の数字（1.1.0 など）は自動で上げない。owner が決める。
