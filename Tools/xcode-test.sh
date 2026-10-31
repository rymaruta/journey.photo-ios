#!/usr/bin/env bash
#
# Mac の CI で、本物の Xcode のテストを**組む → 単体 → UI** の3段に分けて流す
# （`ios-testflight.yml` と `ios-pr.yml` の両方が使う）。
#
#     bash Tools/xcode-test.sh build                         # 組むだけ（build-for-testing）
#     bash Tools/xcode-test.sh unit <結果.xcresult>           # 単体テスト（JourneyPhotoTests）
#     bash Tools/xcode-test.sh ui <結果.xcresult> [<一覧>]    # UI テスト。一覧は Tools/pick-ui-tests.py の出力
#
# **2026-10-17 判断: 1回の `test` を3段に分けた。** 前は単体と UI を1回の `xcodebuild test` で
# 流していたので、単体テストが落ちる回も UI テスト（33分・run 462）を最後まで待ってから赤に
# なった。単体（6分）を先に流し、落ちたらそこで止める（ワークフローの次の段が走らない）。
# 組むのは1回だけ（`test-without-building` は組んだものを使い回す）。
#
# 書き方の理由（`-sdk` を渡さない・arm64 に絞る・xcodebuild を直に叩く）は
# `ios-testflight.yml` の「組む」の段の注記。
#
# **macOS の /bin/bash は 3.2**（`mapfile` も `${var,,}` も無い）。それで書く。
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:?build / unit / ui のどれかを渡す}"
LOG="${XCODE_LOG:-/tmp/xcodebuild-full.log}"
# 機種名は固定しない（Xcode が上がると入っているシミュレータが替わる）。
# 3段で同じ機種を使うよう、ワークフローが `DEVICE` を渡せる
DEVICE="${DEVICE:-$(python3 Tools/pick-simulator.py)}"
echo "シミュレータ: $DEVICE"

# **1本ごとの時間の上限（秒）。** 2026-10-18 判断。
# 🔴 上限が無いと、1本が待ち続けたときに段ごと 90分のジョブの上限まで抜けられない。
# run 233（#274）: xcodebuild が 63秒止まって起動の頼みが遅れ、1本目が「Timed out while launching
# application」で落ちたあと、2本目の起動は「起動の進み具合 0」のまま 72分待ち続けて取り消された
# （signal 19 を送れなかった起動が終わらない）。どの1本で止まったかも結果に残らなかった。
# 上限を越えた1本は Xcode が止め（spindump を取り、テストの実行役を立て直す）、**その1本だけ落として
# 次へ進む**。結果（xcresult）にはその1本が「時間の上限を越えた」として残る。
# Xcode は上限を分単位に切り上げる（60 未満は 60）。
#
# 数の根拠（成功した run 225〜232・TestFlight 515〜522 の xcodebuild のログ、計10回の実測）:
#   - UI テスト: 画面を全部撮る `ScreenshotTests.testCapturesEveryScreen` がいちばん長く 362〜462秒。
#     それ以外は最長 119秒（起動直後の `MedalViewerTests.testNameSideCloseAfterSpin`）。
#     → 既定 300秒（119 の約2.5倍）。全部撮る1本だけはテストの中で `executionTimeAllowance` を
#       1200秒に上げ、上限（maximum）も 1200秒（462 の約2.6倍）。上限はテスト側の指定も頭打ちにする
#   - 単体テスト: 最長 2.3秒（Linux の模型・4088件）。Xcode の最小の 60秒（約25倍）
# 長いテストを足して上限に当たったら、ここの数ではなく、そのテストの `executionTimeAllowance` を
# 実測の2〜3倍で付ける（既定を上げると、詰まった1本を待つ時間が全部のテストで延びる）。
# `Tools/check-config.py` が、この数・渡し方・全部撮る1本の指定を見張る
UNIT_TIME_ALLOWANCE=60
UNIT_TIME_MAXIMUM=60
UI_TIME_ALLOWANCE=300
UI_TIME_MAXIMUM=1200

# `set -u` の bash 3.2 は空の "$@" を「未定義」と言うので、`shift` で進める
shift
case "$mode" in
    build)
        action="build-for-testing"
        extra=""
        ;;
    unit)
        result="${1:?結果の .xcresult の置き場を渡す}"
        rm -rf "$result"
        action="test-without-building"
        extra="-resultBundlePath $result -only-testing:JourneyPhotoTests"
        extra="$extra -test-timeouts-enabled YES"
        extra="$extra -default-test-execution-time-allowance $UNIT_TIME_ALLOWANCE"
        extra="$extra -maximum-test-execution-time-allowance $UNIT_TIME_MAXIMUM"
        ;;
    ui)
        result="${1:?結果の .xcresult の置き場を渡す}"
        rm -rf "$result"
        action="test-without-building"
        extra="-resultBundlePath $result"
        extra="$extra -test-timeouts-enabled YES"
        extra="$extra -default-test-execution-time-allowance $UI_TIME_ALLOWANCE"
        extra="$extra -maximum-test-execution-time-allowance $UI_TIME_MAXIMUM"
        only=""
        if [ -n "${2:-}" ] && [ -s "$2" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && only="$only $line"
            done < "$2"
        fi
        # 一覧が無ければ UI テストを全部
        only="${only:--only-testing:JourneyPhotoUITests}"
        # 名指しした回だけ流す UI テスト（`Tools/pick-ui-tests.py` の ONLY_WHEN_NAMED）は、一覧に名前が無ければ飛ばす。
        # 2026-10-22: 家具の脚の接写（約5分）が PR の検証・TestFlight の全部の回を延ばさないように
        for named in $(python3 Tools/pick-ui-tests.py --only-when-named); do
            case " $only " in
                *"/$named "*) ;;
                *) only="$only -skip-testing:JourneyPhotoUITests/$named" ;;
            esac
        done
        extra="$extra $only"
        ;;
    *)
        echo "使い方: xcode-test.sh build | unit <xcresult> | ui <xcresult> [<一覧>]" >&2
        exit 2
        ;;
esac

# **別の台で組んだ品で流す**（2026-10-31・#429）。`XCTESTRUN` に xctestrun の置き場を渡すと、
# プロジェクトではなくその品で流す（`Tools/test-products.py unpack` が置き場を出す）。組む段では使えない
if [ -n "${XCTESTRUN:-}" ]; then
    if [ "$mode" = "build" ]; then
        echo "XCTESTRUN は組んだ品で流すとき（unit・ui）だけ渡す" >&2
        exit 2
    fi
    # 組む設定（arm64 に絞る・プラグインの関所）は組む側の話なので、組んだ品で流すときは渡さない
    source_args="-xctestrun $XCTESTRUN"
else
    source_args="-project JourneyPhoto.xcodeproj -scheme JourneyPhoto"
    source_args="$source_args ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -skipPackagePluginValidation -skipMacroValidation"
fi

mkdir -p "$(dirname "$LOG")"
# `extra`・`source_args` は空白を含まない語の並び（置き場の名前・時間の上限・-only-testing:…）なので、わざと分けて渡す
# shellcheck disable=SC2086
xcodebuild \
    $source_args \
    -destination "platform=iOS Simulator,name=$DEVICE,arch=arm64" \
    $extra \
    "$action" 2>&1 | tee -a "$LOG" | tail -n 400 || {
        echo "::group::error: と落ちたテストの行だけ"
        grep -E "error:|Failing tests|\*\* TEST|' failed \(" "$LOG" | sort -u | head -200 || true
        echo "::endgroup::"
        exit 1
    }
