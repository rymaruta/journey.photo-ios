#!/usr/bin/env python3
"""
**2つの import が揃って初めて見える型**を、片方だけで使っていないかを見る。

本物の SDK では `PhotosPicker` / `PhotosPickerItem` は PhotosUI と SwiftUI の
**重なりのモジュール**（cross-import overlay）にあり、`import SwiftUI` と
`import PhotosUI` の**両方**が要る。Linux の模型は PhotosUI だけで見えてしまうので、
片方を書き忘れても手元の検証は通り、Xcode でだけ落ちる
（2026-09-27: TestFlight run 157 がテストの型検査で止まった）。

    python3 Tools/check-cross-imports.py Sources Tests
"""
import os
import re
import sys

# 型 → 必要な import の組
OVERLAYS = {
    r"\bPhotosPicker(Item|SelectionBehavior)?\b": ("SwiftUI", "PhotosUI"),
}

def main(roots):
    bad = []
    for root in roots:
        for dirpath, _, files in os.walk(root):
            for name in files:
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, name)
                text = open(path, encoding="utf-8").read()
                imports = set(re.findall(r"^\s*(?:@testable\s+)?import\s+(\w+)", text, re.M))
                for pattern, needed in OVERLAYS.items():
                    # 注記の中の言及は数えない（行頭の // と /// を落とす）
                    code = re.sub(r"//.*", "", text)
                    if re.search(pattern, code):
                        missing = [m for m in needed if m not in imports]
                        if missing:
                            bad.append(f"{path}: {pattern} を使うのに import {' / '.join(missing)} が無い")
    for line in bad:
        print("  " + line)
    print(f"{len(bad)} 件")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["Sources", "Tests"]))
