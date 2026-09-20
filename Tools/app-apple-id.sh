#!/usr/bin/env bash
#
# App Store Connect の「アプリの Apple ID」（数字）を出す。
#
# **人が画面から写してこない。** 以前は `codemagic.yaml` に
# `APP_APPLE_ID: 0000000000` と書いてあり、置き換えるまでビルドが始まらなかった
# ——owner の手を1回止める値を、CI が自分で引けるなら引く。
#
#     bash Tools/app-apple-id.sh com.journeyphoto.JourneyPhoto
#
# 引けなければ**何も出さずに 1 を返す**（呼び出し側が理由を出す）。
# App Store Connect の API キーは Codemagic が環境変数で渡している。
set -uo pipefail

BUNDLE_ID="${1:?Bundle ID を渡してください}"

command -v app-store-connect >/dev/null 2>&1 || exit 1

# **完全一致だけ**（`--strict-match-identifier`）。部分一致だと
# `com.journeyphoto.JourneyPhoto.staging` を拾って、staging の枠に
# 本番のビルドを上げる事故になる
JSON="$(app-store-connect apps list \
    --bundle-id-identifier "$BUNDLE_ID" \
    --strict-match-identifier \
    --json 2>/dev/null)" || exit 1

printf '%s' "$JSON" | python3 Tools/pick-app-id.py
