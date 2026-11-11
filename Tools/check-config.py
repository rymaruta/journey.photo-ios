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

# ---- 毎回の（ios-quick.yml）・ガチガチの（ios-full.yml）と「Mac でテスト済み」の数え方 ------------
# 2026-11-11 owner「毎回のと ガチガチので」作り替え。毎回の = PR と枝の確かめ（目標 10 分・上限 30 分）、
# ガチガチの = 全部の単体と全部の UI を4台に分けて（手で押したときだけ）。TestFlight に上げる回はテストを流さない。
# 🔴 **印（Mac でテスト済み）を付けるのは、毎回のの門とガチガチののまとめだけ**。名前・条件・数える側のどれかが崩れたら止める
MARK = "Mac のテストが通った（PR の検証が数える印）"
pr_yml = ROOT / ".github/workflows/ios-pr.yml"
quick_yml = ROOT / ".github/workflows/ios-quick.yml"
full_yml = ROOT / ".github/workflows/ios-full.yml"
sharded_yml = ROOT / ".github/workflows/mac-sharded-tests.yml"


def _jobs(text):
    return {m.group(1): m.group(2) for m in re.finditer(r"^  ([\w-]+):\n(.*?)(?=^  [\w-]+:\n|\Z)", text, re.M | re.S)}


def _code(text):
    """注記の行を除いた中身（注記に書いた名前を数えない）"""
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))


for _required in (testflight_yml, pr_yml, quick_yml, full_yml, sharded_yml):
    if not _required.exists():
        fail(f"{_required.relative_to(ROOT)} がありません")
