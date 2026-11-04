#!/usr/bin/env python3
"""`workflow_lint.py` の回帰テスト（Linux だけで動く）。

「壊れた入力で落ちること」を、実際に踏んだ事故の形で1つずつ確かめる。
最後に、いまの作業ツリー（main の写し）が NG 0 件であること。
"""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import workflow_lint as w  # noqa: E402

try:
    import yaml
except ModuleNotFoundError:  # pragma: no cover
    yaml = None

NEEDS_YAML = unittest.skipIf(yaml is None, "PyYAML が無い")


def doc(run=None, shell=None, extra_job=None, top=None):
    """1 job だけのワークフロー（permissions・timeout 付き）を作る。"""
    step = {"name": "t"}
    if run is not None:
        step["run"] = run
    if shell:
        step["shell"] = shell
    job = {"runs-on": "ubuntu-latest", "timeout-minutes": 5, "steps": [step]}
    job.update(extra_job or {})
    d = {"permissions": {"contents": "read"}, "jobs": {"j": job}}
    d.update(top or {})
    return d


def lint(d, root=None):
    root = root or pathlib.Path(tempfile.mkdtemp())
    return w.lint_doc(root / ".github/workflows/x.yml", d, root)


class BashSyntax(unittest.TestCase):
    def test_451_find_with_double_backslash_paren_fails(self):
        # #451（#818・#819・#825）: ios-testflight.yml の `build` と `finish` に入っていた行
        bad = "find build/logs -type f \\\\( -iname '*.png' -o -iname '*.jpg' \\\\) -delete 2>/dev/null || true\n"
        errs = lint(doc(bad))
        self.assertEqual(len(errs), 1, errs)
        self.assertIn("bash の構文エラー", errs[0])

    def test_451_fixed_form_passes(self):
        ok = "find build/logs -type f \\( -iname '*.png' -o -iname '*.jpg' \\) -delete 2>/dev/null || true\n"
        self.assertEqual(lint(doc(ok)), [])

    def test_expression_is_replaced_not_parsed(self):
        self.assertEqual(lint(doc('echo "${{ github.event.pull_request.head.sha }}" && [ "${{ inputs.x }}" = true ]')), [])

    def test_unclosed_quote_fails(self):
        self.assertEqual(len(lint(doc("echo 'abc\n"))), 1)

    def test_other_shell_is_skipped(self):
        self.assertEqual(lint(doc("def broken(:\n  pass(\n", shell="python")), [])

    def test_job_default_shell_other_than_bash_is_skipped(self):
        d = doc("print('x'", extra_job={"defaults": {"run": {"shell": "python"}}})
        self.assertEqual(lint(d), [])

    def test_composite_action_run_is_checked(self):
        action = {"runs": {"using": "composite", "steps": [{"run": "if true; then\n", "shell": "bash"}]}}
        errs = lint(action)
        self.assertEqual(len(errs), 1, errs)


class PythonSyntax(unittest.TestCase):
    def test_literal_backslash_n_in_py_fails(self):
        # #466（#824）: `pick-ui-tests.py` に改行ではなく文字どおりの `\n` が入った
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "Tools").mkdir()
            (root / "Tools/pick.py").write_text("for p in x:\\n    pass\n", encoding="utf-8")
            (root / "Tools/ok.py").write_text("x = 1\n", encoding="utf-8")
            errs = w.python_errors(root)
            self.assertEqual(len(errs), 1, errs)
            self.assertIn("Tools/pick.py", errs[0])


class References(unittest.TestCase):
    def test_missing_tool_script_fails(self):
        errs = lint(doc("bash Tools/nope.sh arg\npython3 Tools/nope.py\n"))
        self.assertEqual(len(errs), 2, errs)

    def test_existing_tool_script_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "Tools").mkdir()
            (root / "Tools/a.sh").write_text("", encoding="utf-8")
            (root / "Tools/b.py").write_text("", encoding="utf-8")
            self.assertEqual(lint(doc("bash Tools/a.sh && python3 -u Tools/b.py x"), root), [])

    def test_missing_local_action_fails(self):
        d = doc(extra_job={"steps": [{"uses": "./.github/actions/nope"}]})
        errs = lint(d)
        self.assertEqual(len(errs), 1, errs)
        self.assertIn("無い action", errs[0])

    def test_remote_action_is_not_checked(self):
        self.assertEqual(lint(doc(extra_job={"steps": [{"uses": "actions/checkout@v7"}]})), [])


class Secrets(unittest.TestCase):
    KNOWN = {"APP_STORE_CONNECT_KEY_ID", "CERTIFICATE_PRIVATE_KEY"}

    def test_typo_fails(self):
        errs = w.secret_errors({"a.yml": "k: ${{ secrets.APP_STORE_CONNECT_KEYID }}\n"}, self.KNOWN)
        self.assertEqual(len(errs), 1, errs)
        self.assertIn("APP_STORE_CONNECT_KEYID", errs[0])

    def test_known_builtin_and_step_output_pass(self):
        text = "a: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}\nb: ${{ secrets.GITHUB_TOKEN }}\nc: ${{ steps.secrets.outputs.signing }}\n"
        self.assertEqual(w.secret_errors({"a.yml": text}, self.KNOWN), [])

    def test_commented_out_name_is_ignored(self):
        self.assertEqual(w.secret_errors({"a.yml": "# secrets.TYPO_NAME は昔の名前\n"}, self.KNOWN), [])


class JobGuards(unittest.TestCase):
    def test_missing_timeout_fails(self):
        d = doc()
        del d["jobs"]["j"]["timeout-minutes"]
        errs = lint(d)
        self.assertEqual(len(errs), 1, errs)
        self.assertIn("timeout-minutes", errs[0])

    def test_missing_permissions_fails_only_without_workflow_level(self):
        d = doc()
        del d["permissions"]
        errs = lint(d)
        self.assertEqual(len(errs), 1, errs)
        self.assertIn("permissions", errs[0])
        d["jobs"]["j"]["permissions"] = {"contents": "read"}
        self.assertEqual(lint(d), [])

    def test_reusable_workflow_call_job_needs_no_timeout(self):
        d = {"permissions": {"contents": "read"}, "jobs": {"p": {"uses": "./.github/workflows/y.yml"}}}
        root = pathlib.Path(tempfile.mkdtemp())
        (root / ".github/workflows").mkdir(parents=True)
        (root / ".github/workflows/y.yml").write_text("", encoding="utf-8")
        self.assertEqual(lint(d, root), [])


@NEEDS_YAML
class RealRepository(unittest.TestCase):
    def test_current_tree_has_zero_ng(self):
        errs, skipped = w.lint()
        self.assertEqual(skipped, "")
        self.assertEqual(errs, [], "\n".join(errs))

    def test_every_used_secret_is_documented(self):
        known = w.documented_secrets()
        self.assertTrue(known)
        used = set()
        for f in w.workflow_files():
            used |= set(w.SECRET_REF.findall(f.read_text(encoding="utf-8")))
        self.assertTrue(used - w.BUILTIN_SECRETS, "Secrets を1つも使っていない（正規表現が壊れている？）")
        self.assertEqual(sorted(used - known - w.BUILTIN_SECRETS), [])


if __name__ == "__main__":
    unittest.main(verbosity=1)
