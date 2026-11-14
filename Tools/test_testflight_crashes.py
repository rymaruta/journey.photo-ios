#!/usr/bin/env python3
"""`testflight-crashes.py`（TestFlight の落ちた記録を取る・札 #596）の回帰テスト。macOS/Xcode・ネット不要。

- JWT が Apple の決まり（ES256・kid・iss・aud・20分以内）で、openssl で検証できる署名になっていること
- 記録の本文（.ips の JSON・従来の .crash の文）から、例外の型と落ちたスレッドの上の数段を抜けること
- 🔴 標準出力（Actions の公開ログ）に、本文・端末の型・利用者の書いた言葉・端末の識別子が出ないこと
"""
import base64
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("tfc", pathlib.Path(__file__).with_name("testflight-crashes.py"))
tfc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tfc)


def ub(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def der_int(b: bytes) -> bytes:
    b = b.lstrip(b"\x00") or b"\x00"
    if b[0] & 0x80:
        b = b"\x00" + b
    return b"\x02" + bytes([len(b)]) + b


IPS_HEADER = {"app_name": "JourneyPhoto", "app_version": "1.1.85", "build_version": "1", "bug_type": "309"}
IPS_BODY = {
    "exception": {"type": "EXC_BREAKPOINT", "signal": "SIGTRAP"},
    "faultingThread": 1,
    "crashReporterKey": "SECRETDEVICEKEY",
    "usedImages": [{"name": "JourneyPhoto"}, {"name": "libswiftCore.dylib"}],
    "threads": [
        {"frames": [{"imageIndex": 1, "imageOffset": 1}]},
        {"triggered": True, "frames": [
            {"imageIndex": 1, "imageOffset": 4660, "symbol": "_assertionFailure(_:_:file:line:flags:)"},
            {"imageIndex": 0, "imageOffset": 74565, "symbol": "StoryViewer.body.getter",
             "sourceFile": "StoryViewer.swift", "sourceLine": 120},
            {"imageIndex": 0, "imageOffset": 3054},
        ]},
    ],
}
IPS = json.dumps(IPS_HEADER) + "\n" + json.dumps(IPS_BODY, indent=2)
TEXT = """Incident Identifier: SECRET-UUID
Hardware Model:      iPhone16,1
Exception Type:  EXC_CRASH (SIGABRT)
Triggered by Thread:  0

Thread 0 name:   Dispatch queue: com.apple.main-thread
Thread 0 Crashed:
0   libsystem_kernel.dylib        \t0x00000001e1d3a1d4 __pthread_kill + 8
1   JourneyPhoto                  \t0x0000000102a8c3e0 0x102a80000 + 50144
2   JourneyPhoto                  \t0x0000000102a8c3e0 StoryPlayer.start() + 44 (StoryPlayer.swift:88)

Thread 1:
0   libsystem_kernel.dylib 0x1 x
"""


class JwtTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        d = self.dir.name
        subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", f"{d}/k.pem"],
                       check=True, capture_output=True)
        subprocess.run(["openssl", "pkcs8", "-topk8", "-nocrypt", "-in", f"{d}/k.pem", "-out", f"{d}/k.p8"],
                       check=True, capture_output=True)
        subprocess.run(["openssl", "ec", "-in", f"{d}/k.pem", "-pubout", "-out", f"{d}/pub.pem"],
                       check=True, capture_output=True)
        self.p8 = pathlib.Path(f"{d}/k.p8").read_text()

    def tearDown(self):
        self.dir.cleanup()

    def check(self, key: str):
        with tempfile.TemporaryDirectory() as kd:
            c = tfc.Client("ISS", "KID123", key, kd)
            for _ in range(20):  # r・s の頭が 0 の回（短い整数）も混ざる回数
                c.token = ""
                h, p, s = c.jwt().split(".")
                raw = ub(s)
                self.assertEqual(len(raw), 64)
                der = der_int(raw[:32]) + der_int(raw[32:])
                sig = pathlib.Path(self.dir.name, "sig")
                sig.write_bytes(b"\x30" + bytes([len(der)]) + der)
                r = subprocess.run(["openssl", "dgst", "-sha256", "-verify", f"{self.dir.name}/pub.pem",
                                    "-signature", str(sig)], input=f"{h}.{p}".encode(), capture_output=True)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertEqual(json.loads(ub(h)), {"alg": "ES256", "kid": "KID123", "typ": "JWT"})
                pl = json.loads(ub(p))
                self.assertEqual((pl["iss"], pl["aud"]), ("ISS", "appstoreconnect-v1"))
                self.assertLessEqual(pl["exp"] - pl["iat"], 20 * 60)

    def test_signs_with_real_newlines(self):
        self.check(self.p8)

    def test_signs_with_escaped_newlines(self):
        self.check(self.p8.strip().replace("\n", "\\n"))


