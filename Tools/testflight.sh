#!/usr/bin/env bash
#
# Archive して App Store Connect に上げる（TestFlight へ）。
#
# **初回は Xcode の画面からやること**（`docs/TESTFLIGHT.md`）。証明書と
# プロファイルの作成で確認を求められる場面があり、画面の方が分かりやすい。
# このスクリプトは2回目以降を楽にするためのもの。
#
#     export APPLE_ID="あなたの@apple.id"
#     export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # App 用パスワード
#     bash Tools/testflight.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${APPLE_ID:?APPLE_ID を設定してください（docs/TESTFLIGHT.md）}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD を設定してください（App 用パスワード）}"

command -v xcodebuild >/dev/null 2>&1 || { echo "Xcode がありません"; exit 1; }
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen がありません: brew install xcodegen"; exit 1; }

BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/JourneyPhoto.xcarchive"

echo "== 上げる前に手元の検査を通す"
bash Tools/verify.sh

echo
echo "== ビルド番号を上げる"
# **同じ番号は受け付けられない。** 上げ忘れは上げ切ったあとに分かるので、
# 訊かずに上げる（上げすぎて困ることはない）
bash Tools/bump-build.sh

xcodegen generate

echo
echo "== Archive"
rm -rf "$ARCHIVE"
xcodebuild -scheme JourneyPhoto -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    archive

echo
echo "== 書き出し"
cat > "$BUILD_DIR/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <!-- シンボルを送る。落ちたときの記録が読める形になる -->
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$BUILD_DIR/export" \
    -allowProvisioningUpdates

IPA=$(find "$BUILD_DIR/export" -name "*.ipa" | head -1)
[ -n "$IPA" ] || { echo "ipa が作られませんでした"; exit 1; }

echo
echo "== 上げる（$IPA）"
xcrun altool --upload-app -f "$IPA" -t ios \
    -u "$APPLE_ID" -p "$APPLE_APP_PASSWORD"

cat <<'NEXT'

上げました。ここから先は App Store Connect の画面:

  1. TestFlight タブ → ビルドが「処理中」→ 10〜30分待つ
  2. 処理が終わったら 内部テスト → グループに自分を追加 → ビルドを選ぶ
  3. iPhone の TestFlight アプリに招待が届く

  ⚠️ TestFlight のビルドは **本番** に繋がる。試しの投稿は
     「すぐ公開する」をオフにするか、あとで消すこと。

  詳しい手順: docs/TESTFLIGHT.md
NEXT
