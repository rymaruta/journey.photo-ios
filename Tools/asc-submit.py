#!/usr/bin/env python3
"""App Store Connect の申請用の版をそろえて、審査に出す（2026-11-25・札 #604）。

    python3 -I Tools/asc-submit.py --version 1.2.6 [--apply] [--no-submit]

呼ぶのは `.github/workflows/asc-submit.yml`（手で流す）。owner は iPhone しか無く、App Store Connect の Web は
iPhone では版の文・ビルド・審査の情報を入れにくいので、CI から入れる（owner 2026-11-25 承認）。

**既定は下見（dry-run）。** それぞれ「今の値 → 入れる値」を出すだけで、何も書かない。`--apply` のときだけ書く。
`--no-submit` は、版をそろえるところまでで止め、審査には出さない（画面写真を入れる前に版を作るときに使う）。

🔴 守ること
  - 相手にするのは、まだ公開されていない申請用の版（PREPARE_FOR_SUBMISSION・DEVELOPER_REJECTED など）だけ。
    公開中（READY_FOR_SALE）や審査中の版には絶対に書かない。書き込みのたびに、行き先と中身に
    その版の id が入っていないかを見て、入っていたら止める（`Writer`）。書く直前にも版の状態を読み直す
  - 審査用のアカウントのパスワードは読むだけ（在るかどうかを見る）。上書きしない・ログに出さない。
    審査の情報に送るのは notes の欄だけ
  - 鍵・アップロードの URL・審査用のアカウントの名前はログに出さない
  - 画面写真はここでは上げない（絵は Mac の storeShots の回の中にしか無い。`Tools/asc-screenshots.py`）。
    ここでは、そろっているかを `asc-screenshots.py` の読み方で確かめ、そろっていなければ審査に出さない
  - POST は送り直さない（届いたか分からなければ読み直す）。PATCH だけ送り直す（`asc-screenshots.py` の `Asc`）

すること（順に）
  1. 申請用の版: 無ければ作る（POST /v1/appStoreVersions）。版の名前が違えば直す（PATCH versionString）
  2. 新機能の説明（whatsNew）を日本語と英語で入れる（PATCH /v1/appStoreVersionLocalizations/{id}）
  3. ビルド: その版の、処理済み（VALID）で期限の切れていない最新のビルドを選ぶ（PATCH …/relationships/build）
  4. 審査の情報の Notes（`docs/APP_REVIEW.md` の「英語（貼る）」）を入れる（PATCH /v1/appStoreReviewDetails/{id}・notes だけ）
  5. 段階的リリース（7日）を付ける（無ければ POST /v1/appStoreVersionPhasedReleases・`docs/APP_REVIEW.md` の推奨）
  6. 定期購入が「提出の準備ができた」なら、版と一緒に審査に出す（POST /v1/subscriptionSubmissions）
  7. 審査に出す: reviewSubmissions を作り（下書きがあれば使い回す）、版を足して、submitted=true
  使う口は Apple の App Store Connect API の文書（appStoreVersions・appStoreVersionLocalizations・builds・
  appStoreReviewDetails・appStoreVersionPhasedReleases・subscriptionSubmissions・reviewSubmissions・reviewSubmissionItems）
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import pathlib
import re
import sys
import tempfile
import time
import urllib.error
import urllib.request

_here = pathlib.Path(__file__).resolve()
_spec = importlib.util.spec_from_file_location("ascs", _here.with_name("asc-screenshots.py"))
ascs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ascs)
Stop, Unsure, ApiError, tfc = ascs.Stop, ascs.Unsure, ascs.ApiError, ascs.tfc

REVIEW_DOC = _here.parent.parent / "docs" / "APP_REVIEW.md"

# 新機能の説明（2026-11-25 owner 承認の案。1.2.6 の人間工学の直しを1行足した）
WHATS_NEW = {
    "ja": """1.0.87 からの大きな更新です。
– 旅の本棚：撮りためた旅を、本のように棚に並べます
– 旅のスタンプ帳：行った所の記録がたまります。あなたにだけ見えます
– 旅のトランク：投稿で硬貨がもらえます。ふたには、行きたい場所の方角を指す羅針盤
– かけら：持っている部品が出たら、かけらに。5つで好きな部品と交換できます
– Apple や Google のアカウントでログインできるようになりました
– 登録は、メールに届く確認コードで済みます
– AI で作る旅行プランを直しました。主な行き先で組めて、「もっとゆっくり」「雨なら」を押すとすぐ変わります
– 片手で使いやすく、文字を大きくしても読みやすくしました
– アプリ全体の動きを軽くしました""",
    "en-US": """A big update since 1.0.87.
