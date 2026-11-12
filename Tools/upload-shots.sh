#!/usr/bin/env bash
#
# Mac の CI が撮った画面写真を、**非公開の S3** に置く（2026-11-12 owner）。
# 取り出すのは `Tools/fetch-shots.sh <run>`、置き場は3日で自動で消える（`Tools/ci-shots/lifecycle.json`）。
#
# 🔴 **公開リポジトリなので、写真はどこにも公開しない（#451）。**
#   - 枝・成果物（artifact）には置かない。ログに置き場の名前・URL・写真の中身を出さない
#     （出すのは枚数と、取り出すときの run の印だけ。バケット名と役割は secrets なのでログでは伏せられる）
#   - 長く使える鍵は持たない。GitHub の OIDC で役割 `journey-photo-ios-ci-shots-writer` に入る。
#     役割ができるのは、このバケットに置くこと（`s3:PutObject`）だけ（`Tools/ci-shots/writer-policy.json`）
#   - PR の回（フォークを含む）では動かない。ここで止めるほか、役割の入れる条件も枝の回（`ref:refs/heads/*`）だけ
#
# **落とさない**（`Tools/export-screenshots.sh` と同じ約束）。置けなくても警告を出して 0 で終わる。
#
#     bash Tools/upload-shots.sh <組> <xcresult>…
#       組: build（1台で流した回）・first・1〜3（分けて流した回の組）
#
# 置く場所: s3://<バケット>/<run の印>/<組>.tar
#   run の印は TestFlight の回なら run 番号そのまま（例 1160）、ほかのワークフローから呼ばれた回は
#   `<ワークフロー名の英小文字>-<run 番号>`（例 release-center-12）。番号の数え方がワークフローごとに別なので重ねない
set -uo pipefail

PART="${1:-}"
[ "$#" -gt 0 ] && shift

skip() { echo "画面写真は置きません: $*"; exit 0; }
warn() { echo "::warning::画面写真を置けませんでした: $*"; exit 0; }

case "${GITHUB_EVENT_NAME:-}" in
    pull_request|pull_request_target) skip "PR の回" ;;
esac
[ "${GITHUB_REPOSITORY:-}" = "rymaruta/journey.photo-ios" ] || skip "このリポジトリの回ではない"
[[ "$PART" =~ ^[a-z0-9-]{1,20}$ ]] || warn "組の名前が変です"
[ "$#" -gt 0 ] || warn "xcresult が渡されていません"
if [ -z "${CI_SHOTS_ROLE_ARN:-}" ] || [ -z "${CI_SHOTS_BUCKET:-}" ]; then
    warn "secrets の CI_SHOTS_ROLE_ARN・CI_SHOTS_BUCKET が未設定"
fi
if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
    warn "この job に id-token: write がありません"
fi
command -v aws > /dev/null 2>&1 || warn "aws の CLI がありません"

# ---- 取り出して縮める（枝には押さない形）--------------------------------------
SHOTS_EXPORT_ONLY=1 SHOTS_PART="$PART" bash Tools/export-screenshots.sh "$@"
OUT=/tmp/shots-out
count=$(find "$OUT" -maxdepth 1 -type f -name '*.jpg' 2>/dev/null | wc -l | tr -d ' ')
[ "${count:-0}" -gt 0 ] || skip "絵が1枚もありません"

if [ "${GITHUB_WORKFLOW:-}" = "TestFlight" ]; then
    RUN_KEY="${GITHUB_RUN_NUMBER:?}"
else
    slug="$(printf '%s' "${GITHUB_WORKFLOW:-other}" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')"
    RUN_KEY="${slug:-other}-${GITHUB_RUN_NUMBER:?}"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"
tar -cf "$WORK/$PART.tar" -C "$OUT" . || warn "まとめられませんでした"

# ---- OIDC の札を取り、役割に入って置く ----------------------------------------
# 札はファイルに置き、aws の CLI に `AWS_WEB_IDENTITY_TOKEN_FILE` で渡す（コマンドの引数・ログに出さない）
if ! curl -sSf -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
        "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" 2> /dev/null \
        | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["value"])' > "$WORK/token" 2> /dev/null \
   || [ ! -s "$WORK/token" ]; then
    warn "OIDC の札を取れませんでした"
fi

(
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
    export AWS_ROLE_ARN="$CI_SHOTS_ROLE_ARN"
    export AWS_WEB_IDENTITY_TOKEN_FILE="$WORK/token"
    export AWS_ROLE_SESSION_NAME="gh-${GITHUB_RUN_ID:-0}-${PART}"
    export AWS_REGION=ap-northeast-1 AWS_DEFAULT_REGION=ap-northeast-1
    # 失敗の文には置き場の名前と鍵が入るので、ログには出さない（エラーの種類だけを拾う）
    aws s3 cp "$WORK/$PART.tar" "s3://${CI_SHOTS_BUCKET}/${RUN_KEY}/${PART}.tar" \
        --only-show-errors --no-progress > /dev/null 2> "$WORK/err"
) || warn "S3 に置けませんでした（$(grep -o 'An error occurred ([A-Za-z]*)' "$WORK/err" | head -1 || true)）"

echo "画面の絵 $count 枚を非公開の置き場に置きました（run の印: ${RUN_KEY}・組: ${PART}・3日で消える）"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### 画面の絵 $count 枚を非公開の置き場に置きました（組: ${PART}）"
        echo "取り出し: \`bash Tools/fetch-shots.sh $RUN_KEY\`（3日で自動で消える。見終わったら \`--delete\`）"
        cat /tmp/shots-report.md 2> /dev/null || true
    } >> "$GITHUB_STEP_SUMMARY"
fi
exit 0
