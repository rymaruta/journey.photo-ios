#!/usr/bin/env bash
#
# Mac でやる工程を1本にまとめたもの。**ここから先は Apple のハードウェアと
# owner の開発者アカウントが要る**（Linux 側では越えられない）。
#
#     bash Tools/mac-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen がありません: brew install xcodegen"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "Xcode がありません"; exit 1; }

DEVICE="${DEVICE:-iPhone 15}"

echo "== プロジェクトを作る"
xcodegen generate

echo
echo "== staging（Debug）でビルドとテスト"
xcodebuild -scheme JourneyPhoto \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -quiet build test

echo
echo "== 本番（Release）でビルドだけ確かめる"
xcodebuild -scheme JourneyPhoto -configuration Release \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -quiet build

cat <<'NEXT'

ここまで緑なら、残りは Xcode の画面でやる工程:

  1. 実機で一巡する
     - カメラから投稿（シミュレータにカメラが無いのでここが初回）
     - ライブラリから投稿 → 撮影地が勝手に入らないこと
     - 通報・ブロック・解除 → アカウント削除
     - 機内モードで起動 → 前回の一覧と、一度見た写真が出ること

  2. スクリーンショット（6.7インチ・最低3枚）
     ギャラリー / 写真の詳細 / 投稿 / 地図 / 年表
     **人の顔と他人の投稿は入れない**

  3. Product → Archive → Distribute App → App Store Connect

  4. App Store Connect で docs/APP_REVIEW.md の内容を写す
     - App Review Information の Notes（あの文面をそのまま）
     - Demo Account（本番に作る。写真を1枚は投稿しておく）
     - App のプライバシー（PrivacyInfo.xcprivacy と同じ答えにする）
     - 年齢制限の質問票（ユーザー生成コンテンツ＝はい）

  詳しい手順: docs/RELEASE.md
NEXT
