#!/usr/bin/env python3
"""Explain UI test selection in GitHub Actions without changing test execution."""
import os
import pathlib
import sys

import importlib.util

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("picker", ROOT / "Tools/pick-ui-tests.py")
picker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(picker)
CLASS_DOC = {
    "SmokeTests": "起動・基本画面の表示を確認",
    "ScreenshotTests": "各画面を操作してスクリーンショットを撮影",
    "PerformanceTests": "操作時間・メモリ使用量を計測（性能値そのものでは合否を付けない）",
    "MapETAProbeTests": "日本の区間で Apple の地図が返す移動の見込み（車・歩き・公共交通）を記録（合否なし）",
    "DMHangProbeTests": "DM の会話を下へ払って固まるかを、疑う箇所を外す印ごとに測る（払い1回の秒・固まった版は赤）",
}
DETAILS = {
    "PerformanceTests/testMainTabRevisitTime": ("タブ再訪問", "各タブを開き、再選択が反映されるまでの時間を計測"),
    "PerformanceTests/testHomeScrollMemory": ("ホームのスクロール", "写真一覧をスクロールしてメモリ使用量を計測"),
    "PerformanceTests/testPhotoDetailMemory": ("写真詳細", "写真詳細画面を開いてメモリ使用量を計測"),
}
def escape(value):
    return str(value).replace("|", "&#124;").replace("\n", " ")

def render(selection):
    tests = picker.read_tests()
    if not tests:
        raise RuntimeError("UIテストを発見できません")
    args, missing = picker.pick(selection, tests)
    if missing:
        raise ValueError("対象が見つかりません: " + ", ".join(missing))
    if picker.wants_all(selection):
        selected = sorted(t for t in tests if not picker.only_when_named(t))
    else:
        selected = sorted(t for t in tests if any(a == f"-only-testing:{picker.TARGET}/{t}" or a == f"-only-testing:{picker.TARGET}/{t.split('/')[0]}" for a in args))
    from collections import Counter
    counts = Counter(t.split("/", 1)[0] for t in selected)
    lines = ["### UIテストの予定", "",
             f"**{len(selected)}件** / 指定: `{escape(selection or '全部')}`",
             " / ".join(f"{escape(k)} {v}" for k, v in sorted(counts.items())), "",
             "<details><summary>対象テストを表示</summary>", "",
             "| テスト | 目的 |", "|---|---|"]
    for name in selected:
        title, desc = DETAILS.get(name, (name.split("/", 1)[1], CLASS_DOC.get(name.split("/")[0], "UIの動作確認")))
        lines.append(f"| `{escape(name)}` | {escape(title)}: {escape(desc)} |")
    lines += ["", "</details>", "",
              "※実行予定です。結果は各ジョブのSummaryを参照。画像・xcresultは公開保存しません。", ""]
    return "\n".join(lines)

if __name__ == "__main__":
    selection = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        report = render(selection)
    except (ValueError, RuntimeError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(2)
    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as output:
            output.write(report)
