#!/usr/bin/env bash
#
# TestFlight に出す**表に出る版**（`MARKETING_VERSION`）を決めて、
# project.yml に書く。CI（`ios-testflight.yml`）から使う。
#
#     bash Tools/next-marketing-version.sh      # → 0.2.1 などを表示して書き込む
#
# **毎回、最後の数字を1つ上げる**（owner の依頼・2026-09-25）。
# 0.2.0 → 0.2.1 → 0.2.2 … TestFlight の一覧で、どの版かが一目で分かる。
#
# **どこまで出したかは git のタグで覚える。** 上げるのに成功した回だけ
# `testflight/<版>` のタグを付ける（ワークフローの「版の印を付ける」）。
# 次の回はそれを見て +1 する。App Store Connect に問い合わせない
# ——手元（Linux）で動きを確かめられる形にしておくため。
#
# **真ん中の数字は人が上げる**（大きく変わる版のとき）:
#
#     bash Tools/bump-build.sh 0.3.0     # project.yml を 0.3.0 にしてコミット
#
# project.yml の版が、出したことのある最大より**新しければそれを使う**
# （0.3.0 と書けば 0.3.0 から始まる）。同じか古ければ、最大 +1。
# 上げるのに失敗した回はタグが付かないので、同じ番号がもう一度使われる。
set -euo pipefail
cd "$(dirname "$0")/.."

# **`\s` は使わない**（macOS の BSD sed / grep が読まない。set-build-number.sh の注記）
BASE=$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -z "${BASE:-}" ]; then
    echo "project.yml から表に出る版（X.Y.Z）を読めませんでした" >&2
    exit 1
fi
SERIES="${BASE%.*}"      # 0.2
BASE_PATCH="${BASE##*.}" # 0

# 印は浅い checkout には来ないので、取りに行く（取れなくても先へ進む＝初回扱い）
git fetch --quiet --force origin 'refs/tags/testflight/*:refs/tags/testflight/*' 2>/dev/null || true

LAST=$(git tag -l "testflight/${SERIES}.*" \
        | sed -E "s|^testflight/${SERIES//./\\.}\.||" \
        | grep -E '^[0-9]+$' | sort -n | tail -1 || true)

if [ -n "${LAST:-}" ] && [ "$LAST" -ge "$BASE_PATCH" ]; then
    NEXT="${SERIES}.$((LAST + 1))"
else
    NEXT="$BASE"
fi

sed -i.bak -E "s/^([[:space:]]+MARKETING_VERSION: )\"?[0-9.]+\"?/\1\"$NEXT\"/" project.yml
rm -f project.yml.bak
if ! grep -qE "^[[:space:]]+MARKETING_VERSION: \"$NEXT\"" project.yml; then
    echo "project.yml の表に出る版を $NEXT に書き換えられませんでした" >&2
    exit 1
fi
echo "$NEXT"
