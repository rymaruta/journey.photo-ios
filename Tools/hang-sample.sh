#!/bin/bash
# UI テストの間だけ裏で動かす見張り（2026-11-20・札 #662 の「Failed to terminate」の調べ）。
#
# XCTest が前のアプリを閉じようとした（ログに「Terminate com.journeyphoto…:<pid>」が出た）のに、
# 15 秒たってもそのアプリが残っていたら、その場でアプリの積み（`sample`）を取り、主スレッドの所を
# `measured [hang-sample]` の行で段のログに出す。全文は /tmp/hang-<pid>.txt（公開の成果物には入れない）。
#
#   bash Tools/hang-sample.sh /tmp/xcodebuild-full.log &
#
# 見張るだけで、テストの成否は変えない。macOS の `sample` が無い所では何もしない（試験は HANG_SAMPLE_TOOL で差し替える）。
#
# 2026-11-21 判断（run 1677・1683 の調べ）: 2回とも「Failed to terminate」で落ちたのに、この見張りは1行も出さなかった。
# 見張りが動いていなかったのか、アプリが 15 秒より前に消えていたのか（XCTest が消えたことに気づいていない）を、
# ログから見分けられなかった。run 1681 では積みを取りに行ったが、`sample` の後の行が出ず（固まった・権限で断られた、の見分けが
# つかない）。だから次の4つを足した:
# - 見張りを始めた行と、閉じると言われたアプリを見つけた行を、いつも出す
# - 5・15・30・45 秒の時点で、残っているか（ps の状態）か消えたかを出す（消えていれば「XCTest の気づき漏れ」の手がかり）
# - `sample` に時間の上限（20 秒）を付け、断りの文（stderr）もログに出す。取れなければ lldb の `bt all` を試す
# - 「Failed to terminate …:<pid>」の行を見たら、その pid と、残っている JourneyPhoto のプロセスを全部出す
set -u
LOG="${1:-/tmp/xcodebuild-full.log}"
TOOL="${HANG_SAMPLE_TOOL:-sample}"
WAIT_FIRST="${HANG_SAMPLE_CHECKS:-5 15 30 45}"
# 積みを取り始める秒（これより前の確かめでは状態だけ出す）
SAMPLE_AT="${HANG_SAMPLE_AT:-15}"
command -v "$TOOL" >/dev/null 2>&1 || exit 0
# 段のログ（job の出力）と、成果物の xcodebuild-full.log の両方に出す（読む側はどちらでも探せる）
say() { echo "measured [hang-sample] $*" | tee -a "$LOG"; }

# 上限つきで走らせる（macOS には timeout が無い）。上限を越えたら止めて、その旨を出す
bounded() {
    local limit="$1"; shift
    "$@" &
    local p=$!
    ( sleep "$limit"; kill -9 "$p" 2>/dev/null && say "時間切れ（${limit}s）: $1" ) &
    local guard=$!
    wait "$p" 2>/dev/null
    local status=$?
    kill "$guard" 2>/dev/null
    return $status
}

state() { ps -o stat=,etime= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //'; }

stack() {
    local pid="$1" out="/tmp/hang-$1.txt" err="/tmp/hang-$1.err"
    bounded 20 "$TOOL" "$pid" 3 -mayDie -file "$out" >/dev/null 2>"$err"
    local status=$?
    if [ ! -s "$out" ]; then
        say "pid=$pid sample が取れない（終わりの値 ${status}）: $(head -c 300 "$err" 2>/dev/null | tr '\n' ' ')"
        if command -v xcrun >/dev/null 2>&1; then
            bounded 30 xcrun lldb --batch -p "$pid" -o "thread backtrace all" -o "detach" >"$out" 2>"$err"
            [ -s "$out" ] || say "pid=$pid lldb でも取れない: $(head -c 300 "$err" 2>/dev/null | tr '\n' ' ')"
        fi
    fi
    if [ -s "$out" ]; then
        # 主スレッドの積み（最初の 80 行）と、全部のスレッドの頭の行。lldb の形（thread #1）も読む
        awk '/com.apple.main-thread|^\* thread #1|^  thread #1/{on=1} on{print; n++} n>=80{exit}' "$out" | sed 's/^/measured [hang-sample] main /' | tee -a "$LOG"
        grep -E '^ +[0-9]+ Thread_|^[ *] thread #' "$out" | head -40 | sed 's/^/measured [hang-sample] thread /' | tee -a "$LOG"
    fi
}

watch_pid() {
    local pid="$1" waited=0 sampled=0
    for at in $WAIT_FIRST; do
        sleep $((at - waited)); waited=$at
        if ! kill -0 "$pid" 2>/dev/null; then
            say "pid=$pid ${at}s の時点で消えていた（アプリは閉じている）"
            return
        fi
        say "pid=$pid ${at}s の時点で残っている（状態 $(state "$pid")）"
        if [ "$sampled" = 0 ] && [ "$at" -ge "$SAMPLE_AT" ]; then
            say "pid=$pid 閉じると言われて ${at} 秒たっても残っている。積みを取る"
            stack "$pid"
            sampled=1
        fi
    done
}

say "見張りを始めた（${LOG}）"
seen=" "
failed=" "
# ログがまだ無ければ待つ
for _ in $(seq 1 120); do [ -f "$LOG" ] && break; sleep 1; done
tail -n 0 -F "$LOG" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
        *"measured [hang-sample]"*) ;;
        *"Failed to terminate com.journeyphoto."*)
            pid="${line#*Failed to terminate com.journeyphoto.}"
            pid="${pid#*:}"
            pid="${pid%%[!0-9]*}"
            [ -n "$pid" ] || continue
            case "$failed" in *" $pid "*) continue ;; esac
            failed="$failed$pid "
            if kill -0 "$pid" 2>/dev/null; then
                say "XCTest が閉じられなかった pid=$pid はまだ残っている（状態 $(state "$pid")）"
            else
                say "XCTest が閉じられなかった pid=$pid はもう無い（XCTest が消えたことに気づいていない）"
            fi
            ps -axo pid,stat,etime,command 2>/dev/null | grep '/JourneyPhoto.app/JourneyPhoto' | grep -v grep \
                | cut -c1-60 | sed 's/^/measured [hang-sample] ps /' | tee -a "$LOG"
            ;;
        *"Terminate com.journeyphoto."*)
            pid="${line##*:}"
            pid="${pid//[^0-9]/}"
            [ -n "$pid" ] || continue
            case "$seen" in *" $pid "*) continue ;; esac
            seen="$seen$pid "
            say "pid=$pid 閉じると言われた"
            watch_pid "$pid" &
            ;;
    esac
done
