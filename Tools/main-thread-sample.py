#!/usr/bin/env python3
"""macOS の `sample` の出力から、**主スレッドで時間を食った関数**だけを数で出す（札 #610・2026-11-15）。

    python3 Tools/main-thread-sample.py <sample の出力> [<間隔 ms>]

単体テストの組 `APIClientThrottleRetryTests` で、試験の本体（setUp〜tearDown 0.12秒）の後に主スレッドが
18.4秒止まった（run 1348 の `measured [throttle-main]`）。何が主スレッドを止めているかを見るため、
`Tools/xcode-test.sh` がテストを載せるアプリを `sample` で取り、これで主スレッドの分だけを数える。

出すのは関数の名前・数・置き場のファイル名（`名前.swift:行`）だけ。番地・置き場のフォルダ（端末の識別子を含む）は出さない
（公開のリポジトリなので、ログに残さない）。
"""
import re
import sys

LINE = re.compile(r"^(?P<indent>[\s+!:|]*)(?P<count>\d+)\s+(?P<symbol>.+?)\s+\(in (?P<module>[^)]+)\)(?P<rest>.*)$")
THREAD = re.compile(r"^\s*(\d+)\s+Thread_\S+")
FILE = re.compile(r"([A-Za-z0-9_+\-]+\.(?:swift|m|mm|c|cpp)):(\d+)")


def main_thread_lines(lines):
    """主スレッドの塊の行（`Main Thread` の見出しから、次のスレッドの見出しまで）"""
    out, inside, total = [], False, 0
    for line in lines:
        head = THREAD.match(line)
        if head:
            if inside:
                break
            # 見出しは「Thread_<番号>: Main Thread   DispatchQueue_…」（run 1354）か「… com.apple.main-thread …」
            if "Main Thread" in line or "com.apple.main-thread" in line:
                inside, total = True, int(head.group(1))
            continue
        if inside:
            if not line.strip():
                break
            out.append(line)
    return out, total


def main():
    path = sys.argv[1]
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 10.0
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError as error:
        print(f"measured [main-sample] 読めなかった: {error.__class__.__name__}")
        return 0
    body, total = main_thread_lines(lines)
    if not body:
        # 取れなかった理由を見るため、行の数とスレッドの見出しの数・名前の種類だけ出す（番地・置き場は出さない）
        heads = [l for l in lines if THREAD.match(l)]
        kinds = sorted({re.sub(r"[0-9a-fA-Fx]{6,}", "#", l.split("Thread_", 1)[-1]).strip()[:60] for l in heads})[:8]
        first = [re.sub(r"(/[^ ]*)|0x[0-9a-fA-F]+|[0-9A-F]{8}-[0-9A-F-]{27}", "…", l).strip()[:80] for l in lines[:6]]
        print(f"measured [main-sample] 主スレッドの塊が見つからない（行 {len(lines)}・スレッドの見出し {len(heads)}）"
              f" 見出し={kinds} 頭={first}")
        return 0
    ours, deepest = {}, {}
    for line in body:
        m = LINE.match(line)
        if not m:
            continue
        count = int(m.group("count"))
        symbol = re.sub(r"\s+\+\s+\d+$", "", m.group("symbol")).strip()[:160]
        where = FILE.search(m.group("rest"))
        label = symbol + (f"  {where.group(1)}:{where.group(2)}" if where else "")
        # 主スレッドが待っているだけの所（ランループの眠り）と、いつも積みの底にある入口は数えない
        if re.search(r"mach_msg|__CFRunLoopServiceMachPort|__CFRunLoopRun|CFRunLoopRunSpecific|"
                     r"GSEventRunModal|UIApplicationMain|^start$|^main$", symbol):
            continue
        if "JourneyPhoto" in m.group("module"):
            ours[label] = max(ours.get(label, 0), count)
        key = label + f"  ({m.group('module')})"
        deepest[key] = max(deepest.get(key, 0), count)
    print(f"measured [main-sample] 主スレッドの見本 {total} 回（{interval:.0f}ms ごと）")
    for label, count in sorted(ours.items(), key=lambda kv: -kv[1])[:20]:
        print(f"measured [main-sample] アプリ {count * interval / 1000:7.2f}s {label}")
    busy = [kv for kv in deepest.items() if kv[1] * interval >= 1000]
    for label, count in sorted(busy, key=lambda kv: -kv[1])[:15]:
        print(f"measured [main-sample] 全体 {count * interval / 1000:7.2f}s {label}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
