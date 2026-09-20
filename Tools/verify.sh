#!/usr/bin/env bash
#
# 手元でできるだけの検査を通す。**Mac なら最後にビルドまで行く。**
#
# Linux では **全ファイル**をビルドしてテストまで走る。
# SwiftUI・UIKit・ImageIO・Amplify は `Shims/` の模型に向けてコンパイルする。
#
# **緑でも「Xcode のビルドが通る」とは言えない。** 模型の修飾子は素通しなので、
# SwiftUI 側の制約（ViewBuilder の枝の数・`some View` の同一性・修飾子の順序・
# 実行時の挙動）は見ていない。見えているのは**自分たちのコードの誤り**——
# 綴り違い・無いプロパティ・引数ラベルの不一致・型の取り違え・分離の誤り。
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
echo "== Web 版との突き合わせ =="
python3 Tools/check-api-parity.py "${PHOTO_GALLERY:-../photo-gallery}"

echo
echo "== 設定ファイル =="
python3 Tools/check-config.py

echo
echo "== ビルドとテスト（模型に向けて・Swift があるときだけ） =="
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
    echo "== 実機向けのビルドは飛ばす =="
    echo "   Xcode が無い環境です。**本物の SwiftUI では確かめていません。**"
    echo "   （上のビルドは Shims/ の模型に向けたもの）"
    echo "   Mac で次を実行してください:"
    echo "     xcodegen generate && xcodebuild -scheme JourneyPhoto \\"
    echo "       -destination 'platform=iOS Simulator,name=iPhone 15' build test"
fi
