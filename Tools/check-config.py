#!/usr/bin/env python3
"""設定ファイルの形と、ファイルをまたいだ約束を確かめる。

Xcode が無い環境で踏みやすいのは「設定の食い違い」で、しかも**ビルドは通って
実行時に落ちる**（`AppConfig` は値が欠けていたら `fatalError` で止める）。
機械で見られるところは見る:

  1. project.yml が YAML として読めて、必要なキーがある
  2. PrivacyInfo.xcprivacy が plist として読める
  3. Assets の Contents.json が JSON として読めて、参照する画像が在る
  4. **AppConfig が読む Info.plist のキーが、project.yml に全部ある**
  5. **project.yml が参照する $(VAR) が、prod と staging の両方にある**
     ——片方だけだと、その構成のビルドが起動直後に落ちる
"""
import json
import plistlib
import re
import sys
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# **Web 側の置き場は差し替えられる。** `Tools/verify.sh` は
# `check-api-parity.py` に `PHOTO_GALLERY` を渡せるのに、こちらは
# 隣の `../photo-gallery` 固定だった——別の作業枝を出しているときに
# 「サーバーにその設定が無い」と誤って赤くなる。**同じ口を見る**
WEB = Path(os.environ.get("PHOTO_GALLERY") or (ROOT.parent / "photo-gallery")).resolve()
errors = []


def fail(message):
    errors.append(message)


# ---- 1. project.yml -------------------------------------------------------
project_text = (ROOT / "project.yml").read_text(encoding="utf-8")
try:
    import yaml  # type: ignore
    project = yaml.safe_load(project_text)
except ModuleNotFoundError:
    project = None
    print("[skip] PyYAML が無いので project.yml の構造検査は飛ばす（文字列の検査だけ行う）")

if project is not None:
    for key in ("name", "targets", "schemes", "packages"):
        if key not in project:
            fail(f"project.yml に {key} がありません")
    target = (project.get("targets") or {}).get("JourneyPhoto")
    if not target:
        fail("project.yml に JourneyPhoto ターゲットがありません")
    else:
        configs = target.get("configFiles") or {}
        for build in ("Debug", "Release"):
            path = configs.get(build)
            if not path:
                fail(f"configFiles に {build} がありません")
            elif not (ROOT / path).exists():
                fail(f"{build} の xcconfig が見つかりません: {path}")

# ---- 2. プライバシーマニフェスト -------------------------------------------
privacy_path = ROOT / "Sources/JourneyPhoto/Resources/PrivacyInfo.xcprivacy"
try:
    privacy = plistlib.loads(privacy_path.read_bytes())
except Exception as e:  # noqa: BLE001
    privacy = {}
    fail(f"PrivacyInfo.xcprivacy を plist として読めません: {e}")
