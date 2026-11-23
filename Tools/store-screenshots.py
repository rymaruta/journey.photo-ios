#!/usr/bin/env python3
"""App Store のスクリーンショットを、**シミュレータの画面写真そのまま**で出す（合成しない・縮めない）。

    python3 Tools/store-screenshots.py <大型の材料> <中型の材料> <出力先>

    python3 Tools/store-screenshots.py --only-testing   # 撮るのに要る UI テストだけを xcodebuild の引数で出す

    python3 Tools/store-screenshots.py --check-demo     # 撮る UI テストが見本の表示（-JPStoreDemo）だけで撮るかを見る

    python3 Tools/store-screenshots.py --device large|medium   # 撮る機種の名前（無ければ終了コード 1）

    python3 Tools/store-screenshots.py --ios <機種の名前>       # そのシミュレータの iOS の版（README に書く）

2026-11-23 owner「ちゃんと実機通りのスクショかも見ないといけない。イメージで作るのはダメ」: 前は黒地に真鍮の小見出しと明朝の
見出しを足し、画面を縮めて置いていた（合成）。いまは、2組の枠の寸法がそのまま出る機種のシミュレータで撮った画面を、
**そのまま**ストアの絵にする:

- 大型（Dynamic Island 搭載 iPhone の大型ディスプレイ）1320×2868: iPhone 17 Pro Max（無ければ 16 Pro Max）
- 中型（Dynamic Island 搭載 iPhone の中型ディスプレイ）1206×2622: iPhone 17 Pro（無ければ 16 Pro）

材料の寸法が枠と1画素でも違えば、その枚は作らず赤にする（**縮めて合わせない**）。状態のバーは撮る前に Apple の決まった形
（9:41・電波と電池が満タン・`Tools/store-status-bar.sh`）にする。

<大型の材料>・<中型の材料> は `xcrun xcresulttool export attachments` で取り出した所
（`manifest.json` と、名前が UUID の png が並んだところ）。CI では `Tools/upload-store-shots.sh` が
`ios-testflight.yml` の `storeShots: true` の回に呼び、出来た絵を**非公開の S3** に置く（札 #604）。
並びは docs/APP_STORE_METADATA.md の「画面写真」と同じ。**材料の絵が無い枚は作らない**。
作れなかった枚は最後に一覧で出し、終了コード 1 を返す。Pillow が要る（`pip install pillow`）。
README に機種の名前と iOS の版を書く（環境変数 `STORE_DEVICE_LARGE`・`STORE_DEVICE_MEDIUM`・`STORE_IOS`）。
"""
import json
import os
import shutil
import sys
import unicodedata

# Pillow は絵を作るときだけ読む（`--only-testing` は Mac の素の python3 で呼ぶ。Pillow が無い）
Image = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 出す枠（置き場, 寸法, App Store Connect の枠の名前, 材料の組, 撮る機種の候補（先に在るもの））。
# Apple の今の決まりでは「iPhone with Dynamic Island (medium display)」が最低1枚要る（2026-11-23）
FRAMES = [
    ("", (1320, 2868), "Dynamic Island 搭載 iPhone（大型ディスプレイ）", "large",
     ["iPhone 17 Pro Max", "iPhone 16 Pro Max"]),
    ("medium-1206x2622", (1206, 2622), "Dynamic Island 搭載 iPhone（中型ディスプレイ）", "medium",
     ["iPhone 17 Pro", "iPhone 16 Pro"]),
]

# (出力の名前, 材料の画面写真の名前の頭)。アプリの芯の輪の順（見つける → 計画する → 撮る、載せる → 話す）。
# 2026-11-23（owner「AIに頼むって文字ないような」）: 宣伝文の先頭が AI なので、検索結果に出る最初の3枚に入る2枚目に AI に頼む
SLIDES = [
    ("01-ホーム", "10-ホーム"),
    ("02-AI に頼む", "90-ストア・AI に頼む"),
    ("03-観光スポット", "70-ストア・撮影スポット"),
    ("04-旅行プラン", "66c-旅行プラン（仲間と共有・日程）"),
    ("05-投稿", "42-投稿（写真の編集の入口）"),
    ("06-ストーリー", "62a-ストーリーの曲の札"),
    ("07-メッセージ", "86m4-メッセージ（会話）"),
    ("08-写真の詳細", "20-写真の詳細"),
]

# 審査（App 内課金の審査）に出す絵。大型の材料をそのまま置く（出力の名前, 材料の名前の頭）
REVIEW = [
    ("review-Pro の案内", "81-Pro の案内"),
]

