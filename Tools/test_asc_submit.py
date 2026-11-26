#!/usr/bin/env python3
"""`asc-submit.py`（App Store の審査に出す・札 #604）の回帰テスト。macOS/Xcode・ネット不要。

- 公開中（READY_FOR_SALE）の版には書かない。書き込みの行き先にも中身にも、その版の id が入らない
- 下見（apply なし）では何も書かない。「今 → 入れる」が出る
- 審査の情報に送るのは notes の欄だけ（審査用のアカウントのパスワードは送らない・ログに出さない）
- 申請用の版が無ければ作る（下見では作ると出すだけ）。名前が違えば直す。2つあれば止める。公開中の版より古い版は止める
- 書く直前に状態が変わったら（審査に出された）止める
- 画面写真・審査用のアカウントがそろっていなければ審査に出さない
- もう審査に出ている版は何も書かずに終える
- 販売をやめた定期購入は問題として出す。進んでいる申請があるときは定期購入だけを出さない。初めての定期購入を単独で出さない
- 下見で、利用規約のリンクか EULA、プライバシーポリシーの URL、定期購入でない課金の商品を確かめる（読むだけ）
"""
import contextlib
import copy
import importlib.util
import io
import json
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("ascsub", pathlib.Path(__file__).with_name("asc-submit.py"))
sub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sub)

LIVE = "ver-live"
PASSWORD = "secret-demo-password-xyz"
DEMO_NAME = "reviewer@example.invalid"


def shot(i, name, state="COMPLETE"):
    return {"id": f"shot{i}", "attributes": {"fileName": name, "assetDeliveryState": {"state": state}}}


