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
        self.assertEqual(store.accepted("large"), [(1320, 2868), (1290, 2796), (1260, 2736)])
        self.assertEqual(store.accepted("medium"), [(1206, 2622), (1179, 2556)])
        self.assertFalse(hasattr(store, "compose"), "合成の関数が残っている")
        with tempfile.TemporaryDirectory() as work:
            large, medium, out = (os.path.join(work, n) for n in ("large", "medium", "out"))
            make_material(large, (1320, 2868), color=(10, 20, 30))
            # 中型は受け付ける2つ目の寸法（1179×2556）の機種で撮った回も通る
            make_material(medium, (1179, 2556), color=(200, 100, 50))
            env = {"STORE_DEVICE_LARGE": "iPhone 17 Pro Max", "STORE_DEVICE_MEDIUM": "iPhone 17 Pro", "STORE_IOS": "iOS 26.1"}
            self.assertEqual(run(large, medium, out, env), 0)
            for sub, _, label, kind in store.FRAMES:
                folder = os.path.join(out, sub) if sub else out
                size = (1320, 2868) if kind == "large" else (1179, 2556)
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
                         "Dynamic Island 搭載 iPhone（中型ディスプレイ）", "medium/", "1179×2556", "1320×2868"]:
                self.assertIn(want, readme)
            self.assertTrue(os.path.exists(os.path.join(out, "review-Pro の案内.png")))
            self.assertFalse(os.path.exists(os.path.join(out, "medium", "review-Pro の案内.png")))

    def test_wrong_size_is_not_scaled(self):
        """寸法が違う材料は縮めて合わせず、書かずに赤（終了コード 1）"""
        with tempfile.TemporaryDirectory() as work:
            large, medium, out = (os.path.join(work, n) for n in ("large", "medium", "out"))
            make_material(large, (1320, 2868), wrong="10-ホーム")
            make_material(medium, (1206, 2622), skip=("20-写真の詳細",))
            self.assertEqual(run(large, medium, out), 1)
            self.assertFalse(os.path.exists(os.path.join(out, "01-ホーム.png")), "寸法の違う絵を書いた")
            self.assertTrue(os.path.exists(os.path.join(out, "02-AI に頼む.png")))
            self.assertFalse(os.path.exists(os.path.join(out, "medium", "08-写真の詳細.png")))
            readme = open(os.path.join(out, "README.md"), encoding="utf-8").read()
            self.assertIn("縮めて合わせない", readme)

    def test_mixed_sizes_in_one_frame_fail(self):
        """1組の中で寸法がそろっていなければ赤（どちらも受け付ける寸法でも）"""
        with tempfile.TemporaryDirectory() as work:
            large, medium, out = (os.path.join(work, n) for n in ("large", "medium", "out"))
            make_material(large, (1320, 2868))
            make_material(medium, (1206, 2622))
            # 1枚だけ別の受け付ける寸法に差し替える
            first = sorted(f for f in os.listdir(medium) if f.endswith(".png"))[0]
            Image.new("RGB", (1179, 2556)).save(os.path.join(medium, first))
            self.assertEqual(run(large, medium, out), 1)

    def test_selects_small_iphone_in_order(self):
        """小さい画面（375pt）の機種: SE（750×1334）→ mini（1080×2340）の順。作れない機種があるので候補を全部、順に返す（2026-11-25）"""
        types = [
            {"identifier": "t.mini", "name": "iPhone 13 mini", "size": (1080, 2340)},
            {"identifier": "t.se3", "name": "iPhone SE (3rd generation)", "size": (750, 1334)},
            {"identifier": "t.18pm", "name": "iPhone 18 Pro Max", "size": (1320, 2868)},
            {"identifier": "t.16e", "name": "iPhone 16e", "size": (1170, 2532)},
        ]
        payload = {"devices": {}}
        self.assertEqual(store.select_devices("small", types, payload),
                         [("create", "t.se3", (750, 1334), "iPhone SE (3rd generation)"),
                          ("create", "t.mini", (1080, 2340), "iPhone 13 mini")])
        # 390pt 以上の機種には落とさない
        self.assertEqual(store.select_devices("small", types[2:], payload), [])
        self.assertIsNone(store.select_device("small", types[2:], payload))
        # 点で書かれた SE の機種の情報も 750×1334 になる
        self.assertEqual(store.profile_size({"mainScreenWidth": 375, "mainScreenHeight": 667, "mainScreenScale": 2}), (750, 1334))

    def test_selects_device_by_screen_size_not_name(self):
        """機種は名前で決め打ちせず、画面写真の寸法が受け付ける寸法そのものの機種を選ぶ（run 1740: 名前の機種が無く止まった）"""
        types = [
            {"identifier": "t.air", "name": "iPhone Air", "size": (1260, 2736)},
            {"identifier": "t.18pm", "name": "iPhone 18 Pro Max", "size": (1320, 2868)},
            {"identifier": "t.18p", "name": "iPhone 18 Pro", "size": (1206, 2622)},
            {"identifier": "t.16e", "name": "iPhone 16e", "size": (1170, 2532)},
            {"identifier": "t.x", "name": "iPhone 19", "size": None},
        ]
        payload = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [{"name": "Old Pro Max", "deviceTypeIdentifier": "t.18pm", "isAvailable": True}],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-2": [{"name": "iPhone 18 Pro Max", "deviceTypeIdentifier": "t.18pm", "isAvailable": True}],
        }}
        # 受け付ける寸法の先（1320×2868）の機種を、いちばん新しい iOS のシミュレータで
        self.assertEqual(store.select_device("large", types, payload), ("use", "iPhone 18 Pro Max", (1320, 2868), "iPhone 18 Pro Max"))
        # シミュレータが無い機種は作る
        self.assertEqual(store.select_device("medium", types, payload), ("create", "t.18p", (1206, 2622), "iPhone 18 Pro"))
        # 先の寸法の機種が無ければ、次の受け付ける寸法の機種（Air 1260×2736）
        self.assertEqual(store.select_device("large", [t for t in types if t["identifier"] != "t.18pm"], payload)[1:],
                         ("t.air", (1260, 2736), "iPhone Air"))
        # 合う機種が無ければ None（赤・縮めて合わせる機種には落とさない）
        self.assertIsNone(store.select_device("medium", [t for t in types if t["identifier"] != "t.18p"], payload))
        # 機種の情報から寸法を出す（画素でも点でも）
        self.assertEqual(store.profile_size({"mainScreenWidth": 1320, "mainScreenHeight": 2868, "mainScreenScale": 3}), (1320, 2868))
        self.assertEqual(store.profile_size({"mainScreenWidth": 402, "mainScreenHeight": 874, "mainScreenScale": 3}), (1206, 2622))
        self.assertIsNone(store.profile_size({}))
        with tempfile.TemporaryDirectory() as work:
            shot = os.path.join(work, "a.png")
            Image.new("RGB", (1206, 2622)).save(shot)
            self.assertEqual(store.png_size(shot), (1206, 2622))

    def test_devices_and_ios_version(self):
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
