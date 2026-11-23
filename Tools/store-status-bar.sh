#!/usr/bin/env bash
#
# App Store 用の絵を撮るシミュレータの状態のバーを、Apple の決まった形にする（2026-11-23・札 #604）。
# owner「ちゃんと実機通りのスクショかも見ないといけない」: 時刻 9:41、Wi-Fi と電波が満タン、電池が満タン（充電済み）。
#
#     bash Tools/store-status-bar.sh "iPhone 17 Pro Max"                 # 起動して、かける（かけられなければ 1）
#     bash Tools/store-status-bar.sh "iPhone 17 Pro Max" --keep <pid>    # <pid> が動いている間、外れたらかけ直す（裏で動かす）
#     bash Tools/store-status-bar.sh "iPhone 17 Pro Max" --check         # 今かかっているか（`status_bar list` を出す・無ければ 1）
#
# 起動のし直し・消去ではかけ直しが要るので、UI テストの直前に呼ぶ（`Tools/xcode-test.sh` の `STORE_STATUS_BAR=1`）。
# かけられなければ終了コード 1（実機と違う状態のバーで撮らない）
#
# 🔴 2026-11-23 判断（Mac run 1741）: **かけたのに、撮った絵は実際の時刻（10:11 など）・電波は「••••」の空だった。**
# ログでは大型・中型の両方の段で「9:41、満タンにしました」が出ていて、テストは同じ名前の端末で流れていた
# （並列の写し「Clone 1 of …」は出ていない・`xcodebuild` は同じ UDID の端末に「lockdown に 120秒つながらない」と言ってから流れた）。
# 時刻も電波もどちらも素の値＝かけた形がまるごと消えていた。かけてからテストが始まるまで15分あり（パッケージの解決 5分・
# 端末への接続の待ち 2分・アプリを入れる）、その間に端末の側（SpringBoard の立て直しなど）でかけた形が消えたと見る。
# 一度かけるだけでは守れないので、**テストが走っている間ずっと見張り、外れていたらかけ直す**（`--keep`）。
# 外れていた回数は `measured [statusBar]` の行で残す（次に外れたら、いつ外れたかが数で分かる）。
# 名前が同じ端末の写し（並列の「Clone N of <名前>」）も同じ形にする（`-parallel-testing-enabled NO` で写しは作らないが、念のため）
set -euo pipefail

name="${1:?シミュレータの名前を渡す}"
mode="${2:-apply}"

# その名前の端末（使えるもの）。--keep・--check は、起動している写し（Clone N of <名前>）も
udids() {
    local which="$1"
    xcrun simctl list devices -j | python3 -I -c '
import json, sys
name, which = sys.argv[1], sys.argv[2]
for devices in json.load(sys.stdin).get("devices", {}).values():
    for d in devices:
        if not d.get("isAvailable"):
            continue
        clone = d.get("name", "").startswith("Clone ") and d.get("name", "").endswith(" of " + name)
        # 2026-11-23（Mac run 1742）: 同じ名前の端末が別の iOS の版にもあり、止まっている方まで --check が見て
        # 「Shutdown」で赤になった（撮った絵は 9:41 だった）。起動している端末だけを見るときは、名前が同じでも Booted だけ
        if which == "booted":
            if (d.get("name") == name or clone) and d.get("state") == "Booted":
                print(d["udid"])
        elif d.get("name") == name:
            print(d["udid"])
' "$name" "$which"
}

override() {
    # 電波は満タン、運用者の名前は出さない（`''`）。電池は満タンで、充電中の稲妻を出さない（`discharging`。run 1742 の絵で緑の稲妻が出た・2026-11-23）。位置の矢印は状態のバーの上書きでは消せない（アプリが位置を使わないこと・
    # 見本の表示では `CurrentLocation` が端末の位置を読まない）
    xcrun simctl status_bar "$1" override \
        --time "9:41" \
        --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --operatorName '' \
        --batteryState discharging --batteryLevel 100
}

# かかっているか（`status_bar list` に 9:41 が出る）
applied() { xcrun simctl status_bar "$1" list 2>/dev/null | grep -q "9:41"; }

case "$mode" in
    apply)
        udid="$(udids available | head -1)"
        [ -n "$udid" ] || { echo "::error::シミュレータ「${name}」がありません"; exit 1; }
        xcrun simctl boot "$udid" 2>/dev/null || true
        xcrun simctl bootstatus "$udid" -b > /dev/null
        override "$udid" || { echo "::error::状態のバーを決まった形にできませんでした（${name}）"; exit 1; }
        applied "$udid" || { echo "::error::状態のバーをかけたのに、かかっていません（${name}）"; exit 1; }
        echo "状態のバーを 9:41、満タンにしました: $name"
        ;;
    --keep)
        pid="${3:?見張る間の処理の pid を渡す}"
        started=$(date +%s); fixed=0
        while kill -0 "$pid" 2>/dev/null; do
            for udid in $(udids booted); do
                if ! applied "$udid"; then
                    if override "$udid" > /dev/null 2>&1; then
                        fixed=$((fixed + 1))
                        echo "measured [statusBar] 外れていたのでかけ直した ${fixed}回目 $(( $(date +%s) - started ))s"
                    fi
                fi
            done
            sleep 2
        done
        echo "measured [statusBar] 見張りを終えた かけ直し ${fixed}回"
        ;;
    --check)
        status=0; seen=0
        for udid in $(udids booted); do
            seen=$((seen + 1))
            echo "::group::状態のバーの上書き（${name}）"
            xcrun simctl status_bar "$udid" list || true
            echo "::endgroup::"
            applied "$udid" || status=1
        done
        [ "$seen" -gt 0 ] || status=1
        if [ "$status" -ne 0 ]; then
            echo "::error::テストのあとに状態のバーの上書きが残っていません（${name}）。撮った絵が 9:41 でない見込み"
        else
            echo "measured [statusBar] テストのあとも 9:41 のまま: $name"
        fi
        exit "$status"
        ;;
    *)
        echo "使い方: store-status-bar.sh <名前> [--keep <pid> | --check]" >&2
        exit 2
        ;;
esac
