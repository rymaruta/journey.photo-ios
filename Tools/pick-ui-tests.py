#!/usr/bin/env python3
"""枝の確認（`ios-testflight.yml` の `submit=false`）で流す UI テストを、名前の一部で絞る。

**なぜ絞るか**（2026-10-17・run 462 の実測）: Mac の1回 約69分のうち、UI テストが 33分
（画面の絵 `ScreenshotTests` 19分・メダル 11分・ほか 4分）。変えたのが1画面でも、毎回
全部の画面を起動からたどって撮っていた。枝の確認では**変えた画面の絵だけ**撮れば足りる。

**全部を回す場所は別にある**: main に入る前の「PR の検証」の Mac の job は、絞らずに全部を
回す（絞った回は「Mac でテスト済み」と数えない＝飛ばさない）。TestFlight に上げる回も絞らない。

    python3 Tools/pick-ui-tests.py "撮影スポット, Pass"
        → xcodebuild に渡す `-only-testing:...` を1行ずつ出す

- 空・`all`・`全部` → 全部（`-only-testing:JourneyPhotoUITests`）
- `none`・`なし` → 起動の見張り（`SmokeTests`）だけ
- それ以外 → 区切り（`,` か `、`）ごとに、**テストの名前**（`ScreenshotTests/testCapturesPass`）
  か、**そのテストが撮る絵の名前**（`"13f-撮影スポット（光の時刻）"` などの文字列。中で呼ぶ
  補助の関数の分も含む）に、大文字小文字を問わず含まれるものを選ぶ。
  **起動の見張り（`SmokeTests`・2分弱）はいつも足す**（落ちずに描けるかは毎回見る）
- どれにも当たらない語があれば、候補を出して止める（打ち間違いで0件のまま緑にしない）

**名指しした回だけ流す UI テスト**（`ONLY_WHEN_NAMED`・2026-10-22）: 家具の脚の接写（49 頁・約5分）・額の頁（60 頁あまり・約6〜7分）のように、
直している間だけ見る絵は、全部を回す回（空・`all`・PR の検証・TestFlight）では流さない。
`Tools/xcode-test.sh ui` が、一覧に名前が無ければ `-skip-testing:` を足す
（`python3 Tools/pick-ui-tests.py --only-when-named` で名前を出す）
"""
import os
import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
# 読む場所は差し替えられる（`check-config.py` が「空なら読まない」を確かめるのに使う）
UI_DIR = pathlib.Path(os.environ.get("JP_UI_TESTS_DIR") or (ROOT / "UITests" / "JourneyPhotoUITests"))
TARGET = "JourneyPhotoUITests"
ALWAYS = "SmokeTests"
# 名指しした回だけ流す（全部を回す回では飛ばす）。「Class/testName」
# 2026-10-22: 額の頁（写真を入れられる額 120 点あまり × 横長・縦長 = 60 頁あまり・1 頁 6 秒ほどで約 6〜7 分）も同じ扱い。
# 印画が写真の外を読まないことは単体テスト（`testEveryPhotoPanelHasPlanarUVs`・`testPhotoFitCropsInsideThePhotoAndKeepsAspect`）が毎回見る
ONLY_WHEN_NAMED = ["ScreenshotTests/testCapturesCamperFurnitureLegs", "ScreenshotTests/testCapturesCamperRoomFrameSheet",
                   # 2026-10-31（#430）: とおまわり号の描画を測る試験（4 本・計 6 分ほど）。直している間だけ `screens=testMeasuresCamperRender` で流す
                   "ScreenshotTests/testMeasuresCamperRenderExterior", "ScreenshotTests/testMeasuresCamperRenderNight",
                   "ScreenshotTests/testMeasuresCamperRenderRoom", "ScreenshotTests/testMeasuresCamperRenderRoomNight"]

# クラスの直下（字下げ4つ）の関数だけを区切りにする。中の入れ子の関数は本体に含める
MEMBER = re.compile(r"^    (?:@\w+\s+)*(?:(?:private|fileprivate|override|static|final)\s+)*func\s+(\w+)\s*\(", re.M)
CLASS = re.compile(r"^(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase", re.M)
STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def nfc(text):
    # macOS のファイル名は NFD で返る（`export-screenshots.sh` の注記）。比べる前に揃える
    return unicodedata.normalize("NFC", text).casefold()


def read_tests(directory=UI_DIR):
    """{"Class/testName": 探す文字列} を返す。文字列には名前と、撮る絵の名前（補助の関数の分も）を入れる"""
    tests = {}
    for path in sorted(directory.glob("*.swift")):
        source = path.read_text(encoding="utf-8")
        found = CLASS.search(source)
        if not found:
            continue
        cls = found.group(1)
        members = list(MEMBER.finditer(source))
        bodies = {}
        for index, member in enumerate(members):
            end = members[index + 1].start() if index + 1 < len(members) else len(source)
            bodies[member.group(1)] = source[member.start():end]

        def texts(name, seen):
            if name in seen or name not in bodies:
                return []
            seen.add(name)
            body = bodies[name]
            out = STRING.findall(body)
            for helper in bodies:
                if helper != name and re.search(r"\b" + re.escape(helper) + r"\s*\(", body):
                    out += texts(helper, seen)
            return out

        for name in bodies:
            if name.startswith("test"):
                tests[f"{cls}/{name}"] = "\n".join([f"{cls}/{name}", *texts(name, set())])
    return tests


def wants_all(screens):
    """空・`all`・`全部` なら True（UI テストのファイルを読む前に決める）"""
    words = [w.strip() for w in re.split(r"[,、]", screens or "") if w.strip()]
    return not words or any(nfc(w) in ("all", "全部") for w in words)


def pick(screens, tests):
    """xcodebuild の引数の並びと、当たらなかった語を返す"""
    words = [w.strip() for w in re.split(r"[,、]", screens or "") if w.strip()]
    if wants_all(screens):
        return [f"-only-testing:{TARGET}"], []
    chosen = {name for name in tests if name.startswith(f"{ALWAYS}/")}
    missing = []
    for word in words:
        if nfc(word) in ("none", "なし"):
            continue
        hits = [name for name, text in tests.items() if nfc(word) in nfc(text)]
        if not hits:
            missing.append(word)
        chosen.update(hits)
    # `SmokeTests` は全件なのでクラスごと渡す（1件ずつより短い）
    args = [f"-only-testing:{TARGET}/{ALWAYS}"]
    args += [f"-only-testing:{TARGET}/{name}" for name in sorted(chosen) if not name.startswith(f"{ALWAYS}/")]
    return args, missing


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--only-when-named":
        print("\n".join(ONLY_WHEN_NAMED))
        return 0
    screens = sys.argv[1] if len(sys.argv) > 1 else ""
    # **全部のときはファイルを読まない**（2026-10-17）。上げる回（submit=true）はいつも全部で、
    # UI テストのファイルの書き方に左右される理由が無い
    if wants_all(screens):
        print(f"-only-testing:{TARGET}")
        return 0
    tests = read_tests()
    if not tests:
        print(f"UI テストが読めません（{UI_DIR}）", file=sys.stderr)
        return 1
    args, missing = pick(screens, tests)
    if missing:
        print("::error::次の語に当たる UI テストがありません: " + " / ".join(missing), file=sys.stderr)
        print("テストの名前（`Class/test…`）か、撮る絵の名前の一部で指す。候補:", file=sys.stderr)
        for name in sorted(tests):
            print(f"  {name}", file=sys.stderr)
        return 2
    print("\n".join(args))
    return 0


if __name__ == "__main__":
    sys.exit(main())