class SummarizeTests(unittest.TestCase):
    def test_ips(self):
        etype, frames, kind = tfc.summarize(IPS)
        self.assertEqual((kind, etype), ("ips", "EXC_BREAKPOINT (SIGTRAP)"))
        self.assertEqual(frames, [
            "libswiftCore.dylib: _assertionFailure(_:_:file:line:flags:)",
            "JourneyPhoto: StoryViewer.body.getter (StoryViewer.swift:120)",
            "JourneyPhoto: +0xbee（シンボル無し）",
        ])

    def test_text(self):
        etype, frames, kind = tfc.summarize(TEXT)
        self.assertEqual((kind, etype), ("text", "EXC_CRASH (SIGABRT)"))
        self.assertEqual(frames, [
            "libsystem_kernel.dylib: __pthread_kill + 8",
            "JourneyPhoto: 0x102a80000 + 50144",
            "JourneyPhoto: StoryPlayer.start() + 44 (StoryPlayer.swift:88)",
        ])


class MainTests(unittest.TestCase):
    def test_log_has_only_the_summary(self):
        calls = []
        nxt = "https://api.appstoreconnect.apple.com/v1/apps/A1/betaFeedbackCrashSubmissions?cursor=x"

        def fake_get(self, path, params=None):
            calls.append((path, params))
            pages = {
                "/v1/apps": {"data": [
                    {"id": "A1", "attributes": {"bundleId": "com.journeyphoto.JourneyPhoto"}},
                    {"id": "A2", "attributes": {"bundleId": "com.journeyphoto.JourneyPhoto.staging"}}]},
                "/v1/builds": {"data": [{"id": "B1", "attributes": {"version": "1"}},
                                        {"id": "B2", "attributes": {"version": "2"}}]},
                "/v1/apps/A1/betaFeedbackCrashSubmissions": {
                    "data": [{"id": "S1", "attributes": {"createdDate": "2026-11-13T10:00:00.000Z",
                                                         "comment": "SECRETCOMMENT", "deviceModel": "iPhone16,1"},
                              "relationships": {"build": {"data": {"type": "builds", "id": "B2"}}}}],
                    "links": {"next": nxt}},
                nxt: {"data": [{"id": "S2", "attributes": {"createdDate": "2026-11-12T10:00:00Z"},
                                "relationships": {"build": {"data": {"id": "B1"}}}}], "links": {}},
                "/v1/betaFeedbackCrashSubmissions/S1/crashLog": {"data": {"attributes": {"logText": IPS}}},
                "/v1/betaFeedbackCrashSubmissions/S2/crashLog": {"data": {"attributes": {"logText": TEXT}}},
            }
            return pages[path]

        old_get, old_argv = tfc.Client.get, list(os.sys.argv)
        tfc.Client.get = fake_get
        env = {"APP_STORE_CONNECT_ISSUER_ID": "I", "APP_STORE_CONNECT_KEY_IDENTIFIER": "K",
               "APP_STORE_CONNECT_PRIVATE_KEY": "-----BEGIN PRIVATE KEY-----\nx\n-----END PRIVATE KEY-----"}
        old_env = {k: os.environ.get(k) for k in env}
        os.environ.update(env)
        try:
            with tempfile.TemporaryDirectory() as out:
                os.sys.argv = ["x", "--version", "1.1.85", "--out", out]
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    self.assertEqual(tfc.main(), 0)
                log = buf.getvalue()
                for secret in ("SECRET", "iPhone16", "Incident", "crashReporterKey"):
                    self.assertNotIn(secret, log)
                self.assertIn("#1 1.1.85 (2) 2026-11-13T10:00:00.000Z EXC_BREAKPOINT (SIGTRAP)", log)
                self.assertIn("StoryViewer.body.getter (StoryViewer.swift:120)", log)
                self.assertIn("#2 1.1.85 (1) 2026-11-12T10:00:00Z EXC_CRASH (SIGABRT)", log)
                # 要点は Actions の指示を止めた間だけに出す
                self.assertRegex(log, r"::stop-commands::([0-9a-f]{32})\n(?:.*\n)*::\1::\n")
                files = sorted(os.listdir(out))
                self.assertEqual(pathlib.Path(out, "count").read_text(), "2")
                self.assertTrue(any(f.endswith(".ips") for f in files) and any(f.endswith(".crash") for f in files))
                # 本文は置き場のファイルにだけある
                self.assertIn("SECRETDEVICEKEY", pathlib.Path(out, next(f for f in files if f.endswith(".ips"))).read_text())
        finally:
            tfc.Client.get, os.sys.argv = old_get, old_argv
            for k, v in old_env.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
        sub = next(p for path, p in calls if path == "/v1/apps/A1/betaFeedbackCrashSubmissions")
        self.assertEqual(sub["filter[build]"], "B1,B2")
        fields = sub["fields[betaFeedbackCrashSubmissions]"].split(",")
        self.assertNotIn("email", fields)
        self.assertNotIn("tester", fields)


if __name__ == "__main__":
    unittest.main()
