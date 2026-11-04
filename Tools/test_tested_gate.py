#!/usr/bin/env python3
"""`tested_gate.py`（上げる前の関門と、PR の検証の「テスト済みか」の共通の判定）の回帰テスト。Linux だけで動く。

GitHub の API は呼ばず、`api(path)` を差し替えて確かめる。実際の動きは GitHub で流さないと確かめられない。
"""
import pathlib
import re
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import tested_gate as g  # noqa: E402

try:
    import yaml
except ModuleNotFoundError:  # pragma: no cover
    yaml = None

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = "o/r"


def job(name, conclusion="success", steps=()):
    return {"name": name, "conclusion": conclusion, "steps": [{"name": n, "conclusion": c} for n, c in steps]}


def make_api(tf_runs=(), pr_runs=(), jobs=None, trees=None):
    """tf_runs / pr_runs: [{id, head_sha, conclusion}]。jobs: {run_id: [job]}。trees: {sha: tree}"""
    jobs, trees = jobs or {}, trees or {}
    calls = []

    def api(path):
        calls.append(path)
        if "/workflows/ios-testflight.yml/runs" in path:
            m = re.search(r"head_sha=([0-9a-z]+)", path)
            runs = [r for r in tf_runs if not m or r["head_sha"] == m.group(1)]
            return {"workflow_runs": runs}
        if "/workflows/ios-pr.yml/runs" in path:
            return {"workflow_runs": list(pr_runs)}
        m = re.search(r"/actions/runs/(\d+)/jobs", path)
        if m:
            return {"jobs": jobs.get(int(m.group(1)), [])}
        m = re.search(r"/commits/([0-9a-z]+)$", path)
        if m:
            t = trees.get(m.group(1))
            return {"commit": {"tree": {"sha": t}}} if t else None
        return None
    api.calls = calls
    return api


MARK = job("build", steps=[(g.MARK_STEP, "success")])
XCODE = job(g.XCODE_JOB)


class Judge(unittest.TestCase):
    def test_nothing_found_stops(self):
        ok, reason = g.judge("m1", "T", REPO, make_api())
        self.assertFalse(ok)
        self.assertIn("記録が見つからない", reason)

    def test_unreadable_tree_stops(self):
        self.assertFalse(g.judge("m1", "", REPO, make_api())[0])

    def test_api_failure_stops(self):
        self.assertFalse(g.judge("m1", "T", REPO, lambda path: None)[0])

    def test_pr_xcode_success_on_same_tree_passes_even_if_commit_differs(self):
        api = make_api(pr_runs=[{"id": 1, "head_sha": "h1", "conclusion": "success"}], jobs={1: [XCODE]}, trees={"h1": "T"})
        ok, reason = g.judge("m1", "T", REPO, api)
        self.assertTrue(ok, reason)

    def test_pr_xcode_failure_or_skipped_does_not_count(self):
        # #476: Xcode の検査が終わる前にマージされた木。failure / skipped / 実行中は数えない
        for c in ("failure", "skipped", "cancelled", None):
            api = make_api(pr_runs=[{"id": 1, "head_sha": "h1", "conclusion": "failure"}],
                           jobs={1: [job(g.XCODE_JOB, c)]}, trees={"h1": "T"})
            self.assertFalse(g.judge("m1", "T", REPO, api)[0], c)

    def test_pr_success_on_other_tree_does_not_count(self):
        api = make_api(pr_runs=[{"id": 1, "head_sha": "h1", "conclusion": "success"}], jobs={1: [XCODE]}, trees={"h1": "OTHER"})
        self.assertFalse(g.judge("m1", "T", REPO, api)[0])

    def test_other_job_named_similarly_does_not_count(self):
        api = make_api(pr_runs=[{"id": 1, "head_sha": "h1", "conclusion": "success"}],
                       jobs={1: [job("静的な検査")]}, trees={"h1": "T"})
        self.assertFalse(g.judge("m1", "T", REPO, api)[0])

    def test_mac_testflight_run_on_same_sha_passes(self):
        api = make_api(tf_runs=[{"id": 5, "head_sha": "m1", "conclusion": "cancelled"}], jobs={5: [MARK]})
        self.assertTrue(g.judge("m1", "T", REPO, api)[0])

    def test_mac_testflight_run_on_same_tree_passes(self):
        api = make_api(tf_runs=[{"id": 5, "head_sha": "h9", "conclusion": "success"}], jobs={5: [MARK]}, trees={"h9": "T"})
        self.assertTrue(g.judge("m1", "T", REPO, api)[0])

    def test_failed_testflight_run_or_missing_mark_does_not_count(self):
        api = make_api(tf_runs=[{"id": 5, "head_sha": "m1", "conclusion": "failure"}], jobs={5: [MARK]})
        self.assertFalse(g.judge("m1", "T", REPO, api)[0])
        api = make_api(tf_runs=[{"id": 5, "head_sha": "m1", "conclusion": "success"}], jobs={5: [job("build", steps=[(g.MARK_STEP, "skipped")])]})
        self.assertFalse(g.judge("m1", "T", REPO, api)[0])

    def test_mark_in_either_job_counts(self):
        # 分けて流す回は「まとめ」の job に印がある。流れなかった方は skipped でよい
        api = make_api(tf_runs=[{"id": 5, "head_sha": "m1", "conclusion": "success"}],
                       jobs={5: [job("build", steps=[(g.MARK_STEP, "skipped")]), job("finish", steps=[(g.MARK_STEP, "success")])]})
        self.assertTrue(g.judge("m1", "T", REPO, api)[0])

    def test_same_path_is_not_fetched_twice(self):
        runs = [{"id": i, "head_sha": "h", "conclusion": "success"} for i in range(1, 6)]
        api = make_api(pr_runs=runs, jobs={}, trees={"h": "OTHER"})
        g.judge("m1", "T", REPO, api)
        commit_calls = [c for c in api.calls if c.endswith("/commits/h")]
        self.assertEqual(len(commit_calls), 1)


