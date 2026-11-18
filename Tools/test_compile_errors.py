#!/usr/bin/env python3
"""`compile-errors.py`（ビルドだけの回の要約に、コンパイルのエラーの行を並べる）の回帰テスト。macOS/Xcode 不要。

行の形は xcodebuild（Swift）のエラーの行そのもの: `<絶対の置き場>:<行>:<桁>: error: <文>`。"""
import importlib.util
import io
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout

spec = importlib.util.spec_from_file_location("compile_errors", pathlib.Path(__file__).with_name("compile-errors.py"))
ce = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ce)

ROOT = "/Users/runner/work/journey.photo-ios/journey.photo-ios"
LOG = f"""CompileSwift normal arm64 {ROOT}/Sources/JourneyPhoto/A.swift
{ROOT}/Sources/JourneyPhoto/A.swift:12:5: error: cannot find 'foo' in scope
        foo()
        ^~~
{ROOT}/Sources/JourneyPhoto/A.swift:12:5: error: cannot find 'foo' in scope
{ROOT}/UITests/JourneyPhotoUITests/B.swift:3:1: error: 100% bad
{ROOT}/Sources/JourneyPhoto/A.swift:20:1: warning: unused
** TEST BUILD FAILED **

The following build commands failed:
\tSwiftCompile normal arm64 {ROOT}/Sources/JourneyPhoto/A.swift (in target 'JourneyPhoto' from project 'JourneyPhoto')
(1 failure)
"""


def run(text, *flags):
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp, "x.log")
        if text is not None:
            path.write_text(text, encoding="utf-8")
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = ce.main([str(path), *flags])
        return code, buf.getvalue()


class CompileErrorsTests(unittest.TestCase):
    def test_lists_located_errors_once_with_relative_paths(self):
        code, out = run(LOG)
        self.assertEqual(code, 0)
        self.assertIn("2 件", out)
        self.assertIn("- `Sources/JourneyPhoto/A.swift:12` cannot find 'foo' in scope", out)
        self.assertIn("- `UITests/JourneyPhotoUITests/B.swift:3` 100% bad", out)
        self.assertEqual(out.count("A.swift:12"), 1)
        self.assertNotIn("warning", out)
        self.assertNotIn("/Users/runner", out)

    def test_annotations_escape_percent(self):
        _, out = run(LOG, "--annotate")
        self.assertEqual(out.splitlines(), [
            "::error file=Sources/JourneyPhoto/A.swift,line=12,col=5::cannot find 'foo' in scope",
            "::error file=UITests/JourneyPhotoUITests/B.swift,line=3,col=1::100%25 bad",
        ])

    def test_falls_back_to_error_lines_and_failed_commands(self):
        log = ("ld: error: undefined symbol: _foo\n** TEST BUILD FAILED **\n\n"
               "The following build commands failed:\n\tLd /x/JourneyPhoto normal (in target 'JourneyPhoto')\n(1 failure)\n")
        _, out = run(log)
        self.assertIn("ld: error: undefined symbol: _foo", out)
        self.assertIn("Ld /x/JourneyPhoto normal", out)

    def test_missing_log_says_so(self):
        code, out = run(None)
        self.assertEqual(code, 0)
        self.assertIn("ログ", out)
        self.assertIn("ありません", out)


if __name__ == "__main__":
    unittest.main()
