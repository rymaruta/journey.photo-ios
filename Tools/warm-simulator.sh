#!/usr/bin/env bash
#
# UI テストの前に、シミュレーターを起動し、組んだアプリを1回起動して閉じる（2026-10-31・#429 の試し）。
#
#     DEVICE="iPhone 17 Pro Max" bash Tools/warm-simulator.sh build/products
#
# **試しの理由（記録）**: 別々の Mac に分けて流すようにしてから、各台の**最初の** UI テストで2回落ちた
# （run 791 の組 1・run 805 の組 3。12 本中 2 本。2本目以降は約 270 本で 0 本）。最初のテストの起動は
# 11〜49 秒（2本目以降は 2〜6 秒）。前の1台の作りでは、単体テストが同じシミュレーターで先にアプリを
# 起動していて、UI の最初の起動は 7 秒だった（run 778）。その条件に戻して、落ちが減るかを数で比べた。
#
# **比べた数（2026-11-01）**: 各台の最初の UI テスト
#   - 温め無し（run 791・800・805・12 本）: 起動 11.7〜76.5 秒（真ん中 29.0）・落ちた 2 本
#   - 温め有り（run 809・812・8 本）     : 起動 6.2〜49.3 秒（真ん中 12.6）・落ちた 0 本
#   - 温めの手間は1台 2.5〜7.6 分（起動 71〜118 秒・入れる 26〜90 秒・アプリの起動 6〜314 秒＋20 秒）
# 本数がまだ少ない（8 本）。落ちが出たら、ここの数に足して考え直す。
# 落ちた2回の中身（録画・UI の木）: 805 はマイページのタブを押して選択が動き始めたあと 70ms でホームに戻った。
# 791 は 3D の絵が描かれる前に「中に入る」を押していた。どちらもアプリの側の理由はまだ分かっていない（#429）
#
# 時間（秒）を標準出力と GITHUB_STEP_SUMMARY に出す。どこかで失敗しても落とさない（テストの結果が本来の見張り）
set -u

products="${1:?組んだ品の置き場（build/products）を渡す}"
DEVICE="${DEVICE:-$(python3 "$(dirname "$0")/pick-simulator.py")}"
app="$(find "$products" -maxdepth 2 -name 'JourneyPhoto.app' -type d | head -1)"
if [ -z "$app" ]; then
    echo "::warning::温め: JourneyPhoto.app が見つかりません（${products}）。温めずに進みます"
    exit 0
fi
bundle="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist" 2>/dev/null)"

now() { python3 -c 'import time; print(time.time())'; }
since() { python3 -c "import sys; print(f'{float(sys.argv[2]) - float(sys.argv[1]):.1f}')" "$1" "$(now)"; }

t0="$(now)"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
boot="$(since "$t0")"

t1="$(now)"
xcrun simctl install "$DEVICE" "$app" || echo "::warning::温め: 入れられませんでした"
install="$(since "$t1")"

t2="$(now)"
xcrun simctl launch "$DEVICE" "$bundle" >/dev/null || echo "::warning::温め: 起動できませんでした"
launch="$(since "$t2")"
# 起動のあとの読み込み（一覧・字体・3D の初回の支度）が進むよう、しばらく開いたままにする
sleep 20
xcrun simctl terminate "$DEVICE" "$bundle" 2>/dev/null || true

line="温め（${DEVICE}・${bundle}）: 起動 ${boot} 秒・入れる ${install} 秒・アプリの起動 ${launch} 秒＋開いたまま 20 秒"
echo "$line"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "- $line" >> "$GITHUB_STEP_SUMMARY"
exit 0
