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
        ;;
    ui)
        result="${1:?結果の .xcresult の置き場を渡す}"
        rm -rf "$result"
        action="test-without-building"
        extra="-resultBundlePath $result"
        only=""
        if [ -n "${2:-}" ] && [ -s "$2" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && only="$only $line"
            done < "$2"
        fi
        # 一覧が無ければ UI テストを全部
        extra="$extra ${only:--only-testing:JourneyPhotoUITests}"
        ;;
    *)
        echo "使い方: xcode-test.sh build | unit <xcresult> | ui <xcresult> [<一覧>]" >&2
        exit 2
        ;;
esac

mkdir -p "$(dirname "$LOG")"
# `extra` は空白を含まない語の並び（置き場の名前と -only-testing:…）なので、わざと分けて渡す
# shellcheck disable=SC2086
xcodebuild \
    -project JourneyPhoto.xcodeproj \
    -scheme JourneyPhoto \
    -destination "platform=iOS Simulator,name=$DEVICE,arch=arm64" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    $extra \
    "$action" 2>&1 | tee -a "$LOG" | tail -n 400 || {
        echo "::group::error: と落ちたテストの行だけ"
        grep -E "error:|Failing tests|\*\* TEST|' failed \(" "$LOG" | sort -u | head -200 || true
        echo "::endgroup::"
        exit 1
    }
