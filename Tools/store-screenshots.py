#!/usr/bin/env python3
"""App Store のスクリーンショット（6.9インチ枠・1320×2868）を、UI テストの画面写真から作る。

    python3 Tools/store-screenshots.py <画面写真の置き場> <出力先>

<画面写真の置き場> は PR の検証の「xcode-test-results」の中の `build/shots`
（`manifest.json` と、名前が UUID の png が並んだところ）。ScreenshotTests が
iPhone 17 Pro Max で撮るので、写真は 1320×2868 で届く。

1枚ごとに、上に真鍮の眉ラベルと明朝の見出し、下に画面を角丸で置く（黒地）。
色と字はデザインの板「黒塗りの真鍮」に合わせる: 地 #000・真鍮 #C9A66B（黒地の上だけ）・
見出しは Shippori Mincho B1（アプリに同梱しているもの）。

並びと見出しは docs/APP_STORE_METADATA.md の「スクリーンショット」と同じ。
**材料の絵が無い枚は作らない**（名前と中身が食い違う絵は、無い絵より悪い）。
作れなかった枚は最後に一覧で出し、終了コード 1 を返す。
Pillow が要る（`pip install pillow`）。
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MINCHO = os.path.join(ROOT, "Sources/JourneyPhoto/Resources/Fonts/ShipporiMinchoB1-Bold.ttf")

W, H = 1320, 2868
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
BRASS = (0xC9, 0xA6, 0x6B)

# (出力の名前, 材料の画面写真の名前の頭, 眉ラベル, 見出し)。見出しの改行は手で入れる
SLIDES = [
    ("01-撮影スポット", "70-ストア・撮影スポット", "撮影スポット図鑑", "日本中の「撮りたい」が、\nここに。"),
    ("02-光の時刻", "71-ストア・光の時刻", "光の時刻", "いちばん美しい時刻が\nわかる"),
    ("03-いまの季節", "10d-ホーム（いまの季節のスポット", "いまの季節", "いま見頃の場所が、\n毎日届く"),
    ("04-地図", "13b-マップ（撮影スポットのピン）", "地図で探す", "旅先の近くの撮影地を\n地図で"),
    ("05-旅の計画", "64-行きたい場所の地図で選んだ", "旅の計画", "保存して、\nそのまま旅の計画に"),
    ("06-旅の一冊", "30-旅の一冊", "旅の一冊", "撮った旅を、\n一冊の読み物に"),
]


def shots_by_name(folder):
    """manifest.json を読み、「人が読める名前」→ png の道 を返す"""
    with open(os.path.join(folder, "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    found = {}

    def walk(node):
        if isinstance(node, dict):
            name = node.get("suggestedHumanReadableName")
            file = node.get("exportedFileName")
            if name and file and file.endswith(".png"):
                found[name] = os.path.join(folder, file)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(manifest)
    return found


def pick(found, prefix):
    for name in sorted(found):
        if name.startswith(prefix):
            return found[name]
    return None


def rounded(image, radius):
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius, fill=255)
    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    out.paste(image, (0, 0), mask)
    return out


def compose(shot_path, eyebrow, heading):
    canvas = Image.new("RGB", (W, H), BLACK)
    draw = ImageDraw.Draw(canvas)
    eyebrow_font = ImageFont.truetype(MINCHO, 46)
    heading_font = ImageFont.truetype(MINCHO, 96)

    # 眉ラベル（真鍮・字間を少し空ける）
    spaced = " ".join(eyebrow)
    draw.text((W / 2, 200), spaced, font=eyebrow_font, fill=BRASS, anchor="mm")
    # 見出し（白・明朝・中央そろえ）
    draw.multiline_text((W / 2, 300), heading, font=heading_font, fill=WHITE,
                        anchor="ma", align="center", spacing=28)

    # 画面（幅 1000・角丸・細い縁。黒地の上の白 15% にあたる灰）。下は枠の外へ流す
    shot = Image.open(shot_path).convert("RGB")
    width = 1000
    height = round(shot.height * width / shot.width)
    shot = rounded(shot.resize((width, height), Image.LANCZOS), 70)
    left, top = (W - width) // 2, 620
    canvas.paste(shot, (left, top), shot)
    draw.rounded_rectangle((left - 2, top - 2, left + width + 1, top + height + 1), 72,
                           outline=(38, 38, 38), width=3)
    return canvas


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    folder, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    found = shots_by_name(folder)
    missing = []
    for name, prefix, eyebrow, heading in SLIDES:
        path = pick(found, prefix)
        if path is None:
            missing.append(f"{name}（材料「{prefix}…」が無い）")
            continue
        image = compose(path, eyebrow, heading)
        assert image.size == (W, H)
        dest = os.path.join(out, f"{name}.png")
        image.save(dest)
        print(f"作った: {dest}")
    if missing:
        print("作れなかった:", *missing, sep="\n  ")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
