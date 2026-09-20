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

CURRENT=$(grep -E '^\s+CURRENT_PROJECT_VERSION:' project.yml | grep -oE '[0-9]+' | head -1)
NEXT=$((CURRENT + 1))
sed -i.bak -E "s/^(\s+CURRENT_PROJECT_VERSION: )\"?[0-9]+\"?/\1\"$NEXT\"/" project.yml

if [ $# -ge 1 ]; then
    sed -i.bak -E "s/^(\s+MARKETING_VERSION: )\"?[0-9.]+\"?/\1\"$1\"/" project.yml
    echo "表に出る版: $1"
fi
rm -f project.yml.bak

echo "ビルド番号: $CURRENT → $NEXT"
python3 Tools/check-config.py
