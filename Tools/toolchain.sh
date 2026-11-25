#!/usr/bin/env bash
#
# 開発の道具の版（`Tools/toolchain.env`）を読む・確かめる・入れる（2026-11-25 判断）。
#
#     bash Tools/toolchain.sh swift              # 決めた Swift の版を出す（例 6.4.2）
#     bash Tools/toolchain.sh xcodegen           # 決めた XcodeGen の版を出す
#     bash Tools/toolchain.sh check-swift        # その場の `swift --version` が決めた版か。違えば警告（止めない）
#     bash Tools/toolchain.sh install-xcodegen   # Mac の CI: 決めた版の XcodeGen を正式の配布物から入れる（sha256 を確かめる）
#     bash Tools/toolchain.sh generate           # 上のとおり用意して `xcodegen generate`
#
# **macOS の /bin/bash は 3.2** なので、それで書く。
set -euo pipefail
cd "$(dirname "$0")/.."

# 値は `KEY=値` の行だけを読む（`source` しない。ほかの行が混ざっても動かさない）
value() {
    local key="$1" line
    line="$(grep -E "^${key}=" Tools/toolchain.env | tail -1)"
    [ -n "$line" ] || { echo "Tools/toolchain.env に ${key} がありません" >&2; exit 1; }
    echo "${line#*=}"
}

# 決めた版の XcodeGen を用意して、使う実行ファイルを XCODEGEN_BIN に入れる（Mac の CI 用）
install_xcodegen() {
    local want sum dest work got
    want="$(value JP_XCODEGEN)"
    sum="$(value JP_XCODEGEN_SHA256)"
    dest="${RUNNER_TEMP:-$HOME/.cache}/xcodegen-$want"
    if [ -x "$dest/xcodegen/bin/xcodegen" ]; then
        XCODEGEN_BIN="$dest/xcodegen/bin/xcodegen"
    elif command -v xcodegen >/dev/null 2>&1 && [ "$(xcodegen --version 2>/dev/null | sed 's/^Version: //')" = "$want" ]; then
        XCODEGEN_BIN="$(command -v xcodegen)"
    else
        # **brew は使わない。** brew は版を選べず、その日の版になる（run 45596610574 は 2.46.0。手元は 2.47.0 だった）
        work="$(mktemp -d)"
        curl -fsSL --retry 3 -o "$work/xcodegen.zip" \
            "https://github.com/yonaskolb/XcodeGen/releases/download/$want/xcodegen.zip"
        got="$(shasum -a 256 "$work/xcodegen.zip" 2>/dev/null || sha256sum "$work/xcodegen.zip")"
        got="${got%% *}"
        if [ "$got" != "$sum" ]; then
            rm -rf "$work"
            echo "::error::XcodeGen $want の配布物の sha256 が Tools/toolchain.env と違います（${got}）。使いません"
            exit 1
        fi
        rm -rf "$dest"
        mkdir -p "$dest"
        # 中は xcodegen/bin/xcodegen と xcodegen/share/xcodegen/SettingPresets（bin の隣の share を読むので、この形のまま置く）
        unzip -q "$work/xcodegen.zip" -d "$dest"
        rm -rf "$work"
        XCODEGEN_BIN="$dest/xcodegen/bin/xcodegen"
    fi
    # 後の段の `xcodegen` もこの版にする（GITHUB_PATH は次の段から効く）
    if [ -n "${GITHUB_PATH:-}" ]; then dirname "$XCODEGEN_BIN" >> "$GITHUB_PATH"; fi
    echo "XcodeGen: $("$XCODEGEN_BIN" --version)（${XCODEGEN_BIN}）"
}

case "${1:-}" in
    swift)
        value JP_SWIFT
        ;;
    xcodegen)
        value JP_XCODEGEN
        ;;
    check-swift)
        want="$(value JP_SWIFT)"
        # Mac では DEVELOPER_DIR の Xcode の Swift（xcrun）、Linux では PATH の swift
        if command -v xcrun >/dev/null 2>&1; then
            text="$(xcrun swift --version 2>&1 || true)"
        else
            text="$(swift --version 2>&1 || true)"
        fi
        echo "$text"
        # 「Apple Swift version 6.4.2 (swiftlang-…)」「Swift version 6.4.2 (swift-6.4.2-RELEASE)」の版の数字
        have="$(echo "$text" | grep -oE 'Swift version [0-9]+(\.[0-9]+)+' | head -1 | sed 's/Swift version //')"
        [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "Swift: ${have:-不明}（決めた版 ${want}・Tools/toolchain.env）" >> "$GITHUB_STEP_SUMMARY"
        # 6.4 と 6.4.0 は同じに数える
        norm() { echo "$1" | sed -E 's/^([0-9]+\.[0-9]+)$/\1.0/'; }
        if [ "$(norm "${have:-?}")" != "$(norm "$want")" ]; then
            echo "::warning::Swift の版が Tools/toolchain.env（${want}）と違います: ${have:-不明}。Xcode が上がったなら JP_SWIFT を上げてください（手元と PR の検証の Linux の段がずれます）"
        fi
        ;;
    install-xcodegen|generate)
        install_xcodegen
        if [ "$1" = "generate" ]; then
            shift
            "$XCODEGEN_BIN" generate "$@"
        fi
        ;;
    *)
        echo "使い方: toolchain.sh swift | xcodegen | check-swift | install-xcodegen | generate" >&2
        exit 2
        ;;
esac
