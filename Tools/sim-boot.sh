#!/usr/bin/env bash
#
# Mac の CI で、組む前の支度（キャッシュの復元）のあいだに、シミュレーターを**裏で起動しておく**（札 #610・2026-11-15 判断）。
#
#     DEVICE="iPhone 17 Pro Max" bash Tools/sim-boot.sh start    # 裏で起動を始めて、すぐ戻る
#     bash Tools/sim-boot.sh report                              # 裏の起動が終わったか・何秒かかったか
#
# **理由（数）**: 単体テストの段で、結果の置き場を書いてから最初のテストまで 151〜357秒（run 1332〜1334）。
# `measured [sim]` の行では、そのうちシミュレーターの起動が 46〜330秒。xcodebuild はテストを始めてから
# 起動するので、それまでシミュレーターは何もしていない。先に起動しておけば、単体テストの段で待たない。
# 組む段の中では起動しない（起動の間 xcodebuild の立ち上がりが止まる・run 1336。`ios-testflight.yml` の注記）。
#
# 時刻はこの台の /tmp に置き、端末の識別子は出さない（公開のリポジトリなので、ログに残さない）。
# どこで失敗しても落とさない（xcodebuild が起動していなければ自分で起動する。それが本来の道）。
# **macOS の /bin/bash は 3.2**。それで書く。
set -u
cd "$(dirname "$0")/.."

STATE="${SIM_BOOT_STATE:-/tmp/sim-boot}"
mode="${1:?start か report を渡す}"

case "$mode" in
    start)
        DEVICE="${DEVICE:-$(python3 Tools/pick-simulator.py)}"
        rm -rf "$STATE"; mkdir -p "$STATE"
        date +%s > "$STATE/start"
        # 同じ名前の機種が何台あるか（2台以上なら、xcodebuild が別の1台を使うおそれがある。数だけ出す）
        same="$(xcrun simctl list devices available 2>/dev/null | grep -cF "    $DEVICE (" || true)"
        echo "measured [sim] 裏で起動を始めた（同じ名前の機種 ${same} 台）"
        (
            xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
            xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
            date +%s > "$STATE/done"
        ) </dev/null >/dev/null 2>&1 &
        exit 0
        ;;
    report)
        [ -f "$STATE/start" ] || exit 0
        started="$(cat "$STATE/start")"
        if [ -f "$STATE/done" ]; then
            echo "measured [sim] 裏の起動は $(( $(cat "$STATE/done") - started ))s で終わっていた"
        else
            echo "measured [sim] 裏の起動はまだ終わっていない（始めてから $(( $(date +%s) - started ))s）"
        fi
        exit 0
        ;;
    *)
        echo "使い方: sim-boot.sh start | report" >&2
        exit 2
        ;;
esac
