#!/usr/bin/env python3
"""`.xcresult` から、テスト1本ずつの秒数を **xcodebuild の全文ログと同じ書き方** で標準出力に出す。

    python3 Tools/xcresult-times.py build/ios/test/Test-1.xcresult

    Test Case '-[JourneyPhotoUITests.ScreenshotTests testCapturesFoo]' passed (12.3 seconds).

なぜ要るか（2026-11-04・速さの担当）: Mac の job のログには xcodebuild の出力の**最後の数百行**しか残らず
（run 815 の組 3 は 24 本のうち 5 本だけ）、`Tools/ui-test-times.json`（組の割り振りに使う1本ごとの時間）を
作り直す材料がなかった。結果の束（xcresult）には全部の秒数があるので、それをログに書き出す。
`Tools/ui-times-from-runs.py` が、この行を読んで表を作り直す。

使うのは `xcrun xcresulttool get test-results tests`（Xcode 16 から）。**読めなくても落とさない**
（見張りはテストの結果そのもの。ここは時間の記録のため）。
"""
import json
import re
import subprocess
import sys


def load_tests(path):
    try:
        out = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", path, "--compact"],
            capture_output=True, text=True, timeout=180,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, f"xcresulttool を呼べません: {error}"
    if out.returncode != 0:
        return None, out.stderr.strip()
    try:
        return json.loads(out.stdout), None
    except json.JSONDecodeError as error:
        return None, f"JSON として読めません: {error}"


def seconds_of(node):
    """秒数。`durationInSeconds`（数）があればそれ、なければ `duration`（"1m 47s"・"12s"・"0.4s"）を読む"""
    value = node.get("durationInSeconds")
    if isinstance(value, (int, float)):
        return float(value)
    text = node.get("duration")
    if not isinstance(text, str):
        return None
    total, found = 0.0, False
    for number, unit in re.findall(r"([0-9]+(?:\.[0-9]+)?)\s*(h|m|s)", text):
        total += float(number) * {"h": 3600, "m": 60, "s": 1}[unit]
        found = True
    return total if found else None


def walk(node, bundle, suite, out):
    kind = node.get("nodeType")
    name = node.get("name", "")
    if kind == "Unit test bundle" or kind == "UI test bundle":
        bundle = name.replace(".xctest", "")
    elif kind == "Test Suite":
        suite = name
    elif kind == "Test Case":
        sec = seconds_of(node)
        if sec is not None and bundle and suite:
            result = {"Passed": "passed", "Failed": "failed", "Skipped": "skipped"}.get(node.get("result"), "passed")
            out.append((bundle, suite, re.sub(r"\(\)$", "", name), result, sec))
        return
    for child in node.get("children") or []:
        walk(child, bundle, suite, out)


def render(doc):
    found = []
    for node in doc.get("testNodes") or []:
        walk(node, None, None, found)
    return [f"Test Case '-[{bundle}.{suite} {name}]' {result} ({sec:.3f} seconds)."
            for bundle, suite, name, result, sec in found]


def main():
    if len(sys.argv) < 2:
        print("使い方: xcresult-times.py <Test.xcresult>", file=sys.stderr)
        return 0
    doc, error = load_tests(sys.argv[1])
    if doc is None:
        print(f"::warning::テストごとの秒数を読めませんでした（{error or '理由不明'}）")
        return 0
    lines = render(doc)
    print(f"== テストごとの秒数（{sys.argv[1]}・{len(lines)} 本）")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
