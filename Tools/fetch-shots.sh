#!/usr/bin/env bash
#
# Mac の CI が非公開の S3 に置いた画面写真を、手元（scratchpad）に落として見る・消す（2026-11-12 owner）。
# TestFlight の落ちた記録（`Tools/testflight-crashes.sh`・印 testflight-crashes-<run>）も同じ使い方（2026-11-14）。
# 置くのは `Tools/upload-shots.sh`。置き場は3日で自動で消える（`Tools/ci-shots/lifecycle.json`）。
#
#     bash Tools/fetch-shots.sh --list            # 置き場にある run の印の一覧
#     bash Tools/fetch-shots.sh 1160              # run 1160 の絵を落とす（<落とす先>/1160/<組>/…）
#     bash Tools/fetch-shots.sh 1160 --clean      # 見終わった: 手元の 1160 を消す
#     bash Tools/fetch-shots.sh 1160 --delete     # 見終わった: 手元と S3 の 1160 をすぐ消す（3日を待たない）
#
# 🔴 **落とす先はリポジトリの外**（scratchpad）。リポジトリの中には置かない（公開リポジトリ・#451）。
#   既定は `SHOTS_DIR`、無ければこのリポジトリの Claude の scratchpad の `shots/`
#   （`/tmp/claude-*/-home-user-journey-photo-ios/*/scratchpad` のいちばん新しいもの）。
#   リポジトリの中を指したら止まる
# 🔴 **見たら消す。** 画面写真には試験用の利用者の写真・名前が写る。見終わったら `--clean`（S3 も消すなら `--delete`）。
#   人に渡した絵（SendUserFile など）も、渡し終わったら消す
#
# 資格情報: この環境の aws の CLI（プロキシ経由で設定済み）。要るのは置き場の読み・一覧・消す
# （CI の役割は置くことしかできないので、取り出しには使えない）
set -euo pipefail

BUCKET="${CI_SHOTS_BUCKET:-journey-photo-ios-ci-shots}"
export AWS_REGION=ap-northeast-1 AWS_DEFAULT_REGION=ap-northeast-1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() { sed -n '6,10p' "$0" | sed 's/^# \{0,4\}//'; exit 2; }

if [ "${1:-}" = "--list" ]; then
    aws s3 ls "s3://$BUCKET/" | awk '$1 == "PRE" { sub("/$", "", $2); print $2 }' | sort -n
    exit 0
fi

RUN="${1:-}"
MODE="${2:-fetch}"
[ -n "$RUN" ] || usage
[[ "$RUN" =~ ^[a-z0-9-]{1,60}$ ]] || { echo "NG: run の印は英小文字・数字・- だけ: $RUN" >&2; exit 2; }
case "$MODE" in fetch|--clean|--delete) ;; *) usage ;; esac

# ---- 落とす先（リポジトリの外）---------------------------------------------------
if [ -n "${SHOTS_DIR:-}" ]; then
    DIR="$SHOTS_DIR"
else
    pad="$(ls -dt /tmp/claude-*/-home-user-journey-photo-ios/*/scratchpad 2> /dev/null | head -1 || true)"
    [ -n "$pad" ] || { echo "NG: scratchpad が見つかりません。SHOTS_DIR=<scratchpad>/shots を渡してください" >&2; exit 2; }
    DIR="$pad/shots"
fi
# 作る前に確かめる（リポジトリの中に空のフォルダも作らない）
DIR="$(realpath -m -- "$DIR")"
case "$DIR/" in
    "$(realpath -- "$ROOT")"/*) echo "NG: 落とす先がリポジトリの中です: $DIR" >&2; exit 2 ;;
esac
mkdir -p "$DIR"
DEST="$DIR/$RUN"

clean_local() {
    if [ -d "$DEST" ]; then
        rm -rf -- "$DEST"
        echo "手元の絵を消しました: $DEST"
    else
        echo "手元には在りません: $DEST"
    fi
}

case "$MODE" in
    --clean)
        clean_local
        exit 0
        ;;
    --delete)
        clean_local
        aws s3 rm "s3://$BUCKET/$RUN/" --recursive --only-show-errors
        left="$(aws s3 ls "s3://$BUCKET/$RUN/" 2> /dev/null | wc -l | tr -d ' ')"
        if [ "$left" = "0" ]; then
            echo "S3 からも消しました: $RUN"
        else
            echo "NG: S3 に $left 件残っています: $RUN" >&2
            exit 1
        fi
        exit 0
        ;;
esac

# ---- 落とす --------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
aws s3 cp "s3://$BUCKET/$RUN/" "$TMP/" --recursive --exclude '*' --include '*.tar' --only-show-errors
tars=("$TMP"/*.tar)
if [ ! -e "${tars[0]}" ]; then
    echo "NG: 置き場に run $RUN の絵がありません（まだ置かれていない・3日を過ぎて消えた・印の違い。--list で一覧）" >&2
    exit 1
fi
rm -rf -- "$DEST"
mkdir -p "$DEST"
for t in "${tars[@]}"; do
    part="$(basename "$t" .tar)"
    mkdir -p "$DEST/$part"
    # 外へ書き出す名前（../ や絶対パス・リンク）を断ってほどく
    python3 -I - "$t" "$DEST/$part" <<'PY'
import sys, tarfile
with tarfile.open(sys.argv[1]) as tar:
    tar.extractall(sys.argv[2], filter="data")
PY
done

n="$(find "$DEST" -type f \( -name '*.jpg' -o -name '*.png' \) | wc -l | tr -d ' ')"
# TestFlight の落ちた記録（`Tools/testflight-crashes.sh`・組 crashes）も同じ置き場から落とす
c="$(find "$DEST" -type f \( -name '*.ips' -o -name '*.crash' \) | wc -l | tr -d ' ')"
if [ "$c" != "0" ]; then
    echo "run $RUN の落ちた記録 $c 件を落としました: ${DEST}（要点は crashes/index.json・読み方は docs/TESTFLIGHT.md）"
else
    echo "run $RUN の絵 $n 枚を落としました: $DEST"
fi
for readme in "$DEST"/*/README.md; do
    [ -f "$readme" ] || continue
    echo "  $(basename "$(dirname "$readme")"): $(grep -m1 '撮れなかった画面\|絞った回' "$readme" || true)"
done
echo "見終わったら: bash Tools/fetch-shots.sh $RUN --clean（S3 もすぐ消すなら --delete）"
