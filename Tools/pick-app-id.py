#!/usr/bin/env python3
"""App Store Connect の応答から「アプリの Apple ID」を1つだけ取り出す。

標準入力に `app-store-connect apps list --json` の出力を渡す。
取り出せなければ**何も出さずに 1 を返す**（呼び出し側が理由を出す）。
"""
import json
import sys


def app_id(payload):
    """**1件のときだけ返す。**

    2件以上で当てずっぽうに選ぶと、`…JourneyPhoto` と `…JourneyPhoto.staging`
    のような並びで**staging の枠に本番のビルドを上げる**事故になる。
    """
    if isinstance(payload, dict):
        payload = payload.get("data", [])
    if not isinstance(payload, list):
        return None
    ids = [str(app["id"]) for app in payload
           if isinstance(app, dict) and app.get("id")]
    return ids[0] if len(ids) == 1 else None


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 1
    found = app_id(payload)
    if not found:
        return 1
    print(found)
    return 0


if __name__ == "__main__":
    sys.exit(main())