class Fake:
    def __init__(self, editable=("1.2.0", "PREPARE_FOR_SUBMISSION"), shots=True, demo=True, subs="APPROVED"):
        self.versions = {LIVE: {"versionString": "1.0.87", "appVersionState": "READY_FOR_SALE",
                                "appStoreState": "READY_FOR_SALE"}}
        if editable:
            self.versions["ver-edit"] = {"versionString": editable[0], "appVersionState": editable[1],
                                         "appStoreState": editable[1]}
        self.writes = []
        self.state_after_reads = None  # 何回か読んだあとに申請用の版の状態を変える
        self.reads = 0
        self.locs = {"loc-ja": {"locale": "ja", "whatsNew": "前の文",
                                "description": "説明\n利用規約 https://journey-photo.com/terms", "keywords": "旅"},
                     "loc-en": {"locale": "en-US", "whatsNew": "",
                                "description": "desc\nTerms https://journey-photo.com/terms", "keywords": "trip"}}
        self.eula = None  # 404（EULA の欄が空）
        self.privacy = {"ja": "https://journey-photo.com/privacy", "en-US": "https://journey-photo.com/privacy"}
        self.iaps = []
        self.review = {"notes": "old notes", "demoAccountRequired": demo, "demoAccountName": DEMO_NAME if demo else "",
                       "demoAccountPassword": PASSWORD if demo else "", "contactFirstName": "A",
                       "contactLastName": "B", "contactPhone": "+81 90", "contactEmail": "a@example.invalid"}
        self.build = None
        self.phased = None
        self.shots = shots
        self.subs = subs
        self.submissions = {}

    # ---- 読む
    def get(self, path, params=None):
        self.reads += 1
        if self.state_after_reads is not None and self.reads > self.state_after_reads and "ver-edit" in self.versions:
            self.versions["ver-edit"]["appVersionState"] = self.versions["ver-edit"]["appStoreState"] = "WAITING_FOR_REVIEW"
        if path == "/v1/apps":
            return {"data": [{"id": "app1", "attributes": {"bundleId": "com.journeyphoto.JourneyPhoto"}}]}
        if path == "/v1/builds":
            assert params["filter[preReleaseVersion.version]"] == "1.2.6"
            return {"data": [{"id": "build-old", "attributes": {"version": "1", "uploadedDate": "2026-11-24T01:00",
                                                                "processingState": "VALID", "expired": False}},
                             {"id": "build-new", "attributes": {"version": "2", "uploadedDate": "2026-11-25T01:00",
                                                                "processingState": "VALID", "expired": False}}]}
        parts = path.split("/")
        if path.startswith("/v1/appStoreVersions/") and len(parts) == 4:
            return {"data": {"id": parts[3], "attributes": dict(self.versions[parts[3]])}}
        if path.endswith("/build"):
            return {"data": self.build}
        if path.endswith("/appStoreReviewDetail"):
            if self.review is None:
                return {"data": None}
            return {"data": {"id": "rd1", "attributes": copy.deepcopy(self.review)}}
        if path.endswith("/appStoreVersionPhasedRelease"):
            return {"data": self.phased}
        if path.startswith("/v1/reviewSubmissions/"):
            return {"data": {"id": parts[3], "attributes": {"state": self.submissions[parts[3]]}}}
        # 定期購入の中身（下見で読む・2026-11-25）: 値段なし、審査用の画面写真なし、販売する国や地域はあり
        if path.startswith("/v1/subscriptions/") and path.endswith("/prices"):
            return {"data": []}
        if path.startswith("/v1/subscriptions/") and path.endswith("/appStoreReviewScreenshot"):
            return {"data": None}
        if path == "/v1/apps/app1/endUserLicenseAgreement":
            if self.eula is None:
                raise sub.ApiError(404, "NOT_FOUND")
            return {"data": self.eula}
        if path.startswith("/v1/subscriptions/") and path.endswith("/subscriptionAvailability"):
            if getattr(self, "no_availability", False):
                raise sub.ApiError(404, "NOT_FOUND")
            return {"data": {"id": "av1"}}
        raise AssertionError(f"知らない GET: {path}")

    def get_all(self, path, params=None):
        self.reads += 1
        if path == "/v1/apps/app1/appStoreVersions":
            return [{"id": k, "attributes": dict(v)} for k, v in self.versions.items()]
        if path.endswith("/appStoreVersionLocalizations"):
            assert "ver-edit" in path or "ver-new" in path, path
            return [{"id": k, "attributes": dict(v)} for k, v in self.locs.items()]
        if path.startswith("/v1/appStoreVersionLocalizations/") and path.endswith("/appScreenshotSets"):
            if not self.shots:
                return []
            return [{"id": f"set-{path.split('/')[3]}-67", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}},
                    {"id": f"set-{path.split('/')[3]}-61", "attributes": {"screenshotDisplayType": "APP_IPHONE_61"}}]
        if path.startswith("/v1/appScreenshotSets/"):
            return [shot(1, "01-ホーム.png"), shot(2, "02-AI に頼む.png")]
        if path == "/v1/apps/app1/subscriptionGroups":
            return [{"id": "grp1"}]
        if path == "/v1/subscriptionGroups/grp1/subscriptions":
            return [{"id": "subm", "attributes": {"productId": "pro.monthly", "state": self.subs}},
                    {"id": "suby", "attributes": {"productId": "pro.yearly", "state": self.subs}}]
        if path == "/v1/reviewSubmissions":
            return [{"id": k, "attributes": {"state": v}} for k, v in self.submissions.items()]
        if path == "/v1/subscriptionGroups/grp1/subscriptionGroupLocalizations":
            return [{"id": "gl1", "attributes": {"locale": "ja"}}]
        if path.startswith("/v1/subscriptions/") and path.endswith("/subscriptionLocalizations"):
            return [{"id": "sl1", "attributes": {"locale": "en-US"}}]
        if path == "/v1/apps/app1/inAppPurchasesV2":
            return list(self.iaps)
        if path == "/v1/apps/app1/appInfos":
            return [{"id": "info-live", "attributes": {"state": "READY_FOR_DISTRIBUTION"}}]
        if path == "/v1/appInfos/info-live/appInfoLocalizations":
            return [{"id": f"il-{k}", "attributes": {"locale": k, "privacyPolicyUrl": v}} for k, v in self.privacy.items()]
        if path.endswith("/items"):
            return []
        raise AssertionError(f"知らない GET: {path}")

    # ---- 書く
    def call(self, method, path, body=None):
        self.writes.append((method, path, copy.deepcopy(body)))
        d = (body or {}).get("data") or {}
        if method == "POST" and path == "/v1/appStoreVersions":
            self.versions["ver-new"] = {"versionString": d["attributes"]["versionString"],
                                        "appVersionState": "PREPARE_FOR_SUBMISSION",
                                        "appStoreState": "PREPARE_FOR_SUBMISSION"}
            return {"data": {"id": "ver-new"}}
        if method == "PATCH" and path.startswith("/v1/appStoreVersions/") and path.count("/") == 3:
            self.versions[path.split("/")[3]]["versionString"] = d["attributes"]["versionString"]
            return {}
        if method == "PATCH" and path.startswith("/v1/appStoreVersionLocalizations/"):
            self.locs[path.split("/")[3]]["whatsNew"] = d["attributes"]["whatsNew"]
            return {}
        if method == "PATCH" and path.endswith("/relationships/build"):
            self.build = {"id": d["id"], "attributes": {"version": "2", "uploadedDate": "2026-11-25T01:00"}}
            return {}
        if method == "PATCH" and path.startswith("/v1/appStoreReviewDetails/"):
            self.review.update(d["attributes"])
            return {}
        if method == "POST" and path == "/v1/appStoreVersionPhasedReleases":
            self.phased = {"id": "ph1", "attributes": {"phasedReleaseState": "INACTIVE"}}
            return {"data": self.phased}
        if method == "POST" and path == "/v1/subscriptionSubmissions":
            return {"data": {"id": "ss1"}}
        if method == "POST" and path == "/v1/reviewSubmissions":
            self.submissions["rs1"] = "READY_FOR_REVIEW"
            return {"data": {"id": "rs1"}}
        if method == "POST" and path == "/v1/reviewSubmissionItems":
            return {"data": {"id": "item1"}}
        if method == "PATCH" and path.startswith("/v1/reviewSubmissions/"):
            self.submissions[path.split("/")[3]] = "WAITING_FOR_REVIEW"
            for v in self.versions.values():
                if v["appVersionState"] == "PREPARE_FOR_SUBMISSION":
                    v["appVersionState"] = v["appStoreState"] = "WAITING_FOR_REVIEW"
            return {}
        raise AssertionError(f"知らない書き込み: {method} {path}")


