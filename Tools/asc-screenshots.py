#!/usr/bin/env python3
"""App Store 用の画面写真を、App Store Connect の「提出の準備中」の版に入れ替える（2026-11-23・札 #604）。

    python3 -I Tools/asc-screenshots.py --dir <store.tar をほどいた所> --version 1.1.119 [--apply]

呼ぶのは `Tools/asc-screenshots.sh`（`ios-testflight.yml` の storeShots の回で `ascVersion` を渡したとき・作った絵をその場から上げる）。owner は iPhone しか無く、
App Store Connect の Web は iPhone では画面写真の追加・削除ができないので、CI から入れ替える（owner 2026-11-23「仕組み作ろう」）。

**既定は下見（dry-run）。** 何を消して何を上げるかを出すだけで、何も変えない。`--apply` のときだけ変える。

🔴 守ること
  - 相手にするのは、指定の版で **状態が PREPARE_FOR_SUBMISSION のものだけ**。ほかの状態（配信中・審査中・却下など）なら
    何もせずに赤で止まる（配信中の版には触らない）。変える直前にも状態を読み直す
  - 触るのは iPhone の画面写真の組だけ。名前・説明などのメタデータ、App プレビュー、iPad の組、審査への提出には触らない
  - 画像の中身・アップロードの URL・鍵はログに出さない（ファイル名・枚数・状態だけ）
  - 入れ替えるのは `--locales` で渡した言語だけ（既定 ja）。ほかの言語は消さない・作らない。版に無い言語は作らずに止まる
  - 組ごとに全部 COMPLETE でなければその場で止める。古い組（6.5 以前）を消すのは、その言語の大型と中型がそろってから。
    止まっても最後に今の組の中身を必ず出す。POST・DELETE は送り直さない（届いたか分からなければ読み直して確かめる）

組の振り分け（ScreenshotDisplayType。Apple の enum には寸法が書かれていないので、Apple の「Screenshot specifications」と
fastlane の `deliver/lib/deliver/app_screenshot.rb` の DEVICE_RESOLUTIONS で突き合わせた・2026-11-23）:
  - APP_IPHONE_67 … 6.9インチ（と 6.7）。1320×2868・1290×2796・1260×2736。ここに大型の絵
  - APP_IPHONE_61 … 6.3インチ（と 6.1 の一部）＝ Dynamic Island 搭載の中型。1206×2622・1179×2556。
    ここに中型の絵
  （2026-11-23: 撮る機種で寸法が変わるので、フォルダの名前（直下・`medium/`・`medium-1206x2622/`）には頼らず、
   受け付ける寸法の一覧 SIZES だけで振り分ける）
  - APP_IPHONE_65・58・55・47・40・35 … 6.5インチ（Face ID 大型）以前の古い iPhone。中身を全部消す
    （6.9インチの組があれば、App Store Connect が縮めて使う）
  どの組に入れるかは、フォルダの名前ではなく **PNG の寸法** で決める（寸法の合わない絵は上げずに止まる）

使う口（Apple「Uploading assets to App Store Connect」と各資源の文書・2026-11-23）:
  - GET    /v1/apps?filter[bundleId]=…
  - GET    /v1/apps/{id}/appStoreVersions?filter[versionString]=…&filter[platform]=IOS   （状態は appVersionState・appStoreState）
  - GET    /v1/appStoreVersions/{id}/appStoreVersionLocalizations                        （その版の言語。入れ替えるのは --locales で渡した言語だけ）
  - GET    /v1/appStoreVersionLocalizations/{id}/appScreenshotSets
  - GET    /v1/appScreenshotSets/{id}/appScreenshots
  - POST   /v1/appScreenshotSets                    （組が無ければ作る）
  - DELETE /v1/appScreenshots/{id}                  （今の絵を消す）
  - POST   /v1/appScreenshots → 分割の PUT → PATCH /v1/appScreenshots/{id}（uploaded・MD5 の sourceFileChecksum）
    → GET で assetDeliveryState が COMPLETE になるまで待つ
  - PATCH  /v1/appScreenshotSets/{id}/relationships/appScreenshots   （01 からの順に並べ直す）
  Apple の文書には「appScreenshots などは非推奨。App Asset Library と placements に移る」とある（2026-11-23 時点。口はまだ在る）。
  消えたら、この台本を新しい口に移す

2026-11-23 判断: fastlane（deliver）でなく、この小さな台本にした。理由:
  - 下見（何を消して何を上げるか）を出せる。deliver には下見が無く、`overwrite_screenshots` は版の状態を問わず
    選んだ言語の組を全部消す（PREPARE_FOR_SUBMISSION だけに絞る止め方を外から足せない）
  - 古い組（6.5 など）だけを空にし、iPad の組には触らない、を言葉どおりに書ける
  - 鍵（JWT）と口の引き方は `Tools/testflight-crashes.py` の `Client` を使い回す（写しを作らない）。pip で何も入れない
  - 振り分け・状態の判定・下見の表示を Linux の単体テスト（`Tools/test_asc_screenshots.py`）で守れる
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import pathlib
import re
import struct
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

_spec = importlib.util.spec_from_file_location("tfc", pathlib.Path(__file__).with_name("testflight-crashes.py"))
tfc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tfc)
ApiError = tfc.ApiError
API = tfc.API

LARGE = "APP_IPHONE_67"
MEDIUM = "APP_IPHONE_61"
# 受け付ける寸法（縦向き）→ 組。大型3種と中型2種（Apple の Screenshot specifications・fastlane の DEVICE_RESOLUTIONS）
SIZES = {(1320, 2868): LARGE, (1290, 2796): LARGE, (1260, 2736): LARGE,
         (1206, 2622): MEDIUM, (1179, 2556): MEDIUM}
TARGETS = (LARGE, MEDIUM)
OLD_IPHONE = ("APP_IPHONE_65", "APP_IPHONE_58", "APP_IPHONE_55", "APP_IPHONE_47", "APP_IPHONE_40", "APP_IPHONE_35")
LABEL = {LARGE: "6.9インチ（大型）", MEDIUM: "6.3インチ（中型）", "APP_IPHONE_65": "6.5インチ（Face ID 大型）",
         "APP_IPHONE_58": "5.8インチ", "APP_IPHONE_55": "5.5インチ", "APP_IPHONE_47": "4.7インチ",
         "APP_IPHONE_40": "4インチ", "APP_IPHONE_35": "3.5インチ"}
EDITABLE = "PREPARE_FOR_SUBMISSION"
MAX_PER_SET = 10  # Apple の決まり: 1つの組に10枚まで
SHOT_NAME = re.compile(r"^\d{2}-.+\.png$")  # 01-ホーム.png …（審査用の review-….png は上げない）


class Stop(Exception):
    """赤で止める（理由はログに出してよい文だけ）。"""


# ---- 手元の絵 ------------------------------------------------------------------------------

def png_size(path: str) -> tuple[int, int]:
    with open(path, "rb") as f:
        head = f.read(24)
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise Stop(f"PNG ではありません: {os.path.basename(path)}")
    return struct.unpack(">II", head[16:24])


def collect(folder: str) -> dict[str, list[str]]:
    """{display type: [絵の道（名前の順）]}。直下と1段下のフォルダの `NN-….png` を寸法で振り分ける。"""
    found: dict[str, list[str]] = {t: [] for t in TARGETS}
    bad = []
    for dirpath, dirnames, filenames in os.walk(folder):
        if os.path.relpath(dirpath, folder) != ".":
            dirnames[:] = []  # 見るのは直下と1段下（`medium/` など。名前は見ない）だけ
        for name in filenames:
            if not SHOT_NAME.match(unicodedata.normalize("NFC", name)):
                continue
            path = os.path.join(dirpath, name)
            size = png_size(path)
            kind = SIZES.get(size)
            if kind is None:
                bad.append(f"{os.path.relpath(path, folder)}（{size[0]}×{size[1]}）")
            else:
                found[kind].append(path)
    if bad:
        raise Stop("寸法が App Store の組に合わない絵があります: " + "、".join(sorted(bad)))
    for kind in TARGETS:
        found[kind].sort(key=lambda p: unicodedata.normalize("NFC", os.path.basename(p)))
        if not found[kind]:
            raise Stop(f"{LABEL[kind]}の絵がありません（store.tar の中身を確かめる）")
        if len(found[kind]) > MAX_PER_SET:
            raise Stop(f"{LABEL[kind]}の絵が {len(found[kind])} 枚あります（1つの組は {MAX_PER_SET} 枚まで）")
        names = [os.path.basename(p) for p in found[kind]]
        if len(set(names)) != len(names):
            raise Stop(f"{LABEL[kind]}に同じ名前の絵があります")
    return found


# ---- 版の状態 ------------------------------------------------------------------------------

def version_states(attrs: dict) -> list[str]:
    """版の状態。新しい欄 appVersionState と古い欄 appStoreState の、在る方を全部。"""
    return [attrs[k] for k in ("appVersionState", "appStoreState") if attrs.get(k)]


def check_editable(version: dict) -> None:
    attrs = version.get("attributes") or {}
    states = version_states(attrs)
    if not states:
        raise Stop(f"版 {attrs.get('versionString', '?')} の状態が読めません（触らずに止めます）")
    if any(s != EDITABLE for s in states):
        raise Stop(f"版 {attrs.get('versionString', '?')} の状態が {'・'.join(sorted(set(states)))} です。"
                   f"{EDITABLE}（提出の準備中）の版だけを相手にします（配信中・審査中の版には触りません）")


# ---- 計画 ----------------------------------------------------------------------------------

LOCALE = re.compile(r"^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$")


def parse_locales(text: str) -> list[str]:
    """「ja,en-US」→ ["ja", "en-US"]。渡した言語だけを入れ替える（2026-11-23 判断: 版の全部の言語には触らない）。"""
    out = []
    for part in (text or "").split(","):
        part = part.strip()
        if not part:
            continue
        if not LOCALE.match(part):
            raise Stop(f"言語の形が変です: {tfc.clean(part, 20)}（例 ja,en-US）")
        if part not in out:
            out.append(part)
    if not out:
        raise Stop("入れ替える言語がありません（例 ja）")
    return out


def pick_locales(locales: list[dict], wanted: list[str]) -> list[dict]:
    """版の言語のうち、渡した言語だけ。版に無い言語は作らずに止める。"""
    have = {loc["locale"]: loc for loc in locales}
    missing = [w for w in wanted if w not in have]
    if missing:
        raise Stop(f"この版に言語 {', '.join(missing)} がありません（言語は App Store Connect で足す。ここでは作らない）。"
                   f"版にある言語: {', '.join(sorted(have))}")
    return [have[w] for w in wanted]


def make_plan(locales: list[dict], files: dict[str, list[str]]) -> list[dict]:
    """locales: [{"locale", "id", "sets": {display type: {"id", "shots": [{"id", "fileName"}]}}}]（入れ替える言語だけ）
    → 言語ごとに [{"type", "set_id", "delete": [shot], "upload": [道], "upload_first"}]（iPhone の組だけ。iPad などは入れない）。
    upload_first: 今の絵と新しい絵を足して10枚以下なら、先に上げてから消す（途中で止まっても組が空にならない）"""
    plan = []
    for loc in locales:
        steps = []
        for kind in TARGETS + OLD_IPHONE:
            cur = loc["sets"].get(kind)
            delete = list(cur["shots"]) if cur else []
            upload = files[kind] if kind in TARGETS else []
            if not delete and not upload:
                continue
            steps.append({"type": kind, "set_id": cur["id"] if cur else None, "delete": delete, "upload": upload,
                          "upload_first": len(delete) + len(upload) <= MAX_PER_SET})
        plan.append({"locale": loc["locale"], "id": loc["id"], "steps": steps})
    return plan


def print_plan(version: str, plan: list[dict], apply: bool, untouched: list[str] = ()) -> None:
    print(f"== 版 {version}（{EDITABLE}）の iPhone の画面写真を入れ替えます" + ("" if apply else "（下見・何も変えません）"))
    print(f"入れ替える言語: {len(plan)} 件（{', '.join(p['locale'] for p in plan)}）")
    if untouched:
        print(f"触らない言語: {', '.join(sorted(untouched))}")
    for p in plan:
        print(f"-- {p['locale']}")
        for s in p["steps"]:
            kind = s["type"]
            line = f"   {LABEL.get(kind, kind)} [{kind}]: 消す {len(s['delete'])} 枚"
            if kind in TARGETS:
                line += f" → 上げる {len(s['upload'])} 枚" + ("" if s["set_id"] else "（組を作る）")
                line += "（先に上げて後で消す）" if s["upload_first"] else "（10枚を超えるので先に消す）"
            else:
                line += "（大型と中型がそろって COMPLETE になってから）"
            print(line)
            for shot in s["delete"]:
                print(f"      - {tfc.clean(shot.get('fileName') or shot['id'], 80)}")
            for path in s["upload"]:
                print(f"      + {os.path.basename(path)}")
    if not apply:
        print("下見だけで終わりました。入れ替えるときは ascApply=true で流し直す")


# ---- App Store Connect ---------------------------------------------------------------------

class Unsure(Exception):
    """書き込みが届いたか分からない（5xx・つながらない）。送り直さず、読み直して確かめる。"""


class Asc(tfc.Client):
    """`testflight-crashes.py` の Client に、書き込み（POST・PATCH・DELETE）と分割アップロードを足したもの。"""

    def call(self, method: str, path: str, body: dict | None = None) -> dict:
        """書き込み。PATCH（同じものを何度送っても同じ）だけ送り直す。POST・DELETE は送り直さない
        （2026-11-23 判断: 二重の予約・別の絵を消すのを避ける）。429 は受け付けていないので待って送り直す。DELETE の 404 は消せたとみなす"""
        url = API + path
        data = json.dumps(body).encode() if body is not None else None
        retry = method == "PATCH"
        for attempt in range(5):
            req = urllib.request.Request(url, data=data, method=method, headers={
                "Authorization": f"Bearer {self.jwt()}", "Accept": "application/json",
                **({"Content-Type": "application/json"} if data is not None else {})})
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    raw = r.read()
                    return json.loads(raw) if raw else {}
            except urllib.error.HTTPError as e:
                if method == "DELETE" and e.code == 404:
                    return {}
                if e.code == 429 or (retry and e.code >= 500):
                    time.sleep(2 ** attempt * 3)
                    continue
                if e.code >= 500:
                    raise Unsure(f"{method} {e.code}")
                codes = ""
                try:
                    codes = ",".join(sorted({x.get("code", "") for x in json.load(e).get("errors", [])}))
                except Exception:
                    pass
                raise ApiError(e.code, codes)
            except urllib.error.URLError:
                if not retry:
                    raise Unsure(f"{method} つながらない")
                time.sleep(2 ** attempt * 3)
        raise Stop("App Store Connect が何度送っても受け付けませんでした")

    def get_all(self, path: str, params: dict | None = None) -> list[dict]:
        out, url = [], path
        while url:
            page = self.get(url, params)
            out += page.get("data", [])
            url, params = (page.get("links") or {}).get("next"), None
        return out

    def put_part(self, op: dict, chunk: bytes) -> None:
        # アップロードの URL は認証なしの期限付き（Apple の文書: 人に渡さない）。ログに出さない
        url = op.get("url", "")
        if not url.startswith("https://"):
            raise Stop("アップロードの行き先が https ではありません")
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        for attempt in range(5):
            req = urllib.request.Request(url, data=chunk, method=op.get("method", "PUT"), headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=120):
                    return
            except urllib.error.HTTPError as e:
                if e.code == 429 or e.code >= 500:
                    time.sleep(2 ** attempt * 3)
                    continue
                raise Stop(f"絵の一部を送れませんでした（{e.code}）")
            except urllib.error.URLError:
                time.sleep(2 ** attempt * 3)
        raise Stop("絵の一部を何度送っても届きませんでした")


def find_version(c, bundle_id: str, version: str) -> dict:
    apps = c.get("/v1/apps", {"filter[bundleId]": bundle_id, "fields[apps]": "bundleId"})
    ids = [x["id"] for x in apps.get("data", []) if (x.get("attributes") or {}).get("bundleId") == bundle_id]
    if len(ids) != 1:
        raise Stop(f"App Store Connect に {bundle_id} のアプリが1つに決まりません（{len(ids)} 件）")
    vers = c.get_all(f"/v1/apps/{ids[0]}/appStoreVersions", {
        "filter[versionString]": version, "filter[platform]": "IOS",
        "fields[appStoreVersions]": "versionString,appVersionState,appStoreState,platform", "limit": 50})
    vers = [v for v in vers if (v.get("attributes") or {}).get("versionString") == version]
    if not vers:
        raise Stop(f"App Store Connect に版 {version} がありません（先に App Store Connect で版を作る）")
    if len(vers) != 1:
        raise Stop(f"版 {version} が {len(vers)} 件あります（1つに決まらないので触りません）")
    return vers[0]


def read_locales(c, version_id: str) -> list[dict]:
    locales = []
    for loc in c.get_all(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
                         {"fields[appStoreVersionLocalizations]": "locale", "limit": 200}):
        sets = {}
        for s in c.get_all(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets",
                           {"fields[appScreenshotSets]": "screenshotDisplayType", "limit": 50}):
            kind = (s.get("attributes") or {}).get("screenshotDisplayType", "")
            shots = c.get_all(f"/v1/appScreenshotSets/{s['id']}/appScreenshots",
                              {"fields[appScreenshots]": "fileName,assetDeliveryState", "limit": 50})
            sets[kind] = {"id": s["id"], "shots": [{"id": x["id"], **(x.get("attributes") or {})} for x in shots]}
        locales.append({"locale": (loc.get("attributes") or {}).get("locale", "?"), "id": loc["id"], "sets": sets})
    if not locales:
        raise Stop("この版に言語（localization）が1つもありません")
    return locales


def shots_of(c, set_id: str) -> list[dict]:
    return [{"id": x["id"], **(x.get("attributes") or {})} for x in c.get_all(
        f"/v1/appScreenshotSets/{set_id}/appScreenshots", {"fields[appScreenshots]": "fileName,assetDeliveryState", "limit": 50})]


def delete_shot(c, shot_id: str) -> None:
    try:
        c.call("DELETE", f"/v1/appScreenshots/{shot_id}")
    except Unsure:
        # 届いたか分からない: 送り直さず読み直す（404 なら消えている）
        try:
            c.get(f"/v1/appScreenshots/{shot_id}", {"fields[appScreenshots]": "fileName"})
        except ApiError as e:
            if e.status == 404:
                return
            raise
        raise Stop("絵を消せたか分かりません（App Store Connect が答えなかった）。ここで止めます")


def create_set(c, loc_id: str, kind: str) -> str:
    try:
        res = c.call("POST", "/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": kind},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
        return res["data"]["id"]
    except Unsure:
        # 届いたか分からない: 送り直さず読み直す（できていればそれを使う）
        for st in c.get_all(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets",
                            {"fields[appScreenshotSets]": "screenshotDisplayType", "limit": 50}):
            if (st.get("attributes") or {}).get("screenshotDisplayType") == kind:
                return st["id"]
        raise Stop(f"{LABEL[kind]}の組を作れたか分かりません（読み直しても無い）。ここで止めます")


def cover(ops: list[dict], size: int) -> bool:
    """送り方の区切りが 0 から size まで、重ならず隙間なく並んでいるか。"""
    pos = 0
    for off, length in sorted((int(op.get("offset", 0)), int(op.get("length", 0))) for op in ops):
        if off != pos or length <= 0:
            return False
        pos += length
    return pos == size


def upload_one(c, set_id: str, path: str, made: list | None = None) -> str:
    """1枚を上げる。予約できた id は made に足す（途中で止まったとき、呼ぶ側がこの回で作った分だけを消せるように）。"""
    name = unicodedata.normalize("NFC", os.path.basename(path))
    with open(path, "rb") as f:
        blob = f.read()
    before = {x["id"] for x in shots_of(c, set_id)}
    try:
        res = c.call("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots", "attributes": {"fileName": name, "fileSize": len(blob)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
    except Unsure:
        # 予約が届いたか分からない: 送り直さず読み直し、できていた予約（送る先が分からない）は消してから止める
        for x in shots_of(c, set_id):
            if x["id"] not in before and unicodedata.normalize("NFC", x.get("fileName") or "") == name:
                delete_shot(c, x["id"])
        raise Stop(f"{name} の予約が届いたか分かりません（読み直して、できていた予約は消しました）。ここで止めます")
    shot = res["data"]
    if made is not None:
        made.append(shot["id"])
    ops = (shot.get("attributes") or {}).get("uploadOperations") or []
    if not ops:
        raise Stop(f"{name} の送り方（uploadOperations）が返りませんでした")
    if not cover(ops, len(blob)):
        raise Stop(f"{name} の送り方の区切りがファイルの大きさと合いません")
    for op in ops:
        off, length = int(op.get("offset", 0)), int(op.get("length", 0))
        c.put_part(op, blob[off:off + length])
    c.call("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {
        "type": "appScreenshots", "id": shot["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
    return shot["id"]


def wait_complete(c, ids: list[str], deadline: float, sleep=None) -> dict[str, str]:
    """{id: 状態}。COMPLETE か FAILED になるか、締め切り（段の残り時間から決めた時刻）まで待つ（処理は数秒〜数分・Apple の文書）。"""
    sleep = sleep or time.sleep
    states: dict[str, str] = {}
    pending = list(ids)
    while pending:
        for sid in list(pending):
            d = c.get(f"/v1/appScreenshots/{sid}", {"fields[appScreenshots]": "assetDeliveryState"})
            st = (((d.get("data") or {}).get("attributes") or {}).get("assetDeliveryState") or {}).get("state", "?")
            states[sid] = st
            if st in ("COMPLETE", "FAILED"):
                pending.remove(sid)
        if pending:
            if time.time() > deadline:
                break
            sleep(5)
    return states


def apply_plan(c, plan: list[dict], deadline: float) -> None:
    """言語ごとに、大型 → 中型 → 古い組の順。組ごとに全部 COMPLETE でなければその場で止める。
    古い組（6.5 以前）を消すのは、その言語の大型と中型がそろって COMPLETE になってから。"""
    for p in plan:
        loc = p["locale"]
        for s in [x for x in p["steps"] if x["type"] in TARGETS]:
            kind = s["type"]
            if time.time() > deadline:
                raise Stop("段の残り時間が足りません。ここで止めます（流し直せば入れ替え直す）")
            how = "先に上げて後で消す" if s["upload_first"] else "先に消して後で上げる"
            print(f"-- {loc} {LABEL[kind]}: 今 {len(s['delete'])} 枚 → {len(s['upload'])} 枚を始めます（{how}）")
            set_id = s["set_id"] or create_set(c, p["id"], kind)
            if not s["upload_first"]:
                for shot in s["delete"]:
                    delete_shot(c, shot["id"])
            made: list[str] = []
            try:
                for path in s["upload"]:
                    # 送る前にも締め切りを見る（送りの途中で段の上限に切られないように）
                    if time.time() > deadline:
                        raise Stop("段の残り時間が足りません")
                    upload_one(c, set_id, path, made)
                states = wait_complete(c, made, deadline)
                bad = [states.get(i, "?") for i in made if states.get(i) != "COMPLETE"]
                if bad:
                    raise Stop(f"COMPLETE にならない絵が {len(bad)} 枚（{'・'.join(sorted(set(bad)))}）")
            except (Stop, ApiError, Unsure) as e:
                raise Stop(stopped(c, loc, kind, s, made, e)) from e
            ids = made
            if s["upload_first"]:
                for shot in s["delete"]:
                    delete_shot(c, shot["id"])
            c.call("PATCH", f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots",
                   {"data": [{"type": "appScreenshots", "id": i} for i in ids]})
            print(f"   {loc} {LABEL[kind]}: 消した {len(s['delete'])} 枚、上げた {len(ids)} 枚（全部 COMPLETE）")
        for s in [x for x in p["steps"] if x["type"] not in TARGETS]:
            print(f"-- {loc} {LABEL[s['type']]}: 古い組の {len(s['delete'])} 枚を消します（大型と中型がそろったので）")
            for shot in s["delete"]:
                delete_shot(c, shot["id"])


def stopped(c, loc: str, kind: str, step: dict, made: list[str], why: Exception) -> str:
    """組の途中で止まったときの後始末と、事実どおりの知らせ。
    先に上げる形: この回で作った id（上げ終えた絵・AWAITING_UPLOAD の予約）を消して元の組に戻す。
    先に消す形（10枚を超える）: 今の絵はもう消してあるので、そう伝える（戻せない）。"""
    if isinstance(why, ApiError):
        reason = f"App Store Connect が断りました（{why.status} {why.codes}）"
    elif isinstance(why, Unsure):
        reason = f"App Store Connect が書き込みに答えませんでした（{why}）"
    else:
        reason = str(why)
    head = f"{loc} {LABEL[kind]}: {reason}。ここで止めます（古い組は消していません）。"
    if step["upload_first"]:
        left = 0
        for i in made:
            try:
                delete_shot(c, i)
            except (Stop, ApiError, Unsure):
                left += 1
        if left:
            return head + f"この回で作った {len(made)} 枚のうち {left} 枚を消せませんでした（元の絵は残っています）"
        return head + f"この回で作った {len(made)} 枚を消して、元の組（{len(step['delete'])} 枚）に戻しました"
    return head + (f"この組の今の絵（{len(step['delete'])} 枚）は先に消しました。"
                   f"この回で上げた {len(made)} 枚が残っています。流し直して入れ替える")


def summarize(locales: list[dict], files: dict[str, list[str]]) -> list[str]:
    """今の組を出し、合わないもの（枚数・状態・名前の順）の一覧を返す（空なら全部そろった）。"""
    problems = []
    print("== 入れ替えたあとの組")
    for loc in locales:
        for kind in TARGETS + OLD_IPHONE:
            cur = loc["sets"].get(kind)
            shots = cur["shots"] if cur else []
            if kind not in TARGETS and not shots:
                continue
            states = [((x.get("assetDeliveryState") or {}).get("state") or "?") for x in shots]
            done = sum(1 for s in states if s == "COMPLETE")
            print(f"{loc['locale']} {LABEL.get(kind, kind)}: {len(shots)} 枚（COMPLETE {done} 枚）")
            if kind in TARGETS:
                want = [unicodedata.normalize("NFC", os.path.basename(p)) for p in files[kind]]
                got = [unicodedata.normalize("NFC", x.get("fileName") or "") for x in shots]
                if len(shots) != len(want):
                    problems.append(f"{loc['locale']} {kind}: {len(shots)} 枚（{len(want)} 枚のはず）")
                elif got != want:
                    problems.append(f"{loc['locale']} {kind}: 並びが 01 からの順になっていません")
                if done != len(shots):
                    problems.append(f"{loc['locale']} {kind}: COMPLETE でない絵が {len(shots) - done} 枚")
            elif shots:
                problems.append(f"{loc['locale']} {kind}: 古い組に {len(shots)} 枚残っています")
    return problems


def run(c, a, files) -> int:
    wanted = parse_locales(a.locales)
    deadline = time.time() + max(60.0, a.budget - 90.0)  # 最後に今の組を読んで出す分を残す
    version = find_version(c, a.bundle_id, a.version)
    check_editable(version)
    every = read_locales(c, version["id"])
    locales = pick_locales(every, wanted)
    plan = make_plan(locales, files)
    print_plan(a.version, plan, a.apply, [x["locale"] for x in every if x["locale"] not in wanted])
    if not a.apply:
        return 0
    # 変える直前にもう一度状態を読む（下見のあとで審査に出された版に触らない）
    check_editable(c.get(f"/v1/appStoreVersions/{version['id']}",
                         {"fields[appStoreVersions]": "versionString,appVersionState,appStoreState"})["data"])
    problems = ["今の組を読めませんでした"]
    try:
        apply_plan(c, plan, deadline)
    finally:
        # 止まっても、必ず今の組の中身を出す（どこまで入れ替わったかを見て流し直せるように）
        try:
            problems = summarize(pick_locales(read_locales(c, version["id"]), wanted), files)
        except (Stop, ApiError, Unsure, SystemExit) as e:
            # 最後の読みで止まっても（答えない・断られた）、その旨を1行出して赤で終える
            print(f"今の組を読めませんでした（{type(e).__name__}: {tfc.clean(e, 120)}）")
    if problems:
        for msg in problems:
            print(f"::error::{msg}")
        return 1
    print(f"{', '.join(wanted)} で、大型と中型の組が COMPLETE になりました")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", help="絵のフォルダ。無ければ App Store Connect を読むだけ（下見だけ）")
    ap.add_argument("--version", required=True)
    ap.add_argument("--locales", default="ja", help="入れ替える言語（例 ja,en-US）。ほかの言語には触らない")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--bundle-id", default="com.journeyphoto.JourneyPhoto")
    # 段の上限（ios-testflight.yml の timeout-minutes）より短くする。送りと待ちはこの中に収め、超えそうなら止めて今の組を出す
    ap.add_argument("--budget", type=float, default=2100.0, help="使ってよい秒（段の残り時間）")
    a = ap.parse_args(argv)
    try:
        if not re.fullmatch(r"\d+(\.\d+){1,3}", a.version):
            raise Stop(f"版の形が変です: {tfc.clean(a.version, 20)}（例 1.1.119）")
        parse_locales(a.locales)
        if a.dir:
            files = collect(a.dir)
        elif a.apply:
            raise Stop("絵が無いまま入れ替えはしません（--dir が要る）")
        else:
            # 絵が取れなかった回でも、鍵・版の状態・今の組を読んで確かめる（2026-11-23 判断: 下見で鍵の権限まで分かるように）
            files = {kind: [] for kind in TARGETS}
            print("手元の絵がありません。App Store Connect を読むだけにします")
        for kind in TARGETS:
            print(f"手元の絵 {LABEL[kind]} [{kind}]: {len(files[kind])} 枚")
        env = {k: os.environ.get(k, "") for k in
               ("APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_KEY_IDENTIFIER", "APP_STORE_CONNECT_PRIVATE_KEY")}
        missing = [k for k, v in env.items() if not v]
        if missing:
            raise Stop(f"Secrets が足りません: {' '.join(missing)}")
        with tempfile.TemporaryDirectory() as keydir:
            c = Asc(env["APP_STORE_CONNECT_ISSUER_ID"], env["APP_STORE_CONNECT_KEY_IDENTIFIER"],
                    env["APP_STORE_CONNECT_PRIVATE_KEY"], keydir)
            return run(c, a, files)
    except Stop as e:
        print(f"::error::{e}")
        return 1
    except Unsure as e:
        print(f"::error::App Store Connect が書き込みに答えませんでした（{e}）。送り直していません。今の組を確かめて流し直す")
        return 1
    except ApiError as e:
        hint = ""
        if e.status in (401, 403):
            hint = "（鍵が違う・鍵の役割が足りない。画面写真を変えるには App Manager 以上の鍵が要る）"
        elif e.status == 409:
            hint = "（App Store Connect が受け付けない変更。版の状態・枚数・寸法を確かめる）"
        print(f"::error::App Store Connect が断りました: {e.status} {e.codes}{hint}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
