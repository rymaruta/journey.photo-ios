#!/usr/bin/env bash
#
# Mac の CI が撮った画面写真の置き場（非公開の S3）と、CI が書き込む役割（IAM ロール）を作る。
# 2026-11-12 owner「S3 において、それを DL してみるとかならいいけど、もちろんちゃんと消す前提で」。
#
# **既定は下見だけ**（作るものの全文を出して終わる）。`--apply` のときだけ作る。
# 何度流しても、在るものは作り直さず、設定（公開止め・暗号化・自動で消す・TLS だけ・許可）を入れ直す。
# 費用・資源を増やすので、`--apply` は owner の了承のあとだけ（CLAUDE.md）。
#
#     bash Tools/ci-shots/setup.sh            # 下見（何も作らない）
#     bash Tools/ci-shots/setup.sh --apply    # 作る（管理者の資格情報で）
#
# 作るもの:
#   - バケット `journey-photo-ios-ci-shots`（東京）: 公開のアクセスを4つとも止める・ACL を使わない・
#     既定の暗号化（SSE-S3）・3日で消す（`lifecycle.json`）・TLS でない読み書きを断る（`bucket-policy.json`）。
#     版の管理（versioning）は入れない（消したら本当に消えるように）
#   - ロール `journey-photo-ios-ci-shots-writer`: GitHub Actions の OIDC で、このリポジトリの**枝の回**
#     （`ref:refs/heads/*`）だけが入れる（`trust-policy.json`。PR の回の sub は `pull_request` なので入れない）。
#     できるのは、このバケットに置くこと（`s3:PutObject`）だけ（`writer-policy.json`）。読む・一覧・消すはできない
#
# GitHub の OIDC の入口（`token.actions.githubusercontent.com`）は、このアカウントに既にあるものを使う
# （2026-10-01 に作られたもの）。無ければ作らずに止まる（入口を作るのは別の判断）
set -euo pipefail

APPLY=false
[ "${1:-}" = "--apply" ] && APPLY=true

HERE="$(cd "$(dirname "$0")" && pwd)"
REGION=ap-northeast-1
BUCKET="${CI_SHOTS_BUCKET:-journey-photo-ios-ci-shots}"
ROLE=journey-photo-ios-ci-shots-writer
TAGS_S3='TagSet=[{Key=Project,Value=journey-photo-ios},{Key=Purpose,Value=ci-screenshots}]'

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
PROVIDER="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

render() {
    sed -e "s/\${ACCOUNT_ID}/${ACCOUNT_ID}/g" -e "s/\${BUCKET}/${BUCKET}/g" "$HERE/$1"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
for f in trust-policy.json writer-policy.json bucket-policy.json lifecycle.json; do
    render "$f" > "$WORK/$f"
    python3 -I -m json.tool "$WORK/$f" > /dev/null
done

echo "== 置き場: s3://${BUCKET}（${REGION}）"
echo "== 役割:   $ROLE"
echo "== OIDC の入口: $PROVIDER"
for f in trust-policy.json writer-policy.json bucket-policy.json lifecycle.json; do
    echo "---- $f"
    cat "$WORK/$f"
done

if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER" > /dev/null 2>&1; then
    echo "NG: GitHub の OIDC の入口がこのアカウントにありません。作らずに止めます" >&2
    exit 1
fi

if ! $APPLY; then
    echo
    echo "下見だけです（何も作っていません）。作るときは --apply"
    exit 0
fi

# ---- バケット ----------------------------------------------------------------
if aws s3api head-bucket --bucket "$BUCKET" > /dev/null 2>&1; then
    echo "バケットは在ります（作り直さない）: $BUCKET"
else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
        --create-bucket-configuration "LocationConstraint=$REGION" > /dev/null
    echo "バケットを作りました: $BUCKET"
fi
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-ownership-controls --bucket "$BUCKET" \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
    --lifecycle-configuration "file://$WORK/lifecycle.json"
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "file://$WORK/bucket-policy.json"
aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging "$TAGS_S3"

# ---- 役割 --------------------------------------------------------------------
if aws iam get-role --role-name "$ROLE" > /dev/null 2>&1; then
    aws iam update-assume-role-policy --role-name "$ROLE" --policy-document "file://$WORK/trust-policy.json"
    echo "役割は在ります（入れる条件を入れ直した）: $ROLE"
else
    aws iam create-role --role-name "$ROLE" \
        --assume-role-policy-document "file://$WORK/trust-policy.json" \
        --max-session-duration 3600 \
        --description "journey.photo-ios: Mac CI puts XCTest screenshots to s3://$BUCKET (PutObject only)" \
        --tags Key=Project,Value=journey-photo-ios Key=Purpose,Value=ci-screenshots > /dev/null
    echo "役割を作りました: $ROLE"
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name put-ci-shots \
    --policy-document "file://$WORK/writer-policy.json"

# ---- 確かめる（入れた設定を読み戻す）-------------------------------------------
echo "== 読み戻し"
aws s3api get-public-access-block --bucket "$BUCKET" --output json
aws s3api get-bucket-encryption --bucket "$BUCKET" --output json
aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" --output json
aws s3api get-bucket-versioning --bucket "$BUCKET" --output json
aws iam get-role-policy --role-name "$ROLE" --policy-name put-ci-shots --output json
echo
echo "GitHub の Actions の secrets に2つ入れる（値はログで伏せられる）:"
echo "  CI_SHOTS_BUCKET   = $BUCKET"
echo "  CI_SHOTS_ROLE_ARN = arn:aws:iam::${ACCOUNT_ID}:role/$ROLE"