class Message(unittest.TestCase):
    def test_refusal_says_what_is_missing_and_how_to_proceed(self):
        msg = g.refusal_message("abc", "T", "記録が見つからない")
        for word in ("足りない検査", g.XCODE_JOB, "skip_tested_gate=true", "abc"):
            self.assertIn(word, msg)


@unittest.skipIf(yaml is None, "PyYAML が無い")
class WorkflowShape(unittest.TestCase):
    """YAML の形: 名前が ios-testflight.yml / ios-pr.yml とずれたら、関門が黙って何も通さなくなる。"""

    def load(self, name):
        return yaml.safe_load((ROOT / ".github/workflows" / name).read_text(encoding="utf-8"))

    def test_names_match_the_workflows(self):
        tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text(encoding="utf-8")
        pr = (ROOT / ".github/workflows/ios-pr.yml").read_text(encoding="utf-8")
        self.assertIn(f"name: {g.MARK_STEP}", tf)
        self.assertIn(f"name: {g.XCODE_JOB}", pr)

    def test_gate_job_blocks_upload(self):
        tf = self.load("ios-testflight.yml")
        gate, build = tf["jobs"]["gate"], tf["jobs"]["build"]
        self.assertEqual(build["needs"], "gate")
        # 関門が failure なら build は動かない・上げない回（gate が skipped）は動く
        self.assertIn("needs.gate.result != 'failure'", build["if"])
        self.assertIn("inputs.submit", gate["if"])
        self.assertEqual(gate["permissions"].get("actions"), "read")
        text = "\n".join(s.get("run", "") for s in gate["steps"])
        self.assertIn("tested_gate.py gate", text)
        self.assertIn("skip_tested_gate", " ".join(str(s.get("env", {})) for s in gate["steps"]))

    def test_skip_input_defaults_to_false_in_all_entrances(self):
        tf = self.load("ios-testflight.yml")
        on = tf.get("on") or tf.get(True)
        for entrance in ("workflow_dispatch", "workflow_call"):
            spec = on[entrance]["inputs"]["skip_tested_gate"]
            self.assertIs(spec["default"], False, entrance)
            self.assertEqual(spec["type"], "boolean")
        rc = self.load("release-center.yml")
        self.assertIn("skip_tested_gate", rc["jobs"]["pipeline"]["with"])

    def test_pr_tested_job_uses_the_shared_judgement(self):
        pr = self.load("ios-pr.yml")
        text = "\n".join(s.get("run", "") for s in pr["jobs"]["tested"]["steps"])
        self.assertIn("tested_gate.py mac-run", text)
        # 判定を2つ作らない: 印の段の名前を、ワークフロー側に直書きしない
        self.assertNotIn(g.MARK_STEP, text)


if __name__ == "__main__":
    unittest.main(verbosity=1)
