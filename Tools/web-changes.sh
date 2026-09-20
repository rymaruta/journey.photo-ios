#!/usr/bin/env bash
#
# Web 版（photo-gallery）で、前回合わせたところから何が変わったかを出す。
#
# **追従を記憶に頼らない**ための道具。`docs/WEB_SYNC.md` に書いてある
# 「前回合わせたコミット」以降で、アプリに効く場所を触った変更だけを並べる。
#
#     bash Tools/web-changes.sh [photo-gallery の場所]
set -euo pipefail
cd "$(dirname "$0")/.."

GALLERY="${1:-${PHOTO_GALLERY:-../photo-gallery}}"
if [ ! -d "$GALLERY/api-user" ]; then
    echo "photo-gallery が $GALLERY に見つかりません（引数か PHOTO_GALLERY で渡してください）"
    exit 2
fi

SINCE=$(grep -oE '^- 前回合わせたコミット: `[0-9a-f]+`' docs/WEB_SYNC.md | grep -oE '[0-9a-f]{7,}' | head -1)
if [ -z "$SINCE" ]; then
    echo "docs/WEB_SYNC.md に「前回合わせたコミット」がありません"
    exit 2
fi

echo "== $SINCE 以降の変更（アプリに効く場所だけ）"
echo
# **アプリに効くのはこの3つ。** それ以外（SEO・静的書き出し・Service Worker）は
# アプリに持ち込む相手が無い
for scope in \
    "api-user/:API の契約（応答の形・新しい口・認証の有無）" \
    "lib/utils/:表示の規則（題の扱い・日付・タグ・座標の丸め）" \
    "app/components/:画面の作り（導線・文言・並び）"
do
    path="${scope%%:*}"
    label="${scope#*:}"
    echo "-- $label  [$path]"
    git -C "$GALLERY" log --oneline "$SINCE..origin/main" -- "$path" | sed 's/^/   /' || true
    echo
done

echo "== 突き合わせ"
python3 Tools/check-api-parity.py "$GALLERY"
