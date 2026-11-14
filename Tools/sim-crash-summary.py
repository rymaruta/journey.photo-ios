#!/usr/bin/env python3
"""UI テストの間にシミュレーターでアプリが落ちた記録（`.ips`）を、落ちた所が読める形でログに出す。

    python3 Tools/sim-crash-summary.py <印のファイル> [<記録の置き場>]

2026-11-13（札 #596）: アプリが落ちると XCTest は「… crashed in …」の1行しか残さず、積み（呼び出し履歴）は
Mac の `~/Library/Logs/DiagnosticReports/` の `.ips` にだけ残る。CI はこれを拾っていなかった。
`Tools/xcode-test.sh ui` が失敗したときに呼び、**印のファイルより新しい**このアプリの記録だけを読む
（前の回・ほかのアプリの記録を混ぜない）。

出すのは `[simCrash]` で始まる行だけ: 例外の種類・信号・終わった理由・アプリが残した文（`asi`。
`Fatal error: Index out of range` など）・落ちたスレッドの積み（上から 40 段・像の名前と関数と行）・
最後の例外の積み（Objective-C の例外のとき）。**公開のログに出る**ので、記録の頭（端末の識別子など）と
画像の置き場の道（利用者名を含む）は出さない。

読めなくても落とさない（終わりの値はいつも 0。見張りはテストの結果そのもの）。
"""
import json
import os
import pathlib
import sys

APP_PREFIXES = ("JourneyPhoto",)
MAX_FRAMES = 40


def parse_ips(text):
    """`.ips` は「1行目の JSON（頭）＋残りの JSON（本体）」。本体だけを返す（読めなければ None）"""
    head, _, body = text.partition("\n")
    try:
        header = json.loads(head)
    except json.JSONDecodeError:
        header = {}
    try:
        return header, json.loads(body)
    except json.JSONDecodeError:
        return header, None


def frame_line(frame, images):
    index = frame.get("imageIndex")
    image = images[index].get("name", "?") if isinstance(index, int) and 0 <= index < len(images) else "?"
    symbol = frame.get("symbol") or f"+{frame.get('imageOffset', '?')}"
    where = ""
    if frame.get("sourceFile"):
        where = f" ({os.path.basename(frame['sourceFile'])}:{frame.get('sourceLine', '?')})"
    return f"{image} {symbol}{where}"


def render(header, body, name):
    lines = [f"[simCrash] ==== {name} ===="]
    if body is None:
        lines.append("[simCrash] 本体を JSON として読めません")
        return lines
    images = body.get("usedImages") or []
    exc = body.get("exception") or {}
    lines.append(f"[simCrash] app={header.get('app_name', body.get('procName', '?'))} "
                 f"version={header.get('app_version', '?')} build={header.get('build_version', '?')}")
    lines.append(f"[simCrash] exception type={exc.get('type', '?')} signal={exc.get('signal', '?')} "
                 f"codes={exc.get('codes', '?')} subtype={exc.get('subtype', '')}")
    term = body.get("termination") or {}
    if term:
        lines.append(f"[simCrash] termination namespace={term.get('namespace', '?')} code={term.get('code', '?')} "
                     f"indicator={term.get('indicator', '')}")
    for key, values in (body.get("asi") or {}).items():
        for value in values if isinstance(values, list) else [values]:
            lines.append(f"[simCrash] asi {key}: {value}")
    threads = body.get("threads") or []
    faulting = body.get("faultingThread")
    if isinstance(faulting, int) and 0 <= faulting < len(threads):
        thread = threads[faulting]
        lines.append(f"[simCrash] faultingThread={faulting} queue={thread.get('queue', '')} name={thread.get('name', '')}")
        for depth, frame in enumerate((thread.get("frames") or [])[:MAX_FRAMES]):
            lines.append(f"[simCrash]   {depth:2d} {frame_line(frame, images)}")
    last = body.get("lastExceptionBacktrace") or []
    if last:
        lines.append("[simCrash] lastExceptionBacktrace:")
        for depth, frame in enumerate(last[:MAX_FRAMES]):
            lines.append(f"[simCrash]   {depth:2d} {frame_line(frame, images)}")
    return lines


def crash_files(folder, since):
    if not folder.is_dir():
        return []
    found = []
    for path in folder.rglob("*.ips"):
        try:
            if path.name.startswith(APP_PREFIXES) and path.stat().st_mtime >= since:
                found.append(path)
        except OSError:
            continue
    return sorted(found, key=lambda p: p.stat().st_mtime)


def main(argv):
    if len(argv) < 2:
        print("使い方: sim-crash-summary.py <印のファイル> [<記録の置き場>]", file=sys.stderr)
        return 0
    try:
        since = pathlib.Path(argv[1]).stat().st_mtime
    except OSError:
        since = 0
    folder = pathlib.Path(argv[2]) if len(argv) > 2 else pathlib.Path.home() / "Library/Logs/DiagnosticReports"
    files = crash_files(folder, since)
    if not files:
        print("[simCrash] この回にアプリが落ちた記録（.ips）はありません")
        return 0
    for path in files[:5]:
        try:
            header, body = parse_ips(path.read_text(encoding="utf-8", errors="replace"))
        except OSError as error:
            print(f"[simCrash] {path.name} を読めません: {error}")
            continue
        print("\n".join(render(header, body, path.name)))
    if len(files) > 5:
        print(f"[simCrash] ほか {len(files) - 5} 件")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
