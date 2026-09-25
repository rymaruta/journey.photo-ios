#!/usr/bin/env python3
"""
見出しの明朝（Shippori Mincho B1 Bold）を、アプリに同梱できる大きさまで削る。

    pip install fonttools
    curl -sSfLO https://raw.githubusercontent.com/google/fonts/main/ofl/shipporiminchob1/ShipporiMinchoB1-Bold.ttf
    python3 Tools/make-display-font.py ShipporiMinchoB1-Bold.ttf

**原本は 15 MB**（sha256 d20f3981…25a、google/fonts の ofl/shipporiminchob1）。
そのまま入れるとアプリが 15 MB 太る。見出しにしか使わないので、次だけを残す:

- JIS X 0208 の非漢字（1〜8区: 記号・英数・かな・ギリシャ・キリル・罫線）
- JIS X 0208 の第1水準漢字（16〜47区・2,965字）
- ASCII と Latin-1 の印字可能な字

**外の字（髙・﨑・𠮷・第2水準の地名など）は、画面側でヒラギノ明朝 W6 へ落とす**
（`JPFont.display` の `cascadeList`）。明朝から明朝へ落ちるので、字形の差は小さい。

**名前は変えない。** Shippori Mincho は OFL だが Reserved Font Name を
宣言していない（同梱の `OFL-ShipporiMincho.txt` の1行目）ので、削った版が
同じ名前を名乗ってよい。**IBM Plex Mono は「Plex」を予約している**ので、
あちらは削らずに原本のまま入れる（このスクリプトは触らない）。

名前テーブル（著作権・ライセンスの文）は全部残す。
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

SOURCE_SHA256 = "d20f3981afb8bceda5fdf8f0fb29ba51eb21518644612ccd8a183e5bd433e25a"
OUT = Path(__file__).resolve().parent.parent / "Sources/JourneyPhoto/Resources/Fonts/ShipporiMinchoB1-Bold.ttf"


def jis_x_0208(rows):
    """EUC-JP で区点を回し、Unicode の字を集める（Python の codec に任せる）。"""
    chars = set()
    for row in rows:
        for cell in range(1, 95):
            try:
                ch = bytes([0xA0 + row, 0xA0 + cell]).decode("euc_jp")
            except UnicodeDecodeError:
                continue
            chars.add(ch)
    return chars


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])

    import hashlib
    digest = hashlib.sha256(src.read_bytes()).hexdigest()
    if digest != SOURCE_SHA256:
        sys.exit(f"原本が違います（sha256 {digest}）。google/fonts の ofl/shipporiminchob1 から取り直してください")

    chars = set()
    chars |= jis_x_0208(range(1, 9))     # 非漢字
    chars |= jis_x_0208(range(16, 48))   # 第1水準
    chars |= {chr(c) for c in range(0x20, 0x7F)}
    chars |= {chr(c) for c in range(0xA0, 0x100)}

    options = subset.Options()
    options.name_IDs = ["*"]            # 著作権・ライセンスの文を落とさない
    options.name_languages = ["*"]
    options.layout_features = ["*"]     # palt・vert をそのまま
    options.notdef_outline = True
    options.glyph_names = False
    options.hinting = True

    font = TTFont(src)
    sub = subset.Subsetter(options)
    sub.populate(text="".join(sorted(chars)))
    sub.subset(font)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    kept = len(TTFont(OUT).getBestCmap())
    print(f"{OUT.relative_to(OUT.parents[4])}: {OUT.stat().st_size:,} bytes / {kept} 字")


if __name__ == "__main__":
    main()
