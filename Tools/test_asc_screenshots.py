#!/usr/bin/env python3
"""`asc-screenshots.py`（App Store の画面写真を入れ替える・札 #604）の回帰テスト。macOS/Xcode・ネット不要。

- 寸法から組（ScreenshotDisplayType）への振り分け・審査用の絵を上げない・寸法の合わない絵で止まる
- 版の状態の判定（PREPARE_FOR_SUBMISSION だけ。配信中・審査中は止まる・変える直前にも読み直す）・アプリと版名の完全一致
- 渡した言語だけを入れ替え、ほかの言語は消さない・作らない。版に無い言語は作らずに止まる
- 組ごとに COMPLETE でなければその場で止め、古い組は大型と中型がそろうまで消さない。止まっても今の組を出す
- 10枚以下なら先に上げて後で消す。分割の送りが length どおり。uploadOperations が空なら止まる
- 書き込み（POST・DELETE）を送り直さない。DELETE の 404 は消せたとみなす。届いたか分からなければ読み直す
- 下見は何も書かない・表示にファイル名と枚数が出て、アップロードの URL が出ない
"""
import contextlib
import importlib.util
import io
import os
import pathlib
import struct
import tempfile
import unittest
import urllib.error
import zlib

spec = importlib.util.spec_from_file_location("ascs", pathlib.Path(__file__).with_name("asc-screenshots.py"))
ascs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ascs)

UPLOAD_URL = "https://upload.example.invalid/secret-upload-path?Expires=1"


def png(path, w, h, extra=b"rest"):
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    chunk = b"IHDR" + ihdr
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", len(ihdr)) + chunk
                + struct.pack(">I", zlib.crc32(chunk)) + extra)