- Travel bookshelf: your trips line up on a shelf like books
- Travel stamp book: a record of the places you have been. Only you can see it
- Travel trunk: earn coins by posting. The lid has a compass that points toward places you want to go
- Fragments: a part you already have turns into a fragment. Trade 5 fragments for any part you like
- Sign in with your Apple or Google account
- Sign up with a confirmation code sent to your email
- Better AI trip plans: built around the main destinations, and "Slower pace" or "If it rains" changes the plan right away
- Easier to use with one hand, and easier to read with larger text
- The whole app runs lighter""",
}
REQUIRED_LOCALE = "ja"  # 主要言語。無ければ止める。ほかの言語は版に在るものだけ入れる（作らない）

# 書いてよい版の状態（まだ公開されていない申請用）
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
# もう審査に出ている状態（何も書かずに知らせて終える）
SUBMITTED = {"WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW", "WAITING_FOR_EXPORT_COMPLIANCE"}
# 審査の申請（reviewSubmissions）のうち、進んでいるもの。これがあると新しく出さない
OPEN_SUBMISSION = {"WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES", "CANCELING", "COMPLETING"}
SUB_OK = {"APPROVED", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_BINARY_APPROVAL",
          "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE"}
MAX_TEXT = 4000


# ---- 文 -------------------------------------------------------------------------------------

def review_notes(path: pathlib.Path = REVIEW_DOC) -> str:
    """`docs/APP_REVIEW.md` の「### 英語（貼る）」の直後の ``` の中身。"""
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^### 英語（貼る）\s*\n+```[^\n]*\n(.*?)\n```", text, re.S | re.M)
    if not m:
        raise Stop("docs/APP_REVIEW.md に「英語（貼る）」の Notes が見つかりません")
    notes = m.group(1).strip()
    if not notes or len(notes) > MAX_TEXT:
        raise Stop(f"審査の Notes の長さが {len(notes)} 字です（1〜{MAX_TEXT} 字）")
    return notes


def short(text: str | None, n: int = 50) -> str:
    if not text:
        return "（空）"
    one = tfc.clean(text.replace("\n", " / "), n)
    return f"「{one}{'…' if len(text) > n else ''}」（{len(text)} 字）"


def vtuple(s: str) -> tuple[int, ...]:
    return tuple(int(x) for x in s.split("."))


# ---- 版の状態 -------------------------------------------------------------------------------

def states(v: dict) -> set[str]:
    return set(ascs.version_states(v.get("attributes") or {}))


def is_editable(v: dict) -> bool:
    st = states(v)
    return bool(st) and st <= EDITABLE


def is_submitted(v: dict) -> bool:
    return bool(states(v) & SUBMITTED)


def name_of(v: dict) -> str:
    return (v.get("attributes") or {}).get("versionString", "?")


class SubmitAsc(ascs.Asc):
    """`asc-screenshots.py` の `Asc` と同じ書き方。断られたとき（409 など）に、Apple の言う理由（detail と欄の名前）も残す。
    detail は「この欄が足りない」の類いで、鍵や審査用のアカウントの中身は入らない（それでも 200 字で切る）。"""

    def call(self, method: str, path: str, body: dict | None = None) -> dict:
        url = ascs.API + path
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
                if e.code == 429 or (retry and e.code >= 500):
                    time.sleep(2 ** attempt * 3)
                    continue
                if e.code >= 500:
                    raise Unsure(f"{method} {e.code}")
                codes, why = "", []
                try:
                    errs = json.load(e).get("errors", [])
                    codes = ",".join(sorted({x.get("code", "") for x in errs}))
                    for x in errs[:5]:
                        ptr = ((x.get("source") or {}).get("pointer") or "")
                        why.append(tfc.clean(f"{x.get('detail', '')} {ptr}".strip(), 200))
                        for ae in ((x.get("meta") or {}).get("associatedErrors") or {}).values():
                            for y in (ae or [])[:5]:
                                why.append(tfc.clean(f"{y.get('code', '')} {y.get('detail', '')}", 200))
                except Exception:
                    pass
                if e.code not in (401, 403):
                    for line in why:
                        print(f"   Apple の理由: {line}")
                raise ApiError(e.code, codes)
            except urllib.error.URLError:
                if not retry:
                    raise Unsure(f"{method} つながらない")
                time.sleep(2 ** attempt * 3)
        raise Stop("App Store Connect が何度送っても受け付けませんでした")


