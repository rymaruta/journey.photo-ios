#!/usr/bin/env python3
"""UI テストの時間の表（Tools/ui-test-times.json）を、成功した全部の回のログから作り直す。

  python3 Tools/ui-times-from-runs.py <run id> [<run id> ...]          # 表を stdout に（書かない）
  python3 Tools/ui-times-from-runs.py --write <run id> [<run id> ...]  # ui-test-times.json を書き換える
  python3 Tools/ui-times-from-runs.py --job-log <ファイル> ...          # 手元に落とした job のログから

読むのは各 run の job のうち名前に「UI テスト」「UIテスト」を含むもの（分けた組・先に流す分）の全文ログで、
`Test Case '-[JourneyPhotoUITests.X testY]' passed (N seconds)` の行から1本ずつの秒数を取る。
run を2つ以上渡すと、本ごとの**中央値**を取る（1回の揺れで組分けが傾かないように）。
Linux で動く（`gh` が要る・読むだけ）。`Tools/pick-ui-tests.py --times-from-log` の複数 run 版。
**2026-11-04 より前の回のログは、xcodebuild の出力の最後の数百行しか残らず本数が足りない**（run 815 の組 3 は 24 本のうち 5 本）。
`mac-test-part` が結果の束から `Tools/xcresult-times.py` で全部の秒数をログに書くようになった回以降を渡す。
"""
import importlib.util
import json
import os
import pathlib
import re
import statistics
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = os.environ.get("REPO", "rymaruta/journey.photo-ios")

spec = importlib.util.spec_from_file_location("pick_ui_tests", ROOT / "Tools/pick-ui-tests.py")
pick = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pick)


def gh(path):
    return subprocess.run(["gh", "api", path, "--paginate"], capture_output=True, text=True, check=True).stdout


def jobs_of(run_id):
    out, dec, i, jobs = gh(f"repos/{REPO}/actions/runs/{run_id}/jobs?per_page=100"), json.JSONDecoder(), 0, []
    while i < len(out):
        obj, i = dec.raw_decode(out, i)
        jobs += obj["jobs"]
        while i < len(out) and out[i].isspace():
            i += 1
    return jobs


def ui_logs(run_id):
    """run の UI テストの job のログ（終わった job（落ちた job も、結果の束は読める））"""
    for job in jobs_of(run_id):
        if re.search(r"UI ?テスト", job["name"]) and job["conclusion"] in ("success", "failure"):
            yield f"run {run_id} / {job['name']}", gh(f"repos/{REPO}/actions/jobs/{job['id']}/logs")


def main(argv):
    write = "--write" in argv
    argv = [a for a in argv if a != "--write"]
    sources = []
    if argv and argv[0] == "--job-log":
        for f in argv[1:]:
            sources.append((f, pathlib.Path(f).read_text(encoding="utf-8", errors="replace")))
        label = "job ログ " + " ".join(os.path.basename(f) for f in argv[1:])
    else:
        for run_id in argv:
            sources.extend(ui_logs(run_id))
        label = "run " + "・".join(argv)
    per_test = {}
    for name, text in sources:
        seconds = pick.times_from_log(text)
        print(f"{name}: {len(seconds)} 本", file=sys.stderr)
        for test, sec in seconds.items():
            per_test.setdefault(test, []).append(sec)
    if not per_test:
        print("ログに UI テストの時間が見つかりません（成功した全部の回の run id を渡す）", file=sys.stderr)
        return 1
    seconds = {t: round(statistics.median(v), 1) for t, v in sorted(per_test.items())}
    total = sum(seconds.values())
    print(f"{len(seconds)} 本・合計 {total / 60:.1f} 分", file=sys.stderr)
    doc = {"source": f"{label} の実測（本ごとの中央値）", "seconds": seconds}
    text = json.dumps(doc, ensure_ascii=False, indent=1) + "\n"
    if write:
        pick.TIMES.write_text(text, encoding="utf-8")
        print(f"{pick.TIMES} に書きました", file=sys.stderr)
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
