#!/usr/bin/env bash
#
# ビルド番号を指定の値にする。CI から使う（`bump-build.sh` は手元用）。
#
#     bash Tools/set-build-number.sh 42
set -euo pipefail
cd "$(dirname "$0")/.."

NEXT="${1:?ビルド番号を渡してください}"
case "$NEXT" in
    ''|*[!0-9]*) echo "数字ではありません: $NEXT"; exit 1 ;;
esac

# `sed -i.bak` は macOS でも Linux でも同じに動く（`-i ''` は GNU で落ちる）
sed -i.bak -E "s/^(\s+CURRENT_PROJECT_VERSION: )\"?[0-9]+\"?/\1\"$NEXT\"/" project.yml
rm -f project.yml.bak

echo "ビルド番号: $NEXT"
grep -E '^\s+CURRENT_PROJECT_VERSION:' project.yml