class Writer:
    """書き込みの関所。下見では何も通さない。公開中などの版の id が行き先か中身に入っていたら止める。"""

    def __init__(self, c, apply: bool, protected: set[str]):
        self.c, self.apply, self.protected = c, apply, set(protected)

    def call(self, method: str, path: str, body: dict | None = None) -> dict:
        if not self.apply:
            raise Stop("下見なのに書き込もうとしました（ここには来ないはず）。止めます")
        parts = set(path.split("?")[0].split("/"))
        blob = json.dumps(body or {})
        for pid in self.protected:
            if pid in parts or f'"{pid}"' in blob:
                raise Stop("公開中か審査中の版に書き込もうとしました。止めます（何も送っていません）")
        return self.c.call(method, path, body)


def recheck(c, vid: str) -> None:
    """書く直前に版の状態を読み直す（下見のあとで審査に出された・公開された版に触らない）。"""
    v = c.get(f"/v1/appStoreVersions/{vid}",
              {"fields[appStoreVersions]": "versionString,appVersionState,appStoreState"})["data"]
    if not is_editable(v):
        raise Stop(f"版 {name_of(v)} の状態が {'、'.join(sorted(states(v))) or '?'} に変わりました。書かずに止めます")


# ---- 読む -----------------------------------------------------------------------------------

def app_id(c, bundle_id: str) -> str:
    apps = c.get("/v1/apps", {"filter[bundleId]": bundle_id, "fields[apps]": "bundleId"})
    ids = [x["id"] for x in apps.get("data", []) if (x.get("attributes") or {}).get("bundleId") == bundle_id]
    if len(ids) != 1:
        raise Stop(f"App Store Connect に {bundle_id} のアプリが1つに決まりません（{len(ids)} 件）")
    return ids[0]


def all_versions(c, aid: str) -> list[dict]:
    return c.get_all(f"/v1/apps/{aid}/appStoreVersions", {
        "filter[platform]": "IOS", "limit": 200,
        "fields[appStoreVersions]": "versionString,appVersionState,appStoreState,platform,releaseType"})


def pick_target(versions: list[dict], version: str) -> tuple[dict | None, set[str], str]:
    """(申請用の版 か None, 書いてはいけない版の id, どうするか)。どうするか: use / rename / create / submitted"""
    if not re.fullmatch(r"\d+(\.\d+){1,3}", version):
        raise Stop(f"版の形が変です: {tfc.clean(version, 20)}（例 1.2.6）")
    protected = {v["id"] for v in versions if not is_editable(v)}
    same = [v for v in versions if name_of(v) == version]
    if len(same) > 1:
        raise Stop(f"版 {version} が {len(same)} 件あります（1つに決まらないので触りません）")
    if same and is_submitted(same[0]):
        return same[0], protected | {same[0]["id"]}, "submitted"
    if same and not is_editable(same[0]):
        raise Stop(f"版 {version} の状態は {'、'.join(sorted(states(same[0])))} です。"
                   "公開中・公開済みの版には書きません")
    newer_than = [name_of(v) for v in versions if not is_editable(v)
                  and re.fullmatch(r"\d+(\.\d+){1,3}", name_of(v)) and vtuple(name_of(v)) >= vtuple(version)]
    if newer_than:
        raise Stop(f"版 {version} は、もうある版（{', '.join(sorted(newer_than))}）より新しくありません")
    busy = [name_of(v) for v in versions if is_submitted(v)]
    if busy:
        raise Stop(f"別の版（{', '.join(busy)}）が審査に出ています。新しい版には触りません")
    editable = [v for v in versions if is_editable(v)]
    if len(editable) > 1:
        raise Stop(f"申請用の版が {len(editable)} 件あります（{', '.join(name_of(v) for v in editable)}）。"
                   "1つに決まらないので触りません")
    if not editable:
        return None, protected, "create"
    target = editable[0]
    return target, protected, ("use" if name_of(target) == version else "rename")


def latest_build(c, aid: str, version: str) -> dict:
    builds = c.get("/v1/builds", {
        "filter[app]": aid, "filter[preReleaseVersion.version]": version, "filter[processingState]": "VALID",
        "filter[expired]": "false", "sort": "-uploadedDate", "limit": 20,
        "fields[builds]": "version,uploadedDate,processingState,expired"}).get("data", [])
    ok = [b for b in builds if (b.get("attributes") or {}).get("processingState") == "VALID"
          and not (b.get("attributes") or {}).get("expired")]
    if not ok:
        raise Stop(f"版 {version} の処理済みのビルドが App Store Connect にありません（TestFlight に出てから）")
    return max(ok, key=lambda b: (b.get("attributes") or {}).get("uploadedDate") or "")


