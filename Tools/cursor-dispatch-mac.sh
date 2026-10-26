#!/bin/bash
# Cursor Cloud Agent から Mac の CI / TestFlight を起こす（2026-10-24）。
#
# Cursor の連携トークンは `workflow_dispatch` が 403、`repository_dispatch` は通る。
# Skills の `/release`・`/mac-check` はここを使う（GitHub の「Run workflow」画面は開かない）。
#
# 使い方:
#   bash Tools/cursor-dispatch-mac.sh testflight [ref]
#       → event_type=ios-testflight（TestFlight に上げる）。既定 ref=main
#   bash Tools/cursor-dispatch-mac.sh check <ref> [screens]
#       → event_type=ios-mac-check（上げない）。screens は , 区切り（空＝全部・none＝見張りだけ）
#   bash Tools/cursor-dispatch-mac.sh check <ref> --screens '撮影スポット' --tests
#
# 出力（1行）: <run id> <event_type> <ref> <sha7>
# 続けて待つときは: bash Tools/wait-mac-run.sh --run-id <run id>
#                  または従来どおり bash Tools/wait-mac-run.sh <sha7>
#                  （repository_dispatch の head_sha は既定ブランチ側なので、枝の確認は --run-id 推奨）
set -euo pipefail

repo=${REPO:-rymaruta/journey.photo-ios}
dry_run=false
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=true
  shift
fi
mode=${1:?mode（testflight|check）を渡す}
shift || true

bool_json() {
  case "${1:-}" in true|True|TRUE|1|yes|YES) echo true ;; *) echo false ;; esac
}

case "$mode" in
  testflight|release|ship)
    event=ios-testflight
    ref=${1:-main}
    screens=""
    tests=false
    store=false
    beta=false
    ;;
  check|mac-check|mac)
    event=ios-mac-check
    ref=${1:?check には枝（ref）が要る}
    shift || true
    screens=""
    tests=false
    store=false
    beta=false
    while [ $# -gt 0 ]; do
      case "$1" in
        --tests) tests=true; shift ;;
        --store-shots) store=true; shift ;;
        --beta-review) beta=true; shift ;;
        --screens) screens=${2:?}; shift 2 ;;
        -*)
          echo "未知の旗: $1" >&2
          exit 2
          ;;
        *)
          screens=$1
          shift
          ;;
      esac
    done
    ;;
  *)
    echo "mode は testflight か check: $mode" >&2
    exit 2
    ;;
esac

# 起動前の最新 run id（これより新しい repository_dispatch を拾う）
before_id=$(gh api "repos/$repo/actions/workflows/ios-testflight.yml/runs?per_page=1" \
  --jq '.workflow_runs[0].id // 0')

# 枝の tip の sha（報告・待ち用）。repository_dispatch の head_sha は既定ブランチなので使わない
sha7=$(git ls-remote "https://github.com/$repo.git" "refs/heads/$ref" 2>/dev/null | awk '{print substr($1,1,7)}')
if [ -z "${sha7:-}" ]; then
  # タグや短 sha も許す
  sha7=$(git ls-remote "https://github.com/$repo.git" "$ref" 2>/dev/null | awk '{print substr($1,1,7)}' | head -1)
fi
if [ -z "${sha7:-}" ]; then
  echo "ref がリモートに無い: $ref" >&2
  exit 1
fi

body=$(EVENT="$event" REF="$ref" SCREENS="$screens" \
  TESTS="$(bool_json "$tests")" STORE="$(bool_json "$store")" BETA="$(bool_json "$beta")" \
  python3 - <<'PY'
import json, os
print(json.dumps({
    "event_type": os.environ["EVENT"],
    "client_payload": {
        "ref": os.environ["REF"],
        "screens": os.environ.get("SCREENS", ""),
        "tests": os.environ["TESTS"] == "true",
        "storeShots": os.environ["STORE"] == "true",
        "betaReview": os.environ["BETA"] == "true",
    },
}))
PY
)

if $dry_run; then
  echo "dry-run $event $ref $sha7 before_id=$before_id"
  echo "$body"
  exit 0
fi

echo "$body" | gh api -X POST "repos/$repo/dispatches" --input - >/dev/null

# 新しい回が出るまで待つ（repository_dispatch は数秒〜十数秒かかることがある）
run_id=""
for _ in $(seq 1 40); do
  sleep 3
  run_id=$(gh api "repos/$repo/actions/workflows/ios-testflight.yml/runs?event=repository_dispatch&per_page=10" \
    --jq --argjson before "$before_id" --arg ev "$event" '
      [.workflow_runs[]
        | select(.id > $before)
        | select(.display_title == $ev)
      ][0].id // empty
    ' 2>/dev/null || true)
  if [ -n "${run_id:-}" ]; then
    break
  fi
done

if [ -z "${run_id:-}" ]; then
  echo "timeout: repository_dispatch（${event}）の回が見つからない（before_id=${before_id}）" >&2
  exit 1
fi

echo "$run_id $event $ref $sha7"
