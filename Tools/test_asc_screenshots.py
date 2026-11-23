#!/usr/bin/env python3
"""`asc-screenshots.py`（App Store の画面写真を入れ替える・札 #604）の回帰テスト。macOS/Xcode・ネット不要。

- 寸法から組（ScreenshotDisplayType）への振り分け・審査用の絵を上げない・寸法の合わない絵で止まる
- 版の状態の判定（PREPARE_FOR_SUBMISSION だけ。配信中・審査中は止まる・変える直前にも読み直す）
- 言語の列挙と計画（大型・中型を入れ替え、6.5 以前を空にし、iPad の組には触らない）
- 下見は何も書かない・表示にファイル名と枚数が出て、アップロードの URL が出ない
- 入れ替えのあと、全部 COMPLETE で 01 からの順に並ぶ
"""
import contextlib
import importlib.util
import io
import os
import pathlib
import struct
import tempfile
import unittest
import zlib

spec = importlib.util.spec_from_file_location("ascs", pathlib.Path(__file__).with_name("asc-screenshots.py"))
ascs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ascs)

UPLOAD_URL = "https://upload.example.invalid/secret-upload-path?Expires=1"


def png(path, w, h):
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    chunk = b"IHDR" + ihdr
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", len(ihdr)) + chunk
                + struct.pack(">I", zlib.crc32(chunk)) + b"rest")


def store_dir(root, large=("01-ホーム.png", "02-地図.png"), medium=("01-ホーム.png", "02-地図.png")):
    for n in large:
        png(os.path.join(root, n), 1320, 2868)
    png(os.path.join(root, "review-Pro の案内.png"), 1320, 2868)
    with open(os.path.join(root, "README.md"), "w") as f:
        f.write("x")
    os.makedirs(os.path.join(root, "medium-1206x2622"))
    for n in medium:
        png(os.path.join(root, "medium-1206x2622", n), 1206, 2622)
    return root


