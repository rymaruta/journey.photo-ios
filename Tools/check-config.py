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
    fail("project.yml の UIAppFonts が空です（見出しの明朝・数字の等幅が出ません）")
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
for lic in ("OFL-ShipporiMincho.txt", "OFL-IBMPlexMono.txt"):
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

# ---- 結果 -----------------------------------------------------------------
if errors:
    for message in errors:
        print(f"NG  {message}")
    sys.exit(1)
print("設定ファイルの検査: 問題なし")
