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
import json
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
# 2026-10-31（札 #429）: アプリの重さを測る試験（`PerformanceTests`・合否を付けない計測・5本で約9分）も同じ扱い。
# 測りたい回だけ `inputs[screens]=PerformanceTests` で名指しする（全部の回・PR の検証・TestFlight では流さない）
ONLY_WHEN_NAMED = ["ScreenshotTests/testCapturesCamperFurnitureLegs", "ScreenshotTests/testCapturesCamperRoomFrameSheet",
                   "PerformanceTests/testLaunchTime", "PerformanceTests/testLaunchAndHomeLoadSignposts",
                   "PerformanceTests/testHomeScrollMemory", "PerformanceTests/testStoryRingsMemory",
                   "PerformanceTests/testPhotoDetailMemory", "PerformanceTests/testStoryReelMemory",
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


def only_when_named(test):
    """「Class/test」が名指しした回だけ流すテストか（ONLY_WHEN_NAMED にテストの名前かクラスの名前がある）"""
    return test in ONLY_WHEN_NAMED or test.split("/", 1)[0] in ONLY_WHEN_NAMED


def sharded(submit, store_shots, screens):
    """UI テストを別々の Mac に分けて流す回か（2026-10-31・#429）。上げない回（submit=false）で、全部を流すとき
    （screens が空・all・全部 を含む——`wants_all` と同じ決め方——か、storeShots で screens を捨てるとき）"""
    return not submit and (store_shots or wants_all(screens))


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


# ---- 全部の回を「先に流す段」と「分けた段」に割る（2026-10-31 判断・#429） -----------------
# run 778（41187923424）の実測: 全部の回 128 分のうち UI テストが 109 分（1台で1本ずつ順に流していた）。
# Mac を3台にして同時に流し、その前に「枝で変えた画面のテスト」だけを別の Mac で先に流す。
# 先に流した分が落ちたら、分けた段は走らない（全部の段まで進めずに止まる）。
# 先に流した分は分けた段から抜くので、テストの本数は変わらない（1本も足さない・減らさない）
TIMES = ROOT / "Tools" / "ui-test-times.json"
# 先に流す段の上限（秒・時間の表での見積もり）。先に流す段は単体テスト（run 778 で 8 分）と別の Mac で
# 同時に走るので、単体より短ければ通る回は延びない。起動の見張り（SmokeTests・90 秒）を含めて 7 分
FIRST_BUDGET = 420
# 識別子らしい文字列（`camper.room.contact` の形）。画面のコードとテストの両方に同じ文字列で現れる
IDENT = re.compile(r"^[a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9_-]+)+$")
TYPE_DECL = re.compile(r"^(?:\w+\s+)*(?:enum|struct|class|extension)\s+(\w+)", re.M)


def read_index(directory=UI_DIR):
    """テストごとに {file, lines: 自分と呼ぶ補助の関数の行の範囲, literals: 文字列の集合, text: 本文} を返す。
    `read_tests` と同じ区切り（クラスの直下の関数）で、補助の関数を呼ぶ先までたどる。
    2つ目の戻り値は、クラスの無いファイル（`TripsTabWait.swift` などの共通の助け）ごとの型の名前"""
    index = {}
    loose = {}
    for path in sorted(directory.glob("*.swift")):
        source = path.read_text(encoding="utf-8")
        found = CLASS.search(source)
        if not found:
            loose[path.name] = set(TYPE_DECL.findall(source))
            continue
        cls = found.group(1)
        members = list(MEMBER.finditer(source))
        spans, bodies = {}, {}
        for i, member in enumerate(members):
            end = members[i + 1].start() if i + 1 < len(members) else len(source)
            bodies[member.group(1)] = source[member.start():end]
            spans[member.group(1)] = (source.count("\n", 0, member.start()) + 1, source.count("\n", 0, end) + 1)
        # クラスの頭（最初の関数より前・性質や定数）を変えたら、そのクラスのテストは全部が当たる
        head = (1, spans[members[0].group(1)][0]) if members else (1, source.count("\n") + 2)

        def reach(name, seen):
            if name in seen or name not in bodies:
                return
            seen.add(name)
            for helper in bodies:
                if helper != name and re.search(r"\b" + re.escape(helper) + r"\s*\(", bodies[name]):
                    reach(helper, seen)

        for name in bodies:
            if not name.startswith("test"):
                continue
            seen = set()
            reach(name, seen)
            index[f"{cls}/{name}"] = {
                "file": path.name,
                "lines": [spans[m] for m in seen] + [head],
                "literals": {lit for m in seen for lit in STRING.findall(bodies[m])},
                "text": "\n".join(bodies[m] for m in seen),
            }
    return index, loose


def changed_files(diff_text):
    """unified diff から {ファイル: (新しい側の変えた行の集合, 足した行と消した行の本文)} を返す"""
    files, current, line = {}, None, 0
    for raw in diff_text.splitlines():
        if raw.startswith("diff --git "):
            current = None
        elif raw.startswith("+++ ") and current is None:
            name = raw[4:].strip()
            current = None if name == "/dev/null" else name[2:] if name.startswith("b/") else name
            if current:
                files.setdefault(current, (set(), []))
        elif raw.startswith("@@") and current:
            found = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", raw)
            line = int(found.group(1)) if found else 0
            # 消しただけの塊（+n,0）は、その位置の行を変えた行として数える
            if found and found.group(2) == "0":
                files[current][0].add(max(line, 1))
        elif current and raw.startswith("+"):
            files[current][0].add(line)
            files[current][1].append(raw[1:])
            line += 1
        elif current and raw.startswith("-"):
            files[current][1].append(raw[1:])
        elif current and raw.startswith(" "):
            line += 1
    return files


def tests_for_diff(diff_text, index, loose, root=ROOT):
    """枝で変えたファイルから、先に流す UI テストを選ぶ。{テスト: 選んだ理由} を返す。
    - UI テストのファイル: 変えた行を含む関数（呼ぶ先の補助の関数を含む）を持つテスト。
      クラスの頭（関数の前）を変えたら、そのクラスの全部
    - クラスの無い UI テストのファイル（共通の助け）: そこで宣言した型の名前を使うテスト
    - アプリのコード: 識別子らしい文字列（`camper.room.contact` の形）が、テストの文字列にそのまま現れるテスト。
      ファイルの今の中身と、消した行の両方から拾う（消した識別子を待つテストも先に落ちる）"""
    try:
        ui_prefix = UI_DIR.resolve().relative_to(root).as_posix() + "/"
    except ValueError:
        ui_prefix = None
    chosen = {}
    for path, (lines, texts) in changed_files(diff_text).items():
        if not path.endswith(".swift"):
            continue
        if ui_prefix and path.startswith(ui_prefix):
            name = path[len(ui_prefix):]
            if name in loose:
                for test, info in index.items():
                    if any(re.search(r"\b" + re.escape(t) + r"\b", info["text"]) for t in loose[name]):
                        chosen.setdefault(test, f"共通の助け {name}")
                continue
            for test, info in index.items():
                if info["file"] == name and any(a <= n < b for n in lines for a, b in info["lines"]):
                    chosen.setdefault(test, f"テストの {name}")
            continue
        # アプリのコードだけ見る（単体テスト・模型 `Shims/` は画面を変えない）
        if not path.startswith("Sources/"):
            continue
        sources = list(texts)
        if (root / path).exists():
            sources.append((root / path).read_text(encoding="utf-8", errors="replace"))
        idents = {lit for text in sources for lit in STRING.findall(text) if IDENT.match(lit)}
        for test, info in index.items():
            hit = sorted(idents & info["literals"])
            if hit:
                chosen.setdefault(test, f"{pathlib.Path(path).name} の {hit[0]}")
    return chosen


def read_times(path=None):
    try:
        data = json.loads((path or TIMES).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return {k: float(v) for k, v in data.get("seconds", {}).items()}


def estimate(tests, times):
    """時間の表に無いテスト（新しく足したもの）は、表の中央の値で見積もる（割り振りが崩れない）"""
    known = sorted(times[t] for t in tests if t in times) or [60.0]
    middle = known[len(known) // 2]
    return {t: times.get(t, middle) for t in tests}


def balance(tests, seconds, parts):
    """長いものから順に、いまいちばん軽い組に入れる（LPT）。同じ長さは名前の順（毎回同じ割り振り）"""
    bins = [[] for _ in range(parts)]
    load = [0.0] * parts
    for test in sorted(tests, key=lambda t: (-seconds[t], t)):
        i = min(range(parts), key=lambda k: (load[k], k))
        bins[i].append(test)
        load[i] += seconds[test]
    return bins, load


def plan(first_words, diff_text, parts, index=None, loose=None, times=None):
    """全部の回の割り振りを決める。
    返すのは {first: 先に流す段の引数, parts: 組ごとの引数, first_seconds, loads, notes, missing}"""
    if index is None:
        index, loose = read_index()
    times = read_times() if times is None else times
    runnable = {t for t in index if not only_when_named(t)}
    seconds = estimate(sorted(index), times)
    smoke = {t for t in runnable if t.startswith(f"{ALWAYS}/")}
    notes = []
    if first_words.strip() and not wants_all(first_words):
        # 指定があればそれを先に流す（`screens` と同じ書き方・`pick` をそのまま使う）。上限は掛けない
        args, missing = pick(first_words, {t: f"{t}\n" + "\n".join(sorted(index[t]["literals"])) for t in index})
        if missing:
            return {"missing": missing}
        first = {a.split(f"{TARGET}/", 1)[1] for a in args if a.count("/") >= 2} & set(index)
        notes.append(f"先に流す: 指定（{first_words}）")
        # 🔴 **名指しした回だけ流すテスト（ONLY_WHEN_NAMED）も、`first` で名指しすれば先に流す**（2026-10-31）。
        # 前は流せる一覧から外してから選んでいたので、`first=PerformanceTests` が黙って0本になった
        # （`claude/app-perf-429` と合わせた木で見つかった）。分けた組には入れない（全部の回では流さない決まりのまま）
        named = sorted(t for t in first if only_when_named(t))
        if named:
            notes.append("名指しした回だけ流すテストを、指定どおり先に流す: " + "・".join(named))
    else:
        found = tests_for_diff(diff_text, index, loose or {})
        first, used, later = set(), sum(seconds[t] for t in smoke), []
        # 短いものから詰める（上限の中で、変えた画面のテストをなるべく多く先に見る）
        # 🔴 **名指しした回だけ流すテストは、差分から選ばない**（2026-10-31・見直しの指摘）。`seconds` には名指し専用も
        # 入っているので、`runnable`（名指し専用を除いたもの）で絞る。入れると全部の回で家具の脚の接写などが流れる
        for test in sorted((t for t in found if t in runnable and t not in smoke), key=lambda t: (seconds[t], t)):
            if used + seconds[test] <= FIRST_BUDGET:
                first.add(test)
                used += seconds[test]
                notes.append(f"先に流す: {test}（{found[test]}・見積もり {seconds[test]:.0f} 秒）")
            else:
                later.append(test)
        if later:
            notes.append(f"変えた画面のテストのうち {len(later)} 本は、先に流す段の上限（{FIRST_BUDGET} 秒）を越えるので"
                         f"分けた段で流す: " + "・".join(later[:5]) + (" ほか" if len(later) > 5 else ""))
        if not found:
            notes.append("枝で変えた画面の UI テストは見つからなかった（先に流すのは起動の見張りだけ）")
    first_all = first | smoke
    rest = sorted(t for t in runnable if t not in first_all)
    bins, load = balance(rest, seconds, parts)
    groups = [[f"-only-testing:{TARGET}/{t}" for t in sorted(group)] for group in bins[:-1]]
    # 🔴 **最後の組は「全部から、ほかで流すものを抜いた残り」**。この台本が読み落としたテスト
    # （書き方が変わって関数の区切りに当たらないもの）も、ここで必ず流れる（黙って減らない）
    others = first_all | {t for group in bins[:-1] for t in group}
    groups.append([f"-only-testing:{TARGET}"] + [f"-skip-testing:{TARGET}/{t}" for t in sorted(others)])
    first_args = [f"-only-testing:{TARGET}/{ALWAYS}"] + [f"-only-testing:{TARGET}/{t}" for t in sorted(first)
                                                          if t not in smoke]
    return {"first": first_args, "parts": groups, "first_seconds": sum(seconds[t] for t in first_all),
            "loads": load, "notes": notes, "missing": [], "counts": [len(first_all)] + [len(b) for b in bins]}


def times_from_log(log_text):
    """xcodebuild の全文ログから、UI テスト1本ずつの秒数を読む
    （`Test Case '-[JourneyPhotoUITests.X testY]' passed (12.3 seconds).`）"""
    found = re.findall(r"Test Case '-\[" + TARGET + r"\.(\w+) (\w+)\]' (?:passed|failed|skipped) \(([0-9.]+) seconds\)",
                       log_text)
    return {f"{cls}/{name}": round(float(sec), 1) for cls, name, sec in found}


def main_plan(argv):
    """python3 Tools/pick-ui-tests.py --plan <組の数> <出す場所> <先に流す語> [<diff のファイル>]"""
    parts, out, words = int(argv[0]), pathlib.Path(argv[1]), argv[2]
    diff_text = ""
    if len(argv) > 3 and pathlib.Path(argv[3]).is_file():
        diff_text = pathlib.Path(argv[3]).read_text(encoding="utf-8", errors="replace")
    result = plan(words, diff_text, parts)
    if result["missing"]:
        print("::error::先に流す語に当たる UI テストがありません: " + " / ".join(result["missing"]), file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    (out / "first.txt").write_text("\n".join(result["first"]) + "\n", encoding="utf-8")
    for i, group in enumerate(result["parts"], 1):
        # 空の組は空のファイルにする（`Tools/xcode-test.sh` は、渡された一覧が空なら何も流さない）
        (out / f"part-{i}.txt").write_text("".join(f"{a}\n" for a in group), encoding="utf-8")
    counts = result["counts"]
    lines = [f"- 先に流す段: {counts[0]} 本・見積もり {result['first_seconds'] / 60:.1f} 分"]
    lines += [f"- 分けた段 {i}: {counts[i]} 本・見積もり {sec / 60:.1f} 分" for i, sec in enumerate(result["loads"], 1)]
    lines += [f"- {note}" for note in result["notes"]]
    (out / "plan.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return 0


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--only-when-named":
        print("\n".join(ONLY_WHEN_NAMED))
        return 0
    if len(sys.argv) > 1 and sys.argv[1] == "--sharded":
        # 全部の回を別々の Mac に分けて流すか（`ios-testflight.yml` の2か所がこれを呼ぶ・式を2つ書かない）。
        # python3 Tools/pick-ui-tests.py --sharded <submit> <storeShots> <screens>
        submit, store = (sys.argv[2:4] + ["", ""])[:2]
        screens = sys.argv[4] if len(sys.argv) > 4 else ""
        print("true" if sharded(submit == "true", store == "true", screens) else "false")
        return 0
    if len(sys.argv) > 1 and sys.argv[1] == "--plan":
        return main_plan(sys.argv[2:])
    if len(sys.argv) > 2 and sys.argv[1] == "--count-log":
        # 流れた本数を数える（分けて流した回が、前の1台の回と同じ本数か）。同じテストが2つの台で流れたら名指し
        text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")
        ui = re.findall(r"Test Case '-\[" + TARGET + r"\.(\w+ \w+)\]' (passed|failed|skipped)", text)
        unit = re.findall(r"Test Case '-\[JourneyPhotoTests\.\w+ \w+\]' (?:passed|failed|skipped)", text)
        names = [n for n, _ in ui]
        # xctest の束ごとの「Executed N tests」も足す（名前の書き方で上の数え方から漏れたものも数に入る）
        executed = {}
        for bundle, count in re.findall(r"Test Suite '(\w+)\.xctest' (?:passed|failed) at [^\n]*\n\s*Executed (\d+) test", text):
            executed[bundle] = executed.get(bundle, 0) + int(count)
        print(f"### 流れたテスト: 単体 {len(unit)} 本・UI {len(set(names))} 本"
              f"（落ちた UI {len({n for n, r in ui if r == 'failed'})} 本）")
        print("xcodebuild の数（束ごとの Executed の合計）: "
              + "・".join(f"{b} {c} 本" for b, c in sorted(executed.items())))
        dup = sorted({n for n in names if names.count(n) > 1})
        if dup:
            print("UI で2回以上流れたもの: " + " / ".join(dup))
        return 0
    if len(sys.argv) > 2 and sys.argv[1] == "--times-from-log":
        # 時間の表を作り直す: python3 Tools/pick-ui-tests.py --times-from-log <xcodebuild-full.log> "<どの回か>"
        seconds = times_from_log(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace"))
        if not seconds:
            print("ログに UI テストの時間が見つかりません", file=sys.stderr)
            return 1
        TIMES.write_text(json.dumps({"source": sys.argv[3] if len(sys.argv) > 3 else "",
                                     "seconds": dict(sorted(seconds.items()))},
                                    ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"{len(seconds)} 本の時間を {TIMES.name} に書きました")
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