class FakeAsc:
    """App Store Connect の口のうち、この台本が使う分だけを覚えて答える。"""

    def __init__(self, state="PREPARE_FOR_SUBMISSION", locales=("ja", "en-US")):
        self.state = state
        self.after_read_state = None  # 下見のあと（最初の読みのあと）に状態を変える
        self.writes = []
        self.n = 0
        self.locs = {}
        self.sets = {}   # set id → {"loc", "type"}
        self.shots = {}  # shot id → {"set", "fileName", "state"}
        self.order = {}  # set id → [shot id]
        for loc in locales:
            lid = self.new("loc")
            self.locs[lid] = loc
            for kind, names in [("APP_IPHONE_67", ["old-a.png", "old-b.png"]), ("APP_IPHONE_65", ["old-65.png"]),
                                ("APP_IPAD_PRO_3GEN_129", ["ipad.png"])]:
                sid = self.new("set")
                self.sets[sid] = {"loc": lid, "type": kind}
                self.order[sid] = []
                for name in names:
                    self.add_shot(sid, name, "COMPLETE")

    def new(self, p):
        self.n += 1
        return f"{p}{self.n}"

    def add_shot(self, sid, name, state):
        xid = self.new("shot")
        self.shots[xid] = {"set": sid, "fileName": name, "state": state}
        # 上げた絵の並びは上げた順とは限らない（並べ直しの PATCH を守るため、新しい絵は前に入れる）
        if state == "AWAITING_UPLOAD":
            self.order[sid].insert(0, xid)
        else:
            self.order[sid].append(xid)
        return xid

    def version(self):
        return {"id": "ver1", "attributes": {"versionString": "1.1.119", "appVersionState": self.state,
                                               "appStoreState": self.state}}

    def get(self, path, params=None):
        if path.startswith("/v1/appStoreVersions/ver1"):
            if self.after_read_state:
                self.state = self.after_read_state
            return {"data": self.version()}
        if path == "/v1/apps":
            return {"data": [{"id": "app1", "attributes": {"bundleId": "com.journeyphoto.JourneyPhoto"}},
                             {"id": "app2", "attributes": {"bundleId": "com.journeyphoto.JourneyPhoto.staging"}}]}
        if path.startswith("/v1/appScreenshots/"):
            x = self.shots[path.rsplit("/", 1)[1]]
            if x["state"] == "UPLOAD_COMPLETE":
                x["state"] = "COMPLETE"
            return {"data": {"attributes": {"assetDeliveryState": {"state": x["state"]}}}}
        raise AssertionError(f"知らない GET: {path}")

    def get_all(self, path, params=None):
        if path == "/v1/apps/app1/appStoreVersions":
            assert params["filter[platform]"] == "IOS"
            return [self.version()] if params["filter[versionString]"] == "1.1.119" else []
        if path == "/v1/appStoreVersions/ver1/appStoreVersionLocalizations":
            return [{"id": lid, "attributes": {"locale": loc}} for lid, loc in self.locs.items()]
        if path.startswith("/v1/appStoreVersionLocalizations/"):
            lid = path.split("/")[3]
            return [{"id": sid, "attributes": {"screenshotDisplayType": s["type"]}}
                    for sid, s in self.sets.items() if s["loc"] == lid]
        if path.startswith("/v1/appScreenshotSets/"):
            sid = path.split("/")[3]
            return [{"id": x, "attributes": {"fileName": self.shots[x]["fileName"],
                                             "assetDeliveryState": {"state": self.shots[x]["state"]}}}
                    for x in self.order[sid]]
        raise AssertionError(f"知らない GET: {path}")

    def call(self, method, path, body=None):
        self.writes.append((method, path))
        if method == "DELETE" and path.startswith("/v1/appScreenshots/"):
            xid = path.rsplit("/", 1)[1]
            x = self.shots.pop(xid)
            self.order[x["set"]].remove(xid)
            return {}
        if method == "POST" and path == "/v1/appScreenshotSets":
            sid = self.new("set")
            rel = body["data"]["relationships"]["appStoreVersionLocalization"]["data"]["id"]
            self.sets[sid] = {"loc": rel, "type": body["data"]["attributes"]["screenshotDisplayType"]}
            self.order[sid] = []
            return {"data": {"id": sid}}
        if method == "POST" and path == "/v1/appScreenshots":
            d = body["data"]
            xid = self.add_shot(d["relationships"]["appScreenshotSet"]["data"]["id"], d["attributes"]["fileName"],
                                "AWAITING_UPLOAD")
            size = d["attributes"]["fileSize"]
            return {"data": {"id": xid, "attributes": {"uploadOperations": [
                {"method": "PUT", "url": UPLOAD_URL, "offset": 0, "length": size, "requestHeaders": []}]}}}
        if method == "PATCH" and path.startswith("/v1/appScreenshots/"):
            assert body["data"]["attributes"]["uploaded"] is True
            assert len(body["data"]["attributes"]["sourceFileChecksum"]) == 32
            self.shots[path.rsplit("/", 1)[1]]["state"] = "UPLOAD_COMPLETE"
            return {}
        if method == "PATCH" and path.endswith("/relationships/appScreenshots"):
            sid = path.split("/")[3]
            ids = [x["id"] for x in body["data"]]
            assert sorted(ids) == sorted(self.order[sid])
            self.order[sid] = ids
            return {}
        raise AssertionError(f"知らない書き込み: {method} {path}")

    def put_part(self, op, chunk):
        self.writes.append(("PUT", "upload"))


class Args:
    def __init__(self, apply):
        self.apply, self.bundle_id, self.version, self.timeout = apply, "com.journeyphoto.JourneyPhoto", "1.1.119", 5


def quiet(fn, *a):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        r = fn(*a)
    return r, out.getvalue()