class Args:
    def __init__(self, apply, version="1.2.6", no_submit=False):
        self.apply, self.version, self.no_submit = apply, version, no_submit
        self.bundle_id = "com.journeyphoto.JourneyPhoto"


def go(fake, args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        try:
            code = sub.run(fake, args)
        except sub.Stop as e:
            print(f"STOP {e}")
            code = "stop"
    return code, out.getvalue()


def touches_live(fake):
    return [w for w in fake.writes if LIVE in w[1] or LIVE in json.dumps(w[2] or {})]


class Test(unittest.TestCase):
    def test_dry_run_writes_nothing_and_shows_now_and_new(self):
        f = Fake()
        code, out = go(f, Args(apply=False))
        self.assertEqual(code, 0, out)
        self.assertEqual(f.writes, [])
        self.assertIn("下見", out)
        self.assertIn("今: 1.2.0", out)
        self.assertIn("入れる: 1.2.6", out)
        self.assertIn("今: 「前の文」", out)
        self.assertIn("旅の本棚", out)
        self.assertIn("ビルド 2", out)
        self.assertIn("1.0.87: READY_FOR_SALE（書きません）", out)

    def test_dry_run_without_version_says_create(self):
        f = Fake(editable=None)
        code, out = go(f, Args(apply=False))
        self.assertEqual(code, 0, out)
        self.assertEqual(f.writes, [])
        self.assertIn("版 1.2.6 を作る", out)

    def test_apply_full_never_touches_live(self):
        f = Fake(subs="READY_TO_SUBMIT")
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, 0, out)
        self.assertEqual(touches_live(f), [])
        methods = [(m, p) for m, p, _ in f.writes]
        self.assertIn(("PATCH", "/v1/appStoreVersions/ver-edit"), methods)
        self.assertIn(("PATCH", "/v1/appStoreVersions/ver-edit/relationships/build"), methods)
        self.assertIn(("POST", "/v1/reviewSubmissionItems"), methods)
        self.assertEqual(methods[-1], ("PATCH", "/v1/reviewSubmissions/rs1"))
        self.assertEqual(sum(1 for m, p in methods if p == "/v1/subscriptionSubmissions"), 2)
        build = next(b for m, p, b in f.writes if p.endswith("/relationships/build"))
        self.assertEqual(build["data"]["id"], "build-new")
        self.assertEqual(f.versions[LIVE]["versionString"], "1.0.87")
        self.assertIn("WAITING_FOR_REVIEW", out)

    def test_review_detail_sends_only_notes_and_hides_password(self):
        f = Fake()
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, 0, out)
        rd = [b for m, p, b in f.writes if p.startswith("/v1/appStoreReviewDetails/")]
        self.assertEqual(len(rd), 1)
        self.assertEqual(set(rd[0]["data"]["attributes"]), {"notes"})
        self.assertTrue(rd[0]["data"]["attributes"]["notes"].startswith("Journey Photo is a social network"))
        self.assertEqual(f.review["demoAccountPassword"], PASSWORD)
        self.assertNotIn(PASSWORD, out)
        self.assertNotIn(DEMO_NAME, out)

    def test_writer_refuses_live_id(self):
        w = sub.Writer(Fake(), True, {LIVE})
        with self.assertRaises(sub.Stop):
            w.call("PATCH", f"/v1/appStoreVersions/{LIVE}", {"data": {}})
        with self.assertRaises(sub.Stop):
            w.call("POST", "/v1/reviewSubmissionItems", {"data": {"relationships": {"appStoreVersion": {
                "data": {"type": "appStoreVersions", "id": LIVE}}}}})
        with self.assertRaises(sub.Stop):
            sub.Writer(Fake(), False, set()).call("PATCH", "/v1/x", {})

    def test_only_live_version_named_same_stops(self):
        f = Fake(editable=None)
        code, out = go(f, Args(apply=True, version="1.0.87"))
        self.assertEqual(code, "stop", out)
        self.assertEqual(f.writes, [])

    def test_older_than_live_stops(self):
        f = Fake(editable=None)
        code, out = go(f, Args(apply=True, version="1.0.5"))
        self.assertEqual(code, "stop", out)
        self.assertEqual(f.writes, [])

    def test_two_editable_stops(self):
        f = Fake()
        f.versions["ver-edit2"] = {"versionString": "1.2.1", "appVersionState": "PREPARE_FOR_SUBMISSION",
                                   "appStoreState": "PREPARE_FOR_SUBMISSION"}
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, "stop", out)
        self.assertEqual(f.writes, [])

    def test_create_when_missing(self):
        f = Fake(editable=None)
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, 0, out)
        first = f.writes[0]
        self.assertEqual(first[:2], ("POST", "/v1/appStoreVersions"))
        self.assertEqual(first[2]["data"]["attributes"]["versionString"], "1.2.6")
        self.assertEqual(touches_live(f), [])

    def test_state_change_before_write_stops(self):
        f = Fake()
        f.state_after_reads = 4  # 最初の読み（アプリ・版・定期購入）のあとで審査に出された
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, "stop", out)
        self.assertEqual(f.writes, [])

    def test_missing_screenshots_does_not_submit(self):
        f = Fake(shots=False)
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, 1, out)
        self.assertFalse([w for w in f.writes if "reviewSubmission" in w[1]])
        self.assertIn("画面写真", out)

    def test_missing_demo_account_does_not_submit(self):
        f = Fake(demo=False)
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, 1, out)
        self.assertFalse([w for w in f.writes if "reviewSubmission" in w[1]])
        rd = [b for m, p, b in f.writes if p.startswith("/v1/appStoreReviewDetails/")]
        self.assertTrue(all(set(b["data"]["attributes"]) == {"notes"} for b in rd))

    def test_no_review_detail_does_not_create_one(self):
        f = Fake()
        f.review = None
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, 1, out)
        self.assertFalse([w for w in f.writes if "ReviewDetail" in w[1] or "reviewSubmission" in w[1]])

    def test_no_submit_stops_before_review(self):
        f = Fake()
        code, out = go(f, Args(apply=True, no_submit=True))
        self.assertEqual(code, 0, out)
        self.assertFalse([w for w in f.writes if "reviewSubmission" in w[1] or "subscriptionSubmissions" in w[1]])

    def test_already_submitted_writes_nothing(self):
        f = Fake(editable=("1.2.6", "WAITING_FOR_REVIEW"))
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, 0, out)
        self.assertEqual(f.writes, [])
        self.assertIn("もう審査に出ています", out)

    def test_other_submission_in_progress_stops(self):
        f = Fake()
        f.submissions["rs-other"] = "WAITING_FOR_REVIEW"
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, "stop", out)
        self.assertFalse([w for w in f.writes if "reviewSubmission" in w[1]])

    def test_dry_run_lists_what_subscriptions_lack(self):
        """審査の差し戻し 2.1(b)（2026-11-25）: 下見で、定期購入に足りないもの（値段・審査用の画面写真・言語）を出す。書かない"""
        f = Fake(subs="MISSING_METADATA")
        code, out = go(f, Args(apply=False))
        self.assertEqual(f.writes, [])
        self.assertIn("定期購入 pro.monthly: MISSING_METADATA", out)
        self.assertIn("pro.monthly: 審査用の画面写真がありません", out)
        self.assertIn("pro.yearly: 値段が決まっていません", out)
        self.assertIn("pro.monthly: 表示名と説明（ja）がありません", out)
        self.assertNotIn("販売する国や地域が決まっていません", out)

    def test_availability_404_means_not_set(self):
        """販売する国や地域を決めていない定期購入は 404 が返る（run 45664927348）。読めないではなく「決まっていない」"""
        f = Fake(subs="MISSING_METADATA")
        f.no_availability = True
        code, out = go(f, Args(apply=False))
        self.assertEqual(f.writes, [])
        self.assertIn("pro.monthly: 販売する国や地域が決まっていません", out)

    def test_dry_run_skips_details_of_approved_subscriptions(self):
        f = Fake(subs="APPROVED")
        code, out = go(f, Args(apply=False))
        self.assertEqual(f.writes, [])
        self.assertNotIn("審査用の画面写真がありません", out)

    def test_removed_from_sale_is_a_problem(self):
        """販売をやめた定期購入は、そのままでよいとしない（審査の人が Pro を買えない・2026-11-26）"""
        for state in ("DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE"):
            self.assertNotIn(state, sub.SUB_OK)
            f = Fake(subs=state)
            code, out = go(f, Args(apply=False))
            self.assertEqual(f.writes, [])
            self.assertIn(f"::warning::定期購入 pro.monthly は販売をやめています（{state}）", out)
            self.assertIn("pro.yearly: 販売をやめています", out)
            f = Fake(subs=state)
            code, out = go(f, Args(apply=True))
            self.assertEqual(code, 1, out)
            self.assertFalse([w for w in f.writes if "reviewSubmission" in w[1]])

    def test_busy_submission_does_not_submit_subscriptions_alone(self):
        """進んでいる申請があって版を出せないとき、定期購入だけを先に出さない"""
        f = Fake(subs="READY_TO_SUBMIT")
        f.submissions["rs-other"] = "WAITING_FOR_REVIEW"
        code, out = go(f, Args(apply=True))
        self.assertEqual(code, "stop", out)
        self.assertFalse([w for w in f.writes if "subscriptionSubmissions" in w[1]])

    def test_first_subscription_alone_stops(self):
        subs = [{"id": "subm", "productId": "pro.monthly", "state": "READY_TO_SUBMIT", "group": "grp1"}]
        steps, _ = sub.plan_subscriptions(subs)
        f = Fake()
        w = sub.Writer(f, True, {LIVE})
        with self.assertRaises(sub.Stop) as e:
            sub.submit_subscriptions(w, f, "ver-edit", steps, subs, with_version=False)
        self.assertIn("版と一緒に出す", str(e.exception))
        self.assertEqual(f.writes, [])
        # 一度承認された定期購入があれば、単独で出してよい
        approved = subs + [{"id": "suby", "productId": "pro.yearly", "state": "APPROVED", "group": "grp1"}]
        with contextlib.redirect_stdout(io.StringIO()):
            sub.submit_subscriptions(w, f, "ver-edit", steps, approved, with_version=False)
        self.assertEqual([p for m, p, _ in f.writes], ["/v1/subscriptionSubmissions"])

    def test_no_submit_says_first_subscription_goes_with_version(self):
        f = Fake(subs="READY_TO_SUBMIT")
        code, out = go(f, Args(apply=True, no_submit=True))
        self.assertEqual(code, 0, out)
        self.assertIn("初めての定期購入は版と一緒に出す", out)
        self.assertFalse([w for w in f.writes if "subscriptionSubmissions" in w[1]])

    def test_dry_run_listing_all_good_has_no_listing_warnings(self):
        f = Fake()
        code, out = go(f, Args(apply=False))
        self.assertEqual(f.writes, [])
        self.assertNotIn("利用規約:", out)
        self.assertNotIn("プライバシーポリシーの URL が空", out)
        self.assertNotIn("定期購入でない課金の商品が", out)
        self.assertIn("すべての言語にあり", out)

    def test_dry_run_warns_terms_missing_without_eula(self):
        f = Fake()
        f.locs["loc-en"]["description"] = "desc without link"
        code, out = go(f, Args(apply=False))
        self.assertEqual(f.writes, [])
        self.assertIn("::warning::利用規約: 説明文（en-US）に journey-photo.com/terms が無く", out)
        # EULA の欄が埋まっていれば、説明文にリンクが無くてもよい
        f = Fake()
        f.locs["loc-en"]["description"] = "desc without link"
        f.eula = {"id": "eula1", "attributes": {"agreementText": "..."}}
        code, out = go(f, Args(apply=False))
        self.assertNotIn("::warning::利用規約", out)

    def test_dry_run_warns_empty_privacy_url(self):
        f = Fake()
        f.privacy["en-US"] = ""
        code, out = go(f, Args(apply=False))
        self.assertEqual(f.writes, [])
        self.assertIn("::warning::プライバシーポリシーの URL が空です（en-US", out)

    def test_dry_run_warns_non_subscription_iap(self):
        f = Fake()
        f.iaps = [{"id": "iap1", "attributes": {"productId": "coins.100", "state": "MISSING_METADATA",
                                                "inAppPurchaseType": "CONSUMABLE"}}]
        code, out = go(f, Args(apply=False))
        self.assertEqual(f.writes, [])
        self.assertIn("::warning::定期購入でない課金の商品が 1 件あります", out)

    def test_texts_fit_and_have_no_nakaguro(self):
        for loc, text in sub.WHATS_NEW.items():
            self.assertLessEqual(len(text), sub.MAX_TEXT)
            self.assertNotIn("・", text)
            self.assertNotIn("撮影スポット", text)
            self.assertNotIn("撮りどき", text)
        self.assertLessEqual(len(sub.review_notes()), sub.MAX_TEXT)

    def test_review_notes_say_what_reviewers_trip_on(self):
        """申請し直す前に直した審査メモ（2026-11-26）。消すと落ちる。言葉の判定の行を入れても 4,000 字に収まる"""
        notes = sub.review_notes()
        for line in (
            "After the first post or follow, a short explanation appears with one button that leads to the iOS prompt; "
            "declining keeps the app fully usable.",
            "Supporter badge is granted for production purchases only; in Sandbox, Pro features work but the badge is not shown.",
            "A subscription bought with a sandbox Apple ID stays with the account that bought it; after deleting the demo "
            "account, please use a different sandbox Apple ID to test Pro.",
            'an explanation with a single "Continue" button and the iOS prompt',
            "While on, swapping continues with the app closed.",
            "iTunes Search API", "Apple Music", '"Report this answer"', "an account (email, Apple or Google)",
        ):
            self.assertIn(line, notes)
        # 言葉の判定（サーバーの `content_rejected`・2026-11-26 から本番）。今の範囲を言う
        self.assertIn("- Text in posts, comments, profiles, messages, stories and trip plans is checked on our server; "
                      "abusive words are blocked.", notes)
        self.assertLessEqual(len(notes), sub.MAX_TEXT)
        doc = sub.REVIEW_DOC.read_text(encoding="utf-8")
        self.assertNotIn("### 入ったら足す文", doc, "入れ終えた文の節を残さない")
        self.assertIn(f"（{len(notes):,}字。", doc, "頭の字数を貼る文に合わせる")

if __name__ == "__main__":
    unittest.main()
