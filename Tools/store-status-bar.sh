#!/usr/bin/env bash
#
# App Store 用の絵を撮るシミュレータの状態のバーを、Apple の決まった形にする（2026-11-23・札 #604）。
# owner「ちゃんと実機通りのスクショかも見ないといけない」: 時刻 9:41、Wi-Fi と電波が満タン、電池が満タン（充電済み）。
#
#     bash Tools/store-status-bar.sh "iPhone 17 Pro Max"
#
# そのシミュレータを起動して（起動済みならそのまま）、`xcrun simctl status_bar override` をかける。
# 起動のし直し・消去ではかけ直しが要るので、UI テストの直前に呼ぶ（`Tools/xcode-test.sh` の `STORE_STATUS_BAR=1`）。
# かけられなければ終了コード 1（実機と違う状態のバーで撮らない）
set -euo pipefail

name="${1:?シミュレータの名前を渡す}"
udid="$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin).get("devices", {}).values():
    for d in devices:
        if d.get("name") == name and d.get("isAvailable"):
            print(d["udid"]); sys.exit(0)
sys.exit(1)
' "$name")" || { echo "::error::シミュレータ「${name}」がありません"; exit 1; }

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl status_bar "$udid" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100 \
    || { echo "::error::状態のバーを決まった形にできませんでした（${name}）"; exit 1; }
echo "状態のバーを 9:41、満タンにしました: $name"
