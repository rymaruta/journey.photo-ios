#!/usr/bin/env python3
"""`Tools/store-screenshots.py` の回帰テスト（2026-11-23・札 #604）。

App Store に出す絵を、6.9インチ（1320×2868）と中型（1206×2622・「Dynamic Island 搭載 iPhone（中型ディスプレイ）」）の
2組で作ることを確かめる。中型の組を外すと落ちる。Pillow が要る（`pip install pillow`）。
"""
import importlib.util
import json
import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("store_screenshots", os.path.join(ROOT, "Tools/store-screenshots.py"))
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)

from PIL import Image  # noqa: E402


class StoreScreenshotsTests(unittest.TestCase):

    def make_material(self, folder):
        """xcresulttool の書き出しの形（manifest.json と png）で、材料を全部並べる"""
        rows = []
        names = [prefix for _, prefix, _, _ in store.SLIDES] + [prefix for _, prefix in store.REVIEW]
        for i, prefix in enumerate(names):
            file = f"{i:04d}.png"
            Image.new("RGB", (1206, 2622), (40 + i * 10, 80, 120)).save(os.path.join(folder, file))
            rows.append({"suggestedHumanReadableName": f"{prefix}_0_ABC.png", "exportedFileName": file})
        with open(os.path.join(folder, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump([{"attachments": rows}], f, ensure_ascii=False)

    def test_makes_both_frames(self):
        self.assertIn((1320, 2868), [size for _, size, _ in store.FRAMES])
        self.assertIn((1206, 2622), [size for _, size, _ in store.FRAMES])
        with tempfile.TemporaryDirectory() as work:
            raw, out = os.path.join(work, "raw"), os.path.join(work, "out")
            os.makedirs(raw)
            self.make_material(raw)
            argv = sys.argv
            sys.argv = ["store-screenshots.py", raw, out]
            try:
                self.assertEqual(store.main(), 0)
            finally:
                sys.argv = argv
            for sub, size, label in store.FRAMES:
                folder = os.path.join(out, sub) if sub else out
                for name, _, _, _ in store.SLIDES:
                    with Image.open(os.path.join(folder, f"{name}.png")) as image:
                        self.assertEqual(image.size, size, f"{label} の {name}")
            readme = open(os.path.join(out, "README.md"), encoding="utf-8").read()
            self.assertIn("Dynamic Island 搭載 iPhone（中型ディスプレイ）", readme)
            self.assertIn("medium-1206x2622/", readme)
            self.assertIn("1206×2622", readme)
            # 審査用の原寸は1組だけ（中型の置き場に写さない）
            self.assertTrue(os.path.exists(os.path.join(out, "review-Pro の案内.png")))
            self.assertFalse(os.path.exists(os.path.join(out, "medium-1206x2622", "review-Pro の案内.png")))

    def test_store_tests_use_demo(self):
        # いまの UI テストは、どれも見本の表示で撮る
        self.assertEqual(store.check_demo(), [])

    def test_check_demo_catches_production_launch(self):
        """見本の印が無い試験・本番の向き先を渡す試験を名指しする（`--check-demo` が赤にする）"""
        with tempfile.TemporaryDirectory() as ui:
            body = "\n".join(
                f"    func {t.split('/')[1]}() {{\n        app.launchArguments += [\"-JPSiteBaseURL\", \"https://journey-photo.com\"]\n    }}"
                for t in store.STORE_TESTS)
            with open(os.path.join(ui, "ScreenshotTests.swift"), "w", encoding="utf-8") as f:
                f.write("final class ScreenshotTests: JPUITestCase {\n" + body + "\n}\n")
            bad = store.check_demo(ui)
            self.assertEqual(len(bad), len(store.STORE_TESTS))
            self.assertIn("見本の表示", bad[0])
            body = body.replace('"-JPSiteBaseURL"', '"-JPStoreDemo", "YES", "-JPSiteBaseURL"')
            with open(os.path.join(ui, "ScreenshotTests.swift"), "w", encoding="utf-8") as f:
                f.write("final class ScreenshotTests: JPUITestCase {\n" + body + "\n}\n")
            bad = store.check_demo(ui)
            self.assertEqual(len(bad), len(store.STORE_TESTS))
            self.assertIn("本番の向き先", bad[0])


if __name__ == "__main__":
    unittest.main()