# 上の材料を撮る UI テスト（「Class/test」）。`storeShots` の回はこれだけを流す（2026-11-22 判断・札 #604）。
# 全部の UI テスト（4台・約1時間）を流さずに、Mac の回を30分に収める（CLAUDE.md「Mac のテストは毎回30分以内」）。
# 名前の一部で選ぶ `pick-ui-tests.py` の書き方だと、`testCapturesProPaywall` が `…FromTrunk` まで拾うので、ここは名前で決め打つ。
# 材料とテストの対応は `Tools/check-config.py` が見る（材料の名前がテストの中から消えたら止まる）
STORE_TESTS = [
    # 2026-11-23（札 #604・owner「写真ないので見本でお願い」）: 見本の表示（`-JPStoreDemo YES`）だけで撮る試験に替えた。
    # 画像はアプリに入っている構図の作例写真（CC0）、文は作った見本、ネットワークからは何も読まない（`StoreDemo`）。
    # 前の材料（`testCapturesEveryScreen` など）は本番の公開写真と実在の利用者で描いていたので、ストアには使えない
    "ScreenshotTests/testStoreDemoHomeAndDetail",  # 10-ホーム・20-写真の詳細
    "ScreenshotTests/testStoreDemoAsk",            # 90-ストア・AI に頼む
    "ScreenshotTests/testStoreDemoSpot",           # 70-ストア・撮影スポット
    "ScreenshotTests/testStoreDemoTripPlan",       # 66c-旅行プラン（仲間と共有・日程）
    "ScreenshotTests/testStoreDemoUpload",         # 42-投稿（写真の編集の入口）
    "ScreenshotTests/testStoreDemoStorySong",      # 62a-ストーリーの曲の札
    "ScreenshotTests/testStoreDemoMessages",       # 86m4-メッセージ（会話）
    "ScreenshotTests/testStoreDemoProPaywall",     # 81-Pro の案内（審査用）
]
UI_TARGET = "JourneyPhotoUITests"
UI_DIR = os.path.join(ROOT, "UITests", UI_TARGET)
# 見本の表示で起動する印と、ストアの絵に使ってはいけない起動の引数（本番の向き先・実在の利用者で描く道）
DEMO_MARK = "-JPStoreDemo"
FORBIDDEN = ("-JPSiteBaseURL", "-JPUserApiBaseURL", "-JPPreviewUserId")
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


def check_demo(ui_dir=UI_DIR):
    """`STORE_TESTS` の試験が、見本の表示（`-JPStoreDemo YES`）だけで撮っているか（2026-11-23・札 #604）。
    試験の本文と、そこから呼ぶ補助の関数の字を見る（`pick-ui-tests.py` の `read_tests` と同じ読み方）。
    見本の印が無い・本番の向き先や実在の利用者を渡している試験の名前を返す（空なら良い）"""
    import importlib.util
    spec = importlib.util.spec_from_file_location("pick_ui_tests", os.path.join(ROOT, "Tools", "pick-ui-tests.py"))
    pick = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pick)
    from pathlib import Path
    tests = pick.read_tests(Path(ui_dir))
    bad = []
    for test in STORE_TESTS:
        text = tests.get(test)
        if text is None:
            bad.append(f"{test}（UI テストに無い）")
        elif DEMO_MARK not in text:
            bad.append(f"{test}（見本の表示 {DEMO_MARK} で起動していない）")
        elif any(word in text for word in FORBIDDEN):
            bad.append(f"{test}（本番の向き先か実在の利用者を渡している）")
    return bad


def pick_device(kind, available):
    """撮る機種（`FRAMES` の候補のうち、その場に在る最初のもの）。無ければ None（縮めて合わせる機種には落とさない）"""
    for _, _, _, frame_kind, candidates in FRAMES:
        if frame_kind == kind:
            return next((name for name in candidates if name in available), None)
    return None


def available_devices():
    import subprocess
    raw = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                         capture_output=True, text=True, check=True).stdout
    return {d["name"] for ds in json.loads(raw).get("devices", {}).values() for d in ds if d.get("isAvailable")}


def runtime_of(name, payload):
    """その機種のシミュレータの iOS の版（「iOS 26.1」）。無ければ「?」"""
    for runtime, devices in payload.get("devices", {}).items():
        if any(d.get("name") == name and d.get("isAvailable") for d in devices):
            tail = runtime.rsplit(".", 1)[-1]          # iOS-26-1
            head, _, version = tail.partition("-")
            return f"{head} {version.replace('-', '.')}" if version else tail
    return "?"


def copy_exact(src, dest, size):
    """材料をそのまま書き出す。寸法が違えば書かずに理由を返す（縮めない）。透過は外す（App Store は透過の無い PNG）"""
    with Image.open(src) as image:
        if image.size != size:
            return f"寸法が {image.width}×{image.height}（{size[0]}×{size[1]} が要る・縮めて合わせない）"
        if image.mode == "RGB":
            shutil.copyfile(src, dest)
        else:
            image.convert("RGB").save(dest)
    return None


