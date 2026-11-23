#!/usr/bin/env bash
#
# storeShots の回で作った App Store 用の画面写真を、その場から App Store Connect の「提出の準備中」の版に
# 入れ替える（2026-11-23・札 #604）。呼ぶのは `ios-testflight.yml` の「App Store Connect に画面写真を入れ替える」の段
# （`ascVersion` を渡した storeShots の回だけ）。
#
#     bash Tools/asc-screenshots.sh --local <絵のフォルダ> <版> [apply]     # 例 --local "$RUNNER_TEMP/store-out" 1.1.119（下見）
#
# **既定は下見（dry-run）。** 4つ目が `apply` のときだけ App Store Connect を変える。中身は `Tools/asc-screenshots.py`。
# 絵のフォルダは `Tools/upload-store-shots.sh` が `STORE_SHOTS_KEEP` に残したもの（大型が直下、中型が `medium-1206x2622/`。
# どの組に入れるかは PNG の寸法で決める）。
#
# 2026-11-23 判断（コーディネーターの指示）: S3 から取り直す形はやめた。CI の役割は置くこと（s3:PutObject）しかできず、
# AWS の権限を変えずに済むように、絵を作った回の中から上げる。手で流す単独の workflow も置かない
#
# 🔴 公開リポジトリなので、絵はログ・成果物に出さない（#451）。ログに出すのはファイル名・枚数・状態だけ
set -euo pipefail

[ "${1:-}" = "--local" ] || { echo "::error::使い方: bash Tools/asc-screenshots.sh --local <絵のフォルダ> <版> [apply]"; exit 1; }
DIR="${2:?絵のフォルダを渡してください}"
VERSION="${3:?版を渡してください（例 1.1.119）}"
MODE="${4:-dry-run}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "::error::版の形が変です（例 1.1.119）"; exit 1; }
case "$MODE" in apply|dry-run) ;; *) echo "::error::4つ目は apply か dry-run"; exit 1 ;; esac
[ -d "$DIR" ] || { echo "::error::絵のフォルダがありません（App Store 用の絵を作る段が通っていない）"; exit 1; }

args=(--dir "$DIR" --version "$VERSION")
[ "$MODE" = "apply" ] && args+=(--apply)
# ログには一時フォルダの道を出さない
status=0
python3 -I Tools/asc-screenshots.py "${args[@]}" | sed "s#${DIR%/}/##g" || status=$?

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        if [ "$status" -ne 0 ]; then
            echo "### 版 ${VERSION} の画面写真: 止まりました（${MODE}）"
            echo "理由は「App Store Connect に画面写真を入れ替える」の段のログの赤い行"
        elif [ "$MODE" = "apply" ]; then
            echo "### 版 ${VERSION} の画面写真を App Store Connect で入れ替えました"
            echo "各言語・各組の枚数と状態は段のログの「入れ替えたあとの組」"
        else
            echo "### 版 ${VERSION} の画面写真の下見（App Store Connect は何も変えていません）"
            echo "消す絵と上げる絵は段のログ。よければ ascApply=true で流し直す"
        fi
    } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$status"
