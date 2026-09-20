#!/usr/bin/env bash
#
# 手元でできるだけの検査を通す。**Mac なら最後にビルドまで行く。**
#
# Linux では:
#   - 画面を持たない層（Package.swift に並べたファイル）は**本当に**
#     ビルドしてテストまで走る
#   - SwiftUI / UIKit / ImageIO / Amplify に触るファイルは iOS SDK が要るので、
#     構文と参照の検査までしか見られない
# **緑でも「アプリのビルドが通る」とは言えない。**
#
#     bash Tools/verify.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Swift の構文 =="
if [ ! -d Tools/node_modules ]; then
    echo "-- tree-sitter を入れる（初回だけ）"
    (cd Tools && npm install --silent)
fi
node Tools/check-swift-syntax.js Sources Tests

echo
echo "== 参照（配られていない EnvironmentObject・型の重複） =="
node Tools/check-swift-refs.js Sources Tests

echo
echo "== 設定ファイル =="
python3 Tools/check-config.py

echo
echo "== 画面を持たない層のビルドとテスト（Swift があるときだけ） =="
if [ -x /opt/swift/bin/swift ]; then
    export PATH=/opt/swift/bin:$PATH
fi
if command -v swift >/dev/null 2>&1; then
    swift build
    swift test
else
    echo "   Swift がありません。入れるには: sudo bash Tools/install-swift-linux.sh"
    echo "   （SwiftUI に触るファイルは iOS SDK が要るので、どのみち Mac が必要）"
fi

echo
if command -v xcodebuild >/dev/null 2>&1; then
    echo "== Xcode プロジェクトの生成とビルド =="
    command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen がありません: brew install xcodegen"; exit 1; }
    xcodegen generate
    xcodebuild -scheme JourneyPhoto \
        -destination 'platform=iOS Simulator,name=iPhone 15' \
        -quiet build test
else
    echo "== 画面側のビルドは飛ばす =="
    echo "   Xcode が無い環境です。**SwiftUI に触るファイルは型検査していません。**"
    echo "   （画面を持たない層は上でビルドとテストまで通っています）"
    echo "   Mac で次を実行してください:"
    echo "     xcodegen generate && xcodebuild -scheme JourneyPhoto \\"
    echo "       -destination 'platform=iOS Simulator,name=iPhone 15' build test"
fi
