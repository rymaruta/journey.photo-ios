#!/usr/bin/env python3
"""共有カードの地図で塗る、日本の47都道府県の輪郭を作る。

Usage: python3 Tools/generate-japan-prefectures.py [ne_10m_admin_1_states_provinces.geojson]
Source: Natural Earth（パブリックドメイン）の ne_10m_admin_1_states_provinces。
アプリの国の輪郭（Tools/generate-country-outlines.py・admin-0）と同じ出どころ。
引数を省くと GitHub の natural-earth-vector から取る（約40MB）。外部の Python パッケージは使わない。

2026-11-04 判断（案A-3・owner 了承）: 日本の写真では、撮った都道府県を真鍮 75% で塗る。
- 県は ISO 3166-2 の番号（JP-01〜JP-47）で決め、名前は RegionList.prefectures と同じ並び
  （JIS の都道府県コード順）の日本語名にする。Natural Earth の name_ja の表記揺れに頼らない
- 0.01° の RDP で間引く（カードの地図は 290px 幅。日本の全体で 0.01° は 0.2px に満たない）
- 輪の作り方は国の輪郭と同じ `normalize_ring`（閉じた輪を RDP で潰さない）
"""
import importlib.util
import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson"
DEST = ROOT / "Sources/JourneyPhoto/Resources/japan-prefectures.json"
TOLERANCE = 0.01

# RegionList.prefectures と同じ並び（JIS X 0401 の都道府県コード順）
PREFECTURES = [
    "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
    "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
    "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
    "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
    "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
    "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
    "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県",
]


def country_tools():
    """国の輪郭の生成スクリプトの間引き方を使い回す（写しを作らない）。"""
    path = ROOT / "Tools/generate-country-outlines.py"
    spec = importlib.util.spec_from_file_location("generate_country_outlines", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load(argv):
    if len(argv) > 1:
        with open(argv[1], encoding="utf-8") as handle:
            return json.load(handle)
    # 名乗りはサイトの URL だけ（個人の情報を外へ送らない）
    request = urllib.request.Request(SOURCE, headers={"User-Agent": "https://journey-photo.com"})
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.load(response)


def main(argv):
    tools = country_tools()
    original = tools.simplify

    def simplify(points, tolerance=TOLERANCE):
        return original(points, tolerance)

    tools.simplify = simplify
    geojson = load(argv)
    if geojson.get("type") != "FeatureCollection":
        raise ValueError("Expected Natural Earth FeatureCollection")
    found = {}
    for feature in geojson["features"]:
        properties = feature.get("properties") or {}
        if properties.get("adm0_a3") != "JPN":
            continue
        code = properties.get("iso_3166_2") or ""
        if not code.startswith("JP-"):
            continue
        number = int(code[3:])
        if not 1 <= number <= len(PREFECTURES):
            raise ValueError(f"Unknown prefecture code: {code}")
        geometry = feature.get("geometry") or {}
        kind = geometry.get("type")
        coords = geometry.get("coordinates") or []
        polygons = [coords] if kind == "Polygon" else coords if kind == "MultiPolygon" else []
        rings = [normalized for polygon in polygons
                 for ring in polygon
                 for normalized in [tools.normalize_ring(ring)] if normalized]
        if rings:
            found[number] = {"n": PREFECTURES[number - 1], "r": rings}
    if sorted(found) != list(range(1, len(PREFECTURES) + 1)):
        missing = [PREFECTURES[i - 1] for i in range(1, 48) if i not in found]
        raise ValueError(f"Missing prefectures: {missing}")
    payload = json.dumps([found[i] for i in sorted(found)], ensure_ascii=False, separators=(",", ":"))
    DEST.write_text(payload + "\n", encoding="utf-8")
    print(f"Wrote {len(found)} prefectures to {DEST} ({len(payload.encode()):,} bytes)")


if __name__ == "__main__":
    main(sys.argv)
