#!/usr/bin/env python3
"""その場にある いちばん新しい iPhone シミュレータの名前を出す。

**機種名を CI に直書きしない。** `xcode: latest` は Xcode が上がるたびに
入っているシミュレータが入れ替わる。消えた機種を指すと
「そんな行き先は無い」でテストの段が落ちる——原因が分かりにくく、
しかも直すたびにまた古くなる。
"""
import json
import re
import subprocess
import sys


def available_iphones(payload):
    return [device["name"]
            for devices in payload.get("devices", {}).values()
            for device in devices
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone")]


def newest(names):
    """「iPhone 17 Pro Max」> 「iPhone 17 Pro」> 「iPhone 17」> 「iPhone 16」。

    数字が読めない名前（iPhone SE など）は 0 扱いで後ろに回す。
    """
    def key(name):
        found = re.search(r"\d+", name)
        return (int(found.group()) if found else 0, "Pro" in name, len(name))
    return sorted(names, key=key)[-1] if names else ""


def main():
    raw = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                         capture_output=True, text=True, check=True).stdout
    name = newest(available_iphones(json.loads(raw)))
    if not name:
        print("使える iPhone シミュレータが見つかりませんでした。", file=sys.stderr)
        return 1
    print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
