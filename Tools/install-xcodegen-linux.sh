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

git clone --depth 1 https://github.com/yonaskolb/XcodeGen "$WORK/XcodeGen"
(cd "$WORK/XcodeGen" && swift build -c release)
mkdir -p "$DEST"
cp "$WORK/XcodeGen/.build/release/xcodegen" "$DEST/"
echo "入れました: $DEST/xcodegen"