def store_dir(root, large=("01-ホーム.png", "02-地図.png"), medium=("01-ホーム.png", "02-地図.png")):
    for n in large:
        png(os.path.join(root, n), 1320, 2868, extra=os.urandom(100))
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
        self.apps = [{"id": "app1", "attributes": {"bundleId": "com.journeyphoto.JourneyPhoto"}},
                     {"id": "app2", "attributes": {"bundleId": "com.journeyphoto.JourneyPhoto.staging"}}]
        self.version_names = ["1.1.119"]
        self.split = 1           # 送り方を何個に分けるか
        self.ops_override = None  # uploadOperations をこれに差し替える
        self.processed = {}      # 上げた絵の名前 → 処理のあとの状態（無ければ COMPLETE）
        self.writes = []
        self.chunks = []
        self.n = 0
        self.locs = {}
        self.sets = {}   # set id → {"loc", "type"}
        self.shots = {}  # shot id → {"set", "fileName", "state"}
        self.order = {}  # set id → [shot id]
        self.blobs = {}  # shot id → 送られた中身
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

    def loc_id(self, locale):
        return next(k for k, v in self.locs.items() if v == locale)

    def names(self, locale, kind):
        sid = next((s for s, v in self.sets.items() if v["loc"] == self.loc_id(locale) and v["type"] == kind), None)
        return None if sid is None else [self.shots[x]["fileName"] for x in self.order[sid]]

    def version(self, name="1.1.119"):
        return {"id": "ver1" if name == "1.1.119" else "ver-" + name,
                "attributes": {"versionString": name, "appVersionState": self.state, "appStoreState": self.state}}

    def get(self, path, params=None):
        if path.startswith("/v1/appStoreVersions/ver1"):
            if self.after_read_state:
                self.state = self.after_read_state
            return {"data": self.version()}
        if path == "/v1/apps":
            return {"data": self.apps}
        if path.startswith("/v1/appScreenshots/"):
            xid = path.rsplit("/", 1)[1]
            if xid not in self.shots:
                raise ascs.ApiError(404, "NOT_FOUND")
            x = self.shots[xid]
            if x["state"] == "UPLOAD_COMPLETE":
                x["state"] = self.processed.get(x["fileName"], "COMPLETE")
            return {"data": {"attributes": {"assetDeliveryState": {"state": x["state"]}}}}
        raise AssertionError(f"知らない GET: {path}")

    def get_all(self, path, params=None):
        if path == "/v1/apps/app1/appStoreVersions":
            assert params["filter[platform]"] == "IOS"
            return [self.version(n) for n in self.version_names]  # 絞り込みは信じない（前方一致で返っても拾わない）
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
            step = -(-size // self.split)
            ops = [{"method": "PUT", "url": UPLOAD_URL, "offset": off, "length": min(step, size - off),
                    "requestHeaders": [{"name": "Content-Type", "value": "image/png"}], "_id": xid}
                   for off in range(0, size, step)]
            if self.ops_override is not None:
                ops = self.ops_override
            return {"data": {"id": xid, "attributes": {"uploadOperations": ops}}}
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
        self.chunks.append((op["offset"], op["length"], chunk))


class Args:
    def __init__(self, apply, locales="ja,en-US"):
        self.apply, self.bundle_id, self.version, self.budget = apply, "com.journeyphoto.JourneyPhoto", "1.1.119", 300
        self.locales = locales


def quiet(fn, *a):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        r = fn(*a)
    return r, out.getvalue()


def quiet_stop(test, fn, *a, pattern=""):
    """Stop で止まることを確かめ、それまでに出た表示を返す。"""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        with test.assertRaisesRegex(ascs.Stop, pattern):
            fn(*a)
    return out.getvalue()


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

    def test_other_sizes_and_folder_names_go_by_size(self):
        # 機種で寸法が変わる（大型 1290×2796、中型 1179×2556）。置き場の名前（medium/）には頼らない
        with tempfile.TemporaryDirectory() as d:
            png(os.path.join(d, "01-ホーム.png"), 1290, 2796)
            png(os.path.join(d, "02-地図.png"), 1260, 2736)
            os.makedirs(os.path.join(d, "medium"))
            png(os.path.join(d, "medium", "01-ホーム.png"), 1179, 2556)
            png(os.path.join(d, "medium", "02-地図.png"), 1206, 2622)
            files = ascs.collect(d)
            self.assertEqual([os.path.basename(p) for p in files["APP_IPHONE_67"]], ["01-ホーム.png", "02-地図.png"])
            self.assertEqual([os.path.relpath(p, d) for p in files["APP_IPHONE_61"]],
                             [os.path.join("medium", "01-ホーム.png"), os.path.join("medium", "02-地図.png")])

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

    def test_two_apps_stop(self):
        fake = FakeAsc()
        fake.apps = [{"id": "app1", "attributes": {"bundleId": "com.journeyphoto.JourneyPhoto"}},
                     {"id": "app3", "attributes": {"bundleId": "com.journeyphoto.JourneyPhoto"}}]
        with self.assertRaisesRegex(ascs.Stop, "1つに決まりません（2 件）"):
            ascs.find_version(fake, "com.journeyphoto.JourneyPhoto", "1.1.119")

    def test_version_name_must_match_exactly(self):
        fake = FakeAsc()
        fake.version_names = ["1.1.11", "1.1.1190", "1.1.119"]
        self.assertEqual(ascs.find_version(fake, "com.journeyphoto.JourneyPhoto", "1.1.119")["id"], "ver1")
        fake.version_names = ["1.1.1190"]
        with self.assertRaisesRegex(ascs.Stop, "版 1.1.119 がありません"):
            ascs.find_version(fake, "com.journeyphoto.JourneyPhoto", "1.1.119")


class LocaleTests(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(ascs.parse_locales(" ja , en-US,ja"), ["ja", "en-US"])
        for bad in ("", "ja;rm", "日本"):
            with self.assertRaises(ascs.Stop):
                ascs.parse_locales(bad)

    def test_plan_only_has_given_locales_and_skips_ipad(self):
        fake = FakeAsc(locales=("ja", "en-US", "fr-FR"))
        locs = ascs.pick_locales(ascs.read_locales(fake, "ver1"), ["ja"])
        files = {"APP_IPHONE_67": ["/x/01-a.png"], "APP_IPHONE_61": ["/x/m/01-a.png"]}
        plan = ascs.make_plan(locs, files)
        self.assertEqual([p["locale"] for p in plan], ["ja"])
        kinds = {s["type"]: s for s in plan[0]["steps"]}
        self.assertEqual(set(kinds), {"APP_IPHONE_67", "APP_IPHONE_61", "APP_IPHONE_65"})
        self.assertIsNone(kinds["APP_IPHONE_61"]["set_id"])  # 中型の組は無いので作る
        self.assertEqual(kinds["APP_IPHONE_65"]["upload"], [])

    def test_missing_locale_stops_without_creating(self):
        fake = FakeAsc(locales=("ja",))
        with self.assertRaisesRegex(ascs.Stop, "en-US がありません"):
            ascs.pick_locales(ascs.read_locales(fake, "ver1"), ["ja", "en-US"])


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
        fake = FakeAsc(locales=("ja", "en-US", "fr-FR"))
        r, out = quiet(ascs.run, fake, Args(False), self.files)
        self.assertEqual(r, 0)
        self.assertEqual(fake.writes, [])
        self.assertIn("下見", out)
        self.assertIn("+ 01-ホーム.png", out)
        self.assertIn("- old-65.png", out)
        self.assertIn("触らない言語: fr-FR", out)
        self.assertNotIn("ipad.png", out)
        self.assertNotIn(self.tmp.name, out)

    def test_live_version_is_never_touched(self):
        fake = FakeAsc(state="READY_FOR_SALE")
        quiet_stop(self, ascs.run, fake, Args(True), self.files, pattern="READY_FOR_SALE")
        self.assertEqual(fake.writes, [])

    def test_state_is_read_again_before_writing(self):
        fake = FakeAsc()
        fake.after_read_state = "WAITING_FOR_REVIEW"
        quiet_stop(self, ascs.run, fake, Args(True), self.files, pattern="WAITING_FOR_REVIEW")
        self.assertEqual(fake.writes, [])

    def test_apply_replaces_given_locales_only(self):
        fake = FakeAsc(locales=("ja", "en-US", "fr-FR"))
        r, out = quiet(ascs.run, fake, Args(True, "ja,en-US"), self.files)
        self.assertEqual(r, 0, out)
        self.assertNotIn("secret-upload-path", out)
        for loc in ("ja", "en-US"):
            self.assertEqual(fake.names(loc, "APP_IPHONE_67"), ["01-ホーム.png", "02-地図.png"])
            self.assertEqual(fake.names(loc, "APP_IPHONE_61"), ["01-ホーム.png", "02-地図.png"])
            self.assertEqual(fake.names(loc, "APP_IPHONE_65"), [])
            self.assertEqual(fake.names(loc, "APP_IPAD_PRO_3GEN_129"), ["ipad.png"])
        # 渡していない言語は消さない・作らない
        self.assertEqual(fake.names("fr-FR", "APP_IPHONE_67"), ["old-a.png", "old-b.png"])
        self.assertEqual(fake.names("fr-FR", "APP_IPHONE_65"), ["old-65.png"])
        self.assertIsNone(fake.names("fr-FR", "APP_IPHONE_61"))
        self.assertIn("COMPLETE になりました", out)
        self.assertIn("-- ja 6.9インチ（大型）: 今 2 枚 → 2 枚を始めます（先に上げて後で消す）", out)

    def test_upload_first_when_ten_or_less_else_delete_first(self):
        fake = FakeAsc(locales=("ja",))
        quiet(ascs.run, fake, Args(True, "ja"), self.files)
        big = [w for w in fake.writes if w[0] in ("POST", "DELETE")]
        first_post = next(i for i, w in enumerate(big) if w == ("POST", "/v1/appScreenshots"))
        first_del = next(i for i, w in enumerate(big) if w[0] == "DELETE")
        self.assertLess(first_post, first_del)  # 2+2 ≦ 10 なので先に上げる
        with tempfile.TemporaryDirectory() as d:
            files = ascs.collect(store_dir(d, large=[f"{i:02d}-x.png" for i in range(9)]))
            fake = FakeAsc(locales=("ja",))
            r, out = quiet(ascs.run, fake, Args(True, "ja"), files)
            self.assertEqual(r, 0, out)
            big = [w for w in fake.writes if w[0] in ("POST", "DELETE")]
            self.assertEqual(big[0][0], "DELETE")  # 2+9 > 10 なので先に消す
            self.assertEqual(len(fake.names("ja", "APP_IPHONE_67")), 9)

    def test_not_complete_stops_there_and_keeps_old_sets(self):
        fake = FakeAsc(locales=("ja",))
        fake.processed = {"02-地図.png": "FAILED"}
        out = quiet_stop(self, ascs.run, fake, Args(True, "ja"), self.files, pattern="大型）: COMPLETE にならない絵が 1 枚（FAILED）")
        # 大型で止まる: 中型は始めない・古い組（6.5）は消さない・先に上げたので今の大型の絵も残っている
        self.assertIsNone(fake.names("ja", "APP_IPHONE_61"))
        self.assertEqual(fake.names("ja", "APP_IPHONE_65"), ["old-65.png"])
        self.assertIn("old-a.png", fake.names("ja", "APP_IPHONE_67"))
        # 止まっても今の組を出す
        self.assertIn("== 入れ替えたあとの組", out)
        self.assertIn("ja 6.5インチ（Face ID 大型）: 1 枚", out)

    def test_old_set_left_over_is_red(self):
        fake = FakeAsc(locales=("ja",))
        orig_call = fake.call
        keep = {x for x, v in fake.shots.items() if fake.sets[v["set"]]["type"] == "APP_IPHONE_65"}

        def call(method, path, body=None):
            if method == "DELETE" and path.rsplit("/", 1)[1] in keep:
                return {}
            return orig_call(method, path, body)
        fake.call = call
        r, out = quiet(ascs.run, fake, Args(True, "ja"), self.files)
        self.assertEqual(r, 1)
        self.assertIn("古い組に 1 枚残っています", out)


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "01-ホーム.png")
        png(self.path, 1320, 2868, extra=os.urandom(1000))
        self.fake = FakeAsc(locales=("ja",))
        self.sid = next(s for s, v in self.fake.sets.items() if v["type"] == "APP_IPHONE_67")

    def tearDown(self):
        self.tmp.cleanup()

    def test_split_parts_match_length(self):
        self.fake.split = 3
        ascs.upload_one(self.fake, self.sid, self.path)
        blob = pathlib.Path(self.path).read_bytes()
        self.assertEqual(len(self.fake.chunks), 3)
        for off, length, chunk in self.fake.chunks:
            self.assertEqual(len(chunk), length)
            self.assertEqual(chunk, blob[off:off + length])
        self.assertEqual(b"".join(c for _, _, c in sorted(self.fake.chunks)), blob)

    def test_empty_or_wrong_operations_stop(self):
        self.fake.ops_override = []
        with self.assertRaisesRegex(ascs.Stop, "uploadOperations"):
            ascs.upload_one(self.fake, self.sid, self.path)
        size = os.path.getsize(self.path)
        self.fake.ops_override = [{"method": "PUT", "url": UPLOAD_URL, "offset": 0, "length": size - 10}]
        with self.assertRaisesRegex(ascs.Stop, "区切り"):
            ascs.upload_one(self.fake, self.sid, self.path)
        self.assertEqual(self.fake.chunks, [])

    def test_unsure_post_is_not_resent_and_reservation_is_removed(self):
        orig = self.fake.call
        posts = []

        def call(method, path, body=None):
            if method == "POST" and path == "/v1/appScreenshots":
                posts.append(1)
                orig(method, path, body)  # 届いたが答えが返らなかった
                raise ascs.Unsure("POST 503")
            return orig(method, path, body)
        self.fake.call = call
        with self.assertRaisesRegex(ascs.Stop, "予約が届いたか分かりません"):
            ascs.upload_one(self.fake, self.sid, self.path)
        self.assertEqual(len(posts), 1)
        self.assertNotIn("01-ホーム.png", [v["fileName"] for v in self.fake.shots.values()])

    def test_unsure_set_creation_reads_back(self):
        orig = self.fake.call

        def call(method, path, body=None):
            if method == "POST" and path == "/v1/appScreenshotSets":
                orig(method, path, body)
                raise ascs.Unsure("POST つながらない")
            return orig(method, path, body)
        self.fake.call = call
        lid = self.fake.loc_id("ja")
        sid = ascs.create_set(self.fake, lid, "APP_IPHONE_61")
        self.assertEqual(self.fake.sets[sid]["type"], "APP_IPHONE_61")
        self.assertEqual(sum(1 for v in self.fake.sets.values() if v["type"] == "APP_IPHONE_61"), 1)


class CallTests(unittest.TestCase):
    """`Asc.call` が POST・DELETE を送り直さず、DELETE の 404 を消せたとみなすこと（urlopen を差し替える）。"""

    def setUp(self):
        self.c = ascs.Asc.__new__(ascs.Asc)
        self.c.jwt = lambda: "t"
        self.sent = []
        self.urlopen = ascs.urllib.request.urlopen
        self.sleep = ascs.time.sleep
        ascs.time.sleep = lambda s: None

    def tearDown(self):
        ascs.urllib.request.urlopen = self.urlopen
        ascs.time.sleep = self.sleep

    def fail_with(self, code):
        def urlopen(req, timeout=0):
            self.sent.append(req.get_method())
            raise urllib.error.HTTPError(req.full_url, code, "x", {}, io.BytesIO(b'{"errors":[{"code":"E"}]}'))
        ascs.urllib.request.urlopen = urlopen

    def test_post_and_delete_are_not_resent(self):
        self.fail_with(503)
        for method in ("POST", "DELETE"):
            self.sent.clear()
            with self.assertRaises(ascs.Unsure):
                self.c.call(method, "/v1/appScreenshots", {"data": {}} if method == "POST" else None)
            self.assertEqual(self.sent, [method])

    def test_patch_is_resent(self):
        self.fail_with(503)
        with self.assertRaises(ascs.Stop):
            self.c.call("PATCH", "/v1/appScreenshots/x", {"data": {}})
        self.assertEqual(len(self.sent), 5)

    def test_delete_404_is_done(self):
        self.fail_with(404)
        self.assertEqual(self.c.call("DELETE", "/v1/appScreenshots/x"), {})
        with self.assertRaises(ascs.ApiError):
            self.c.call("POST", "/v1/appScreenshots", {"data": {}})


class MainTests(unittest.TestCase):
    def test_apply_without_files_stops(self):
        r, out = quiet(ascs.main, ["--version", "1.1.119", "--apply"])
        self.assertEqual(r, 1)
        self.assertIn("絵が無いまま入れ替えはしません", out)

    def test_bad_version_or_locale_stops(self):
        r, out = quiet(ascs.main, ["--version", "1.1.119;x"])
        self.assertEqual(r, 1)
        self.assertIn("版の形が変です", out)
        r, out = quiet(ascs.main, ["--version", "1.1.119", "--locales", "ja;x"])
        self.assertEqual(r, 1)
        self.assertIn("言語の形が変です", out)


if __name__ == "__main__":
    unittest.main()
