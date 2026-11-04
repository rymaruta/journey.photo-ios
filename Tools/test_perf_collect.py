#!/usr/bin/env python3
"""`perf-collect.py`（Mac のログから重さの数を拾う）の回帰テスト。macOS/Xcode 不要。

行の形は、実際の Mac のログ（run 808・2026-10-31）の `measured [...]` の行と、
`PerformanceTests.perf` / `PerfProbeSupport.notePerfProbe` が書く行そのもの。"""
import importlib.util
import json
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("perf_collect", pathlib.Path(__file__).with_name("perf-collect.py"))
collect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collect)

MEASURE_LINE = (
    "2026-10-31T22:12:05.2343290Z /Users/runner/work/journey.photo-ios/journey.photo-ios/UITests/JourneyPhotoUITests/"
    "PerformanceTests.swift:147: Test Case '-[JourneyPhotoUITests.PerformanceTests testStoryRingsMemory]' measured "
    "[Memory Peak Physical (staging), kB] average: 133303.211, relative standard deviation: 0.015%, "
    "values: [133308.672000, 133275.904000, 133325.056000], "
    "performanceMetricID:com.apple.dt.XCTMetric_Memory-com.journeyphoto.JourneyPhoto.staging.physical_peak, "
    'baselineName: "", baselineAverage: , polarity: prefers smaller'
)
TIME_LINE = (
    "Test Case '-[JourneyPhotoUITests.PerformanceTests testLaunchTime]' measured [Duration (AppLaunch), s] average: 1.234, "
    "relative standard deviation: 3.1%, values: [1.2, 1.3, 1.2], performanceMetricID:com.apple.dt.XCTMetric_ApplicationLaunch-"
    "com.journeyphoto.JourneyPhoto.staging.duration, baselineName: \"\""
)
PERF_LINE = "    t =    77.37s PERF test=testLaunchTime metric=wall_ms runs=6 values=1500,1210,1190,1205,1180,1222"
PROBE_LINE = ("PERF-PROBE label=afterHome test=testLaunchProbe sel=[+120ms home>search@tabs.set] | "
              "task=[#0 auth.state.sync 80-310ms] | stall=2/180ms/540f | body=home:12,myPage:3,photoDetail:0 | t=1234ms")


class Collect(unittest.TestCase):
    def test_measure_line(self):
        measures, perfs, probes = collect.parse_lines([MEASURE_LINE, TIME_LINE])
        self.assertEqual((len(measures), len(perfs), len(probes)), (2, 0, 0))
        first = measures[0]
        self.assertEqual((first["class"], first["test"]), ("PerformanceTests", "testStoryRingsMemory"))
        self.assertEqual(first["metric"], "Memory Peak Physical (staging)")
        self.assertEqual(first["unit"], "kB")
        self.assertAlmostEqual(first["average"], 133303.211)
        self.assertEqual(len(first["values"]), 3)
        self.assertEqual(measures[1]["metric"], "Duration (AppLaunch)")
        self.assertEqual(measures[1]["unit"], "s")

    def test_perf_and_probe_lines(self):
        measures, perfs, probes = collect.parse_lines([PERF_LINE, PROBE_LINE])
        self.assertEqual((len(measures), len(perfs), len(probes)), (0, 1, 1))
        self.assertEqual(perfs[0]["test"], "testLaunchTime")
        self.assertEqual(perfs[0]["fields"]["metric"], "wall_ms")
        self.assertEqual(perfs[0]["fields"]["values"], "1500,1210,1190,1205,1180,1222")
        self.assertEqual(probes[0]["label"], "afterHome")
        self.assertIn("body=home:12,myPage:3,photoDetail:0", probes[0]["raw"])

    def test_probe_line_is_not_a_perf_line(self):
        _, perfs, probes = collect.parse_lines([PROBE_LINE])
        self.assertEqual((len(perfs), len(probes)), (0, 1))

    def test_same_line_twice_counts_once(self):
        # `print` と `XCTContext.runActivity` の両方がログに出る
        measures, perfs, probes = collect.parse_lines(
            [MEASURE_LINE, MEASURE_LINE, PERF_LINE, PERF_LINE, PROBE_LINE, PROBE_LINE])
        self.assertEqual((len(measures), len(perfs), len(probes)), (1, 1, 1))

    def test_unrelated_lines_are_ignored(self):
        measures, perfs, probes = collect.parse_lines(["Test Case 'x' passed (1.0 seconds)", "t = 1.0s Tap", ""])
        self.assertEqual((measures, perfs, probes), ([], [], []))

    def test_report_and_markdown(self):
        measures, perfs, probes = collect.parse_lines([MEASURE_LINE, PERF_LINE, PROBE_LINE])
        report = collect.build_report(measures, perfs, probes,
                                      env={"GITHUB_SHA": "abcdef1234567890", "GITHUB_RUN_NUMBER": "7"})
        self.assertEqual(report["meta"]["sha"], "abcdef1234567890")
        json.dumps(report)
        text = collect.render_markdown(report)
        self.assertIn("測定（measure）", text)
        self.assertIn("PerformanceTests/testStoryRingsMemory", text)
        self.assertIn("testLaunchTime", text)
        self.assertIn("afterHome", text)

    def test_main_writes_files_and_require_fails_on_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            good = tmp / "good.log"
            good.write_text(MEASURE_LINE + "\n" + PERF_LINE + "\n")
            empty = tmp / "empty.log"
            empty.write_text("nothing here\n")
            out_json, out_md = tmp / "o" / "perf.json", tmp / "o" / "s.md"
            self.assertEqual(collect.main([str(good), "--json", str(out_json), "--markdown", str(out_md), "--require"]), 0)
            data = json.loads(out_json.read_text())
            self.assertEqual(len(data["measures"]), 1)
            self.assertTrue(out_md.read_text().startswith("### "))
            self.assertEqual(collect.main([str(empty), "--require"]), 1)
            self.assertEqual(collect.main([str(empty)]), 0)


if __name__ == "__main__":
    unittest.main()
