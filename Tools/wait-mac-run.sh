#!/bin/bash
# Mac の CI の回が終わるまで待ち、結果を1行で出す。
#   bash Tools/wait-mac-run.sh <sha の先頭7桁以上> [ワークフロー（既定 ios-quick.yml）]
# 2026-11-11: 確かめは毎回の（ios-quick.yml）とガチガチの（ios-full.yml）。上げる回は ios-testflight.yml を渡す
# 出力: <run id> <run 番号> <枝> <sha7> completed <success|failure|cancelled>
# 2時間で打ち切り（Mac の順番待ちが長い日がある）。Bash の run_in_background で流す。
set -u
sha=${1:?sha を渡す}
repo=${REPO:-rymaruta/journey.photo-ios}
workflow=${2:-ios-quick.yml}
for _ in $(seq 1 160); do
  r=$(gh api "repos/$repo/actions/workflows/$workflow/runs?per_page=20" \
        --jq ".workflow_runs[] | select(.head_sha | startswith(\"$sha\")) | \"\(.id) \(.run_number) \(.head_branch) \(.head_sha[0:7]) \(.status) \(.conclusion)\"" 2>/dev/null | head -1)
  case "$r" in *completed*) echo "$r"; exit 0 ;; esac
  sleep 45
done
echo "timeout ${r:-（回が見つからない）}"
exit 1