def load_pillow():
    global Image
    from PIL import Image as _image
    Image = _image


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--check-demo":
        bad = check_demo()
        for line in bad:
            print(f"::error::App Store 用の絵の試験が見本の表示で撮っていません: {line}")
        if not bad:
            print(f"App Store 用の絵の試験 {len(STORE_TESTS)} 本は、どれも見本の表示で撮ります")
        return 1 if bad else 0
    if len(sys.argv) == 2 and sys.argv[1] == "--only-testing":
        print(f"-only-testing:{UI_TARGET}/{ALWAYS}")
        for test in STORE_TESTS:
            print(f"-only-testing:{UI_TARGET}/{test}")
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "--device":
        name = pick_device(sys.argv[2], available_devices())
        if not name:
            print(f"::error::App Store 用の絵を撮る機種（{sys.argv[2]}）のシミュレータがありません（縮めて合わせない）", file=sys.stderr)
            return 1
        print(name)
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "--ios":
        import subprocess
        raw = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                             capture_output=True, text=True, check=True).stdout
        print(runtime_of(sys.argv[2], json.loads(raw)))
        return 0
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    load_pillow()
    folders = {"large": sys.argv[1], "medium": sys.argv[2]}
    out = sys.argv[3]
    os.makedirs(out, exist_ok=True)
    missing = []
    for sub, size, label, kind, _ in FRAMES:
        found = shots_by_name(folders[kind])
        folder_out = os.path.join(out, sub) if sub else out
        os.makedirs(folder_out, exist_ok=True)
        for name, prefix in SLIDES:
            path = pick(found, prefix)
            if path is None:
                missing.append(f"{label} の {name}（材料「{prefix}…」が無い）")
                continue
            why = copy_exact(path, os.path.join(folder_out, f"{name}.png"), size)
            if why:
                missing.append(f"{label} の {name}（{why}）")
            else:
                print(f"置いた（そのまま）: {os.path.join(sub, name) if sub else name}.png")
    large = shots_by_name(folders["large"])
    for name, prefix in REVIEW:
        path = pick(large, prefix)
        if path is None:
            missing.append(f"{name}（材料「{prefix}…」が無い）")
            continue
        Image.open(path).convert("RGB").save(os.path.join(out, f"{name}.png"))
        print(f"置いた（そのまま）: {name}.png")
    with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as f:
        f.write(readme(out, missing))
    if missing:
        print("作れなかった:", *missing, sep="\n  ")
        return 1
    return 0


def readme(out, missing):
    """README（合成なし・シミュレータの実際の画面・機種名・iOS の版・枠ごとの寸法）"""
    devices = {"large": os.environ.get("STORE_DEVICE_LARGE", "?"), "medium": os.environ.get("STORE_DEVICE_MEDIUM", "?")}
    parts = ["# App Store 用の絵\n\n",
             "**合成なし。シミュレータの実際の画面をそのまま**（縮めていない・状態のバーは 9:41、電波と電池が満タン）。\n\n",
             f"- iOS: {os.environ.get('STORE_IOS', '?')}\n",
             f"- コミット: {os.environ.get('GITHUB_SHA', '?')}\n- 実行: {os.environ.get('GITHUB_RUN_NUMBER', '?')}\n\n"]
    for sub, (fw, fh), label, kind, _ in FRAMES:
        folder_out = os.path.join(out, sub) if sub else out
        place = sub + "/" if sub else "./"
        parts.append(f"## {label}（{fw}×{fh}）\n\n機種: {devices[kind]}\n\n置き場: `{place}`\n\n")
        if os.path.isdir(folder_out):
            for file in sorted(os.listdir(folder_out)):
                if file.endswith(".png") and not file.startswith("review-"):
                    with Image.open(os.path.join(folder_out, file)) as image:
                        parts.append(f"- {file}: {image.width}×{image.height}\n")
        parts.append("\n")
    reviews = sorted(f for f in os.listdir(out) if f.startswith("review-") and f.endswith(".png"))
    if reviews:
        parts.append(f"## 審査用（{devices['large']} の画面そのまま・並びには入れない）\n\n")
        for file in reviews:
            with Image.open(os.path.join(out, file)) as image:
                parts.append(f"- {file}: {image.width}×{image.height}\n")
    if missing:
        parts.append("\n作れなかった: " + " / ".join(missing) + "\n")
    parts.append("\n**非公開の置き場から3日で消える。** 見終わったら手元からも消す（`Tools/fetch-shots.sh <run> --clean`）。\n")
    return "".join(parts)


if __name__ == "__main__":
    sys.exit(main())