class CollectTests(unittest.TestCase):
    def test_sizes_go_to_display_types_and_review_is_left_out(self):
        with tempfile.TemporaryDirectory() as d:
            files = ascs.collect(store_dir(d, large=("02-地図.png", "01-ホーム.png")))
            self.assertEqual([os.path.basename(p) for p in files["APP_IPHONE_67"]], ["01-ホーム.png", "02-地図.png"])
            self.assertTrue(all("medium-1206x2622" in p for p in files["APP_IPHONE_61"]))
            self.assertEqual(len(files["APP_IPHONE_61"]), 2)
            self.assertFalse(any("review-" in p for ps in files.values() for p in ps))

    def test_wrong_size_stops(self):
        with tempfile.TemporaryDirectory() as d:
            store_dir(d)
            png(os.path.join(d, "03-古い.png"), 1242, 2688)
            with self.assertRaisesRegex(ascs.Stop, "03-古い.png（1242×2688）"):
                ascs.collect(d)

    def test_missing_medium_or_too_many_stops(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ascs.Stop, "中型"):
                ascs.collect(store_dir(d, medium=()))
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ascs.Stop, "10 枚まで"):
                ascs.collect(store_dir(d, large=[f"{i:02d}-x.png" for i in range(11)]))

    def test_deeper_folders_are_not_read(self):
        with tempfile.TemporaryDirectory() as d:
            store_dir(d)
            os.makedirs(os.path.join(d, "medium-1206x2622", "deep"))
            png(os.path.join(d, "medium-1206x2622", "deep", "09-x.png"), 1206, 2622)
            self.assertEqual(len(ascs.collect(d)["APP_IPHONE_61"]), 2)


class StateTests(unittest.TestCase):
    def test_only_prepare_for_submission_passes(self):
        ascs.check_editable({"attributes": {"appVersionState": "PREPARE_FOR_SUBMISSION"}})
        for st in ("READY_FOR_SALE", "WAITING_FOR_REVIEW", "IN_REVIEW", "REJECTED", "READY_FOR_DISTRIBUTION"):
            with self.assertRaisesRegex(ascs.Stop, st):
                ascs.check_editable({"attributes": {"versionString": "1.0.87", "appVersionState": st}})

    def test_mixed_or_missing_state_stops(self):
        with self.assertRaises(ascs.Stop):
            ascs.check_editable({"attributes": {"appVersionState": "PREPARE_FOR_SUBMISSION",
                                                "appStoreState": "READY_FOR_SALE"}})
        with self.assertRaisesRegex(ascs.Stop, "読めません"):
            ascs.check_editable({"attributes": {}})


class PlanTests(unittest.TestCase):
    def test_plan_lists_all_locales_and_skips_ipad(self):
        fake = FakeAsc()
        locs = ascs.read_locales(fake, "ver1")
        files = {"APP_IPHONE_67": ["/x/01-a.png"], "APP_IPHONE_61": ["/x/m/01-a.png"]}
        plan = ascs.make_plan(locs, files)
        self.assertEqual([p["locale"] for p in plan], ["en-US", "ja"])
        for p in plan:
            kinds = {s["type"]: s for s in p["steps"]}
            self.assertEqual(set(kinds), {"APP_IPHONE_67", "APP_IPHONE_61", "APP_IPHONE_65"})
            self.assertEqual(len(kinds["APP_IPHONE_67"]["delete"]), 2)
            self.assertIsNone(kinds["APP_IPHONE_61"]["set_id"])  # 中型の組は無いので作る
            self.assertEqual(len(kinds["APP_IPHONE_65"]["delete"]), 1)
            self.assertEqual(kinds["APP_IPHONE_65"]["upload"], [])


class RunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.files = ascs.collect(store_dir(self.tmp.name))
        self.sleep = ascs.time.sleep
        ascs.time.sleep = lambda s: None

    def tearDown(self):
        ascs.time.sleep = self.sleep
        self.tmp.cleanup()

    def test_dry_run_writes_nothing_and_shows_names(self):
        fake = FakeAsc()
        r, out = quiet(ascs.run, fake, Args(False), self.files)
        self.assertEqual(r, 0)
        self.assertEqual(fake.writes, [])
        self.assertIn("下見", out)
        self.assertIn("+ 01-ホーム.png", out)
        self.assertIn("- old-65.png", out)
        self.assertNotIn("ipad.png", out)
        self.assertNotIn(self.tmp.name, out)

    def test_live_version_is_never_touched(self):
        fake = FakeAsc(state="READY_FOR_SALE")
        with self.assertRaisesRegex(ascs.Stop, "READY_FOR_SALE"):
            quiet(ascs.run, fake, Args(True), self.files)
        self.assertEqual(fake.writes, [])

    def test_state_is_read_again_before_writing(self):
        fake = FakeAsc()
        fake.after_read_state = "WAITING_FOR_REVIEW"
        with self.assertRaisesRegex(ascs.Stop, "WAITING_FOR_REVIEW"):
            quiet(ascs.run, fake, Args(True), self.files)
        self.assertEqual(fake.writes, [])

    def test_apply_replaces_and_reports_complete(self):
        fake = FakeAsc()
        r, out = quiet(ascs.run, fake, Args(True), self.files)
        self.assertEqual(r, 0, out)
        self.assertNotIn(UPLOAD_URL, out)
        self.assertNotIn("secret-upload-path", out)
        for lid, loc in fake.locs.items():
            by = {s["type"]: sid for sid, s in fake.sets.items() if s["loc"] == lid}
            names = lambda sid: [fake.shots[x]["fileName"] for x in fake.order[sid]]
            self.assertEqual(names(by["APP_IPHONE_67"]), ["01-ホーム.png", "02-地図.png"])
            self.assertEqual(names(by["APP_IPHONE_61"]), ["01-ホーム.png", "02-地図.png"])
            self.assertEqual(names(by["APP_IPHONE_65"]), [])
            self.assertEqual(names(by["APP_IPAD_PRO_3GEN_129"]), ["ipad.png"])
        self.assertIn("COMPLETE になりました", out)

    def test_old_set_left_over_is_red(self):
        fake = FakeAsc()
        orig_call = fake.call
        keep = {x for x, v in fake.shots.items() if fake.sets[v["set"]]["type"] == "APP_IPHONE_65"}

        def call(method, path, body=None):
            if method == "DELETE" and path.rsplit("/", 1)[1] in keep:
                return {}
            return orig_call(method, path, body)
        fake.call = call
        r, out = quiet(ascs.run, fake, Args(True), self.files)
        self.assertEqual(r, 1)
        self.assertIn("古い組に 1 枚残っています", out)

    def test_not_complete_is_red(self):
        fake = FakeAsc()
        orig = fake.get

        def stuck(path, params=None):
            if path.startswith("/v1/appScreenshots/"):
                return {"data": {"attributes": {"assetDeliveryState": {"state": "FAILED"}}}}
            return orig(path, params)
        fake.get = stuck
        orig_call = fake.call

        def call(method, path, body=None):
            r = orig_call(method, path, body)
            if method == "PATCH" and path.startswith("/v1/appScreenshots/"):
                fake.shots[path.rsplit("/", 1)[1]]["state"] = "FAILED"
            return r
        fake.call = call
        r, out = quiet(ascs.run, fake, Args(True), self.files)
        self.assertEqual(r, 1)
        self.assertIn("::error::", out)
        self.assertIn("COMPLETE でない", out)


class MainTests(unittest.TestCase):
    def test_apply_without_files_stops(self):
        r, out = quiet(ascs.main, ["--version", "1.1.119", "--apply"])
        self.assertEqual(r, 1)
        self.assertIn("絵が無いまま入れ替えはしません", out)

    def test_bad_version_stops(self):
        r, out = quiet(ascs.main, ["--version", "1.1.119;x"])
        self.assertEqual(r, 1)
        self.assertIn("版の形が変です", out)


if __name__ == "__main__":
    unittest.main()
