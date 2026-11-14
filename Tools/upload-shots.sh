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
# 置く場所: s3://<バケット>/<run の印>/<組>.tar（run の印の決め方と置き方は `Tools/private-s3.sh`）
set -uo pipefail

PART="${1:-}"
[ "$#" -gt 0 ] && shift

skip() { echo "画面写真は置きません: $*"; exit 0; }
warn() { echo "::warning::画面写真を置けませんでした: $*"; exit 0; }

# 置けるか・置かない回か（PR の回・別のリポジトリ）を先に見る。置き方は `Tools/private-s3.sh`（落ちた記録と共用）
. "$(dirname "$0")/private-s3.sh"
rc=0
private_s3_check || rc=$?
[ "$rc" -eq 2 ] && skip "$PRIVATE_S3_WHY"
[ "$rc" -eq 0 ] || warn "$PRIVATE_S3_WHY"
[[ "$PART" =~ ^[a-z0-9-]{1,20}$ ]] || warn "組の名前が変です"
[ "$#" -gt 0 ] || warn "xcresult が渡されていません"

# ---- 取り出して縮める（枝には押さない形）--------------------------------------
SHOTS_EXPORT_ONLY=1 SHOTS_PART="$PART" bash Tools/export-screenshots.sh "$@"
OUT=/tmp/shots-out
count=$(find "$OUT" -maxdepth 1 -type f -name '*.jpg' 2>/dev/null | wc -l | tr -d ' ')
[ "${count:-0}" -gt 0 ] || skip "絵が1枚もありません"

RUN_KEY="$(private_s3_run_key)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"
tar -cf "$WORK/$PART.tar" -C "$OUT" . || warn "まとめられませんでした"

# OIDC で役割に入って置く（札・置き場の名前・鍵はログに出さない。`Tools/private-s3.sh`）
private_s3_put "$WORK/$PART.tar" "$PART.tar" || warn "$PRIVATE_S3_WHY"

echo "画面の絵 $count 枚を非公開の置き場に置きました（run の印: ${RUN_KEY}・組: ${PART}・3日で消える）"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### 画面の絵 $count 枚を非公開の置き場に置きました（組: ${PART}）"
        echo "取り出し: \`bash Tools/fetch-shots.sh $RUN_KEY\`（3日で自動で消える。見終わったら \`--delete\`）"
        cat /tmp/shots-report.md 2> /dev/null || true
    } >> "$GITHUB_STEP_SUMMARY"
fi
exit 0