def build_label(b: dict | None) -> str:
    if not b:
        return "（選んでいない）"
    a = b.get("attributes") or {}
    return f"ビルド {a.get('version', '?')}（{(a.get('uploadedDate') or '?')[:16]} に上げた）"


def read_version(c, vid: str) -> dict:
    """版の中身（言語・ビルド・審査の情報・段階的リリース）。審査用のアカウントのパスワードは在るかどうかだけ残す。"""
    locs = c.get_all(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", {
        "fields[appStoreVersionLocalizations]": "locale,whatsNew,description,keywords", "limit": 50})
    build = c.get(f"/v1/appStoreVersions/{vid}/build", {"fields[builds]": "version,uploadedDate,processingState"}
                  ).get("data")
    try:
        rd = c.get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
    except ApiError as e:
        if e.status != 404:
            raise
        rd = None
    review = None
    if rd:
        a = rd.get("attributes") or {}
        review = {"id": rd["id"], "notes": a.get("notes") or "",
                  "required": bool(a.get("demoAccountRequired")),
                  "has_name": bool(a.get("demoAccountName")), "has_password": bool(a.get("demoAccountPassword")),
                  "has_contact": all(a.get(k) for k in ("contactFirstName", "contactLastName",
                                                        "contactPhone", "contactEmail"))}
        a.clear()  # パスワードを手元に残さない
    try:
        phased = c.get(f"/v1/appStoreVersions/{vid}/appStoreVersionPhasedRelease").get("data")
    except ApiError as e:
        if e.status != 404:
            raise
        phased = None
    return {"locales": {(x.get("attributes") or {}).get("locale"): {"id": x["id"], **(x.get("attributes") or {})}
                        for x in locs},
            "build": build, "review": review, "phased": phased}


def read_subscriptions(c, aid: str) -> list[dict]:
    out = []
    for g in c.get_all(f"/v1/apps/{aid}/subscriptionGroups", {"limit": 50}):
        for s in c.get_all(f"/v1/subscriptionGroups/{g['id']}/subscriptions",
                           {"fields[subscriptions]": "productId,state", "limit": 50}):
            a = s.get("attributes") or {}
            out.append({"id": s["id"], "productId": a.get("productId", "?"), "state": a.get("state", "?"),
                        "group": g["id"]})
    return out


