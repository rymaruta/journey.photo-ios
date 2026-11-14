#!/usr/bin/env python3
"""TestFlight のテスターが送った「落ちた記録」を App Store Connect API から取ってくる（2026-11-14・札 #596）。

    python3 -I Tools/testflight-crashes.py --version 1.1.85 --out <置く先（リポジトリの外）> [--limit 50]

呼ぶのは `Tools/testflight-crashes.sh`（`.github/workflows/testflight-crashes.yml`）。手で呼ぶことはない。

使う口（Apple の文書で確かめたもの・2026-11-14）:
  - GET /v1/apps?filter[bundleId]=…                         アプリの id
  - GET /v1/builds?filter[app]=…&filter[preReleaseVersion.version]=…   その版のビルド（ビルド番号は attributes.version）
  - GET /v1/apps/{id}/betaFeedbackCrashSubmissions?filter[build]=…&sort=-createdDate
                                                             テスターが送った落ちた記録（新しい順・1回 200 まで）
  - GET /v1/betaFeedbackCrashSubmissions/{id}/crashLog       その記録の本文（BetaCrashLog の attributes.logText）
  鍵（JWT）は「Generating Tokens for API Requests」のとおり ES256・kid・iss・aud=appstoreconnect-v1・20分以内。
  署名は openssl で作る（pip で何も入れない）

🔴 **公開リポジトリなので、記録の本文はログに出さない。** 本文・端末の型・利用者の書いた言葉・メール・テスターは
   `--out` のファイルにだけ置く（呼ぶ側が非公開の S3 に置いて消す）。標準出力に出すのは、件数と各件の
   版・ビルド・日時・例外の型・落ちたスレッドの上の数段の関数名だけ。テスターの名前・メールは取りにも行かない
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
FRAMES = 8  # ログに出す、落ちたスレッドの上からの段数

# 取りに行く欄（`email` と `tester` は取らない。利用者を指す情報で、落ちた原因には要らない）
SUBMISSION_FIELDS = ",".join([
    "createdDate", "comment", "deviceModel", "osVersion", "locale", "timeZone", "architecture",
    "connectionType", "appUptimeInMilliseconds", "batteryPercentage", "diskBytesAvailable",
    "diskBytesTotal", "screenWidthInPoints", "screenHeightInPoints", "appPlatform", "devicePlatform",
    "deviceFamily", "buildBundleId", "build", "crashLog",
])


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """openssl の ECDSA 署名（DER）を JWT の形（r と s を 32 バイトずつ）に直す。"""
    if len(der) < 8 or der[0] != 0x30:
        raise ValueError("署名の形が DER ではありません")
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("署名の形が DER の整数ではありません")
        n = der[i + 1]
        v = der[i + 2:i + 2 + n].lstrip(b"\x00")
        if len(v) > 32:
            raise ValueError("署名の整数が長すぎます")
        out += v.rjust(32, b"\x00")
        i += 2 + n
    return out


class Client:
    def __init__(self, issuer: str, key_id: str, key_pem: str, workdir: str):
        self.issuer, self.key_id = issuer, key_id
        # 秘密鍵は 600 のファイルにだけ置き、openssl に渡す（引数・ログに出さない）。終わったら呼ぶ側が消す
        if "-----BEGIN" in key_pem and "\n" not in key_pem.strip() and "\\n" in key_pem:
            key_pem = key_pem.replace("\\n", "\n")
        self.key_path = os.path.join(workdir, "asc.p8")
        fd = os.open(self.key_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(key_pem.strip() + "\n")
        self.token, self.minted = "", 0.0

    def jwt(self) -> str:
        now = time.time()
        if self.token and now - self.minted < 10 * 60:
            return self.token
        iat = int(now)
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {"iss": self.issuer, "iat": iat, "exp": iat + 15 * 60, "aud": "appstoreconnect-v1"}
        signing = (b64url(json.dumps(header, separators=(",", ":")).encode()) + "."
                   + b64url(json.dumps(payload, separators=(",", ":")).encode()))
        res = subprocess.run(["openssl", "dgst", "-sha256", "-sign", self.key_path],
                             input=signing.encode(), capture_output=True)
        if res.returncode != 0:
            raise SystemExit("NG: App Store Connect の鍵で署名できませんでした（APP_STORE_CONNECT_PRIVATE_KEY の形）")
        self.token, self.minted = signing + "." + b64url(der_to_raw(res.stdout)), now
        return self.token

    def get(self, path_or_url: str, params: dict | None = None) -> dict:
        url = path_or_url if path_or_url.startswith("https://") else API + path_or_url
        if params:
            url += "?" + urllib.parse.urlencode(params, safe="[],-")
        if not url.startswith(API + "/"):
            raise SystemExit("NG: App Store Connect の外の URL を引こうとしました")
        for attempt in range(5):
            req = urllib.request.Request(url, headers={"Authorization": f"Bearer {self.jwt()}",
                                                       "Accept": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    return json.load(r)
            except urllib.error.HTTPError as e:
                if e.code == 429 or e.code >= 500:
                    time.sleep(2 ** attempt * 3)
                    continue
                # 本文（detail）は出さない。種類（status・code）だけ
                codes = ""
                try:
                    codes = ",".join(sorted({x.get("code", "") for x in json.load(e).get("errors", [])}))
                except Exception:
                    pass
                raise ApiError(e.code, codes)
            except urllib.error.URLError:
                time.sleep(2 ** attempt * 3)
        raise SystemExit("NG: App Store Connect が何度引いても答えませんでした")


class ApiError(Exception):
    def __init__(self, status: int, codes: str):
        super().__init__(f"{status} {codes}")
        self.status, self.codes = status, codes


# ---- 記録の本文から、ログに出してよい要点だけを抜く ------------------------------------------

def clean(s: str, n: int = 160) -> str:
    s = re.sub(r"[\x00-\x1f\x7f]", " ", str(s)).strip()
    return s[:n]


def summarize(text: str) -> tuple[str, list[str], str]:
    """(例外の型, 落ちたスレッドの上の数段, 形) を返す。形は ips（JSON）か text（従来の .crash）。"""
    body = None
    stripped = text.lstrip()
    if stripped.startswith("{"):
        # .ips は「1行目に見出しの JSON・2行目から本体の JSON」。1つの JSON のこともある
        first, _, rest = stripped.partition("\n")
        for cand in (rest, stripped, first):
            try:
                d = json.loads(cand)
            except ValueError:
                continue
            if isinstance(d, dict) and ("threads" in d or "exception" in d):
                body = d
                break
    if body is not None:
        exc = body.get("exception") or {}
        etype = " ".join(x for x in [exc.get("type", ""), f"({exc['signal']})" if exc.get("signal") else ""] if x)
        images = body.get("usedImages") or []
        threads = body.get("threads") or []
        idx = body.get("faultingThread")
        thread = None
        if isinstance(idx, int) and 0 <= idx < len(threads):
            thread = threads[idx]
        else:
            thread = next((t for t in threads if t.get("triggered")), None)
        frames = []
        for f in (thread or {}).get("frames", [])[:FRAMES]:
            ii = f.get("imageIndex")
            img = images[ii].get("name", "?") if isinstance(ii, int) and 0 <= ii < len(images) else "?"
            if f.get("symbol"):
                where = f["symbol"]
                if f.get("sourceFile"):
                    where += f" ({f['sourceFile']}:{f.get('sourceLine', '?')})"
            else:
                where = f"+0x{int(f.get('imageOffset', 0)):x}（シンボル無し）"
            frames.append(clean(f"{img}: {where}"))
        return clean(etype or "（例外の型が無い）", 80), frames, "ips"

    m = re.search(r"^Exception Type:\s*(.+)$", text, re.M)
    etype = m.group(1) if m else "（例外の型が無い）"
    t = re.search(r"^(?:Triggered by Thread|Crashed Thread):\s*(\d+)", text, re.M)
    frames = []
    if t:
        sec = re.search(rf"^Thread {t.group(1)}(?: name:.*\nThread {t.group(1)})? Crashed:\s*\n((?:.+\n?)+?)(?:\n|\Z)",
                        text, re.M)
        if sec:
            for line in sec.group(1).splitlines()[:FRAMES]:
                fm = re.match(r"^\d+\s+(\S+)\s+0x[0-9a-fA-F]+\s+(.*)$", line)
                if fm:
                    frames.append(clean(f"{fm.group(1)}: {fm.group(2)}"))
    return clean(etype, 80), frames, "text"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=50)
    ap.add_argument("--bundle-id", default="com.journeyphoto.JourneyPhoto")
    a = ap.parse_args()
    if not re.fullmatch(r"\d+(\.\d+){1,3}", a.version):
        raise SystemExit(f"NG: 版の形が変です: {clean(a.version, 20)}（例 1.1.85）")
    limit = max(1, min(a.limit, 500))
    env = {k: os.environ.get(k, "") for k in
           ("APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_KEY_IDENTIFIER", "APP_STORE_CONNECT_PRIVATE_KEY")}
    missing = [k for k, v in env.items() if not v]
    if missing:
        raise SystemExit(f"NG: Secrets が足りません: {' '.join(missing)}")
    os.makedirs(a.out, mode=0o700, exist_ok=True)

    with tempfile.TemporaryDirectory() as keydir:
        c = Client(env["APP_STORE_CONNECT_ISSUER_ID"], env["APP_STORE_CONNECT_KEY_IDENTIFIER"],
                   env["APP_STORE_CONNECT_PRIVATE_KEY"], keydir)
        apps = c.get("/v1/apps", {"filter[bundleId]": a.bundle_id, "fields[apps]": "bundleId"})
        # 完全一致だけ（`…JourneyPhoto.staging` を拾わない・`Tools/app-apple-id.sh` と同じ考え）
        app_ids = [x["id"] for x in apps.get("data", []) if x.get("attributes", {}).get("bundleId") == a.bundle_id]
        if len(app_ids) != 1:
            raise SystemExit(f"NG: App Store Connect に {a.bundle_id} のアプリが1つに決まりません（{len(app_ids)} 件）")
        app_id = app_ids[0]

        builds = c.get("/v1/builds", {"filter[app]": app_id, "filter[preReleaseVersion.version]": a.version,
                                      "fields[builds]": "version,uploadedDate", "limit": 200})
        build_no = {b["id"]: b.get("attributes", {}).get("version", "?") for b in builds.get("data", [])}
        print(f"版 {a.version} のビルド: {len(build_no)} 本（ビルド番号 {', '.join(sorted(build_no.values(), key=lambda v: int(v) if v.isdigit() else 0)) or 'なし'}）")
        if not build_no:
            print("この版のビルドが App Store Connect に見つかりません（版の書き違い・期限切れで消えた）")
            return 3

        subs, url, params = [], f"/v1/apps/{app_id}/betaFeedbackCrashSubmissions", {
            "filter[build]": ",".join(build_no), "sort": "-createdDate",
            "fields[betaFeedbackCrashSubmissions]": SUBMISSION_FIELDS, "limit": min(limit, 200)}
        while url and len(subs) < limit:
            page = c.get(url, params)
            subs += page.get("data", [])
            url, params = (page.get("links") or {}).get("next"), None
        subs = subs[:limit]

        token = secrets.token_hex(16)
        # 記録の言葉が Actions の指示（`::…::`）として読まれないよう、要点を出す間は指示を止める
        print(f"::stop-commands::{token}")
        print(f"落ちた記録（テスターが送ったもの）: {len(subs)} 件（新しい順・上限 {limit}）")
        index = []
        for n, s in enumerate(subs, 1):
            attrs = s.get("attributes") or {}
            rel = (s.get("relationships") or {}).get("build", {}).get("data") or {}
            bno = build_no.get(rel.get("id", ""), "?")
            created = clean(attrs.get("createdDate", "?"), 40)
            log = ""
            try:
                cl = c.get(f"/v1/betaFeedbackCrashSubmissions/{s['id']}/crashLog",
                           {"fields[betaCrashLogs]": "logText"})
                log = ((cl.get("data") or {}).get("attributes") or {}).get("logText") or ""
            except ApiError as e:
                print(f"#{n} 本文を取れませんでした（{e.status} {e.codes}）")
            etype, frames, kind = summarize(log) if log else ("（本文なし）", [], "none")
            base = f"{n:03d}-{re.sub(r'[^0-9A-Za-z]', '', created)[:15]}-b{bno}"
            ext = {"ips": "ips", "text": "crash"}.get(kind, "txt")
            if log:
                with open(os.path.join(a.out, f"{base}.{ext}"), "w", encoding="utf-8") as f:
                    f.write(log)
            with open(os.path.join(a.out, f"{base}.json"), "w", encoding="utf-8") as f:
                json.dump({"version": a.version, "build": bno, "submission": s}, f, ensure_ascii=False, indent=2)
            index.append({"file": base, "build": bno, "createdDate": created, "exception": etype, "frames": frames})
            print(f"#{n} {a.version} ({bno}) {created} {etype}")
            for i, fr in enumerate(frames):
                print(f"    {i} {fr}")
            if log and not frames:
                print("    （落ちたスレッドを読み取れませんでした。本文は置き場のファイルで見る）")
        print(f"::{token}::")
        with open(os.path.join(a.out, "index.json"), "w", encoding="utf-8") as f:
            json.dump({"version": a.version, "count": len(subs), "items": index}, f, ensure_ascii=False, indent=2)
        with open(os.path.join(a.out, "count"), "w") as f:
            f.write(str(len(subs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
