#!/bin/bash
# 使い終わった枝を選び、APPLY=true のときだけ消す（`.github/workflows/cleanup-branches.yml` から呼ぶ）。
#
# 消すのは「中身が main に入り終えた枝」:
#  1. 枝の先頭が origin/main の履歴に含まれる
#  2. その枝の PR が併合済みで、枝の先頭がそのときの先頭のまま（squash 併合）
#  3. 枝のコミットがすべて、同じ変更として main に入っている（cherry-pick で取り込み済み・`git cherry`）
# 加えて、頼まれたときだけ「まだ main に入っていない枝」も消す（2026-10-22 owner「いらないブランチ全部消す」）:
#  4. STALE_DAYS=N … 先頭のコミットが N 日より古い枝（止まったままの作業）
#  5. ALSO="枝 枝 …" … 名前を挙げた枝
#  4・5 は消す前に `archive/<枝>/<先頭7桁>` のタグを打つ。中身は残るので、いつでも戻せる:
#    git push origin archive/<枝>/<7桁>:refs/heads/<枝>
# 残すのは守る枝・開いている PR の枝・上のどれにも当たらない枝。
#
# 要るもの: 全履歴の checkout（fetch-depth: 0）・gh（GH_TOKEN）・REPO=owner/name。
# 手元でも試せる: `REPO=rymaruta/journey.photo-ios APPLY=false STALE_DAYS=7 bash Tools/cleanup-branches.sh`
set -euo pipefail

: "${REPO:?REPO=owner/name を渡す}"
APPLY=${APPLY:-false}
STALE_DAYS=${STALE_DAYS:-}
ALSO=" ${ALSO:-} "
# screenshots・store-screenshots は CI が絵を置く枝。develop は念のため。
# claude/apple-signin は owner が止めている作業（2026-10-22「一旦なし」）で、捨てたわけではない
PROTECTED=" main develop screenshots store-screenshots claude/apple-signin "
if [ -n "$STALE_DAYS" ] && ! [[ "$STALE_DAYS" =~ ^[0-9]+$ ]]; then
  echo "STALE_DAYS は日数（整数）で渡す: $STALE_DAYS" >&2; exit 1
fi
cutoff=$(( $(date +%s) - ${STALE_DAYS:-0} * 86400 ))
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

# 枝のコミットが、すべて同じ変更として main に入っているか。
# **`git cherry | grep -q` と繋がない。** grep が先に抜けると cherry が SIGPIPE で落ち、
# pipefail の下では「1件も無い」と取り違えて、main に無い枝を消してしまう
all_in_main() {
  local out
  out=$(git cherry origin/main "$1") || return 1
  ! grep -q '^+' <<< "$out"
}

delete=() archive=() keep=()
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
  if all_in_main "$sha"; then
    delete+=("$branch|変更がすべて main に取り込み済み"); continue
  fi
  if [[ "$ALSO" == *" $branch "* ]]; then
    archive+=("$branch|$sha|名前を挙げた枝"); continue
  fi
  if [ -n "$STALE_DAYS" ] && [ "$(git log -1 --format=%ct "$sha")" -lt "$cutoff" ]; then
    archive+=("$branch|$sha|${STALE_DAYS} 日より前から止まっている（$(git log -1 --format=%cs "$sha")）"); continue
  fi
  keep+=("$branch|まだ main に入っていない")
done < <(git for-each-ref --format='%(refname:lstrip=3) %(objectname)' refs/remotes/origin)

{
  if [ "$APPLY" = "true" ]; then echo "## 枝の掃除（消した）"; else echo "## 枝の掃除（試すだけ・何も消していない）"; fi
  echo
  echo "消す: ${#delete[@]} 本 / 控えのタグを打って消す: ${#archive[@]} 本 / 残す: ${#keep[@]} 本"
  echo
  echo "### 消す枝"
  echo "| 枝 | 理由 |"; echo "| --- | --- |"
  for row in "${delete[@]}"; do echo "| ${row%%|*} | ${row#*|} |"; done
  echo
  echo "### 控えのタグ（archive/<枝>/<7桁>）を打ってから消す枝（main に入っていない）"
  echo "| 枝 | 先頭 | 理由 |"; echo "| --- | --- | --- |"
  for row in "${archive[@]}"; do
    IFS='|' read -r b sha why <<< "$row"; echo "| $b | ${sha:0:7} | $why |"
  done
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
  # cherry-pick で取り込み済みの枝は compare では見分けられないので、読み直した先頭で数え直す
  git fetch -q origin "$now" 2>/dev/null && all_in_main "$now" && return 0
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
# main に入っていない枝は、選んだときの先頭のままで、開いた PR が無いときだけ、
# 控えのタグを打ってから消す（タグが打てなければ消さない）
for row in "${archive[@]}"; do
  IFS='|' read -r branch sha why <<< "$row"
  now=$(gh api "repos/$REPO/git/ref/heads/$branch" --jq .object.sha 2>/dev/null || true)
  if [ "$now" != "$sha" ]; then
    echo "::warning::選んだあとに動いたので残す: $branch"; skipped=$((skipped + 1)); continue
  fi
  if [ -n "$(gh api "repos/$REPO/pulls?state=open&head=${REPO%%/*}:$branch" --jq '.[].number')" ]; then
    echo "::warning::開いている PR があるので残す: $branch"; skipped=$((skipped + 1)); continue
  fi
  tag="archive/$branch/${sha:0:7}"
  have=$(gh api "repos/$REPO/git/ref/tags/$tag" --jq .object.sha 2>/dev/null || true)
  if [ "$have" != "$sha" ] && ! gh api -X POST "repos/$REPO/git/refs" -f "ref=refs/tags/$tag" -f "sha=$sha" --silent; then
    echo "::warning::控えのタグが打てなかったので残す: $branch"; failed=$((failed + 1)); continue
  fi
  echo "控え $tag を打って消す: ${branch}（${why}）"
  if ! gh api -X DELETE "repos/$REPO/git/refs/heads/$branch" --silent; then
    echo "::warning::消せなかった: $branch"; failed=$((failed + 1))
  fi
done
echo "消せなかった枝: $failed 本 / 問い直して残した枝: $skipped 本" >> "$SUMMARY"
[ "$failed" -eq 0 ]
