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

### 変えた画面の絵だけ撮る（`screens`・2026-10-17）

全部を流すと1回 約70分（run 462: 組む12分・単体6分・UI 33分・Archive 11分）。枝の確認では
**変えた画面の名前（撮る絵の名前の一部）かテスト名の一部**を `screens` に渡して絞る:

```bash
gh api -X POST repos/rymaruta/journey.photo-ios/actions/workflows/ios-testflight.yml/dispatches \
  -f ref=<枝> -f 'inputs[submit]=false' -f 'inputs[screens]=撮影スポット, すれちがい'
```

- 区切りは `,` か `、`。何に当たるかは手元で `python3 Tools/pick-ui-tests.py "<screens>"` で先に見る
  （当たらない語があると候補を出して止まる。Mac でも最初の数秒で止まる）
- 起動の見張り（`SmokeTests`）はいつも入る。`none` なら見張りだけ（絵の要らない直し）
- 単体テストは絞らない（全3700件・6分）。単体が落ちたら UI まで行かずに止まる
- 絞った回は Archive（Release の組み立て・約10分）もしない
- **マージの前は絞った回で足りる（2026-11-11 owner・CLAUDE.md）。** 単体（全部）＋機能の UI＋変えた画面の UI＋起動の見張りが
  緑なら PR をマージしてよい。毎回30分以内
- 全部を流す（`screens=all`）のは、原因の分からない不具合を調べる時だけ

待つのは `bash Tools/wait-mac-run.sh <sha7>` を **Bash の run_in_background（timeout 7200000）** で。
`sleep` を繋いで待たない（止められる）。終わると通知が来る。

## 緑なら

- 画面写真は**非公開の S3** に置かれる（700px の JPEG・3日で自動で消える。`screenshots` 枝は #451 で止めた）。
  落ちた回も置かれる。名前は `NN-画面名_…`。run の印は TestFlight の回なら run 番号（Release Center から呼ばれた回は
  `release-center-<番号>`。各 Mac の job の Summary に出る）。
  ```bash
  bash Tools/fetch-shots.sh --list                  # 置き場にある run の一覧
  bash Tools/fetch-shots.sh <run>                   # scratchpad の shots/<run>/<組>/ に落とす（Read で見る・SendUserFile で渡す）
  bash Tools/fetch-shots.sh <run> --delete          # 見終わったら手元と S3 からすぐ消す（手元だけなら --clean）
  ```
  落とす先はリポジトリの外だけ（中を指すと止まる）。見たら必ず消す。
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
