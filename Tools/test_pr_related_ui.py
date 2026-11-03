#!/usr/bin/env python3
"""PR関連UIテスト選別の回帰テスト。macOS/Xcode不要。"""
import contextlib
import io
import pathlib
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import importlib.util
spec = importlib.util.spec_from_file_location("picker", pathlib.Path(__file__).with_name("pick-ui-tests.py"))
picker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(picker)


def diff(path, line='changed'):
    return f'diff --git a/{path} b/{path}\n--- a/{path}\n+++ b/{path}\n@@ -1 +1 @@\n-old\n+{line}\n'


class RelatedTests(unittest.TestCase):
    def run_related(self, patch_text, matches):
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / 'changes.diff'
            path.write_text(patch_text)
            out = io.StringIO()
            with patch.object(picker, 'read_index', return_value=({'SmokeTests/testLaunch': {}, 'ScreenshotTests/testHome': {}}, {})), \
                 patch.object(picker, 'tests_for_diff', side_effect=lambda text, *args: matches.get(next((p for p in matches if p in text), ''), {})), \
                 contextlib.redirect_stdout(out):
                code = picker.main_related([str(path)])
            self.assertEqual(code, 0)
            return out.getvalue()

    def test_related_selection(self):
        result = self.run_related(diff('Sources/Home.swift'), {'Sources/Home.swift': {'ScreenshotTests/testHome': 'matched'}})
        self.assertIn('ScreenshotTests/testHome', result)
        self.assertIn('SmokeTests', result)
        self.assertNotIn('-only-testing:JourneyPhotoUITests\n', result)

    def test_unknown_file_forces_full_suite(self):
        result = self.run_related(diff('Sources/Home.swift') + diff('Sources/Other.swift'), {'Sources/Home.swift': {'ScreenshotTests/testHome': 'matched'}})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests')

    def test_workflow_only_runs_smoke(self):
        result = self.run_related(diff('.github/workflows/ios-pr.yml'), {})
        self.assertIn('SmokeTests', result)

    def test_two_related_files_select_union(self):
        result = self.run_related(diff('Sources/Home.swift') + diff('Sources/Photo.swift'), {
            'Sources/Home.swift': {'ScreenshotTests/testHome': 'home'},
            'Sources/Photo.swift': {'ScreenshotTests/testPhoto': 'photo'},
        })
        self.assertIn('ScreenshotTests/testHome', result)
        self.assertIn('ScreenshotTests/testPhoto', result)

    def test_project_configuration_forces_full_suite(self):
        result = self.run_related(diff('project.yml'), {})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests')

    def test_changed_ui_test_without_match_forces_full_suite(self):
        result = self.run_related(diff('UITests/JourneyPhotoUITests/ScreenshotTests.swift'), {})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests')

    def test_diff_filter_is_per_file(self):
        combined = diff('Sources/Home.swift') + diff('Sources/Other.swift')
        self.assertIn('Sources/Home.swift', picker.diff_text_for_path(combined, 'Sources/Home.swift'))
        self.assertNotIn('Sources/Other.swift', picker.diff_text_for_path(combined, 'Sources/Home.swift'))


if __name__ == '__main__':
    unittest.main()
