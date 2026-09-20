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

# `sed -i.bak` は macOS でも Linux でも同じに動く（`-i ''` は GNU で落ちる）。
#
# **`\s` は使わない。** GNU sed は読むが、macOS（BSD sed）は読まない
# ——CI は macOS なので、置換が**黙って何もしないまま成功する**。
# ビルド番号が上がらず、TestFlight に「同じ番号は受け付けません」で
# はねられて初めて気づく。`[[:space:]]` は両方で同じに動く。
sed -i.bak -E "s/^([[:space:]]+CURRENT_PROJECT_VERSION: )\"?[0-9]+\"?/\1\"$NEXT\"/" project.yml
rm -f project.yml.bak

# **書けたことを確かめてから終わる。** 置換が効かなくても sed は 0 を返す
if ! grep -qE "^[[:space:]]+CURRENT_PROJECT_VERSION: \"$NEXT\"" project.yml; then
    echo "project.yml のビルド番号を書き換えられませんでした（$NEXT にならなかった）"
    grep -E '^[[:space:]]+CURRENT_PROJECT_VERSION:' project.yml
    exit 1
fi

echo "ビルド番号: $NEXT"
grep -E '^[[:space:]]+CURRENT_PROJECT_VERSION:' project.yml
