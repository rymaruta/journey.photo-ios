#!/usr/bin/env python3
"""`linkmap-summary.py`（リンクの地図を部品ごとに数える）の回帰テスト。macOS/Xcode 不要。

行の形は ld（Xcode 15 以降の ld-prime）が `LD_GENERATE_MAP_FILE=YES` で書く LinkMap.txt のもの。"""
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("linkmap_summary", pathlib.Path(__file__).with_name("linkmap-summary.py"))
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)

APP = "/Users/runner/Library/Developer/Xcode/DerivedData/JourneyPhoto-x/Build/Intermediates.noindex/ArchiveIntermediates/JourneyPhoto/IntermediateBuildFilesPath"
MAP = f"""# Path: {APP}/UninstalledProducts/iphoneos/JourneyPhoto.app/JourneyPhoto
# Arch: arm64
# Object files:
[  0] linker synthesized
[  1] {APP}/JourneyPhoto.build/Release-iphoneos/JourneyPhoto.build/Objects-normal/arm64/JourneyPhoto-1.o
[  2] {APP}/aws-sdk-swift.build/Release-iphoneos/AWSCognitoIdentityProvider.build/Objects-normal/arm64/Models.o
[  3] /Applications/Xcode.app/Contents/Developer/usr/lib/libcrt.a(aws_crt.o)
[  4] /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/lib/libSystem.tbd
# Sections:
# Address\tSize    \tSegment\tSection
0x100004000\t0x00002000\t__TEXT\t__text
0x100006000\t0x00000100\t__TEXT\t__cstring
# Symbols:
# Address\tSize    \tFile  Name
0x100004000\t0x00001000\t[  1] _$s12JourneyPhoto4MainV4bodyQrvg
0x100005000\t0x00000800\t[  2] _$s26AWSCognitoIdentityProvider5ModelV
0x100005800\t0x00000400\t[  1] _$s12JourneyPhoto3TabV
0x100005C00\t0x00000400\t[  3] _aws_crt_init
0x100006000\t0x00000010\t[  0] __mh_execute_header
# Dead Stripped Symbols:
#        \tSize    \tFile  Name
<<dead>> \t0x00009000\t[  1] _$s12JourneyPhoto6UnusedV
"""


class LinkMapSummaryTests(unittest.TestCase):
    def test_counts_by_module(self):
        by_module, sections = summary.parse(MAP.splitlines(keepends=True))
        self.assertEqual(by_module["JourneyPhoto"], 0x1400)
        self.assertEqual(by_module["AWSCognitoIdentityProvider"], 0x800)
        self.assertEqual(by_module["libcrt.a"], 0x400)
        self.assertEqual(by_module["（リンカーが作った分）"], 0x10)
        self.assertEqual(dict(sections), {"__TEXT,__text": 0x2000, "__TEXT,__cstring": 0x100})

    def test_dead_stripped_symbols_are_not_counted(self):
        by_module, _ = summary.parse(MAP.splitlines(keepends=True))
        self.assertEqual(sum(by_module.values()), 0x1400 + 0x800 + 0x400 + 0x10)

    def test_report_lists_largest_first(self):
        by_module, sections = summary.parse(MAP.splitlines(keepends=True))
        text = summary.report(by_module, sections)
        lines = text.splitlines()
        first = lines.index("== 部品ごと（大きい順・KB・割合）==") + 1
        self.assertIn("JourneyPhoto", lines[first])
        self.assertIn("AWSCognitoIdentityProvider", lines[first + 1])


car_spec = importlib.util.spec_from_file_location("car_summary", pathlib.Path(__file__).with_name("car-summary.py"))
car = importlib.util.module_from_spec(car_spec)
car_spec.loader.exec_module(car)

# `assetutil --info` の形（頭の1件は Assets.car 全体の情報で SizeOnDisk を持たない）
CAR_INFO = [
    {"AssetStorageVersion": "Xcode 27.2", "Platform": "ios"},
    {"Name": "medal-wish-1", "RenditionName": "medal-wish-1.png", "SizeOnDisk": 185000,
     "PixelWidth": 780, "PixelHeight": 780, "Compression": "lossy", "Encoding": "ARGB"},
    {"Name": "composition-ai-cCurve", "RenditionName": "composition-ai-cCurve.jpg", "SizeOnDisk": 376000,
     "PixelWidth": 864, "PixelHeight": 1152, "Encoding": "JPEG"},
]


class CarSummaryTests(unittest.TestCase):
    def test_skips_header_and_sorts_largest_first(self):
        rows = car.rows_of(CAR_INFO)
        self.assertEqual(len(rows), 2)
        lines = car.report(rows).splitlines()
        self.assertEqual(lines[0], f"合計 {(185000 + 376000) // 1024} KB（2 枚）")
        self.assertIn("composition-ai-cCurve.jpg", lines[1])
        self.assertIn("864x1152", lines[1])
        self.assertIn("medal-wish-1.png", lines[2])


if __name__ == "__main__":
    unittest.main()
