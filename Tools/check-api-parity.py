#!/usr/bin/env python3
"""アプリが叩く口と、api-user が生やしている口を突き合わせる。

Web 版（`rymaruta/photo-gallery`）は動き続ける。**追従を人の記憶に頼らない**
ための道具。見ているのは3つ:

  1. アプリが叩いているのに、サーバーに無い口   → 404 になる（**落とす**）
  2. 認証が要る口を、アプリが未認証で叩いている → 401 になる（**落とす**）
  3. サーバーにあるのに、アプリが使っていない口 → 未実装の一覧（参考）

    python3 Tools/check-api-parity.py ../photo-gallery

`photo-gallery` の場所は引数か環境変数 `PHOTO_GALLERY` で渡す。
無ければ「見ていない」と言って終わる（黙って緑にしない）。
"""
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent


def strip_interpolation(path: str) -> str:
    """Swift の文字列補間 `\(...)` を `{}` に潰す。

    **入れ子の括弧を数える。** `\(encoded(photoId))` を最初の `)` で切ると
    `{}）` のような残骸ができ、全部の口が「サーバーに無い」と誤報になる
    （実際に一度そうなった）。
    """
    out = []
    i = 0
    while i < len(path):
        if path.startswith("\\(", i):
            depth = 1
            i += 2
            while i < len(path) and depth > 0:
                if path[i] == "(":
                    depth += 1
                elif path[i] == ")":
                    depth -= 1
                i += 1
            out.append("{}")
            continue
        out.append(path[i])
        i += 1
    return "".join(out)


def normalize(path: str) -> str:
    """`/photos/{id}/like` と `/photos/\(encoded(photoId))/like` を同じ形にする。"""
    path = strip_interpolation(path)
    path = re.sub(r"\{[^}]*\}", "{}", path)      # serverless のパス変数
    return path.rstrip("/") or "/"


def server_endpoints(root: Path):
    """`api-user/serverless.yml` から (メソッド, パス, 認証が要るか) を拾う。"""
    text = (root / "api-user" / "serverless.yml").read_text(encoding="utf-8")
    endpoints = {}
    # httpApi の各項目は path → method → （あれば）authorizer の順で並ぶ
    pattern = re.compile(
        r"path:\s*(?P<path>\S+)\s*\n\s*method:\s*(?P<method>\w+)(?P<rest>(?:\s*\n(?!\s*- httpApi)[^\n]*)*)"
    )
    for m in pattern.finditer(text):
        path = normalize(m.group("path"))
        method = m.group("method").upper()
        needs_auth = "authorizer" in m.group("rest")
        endpoints[(method, path)] = needs_auth
    return endpoints


CALL = re.compile(
    r"api\.(?P<kind>authorized|authorizedVoid|anonymous)\(\s*\.(?P<method>get|post|put|patch|delete)\s*,\s*\"(?P<path>[^\"]+)\"",
    re.S,
)


def app_calls(root: Path):
    """サービス層が叩いている (メソッド, パス, 認証付きか) を拾う。"""
    calls = {}
    for file in (root / "Sources" / "JourneyPhoto" / "Services").glob("*.swift"):
        text = file.read_text(encoding="utf-8")
        for m in CALL.finditer(text):
            key = (m.group("method").upper(), normalize(m.group("path")))
            calls[key] = (m.group("kind") != "anonymous", file.name)
    return calls


def main() -> int:
    raw = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PHOTO_GALLERY", "../photo-gallery")
    root = Path(raw).expanduser().resolve()
    if not (root / "api-user" / "serverless.yml").exists():
        print(f"[skip] photo-gallery が {root} に見つかりません。")
        print("       突き合わせていません（引数か PHOTO_GALLERY で場所を渡してください）。")
        return 0

    server = server_endpoints(root)
    calls = app_calls(HERE)

    problems = []
    for (method, path), (authed, where) in sorted(calls.items()):
        if (method, path) not in server:
            problems.append(f"{where}: {method} {path} はサーバーにありません（404 になります）")
            continue
        if server[(method, path)] and not authed:
            problems.append(f"{where}: {method} {path} は認証が要るのに未認証で叩いています（401 になります）")

    unused = sorted(k for k in server if k not in calls)

    print(f"サーバーの口 {len(server)} / アプリが叩いている {len(calls)}")
    if unused:
        print(f"\nアプリが使っていない口（{len(unused)}）:")
        for method, path in unused:
            print(f"  {method:6} {path}")

    if problems:
        print()
        for p in problems:
            print(f"NG  {p}")
        return 1
    print("\n突き合わせ: 問題なし")
    return 0


if __name__ == "__main__":
    sys.exit(main())
