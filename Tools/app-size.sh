#!/usr/bin/env bash
#
# アプリの中身の大きさの内訳を出す（2026-10-31 判断・札 #429 アプリ 1「測る仕組み」。2026-11-26 判断で台本に分けた）。
#
#     bash Tools/app-size.sh <.app> [ipa] [リンクの地図]
#
# 呼ぶのは `ios-testflight.yml` の2か所:
#   - 「アプリサイズを確認」（Archive した回。配る ipa から）
#   - 「Release の大きさを測る」（ビルドだけの回で `size=true` のとき。署名しない Archive から・リンクの地図つき）
#
# 出すもの: .app と ipa の大きさ・App Store から落とす大きさの見込み・.app の直下・Frameworks・1MB を超えるファイル・
# 拡張子ごと・本体のバイナリの区画（__TEXT など）・Assets.car の中の絵（大きい順）・部品ごとの本体の大きさ（地図があるとき）。
#
# **App Store から落とす大きさの見込み**: 本体のバイナリは配るときに暗号がかかり、ほとんど縮まない。
# それ以外（絵・書体・JSON）は zip で縮む。なので「本体の大きさ + 本体を除いた .app を zip した大きさ」を見込みにする
# （Apple が数える正しい値は App Store Connect の「App Store ファイルサイズ」。ここでは前後を比べるための目安）。
#
# 落ちても止めない（呼ぶ側が continue-on-error）。macOS の道具（assetutil・size）が無いときは、その節を飛ばす。
set -uo pipefail

app="${1:?.app の置き場を渡す}"
ipa="${2:-}"
linkmap="${3:-}"
[ -d "$app" ] || { echo ".app が見つかりません: $app"; exit 1; }
name="$(basename "$app" .app)"
binary="$app/$name"

kb() { du -sk "$1" 2>/dev/null | cut -f1; }

echo "== 全体（KB）=="
[ -n "$ipa" ] && [ -f "$ipa" ] && echo "ipa: $(kb "$ipa")（$(basename "$ipa")）"
echo ".app（入れたあとの大きさの目安）: $(kb "$app")"
if [ -f "$binary" ]; then
    work="$(mktemp -d)"
    # 本体を除いた .app を zip にする（ditto が無い Linux では zip）
    mkdir -p "$work/c"
    cp -R "$app" "$work/c/"
    rm -f "$work/c/$(basename "$app")/$name"
    if command -v ditto >/dev/null 2>&1; then
        (cd "$work/c" && ditto -c -k --keepParent "$(basename "$app")" "$work/rest.zip")
    else
        (cd "$work/c" && zip -qr "$work/rest.zip" "$(basename "$app")")
    fi
    bin_kb="$(kb "$binary")"
    rest_kb="$(kb "$work/rest.zip")"
    echo "本体のバイナリ: ${bin_kb}"
    echo "本体を除いた .app の zip: ${rest_kb}"
    echo "App Store から落とす大きさの見込み（本体 + 残りの zip）: $(( bin_kb + rest_kb ))"
    rm -rf "$work"
fi

echo
echo "== .app の直下（大きい順・KB）=="
du -sk "$app"/* 2>/dev/null | sort -rn | sed "s|$app/||" | head -40

if [ -d "$app/Frameworks" ]; then
    echo
    echo "== Frameworks（大きい順・KB）=="
    du -sk "$app"/Frameworks/* 2>/dev/null | sort -rn | sed "s|$app/||" | head -40
fi

echo
echo "== 1MB を超えるファイル（大きい順・KB）=="
find "$app" -type f -size +1024k -exec du -k {} + 2>/dev/null | sort -rn | sed "s|$app/||" | head -40

echo
echo "== 種類ごと（拡張子・KB）=="
find "$app" -type f -exec du -k {} + 2>/dev/null \
  | awk -F'\t' '{ n = split($2, p, "/"); f = p[n]; e = (index(f, ".") ? f : "(なし)"); sub(/^.*\./, "", e); s[e] += $1 } END { for (e in s) print s[e], e }' \
  | sort -rn | head -20

if [ -f "$binary" ] && command -v size >/dev/null 2>&1; then
    echo
    echo "== 本体のバイナリの区画（バイト）=="
    size -m "$binary" 2>/dev/null | head -60
fi

if [ -f "$app/Assets.car" ] && command -v xcrun >/dev/null 2>&1; then
    echo
    echo "== Assets.car の中の絵（大きい順・KB・縮め方）=="
    xcrun --sdk iphoneos assetutil --info "$app/Assets.car" 2>/dev/null | python3 "$(dirname "$0")/car-summary.py" \
        || echo "（assetutil で読めませんでした）"
fi

if [ -n "$linkmap" ] && [ -f "$linkmap" ]; then
    echo
    echo "== 本体のバイナリの部品ごと（リンクの地図から）=="
    python3 "$(dirname "$0")/linkmap-summary.py" "$linkmap"
fi
