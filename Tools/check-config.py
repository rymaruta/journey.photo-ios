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
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
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

# ---- 結果 -----------------------------------------------------------------
if errors:
    for message in errors:
        print(f"NG  {message}")
    sys.exit(1)
print("設定ファイルの検査: 問題なし")
