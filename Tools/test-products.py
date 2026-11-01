#!/usr/bin/env python3
"""組んだテストの品（`build-for-testing` の出来上がり）を、別の Mac に渡すために包む・ほどく（2026-10-31・#429）。

    python3 Tools/test-products.py pack <Build/Products> <包み.tar>   # 包む（xctestrun が指す品だけ）
    python3 Tools/test-products.py unpack <包み.tar> <置き場>          # ほどいて、xctestrun の置き場を出す

**なぜ渡すか**: UI テストを3台の Mac に分けて同時に流す（`ios-testflight.yml`）。各台で組み直すと
控えから戻す 2 分＋組む 6 分（run 778 の実測）がかかる。組むのは1回にして、組んだ品を成果物で渡す。

**なぜ tar に包むか**: 成果物（upload-artifact）は zip で、ファイルの実行の権限が落ちる
（アプリの本体・テストの実行役が動かなくなる）。tar は権限と、品の中の別名（symlink）を保つ。

**包むのは xctestrun が指す品だけ**: `__TESTROOT__/…` で書かれた道（アプリ・テストの束・テストの実行役）を
xctestrun から読み、その最上位の束だけを包む（パッケージの中間物 `.o`・`.swiftmodule` は運ばない）。
xctestrun 自体は `__TESTROOT__` を自分の置き場として読むので、同じ並びでほどけばそのまま動く。
"""
import pathlib
import plistlib
import subprocess
import sys

ROOT_MARK = "__TESTROOT__/"
# 品の道を書く鍵だけを見る。環境変数（`DYLD_FRAMEWORK_PATH: __TESTROOT__/Debug-iphonesimulator:…`）は
# 置き場の全体を指すので拾わない（拾うとパッケージの中間物まで丸ごと運ぶ）
PRODUCT_KEYS = {"TestHostPath", "TestBundlePath", "UITargetAppPath", "DependentProductPaths"}


def referenced(value, out, key=None):
    """xctestrun の中の、品の道（`__TESTROOT__/…`）を拾う（版 1・2 のどちらの形でも）"""
    if isinstance(value, dict):
        for name, item in value.items():
            referenced(item, out, name)
    elif isinstance(value, list):
        for item in value:
            referenced(item, out, key)
    elif isinstance(value, str) and key in PRODUCT_KEYS and value.startswith(ROOT_MARK):
        out.add(value[len(ROOT_MARK):].rstrip("/"))


def bundles(paths):
    """`Debug-iphonesimulator/JourneyPhoto.app/PlugIns/X.xctest` のような中の道は、外の束（.app）に含まれる"""
    tops = set()
    for path in paths:
        parts = pathlib.PurePosixPath(path).parts
        # 最初に出てくる束（.app・.xctest・.framework）までで切る
        for i, part in enumerate(parts):
            if part.endswith((".app", ".xctest", ".framework", ".bundle")):
                tops.add("/".join(parts[: i + 1]))
                break
        else:
            tops.add(path)
    return sorted(t for t in tops if not any(t != o and t.startswith(o + "/") for o in tops))


def pack(products, tarball):
    products = pathlib.Path(products)
    runs = sorted(products.glob("*.xctestrun"))
    if len(runs) != 1:
        print(f"::error::xctestrun がちょうど1つではありません（{products}）: {[r.name for r in runs]}", file=sys.stderr)
        return 1
    found = set()
    referenced(plistlib.loads(runs[0].read_bytes()), found)
    items = bundles(found)
    missing = [i for i in items if not (products / i).exists()]
    if not items or missing:
        print(f"::error::xctestrun が指す品が見つかりません: {missing or '（0件）'}", file=sys.stderr)
        return 1
    print("包む: " + " / ".join([runs[0].name, *items]))
    subprocess.run(["tar", "-cf", str(pathlib.Path(tarball).resolve()), runs[0].name, *items],
                   cwd=products, check=True)
    return 0


def unpack(tarball, dest):
    dest = pathlib.Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    subprocess.run(["tar", "-xf", str(pathlib.Path(tarball).resolve())], cwd=dest, check=True)
    runs = sorted(dest.glob("*.xctestrun"))
    if len(runs) != 1:
        print(f"::error::ほどいた中に xctestrun がちょうど1つありません: {[r.name for r in runs]}", file=sys.stderr)
        return 1
    print(runs[0].resolve())
    return 0


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "pack":
        return pack(sys.argv[2], sys.argv[3])
    if len(sys.argv) == 4 and sys.argv[1] == "unpack":
        return unpack(sys.argv[2], sys.argv[3])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