if all(f.exists() for f in (testflight_yml, pr_yml, quick_yml, full_yml, sharded_yml)):
    flow = testflight_yml.read_text(encoding="utf-8")
    pr_flow = pr_yml.read_text(encoding="utf-8")
    quick = quick_yml.read_text(encoding="utf-8")
    full = full_yml.read_text(encoding="utf-8")
    shard_flow = sharded_yml.read_text(encoding="utf-8")
    workflows = {f.name: f.read_text(encoding="utf-8") for f in (ROOT / ".github/workflows").glob("*.yml")}

    # ---- TestFlight に上げる回（ios-testflight.yml）は Archive と上げるだけ -----------------
    tf_code = _code(flow)
    for word in ("Tools/xcode-test.sh unit", "Tools/xcode-test.sh ui", MARK, "mac-sharded-tests.yml",
                 "inputs.tests", "inputs.screens", "inputs.storeShots", "pick-ui-tests.py"):
        if word in tf_code:
            fail(f"ios-testflight.yml に「{word}」があります（上げる回はテストを流さない・2026-11-11）")
    tf_inputs = re.search(r"^  workflow_dispatch:\n    inputs:\n(.*?)(?=^\S)", flow, re.M | re.S)
    if not tf_inputs or sorted(re.findall(r"^      (\w+):\n", tf_inputs.group(1), re.M)) != ["betaReview", "submit"]:
        fail("ios-testflight.yml の入力が submit・betaReview だけになっていません（テストの分岐を抜いた）")

    # ---- 印を付ける所は2つだけ ------------------------------------------------------------
    for name, text in workflows.items():
        count = len(re.findall(r"- name: " + re.escape(MARK) + r"\n", text))
        want = 1 if name in ("ios-quick.yml", "mac-sharded-tests.yml") else 0
        if count != want:
            fail(f"{name} の「{MARK}」の段が {count} 個です（毎回のの門とガチガチののまとめに1つずつ）")
    FINISH_MARK_IF = ("needs.test-build.result == 'success' && needs.pre.result == 'success'"
                      " && needs.ui.result == 'success'")
    shard_marks = re.findall(r"- name: " + re.escape(MARK) + r"\n\s+if: \$\{\{(.+?)\}\}\s*\n", shard_flow)
    if [m.strip() for m in shard_marks] != [FINISH_MARK_IF]:
        fail(f"mac-sharded-tests.yml の「{MARK}」の if が変わっています（分けた組が落ちても付きうる）: {shard_marks}")
    QUICK_MARK_IF = ("needs.plan.result == 'success' && needs.plan.outputs.run == 'true'"
                     " && needs.static.result == 'success' && needs.mac.result == 'success'")
    quick_marks = re.findall(r"- name: " + re.escape(MARK) + r"\n\s+if: \$\{\{(.+?)\}\}\s*\n", quick)
    if [m.strip() for m in quick_marks] != [QUICK_MARK_IF]:
        fail(f"ios-quick.yml の「{MARK}」の if が変わっています（Mac が落ちても・起こさなくても付きうる）: {quick_marks}")
    # 数える側（毎回のの plan）の jq の select は印の名前の完全一致だけ・数える回は毎回のとガチガチのの success だけ
    selects = re.findall(r"select\((\.name[^|]*?)\)\s*\|", quick)
    if selects != [f'.name == "{MARK}"']:
        fail(f"ios-quick.yml の「同じコミットが Mac でテスト済みか」の select が印の名前の完全一致だけではありません: {selects}")
    if "for wf in ios-quick.yml ios-full.yml release-center.yml; do" not in quick or 'select(.conclusion == "success")' not in quick:
        fail("ios-quick.yml が、毎回のとガチガチのの通った回（success）だけを「テスト済み」と数えていません")
    for name, text in workflows.items():
        if re.search(r'startswith\("テスト"\)', text):
            fail(f"{name} が「テスト」で始まる段を数えています（古い数え方）")

    # ---- 毎回の（ios-quick.yml）--------------------------------------------------------
    q_jobs = _jobs(quick)
    if not re.search(r"^on:\n  pull_request:\n", quick, re.M) or not re.search(r"^  workflow_dispatch:\n", quick, re.M) \
            or re.search(r"^  (schedule|push):", quick, re.M):
        fail("ios-quick.yml が PR と手で流したときに走る形（pull_request・workflow_dispatch）になっていません")
    gate = q_jobs.get("xcode", "")
    if "    name: Xcode のビルドとテスト（シミュレータ）\n" not in gate or "needs: [plan, static, mac]" not in gate \
            or 'if [ "$RUN" = "true" ] && [ "$STATIC" != "success" ]; then' not in gate \
            or "if: ${{ always() }}" not in gate or 'if [ "$RUN" = "true" ] && [ "$MAC" != "success" ]; then' not in gate:
        fail("ios-quick.yml の門（Xcode のビルドとテスト（シミュレータ））が、Mac の結果を読んで落ちる形になっていません"
             "（必須のチェックの名前を変えない）")
    static_job = q_jobs.get("static", "")
    if "uses: ./.github/actions/static-checks" not in static_job or "if: ${{ failure() }}" not in static_job \
            or "actions/runs/${GITHUB_RUN_ID}/cancel" not in static_job or "needs: plan\n" not in static_job:
        fail("ios-quick.yml の静的な検査が、Mac と並べて走り・落ちたら回を止める形になっていません")
    if "uses: ./.github/actions/static-checks" not in pr_flow:
        fail("ios-pr.yml の静的な検査が、共通の部品（.github/actions/static-checks）を使っていません")
    if not re.search(r"^  group: ios-quick-\$\{\{ github.workflow \}\}-", quick, re.M):
        fail("ios-quick.yml の concurrency の組に github.workflow がありません（手で流した回と Release Center の回が取り消し合う）")
    mac = q_jobs.get("mac", "")
    limit = re.search(r"^    timeout-minutes: (\d+)$", mac, re.M)
    if not limit or int(limit.group(1)) > 25 or "fromJSON(needs.plan.outputs.matrix)" not in mac:
        fail("ios-quick.yml の Mac の job が、上限（timeout-minutes ≤ 25・回全体で 30 分）と plan の割り振りで動いていません")
    for name, text in (("ios-quick.yml", quick), ("ios-full.yml", full), ("mac-sharded-tests.yml", shard_flow)):
        if "continue-on-error" in _code(text):
            fail(f"{name} に continue-on-error があります（落ちても印まで進む）")
    plan_job = q_jobs.get("plan", "")
    if 'python3 Tools/pick-ui-tests.py --quick-plan build/quick /tmp/quick.diff "${SCREENS:-}" "$cap"' not in plan_job \
            or 'base="$BASE_SHA"; cap=cap' not in plan_job or 'bash Tools/app-changed.sh "$BASE_SHA"' not in plan_job:
        fail("ios-quick.yml の plan が、--quick-plan（PR は上限で外す）と app-changed.sh で中身を決めていません")
    unit_step = re.search(r"- name: 単体テスト（全部・1 台目）\n(.*?)(?=\n      - |\Z)", mac, re.S)
    if not unit_step or "if: ${{ matrix.part == 1 }}" not in unit_step.group(1) \
            or "bash Tools/xcode-test.sh unit build/Unit.xcresult" not in unit_step.group(1) or "UNIT_ONLY_TESTING" in unit_step.group(1) \
            or "bash Tools/xcode-test.sh ui build/Test.xcresult /tmp/quick-list.txt" not in mac:
        fail("ios-quick.yml の Mac 1 台目が、単体テストを全部（JourneyPhotoTests・絞らない）流していません（CLAUDE.md「単体テスト（全部）」）")
    warm_req = re.search(r"- name: 控えが無ければ main の控えを書く回を頼む\n(.*?)(?=\n      - |\Z)", mac, re.S)
    if not warm_req or "matrix.part == 1" not in warm_req.group(1) or 'status == "in_progress"' not in warm_req.group(1) \
            or '-f "xcode=${XCODE_VERSION}"' not in warm_req.group(1):
        fail("ios-quick.yml: 控えを書く回を頼むのは 1 台目だけ・待ち／走っている回があれば頼まない・台の Xcode の版を渡す")
    if "::warning title=流さなかった関係する UI テスト::" not in gate \
            or "dropped=$(paste -sd ',' build/quick/dropped.txt)" not in q_jobs.get("plan", ""):
        fail("ios-quick.yml: 上限で外した関係する UI テストを、門の結果に警告で出していません")
    if "name: build-logs-mac${{ matrix.part }}" not in mac or "retention-days: 3" not in mac:
        fail("ios-quick.yml: 全文ログ（build-logs-macN・xcodebuild-full.log）を短い保存日数で残していません")
    if "bash Tools/app-changed.sh" not in pr_flow or re.search(r"runs-on: .*macos", pr_flow):
        fail("ios-pr.yml は Linux だけ（Mac は ios-quick.yml）・アプリ変更の有無は Tools/app-changed.sh で決める")

    # ---- ガチガチの（ios-full.yml）と、分けて流す組（mac-sharded-tests.yml）------------------
    if re.search(r"^  (pull_request|push|schedule):", full, re.M) or not re.search(r"^  workflow_dispatch:\n", full, re.M):
        fail("ios-full.yml は手で押したときだけ（workflow_dispatch・workflow_call）走ります（2026-11-11 owner）")
    if not re.search(r"^concurrency:\n  group: ios-full-\$\{\{ github.repository \}\}\n  cancel-in-progress: false$", full, re.M):
        fail("ios-full.yml が同時に1本（取り消さない）になっていません（Mac は同時5台まで）")
    if not re.search(r"^on:\n  workflow_call:\n", shard_flow, re.M) or re.search(r"^  (workflow_dispatch|push|pull_request|schedule):", shard_flow, re.M):
        fail("mac-sharded-tests.yml が呼ばれるだけ（on: workflow_call のみ）になっていません")
    USES_SHARDED = "uses: ./.github/workflows/mac-sharded-tests.yml"
    callers = sorted(name for name, text in workflows.items() if USES_SHARDED in _code(text))
    if callers != ["ios-full.yml"]:
        fail(f"mac-sharded-tests.yml を呼ぶのはガチガチの（ios-full.yml）だけのはず: {callers}")
    for name, text in workflows.items():
        # ios-perf.yml（重さの記録）は組む・流すの部品を使い回す別の流れ（2026-11-04・札 #429）
        if name in ("mac-sharded-tests.yml", "ios-perf.yml"):
            continue
        for copied in ("pick-ui-tests.py --plan ", "test-products.py pack", "uses: ./.github/actions/mac-test-part"):
            if copied in _code(text):
                fail(f"{name} に「{copied}」があります（分けて流す組の写し。mac-sharded-tests.yml だけに書く）")
    s_jobs = _jobs(shard_flow)
    result_job = s_jobs.get("result", "")
    if "needs: [test-build, pre, ui]" not in result_job \
            or "if: ${{ !(" + FINISH_MARK_IF + ") }}" not in result_job or "exit 1" not in result_job:
        fail("mac-sharded-tests.yml の `result`（まとめ）が、どれかが落ちたときに落ちる段を持っていません")
    ui_job = s_jobs.get("ui", "")
    if "needs: [test-build, pre]" not in ui_job or re.search(r"^    if:", ui_job, re.M):
        fail("mac-sharded-tests.yml の `ui`（分けた組）が、単体テストと先に流す分の両方を待っていません（needs: [test-build, pre]・if なし）")
    parts = re.search(r"part: \[([0-9, ]+)\]", ui_job)
    plan_n = re.search(r"pick-ui-tests\.py --plan (\d+) ", shard_flow)
    if not parts or not plan_n or [int(x) for x in parts.group(1).split(",")] != list(range(1, int(plan_n.group(1)) + 1)):
        fail("mac-sharded-tests.yml の分けた組の matrix と `pick-ui-tests.py --plan <数>` の数が揃っていません")
    # 同時に動く Mac（Mac は同時5台まで）。分けた組は4台まで（単体と先に流す分の2台とは重ならない）
    shard_macs = max([len(re.findall(r"[^,\[\] ]+", m)) for m in re.findall(r"part: \[([^\]]+)\]", shard_flow)] or [99])
    if shard_macs > 4 or len(re.findall(r"^    runs-on: macos", shard_flow, re.M)) != 3:
        fail(f"mac-sharded-tests.yml の同時に動く Mac が増えています（分けた組 {shard_macs} 台）")
    part_action = ROOT / ".github/actions/mac-test-part/action.yml"
    if "continue-on-error" in (part_action.read_text(encoding="utf-8") if part_action.exists() else "continue-on-error"):
        fail(".github/actions/mac-test-part/action.yml が無いか、continue-on-error があります（落ちても印まで進む）")
    # 夜の定期の回は置かない（2026-11-11 owner「ガチの原因不明のバグの時だけ」）。定期は重さの記録（ios-perf.yml）だけ
    scheduled = sorted(name for name, text in workflows.items() if re.search(r"^  schedule:", text, re.M))
    if [n for n in scheduled if n not in ("ios-perf.yml", "cleanup-branches.yml", "safe-branch-cleanup.yml",
                                          "xcode-cache-warm.yml")]:
        fail(f"定期（schedule）で Mac のテストを流すワークフローがあります: {scheduled}")

    def step_block(text, name):
        found = re.search(r"^      - name: " + re.escape(name) + r"\n(.*?)(?=^      - |\Z)", text, re.M | re.S)
        return found.group(1) if found else None
    # テストを流す道具が、落ちたときに 1 で終わること（0 で終わると段が緑になる）
    runner = (ROOT / "Tools/xcode-test.sh").read_text(encoding="utf-8")
    # **pipefail が無いと** `xcodebuild … | tee | tail` の終了は tail のもの＝いつも 0 になり、
    # 下の `|| { exit 1 }` に来ない
    if not re.search(r"^set -[a-z]*o pipefail\b", runner, re.M):
        fail("Tools/xcode-test.sh に set -euo pipefail（pipefail）がありません（xcodebuild の失敗が tail に隠れる）")
    if not re.search(r'\| tee -a "\$LOG"\s*\|\| \{[^}]*\n\s*exit 1\n\s*\}', runner):
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
    # ---- Mac の控え（2026-11-11・(a)(b)）: 戻すのは共通の部品、書くのは xcode-cache-warm.yml だけ ------------------
    restore_action = ROOT / ".github/actions/xcode-cache-restore/action.yml"
    warm_yml = ROOT / ".github/workflows/xcode-cache-warm.yml"
    restore_text = restore_action.read_text(encoding="utf-8") if restore_action.exists() else ""
    warm_text = warm_yml.read_text(encoding="utf-8") if warm_yml.exists() else ""

    def _cache_paths(text, step):
        found = re.search(r"- name: " + re.escape(step) + r"\n(?:.*\n)*?\s+path: \|\n((?:\s+\S.*\n)+?)\s+key:", text)
        return [line.strip() for line in found.group(1).splitlines()] if found else None
    v2_paths = _cache_paths(restore_text, "控えを戻す（v3・依存と組んだものだけ）")
    if not v2_paths or v2_paths != _cache_paths(warm_text, "控えを書く"):
        fail("Mac の控え: .github/actions/xcode-cache-restore の v3 と xcode-cache-warm.yml の「控えを書く」の path が揃っていません（当たらない）")
    elif any(p.startswith("!") for p in v2_paths) or any("org.swift.swiftpm" in p for p in v2_paths):
        fail("Mac の控え v3: path に `!` の行を書かない（効かず 4GB になった・書く前に消す）・SwiftPM の置き場の写しは入れない")
    if 'rm -rf "$dd/SourcePackages/repositories" "$dd/Build/Intermediates.noindex/ArchiveIntermediates"' not in warm_text:
        fail("xcode-cache-warm.yml が、控えを書く前に SwiftPM の置き場の写しと Archive の中間物を消していません（7GB に戻る）")
    if "python3 Tools/source-mtime.py" not in restore_text:
        fail("Mac の控えを戻す部品が、ソースの時刻を中身から揃えていません（Tools/source-mtime.py）")
    for name, text in workflows.items():
        if "actions/cache/save@" in _code(text) and "DerivedData" in text and name != "xcode-cache-warm.yml":
            fail(f"{name} が Mac の控えを書いています（書くのは xcode-cache-warm.yml だけ・置き場 10GB）")
        if name != "xcode-cache-warm.yml" and "DerivedData/JourneyPhoto-*/SourcePackages" in _code(text):
            fail(f"{name} が Mac の控えの path を自分で書いています（.github/actions/xcode-cache-restore を使う）")
    for name in ("ios-quick.yml", "ios-testflight.yml", "mac-sharded-tests.yml"):
        if "uses: ./.github/actions/xcode-cache-restore" not in workflows.get(name, ""):
            fail(f"{name} が Mac の控えを戻す部品（.github/actions/xcode-cache-restore）を使っていません")

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

    # 共有カードの地図JSONはレンダラ単体テスト＋起動スモークに絞る。
    # 未分類のリソースを誤って除外しない（安全側は全UI）。
    def related_for(path):
        with tempfile.TemporaryDirectory() as tmp:
            relative = "Sources/JourneyPhoto/Resources/" + path
            diff = (
                f"diff --git a/{relative} b/{relative}\n"
                f"--- a/{relative}\n+++ b/{relative}\n"
                "@@ -1 +1 @@\n-old\n+new\n"
            )
            patch = Path(tmp) / "change.diff"
            patch.write_text(diff, encoding="utf-8")
            run = subprocess.run([sys.executable, str(picker), "--related", str(patch)],
                                 capture_output=True, text=True)
            return run.returncode, run.stdout.split()
    code, selected = related_for("country-outlines.json")
    if code != 0 or selected != ["-only-testing:JourneyPhotoUITests/SmokeTests"]:
        fail(f"共有カードの地図JSON変更なのにUIテストが絞れません: {code} {selected}")
    code, selected = related_for("unknown-map-resource.json")
    if code != 0 or selected != ["-only-testing:JourneyPhotoUITests"]:
        fail(f"未分類の地図リソースが安全側の全UIになりません: {code} {selected}")

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
    # **差分から選ぶ先に流す分に、名指し専用のテストを入れない**（2026-10-31・見直しの指摘）。
    # 名指し専用のテストが持つ識別子を、アプリのコードに足した差分を渡す
    for named_test in pick_mod.ONLY_WHEN_NAMED:
        lits = sorted(l for l in index.get(named_test, {}).get("literals", ()) if pick_mod.IDENT.match(l))
        if not lits:
            continue
        diff = f"+++ b/Sources/JourneyPhoto/X.swift\n@@ -1,0 +1,1 @@\n+let x = \"{lits[0]}\"\n"
        if named_test not in pick_mod.tests_for_diff(diff, index, loose):
            continue  # 差分から当たらない書き方なら、この例では確かめられない
        got = pick_mod.plan("", diff, 3, index=index, loose=loose)
        if f"{prefix}{named_test}" in got["first"]:
            fail(f"pick-ui-tests.py --plan が、差分から名指し専用のテスト（{named_test}）を先に流す分に入れます")
        break
    else:
        fail("pick-ui-tests.py の見張り: 名指し専用のテストに当たる差分の例が作れません（確かめられていない）")
    # **空の組は空のファイル**（xcode-test.sh が「流さない」と読む）
    with tempfile.TemporaryDirectory() as tmp:
        saved_plan = pick_mod.plan
        try:
            pick_mod.plan = lambda *a, **k: {**saved_plan(*a, **k), "parts": [[], [f"-only-testing:{pick_mod.TARGET}"]]}
            import contextlib, io
            with contextlib.redirect_stdout(io.StringIO()):
                pick_mod.main_plan(["2", tmp, "", "/nonexistent"])
        finally:
            pick_mod.plan = saved_plan
        if Path(tmp, "part-1.txt").read_text(encoding="utf-8") != "":
            fail("pick-ui-tests.py --plan が、空の組に改行を書きます（xcode-test.sh が中身ありと読み、UI を全部流す）")
    # 全部の回から外した重い試験（2026-11-11・run 42920469610 の内訳）。トランクの選び直しの1本目は全部の回に残す
    for name in ("PerformanceTests/testMainTabRevisitTime", "ScreenshotTests/testCapturesCamperRoomContactSheet",
                 "ScreenshotTests/testTrunkPickRepeat2", "ScreenshotTests/testTrunkPickRepeat3",
                 "ScreenshotTests/testTrunkPickRepeat4"):
        if not pick_mod.only_when_named(name):
            fail(f"pick-ui-tests.py の ONLY_WHEN_NAMED に {name} がありません（全部の回・PR で流れる）")
    if pick_mod.only_when_named("ScreenshotTests/testTrunkPickRepeat"):
        fail("pick-ui-tests.py: testTrunkPickRepeat（1本目）は全部の回に残す（札 #424 が閉じるまで）")
    # **毎回のの割り振り**（2026-11-11）: 1 台目は起動の見張り（＋単体の全部）。関係する UI と名指しは 2 台目から。
    # 全部には倒さない。2 台目からの 1 台の見積もりは QUICK_UI_BUDGET 以下（1 本で越えるテストは別）、台は最大 3
    smoke = sorted(t for t in index if t.startswith("SmokeTests/") and not pick_mod.only_when_named(t))
    if pick_mod.QUICK_MAX_PARTS > 3:
        fail("pick-ui-tests.py: 毎回のの Mac は最大 3 台（同時 5 台・TestFlight ともう 1 本の毎回のが待たない数）")
    got = pick_mod.quick_plan("", "", True, index=index, loose=loose)
    if got["parts"] != [smoke]:
        fail(f"pick-ui-tests.py --quick-plan が、差分の無い回で起動の見張りだけ（1 台）になりません: {got['parts']}")
    for unknown in ("diff --git a/project.yml b/project.yml\n--- a/project.yml\n+++ b/project.yml\n@@ -1 +1 @@\n-a\n+b\n",
                    "unrecognized diff"):
        got = pick_mod.quick_plan(unknown, "", True, index=index, loose=loose)
        if got["parts"] != [smoke]:
            fail("pick-ui-tests.py --quick-plan が、判定できない変更で起動の見張りより多く（全部に）倒れます")
    try:
        pick_mod.quick_plan("", "all", False, index=index, loose=loose)
        fail("pick-ui-tests.py --quick-plan が screens=all を受け付けます（全部は ios-full.yml）")
    except ValueError:
        pass
    seconds = pick_mod.estimate(sorted(index), pick_mod.read_times())
    shots = sorted((t for t in index if t.startswith("ScreenshotTests/") and not pick_mod.only_when_named(t)),
                   key=lambda t: seconds[t])
    got = pick_mod.quick_plan("", ",".join(t.split("/")[1] for t in shots[:12]), True, index=index, loose=loose)
    if got["parts"][0] != smoke or len(got["parts"]) > pick_mod.QUICK_MAX_PARTS or any(
            load > pick_mod.QUICK_UI_BUDGET and len(part) > 1 for part, load in zip(got["parts"][1:], got["loads"][1:])):
        fail(f"pick-ui-tests.py --quick-plan の 2 台目からが上限を越えるか、1 台目が見張りだけでありません: {got['loads']}")
    # 上限で外すのは差分から選んだものだけ（PR）。外したものは返す（門に出す）
    shot_file = "UITests/JourneyPhotoUITests/ScreenshotTests.swift"
    many = (f"diff --git a/{shot_file} b/{shot_file}\n--- a/{shot_file}\n+++ b/{shot_file}\n"
            + "".join(f"@@ -{min(index[t]['lines'])[0] + 1},1 +{min(index[t]['lines'])[0] + 1},1 @@\n+x\n"
                      for t in shots if index[t].get("lines")))
    got = pick_mod.quick_plan(many, "", True, index=index, loose=loose)
    if not got["dropped"] or len(got["parts"]) > pick_mod.QUICK_MAX_PARTS:
        fail(f"pick-ui-tests.py --quick-plan が、上限を越える関係する UI を外して dropped に返していません（{len(got['dropped'])}・{len(got['parts'])} 台）")
    # 全部の回から外した重い試験（2026-11-11・run 42920469610 の内訳）。トランクの選び直しの1本目は全部の回に残す
    for name in ("PerformanceTests/testMainTabRevisitTime", "ScreenshotTests/testCapturesCamperRoomContactSheet",
                 "ScreenshotTests/testTrunkPickRepeat2", "ScreenshotTests/testTrunkPickRepeat3",
                 "ScreenshotTests/testTrunkPickRepeat4"):
        if not pick_mod.only_when_named(name):
            fail(f"pick-ui-tests.py の ONLY_WHEN_NAMED に {name} がありません（全部の回で流れる）")
    if pick_mod.only_when_named("ScreenshotTests/testTrunkPickRepeat"):
        fail("pick-ui-tests.py: testTrunkPickRepeat（1本目）は全部の回に残す（札 #424 が閉じるまで）")
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

