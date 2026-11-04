#!/usr/bin/env python3
"""Mac のテストのログから、アプリの重さの数を行ごとに拾って、記録（JSON）と読みやすい表（Markdown）にする。

    python3 Tools/perf-collect.py <ログ>... --json build/perf/perf.json --markdown build/perf/summary.md [--require]

`.github/workflows/ios-perf.yml`（基準が残る定期の回）が使う。拾うのは3種類の行（2026-11-04・札 #429）:

1. **XCTest の `measure` の行**（XCTest が自分で書く。試験からは読めない）:
   `Test Case '-[JourneyPhotoUITests.PerformanceTests testX]' measured [Memory Peak Physical (staging), kB] average: 133303.211,
   relative standard deviation: 0.015%, values: [...], performanceMetricID:...`
2. **`PERF test=<試験> key=value …`**（`PerformanceTests` が自分で残す1行。壁時計・body の評価回数など）
3. **`PERF-PROBE label=<段> test=<試験> <アプリの記録>`**（`perf.probe` の値。失敗した試験の終わりにも残る）

同じ行がログに2度出る（`print` と `XCTContext.runActivity`）ので、**完全に同じ行は1件に数える**。
合否は付けない（Mac の混み具合で揺れる数で赤にしない）。拾えた件数が 0 のときだけ `--require` で異常終了にする
（「回したのに数が1つも出ない」＝仕組みが壊れている、を見逃さないため）
"""
import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

MEASURE = re.compile(
    r"Test Case '-\[(?:[\w]+\.)?(?P<cls>\w+) (?P<test>\w+)\]' measured \[(?P<metric>.+?), (?P<unit>[^,\]]+)\] "
    r"average: (?P<avg>[-+\d.eE]+|nan|inf), relative standard deviation: (?P<rsd>[\d.]+|inf|nan)%, "
    r"values: \[(?P<values>[^\]]*)\], performanceMetricID:(?P<id>[^,\s]+)"
)
PERF = re.compile(r"PERF test=(?P<test>\w+)(?P<rest>(?: [^\s=]+=\S*)*)\s*$")
PROBE = re.compile(r"PERF-PROBE label=(?P<label>\S+) test=(?P<test>\S+) (?P<raw>.*?)\s*$")


def number(text):
    try:
        return float(text)
    except ValueError:
        return None


def parse_fields(rest):
    """` a=1 b=2,3` → {"a": "1", "b": "2,3"}（値の中の `=` は残す）"""
    fields = {}
    for word in rest.split():
        key, _, value = word.partition("=")
        fields[key] = value
    return fields


def parse_lines(lines):
    """ログの行から (measures, perfs, probes) を返す。同じ内容は1件にまとめる"""
    measures, perfs, probes = [], [], []
    seen = set()
    for line in lines:
        line = line.rstrip("\n")
        m = MEASURE.search(line)
        if m:
            key = ("m", m.group("test"), m.group("metric"), m.group("avg"), m.group("values"))
            if key not in seen:
                seen.add(key)
                values = [number(v) for v in m.group("values").split(",") if v.strip()]
                measures.append({
                    "class": m.group("cls"), "test": m.group("test"),
                    "metric": m.group("metric"), "unit": m.group("unit"),
                    "average": number(m.group("avg")), "rsd_percent": number(m.group("rsd")),
                    "values": values, "metric_id": m.group("id"),
                })
            continue
        # PERF-PROBE を先に見る（`PERF test=` には当たらない形だが、念のため）
        p = PROBE.search(line)
        if p:
            key = ("p", p.group("label"), p.group("test"), p.group("raw"))
            if key not in seen:
                seen.add(key)
                probes.append({"label": p.group("label"), "test": p.group("test"), "raw": p.group("raw")})
            continue
        f = PERF.search(line)
        if f:
            key = ("f", f.group("test"), f.group("rest"))
            if key not in seen:
                seen.add(key)
                perfs.append({"test": f.group("test"), "fields": parse_fields(f.group("rest"))})
    return measures, perfs, probes


def build_report(measures, perfs, probes, env=None):
    env = os.environ if env is None else env
    return {
        "meta": {
            "date_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "sha": env.get("GITHUB_SHA", ""),
            "run_id": env.get("GITHUB_RUN_ID", ""),
            "run_number": env.get("GITHUB_RUN_NUMBER", ""),
            "ref": env.get("GITHUB_REF_NAME", ""),
        },
        "measures": measures,
        "perf": perfs,
        "probes": probes,
    }


def fmt(value):
    if value is None:
        return "-"
    if abs(value) >= 1000:
        return f"{value:,.0f}"
    return f"{value:.3f}".rstrip("0").rstrip(".")


def render_markdown(report):
    meta = report["meta"]
    lines = ["### アプリの重さの記録（PerformanceTests）", ""]
    lines.append(f"- 日時（UTC）: {meta['date_utc']} / sha: `{meta['sha'][:8] or '-'}` / run: {meta['run_number'] or '-'}")
    lines.append(f"- 拾えた数: measure {len(report['measures'])} 行・PERF {len(report['perf'])} 行・PERF-PROBE {len(report['probes'])} 行")
    lines.append("- 合否は付けない。前後を比べるのは、同じ試験・同じ指標の数（この表か成果物 `perf-record` の JSON）")
    if report["measures"]:
        lines += ["", "#### XCTest の測定（measure）", "", "| 試験 | 指標 | 平均 | 相対標準偏差 | 値 |", "|---|---|---:|---:|---|"]
        for m in report["measures"]:
            values = ", ".join(fmt(v) for v in m["values"])
            lines.append(f"| {m['class']}/{m['test']} | {m['metric']} ({m['unit']}) | {fmt(m['average'])} | "
                         f"{fmt(m['rsd_percent'])}% | {values} |")
    if report["perf"]:
        lines += ["", "#### 試験が残した数（PERF）", "", "| 試験 | 内容 |", "|---|---|"]
        for p in report["perf"]:
            body = " ".join(f"{k}=`{v}`" for k, v in p["fields"].items()).replace("|", "\\|")
            lines.append(f"| {p['test']} | {body[:600]} |")
    if report["probes"]:
        lines += ["", "#### アプリの記録（perf.probe）", "", "```"]
        for p in report["probes"]:
            lines.append(f"{p['test']} [{p['label']}] {p['raw'][:500]}")
        lines += ["```"]
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logs", nargs="+")
    parser.add_argument("--json", dest="json_path")
    parser.add_argument("--markdown", dest="markdown_path")
    parser.add_argument("--require", action="store_true", help="1件も拾えなかったら異常終了")
    args = parser.parse_args(argv)

    lines = []
    for path in args.logs:
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                lines.extend(handle.readlines())
        except OSError as error:
            print(f"::warning::ログを読めません: {path}: {error}", file=sys.stderr)
    measures, perfs, probes = parse_lines(lines)
    report = build_report(measures, perfs, probes)
    if args.json_path:
        os.makedirs(os.path.dirname(args.json_path) or ".", exist_ok=True)
        with open(args.json_path, "w", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2)
    markdown = render_markdown(report)
    if args.markdown_path:
        os.makedirs(os.path.dirname(args.markdown_path) or ".", exist_ok=True)
        with open(args.markdown_path, "w", encoding="utf-8") as handle:
            handle.write(markdown)
    sys.stdout.write(markdown)
    if args.require and not (measures or perfs or probes):
        print("::error::数が1つも拾えませんでした（ログに measured / PERF の行が無い）", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
