#!/usr/bin/env python3
"""`.xcresult` から、テストの数と**落ちたテストの名前と理由**を Markdown で出す。

CI のまとめの頁（`$GITHUB_STEP_SUMMARY`）に足して、ログを掘らずに
「何が・なぜ落ちたか」を読めるようにする（2026-10-03・PR の検証）。

    python3 Tools/xcresult-summary.py build/Test.xcresult >> "$GITHUB_STEP_SUMMARY"

使うのは Xcode 16 からの `xcresulttool get test-results summary`。
**読めなくても落とさない**（見張りはテストの結果そのもの。ここは読みやすさのため）。
"""
import json
import subprocess
import sys


def load_summary(path):
    try:
        out = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", path, "--compact"],
            capture_output=True, text=True, timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, f"xcresulttool を呼べません: {error}"
    if out.returncode != 0:
        return None, out.stderr.strip()
    try:
        return json.loads(out.stdout), None
    except json.JSONDecodeError as error:
        return None, f"JSON として読めません: {error}"


def render(summary):
    """`summary` は xcresulttool の JSON。テストできるよう、表示だけを切り出してある"""
    lines = ["### テストの結果（Xcode・シミュレータ）", ""]
    total = summary.get("totalTestCount", "?")
    passed = summary.get("passedTests", "?")
    failed = summary.get("failedTests", "?")
    skipped = summary.get("skippedTests", "?")
    result = summary.get("result", "?")
    lines.append(f"- 結果: **{result}**")
    lines.append(f"- 件数: {total}（通過 {passed} / 失敗 {failed} / 飛ばし {skipped}）")
    devices = summary.get("devicesAndConfigurations") or []
    for entry in devices[:1]:
        device = entry.get("device") or {}
        name = device.get("deviceName")
        os_version = device.get("osVersion")
        if name:
            lines.append(f"- 端末: {name} / iOS {os_version or '?'}")
    failures = summary.get("testFailures") or []
    if failures:
        lines += ["", "#### 落ちたテスト", "", "| テスト | 理由 |", "|---|---|"]
        for failure in failures[:50]:
            name = f"{failure.get('targetName', '?')} / {failure.get('testName', '?')}"
            reason = (failure.get("failureText") or "").replace("\n", " ").replace("|", "\\|")
            lines.append(f"| {name} | {reason[:300]} |")
        if len(failures) > 50:
            lines.append(f"| … | ほか {len(failures) - 50} 件 |")
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) < 2:
        print("使い方: xcresult-summary.py <Test.xcresult>", file=sys.stderr)
        return 0
    summary, error = load_summary(sys.argv[1])
    if summary is None:
        print(f"### テストの結果\n\n`.xcresult` を読めませんでした（{error or '理由不明'}）\n")
        return 0
    sys.stdout.write(render(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
