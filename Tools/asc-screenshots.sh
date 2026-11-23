#!/usr/bin/env bash
#
# 非公開の S3 にある App Store 用の画面写真（`<run>/store.tar`）を取り、App Store Connect の「提出の準備中」の版に
# 入れ替える（2026-11-23・札 #604）。回すのは `.github/workflows/appstore-screenshots.yml`（手で起動）。
#
#     bash Tools/asc-screenshots.sh <store.tar のある run の印> <版> [apply]     # 例 1736 1.1.119（下見）
#
# **既定は下見（dry-run）。** 3つ目が `apply` のときだけ App Store Connect を変える。中身は `Tools/asc-screenshots.py`。
#
# 🔴 公開リポジトリなので、絵はログ・成果物に出さない（#451）。ほどくのは一時フォルダ（`build/` の下に作らない）、
#   終わったら消す。ログに出すのはファイル名・枚数・状態だけ。置き場の名前・鍵は `private-s3.sh` が伏せる
set -euo pipefail

RUN_KEY="${1:?store.tar のある run の印を渡してください（例 1736）}"
VERSION="${2:?版を渡してください（例 1.1.119）}"
MODE="${3:-dry-run}"
[[ "$RUN_KEY" =~ ^[a-z0-9-]{1,60}$ ]] || { echo "::error::run の印は英小文字・数字・- だけ（例 1736）"; exit 1; }
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "::error::版の形が変です（例 1.1.119）"; exit 1; }
case "$MODE" in apply|dry-run) ;; *) echo "::error::3つ目は apply か dry-run"; exit 1 ;; esac

. "$(dirname "$0")/private-s3.sh"
rc=0
private_s3_check || rc=$?
[ "$rc" -eq 0 ] || { echo "::error::非公開の置き場が使えません: $PRIVATE_S3_WHY"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

if ! private_s3_get "$RUN_KEY" "store.tar" "$WORK/store.tar"; then
    echo "::error::$PRIVATE_S3_WHY"
    # 下見なら、絵が無くても App Store Connect を読む（鍵の権限・版の状態・今の組が同じ回で分かる）。結果は赤のまま
    if [ "$MODE" = "dry-run" ]; then
        python3 -I Tools/asc-screenshots.py --version "$VERSION" || true
    fi
    exit 1
fi
mkdir -m 700 "$WORK/store"
# 外へ書き出す名前（../ や絶対パス・リンク）を断ってほどく（`Tools/fetch-shots.sh` と同じ）
python3 -I - "$WORK/store.tar" "$WORK/store" <<'PY'
import sys, tarfile
with tarfile.open(sys.argv[1]) as tar:
    tar.extractall(sys.argv[2], filter="data")
PY

args=(--dir "$WORK/store" --version "$VERSION")
[ "$MODE" = "apply" ] && args+=(--apply)
# ログには一時フォルダの道を出さない
status=0
python3 -I Tools/asc-screenshots.py "${args[@]}" | sed "s#$WORK/store/##g" || status=$?

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        if [ "$status" -ne 0 ]; then
            echo "### 版 ${VERSION} の画面写真: 止まりました（${MODE}）"
            echo "理由は「画面写真を入れ替える」の段のログの赤い行"
        elif [ "$MODE" = "apply" ]; then
            echo "### 版 ${VERSION} の画面写真を入れ替えました（run ${RUN_KEY} の絵）"
            echo "各言語・各組の枚数と状態は段のログの「入れ替えたあとの組」。終わったら \`bash Tools/fetch-shots.sh ${RUN_KEY} --delete\`"
        else
            echo "### 版 ${VERSION} の画面写真の下見（何も変えていません）"
            echo "消す絵と上げる絵は段のログ。よければ apply=true で流し直す"
        fi
    } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$status"
