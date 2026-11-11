#!/usr/bin/env bash
#
# PR がアプリ（ソース・テスト・設定）を変えているかを出す（true / false）。2026-11-11 に ios-pr.yml の
# 「アプリ変更の有無」から取り出した（ios-quick.yml も同じ決め方を使う・写しを作らない）。
#
#     bash Tools/app-changed.sh <base の sha>
#
# ワークフロー・Actions の部品・docs・Markdown だけの変更なら false（Mac と Linux の単体テストを起こさない）。
# 差分が取れない・空のときは true（安全側で回す）
set -uo pipefail
base="${1:-}"
if [ -z "$base" ]; then echo true; exit 0; fi
if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
    git -c protocol.version=2 fetch --no-tags --depth=1 origin "$base" >/dev/null 2>&1 || true
fi
if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then echo true; exit 0; fi
if ! files="$(git diff --name-only --no-ext-diff --find-renames "$base" HEAD)"; then echo true; exit 0; fi
if [ -z "$files" ]; then echo true; exit 0; fi
if printf '%s\n' "$files" | grep -Ev '^(\.github/workflows/|\.github/actions/|docs/|.*\.md$)' | grep -q .; then
    echo true
else
    echo false
fi
