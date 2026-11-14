#!/usr/bin/env bash
#
# TestFlight のテスターが送った落ちた記録を App Store Connect API から取り、**非公開の S3** に置く（2026-11-14・札 #596）。
# 回すのは `.github/workflows/testflight-crashes.yml`（手で起動）。取り出しは画面写真と同じ `Tools/fetch-shots.sh <run の印>`。
# 読み方（シンボル化・dSYM）は `docs/TESTFLIGHT.md` の「落ちた記録を読む」。
#
#     bash Tools/testflight-crashes.sh <版> [件数の上限]      # 例 1.1.85 50
#
# 🔴 **公開リポジトリなので、記録の本文はログ・成果物に出さない（#451 と同じ）。**
#   記録には端末の識別子・端末の型・テスターの書いた言葉が入りうる。本文は S3（3日で消える）にだけ置き、
#   ログには件数と各件の要点（版・ビルド・日時・例外の型・落ちたスレッドの上の数段の関数名）だけを出す
#   （`Tools/testflight-crashes.py`）。置けない回は**取りに行かない**（取ったものを置く先が無いまま持たない）
#
# 置く場所: s3://<バケット>/<run の印>/crashes.tar（印は testflight-crashes-<run 番号>。決め方は `Tools/private-s3.sh`）
set -euo pipefail

VERSION="${1:?版を渡してください（例 1.1.85）}"
LIMIT="${2:-50}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "::error::版の形が変です（例 1.1.85）"; exit 1; }
[[ "$LIMIT" =~ ^[0-9]{1,3}$ ]] || { echo "::error::件数の上限は数字で（例 50）"; exit 1; }

. "$(dirname "$0")/private-s3.sh"
rc=0
private_s3_check || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "::error::落ちた記録を置く非公開の置き場が使えないので、取りに行きません: $PRIVATE_S3_WHY"
    exit 1
fi
RUN_KEY="$(private_s3_run_key)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"
mkdir -m 700 "$WORK/crashes"

rc=0
python3 -I Tools/testflight-crashes.py --version "$VERSION" --limit "$LIMIT" --out "$WORK/crashes" || rc=$?
if [ "$rc" -eq 3 ]; then
    echo "::error::版 ${VERSION} のビルドが App Store Connect に見つかりません"
    exit 1
fi
[ "$rc" -eq 0 ] || { echo "::error::落ちた記録を取れませんでした（上の NG の行）"; exit 1; }

count="$(cat "$WORK/crashes/count" 2> /dev/null || echo 0)"
if [ "$count" = "0" ]; then
    echo "版 ${VERSION} の落ちた記録は 0 件です（テスターが落ちたあとの知らせで「共有」を押した分だけが届く）"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            echo "### 版 ${VERSION} の落ちた記録は 0 件"
            echo "テスターが落ちたあとの知らせで「共有」を押した分だけが App Store Connect に届きます（\`docs/TESTFLIGHT.md\` の「落ちた記録を読む」）"
        } >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 0
fi

tar -cf "$WORK/crashes.tar" -C "$WORK/crashes" .
if ! private_s3_put "$WORK/crashes.tar" "crashes.tar"; then
    echo "::error::落ちた記録を非公開の置き場に置けませんでした: $PRIVATE_S3_WHY"
    exit 1
fi

echo "落ちた記録 $count 件を非公開の置き場に置きました（run の印: ${RUN_KEY}・3日で消える）"
echo "取り出し: bash Tools/fetch-shots.sh ${RUN_KEY}（見終わったら --delete）"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### 版 ${VERSION} の落ちた記録 $count 件を非公開の置き場に置きました"
        echo "要点（例外の型・落ちたスレッドの上の数段）はこの段のログ。本文は置き場だけにあります"
        echo "取り出し: \`bash Tools/fetch-shots.sh ${RUN_KEY}\`（3日で自動で消える。見終わったら \`--delete\`）"
    } >> "$GITHUB_STEP_SUMMARY"
fi