def subscription_details(c, aid: str, subs: list[dict]) -> list[str]:
    """下見のときだけ: 定期購入ごとに、審査に出すのに要るものがそろっているかを読む（読むだけ・2026-11-25 札 #604）。

    審査の差し戻し 2.1(b)「Pro の商品が審査に出されていない」を受けて足した。今までは状態（MISSING_METADATA など）しか
    読まず、何が足りないかが分からなかった。読むのは Apple の App Store Connect API の文書の口
    （subscriptionLocalizations・prices・appStoreReviewScreenshot・subscriptionAvailability・
    subscriptionGroupLocalizations・inAppPurchasesV2）。足りないものを文で返す（`::warning::` で出す）"""
    missing: list[str] = []

    def safe(fn, what: str):
        try:
            return fn()
        except (ApiError, Unsure, urllib.error.URLError, KeyError, TypeError, ValueError) as e:
            print(f"   {what}: 読めませんでした（{tfc.clean(str(e), 80)}）")
            return None

    for gid in sorted({x["group"] for x in subs if x.get("group")}):
        glocs = safe(lambda: c.get_all(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations", {"limit": 50}),
                     "定期購入のグループの表示名")
        if glocs is not None:
            names = sorted((x.get("attributes") or {}).get("locale", "?") for x in glocs)
            print(f"   定期購入のグループの表示名: {len(names)} 言語（{', '.join(names) or 'なし'}）")
            if REQUIRED_LOCALE not in names:
                missing.append(f"定期購入のグループの表示名に {REQUIRED_LOCALE} がありません")
    for x in subs:
        pid, sid = x["productId"], x["id"]
        print(f"-- 定期購入 {pid}: {x['state']}")
        locs = safe(lambda: c.get_all(f"/v1/subscriptions/{sid}/subscriptionLocalizations", {"limit": 50}), "表示名と説明")
        if locs is not None:
            names = sorted((y.get("attributes") or {}).get("locale", "?") for y in locs)
            print(f"   表示名と説明: {len(names)} 言語（{', '.join(names) or 'なし'}）")
            if REQUIRED_LOCALE not in names:
                missing.append(f"{pid}: 表示名と説明（{REQUIRED_LOCALE}）がありません")
        prices = safe(lambda: c.get(f"/v1/subscriptions/{sid}/prices", {"limit": 1}).get("data", []), "値段")
        if prices is not None:
            print(f"   値段: {'あり' if prices else 'なし'}")
            if not prices:
                missing.append(f"{pid}: 値段が決まっていません")
        # 中身が無い（data が null）と読めなかったを分けるため、答えをそのまま受ける
        shot_answer = safe(lambda: c.get(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot"), "審査用の画面写真")
        if shot_answer is not None:
            shot = shot_answer.get("data")
            state = (((shot or {}).get("attributes") or {}).get("assetDeliveryState") or {}).get("state")
            print(f"   審査用の画面写真: {'なし' if not shot else state or 'あり'}")
            if not shot:
                missing.append(f"{pid}: 審査用の画面写真がありません（App Review に関する情報）")
            elif state and state != "COMPLETE":
                missing.append(f"{pid}: 審査用の画面写真が {state} です")
        avail_answer = safe(lambda: c.get(f"/v1/subscriptions/{sid}/subscriptionAvailability"), "販売する国や地域")
        if avail_answer is not None:
            avail = avail_answer.get("data")
            print(f"   販売する国や地域: {'決まっている' if avail else '決まっていない'}")
            if not avail:
                missing.append(f"{pid}: 販売する国や地域が決まっていません")
    others = safe(lambda: c.get_all(f"/v1/apps/{aid}/inAppPurchasesV2",
                                    {"fields[inAppPurchases]": "productId,state,inAppPurchaseType", "limit": 50}),
                  "定期購入でないアプリ内課金")
    if others is not None:
        print(f"-- 定期購入でないアプリ内課金: {len(others)} 件")
        for y in others:
            a = y.get("attributes") or {}
            print(f"   {tfc.clean(a.get('productId') or '?', 80)}: {a.get('state', '?')}（{a.get('inAppPurchaseType', '?')}）")
    return missing


def screenshot_problems(c, vid: str) -> list[str]:
    """主要言語の大型と中型の組に、1枚以上あって全部 COMPLETE か（`asc-screenshots.py` の読み方）。"""
    problems = []
    locales = {x["locale"]: x for x in ascs.read_locales(c, vid)}
    for loc_name, loc in sorted(locales.items()):
        for kind in ascs.TARGETS + ascs.OLD_IPHONE:
            shots = (loc["sets"].get(kind) or {}).get("shots") or []
            if not shots and kind not in ascs.TARGETS:
                continue
            done = sum(1 for x in shots if ((x.get("assetDeliveryState") or {}).get("state")) == "COMPLETE")
            names = "、".join(tfc.clean(x.get("fileName") or "?", 40) for x in shots)
            print(f"   画面写真 {loc_name} {ascs.LABEL.get(kind, kind)}: {len(shots)} 枚（COMPLETE {done} 枚）"
                  + (f" {names}" if names else ""))
            if loc_name == REQUIRED_LOCALE and kind in ascs.TARGETS:
                if not shots:
                    problems.append(f"画面写真: {loc_name} の{ascs.LABEL[kind]}の組が空です")
                elif done != len(shots):
                    problems.append(f"画面写真: {loc_name} の{ascs.LABEL[kind]}に COMPLETE でない絵が {len(shots) - done} 枚")
    if REQUIRED_LOCALE not in locales:
        problems.append(f"画面写真: 言語 {REQUIRED_LOCALE} がありません")
    return problems


def review_problems(review: dict | None) -> list[str]:
    if not review:
        return ["審査の情報（App Review に関する情報）がこの版にありません。審査用のアカウントを App Store Connect で入れてから"]
    out = []
    if not (review["required"] and review["has_name"] and review["has_password"]):
        out.append("審査用のアカウント（サインイン情報）が App Store Connect にありません")
    if not review["has_contact"]:
        out.append("審査の連絡先（名前・電話・メール）が App Store Connect にありません")
    return out


# ---- 計画と実行 -----------------------------------------------------------------------------

def plan_version(c, vid: str, aid: str, version: str, notes: str) -> tuple[list[dict], dict]:
    """版の中身について「今 → 入れる」の一覧。各項目: {"label", "now", "new", "method", "path", "body"}"""
    cur = read_version(c, vid)
    steps = []
    if REQUIRED_LOCALE not in cur["locales"]:
        raise Stop(f"版に言語 {REQUIRED_LOCALE} がありません（言語はここでは作らない）")
    for loc, text in WHATS_NEW.items():
        if len(text) > MAX_TEXT:
            raise Stop(f"新機能の説明（{loc}）が {MAX_TEXT} 字を超えています")
        have = cur["locales"].get(loc)
        if not have:
            print(f"   新機能の説明 {loc}: この版に言語が無いので入れません（作らない）")
            continue
        if (have.get("whatsNew") or "").strip() != text:
            steps.append({"label": f"新機能の説明 {loc}", "now": short(have.get("whatsNew")), "new": text,
                          "method": "PATCH", "path": f"/v1/appStoreVersionLocalizations/{have['id']}",
                          "body": {"data": {"type": "appStoreVersionLocalizations", "id": have["id"],
                                            "attributes": {"whatsNew": text}}}})
        else:
            print(f"   新機能の説明 {loc}: もう入っています")
        for key in ("description", "keywords"):
            if not have.get(key):
                print(f"::warning::{loc} の {key} が空です（App Store Connect で入れる。docs/APP_STORE_METADATA.md）")
    build = latest_build(c, aid, version)
    if not cur["build"] or cur["build"]["id"] != build["id"]:
        steps.append({"label": "ビルド", "now": build_label(cur["build"]), "new": build_label(build),
                      "method": "PATCH", "path": f"/v1/appStoreVersions/{vid}/relationships/build",
                      "body": {"data": {"type": "builds", "id": build["id"]}}})
    else:
        print(f"   ビルド: もう {build_label(build)} を選んでいます")
    review = cur["review"]
    if review and review["notes"].strip() != notes:
        # 送るのは notes の欄だけ（審査用のアカウントのパスワードなど、ほかの欄は送らない＝そのまま残る）
        steps.append({"label": "審査の Notes", "now": short(review["notes"]), "new": short(notes, 60),
                      "method": "PATCH", "path": f"/v1/appStoreReviewDetails/{review['id']}",
                      "body": {"data": {"type": "appStoreReviewDetails", "id": review["id"],
                                        "attributes": {"notes": notes}}}})
    elif review:
        print("   審査の Notes: もう入っています")
    if review:
        print(f"   審査用のアカウント: サインインが必要 {'はい' if review['required'] else 'いいえ'}、"
              f"ユーザー名 {'あり' if review['has_name'] else 'なし'}、パスワード {'あり' if review['has_password'] else 'なし'}"
              f"（中身は出さない・上書きしない）、連絡先 {'あり' if review['has_contact'] else 'なし'}")
    if not cur["phased"]:
        steps.append({"label": "段階的リリース", "now": "なし", "new": "7日で段階的に配る（承認のあとで始まる）",
                      "method": "POST", "path": "/v1/appStoreVersionPhasedReleases",
                      "body": {"data": {"type": "appStoreVersionPhasedReleases",
                                        "attributes": {"phasedReleaseState": "INACTIVE"},
                                        "relationships": {"appStoreVersion": {
                                            "data": {"type": "appStoreVersions", "id": vid}}}}}})
    else:
        print(f"   段階的リリース: もうあります（{(cur['phased'].get('attributes') or {}).get('phasedReleaseState', '?')}）")
    return steps, cur


def plan_subscriptions(subs: list[dict]) -> tuple[list[dict], list[str]]:
    steps, problems = [], []
    for s in subs:
        if s["state"] == "READY_TO_SUBMIT":
            steps.append({"label": f"定期購入 {s['productId']}", "now": s["state"], "new": "版と一緒に審査に出す",
                          "method": "POST", "path": "/v1/subscriptionSubmissions",
                          "body": {"data": {"type": "subscriptionSubmissions", "relationships": {
                              "subscription": {"data": {"type": "subscriptions", "id": s["id"]}}}}}})
        elif s["state"] in SUB_OK:
            print(f"   定期購入 {s['productId']}: {s['state']}（このまま）")
        else:
            problems.append(f"定期購入 {s['productId']} の状態が {s['state']} です（App Store Connect で直す）")
    return steps, problems


def print_steps(steps: list[dict]) -> None:
    if not steps:
        print("   変えるものはありません")
    for s in steps:
        print(f"-- {s['label']}")
        print(f"   今: {s['now']}")
        new = s["new"]
        if "\n" in new:
            print("   入れる:")
            for line in new.splitlines():
                print(f"     {line}")
        else:
            print(f"   入れる: {new}")


def run_steps(w: Writer, c, vid: str, steps: list[dict]) -> None:
    for s in steps:
        recheck(c, vid)
        try:
            w.call(s["method"], s["path"], s["body"])
        except Unsure:
            raise Stop(f"{s['label']}: App Store Connect が答えませんでした（送り直していません）。流し直す")
        print(f"   入れました: {s['label']}")


def ensure_version(w: Writer, c, aid: str, target: dict | None, how: str, version: str) -> str:
    if how == "rename":
        recheck(c, target["id"])
        w.call("PATCH", f"/v1/appStoreVersions/{target['id']}", {"data": {
            "type": "appStoreVersions", "id": target["id"], "attributes": {"versionString": version}}})
        print(f"   版の名前を {name_of(target)} から {version} に直しました")
        return target["id"]
    if how == "create":
        try:
            res = w.call("POST", "/v1/appStoreVersions", {"data": {
                "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": version},
                "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})
            vid = res["data"]["id"]
        except Unsure:
            again = [v for v in all_versions(c, aid) if name_of(v) == version and is_editable(v)]
            if len(again) != 1:
                raise Stop(f"版 {version} を作れたか分かりません。ここで止めます")
            vid = again[0]["id"]
        print(f"   版 {version} を作りました")
        recheck(c, vid)
        return vid
    return target["id"]


def submit(w: Writer, c, aid: str, vid: str) -> str:
    """審査に出す。進んでいる申請があれば止める。下書き（READY_FOR_REVIEW）があれば使い回す。"""
    subs = c.get_all("/v1/reviewSubmissions", {"filter[app]": aid, "filter[platform]": "IOS", "limit": 50,
                                               "fields[reviewSubmissions]": "state,platform"})
    states_ = [(s["id"], (s.get("attributes") or {}).get("state", "?")) for s in subs]
    busy = [st for _, st in states_ if st in OPEN_SUBMISSION]
    if busy:
        raise Stop(f"別の審査の申請が進んでいます（{'、'.join(sorted(set(busy)))}）。新しく出さずに止めます")
    draft = [sid for sid, st in states_ if st == "READY_FOR_REVIEW"]
    if len(draft) > 1:
        raise Stop("審査の申請の下書きが2つ以上あります。止めます")
    recheck(c, vid)
    if draft:
        sid = draft[0]
        items = c.get_all(f"/v1/reviewSubmissions/{sid}/items", {"include": "appStoreVersion", "limit": 50})
        has = any(((i.get("relationships") or {}).get("appStoreVersion") or {}).get("data", {}).get("id") == vid
                  for i in items)
        print(f"   審査の申請の下書きを使います（項目 {len(items)} 件）")
    else:
        try:
            sid = w.call("POST", "/v1/reviewSubmissions", {"data": {
                "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]["id"]
        except Unsure:
            raise Stop("審査の申請を作れたか分かりません（送り直していません）。流し直すと下書きを使い回します")
        has = False
        print("   審査の申請を作りました")
    if not has:
        try:
            w.call("POST", "/v1/reviewSubmissionItems", {"data": {
                "type": "reviewSubmissionItems", "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        except Unsure:
            raise Stop("審査の申請に版を足せたか分かりません（送り直していません）。流し直す")
        print("   審査の申請に版を足しました")
    recheck(c, vid)
    w.call("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {
        "type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
    after = c.get(f"/v1/reviewSubmissions/{sid}", {"fields[reviewSubmissions]": "state,submittedDate"})["data"]
    return (after.get("attributes") or {}).get("state", "?")


def run(c, a) -> int:
    notes = review_notes()
    aid = app_id(c, a.bundle_id)
    versions = all_versions(c, aid)
    for v in versions:
        print(f"   App Store Connect の版 {name_of(v)}: {'、'.join(sorted(states(v))) or '?'}"
              + ("（書きません）" if not is_editable(v) else "（申請用）"))
    target, protected, how = pick_target(versions, a.version)
    mode = "" if a.apply else "（下見・何も書きません）"
    print(f"== 版 {a.version} を審査に出す準備{mode}")
    if how == "submitted":
        print(f"版 {a.version} はもう審査に出ています（{'、'.join(sorted(states(target)))}）。何も書きません")
        return 0
    w = Writer(c, a.apply, protected)
    if how == "create":
        print(f"-- 申請用の版\n   今: なし\n   入れる: 版 {a.version} を作る")
    elif how == "rename":
        print(f"-- 申請用の版の名前\n   今: {name_of(target)}（{'、'.join(sorted(states(target)))}）\n   入れる: {a.version}")
    else:
        print(f"   申請用の版: {a.version}（{'、'.join(sorted(states(target)))}）")
    subs = read_subscriptions(c, aid)
    sub_steps, sub_problems = plan_subscriptions(subs)
    if not a.apply:
        # 定期購入の中身を先に読む（版のビルドが無くて下見が止まっても、課金の足りないものは見えるように）
        for m in subscription_details(c, aid, [x for x in subs if x["state"] not in SUB_OK]):
            print(f"::warning::{m}")
        if how == "create":
            print("   版がまだ無いので、版の中身（新機能の説明・ビルド・審査の情報・画面写真）は作ってから読みます")
            build = latest_build(c, aid, a.version)
            print(f"-- ビルド\n   今: （版が無い）\n   入れる: {build_label(build)}")
            print(f"-- 審査の Notes\n   入れる: {short(notes, 60)}")
            print_steps(sub_steps)
            problems = sub_problems + ["画面写真: 版がまだ無い（作ってから storeShots の回で入れる）"]
        else:
            steps, cur = plan_version(c, target["id"], aid, a.version, notes)
            print_steps(steps + sub_steps)
            problems = sub_problems + review_problems(cur["review"]) + screenshot_problems(c, target["id"])
        if problems:
            print("== このままでは審査に出せません（下見）")
            for p in problems:
                print(f"::warning::{p}")
        else:
            print("== 下見だけで終わりました。審査に出すときは apply=true で流し直す")
        return 0
    vid = ensure_version(w, c, aid, target, how, a.version)
    steps, _ = plan_version(c, vid, aid, a.version, notes)
    print_steps(steps)
    run_steps(w, c, vid, steps)
    # 書いたあとに読み直して、審査に出せるかを確かめる
    cur = read_version(c, vid)
    problems = sub_problems + review_problems(cur["review"]) + screenshot_problems(c, vid)
    if not cur["build"]:
        problems.append("ビルドが選ばれていません")
    if problems:
        for p in problems:
            print(f"::error::{p}")
        print("審査には出していません（上を直してから流し直す）")
        return 1
    if a.no_submit:
        print("版をそろえました。審査には出していません（submit=false）")
        return 0
    print_steps(sub_steps)
    run_steps(w, c, vid, sub_steps)
    state = submit(w, c, aid, vid)
    v = c.get(f"/v1/appStoreVersions/{vid}", {"fields[appStoreVersions]": "versionString,appVersionState,appStoreState"})
    print(f"== 審査に出しました: 申請 {state}、版 {a.version} {'、'.join(sorted(states(v['data'])))}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--no-submit", action="store_true", help="版をそろえるだけで、審査には出さない")
    ap.add_argument("--bundle-id", default="com.journeyphoto.JourneyPhoto")
    a = ap.parse_args(argv)
    try:
        env = {k: os.environ.get(k, "") for k in
               ("APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_KEY_IDENTIFIER", "APP_STORE_CONNECT_PRIVATE_KEY")}
        missing = [k for k, v in env.items() if not v]
        if missing:
            raise Stop(f"Secrets が足りません: {' '.join(missing)}")
        with tempfile.TemporaryDirectory() as keydir:
            c = SubmitAsc(env["APP_STORE_CONNECT_ISSUER_ID"], env["APP_STORE_CONNECT_KEY_IDENTIFIER"],
                         env["APP_STORE_CONNECT_PRIVATE_KEY"], keydir)
            return run(c, a)
    except Stop as e:
        print(f"::error::{e}")
        return 1
    except Unsure as e:
        print(f"::error::App Store Connect が書き込みに答えませんでした（{e}）。送り直していません。状態を確かめて流し直す")
        return 1
    except ApiError as e:
        hint = ""
        if e.status in (401, 403):
            hint = "（鍵が違う・鍵の役割が足りない。版を変えて審査に出すには App Manager 以上の鍵が要る）"
        elif e.status == 409:
            hint = "（App Store Connect が受け付けない変更。足りない欄・版の状態を App Store Connect で確かめる）"
        print(f"::error::App Store Connect が断りました: {e.status} {e.codes}{hint}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
