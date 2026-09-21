#!/usr/bin/env bash
#
# ビルド番号を1つ上げる。
#
# **TestFlight と App Store は同じビルド番号を受け付けない。** 上げ忘れは
# 上げ切ったあとに気づくので、毎回これを通す。
#
#     bash Tools/bump-build.sh            # 1 → 2
#     bash Tools/bump-build.sh 0.2.0      # 表に出る版も上げる
set -euo pipefail
cd "$(dirname "$0")/.."

# **`\s` は使わない**（BSD grep / BSD sed は読まない＝macOS で黙って外れる）。
# 詳しくは Tools/set-build-number.sh の注記
CURRENT=$(grep -E '^[[:space:]]+CURRENT_PROJECT_VERSION:' project.yml | grep -oE '[0-9]+' | head -1)
if [ -z "${CURRENT:-}" ]; then
    echo "project.yml から今のビルド番号を読めませんでした"
    exit 1
fi

# 書き換えと確認は1か所にまとめる（CI も同じものを使う）
bash Tools/set-build-number.sh "$((CURRENT + 1))"

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
