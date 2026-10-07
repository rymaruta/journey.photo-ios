#!/bin/bash
# 使い終わった枝を選び、APPLY=true のときだけ消す（`.github/workflows/cleanup-branches.yml` から呼ぶ）。
#
# 消すのは「中身が main に入り終えた枝」だけ:
#  1. 枝の先頭が origin/main の履歴に含まれる
#  2. その枝の PR が併合済みで、枝の先頭がそのときの先頭のまま（squash 併合）
# 残すのは main・screenshots・開いている PR の枝・それ以外のまだ入っていない枝。
#
# 要るもの: 全履歴の checkout（fetch-depth: 0）・gh（GH_TOKEN）・REPO=owner/name。
# 手元でも試せる: `REPO=rymaruta/journey.photo-ios APPLY=false bash Tools/cleanup-branches.sh`
set -euo pipefail

: "${REPO:?REPO=owner/name を渡す}"
APPLY=${APPLY:-false}
PROTECTED=" main screenshots "
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/stdout}

git fetch -q --prune origin '+refs/heads/*:refs/remotes/origin/*'

# PR の一覧: 枝の名前・先頭・状態・併合済みか（新しい方から最大1000件）
prs=$(mktemp)
for page in $(seq 1 10); do
  got=$(gh api "repos/$REPO/pulls?state=all&per_page=100&page=$page" \
        --jq '.[] | "\(.head.ref)\t\(.head.sha)\t\(.state)\t\(.merged_at != null)"')
  [ -z "$got" ] && break
  printf '%s\n' "$got" >> "$prs"
done

delete=() keep=()
while read -r branch sha; do
  [ "$branch" = "HEAD" ] && continue
  if [[ "$PROTECTED" == *" $branch "* ]]; then keep+=("$branch|守る枝"); continue; fi
  if awk -F'\t' -v b="$branch" '$1==b && $3=="open"{f=1} END{exit !f}' "$prs"; then
    keep+=("$branch|開いている PR"); continue
  fi
  if git merge-base --is-ancestor "$sha" origin/main; then
    delete+=("$branch|main の履歴に含まれる"); continue
  fi
  if awk -F'\t' -v b="$branch" -v s="$sha" '$1==b && $2==s && $4=="true"{f=1} END{exit !f}' "$prs"; then
    delete+=("$branch|PR が併合済みで、その後の追加なし"); continue
  fi
  keep+=("$branch|まだ main に入っていない")
done < <(git for-each-ref --format='%(refname:lstrip=3) %(objectname)' refs/remotes/origin)

{
  if [ "$APPLY" = "true" ]; then echo "## 枝の掃除（消した）"; else echo "## 枝の掃除（試すだけ・何も消していない）"; fi
  echo
  echo "消す: ${#delete[@]} 本 / 残す: ${#keep[@]} 本"
  echo
  echo "### 消す枝"
  echo "| 枝 | 理由 |"; echo "| --- | --- |"
  for row in "${delete[@]}"; do echo "| ${row%%|*} | ${row#*|} |"; done
  echo
  echo "### 残す枝"
  echo "| 枝 | 理由 |"; echo "| --- | --- |"
  for row in "${keep[@]}"; do echo "| ${row%%|*} | ${row#*|} |"; done
} >> "$SUMMARY"

[ "$APPLY" = "true" ] || exit 0

# 🔴 **消す直前に、GitHub に1本ずつ問い直す**（2026-10-07）。
# 初回の一括の掃除で、手元の試しでは「残す」だった枝（main に入っていない・PR なし）が
# 16本消えた。原因は突き止め切れていない（手元で同じ条件を流すと残す側になる）ので、
# 手元の判定だけを信じない。いまの先頭を読み直し、main との比べ（compare）が
# 「main に含まれる」か、その先頭のまま併合された PR があるときだけ消す
still_merged() {
  local branch=$1 now status
  now=$(gh api "repos/$REPO/git/ref/heads/$branch" --jq .object.sha 2>/dev/null) || return 1
  status=$(gh api "repos/$REPO/compare/main...$now" --jq .status 2>/dev/null) || return 1
  case "$status" in identical|behind) return 0 ;; esac
  awk -F'\t' -v b="$branch" -v s="$now" '$1==b && $2==s && $4=="true"{f=1} END{exit !f}' "$prs"
}

failed=0
skipped=0
for row in "${delete[@]}"; do
  branch=${row%%|*}
  if ! still_merged "$branch"; then
    echo "::warning::問い直したら main に入っていなかったので残す: $branch"
    skipped=$((skipped + 1))
    continue
  fi
  echo "消す: ${branch}（${row#*|}）"
  # 枝の名前の / はそのまま（API はパスの続きとして受ける）
  if ! gh api -X DELETE "repos/$REPO/git/refs/heads/$branch" --silent; then
    echo "::warning::消せなかった: $branch"
    failed=$((failed + 1))
  fi
done
echo "消せなかった枝: $failed 本 / 問い直して残した枝: $skipped 本" >> "$SUMMARY"
[ "$failed" -eq 0 ]
