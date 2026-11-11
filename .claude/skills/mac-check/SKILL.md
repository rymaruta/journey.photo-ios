---
name: mac-check
description: 枝を Mac の CI（本物の Xcode でビルド・テスト・画面写真）で確かめる。push した枝を確かめたいとき、Mac が落ちた理由を調べるとき、画面写真を見たいときに使う。
---

# Mac で確かめる

この環境（Linux）では本物の Xcode でコンパイルできない。Mac の確かめは2つだけ（2026-11-11 owner「毎回のと ガチガチので」）:

| 名前 | ワークフロー | いつ | 中身 | 時間 |
|---|---|---|---|---|
| **毎回の（クイック）** | `ios-quick.yml` | PR で自動・枝を確かめるとき手で | Mac でしか流れない単体（38 件）＋起動の見張り（SmokeTests）＋変えた画面に関係する UI＋名指し | 目標 10 分・上限 30 分 |
| **ガチガチの（フル）** | `ios-full.yml` | **原因の分からない不具合を調べるときだけ**手で | 全部の単体＋全部の UI（4 台に分けて） | 1 時間あまり |

ほかの単体（5,352 件）は PR の検証の「単体テスト（Linux・模型）」が毎回流す。TestFlight に上げる回（`ios-testflight.yml`）は
テストを流さない（Archive と上げるだけ）。

## 流す

```bash
# 毎回の（枝の確かめ）。差分に関係する UI は自動で選ぶ。足したい画面・テストは screens に
gh api -X POST repos/rymaruta/journey.photo-ios/actions/workflows/ios-quick.yml/dispatches \
  -f ref=<枝> -f 'inputs[screens]=撮影スポット, すれちがい'

# ガチガチの（原因の分からない不具合のときだけ・同時に1本）
gh api -X POST repos/rymaruta/journey.photo-ios/actions/workflows/ios-full.yml/dispatches -f ref=<枝>
```

- `screens` の区切りは `,` か `、`。何に当たるかは手元で `python3 Tools/pick-ui-tests.py "<screens>"` で先に見る
  （当たらない語があると候補を出して止まる）。`all` は毎回のでは受け付けない（ガチガチのを使う）
- 毎回のの中身は `python3 Tools/pick-ui-tests.py --quick-plan <出す場所> <diff> "<screens>"` で手元でも見られる
- 毎回のが緑なら PR をマージしてよい（2026-11-11 owner・CLAUDE.md）。同じコミットで毎回のかガチガチのが通っていれば、
  PR の毎回のは Mac を起こさない（「Mac のテストが通った（PR の検証が数える印）」）
- アプリの速さ・メモリは `screens=PerformanceTests` で名指しした毎回のだけ測る

### Xcode が上がったとき（控えの温め直し）

Mac の控え（依存と組んだもの・`DerivedData`・約 500MB）の鍵には Xcode の版と `project.yml`（依存の版）が入っている。
GitHub のランナーの Xcode が上がる・依存を変えると控えが当たらなくなり、毎回のは依存（Amplify・aws-sdk-swift）を
丸ごと組んで **30 分の上限で落ちる**（毎回のの「まとめ」に「控えが当たらなかった」と出る）。

ふだんは手を出さなくてよい: 控えを書くのは `xcode-cache-warm.yml`（Mac の控えを書く）で、
- main に入るたび・毎日 1 回（今の Xcode の控えがあるかを見て、無ければ作る）・毎回のが控えに当たらなかったとき（自動で頼む）に走る
- 作り直しは控え無しで 40〜60 分。終わってから落ちた毎回のを流し直す（`gh run rerun <run id>`）

急ぐとき・自動で頼めなかったとき（毎回のの警告「頼めませんでした」）は手で流す:

```bash
gh api -X POST repos/rymaruta/journey.photo-ios/actions/workflows/xcode-cache-warm.yml/dispatches -f ref=main
bash Tools/wait-mac-run.sh <main の sha7> xcode-cache-warm.yml   # run_in_background で待つ
```

- 書けたかは、その回の「控えを書く」の段が success か（`Cache saved with key: xcode-v2-…`）で見る
- 枝で流すと、その枝だけが読める控えを書く（測るとき以外は main で流す）

待つのは `bash Tools/wait-mac-run.sh <sha7>` を **Bash の run_in_background（timeout 7200000）** で。
`sleep` を繋いで待たない（止められる）。終わると通知が来る。

## 緑なら

- 画面写真は公開リポジトリには置かない（2026-11 から。#451）。結果は各 job の Summary を見る。

## 赤なら

1. どの段で落ちたか: `gh api repos/rymaruta/journey.photo-ios/actions/runs/<run id>/jobs --jq '.jobs[] | .name, (.steps[] | select(.conclusion=="failure") | "  " + .name)'`
2. ログは **`mcp__github__get_job_logs`**（`return_content: true`）で読む。`gh api …/logs` はリダイレクトで読めない。
   全文は数千行あるので、自分で読まず**担当（Agent）に読ませ**、`error:`・`failed`・`** TEST FAILED **` の行と原因だけ返させる。
3. UI テスト（ScreenshotTests）は「出なければ撮らずに抜ける」が決まり。撮れないのを失敗にしない。
4. 「不安定」は原因ではない。落ちた理由を突き止めて直す。テストを無効化・削除しない。

## 注意

- Mac は順番待ちが長い（30分〜1時間）。複数の枝は**統合ブランチ**にまとめて1回で流すと早い。
- 同じ枝で新しい push をしたら、古い回の結果は使わない（sha で見分ける）。