else:
    for key in ("NSPrivacyTracking", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"):
        if key not in privacy:
            fail(f"PrivacyInfo.xcprivacy に {key} がありません")

# ---- 3. アセットカタログ ---------------------------------------------------
for contents in (ROOT / "Sources/JourneyPhoto/Assets.xcassets").rglob("Contents.json"):
    try:
        data = json.loads(contents.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        fail(f"{contents.relative_to(ROOT)} が JSON として読めません: {e}")
        continue
    for image in data.get("images", []):
        name = image.get("filename")
        if name and not (contents.parent / name).exists():
            fail(f"{contents.relative_to(ROOT)} が参照する {name} がありません")

# ---- 4. AppConfig が読むキー ----------------------------------------------
app_config = (ROOT / "Sources/JourneyPhoto/Config/AppConfig.swift").read_text(encoding="utf-8")
needed_plist_keys = set(re.findall(r'require(?:URL)?\("([^"]+)"\)', app_config))
for key in sorted(needed_plist_keys):
    if key not in project_text:
        fail(f"AppConfig が読む Info.plist のキー {key} が project.yml にありません")

# ---- 5. xcconfig の変数 ----------------------------------------------------
used_vars = set(re.findall(r"\$\(([A-Z0-9_]+)\)", project_text))
# Xcode が自前で持つ変数は対象外
builtin = {"PRODUCT_NAME", "EXECUTABLE_NAME", "SRCROOT", "PROJECT_DIR", "TARGET_NAME",
           "DEVELOPMENT_LANGUAGE"}
# **project.yml の settings で定義している変数も対象外。**
# 版番号のように、xcconfig ではなくビルド設定側に置くものがある
builtin |= set(re.findall(r"^\s+([A-Z][A-Z0-9_]+):", project_text, re.MULTILINE))
for name in ("Production", "Staging"):
    text = (ROOT / f"Config/{name}.xcconfig").read_text(encoding="utf-8")
    defined = set(re.findall(r"^\s*([A-Z0-9_]+)\s*=", text, re.MULTILINE))
    for var in sorted(used_vars - builtin - defined):
        fail(f"{name}.xcconfig に {var} がありません（この構成のビルドは起動直後に落ちます）")

# ---- 6. 権限を求める文が2言語そろっているか -------------------------------
#
# **ここが片方だけだと、その言語の端末に別の言語のダイアログが出る。**
# 画面の文字は `check-swift-refs.js` が見張っているが、OS が出す文は
# InfoPlist.strings 側なので、ここで見る。
usage_keys = {k for k in project_text.split() if k.startswith("NS") and k.endswith("UsageDescription:")}
usage_keys = {k.rstrip(":") for k in usage_keys}
strings_dir = ROOT / "Sources/JourneyPhoto/Resources"
for lang in ("ja", "en"):
    path = strings_dir / f"{lang}.lproj" / "InfoPlist.strings"
    if not path.exists():
        fail(f"{lang}.lproj/InfoPlist.strings がありません")
        continue
    text = path.read_text(encoding="utf-8")
    for key in sorted(usage_keys):
        if f'"{key}"' not in text:
            fail(f"{lang}.lproj/InfoPlist.strings に {key} がありません"
                 f"（この言語の端末に別の言語のダイアログが出ます）")

# ---- 7. 版番号が1か所か -----------------------------------------------------
#
# **Info.plist に直の値を書かない。** ビルド設定と食い違っても気づけず、
# TestFlight は同じビルド番号を受け付けないので毎回はねられる。
for key, setting in (("CFBundleShortVersionString", "MARKETING_VERSION"),
                     ("CFBundleVersion", "CURRENT_PROJECT_VERSION")):
    line = next((l for l in project_text.splitlines() if l.strip().startswith(f"{key}:")), "")
    if f"$({setting})" not in line:
        fail(f"project.yml の {key} は $({setting}) にしてください"
             f"（直の値だとビルド設定と食い違い、TestFlight にはねられます）: {line.strip()}")

# ---- 7.5 SWIFT_VERSION が Xcode の受け取る値か ------------------------------
#
# **ツールチェーンの版（5.9・6.0.3）ではなく「言語モード」を書く欄。**
# Xcode が受けるのは 4.0 / 4.2 / 5.0 / 6.0 だけで、それ以外は
#   error: SWIFT_VERSION '5.9' is unsupported
# で**ビルドの最初に落ちる**。手元（swift build）は project.yml を読まないので
# 気づけない＝CI で初めて分かる種類の間違い。
ALLOWED_SWIFT_VERSIONS = {"4.0", "4.2", "5.0", "6.0"}
for found in re.findall(r'SWIFT_VERSION:\s*"?([0-9.]+)"?', project_text):
    if found not in ALLOWED_SWIFT_VERSIONS:
        fail(f"project.yml の SWIFT_VERSION（{found}）は Xcode が受け取りません"
             f"（言語モードを書く欄です。使えるのは "
             f"{' / '.join(sorted(ALLOWED_SWIFT_VERSIONS))}）")

# ---- 8. Bundle ID が CI と揃っているか -------------------------------------
#
# **ずれていると署名が通らない。** しかも気づくのは CI で10分待ったあと。
# ID を取り替える場面（誰かに取られていた）で必ず踏む。
codemagic_path = ROOT / "codemagic.yaml"
if codemagic_path.exists():
    codemagic_text = codemagic_path.read_text(encoding="utf-8")
    prod = (ROOT / "Config/Production.xcconfig").read_text(encoding="utf-8")
    m = re.search(r"^\s*JP_BUNDLE_ID\s*=\s*(\S+)", prod, re.MULTILINE)
    bundle_id = m.group(1) if m else ""
    for key in ("bundle_identifier", "BUNDLE_ID"):
        for found in re.findall(rf"{key}:\s*(\S+)", codemagic_text):
            if found != bundle_id:
                fail(f"codemagic.yaml の {key}（{found}）が "
                     f"Production.xcconfig の JP_BUNDLE_ID（{bundle_id}）と違います"
                     f"（署名が通らず、CI で10分待ったあとに落ちます）")

# ---- 9. ビルド番号の段が、仮の値に戻っていないか ---------------------------
#
# **`APP_APPLE_ID` は CI が Bundle ID から引く**（`Tools/app-apple-id.sh`）。
# 仮の数字（`0000000000`）が書き戻されると、**その数字のアプリ**を探しに行き、
# 他人のアプリの枠を見に行くか、意味の分からない失敗になる。
if codemagic_path.exists():
    if "0000000000" in codemagic_text:
        fail("codemagic.yaml に仮の APP_APPLE_ID（0000000000）が残っています"
             "（空にすると Bundle ID から自動で引きます）")

# ---- 10. 通知の文面が、両方の言語に在るか -----------------------------------
#
# **片方だけだと、iOS は鍵の文字列をそのまま通知に出す**
# （「NOTIF_LIKE」と書かれた通知が届く）。サーバーは鍵しか送らないので
# （`api-user/src/notify.ts` の `LOC_KEYS`）、ここが唯一の文面。
notif_keys = {}
for lang in ("ja", "en"):
    path = ROOT / f"Sources/JourneyPhoto/Resources/{lang}.lproj/Localizable.strings"
    if not path.exists():
        fail(f"{lang}.lproj/Localizable.strings がありません（通知の文面がそこにしか無い）")
        continue
    text = path.read_text(encoding="utf-8")
    notif_keys[lang] = set(re.findall(r'"(NOTIF_[A-Z_]+)"\s*=', text))

if len(notif_keys) == 2:
    for lang, other in (("ja", "en"), ("en", "ja")):
        for key in sorted(notif_keys[lang] - notif_keys[other]):
            fail(f"通知の文面 {key} が {other}.lproj にありません"
                 f"（その言語の端末に「{key}」という文字列が通知として届きます）")
    # サーバーが送る鍵と揃っているか（写し間違いを黙って通さない）
    server = WEB / "api-user" / "src" / "notify.ts"
    if server.exists():
        sent = set(re.findall(r'"(NOTIF_[A-Z_]+)"', server.read_text(encoding="utf-8")))
        for key in sorted(sent - notif_keys["ja"]):
            fail(f"サーバーが送る通知の鍵 {key} が Localizable.strings にありません")
    else:
        # **黙って飛ばさない。** CI は photo-gallery を取ってこないので
        # ここは必ず飛ぶ——「見張っている」と書いたまま見ていない、を作らない
        print("--  サーバー側の鍵との突き合わせは飛ばした（photo-gallery が隣に無い）")

# ---- 11. プッシュの環境が、サーバーの送り先と揃っているか -------------------
#
# **ここがずれると、宛先が消える。** 端末のトークンはビルドの
# `aps-environment` で sandbox / production のどちらかに決まる。
# サーバー（`deploy-api.yml` の `apnsHost`）が別の側へ送ると APNs は
# `400 BadDeviceToken` を返し、`apns.ts` はそれを「無効な宛先」と判じて
# **消す**——「許可したのに二度と届かない」という、いちばん追いにくい
# 壊れ方になる。
APS_ENVIRONMENTS = {}
for name in ("Debug", "Release"):
    path = ROOT / f"Sources/JourneyPhoto/JourneyPhoto.{name}.entitlements"
    if not path.exists():
        fail(f"{name} の entitlements がありません（プッシュの環境を決める唯一の場所）")
        continue
    try:
        APS_ENVIRONMENTS[name] = plistlib.loads(path.read_bytes()).get("aps-environment")
    except Exception as e:  # noqa: BLE001
        fail(f"{path.name} を plist として読めません: {e}")

expected = {"Debug": "development", "Release": "production"}
for name, want in expected.items():
    got = APS_ENVIRONMENTS.get(name)
    if name in APS_ENVIRONMENTS and got != want:
        fail(f"{name} の aps-environment が {got}（{want} のはず）"
             f"——サーバーの送り先とずれると、APNs の 400 で宛先が消えます")

# project.yml が構成ごとに entitlements を指しているか。
#
# **名前が出てくるかだけでは見張れない。** Debug と Release を入れ替えても
# 「両方の名前がある」ので素通りする——それは、この検査が防ごうとしている
# 事故（Release を development で署名し、本番の APNs へ送って宛先が消える）
# そのもの。構成ごとの割り当てを見る。
assigned = {}
try:
    import yaml  # 手元にはある。CI（macOS ランナー）に無ければ下の綴りで見る
    configs = (yaml.safe_load(project_text).get("targets", {})
               .get("JourneyPhoto", {}).get("settings", {}).get("configs", {}))
    assigned = {name: (configs.get(name) or {}).get("CODE_SIGN_ENTITLEMENTS")
                for name in expected}
except ImportError:
    for name in expected:
        found = re.search(rf"^\s*{name}:\s*\n\s*CODE_SIGN_ENTITLEMENTS:\s*(\S+)",
                          project_text, re.MULTILINE)
        assigned[name] = found.group(1) if found else None

for name in expected:
    want = f"Sources/JourneyPhoto/JourneyPhoto.{name}.entitlements"
    if assigned.get(name) != want:
        fail(f"project.yml の {name} が {want} を指していません"
             f"（いまは {assigned.get(name)}）"
             f"——入れ替わると、その環境で端末の宛先が消えます")

workflow = WEB / ".github" / "workflows" / "deploy-api.yml"
if not workflow.exists():
    # §10 と同じ理由で、**黙って飛ばさない**（CI では必ず飛ぶ）
    print("--  サーバーの送り先との突き合わせは飛ばした（photo-gallery が隣に無い）")
if workflow.exists():
    text = workflow.read_text(encoding="utf-8")
    # 本番は production の APNs、staging は sandbox
    if "apnsHost=api.push.apple.com" not in text:
        fail("deploy-api.yml が本番の APNs（api.push.apple.com）を指していません")
    if "apnsHost=api.sandbox.push.apple.com" not in text:
        fail("deploy-api.yml が staging の APNs（sandbox）を指していません")

# ---- アプリアイコン（App Store が弾く形になっていないか）------------------
#
# **透明を持った PNG は App Store が受け取らない**（`Invalid Bundle ... alpha
# channel`）。アイコンは `Tools/make-brand-assets.cjs` が透明なしで書くが、
# 手で差し替えたり別の道具で書き出したりすると簡単に混ざる。13分かけて
# アップロードの段で知るより、ここで落とす。
#
# PNG の頭（IHDR）だけ読む。Pillow はこの作業環境に無い。
icon = ROOT / "Sources/JourneyPhoto/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
if not icon.exists():
    fail(f"{icon.relative_to(ROOT)} がありません（App Store に出すアイコン）")
else:
    head = icon.read_bytes()[:33]
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        fail(f"{icon.name} が PNG として読めません")
    else:
        width = int.from_bytes(head[16:20], "big")
        height = int.from_bytes(head[20:24], "big")
        color_type = head[25]
        if (width, height) != (1024, 1024):
            fail(f"{icon.name} が {width}x{height} です（1024x1024 が要る）")
        # 4 = 灰色＋透明・6 = RGB＋透明。3（パレット）は tRNS で透明を持ちうる
        if color_type in (4, 6):
            fail(f"{icon.name} が透明を持っています（App Store が弾きます）。"
                 "`Tools/make-brand-assets.cjs` で作り直してください")
        elif color_type == 3 and b"tRNS" in icon.read_bytes()[:4096]:
            fail(f"{icon.name} がパレットの透明（tRNS）を持っています（App Store が弾きます）")

# ---- ワークフローの鍵の重複 -----------------------------------------------
#
# **同じ段に `env:` を2つ書くと、GitHub はワークフローごと読めなくなる**
# （`'env' is already defined`・実行ボタンを押した瞬間に落ちる）。ところが
# PyYAML は重複を**黙って後勝ち**で読むので、`yaml.safe_load` の検査は
# 素通りした（`7a4ed12` で実際に main を壊した）。重複を拒む読み方で読む。
try:
    import yaml  # type: ignore

    class _StrictLoader(yaml.SafeLoader):
        pass

    def _no_duplicates(loader, node, deep=False):
        seen = set()
        for key_node, _ in node.value:
            key = loader.construct_object(key_node, deep=deep)
            if key in seen:
                raise yaml.constructor.ConstructorError(
                    None, None, f"鍵 {key!r} が重複しています", key_node.start_mark)
            seen.add(key)
        return loader.construct_mapping(node, deep)

    _StrictLoader.add_constructor(
        yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates)
    for path in [*sorted((ROOT / ".github" / "workflows").glob("*.y*ml")),
                 ROOT / "codemagic.yaml", ROOT / "project.yml"]:
        if not path.exists():
            continue
        try:
            yaml.load(path.read_text(encoding="utf-8"), Loader=_StrictLoader)
        except yaml.YAMLError as e:
            fail(f"{path.relative_to(ROOT)} を読めません（GitHub / XcodeGen も弾きます）: {e}")
except ModuleNotFoundError:
    print("[skip] PyYAML が無いのでワークフローの鍵の重複は見ない")

# ---- 同梱の書体 -----------------------------------------------------------
# **名前を1字でも違えると、iOS は黙ってシステム書体で描く**（落ちもしない・
# ビルドも通る）。見出しが明朝にならないまま気づけないので、ここで3つを揃える:
#   project.yml の UIAppFonts ／ Resources/Fonts/ の実物 ／ JPFont が引く名前
FONTS_DIR = ROOT / "Sources/JourneyPhoto/Resources/Fonts"
listed = re.findall(r"""^\s+-\s+["']?([^\s"']+\.(?:ttf|otf))["']?\s*$""",
                    project_text.split("UIAppFonts:", 1)[1].split("CFBundleDevelopmentRegion", 1)[0],
                    re.M) if "UIAppFonts:" in project_text else []
if not listed:
    fail("project.yml の UIAppFonts が空です（見出しの明朝が出ません）")
for name in listed:
    if not (FONTS_DIR / name).exists():
        fail(f"UIAppFonts の {name} が Resources/Fonts/ にありません")
for stray in sorted(p.name for p in FONTS_DIR.glob("*.[ot]tf")):
    if stray not in listed:
        fail(f"Resources/Fonts/{stray} が UIAppFonts に載っていません（同梱されても使えない）")
jpfont = (ROOT / "Sources/JourneyPhoto/Core/Design/JPFont.swift").read_text(encoding="utf-8")
for ps in re.findall(r'static let \w+Name = "([^"]+)"', jpfont):
    # この repo はファイル名＝PostScript 名にしてある（`Tools/make-display-font.py`）
    if f"{ps}.ttf" not in listed and f"{ps}.otf" not in listed:
        fail(f"JPFont が引く {ps} に当たる書体が UIAppFonts にありません")
# **書体の名前を Sources に直に書かない**（`.custom("…"` ・ `UIFont(name: "…"`）。名前は
# JPFont の `*Name` か `TextOverlay.Face.fontName` に置き、上と下で突き合わせる。直に書くと
# 同梱していない名前でも黙ってシステム書体に落ち、ここで気づけない（2026-10-02: Plex を外したとき
# レビューで、`mono` を `.custom("IBMPlexMono-Regular"…` に戻しても何も落ちないと分かった）
for swift in sorted((ROOT / "Sources").rglob("*.swift")):
    for m in re.finditer(r'(?:\.custom\(|UIFont\(name:)\s*"([^"]+)"', swift.read_text(encoding="utf-8")):
        fail(f"{swift.relative_to(ROOT)}: 書体の名前 {m.group(1)} を直に書いています（JPFont の *Name に置く）")
# ストーリーの文字の書体（`TextOverlay.Face.fontName`）も同じく突き合わせる
overlay_src = (ROOT / "Sources/JourneyPhoto/Core/Text/TextOverlay.swift").read_text(encoding="utf-8")
face_block = overlay_src.split("var fontName: String? {", 1)[1].split("\n        }\n", 1)[0] \
    if "var fontName: String? {" in overlay_src else ""
face_names = re.findall(r'return "([^"]+)"', face_block)
if not face_names:
    fail("TextOverlay.Face.fontName が読めません（ストーリーの書体を突き合わせられない）")
# **どの iPhone にも入っている書体**（同梱しない・2026-09-29 に足した3つ）。ここに無い名前は
# 同梱が要る。**名前は Linux では確かめられない**——違っていても端末の太字に落ちるだけで
# 割れはしないが、実機で確かめること（`TextOverlay.Face` の注記）
IOS_SYSTEM_FONTS = {"HiraMaruProN-W4", "AmericanTypewriter-Bold", "SnellRoundhand-Bold"}
for ps in face_names:
    if ps in IOS_SYSTEM_FONTS:
        continue
    if f"{ps}.ttf" not in listed and f"{ps}.otf" not in listed:
        fail(f"ストーリーの文字が引く {ps} に当たる書体が UIAppFonts にありません")
for lic in ("OFL-ShipporiMincho.txt", "OFL-KleeOne.txt",
            "OFL-YuseiMagic.txt", "OFL-HachiMaruPop.txt"):
    if not (FONTS_DIR / lic).exists():
        fail(f"書体のライセンス {lic} がありません（OFL は同梱が条件）")

# **`$名前` の直後に全角文字を置かない**（`${名前}` と書く）。
# macOS の /bin/bash（3.2）は `$MARKETING（` の「（」のバイトまで名前として
# 読み、`set -u` の下で「unbound variable」で止まる。Linux の bash では
# 起きないので手元では気づけない（TestFlight run #92 がここで落ちた）
for shell_file in sorted([*(ROOT / ".github/workflows").glob("*.yml"), *(ROOT / "Tools").glob("*.sh"),
                          ROOT / "codemagic.yaml"]):
    if not shell_file.exists():
        continue
    for number, line in enumerate(shell_file.read_text(encoding="utf-8").splitlines(), 1):
        if re.search(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]", line):
            fail(f"{shell_file.relative_to(ROOT)}:{number} の変数の直後に全角文字（${{名前}} と書く）")

# **リリースのたびに版を上げる**（2026-09-26 owner のルール・CLAUDE.md）。
# 上げているのは TestFlight のワークフローなので、その段が消えていないかを見る。
# 消えると、同じ版のまま TestFlight に並び、どのビルドか見分けられなくなる
testflight_yml = ROOT / ".github/workflows/ios-testflight.yml"
if testflight_yml.exists():
    flow = testflight_yml.read_text(encoding="utf-8")
    if "Tools/next-marketing-version.sh" not in flow:
        fail("ios-testflight.yml が表に出る版を上げていません（Tools/next-marketing-version.sh を呼ぶ）")
    if "testflight/" not in flow:
        fail("ios-testflight.yml が出した版の印（testflight/<版> のタグ）を付けていません")

    # **ビルド番号は表に出る版ごとに 1 から数える**（2026-10-18 owner の判断:
    # TestFlight の表示を「1.1.15 (1)」の形に）。版で絞らずに引くと全版通しの番号に戻り、
    # 版を決める前に引くと前の版で絞ってしまう
    number_step = re.search(r"- name: ビルド番号を決める\n(.*?)(?=\n      - name: )", flow, re.S)
    number_text = number_step.group(1) if number_step else ""
    marketing_at = number_text.find("Tools/next-marketing-version.sh")
    latest_at = number_text.find("get-latest-testflight-build-number")
    if latest_at == -1 or not re.search(
            r'get-latest-testflight-build-number "\$APP_APPLE_ID" \\\n\s+--pre-release-version "\$MARKETING"',
            number_text):
        fail("ios-testflight.yml の「ビルド番号を決める」が、その回の版（--pre-release-version \"$MARKETING\"）で絞って引いていません")
    if marketing_at == -1 or latest_at == -1 or marketing_at > latest_at:
        fail("ios-testflight.yml の「ビルド番号を決める」が、表に出る版を決める前にビルド番号を引いています")

# 手元用の `bump-build.sh` も同じ考え（版を変えたら 1・同じ版なら +1）。
# 写しの一時ディレクトリで流して確かめる（本物の project.yml は触らない）
def _bump_build_cases():
    import shutil
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        tools = Path(tmp, "Tools")
        tools.mkdir()
        for name in ("bump-build.sh", "set-build-number.sh"):
            shutil.copy(ROOT / "Tools" / name, tools / name)
        # 最後に呼ぶ設定の検査は、ここでは空にする（この検査の中から自分を呼ばない）
        (tools / "check-config.py").write_text("", encoding="utf-8")
        (Path(tmp) / "project.yml").write_text(
            '    settings:\n        MARKETING_VERSION: "1.1.14"\n        CURRENT_PROJECT_VERSION: "124"\n',
            encoding="utf-8")

        def bump(*args):
            run = subprocess.run(["bash", str(tools / "bump-build.sh"), *args], capture_output=True, text=True)
            text = (Path(tmp) / "project.yml").read_text(encoding="utf-8")
            version = re.search(r'MARKETING_VERSION: "([0-9.]+)"', text)
            build = re.search(r'CURRENT_PROJECT_VERSION: "([0-9]+)"', text)
            return run.returncode, version and version.group(1), build and build.group(1)

        return [
            ("版を変えると 1", bump("1.1.15"), (0, "1.1.15", "1")),
            ("同じ版をもう一度渡すと +1", bump("1.1.15"), (0, "1.1.15", "2")),
            ("版を渡さないと +1", bump(), (0, "1.1.15", "3")),
            ("次の版でまた 1", bump("1.1.16"), (0, "1.1.16", "1")),
        ]

for label, got, want in _bump_build_cases():
    if got != want:
        fail(f"Tools/bump-build.sh: {label}になりません（版・ビルド番号）: 得たもの {got}・期待 {want}")

# ---- 枝の確認の絞り（`screens`）と「Mac でテスト済み」の数え方 -------------------
# 🔴 **絞った回を「テスト済み」と数えると、全部の UI テストが一度も回らずに main に入る**
# （2026-10-17）。数えるのは ios-testflight.yml の印の段だけで、その段は絞らない回にしか
# 走らない。印の名前・条件・数える側のどれかが崩れたら、ここで止める
MARK = "全部のテストが通った（PR の検証が数える印）"
pr_yml = ROOT / ".github/workflows/ios-pr.yml"
if testflight_yml.exists() and pr_yml.exists():
    flow = testflight_yml.read_text(encoding="utf-8")
    pr_flow = pr_yml.read_text(encoding="utf-8")
    # 印の段の `if:` は**完全一致**で見る（`|| …` を足すだけで絞った回にも付く）
    # 単体・UI の段の結果も見る（`id` が消えると outcome は空になり、印が付かない＝安全側。下で id も見る）
    MARK_IF = ("(inputs.tests || inputs.storeShots || !inputs.submit) && steps.scope.outputs.full == 'true'"
               " && steps.unit.outcome == 'success' && steps.ui.outcome == 'success'")
    mark = re.search(r"- name: " + re.escape(MARK) + r"\n\s+if: \$\{\{(.+?)\}\}\s*\n", flow)
    if not mark:
        fail(f"ios-testflight.yml に「{MARK}」の段（if つき）がありません")
    elif mark.group(1).strip() != MARK_IF:
        fail(f"ios-testflight.yml の「{MARK}」の if が変わっています（絞った回にも付きうる）: {mark.group(1).strip()}")
    # **別々の Mac に分けて流す回の印**（2026-10-31・#429）。「まとめ」の job の同じ名前の段で、
    # 単体・先に流す分・分けた組の**全部**が success のときだけ付く。`always()` や `|| …` を足すと、落ちた回にも付く
    FINISH_MARK_IF = ("needs.test-build.result == 'success' && needs.pre.result == 'success'"
                      " && needs.ui.result == 'success'")
    marks = re.findall(r"- name: " + re.escape(MARK) + r"\n\s+if: \$\{\{(.+?)\}\}\s*\n", flow)
    if len(marks) != 2 or marks[1].strip() != FINISH_MARK_IF:
        fail(f"ios-testflight.yml の「まとめ」の「{MARK}」の if が変わっています（分けた組が落ちても付きうる）: {marks[1:]}")
    # 分けた組は、単体と先に流す分の両方を待つ（`needs: [test-build, pre]`・job の if を足さない＝どれかが落ちたら skipped）
    ui_job = re.search(r"^  ui:\n(.*?)(?=^  \w[\w-]*:\n|\Z)", flow, re.M | re.S)
    if not ui_job or "needs: [test-build, pre]" not in ui_job.group(1) or re.search(r"^    if:", ui_job.group(1), re.M):
        fail("ios-testflight.yml の `ui`（分けた組）が、単体テストと先に流す分の両方を待っていません（needs: [test-build, pre]・if なし）")
    else:
        # 組の数は `--plan <数>` と matrix で揃える（ずれると、流れない組・空の組ができる）
        parts = re.search(r"part: \[([0-9, ]+)\]", ui_job.group(1))
        plan_n = re.search(r"pick-ui-tests\.py --plan (\d+) ", flow)
        if not parts or not plan_n or [int(x) for x in parts.group(1).split(",")] != list(range(1, int(plan_n.group(1)) + 1)):
            fail("ios-testflight.yml の分けた組の matrix と `pick-ui-tests.py --plan <数>` の数が揃っていません")
    # 数える側の jq の `select(...)` は**印の名前の完全一致だけ**
    selects = re.findall(r"select\((\.name[^|]*?)\)\s*\|", pr_flow)
    if selects != [f'.name == "{MARK}"']:
        fail(f"ios-pr.yml の「同じコミットが Mac でテスト済みか」の select が印の名前の完全一致だけではありません: {selects}")

    # **落ちても先へ進む段を作らない。** 組む・単体・UI・印のどれかに `continue-on-error` が付くと、
    # 落ちた回でも印まで進み「テスト済み」と数えられる
    def step_block(text, name):
        found = re.search(r"^      - name: " + re.escape(name) + r"\n(.*?)(?=^      - |\Z)", text, re.M | re.S)
        return found.group(1) if found else None
    for text, file, names in [
        (flow, "ios-testflight.yml", ["組む（本物の SwiftUI で型検査される最初の機会）", "単体テスト", "UI テスト（画面の絵）", MARK]),
        (pr_flow, "ios-pr.yml", ["組む", "単体テスト", "UI テスト（起動・全タブ・画面の絵）"]),
    ]:
        for name in names:
            block = step_block(text, name)
            if block is None:
                fail(f"{file} に「{name}」の段がありません")
            elif "continue-on-error" in block:
                fail(f"{file} の「{name}」に continue-on-error があります（落ちても印まで進む）")
    # 分けて流す回のテストの段（組む・組ごとに流す）にも continue-on-error を付けない
    part_action = ROOT / ".github/actions/mac-test-part/action.yml"
    if "continue-on-error" in (part_action.read_text(encoding="utf-8") if part_action.exists() else "continue-on-error"):
        fail(".github/actions/mac-test-part/action.yml が無いか、continue-on-error があります（落ちても印まで進む）")
    for job in ("test-build", "pre", "ui"):
        body = re.search(r"^  " + job + r":\n(.*?)(?=^  \w[\w-]*:\n|\Z)", flow, re.M | re.S)
        if not body or "continue-on-error" in body.group(1):
            fail(f"ios-testflight.yml の job「{job}」が無いか、continue-on-error があります（落ちても印まで進む）")
    # 印が結果を見る段の `id`
    for name, step_id in [("単体テスト", "unit"), ("UI テスト（画面の絵）", "ui")]:
        block = step_block(flow, name) or ""
        if not re.search(r"^        id: " + step_id + r"\n", block, re.M):
            fail(f"ios-testflight.yml の「{name}」に id: {step_id} がありません（印が結果を見られない）")
    # テストを流す道具が、落ちたときに 1 で終わること（0 で終わると段が緑になる）
    runner = (ROOT / "Tools/xcode-test.sh").read_text(encoding="utf-8")
    # **pipefail が無いと** `xcodebuild … | tee | tail` の終了は tail のもの＝いつも 0 になり、
    # 下の `|| { exit 1 }` に来ない
    if not re.search(r"^set -[a-z]*o pipefail\b", runner, re.M):
        fail("Tools/xcode-test.sh に set -euo pipefail（pipefail）がありません（xcodebuild の失敗が tail に隠れる）")
    if not re.search(r'\| tail -n \d+ \|\| \{[^}]*\n\s*exit 1\n\s*\}', runner):
        fail("Tools/xcode-test.sh が xcodebuild の失敗で exit 1 しません")
    # **1本ごとの時間の上限**（2026-10-18・run 233 で起動の詰まりが 72分待ち続けた）。
    # 単体・UI の両方に渡し、全部撮る1本の指定が UI の上限（maximum）を越えないこと
    limits = dict(re.findall(r"^(UNIT_TIME_ALLOWANCE|UNIT_TIME_MAXIMUM|UI_TIME_ALLOWANCE|UI_TIME_MAXIMUM)=(\d+)$",
                             runner, re.M))
    if len(limits) != 4:
        fail(f"Tools/xcode-test.sh に1本ごとの時間の上限（UNIT_/UI_TIME_ALLOWANCE・MAXIMUM）がそろっていません: {limits}")
    else:
        limits = {k: int(v) for k, v in limits.items()}
        if not (60 <= limits["UNIT_TIME_ALLOWANCE"] <= limits["UNIT_TIME_MAXIMUM"]):
            fail(f"単体テストの時間の上限が変です（60 以上・既定 ≤ 頭打ち）: {limits}")
        if not (60 <= limits["UI_TIME_ALLOWANCE"] <= limits["UI_TIME_MAXIMUM"]):
            fail(f"UI テストの時間の上限が変です（60 以上・既定 ≤ 頭打ち）: {limits}")
        shots = (ROOT / "UITests/JourneyPhotoUITests/ScreenshotTests.swift").read_text(encoding="utf-8")
        every = re.search(r"func testCapturesEveryScreen\(\) \{(?:\s*//[^\n]*)*\s*executionTimeAllowance = (\d+)", shots)
        if not every:
            fail("ScreenshotTests.testCapturesEveryScreen が頭で executionTimeAllowance を上げていません"
                 "（実測 362〜462秒で、UI の既定の上限に当たる）")
        elif not (limits["UI_TIME_ALLOWANCE"] < int(every.group(1)) <= limits["UI_TIME_MAXIMUM"]):
            fail(f"testCapturesEveryScreen の executionTimeAllowance（{every.group(1)}）が、"
                 f"UI の既定より大きく頭打ち以下になっていません: {limits}")
        # 実際に xcodebuild へ渡るか（偽の xcodebuild で引数を書き出す）
        import subprocess as _sp
        import tempfile as _tf
        with _tf.TemporaryDirectory() as tmp:
            fake = Path(tmp, "xcodebuild")
            fake.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$FAKE_XCODEBUILD_ARGS"\n', encoding="utf-8")
            fake.chmod(0o755)
            for mode, prefix in (("unit", "UNIT"), ("ui", "UI")):
                args_file = Path(tmp, f"{mode}.args")
                run = _sp.run(["bash", str(ROOT / "Tools/xcode-test.sh"), mode, str(Path(tmp, f"{mode}.xcresult"))],
                              capture_output=True, text=True,
                              env={**os.environ, "PATH": f"{tmp}:{os.environ.get('PATH', '')}",
                                   "DEVICE": "iPhone Test", "XCODE_LOG": str(Path(tmp, "x.log")),
                                   "FAKE_XCODEBUILD_ARGS": str(args_file)})
                got = args_file.read_text(encoding="utf-8").split("\n") if args_file.exists() else []
                want = ["-test-timeouts-enabled", "YES",
                        "-default-test-execution-time-allowance", str(limits[f"{prefix}_TIME_ALLOWANCE"]),
                        "-maximum-test-execution-time-allowance", str(limits[f"{prefix}_TIME_MAXIMUM"])]
                if run.returncode != 0 or not any(got[i:i + len(want)] == want for i in range(len(got))):
                    fail(f"Tools/xcode-test.sh {mode} が xcodebuild に時間の上限を渡していません: "
                         f"{run.returncode} {got} {run.stderr[-300:]}")
    # 上げる回・storeShots の回は screens を捨てて全部にする
    scope = step_block(flow, "どこまで流すかを決める") or ""
    if not re.search(r'if \[ "\$\{SUBMIT:-\}" = "true" \] \|\| \[ "\$\{STORE_SHOTS:-\}" = "true" \]; then\n\s*SCREENS=""\n\s*fi', scope):
        fail("ios-testflight.yml の「どこまで流すかを決める」が、上げる回・storeShots の回で screens を捨てていません")
    if re.search(r'startswith\("テスト"\)', pr_flow):
        fail("ios-pr.yml が「テスト」で始まる段を数えています（絞った回の単体だけで通った扱いになる）")
    for name in re.findall(r"^      - name: (テスト.*)$", flow, re.M):
        fail(f"ios-testflight.yml の段「{name}」が「テスト」で始まります（古い数え方に拾われる）")
    # main の回の「控えを温める」は、署名用に書き換えたプロジェクトを元に戻してから組む
    warm = step_block(flow, "控えを温める（main の回だけ・シミュレータ向けに組む）") or ""
    warm_order = [warm.find("git checkout -- project.yml"), warm.find("xcodegen generate"),
                  warm.find("Tools/xcode-test.sh build")]
    if -1 in warm_order or warm_order != sorted(warm_order):
        fail("ios-testflight.yml の「控えを温める」が、project.yml を戻して xcodegen し直してから組んでいません")

    import subprocess
    import tempfile
    # 画面の絵の書き出し: 元の拡張子のまま写し、録画・拡張子なしは置かない
    # （`export-screenshots.sh` の中の Python をそのまま取り出して、偽の添付で流す）
    exporter = (ROOT / "Tools/export-screenshots.sh").read_text(encoding="utf-8")
    copy_py = re.search(r"<<'PY'\n(.*?)\nPY\n", exporter, re.S)
    if not copy_py:
        fail("Tools/export-screenshots.sh の添付を写す Python が読めません")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp, "src"), Path(tmp, "out")
            src.mkdir(); out.mkdir()
            manifest = []
            for exported, name in [("a.png", "10-ホーム_0_X.png"), ("b.txt", "note_0_Y.txt"),
                                   ("c.jpg", "pic"), ("d.mp4", "Screen Recording.mp4"), ("e", "UI Snapshot")]:
                (src / exported).write_bytes(b"x")
                manifest.append({"exportedFileName": exported, "suggestedHumanReadableName": name})
            (src / "manifest.json").write_text(json.dumps([{"attachments": manifest}]), encoding="utf-8")
            subprocess.run([sys.executable, "-I", "-c", copy_py.group(1), str(src), str(out)],
                           capture_output=True, text=True)
            got = sorted(f.name for f in out.iterdir())
            if got != ["10-ホーム_0_X.png", "note_0_Y.txt", "pic.jpg"]:
                fail(f"export-screenshots.sh の写し方が変わっています（元の拡張子のまま・録画は置かない）: {got}")

    picker = ROOT / "Tools/pick-ui-tests.py"
    # 全部（空）のときは UI テストのファイルを読まない（上げる回がファイルの書き方に左右されない）
    nowhere = subprocess.run([sys.executable, str(picker), ""], capture_output=True, text=True,
                             env={**os.environ, "JP_UI_TESTS_DIR": "/nonexistent-ui-tests"})
    if nowhere.returncode != 0 or nowhere.stdout.split() != ["-only-testing:JourneyPhotoUITests"]:
        fail("pick-ui-tests.py が空（全部）でも UI テストのファイルを読んでいます")
    def picked(screens):
        run = subprocess.run([sys.executable, str(picker), screens], capture_output=True, text=True)
        return run.returncode, run.stdout.split()
    code, out = picked("")
    if code != 0 or out != ["-only-testing:JourneyPhotoUITests"]:
        fail(f"pick-ui-tests.py の空（全部）が全部になりません: {code} {out}")
    code, out = picked("なし")
    if code != 0 or out != ["-only-testing:JourneyPhotoUITests/SmokeTests"]:
        fail(f"pick-ui-tests.py の「なし」が起動の見張りだけになりません: {code} {out}")
    code, out = picked("01-同意画面")
    if code != 0 or "-only-testing:JourneyPhotoUITests/ScreenshotTests/testCapturesEveryScreen" not in out \
            or "-only-testing:JourneyPhotoUITests/SmokeTests" not in out:
        fail(f"pick-ui-tests.py が絵の名前（01-同意画面）から撮るテストを選べません: {code} {out}")
    code, _ = picked("どの絵にも無い語qqq")
    if code != 2:
        fail("pick-ui-tests.py が当たらない語で止まりません（打ち間違いで UI テスト0件のまま緑になる）")

    # **分けて流す回の割り振り**（2026-10-31・#429）: 先に流す分と組 1〜N-1 は重ならず、最後の組は
    # 「全部から、それらを抜いた残り」。どのテストも、ちょうど1回だけ流れる（足さない・減らさない）
    import importlib.util as _ilu
    _spec = _ilu.spec_from_file_location("pick_ui_tests", picker)
    pick_mod = _ilu.module_from_spec(_spec)
    _spec.loader.exec_module(pick_mod)
    index, loose = pick_mod.read_index()
    runnable = {t for t in index if t not in pick_mod.ONLY_WHEN_NAMED}
    prefix = f"-only-testing:{pick_mod.TARGET}/"
    for words, diff in [("", ""), ("撮影スポット", ""),
                        ("", "+++ b/UITests/JourneyPhotoUITests/SmokeTests.swift\n@@ -1,0 +1,1 @@\n+x\n")]:
        got = pick_mod.plan(words, diff, 3, index=index, loose=loose)
        first = {a[len(prefix):] for a in got["first"]}
        first = {t for t in runnable if t in first or t.split("/")[0] in first}
        groups = [{a[len(prefix):] for a in g} for g in got["parts"][:-1]]
        last = got["parts"][-1]
        skipped = {a.split(f"{pick_mod.TARGET}/", 1)[1] for a in last[1:]}
        listed = [first, *groups]
        overlap = sum(len(g) for g in listed) != len(set().union(*listed))
        if (last[0] != f"-only-testing:{pick_mod.TARGET}" or not all(a.startswith("-skip-testing:") for a in last[1:])
                or overlap or skipped != set().union(*listed) or not set().union(*listed) <= runnable):
            fail(f"pick-ui-tests.py --plan の割り振りで、同じテストが2回流れるか、流れないテストがあります（{words!r}）")
    # **名指しした回だけ流すテストも、`first` で名指しすれば先に流す**（2026-10-31・黙って0本にしない）。
    # クラスの名前で名指しする形（`PerformanceTests`）も見る。全部の回の分けた組には、名前でも入れない
    saved = list(pick_mod.ONLY_WHEN_NAMED)
    try:
        pick_mod.ONLY_WHEN_NAMED[:] = saved + ["StoryPickerTests"]
        named = {t for t in index if t.startswith("StoryPickerTests/")}
        got = pick_mod.plan("StoryPickerTests", "", 3, index=index, loose=loose)
        first = {a[len(prefix):] for a in got["first"]}
        explicit = {a[len(prefix):] for g in got["parts"][:-1] for a in g}
        if not named or not named <= first or named & explicit:
            fail(f"pick-ui-tests.py --plan が、first で名指しした「名指しした回だけ流すテスト」を先に流しません: {sorted(first)}")
        got = pick_mod.plan("", "", 3, index=index, loose=loose)
        if named & ({a[len(prefix):] for a in got["first"]} | {a[len(prefix):] for g in got["parts"][:-1] for a in g}):
            fail("pick-ui-tests.py --plan が、名指ししていないのに「名指しした回だけ流すテスト」を流します")
    finally:
        pick_mod.ONLY_WHEN_NAMED[:] = saved
    # 時間の表に無いテストは中央の値で見積もる（新しいテストで割り振りが崩れない）
    est = pick_mod.estimate(["A/a", "A/b", "A/new"], {"A/a": 10.0, "A/b": 30.0})
    if est["A/new"] != 30.0:
        fail(f"pick-ui-tests.py が、時間の表に無いテストを中央の値で見積もっていません: {est}")
    # 変えた行から先に流すテストを選ぶ（テストの関数の中の行・アプリのコードの識別子）
    smoke_line = next(iter(index[next(t for t in index if t.startswith("SmokeTests/test"))]["lines"]))[0] + 1
    sample = next(t for t in index if t.startswith("SmokeTests/test"))
    chosen = pick_mod.tests_for_diff(f"+++ b/UITests/JourneyPhotoUITests/SmokeTests.swift\n@@ -{smoke_line},1 +{smoke_line},1 @@\n+x\n",
                                     index, loose)
    if not chosen:
        fail(f"pick-ui-tests.py が、変えたテストの行から先に流すテストを選べません（{sample} の {smoke_line} 行目）")

# ---- 結果 -----------------------------------------------------------------
if errors:
    for message in errors:
        print(f"NG  {message}")
    sys.exit(1)
print("設定ファイルの検査: 問題なし")
