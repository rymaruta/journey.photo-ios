#!/usr/bin/env python3
"""
見出しの明朝（Shippori Mincho B1 Bold）を、アプリに同梱できる大きさまで削る。

    pip install fonttools
    curl -sSfLO https://raw.githubusercontent.com/google/fonts/main/ofl/shipporiminchob1/ShipporiMinchoB1-Bold.ttf
    python3 Tools/make-display-font.py ShipporiMinchoB1-Bold.ttf

**原本は 15 MB**（sha256 d20f3981…25a、google/fonts の ofl/shipporiminchob1）。
そのまま入れるとアプリが 15 MB 太る。見出しにしか使わないので、次だけを残す:

- JIS X 0208 の非漢字（1〜8区: 記号・英数・かな・ギリシャ・キリル・罫線）と13区
- JIS X 0208 の第1水準漢字（16〜47区・2,965字）
- ASCII と Latin-1 の印字可能な字

**外の字（髙・﨑・𠮷・第2水準の地名など）は、端末のゴシックで出る**
（理由は `JPFont.swift` の冒頭。本番39枚の題と撮影地では「諧」の1字だけ）。

**名前は変えない。** Shippori Mincho は OFL だが Reserved Font Name を
宣言していない（同梱の `OFL-ShipporiMincho.txt` の1行目）ので、削った版が
同じ名前を名乗ってよい。**IBM Plex Mono は「Plex」を予約している**ので、
あちらは削らずに原本のまま入れる（このスクリプトは触らない）。

名前テーブル（著作権・ライセンスの文）は全部残す。

**手書き風の文字（Klee One SemiBold）も同じ字の組で削る**（ストーリーの
「文字と札」の書体・板 24b）。原本は 8.9 MB。Klee One も OFL で Reserved Font
Name を宣言していない（`OFL-KleeOne.txt` の1行目）ので、同じ名前のまま入れる。

    curl -sSfLO https://raw.githubusercontent.com/google/fonts/main/ofl/kleeone/KleeOne-SemiBold.ttf
    python3 Tools/make-display-font.py KleeOne-SemiBold.ttf
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

# 受け付ける原本（ファイル名 → sha256）。**取り違えた原本からは作らない**
SOURCES = {
    "ShipporiMinchoB1-Bold.ttf": "d20f3981afb8bceda5fdf8f0fb29ba51eb21518644612ccd8a183e5bd433e25a",
    "KleeOne-SemiBold.ttf": "b031ec426c23ca1143ef1f7d58bee7a79efe119ed654152f121c922202b303fd",
}
FONTS = Path(__file__).resolve().parent.parent / "Sources/JourneyPhoto/Resources/Fonts"


def jis_rows(rows):
    """区点を回して Unicode の字を集める（Python の codec に任せる）。

    **2つの対応表の和を取る。** `euc_jp` は JIS の表どおり ― を U+2015、
    〜 を U+301C に割り当てるが、Windows や Mac の入力では同じ字が
    U+2014（—）・U+FF5E（～）で来る。片方だけだと、題に打った全角の
    波線やダッシュがその字だけゴシックで出る（レビューで見つかった）。
    `euc_jis_2004` は13区（①〜⑳・Ⅰ〜Ⅹ・㈱）も読める。
    """
    chars = set()
    for codec in ("euc_jp", "euc_jis_2004"):
        for row in rows:
            for cell in range(1, 95):
                try:
                    chars.add(bytes([0xA0 + row, 0xA0 + cell]).decode(codec))
                except UnicodeDecodeError:
                    continue
    return chars


# 同じ区点の字が、入力元によって別の符号で来るもの（Windows・Mac の変換表）
VARIANTS = "—～－￠￡￢∥™"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])

    import hashlib
    expected = SOURCES.get(src.name)
    if expected is None:
        sys.exit(f"知らない原本です: {src.name}（{', '.join(SOURCES)} のどれか）")
    digest = hashlib.sha256(src.read_bytes()).hexdigest()
    if digest != expected:
        sys.exit(f"原本が違います（sha256 {digest}）。google/fonts の ofl から取り直してください")
    OUT = FONTS / src.name

    chars = set()
    chars |= jis_rows([*range(1, 9), 13])   # 非漢字（13区の丸数字・ローマ数字を含む）
    chars |= jis_rows(range(16, 48))        # 第1水準
    chars |= set(VARIANTS)
    chars |= {chr(c) for c in range(0x20, 0x7F)}
    chars |= {chr(c) for c in range(0xA0, 0x100)}

    options = subset.Options()
    options.name_IDs = ["*"]            # 著作権・ライセンスの文を落とさない
    options.name_languages = ["*"]
    options.layout_features = ["*"]     # palt・vert をそのまま
    options.notdef_outline = True
    options.glyph_names = False
    options.hinting = True

    # **時刻を書き換えない。** 既定だと保存のたびに head の更新時刻が変わり、
    # 同じ原本から作っても毎回ちがうファイルになる（差分が出て気づけない）
    font = TTFont(src, recalcTimestamp=False)
    sub = subset.Subsetter(options)
    sub.populate(text="".join(sorted(chars)))
    sub.subset(font)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    kept = len(TTFont(OUT).getBestCmap())
    print(f"{OUT.relative_to(OUT.parents[4])}: {OUT.stat().st_size:,} bytes / {kept} 字")


if __name__ == "__main__":
    main()
