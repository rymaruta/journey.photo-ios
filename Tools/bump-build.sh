#!/usr/bin/env bash
#
# ビルド番号を上げる（手元の Xcode から出すとき用。CI は ios-testflight.yml が決める）。
#
# **ビルド番号は表に出る版ごとに 1 から数える**（2026-10-18 owner の判断:
# TestFlight の表示を「1.1.15 (1)」の形に）。CI と同じ考え:
#
#     bash Tools/bump-build.sh            # 同じ版でもう一度: 1.1.15 (1) → 1.1.15 (2)
#     bash Tools/bump-build.sh 1.1.15     # 今と同じ版を渡したときも +1
#     bash Tools/bump-build.sh 1.1.16     # 版を変えた: 1.1.16 (1)
#
# **TestFlight は同じ版の中で同じビルド番号を受け付けない。** 上げ忘れは
# 上げ切ったあとに気づくので、毎回これを通す。別の版なら番号を使い直してよい
# （Apple の TN2420 "Version Numbers and Build Numbers" で確認・iOS の場合）。
#
# 手元の project.yml の番号から数えるので、TestFlight に同じ版の手元にない
# ビルドがあると重なる。そのときは `Tools/set-build-number.sh <番号>` で直に決める
set -euo pipefail
cd "$(dirname "$0")/.."

# **`\s` は使わない**（BSD grep / BSD sed は読まない＝macOS で黙って外れる）。
# 詳しくは Tools/set-build-number.sh の注記
CURRENT=$(grep -E '^[[:space:]]+CURRENT_PROJECT_VERSION:' project.yml | grep -oE '[0-9]+' | head -1)
if [ -z "${CURRENT:-}" ]; then
    echo "project.yml から今のビルド番号を読めませんでした"
    exit 1
fi

CURRENT_VERSION=$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml | grep -oE '[0-9]+(\.[0-9]+)*' | head -1)

# 版を変えたら 1、同じ版（または版を渡さない）なら +1
if [ $# -ge 1 ] && [ "$1" != "${CURRENT_VERSION:-}" ]; then
    NEXT_BUILD=1
else
    NEXT_BUILD=$((CURRENT + 1))
fi

# 書き換えと確認は1か所にまとめる（CI も同じものを使う）
bash Tools/set-build-number.sh "$NEXT_BUILD"

if [ $# -ge 1 ]; then
    sed -i.bak -E "s/^([[:space:]]+MARKETING_VERSION: )\"?[0-9.]+\"?/\1\"$1\"/" project.yml
    rm -f project.yml.bak
    if ! grep -qE "^[[:space:]]+MARKETING_VERSION: \"$1\"" project.yml; then
        echo "project.yml の表に出る版を書き換えられませんでした（$1 にならなかった）"
        exit 1
    fi
    echo "表に出る版: $1"
fi

python3 Tools/check-config.py