# ---- 重さの記録（ios-perf.yml・2026-11-04・札 #429）---------------------------
# 毎日1回 PerformanceTests を流して数を残す回。**有効にするまで走らせない**（変数 IOS_PERF_ENABLED）、
# **TestFlight に上げない・版を触らない**、**Mac を同時に1台しか使わない**、数が1つも拾えなければ落とす、を見張る
perf_yml = ROOT / ".github/workflows/ios-perf.yml"
if not perf_yml.exists():
    fail(".github/workflows/ios-perf.yml がありません（アプリの重さを定期に測る回）")
else:
    perf_text = perf_yml.read_text(encoding="utf-8")
    if not re.search(r"^  workflow_dispatch:", perf_text, re.M):
        fail("ios-perf.yml に手動実行（workflow_dispatch）がありません")
    cron = re.search(r'^\s+- cron: "(\d+) (\d+) \* \* \*"', perf_text, re.M)
    if not cron:
        fail("ios-perf.yml に1日1回の schedule（cron: \"分 時 * * *\"）がありません")
    elif cron.group(1) in ("0", "30"):
        fail("ios-perf.yml の schedule が 0 分・30 分です（GitHub の混む時間を避ける）")
    # 有効にするまで定期は走らせない: 変数が 'true' のときだけ（手動は常に可）。組む job と流す job の両方
    gate = "github.event_name == 'workflow_dispatch' || vars.IOS_PERF_ENABLED == 'true'"
    if gate not in perf_text:
        fail("ios-perf.yml の最初の job に「手動か vars.IOS_PERF_ENABLED == 'true'」の if がありません（有効にする前に定期で走る）")
    if not re.search(r"^  perf:\n(?:.*\n)*?    needs: build\n", perf_text, re.M):
        fail("ios-perf.yml の `perf` が `build` を待っていません（組む job が飛ばされたら流す job も飛ばす）")
    if "uses: ./.github/actions/mac-test-part" not in perf_text:
        fail("ios-perf.yml が mac-test-part を使っていません（流し方を写さず使い回す）")
    if not re.search(r"^concurrency:\n  group: ios-perf\n  cancel-in-progress: false", perf_text, re.M):
        fail("ios-perf.yml の concurrency が `ios-perf`・cancel-in-progress: false ではありません（Mac を重ねない）")
    if "--require" not in perf_text or "Tools/perf-collect.py" not in perf_text:
        fail("ios-perf.yml が数を拾う段（perf-collect.py --require）を持っていません")
    if "name: perf-record" not in perf_text:
        fail("ios-perf.yml が成果物 perf-record を残していません")
    for forbidden in ("testflight.sh", "next-marketing-version", "bump-build", "git push", "gh issue", "gh api"):
        if forbidden in perf_text:
            fail(f"ios-perf.yml に「{forbidden}」があります（版・TestFlight・Issue への書き込みには触らない）")
    if re.search(r"^      - name: テスト", perf_text, re.M):
        fail("ios-perf.yml の段が「テスト」で始まります（古い数え方に拾われる）")
    if "build/ui-plan/first.txt" not in perf_text:
        fail("ios-perf.yml が流す試験の一覧（first.txt）を作っていません")

# 名指しした回だけ流す2本（起動直後の記録・body の評価回数）は、UI テストに実在し、全部の回では流れない
import importlib.util as _perf_ilu
_pick_spec = _perf_ilu.spec_from_file_location("pick_ui_tests_perf", ROOT / "Tools/pick-ui-tests.py")
_pick = _perf_ilu.module_from_spec(_pick_spec)
_pick_spec.loader.exec_module(_pick)
_perf_src = (ROOT / "UITests/JourneyPhotoUITests/PerformanceTests.swift").read_text(encoding="utf-8")
for _named in ("testLaunchProbe", "testBodyEvaluationCounts"):
    if f"PerformanceTests/{_named}" not in _pick.ONLY_WHEN_NAMED:
        fail(f"pick-ui-tests.py の ONLY_WHEN_NAMED に PerformanceTests/{_named} がありません（全部の回で流れてしまう）")
    if f"func {_named}()" not in _perf_src:
        fail(f"PerformanceTests に {_named} がありません")

# ---- 結果 -----------------------------------------------------------------
if errors:
    for message in errors:
        print(f"NG  {message}")
    sys.exit(1)
print("設定ファイルの検査: 問題なし")
