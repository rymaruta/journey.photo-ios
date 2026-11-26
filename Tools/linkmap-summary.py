#!/usr/bin/env python3
"""リンクの地図（`LD_GENERATE_MAP_FILE=YES` が書く LinkMap.txt）から、本体のバイナリの中身を部品ごとに数える。

    python3 Tools/linkmap-summary.py build/size/JourneyPhoto-LinkMap.txt

2026-11-26 判断（アプリの大きさ）: 本体のバイナリ（run 1865 で 53MB）が ipa の大半を占めるが、
配る版は記号が消してあり、どの部品がどれだけ持っているか分からない。リンクの地図には、
残った記号ごとの大きさと、それを持ってきた .o が書いてあるので、.o の置き場から部品の名前を引いて足す。

- 部品の名前は .o の道筋の `/<名前>.build/Objects-normal/`（アプリ本体）か、`BuildProductsPath/<構成>/<名前>.o`
  （Swift Package のターゲットをまとめた .o）から取る。
  `libfoo.a(bar.o)` の形は `libfoo.a`。どれにも当たらないものは「その他」
- 数えるのは `# Symbols:` の節だけ（`# Dead Stripped Symbols:` は捨てられた分なので数えない）
- 出すのは「部品ごと（大きい順）」と「区画（__TEXT,__text など）ごと」。数は KB（1000 でなく 1024 で割る）
"""
import collections
import re
import sys

OBJECT_RE = re.compile(r"^\[\s*(\d+)\]\s+(.*)$")
SYMBOL_RE = re.compile(r"^0x[0-9A-Fa-f]+\s+0x([0-9A-Fa-f]+)\s+\[\s*(\d+)\]\s")
SECTION_RE = re.compile(r"^0x([0-9A-Fa-f]+)\s+0x([0-9A-Fa-f]+)\s+(\S+)\s+(\S+)\s*$")


def module_of(path):
    """.o の道筋から部品の名前を引く。"""
    m = re.search(r"/([^/]+)\.build/Objects-normal/", path)
    if m:
        return m.group(1)
    # Swift Package のターゲットは、まとめた1つの .o（`BuildProductsPath/Release-iphoneos/Amplify.o`）で来る（run 1871）
    m = re.search(r"/BuildProductsPath/[^/]+/([^/]+)\.o$", path)
    if m:
        return m.group(1)
    m = re.search(r"/([^/()]+\.a)\(", path)
    if m:
        return m.group(1)
    if path.startswith("linker synthesized"):
        return "（リンカーが作った分）"
    m = re.search(r"/([^/]+\.(?:tbd|dylib))$", path)
    if m:
        return "（システムの " + m.group(1) + "）"
    return "その他"


def parse(lines):
    """部品ごとの大きさ（バイト）と、区画ごとの大きさ（バイト）を返す。"""
    objects = {}
    sections = []
    by_module = collections.Counter()
    part = None
    for raw in lines:
        line = raw.rstrip("\n")
        if line.startswith("#"):
            head = line[1:].strip()
            if head.startswith("Object files"):
                part = "objects"
            elif head.startswith("Sections"):
                part = "sections"
            elif head.startswith("Dead Stripped Symbols"):
                part = "dead"
            elif head.startswith("Symbols"):
                part = "symbols"
            continue
        if part == "objects":
            m = OBJECT_RE.match(line)
            if m:
                objects[int(m.group(1))] = m.group(2)
        elif part == "sections":
            m = SECTION_RE.match(line)
            if m:
                sections.append((f"{m.group(3)},{m.group(4)}", int(m.group(2), 16)))
        elif part == "symbols":
            m = SYMBOL_RE.match(line)
            if m:
                by_module[module_of(objects.get(int(m.group(2)), ""))] += int(m.group(1), 16)
    return by_module, sections


def report(by_module, sections, top=40):
    total = sum(by_module.values())
    out = [f"記号の合計: {total // 1024} KB（部品 {len(by_module)} 個）", "", "== 部品ごと（大きい順・KB・割合）=="]
    for name, size in by_module.most_common(top):
        out.append(f"{size // 1024:>8}  {100 * size / total if total else 0:5.1f}%  {name}")
    out += ["", "== 区画ごと（大きい順・KB）=="]
    for name, size in sorted(sections, key=lambda s: -s[1])[:20]:
        out.append(f"{size // 1024:>8}  {name}")
    return "\n".join(out)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    # リンクの地図は utf-8 とは限らない（記号の名前に壊れた字が混じる）ので、読めない字は置き換える
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        by_module, sections = parse(f)
    print(report(by_module, sections))


if __name__ == "__main__":
    main()
