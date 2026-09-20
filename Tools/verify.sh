#!/usr/bin/env bash
#
# 手元でできるだけの検査を通す。**Mac なら最後にビルドまで行く。**
#
# Mac 以外（この作業環境のような Linux）では Swift ツールチェーンが無いので、
# 構文と設定だけを見る。**これが緑でも「ビルドが通る」とは言えない。**
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
if command -v xcodebuild >/dev/null 2>&1; then
    echo "== Xcode プロジェクトの生成とビルド =="
    command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen がありません: brew install xcodegen"; exit 1; }
    xcodegen generate
    xcodebuild -scheme JourneyPhoto \
        -destination 'platform=iOS Simulator,name=iPhone 15' \
        -quiet build test
else
    echo "== ビルドは飛ばす =="
    echo "   Xcode が無い環境です。**型検査もテストも行っていません。**"
    echo "   Mac で次を実行してください:"
    echo "     xcodegen generate && xcodebuild -scheme JourneyPhoto \\"
    echo "       -destination 'platform=iOS Simulator,name=iPhone 15' build test"
fi
