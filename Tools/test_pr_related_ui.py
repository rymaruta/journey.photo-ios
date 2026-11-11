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
    def run_related(self, patch_text, matches, narrow=False):
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / 'changes.diff'
            path.write_text(patch_text)
            out = io.StringIO()
            with patch.object(picker, 'read_index', return_value=({'SmokeTests/testLaunch': {}, 'ScreenshotTests/testHome': {}}, {})), \
                 patch.object(picker, 'tests_for_diff', side_effect=lambda text, *args: matches.get(next((p for p in matches if p in text), ''), {})), \
                 contextlib.redirect_stdout(out):
                code = picker.main_related([str(path)], narrow=narrow)
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

    def test_deleted_source_forces_full_suite(self):
        deleted = 'diff --git a/Sources/Old.swift b/Sources/Old.swift\n--- a/Sources/Old.swift\n+++ /dev/null\n@@ -1 +0,0 @@\n-old\n'
        result = self.run_related(deleted, {})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests')

    def test_shared_test_runner_forces_full_suite(self):
        result = self.run_related(diff('Tools/xcode-test.sh'), {})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests')

    def test_resources_force_full_suite(self):
        result = self.run_related(diff('Resources/Assets.xcassets/Contents.json'), {})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests')

    def test_package_change_forces_full_suite(self):
        result = self.run_related(diff('Package.swift'), {})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests')

    def test_unknown_ui_support_file_forces_full_suite(self):
        result = self.run_related(diff('UITests/SharedHelper.txt'), {})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests')

    def test_binary_asset_forces_full_suite(self):
        binary = 'diff --git a/Resources/cover.png b/Resources/cover.png\nindex 123..456 100644\nBinary files a/Resources/cover.png and b/Resources/cover.png differ\n'
        self.assertEqual(self.run_related(binary, {}).strip(), '-only-testing:JourneyPhotoUITests')

    def test_rename_forces_full_suite(self):
        renamed = 'diff --git a/Sources/Old.swift b/Sources/New.swift\nsimilarity index 100%\nrename from Sources/Old.swift\nrename to Sources/New.swift\n'
        self.assertEqual(self.run_related(renamed, {}).strip(), '-only-testing:JourneyPhotoUITests')

    def test_no_app_changes_uses_smoke_only(self):
        result = self.run_related(diff('docs/README.md'), {})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests/SmokeTests')

    def test_shared_card_renderer_uses_smoke_and_unit_coverage(self):
        result = self.run_related(diff('Sources/JourneyPhoto/Services/SignatureShareCardRenderer.swift'), {})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests/SmokeTests')

    def test_unparseable_nonempty_diff_forces_full_suite(self):
        result = self.run_related('unrecognized diff content', {})
        self.assertEqual(result.strip(), '-only-testing:JourneyPhotoUITests')

    def test_diff_filter_is_per_file(self):
        combined = diff('Sources/Home.swift') + diff('Sources/Other.swift')
        self.assertIn('Sources/Home.swift', picker.diff_text_for_path(combined, 'Sources/Home.swift'))
        self.assertNotIn('Sources/Other.swift', picker.diff_text_for_path(combined, 'Sources/Home.swift'))


class NarrowTests(RelatedTests):
    """PR の検証（`--related-narrow`）は全部に倒さない（2026-11-11 owner・全部の UI テストは夜の回）"""
    ALL = '-only-testing:JourneyPhotoUITests'

    def lines(self, text):
        return [line for line in text.splitlines() if line]

    def test_narrow_unknown_file_keeps_related_and_smoke(self):
        result = self.lines(self.run_related(diff('Sources/Home.swift') + diff('Sources/Other.swift'),
                                             {'Sources/Home.swift': {'ScreenshotTests/testHome': 'matched'}}, narrow=True))
        self.assertEqual(result, [f'{self.ALL}/SmokeTests', f'{self.ALL}/ScreenshotTests/testHome'])

    def test_narrow_never_full(self):
        cases = [diff('project.yml'), diff('Package.swift'), diff('Tools/xcode-test.sh'),
                 diff('UITests/JourneyPhotoUITests/ScreenshotTests.swift'), 'unrecognized diff content',
                 'diff --git a/Resources/a.png b/Resources/a.png\nBinary files differ\n']
        for text in cases:
            result = self.lines(self.run_related(text, {}, narrow=True))
            self.assertNotIn(self.ALL, result, text)
            self.assertEqual(result[0], f'{self.ALL}/SmokeTests', text)

    def test_default_still_full(self):
        # 夜の回・上げる回の `--related` は今までどおり全部に倒す
        self.assertEqual(self.run_related(diff('project.yml'), {}).strip(), self.ALL)


if __name__ == '__main__':
    unittest.main()
