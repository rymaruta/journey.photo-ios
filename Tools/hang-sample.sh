#!/bin/bash
# UI テストの間だけ裏で動かす見張り（2026-11-20・札 #662 の「Failed to terminate」の調べ）。
#
# XCTest が前のアプリを閉じようとした（ログに「Terminate com.journeyphoto…:<pid>」が出た）のに、
# 15 秒たってもそのアプリが残っていたら、その場でアプリの積み（`sample`）を取り、主スレッドの所を
# `measured [hang-sample]` の行で段のログに出す。全文は /tmp/hang-<pid>.txt（公開の成果物には入れない）。
#
#   bash Tools/hang-sample.sh /tmp/xcodebuild-full.log &
#
# 見張るだけで、テストの成否は変えない。macOS の `sample` が無い所では何もしない。
set -u
LOG="${1:-/tmp/xcodebuild-full.log}"
command -v sample >/dev/null 2>&1 || exit 0
seen=" "
# ログがまだ無ければ待つ
for _ in $(seq 1 120); do [ -f "$LOG" ] && break; sleep 1; done
tail -n 0 -F "$LOG" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
        *"Terminate com.journeyphoto."*)
            pid="${line##*:}"
            pid="${pid//[^0-9]/}"
            [ -n "$pid" ] || continue
            case "$seen" in *" $pid "*) continue ;; esac
            seen="$seen$pid "
            (
                sleep 15
                kill -0 "$pid" 2>/dev/null || exit 0
                out="/tmp/hang-$pid.txt"
                echo "measured [hang-sample] pid=$pid 閉じると言われて 15 秒たっても残っている。積みを取る"
                ps -o pid,stat,etime,command -p "$pid" 2>/dev/null | sed 's/^/measured [hang-sample] ps /'
                sample "$pid" 3 -mayDie -file "$out" >/dev/null 2>&1 || echo "measured [hang-sample] pid=$pid sample が取れない"
                if [ -f "$out" ]; then
                    # 主スレッドの積み（最初の 80 行）と、全部のスレッドの頭の行
                    awk '/com.apple.main-thread/{on=1} on{print; n++} n>=80{exit}' "$out" | sed 's/^/measured [hang-sample] main /'
                    grep -E '^ +[0-9]+ Thread_' "$out" | head -40 | sed 's/^/measured [hang-sample] thread /'
                fi
            ) &
            ;;
    esac
done
