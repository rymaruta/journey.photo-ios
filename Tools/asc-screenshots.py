#!/usr/bin/env python3
"""App Store 用の画面写真を、App Store Connect の「提出の準備中」の版に入れ替える（2026-11-23・札 #604）。

    python3 -I Tools/asc-screenshots.py --dir <store.tar をほどいた所> --version 1.1.119 [--apply]

呼ぶのは `Tools/asc-screenshots.sh`（`.github/workflows/appstore-screenshots.yml`）。owner は iPhone しか無く、
App Store Connect の Web は iPhone では画面写真の追加・削除ができないので、CI から入れ替える（owner 2026-11-23「仕組み作ろう」）。

**既定は下見（dry-run）。** 何を消して何を上げるかを出すだけで、何も変えない。`--apply` のときだけ変える。

🔴 守ること
  - 相手にするのは、指定の版で **状態が PREPARE_FOR_SUBMISSION のものだけ**。ほかの状態（配信中・審査中・却下など）なら
    何もせずに赤で止まる（配信中の版には触らない）。変える直前にも状態を読み直す
  - 触るのは iPhone の画面写真の組だけ。名前・説明などのメタデータ、App プレビュー、iPad の組、審査への提出には触らない
  - 画像の中身・アップロードの URL・鍵はログに出さない（ファイル名・枚数・状態だけ）

組の振り分け（ScreenshotDisplayType。Apple の enum には寸法が書かれていないので、Apple の「Screenshot specifications」と
fastlane の `deliver/lib/deliver/app_screenshot.rb` の DEVICE_RESOLUTIONS で突き合わせた・2026-11-23）:
  - APP_IPHONE_67 … 6.9インチ（と 6.7）。1320×2868・1290×2796・1260×2736。ここに大型の絵（出力の直下の `01-…png`〜）
  - APP_IPHONE_61 … 6.3インチ（と 6.1 の一部）＝ Dynamic Island 搭載の中型。1206×2622・1179×2556。
    ここに中型の絵（`medium-1206x2622/01-…png`〜）
  - APP_IPHONE_65・58・55・47・40・35 … 6.5インチ（Face ID 大型）以前の古い iPhone。中身を全部消す
    （6.9インチの組があれば、App Store Connect が縮めて使う）
  どの組に入れるかは、フォルダの名前ではなく **PNG の寸法** で決める（寸法の合わない絵は上げずに止まる）

使う口（Apple「Uploading assets to App Store Connect」と各資源の文書・2026-11-23）:
  - GET    /v1/apps?filter[bundleId]=…
  - GET    /v1/apps/{id}/appStoreVersions?filter[versionString]=…&filter[platform]=IOS   （状態は appVersionState・appStoreState）
  - GET    /v1/appStoreVersions/{id}/appStoreVersionLocalizations                        （その版の全部の言語）
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
SIZES = {(1320, 2868): LARGE, (1206, 2622): MEDIUM}
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
            dirnames[:] = []  # 見るのは直下と1段下（`medium-1206x2622/`）だけ
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

def make_plan(locales: list[dict], files: dict[str, list[str]]) -> list[dict]:
    """locales: [{"locale", "id", "sets": {display type: {"id", "shots": [{"id", "fileName"}]}}}]
    → 言語ごとに [{"type", "set_id", "delete": [shot], "upload": [道]}]（iPhone の組だけ。iPad などは入れない）"""
    plan = []
    for loc in sorted(locales, key=lambda x: x["locale"]):
        steps = []
        for kind in TARGETS + OLD_IPHONE:
            cur = loc["sets"].get(kind)
            delete = list(cur["shots"]) if cur else []
            upload = files[kind] if kind in TARGETS else []
            if not delete and not upload:
                continue
            steps.append({"type": kind, "set_id": cur["id"] if cur else None, "delete": delete, "upload": upload})
        plan.append({"locale": loc["locale"], "id": loc["id"], "steps": steps})
    return plan


def print_plan(version: str, plan: list[dict], apply: bool) -> None:
    print(f"== 版 {version}（{EDITABLE}）の iPhone の画面写真を入れ替えます" + ("" if apply else "（下見・何も変えません）"))
    print(f"言語: {len(plan)} 件（{', '.join(p['locale'] for p in plan)}）")
    for p in plan:
        print(f"-- {p['locale']}")
        for s in p["steps"]:
            kind = s["type"]
            line = f"   {LABEL.get(kind, kind)} [{kind}]: 消す {len(s['delete'])} 枚"
            if kind in TARGETS:
                line += f" → 上げる {len(s['upload'])} 枚" + ("" if s["set_id"] else "（組を作る）")
            print(line)
            for shot in s["delete"]:
                print(f"      - {tfc.clean(shot.get('fileName') or shot['id'], 80)}")
            for path in s["upload"]:
                print(f"      + {os.path.basename(path)}")
    if not apply:
        print("下見だけで終わりました。入れ替えるときは apply=true で流し直す")


# ---- App Store Connect ---------------------------------------------------------------------

class Asc(tfc.Client):
    """`testflight-crashes.py` の Client に、書き込み（POST・PATCH・DELETE）と分割アップロードを足したもの。"""

    def call(self, method: str, path: str, body: dict | None = None) -> dict:
        url = API + path
        data = json.dumps(body).encode() if body is not None else None
        for attempt in range(5):
            req = urllib.request.Request(url, data=data, method=method, headers={
                "Authorization": f"Bearer {self.jwt()}", "Accept": "application/json",
                **({"Content-Type": "application/json"} if data is not None else {})})
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    raw = r.read()
                    return json.loads(raw) if raw else {}
            except urllib.error.HTTPError as e:
                if e.code == 429 or e.code >= 500:
                    time.sleep(2 ** attempt * 3)
                    continue
                codes = ""
                try:
                    codes = ",".join(sorted({x.get("code", "") for x in json.load(e).get("errors", [])}))
                except Exception:
                    pass
                raise ApiError(e.code, codes)
            except urllib.error.URLError:
                time.sleep(2 ** attempt * 3)
        raise Stop("App Store Connect が何度引いても答えませんでした")

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


def upload_one(c, set_id: str, path: str) -> str:
    name = unicodedata.normalize("NFC", os.path.basename(path))
    with open(path, "rb") as f:
        blob = f.read()
    res = c.call("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots", "attributes": {"fileName": name, "fileSize": len(blob)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
    shot = res["data"]
    for op in (shot.get("attributes") or {}).get("uploadOperations") or []:
        off, length = int(op.get("offset", 0)), int(op.get("length", 0))
        c.put_part(op, blob[off:off + length])
    c.call("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {
        "type": "appScreenshots", "id": shot["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
    return shot["id"]


def wait_complete(c, ids: list[str], timeout: float, sleep=time.sleep) -> dict[str, str]:
    """{id: 状態}。COMPLETE か FAILED になるまで待つ（処理は数秒〜数分・Apple の文書）。"""
    states: dict[str, str] = {}
    end = time.time() + timeout
    pending = list(ids)
    while pending:
        for sid in list(pending):
            d = c.get(f"/v1/appScreenshots/{sid}", {"fields[appScreenshots]": "assetDeliveryState"})
            st = (((d.get("data") or {}).get("attributes") or {}).get("assetDeliveryState") or {}).get("state", "?")
            states[sid] = st
            if st in ("COMPLETE", "FAILED"):
                pending.remove(sid)
        if pending:
            if time.time() > end:
                break
            sleep(5)
    return states


def apply_plan(c, version_id: str, plan: list[dict], timeout: float) -> None:
    for p in plan:
        for s in p["steps"]:
            for shot in s["delete"]:
                c.call("DELETE", f"/v1/appScreenshots/{shot['id']}")
            if s["type"] not in TARGETS:
                print(f"{p['locale']} {LABEL[s['type']]}: {len(s['delete'])} 枚を消しました")
                continue
            set_id = s["set_id"]
            if not set_id:
                res = c.call("POST", "/v1/appScreenshotSets", {"data": {
                    "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": s["type"]},
                    "relationships": {"appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": p["id"]}}}}})
                set_id = res["data"]["id"]
            ids = [upload_one(c, set_id, path) for path in s["upload"]]
            states = wait_complete(c, ids, timeout)
            c.call("PATCH", f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots",
                   {"data": [{"type": "appScreenshots", "id": i} for i in ids]})
            ok = sum(1 for i in ids if states.get(i) == "COMPLETE")
            print(f"{p['locale']} {LABEL[s['type']]}: 消した {len(s['delete'])} 枚、上げた {len(ids)} 枚（COMPLETE {ok} 枚）")


def summarize(locales: list[dict], files: dict[str, list[str]]) -> list[str]:
    """終わったあとの組を読み、合わないもの（枚数・状態・名前の順）の一覧を返す（空なら全部そろった）。"""
    problems = []
    print("== 入れ替えたあとの組")
    for loc in sorted(locales, key=lambda x: x["locale"]):
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
    version = find_version(c, a.bundle_id, a.version)
    check_editable(version)
    locales = read_locales(c, version["id"])
    plan = make_plan(locales, files)
    print_plan(a.version, plan, a.apply)
    if not a.apply:
        return 0
    # 変える直前にもう一度状態を読む（下見のあとで審査に出された版に触らない）
    check_editable(c.get(f"/v1/appStoreVersions/{version['id']}",
                         {"fields[appStoreVersions]": "versionString,appVersionState,appStoreState"})["data"])
    apply_plan(c, version["id"], plan, a.timeout)
    problems = summarize(read_locales(c, version["id"]), files)
    if problems:
        for msg in problems:
            print(f"::error::{msg}")
        return 1
    print("全部の言語で、大型と中型の組が COMPLETE になりました")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", help="store.tar をほどいた所。無ければ App Store Connect を読むだけ（下見だけ・絵が取れなかった回）")
    ap.add_argument("--version", required=True)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--bundle-id", default="com.journeyphoto.JourneyPhoto")
    ap.add_argument("--timeout", type=float, default=600.0, help="処理の完了を待つ秒（1つの組ごと）")
    a = ap.parse_args(argv)
    try:
        if not re.fullmatch(r"\d+(\.\d+){1,3}", a.version):
            raise Stop(f"版の形が変です: {tfc.clean(a.version, 20)}（例 1.1.119）")
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
