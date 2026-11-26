#!/usr/bin/env python3
"""`assetutil --info Assets.car` の JSON を読み、絵ごとの大きさを大きい順に並べる（2026-11-26 判断・アプリの大きさ）。

    xcrun --sdk iphoneos assetutil --info Assets.car | python3 Tools/car-summary.py

呼ぶのは `Tools/app-size.sh`。JSON の頭の1件は Assets.car 全体の情報（SizeOnDisk を持たない）なので数えない。
"""
import json
import sys


def rows_of(info):
    return [r for r in info if isinstance(r, dict) and r.get("SizeOnDisk")]


def report(rows, top=60):
    total = sum(r["SizeOnDisk"] for r in rows)
    out = [f"合計 {total // 1024} KB（{len(rows)} 枚）"]
    for r in sorted(rows, key=lambda r: -r["SizeOnDisk"])[:top]:
        name = r.get("RenditionName") or r.get("Name") or "?"
        pixels = f"{r.get('PixelWidth', '?')}x{r.get('PixelHeight', '?')}"
        out.append(f"{r['SizeOnDisk'] // 1024:>7}  {name:45s} {pixels:>11}  {r.get('Compression', '')} {r.get('Encoding', '')}".rstrip())
    return "\n".join(out)


def main():
    print(report(rows_of(json.load(sys.stdin))))


if __name__ == "__main__":
    main()
