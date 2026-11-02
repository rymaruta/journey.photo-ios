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
        selected = sorted(t for t in tests if any(a.endswith("/" + t) or a.endswith("/" + t.split("/")[0]) for a in args))
    lines = ["## UIテスト実行内容", "",
             f"- 指定: `{escape(selection or '全部')}`",
             f"- 対象: **{len(selected)} 件**（全件指定では名指し専用テストを除外）", "",
             "| テスト | 目的・操作の概要 | 実行方針 |",
             "|---|---|---|"]
    for name in selected:
        title, desc = DETAILS.get(name, (name.split("/", 1)[1], CLASS_DOC.get(name.split("/")[0], "UI操作と期待結果をXCTestで確認")))
        policy = "名指し専用" if picker.only_when_named(name) else "通常"
        lines.append(f"| `{escape(name)}` | **{escape(title)}** — {escape(desc)} | {policy} |")
    lines += ["", "### 確認方法",
              "詳細な操作・アサーションは各テストのSwiftソースを参照してください。",
              "この表は実行計画であり成功結果ではありません。失敗時はActionsの各テストジョブSummaryを確認してください。公開Artifactには画像やxcresultを保存しません。",
              ""]
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
