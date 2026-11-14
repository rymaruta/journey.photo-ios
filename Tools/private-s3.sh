# shellcheck shell=bash
#
# CI から**非公開の S3**（画面写真と同じ置き場 `Tools/ci-shots/`）に1つのファイルを置く。読み込んで使う:
#
#     . Tools/private-s3.sh
#     rc=0; private_s3_check || rc=$?    # 0 = 置ける・2 = 置かない回（PR・別のリポジトリ）・1 = 置けない
#     private_s3_put <ファイル> <名前>     # s3://<バケット>/<run の印>/<名前> に置く。印は private_s3_run_key
#
# 置けない・置かない理由は `PRIVATE_S3_WHY` に入る（置き場の名前・鍵は入れない）。
# 使うのは `Tools/upload-shots.sh`（画面写真）と `Tools/testflight-crashes.sh`（TestFlight の落ちた記録・2026-11-14 #596）。
# 2026-11-14 判断: 画面写真の置き方を落ちた記録でも使うので、`upload-shots.sh` の中から取り出して1か所にした（写しを作らない）
#
# 🔴 **公開リポジトリなので、置くものはどこにも公開しない（#451）。**
#   - ログに置き場の名前・URL・中身を出さない（バケット名と役割は secrets なのでログでは伏せられる）
#   - 長く使える鍵は持たない。GitHub の OIDC で役割 `journey-photo-ios-ci-shots-writer` に入る。
#     役割ができるのは、このバケットに置くこと（`s3:PutObject`）だけ（`Tools/ci-shots/writer-policy.json`）
#   - PR の回（フォークを含む）では置かない。ここで止めるほか、役割の入れる条件も枝の回（`ref:refs/heads/*`）だけ
#   - 置き場は3日で自動で消える（`Tools/ci-shots/lifecycle.json`）。取り出しは `Tools/fetch-shots.sh <run の印>`
#
# run の印は TestFlight の回なら run 番号そのまま（例 1160）、ほかのワークフローの回は
# `<ワークフロー名の英小文字>-<run 番号>`（例 release-center-12・testflight-crashes-3）。番号の数え方がワークフローごとに別なので重ねない

PRIVATE_S3_WHY=""

private_s3_check() {
    case "${GITHUB_EVENT_NAME:-}" in
        pull_request|pull_request_target) PRIVATE_S3_WHY="PR の回"; return 2 ;;
    esac
    if [ "${GITHUB_REPOSITORY:-}" != "rymaruta/journey.photo-ios" ]; then
        PRIVATE_S3_WHY="このリポジトリの回ではない"; return 2
    fi
    if [ -z "${CI_SHOTS_ROLE_ARN:-}" ] || [ -z "${CI_SHOTS_BUCKET:-}" ]; then
        PRIVATE_S3_WHY="secrets の CI_SHOTS_ROLE_ARN・CI_SHOTS_BUCKET が未設定"; return 1
    fi
    if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
        PRIVATE_S3_WHY="この job に id-token: write がありません"; return 1
    fi
    if ! command -v aws > /dev/null 2>&1; then
        PRIVATE_S3_WHY="aws の CLI がありません"; return 1
    fi
    return 0
}

private_s3_run_key() {
    if [ "${GITHUB_WORKFLOW:-}" = "TestFlight" ]; then
        printf '%s\n' "${GITHUB_RUN_NUMBER:?}"
    else
        local slug
        slug="$(printf '%s' "${GITHUB_WORKFLOW:-other}" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')"
        printf '%s\n' "${slug:-other}-${GITHUB_RUN_NUMBER:?}"
    fi
}

# private_s3_put <ファイル> <名前>: 置けたら 0。置けなければ PRIVATE_S3_WHY に理由を入れて 1
private_s3_put() {
    local file="$1" name="$2" key work rc=0
    if [[ ! "$name" =~ ^[a-z0-9-]{1,40}\.tar$ ]]; then
        PRIVATE_S3_WHY="置く名前が変です"; return 1
    fi
    [ -s "$file" ] || { PRIVATE_S3_WHY="置くファイルがありません"; return 1; }
    key="$(private_s3_run_key)"
    work="$(mktemp -d)"
    chmod 700 "$work"
    # ---- OIDC の札を取り、役割に入って置く ----------------------------------------
    # 札はファイルに置き、aws の CLI に `AWS_WEB_IDENTITY_TOKEN_FILE` で渡す（コマンドの引数・ログに出さない）
    if ! curl -sSf -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
            "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" 2> /dev/null \
            | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["value"])' > "$work/token" 2> /dev/null \
       || [ ! -s "$work/token" ]; then
        rm -rf "$work"
        PRIVATE_S3_WHY="OIDC の札を取れませんでした"; return 1
    fi
    (
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
        export AWS_ROLE_ARN="$CI_SHOTS_ROLE_ARN"
        export AWS_WEB_IDENTITY_TOKEN_FILE="$work/token"
        export AWS_ROLE_SESSION_NAME="gh-${GITHUB_RUN_ID:-0}-${name%.tar}"
        export AWS_REGION=ap-northeast-1 AWS_DEFAULT_REGION=ap-northeast-1
        # 失敗の文には置き場の名前と鍵が入るので、ログには出さない（エラーの種類だけを拾う）
        aws s3 cp "$file" "s3://${CI_SHOTS_BUCKET}/${key}/${name}" \
            --only-show-errors --no-progress > /dev/null 2> "$work/err"
    ) || rc=$?
    if [ "$rc" -ne 0 ]; then
        PRIVATE_S3_WHY="S3 に置けませんでした（$(grep -o 'An error occurred ([A-Za-z]*)' "$work/err" | head -1 || true)）"
        rm -rf "$work"
        return 1
    fi
    rm -rf "$work"
    return 0
}
