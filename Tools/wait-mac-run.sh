#!/bin/bash
# Mac の CI（ios-testflight.yml）の回が終わるまで待ち、結果を1行で出す。
#   bash Tools/wait-mac-run.sh <sha の先頭7桁以上>          # テストの回（ビルドだけの回は見ない）
#   bash Tools/wait-mac-run.sh <sha の先頭7桁以上> build    # ビルドだけの回（screens=build）
# 出力: <run id> <run 番号> <枝> <sha7> completed <success|failure|cancelled>
# 2時間で打ち切り（Mac の順番待ちが長い日がある）。Bash の run_in_background で流す。
#
# 2026-11-18 判断: ビルドだけの回とテストの回は同じ sha で続けて流す。sha だけで探すと、テストの回が
# 一覧に出る前の数秒に、終わったビルドだけの回を拾って「終わった」と返す。回の名前（run-name。
# ビルドだけの回は「ビルドだけ」、ほかは「TestFlight」）で見分ける
set -u
sha=${1:?sha を渡す}
kind=${2:-test}
repo=${REPO:-rymaruta/journey.photo-ios}
case "$kind" in
  build) pick='.display_title == "ビルドだけ"' ;;
  test)  pick='.display_title != "ビルドだけ"' ;;
  *) echo "2つ目は build か test（省くと test）" >&2; exit 2 ;;
esac
for _ in $(seq 1 160); do
  r=$(gh api "repos/$repo/actions/workflows/ios-testflight.yml/runs?per_page=30" \
        --jq ".workflow_runs[] | select((.head_sha | startswith(\"$sha\")) and ($pick)) | \"\(.id) \(.run_number) \(.head_branch) \(.head_sha[0:7]) \(.status) \(.conclusion)\"" 2>/dev/null | head -1)
  case "$r" in *completed*) echo "$r"; exit 0 ;; esac
  sleep 45
done
echo "timeout ${r:-（回が見つからない）}"
exit 1
