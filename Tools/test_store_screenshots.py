#!/usr/bin/env python3
"""`Tools/store-screenshots.py` の回帰テスト（2026-11-23・札 #604）。

2026-11-23 owner「ちゃんと実機通りのスクショかも見ないといけない。イメージで作るのはダメ」: App Store に出す絵は、
**シミュレータの画面写真そのまま**（合成しない・縮めない）。大型（1320×2868）と中型（1206×2622・「Dynamic Island 搭載
iPhone（中型ディスプレイ）」）の2組を、その寸法がそのまま出る機種で撮った材料から出す。寸法が違う材料は書かずに赤。
Pillow が要る（`pip install pillow`）。
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


def make_material(folder, size, skip=(), wrong=None, color=(40, 80, 120)):
    """xcresulttool の書き出しの形（manifest.json と png）で、材料を並べる。`wrong` の名前だけ寸法を変える"""
    os.makedirs(folder, exist_ok=True)
    rows = []
    names = [prefix for _, prefix in store.SLIDES] + [prefix for _, prefix in store.REVIEW]
    for i, prefix in enumerate(names):
        if prefix in skip:
            continue
        file = f"{i:04d}.png"
        shape = (size[0] - 6, size[1] - 12) if prefix == wrong else size
        Image.new("RGBA", shape, color + (255,)).save(os.path.join(folder, file))
        rows.append({"suggestedHumanReadableName": f"{prefix}_0_ABC.png", "exportedFileName": file})
    with open(os.path.join(folder, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump([{"attachments": rows}], f, ensure_ascii=False)


def run(large, medium, out, env=None):
    argv, saved = sys.argv, dict(os.environ)
    sys.argv = ["store-screenshots.py", large, medium, out]
    os.environ.update(env or {})
    try:
        store.load_pillow()
        return store.main()
    finally:
        sys.argv = argv
        os.environ.clear()
        os.environ.update(saved)


class StoreScreenshotsTests(unittest.TestCase):

    def test_copies_both_frames_as_they_are(self):
        """合成しない: 出す絵は材料の画面と画素まで同じ（寸法も色も）。透過は外す"""
        self.assertEqual(sorted(f[1] for f in store.FRAMES), [(1206, 2622), (1320, 2868)])
        self.assertFalse(hasattr(store, "compose"), "合成の関数が残っている")
        with tempfile.TemporaryDirectory() as work:
            large, medium, out = (os.path.join(work, n) for n in ("large", "medium", "out"))
            make_material(large, (1320, 2868), color=(10, 20, 30))
            make_material(medium, (1206, 2622), color=(200, 100, 50))
            env = {"STORE_DEVICE_LARGE": "iPhone 17 Pro Max", "STORE_DEVICE_MEDIUM": "iPhone 17 Pro", "STORE_IOS": "iOS 26.1"}
            self.assertEqual(run(large, medium, out, env), 0)
            for sub, size, label, kind, _ in store.FRAMES:
                folder = os.path.join(out, sub) if sub else out
                for name, _ in store.SLIDES:
                    with Image.open(os.path.join(folder, f"{name}.png")) as image:
                        self.assertEqual(image.size, size, f"{label} の {name}")
                        self.assertEqual(image.mode, "RGB", "透過が残っている（App Store は透過の無い PNG）")
                        want = (10, 20, 30) if kind == "large" else (200, 100, 50)
                        self.assertEqual(image.getpixel((size[0] // 2, size[1] // 2)), want, "材料と違う絵になっている")
            self.assertEqual(len(store.SLIDES), 8)
            self.assertEqual(store.SLIDES[1], ("02-AI に頼む", "90-ストア・AI に頼む"))
            readme = open(os.path.join(out, "README.md"), encoding="utf-8").read()
            for want in ["合成なし", "シミュレータの実際の画面", "iPhone 17 Pro Max", "iPhone 17 Pro", "iOS 26.1",
                         "Dynamic Island 搭載 iPhone（中型ディスプレイ）", "medium-1206x2622/", "1206×2622", "1320×2868"]:
                self.assertIn(want, readme)
            self.assertTrue(os.path.exists(os.path.join(out, "review-Pro の案内.png")))
            self.assertFalse(os.path.exists(os.path.join(out, "medium-1206x2622", "review-Pro の案内.png")))

    def test_wrong_size_is_not_scaled(self):
        """寸法が違う材料は縮めて合わせず、書かずに赤（終了コード 1）"""
        with tempfile.TemporaryDirectory() as work:
            large, medium, out = (os.path.join(work, n) for n in ("large", "medium", "out"))
            make_material(large, (1320, 2868), wrong="10-ホーム")
            make_material(medium, (1206, 2622), skip=("20-写真の詳細",))
            self.assertEqual(run(large, medium, out), 1)
            self.assertFalse(os.path.exists(os.path.join(out, "01-ホーム.png")), "寸法の違う絵を書いた")
            self.assertTrue(os.path.exists(os.path.join(out, "02-AI に頼む.png")))
            self.assertFalse(os.path.exists(os.path.join(out, "medium-1206x2622", "08-写真の詳細.png")))
            readme = open(os.path.join(out, "README.md"), encoding="utf-8").read()
            self.assertIn("縮めて合わせない", readme)

    def test_devices_and_ios_version(self):
        """撮る機種は枠の寸法がそのまま出る機種だけ（無ければ None で赤。ほかの寸法の機種に落とさない）"""
        self.assertEqual(store.pick_device("large", {"iPhone 17 Pro Max", "iPhone 17 Pro", "iPhone Air"}), "iPhone 17 Pro Max")
        self.assertEqual(store.pick_device("medium", {"iPhone 17 Pro Max", "iPhone 16 Pro"}), "iPhone 16 Pro")
        self.assertIsNone(store.pick_device("medium", {"iPhone 17 Pro Max", "iPhone Air", "iPhone 16e"}))
        payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-1": [{"name": "iPhone 17 Pro", "isAvailable": True}]}}
        self.assertEqual(store.runtime_of("iPhone 17 Pro", payload), "iOS 26.1")
        self.assertEqual(store.runtime_of("iPhone 99", payload), "?")

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
