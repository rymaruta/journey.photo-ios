#!/usr/bin/env python3
"""共有カードの地図のピンに使う、市区町村の役所・役場の位置の表を作る（2026-11-19）。

出典と決まり（2026-11-19 にそれぞれの頁で確かめた）:
- 位置: 「国土数値情報（市町村役場等及び公的集会施設データ）」（国土交通省）P05 令和4年（2022）
  https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-P05-2022.html （使用許諾条件: オープンデータ CC BY 4.0）
  の P05-22_GML.zip を加工して作成。施設分類 1（本庁）の点だけを使う
- 名前と県: 「全国地方公共団体コード」（総務省）令和6年1月1日現在 https://www.soumu.go.jp/denshijiti/code.html
  （000925835.xlsx・総務省ホームページの「公共データ利用規約（第1.0版）」）を加工して作成
- P05 の行政区域コード（5桁）で総務省の名前を引き、施設の名前（「金沢市役所」）と食い違う行は落とす
  （P05 には名前とコードの誤り・村外にある役場（十島村・竹富町など）がある）。落ちた市区町村は県の代表点にとどまる

使い方: python3 Tools/generate-municipal-offices.py <P05-22_GML.zip を展開し、中の県ごとの zip も展開した所> <000925835.xlsx> \
          Sources/JourneyPhoto/Resources/japan-municipal-offices.json
外部のパッケージ: openpyxl（総務省の xlsx を読む）
出力: [[県の番号(JIS 1-47・RegionList.prefectures の並び), 名前, 緯度, 経度], ...]（緯度経度は小数3桁・約100m）
"""
import glob
import json
import re
import sys
from collections import defaultdict

import openpyxl

src, xlsx, out = sys.argv[1], sys.argv[2], sys.argv[3]

names = {}       # 5桁 → (県, 名前)
cities = defaultdict(dict)  # 県 → 政令市の名前 → 5桁
wb = openpyxl.load_workbook(xlsx, read_only=True)
for ws in wb.worksheets:
    for r in list(ws.iter_rows(values_only=True))[1:]:
        if r[0] and r[2]:
            code = str(r[0])[:5]
            names[code] = (r[1], r[2])
            if code[2:] in ('100', '130', '140', '150') or (ws.title.endswith('政令指定都市') and r[2].endswith('市')):
                cities[r[1]][r[2]] = code

prefs = []
for code, (pref, _) in sorted(names.items()):
    if pref not in prefs:
        prefs.append(pref)
assert len(prefs) == 47, len(prefs)

rows = {}
dropped = []
for path in sorted(glob.glob(src + '/P05-22_*_GML/P05-22_*.geojson')):
    for f in json.load(open(path, encoding='utf-8'))['features']:
        p = f['properties']
        if p['P05_002'] != '1':  # 1 = 本庁
            continue
        code = p['P05_001']
        m = re.fullmatch(r'(.+?[市区町村])(?:役所|役場)(?:本庁舎|本庁|庁舎)?', p['P05_003'].strip())
        lng, lat = f['geometry']['coordinates']
        known = names.get(code)
        if m and not known:
            # 区の作り替えで今は無いコード（浜松市・2024）。政令市の市役所だけ、県をコードの頭2桁で引いて拾う
            pref = next((v[0] for k, v in names.items() if k[:2] == code[:2]), None)
            if pref and m.group(1) in cities.get(pref, {}):
                known = (pref, m.group(1))
        if not m or not known:
            dropped.append((code, p['P05_003'], known))
            continue
        pref, official = known
        fname = m.group(1)
        if fname.replace('ヶ', 'ケ') == official.replace('ヶ', 'ケ') or (official.endswith(fname) and official[:-len(fname)].endswith('市')):
            name = official
        elif fname in cities.get(pref, {}):
            name = fname  # 政令市の市役所（区のコードで載っている）
        else:
            dropped.append((code, p['P05_003'], known))
            continue
        key = (pref, name)
        if key in rows:
            dropped.append((code, p['P05_003'], 'dup'))
            continue
        rows[key] = (prefs.index(pref) + 1, name, round(lat, 3), round(lng, 3), code)

for d in dropped:
    print('dropped', d, file=sys.stderr)
missing = sorted(set(v[1] for v in names.values() if (v[0], v[1]) not in rows and not v[1].endswith('郡')))
print('missing', len(missing), missing, file=sys.stderr)

table = sorted(rows.values(), key=lambda r: (r[4], r[1]))
with open(out, 'w', encoding='utf-8') as fp:
    fp.write('[\n' + ',\n'.join(json.dumps([r[0], r[1], r[2], r[3]], ensure_ascii=False, separators=(',', ':'))
                                  for r in table) + '\n]\n')
print(len(table), 'rows', file=sys.stderr)
