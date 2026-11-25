#!/usr/bin/env bash
#
# XcodeGen を Linux で使えるようにする。
#
# **`project.yml` が壊れていないことを、Mac を待たずに確かめる**ための道具。
# XcodeGen は素の Swift パッケージなので Linux でもビルドできる
# （生成した `.xcodeproj` を開けるのは Mac だけだが、**生成が通るか**は
# ここで分かる——設定の書き間違いはここで落ちる）。
set -euo pipefail

DEST="${DEST:-/opt/xcodegen}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v swift >/dev/null 2>&1 || { echo "Swift がありません: sudo bash Tools/install-swift-linux.sh"; exit 1; }

# 版は Tools/toolchain.env の JP_XCODEGEN（Mac の CI と同じ版・2026-11-25 判断）。2.48.0 から作るのに Swift 6.1 以上が要る
VERSION="$(bash "$(dirname "$0")/toolchain.sh" xcodegen)"
git clone --depth 1 --branch "$VERSION" https://github.com/yonaskolb/XcodeGen "$WORK/XcodeGen"
# **Swift の実行時の部品は、作った Swift の置き場（/opt/swift）から読む。** Linux の Swift は版が違うと部品が合わないので、
# Swift を入れ替えたら XcodeGen も作り直す（`install-swift-linux.sh` が最後にこれを呼ぶ）。
# 2026-11-25: 6.0.3 で作った XcodeGen が、6.4.2 に入れ替えたあと `libswiftCore.so` を読めず /verify が止まった。
# 部品を中に入れる作り（--static-swift-stdlib）は、6.4.2 では生成の途中で「Property list invalid」で落ちたので使わない
(cd "$WORK/XcodeGen" && swift build -c release --product xcodegen)
mkdir -p "$DEST"
cp "$WORK/XcodeGen/.build/release/xcodegen" "$DEST/"
"$DEST/xcodegen" --version
echo "入れました: $DEST/xcodegen"
