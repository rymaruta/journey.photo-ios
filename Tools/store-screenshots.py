#!/usr/bin/env python3
"""App Store のスクリーンショット（6.9インチ枠・1320×2868）を、UI テストの画面写真から作る。

    python3 Tools/store-screenshots.py <画面写真の置き場> <出力先>

    python3 Tools/store-screenshots.py --only-testing   # 撮るのに要る UI テストだけを xcodebuild の引数で出す

<画面写真の置き場> は `xcrun xcresulttool export attachments` で取り出した所
（`manifest.json` と、名前が UUID の png が並んだところ）。CI では `Tools/upload-store-shots.sh` が
`ios-testflight.yml` の `storeShots: true` の回に呼び、出来た絵を**非公開の S3** に置く（2026-11-22・札 #604）。
材料の画面の寸法が機種で変わっても、出す絵は合成で必ず 1320×2868（6.9インチの枠）になる。

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
import unicodedata

# Pillow は絵を作るときだけ読む（`--only-testing` は Mac の素の python3 で呼ぶ。Pillow が無い）
Image = ImageDraw = ImageFont = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MINCHO = os.path.join(ROOT, "Sources/JourneyPhoto/Resources/Fonts/ShipporiMinchoB1-Bold.ttf")

W, H = 1320, 2868
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
BRASS = (0xC9, 0xA6, 0x6B)

# (出力の名前, 材料の画面写真の名前の頭, 眉ラベル, 見出し)。見出しの改行は手で入れる
SLIDES = [
    # 2026-11-15（札 #604）: アプリの芯の輪の順（見つける → 計画する → 撮る、載せる → 話す）
    ("01-ホーム", "10-ホーム", "みんなの写真", "みんなの写真から、\n次の旅へ"),
    ("02-観光スポット", "70-ストア・撮影スポット", "観光スポット", "行きたい場所が、\nきっと見つかる"),
    ("03-旅行プラン", "66c-旅行プラン（仲間と共有・日程）", "旅行プラン", "仲間と一緒に、\n旅を組み立てる"),
    ("04-投稿", "42-投稿（写真の編集の入口）", "投稿", "撮った一枚を、\nすぐ載せる"),
    ("05-ストーリー", "62a-ストーリーの曲の札", "ストーリー", "24時間のストーリーで、\n旅の今を"),
    ("06-メッセージ", "86m4-メッセージ（会話）", "メッセージ", "旅の仲間と、\nそのまま話せる"),
    ("07-写真の詳細", "20-写真の詳細", "写真", "一枚の向こうの\n場所まで"),
]

# 審査（App 内課金の審査）に出す絵。合成せず、撮った原寸の PNG をそのまま置く（出力の名前, 材料の名前の頭）
REVIEW = [
    ("review-Pro の案内", "81-Pro の案内"),
]

# 上の材料を撮る UI テスト（「Class/test」）。`storeShots` の回はこれだけを流す（2026-11-22 判断・札 #604）。
# 全部の UI テスト（4台・約1時間）を流さずに、Mac の回を30分に収める（CLAUDE.md「Mac のテストは毎回30分以内」）。
# 名前の一部で選ぶ `pick-ui-tests.py` の書き方だと、`testCapturesProPaywall` が `…FromTrunk` まで拾うので、ここは名前で決め打つ。
# 材料とテストの対応は `Tools/check-config.py` が見る（材料の名前がテストの中から消えたら止まる）
STORE_TESTS = [
    "ScreenshotTests/testCapturesEveryScreen",             # 10-ホーム・20-写真の詳細・70-ストア・撮影スポット
    "ScreenshotTests/testCapturesTripShare",               # 66c-旅行プラン（仲間と共有・日程）
    "ScreenshotTests/testCapturesUploadEditEntry",         # 42-投稿（写真の編集の入口）
    "ScreenshotTests/testCapturesStorySongStickerStyles",  # 62a-ストーリーの曲の札
    "ScreenshotTests/testCapturesDirectMessages",          # 86m4-メッセージ（会話）
    "ScreenshotTests/testCapturesProPaywall",              # 81-Pro の案内（審査用）
]
UI_TARGET = "JourneyPhotoUITests"
# 起動の見張りはいつも足す（`pick-ui-tests.py` の ALWAYS と同じ）
ALWAYS = "SmokeTests"


def nfc(text):
    # macOS が返す名前は NFD のことがある（`export-screenshots.sh` の注記）。比べる前に揃える
    return unicodedata.normalize("NFC", text)


def shots_by_name(folder):
    """manifest.json を読み、「人が読める名前」→ png の道 を返す"""
    with open(os.path.join(folder, "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    found = {}

    def walk(node):
        if isinstance(node, dict):
            name = node.get("suggestedHumanReadableName")
            file = node.get("exportedFileName")
            if name and file and file.lower().endswith(".png"):
                found[nfc(name)] = os.path.join(folder, file)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(manifest)
    return found


def pick(found, prefix):
    for name in sorted(found):
        if name.startswith(nfc(prefix)):
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


def load_pillow():
    global Image, ImageDraw, ImageFont
    from PIL import Image as _image, ImageDraw as _draw, ImageFont as _font
    Image, ImageDraw, ImageFont = _image, _draw, _font


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--only-testing":
        print(f"-only-testing:{UI_TARGET}/{ALWAYS}")
        for test in STORE_TESTS:
            print(f"-only-testing:{UI_TARGET}/{test}")
        return 0
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    load_pillow()
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
    for name, prefix in REVIEW:
        path = pick(found, prefix)
        if path is None:
            missing.append(f"{name}（材料「{prefix}…」が無い）")
            continue
        dest = os.path.join(out, f"{name}.png")
        Image.open(path).save(dest)
        print(f"写した（原寸）: {dest}")
    # 何をどの寸法で作ったかの控え（`Tools/fetch-shots.sh` で落とした人が読む）
    with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as f:
        f.write("# App Store 用の絵\n\n")
        f.write(f"- コミット: {os.environ.get('GITHUB_SHA', '?')}\n- 実行: {os.environ.get('GITHUB_RUN_NUMBER', '?')}\n\n")
        for file in sorted(os.listdir(out)):
            if file.endswith(".png"):
                with Image.open(os.path.join(out, file)) as image:
                    f.write(f"- {file}: {image.width}×{image.height}\n")
        if missing:
            f.write("\n作れなかった: " + " / ".join(missing) + "\n")
        f.write("\n**非公開の置き場から3日で消える。** 見終わったら手元からも消す（`Tools/fetch-shots.sh <run> --clean`）。\n")
    if missing:
        print("作れなかった:", *missing, sep="\n  ")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
