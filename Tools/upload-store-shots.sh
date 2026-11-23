#!/usr/bin/env bash
#
# App Store 用の絵（大型 1320×2868 と中型 1206×2622。シミュレータの画面そのまま・合成なし）を、**非公開の S3** に置く（札 #604）。
# `ios-testflight.yml` の `storeShots: true` の回に、UI テストのあとで呼ぶ。
#
#     bash Tools/upload-store-shots.sh build/ios/test/Test.xcresult build/ios/test/StoreMedium.xcresult
#
# 2026-11-22 判断: 前は原寸を公開の枝 `store-screenshots` に押していて、#451 で止めていた。
# 置き場・入り方・消え方は画面写真（`Tools/upload-shots.sh`）と同じものを使い回す（`Tools/private-s3.sh`）。
#   - 置く場所: s3://<バケット>/<run の印>/store.tar（同じ run の画面写真の組 `build.tar` の隣）。3日で自動で消える
#   - 取り出し: `bash Tools/fetch-shots.sh <run の印>` → <落とす先>/<run>/store/ に原寸の PNG と README.md
#   - 🔴 公開の枝・成果物（artifact）・ログには絵を出さない。作業の場所は /tmp の外に出さない一時フォルダ（`build/` の下に作らない。
#     `build-logs` の成果物に混ざらないように）。ログに出すのは枚数と run の印だけ
#
# **画面写真と違い、作れなかったら赤にする。** この回の目的が絵なので、足りない絵を黙って緑にしない
# （置けない・材料が足りないの理由はログに出す。置き場の名前・鍵は `private-s3.sh` が伏せる）
set -uo pipefail

XCRESULT="${1:-build/ios/test/Test.xcresult}"
# 中型の枠（1206×2622）の機種で撮った結果（2026-11-23・合成をやめ、2つの機種の画面をそのまま出す）
MEDIUM_XCRESULT="${2:-build/ios/test/StoreMedium.xcresult}"
fail() { echo "::error::App Store 用の絵を置けませんでした: $*"; exit 1; }

. "$(dirname "$0")/private-s3.sh"
rc=0
private_s3_check || rc=$?
if [ "$rc" -eq 2 ]; then
    echo "App Store 用の絵は置きません: $PRIVATE_S3_WHY"
    exit 0
fi
[ "$rc" -eq 0 ] || fail "$PRIVATE_S3_WHY"
[ -d "$XCRESULT" ] || fail "テストの結果（xcresult）がありません"
[ -d "$MEDIUM_XCRESULT" ] || fail "中型の機種のテストの結果（xcresult）がありません"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

xcrun xcresulttool export attachments --path "$XCRESULT" --output-path "$WORK/raw" > /dev/null \
    || fail "添付を取り出せませんでした（xcresulttool の版違い？）"
xcrun xcresulttool export attachments --path "$MEDIUM_XCRESULT" --output-path "$WORK/raw-medium" > /dev/null \
    || fail "中型の機種の添付を取り出せませんでした"
# README に書く機種と iOS の版
export STORE_DEVICE_LARGE="${STORE_DEVICE_LARGE:-?}" STORE_DEVICE_MEDIUM="${STORE_DEVICE_MEDIUM:-?}"
STORE_IOS="$(python3 Tools/store-screenshots.py --ios "$STORE_DEVICE_LARGE" 2> /dev/null || echo "?")"
export STORE_IOS

# Pillow は Mac の素の python3 に無い。この回だけの一時の venv に入れる（ランナーの python を汚さない）
python3 -m venv "$WORK/venv" > /dev/null && "$WORK/venv/bin/pip" install --quiet --disable-pip-version-check pillow \
    || fail "Pillow を入れられませんでした"

status=0
# pipefail なので python の失敗（材料が足りない＝1）が status に入る。ログには一時フォルダの道を出さない
"$WORK/venv/bin/python" Tools/store-screenshots.py "$WORK/raw" "$WORK/raw-medium" "$WORK/out" | sed "s#$WORK/out/##" || status=$?
# 6.9インチ（直下）と中型（`medium-1206x2622/`）の2組を合わせて数える（2026-11-23・札 #604）
count=$(find "$WORK/out" -type f -name '*.png' 2> /dev/null | wc -l | tr -d ' ')
[ "${count:-0}" -gt 0 ] || fail "絵が1枚も作れませんでした"

tar -cf "$WORK/store.tar" -C "$WORK/out" . || fail "まとめられませんでした"
private_s3_put "$WORK/store.tar" "store.tar" || fail "$PRIVATE_S3_WHY"

RUN_KEY="$(private_s3_run_key)"
echo "App Store 用の絵 $count 枚を非公開の置き場に置きました（run の印: ${RUN_KEY}・組: store・3日で消える）"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### App Store 用の絵 $count 枚を非公開の置き場に置きました（組: store・6.9インチ 1320×2868 と中型 1206×2622）"
        echo "取り出し: \`bash Tools/fetch-shots.sh $RUN_KEY\`（<落とす先>/$RUN_KEY/store/。3日で自動で消える。App Store Connect に上げ終わったら \`--delete\`）"
    } >> "$GITHUB_STEP_SUMMARY"
fi
# 材料が足りなかった絵は store-screenshots.py が名指しにしている。置けた分は置いたうえで赤にする
[ "$status" -eq 0 ] || fail "作れなかった絵があります（上の「作れなかった」）"
exit 0
