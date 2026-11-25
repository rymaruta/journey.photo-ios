#!/usr/bin/env python3
"""xcodebuild の全文ログから、コンパイルのエラーの行だけを Markdown で出す（2026-11-18・ビルドだけの回）。

    python3 Tools/compile-errors.py <xcodebuild の全文ログ> [--annotate]

- `file:line:col: error: …` の行を、重なりを除いて出た順に並べる（置き場はリポジトリからの相対にする）
- その形の行が無いとき（リンク・依存の解決・署名など）は、`error:` を含む行と
  「The following build commands failed:」の下の行を出す
- `--annotate` を付けると、Markdown の代わりに先頭10件を GitHub の `::error file=…,line=…::` で出す
  （run の画面の注釈。注釈の命令は標準出力から読まれるので、要約とは別に呼ぶ）
- `--warnings` を付けると、エラーの代わりに自分のコード（Sources・Tests・UITests）の `warning:` を数える。
  ファイルごと・種類ごとの数と、全部の行を出す（2026-11-25 判断: Swift 6 へ移す前に、本物の SDK での
  並行処理の警告の数を Mac のビルドだけの回で数えるため。Linux の模型では SDK 側の型の決まりが本物と違う）

2026-11-18 判断: 担当が Mac の回を「試しに流す場所」に使い、1日 40 回中 24 回落ちた（うち3回はビルドの失敗）。
落ちた理由を `gh run view --log-failed` の数千行から探さずに、job の要約だけで分かるようにする。
Markdown は標準出力へ（ワークフローが GITHUB_STEP_SUMMARY に足す）。
"""
import re
import sys
from pathlib import Path

LOCATED = re.compile(r"^(?P<path>/[^:\n]+?\.(?:swift|m|mm|h|c|cpp|plist|xcconfig|yml|json|strings|xcstrings|metal)):"
                     r"(?P<line>\d+)(?::(?P<col>\d+))?: (?:fatal )?error: (?P<msg>.*)$")
LIMIT = 60
ANNOTATE_LIMIT = 10


def relative(path):
    """ランナーの置き場（/Users/runner/work/<repo>/<repo>/…）を外し、リポジトリからの相対にする"""
    for marker in ("/Sources/", "/Tests/", "/UITests/", "/Packages/", "/Tools/"):
        at = path.find(marker)
        if at >= 0:
            return path[at + 1:]
    return path


WARNED = re.compile(r"^(?P<path>/[^:\n]+?\.swift):(?P<line>\d+)(?::(?P<col>\d+))?: warning: (?P<msg>.*)$")
WARN_LIMIT = 900


def warnings(text):
    """自分のコードの warning を、同じ行の重なりを除いて出す（Markdown）"""
    found, seen = [], set()
    for line in text.splitlines():
        m = WARNED.match(line.strip())
        if not m:
            continue
        if "/SourcePackages/" in m["path"] or "/checkouts/" in m["path"]:
            continue  # 外の部品の警告は数えない
        path = relative(m["path"])
        if not path.startswith(("Sources/", "Tests/", "UITests/")):
            continue  # 外の部品（SourcePackages）の警告は数えない
        key = (path, m["line"], m["msg"].strip())
        if key in seen:
            continue
        seen.add(key)
        found.append(key)
    by_file, by_kind = {}, {}
    for path, _, msg in found:
        by_file[path] = by_file.get(path, 0) + 1
        kind = re.sub(r"'[^']*'", "X", msg).split(";")[0]
        by_kind[kind] = by_kind.get(kind, 0) + 1
    out = ["### 自分のコードの警告", f"{len(found)} 件（同じ行の重なりは除いた）・{len(by_file)} ファイル", ""]
    out.append("#### 種類ごと")
    for kind, n in sorted(by_kind.items(), key=lambda kv: -kv[1])[:40]:
        out.append(f"- {n}: {kind}")
    out += ["", "#### ファイルごと"]
    for path, n in sorted(by_file.items(), key=lambda kv: -kv[1]):
        out.append(f"- {n}: `{path}`")
    out += ["", "#### 全部", "```"]
    out += [f"{p}:{l}: {m}" for p, l, m in found[:WARN_LIMIT]]
    if len(found) > WARN_LIMIT:
        out.append(f"…ほか {len(found) - WARN_LIMIT} 件")
    out.append("```")
    return "\n".join(out)


def main(argv):
    if not argv:
        print("使い方: compile-errors.py <xcodebuild の全文ログ> [--annotate]", file=sys.stderr)
        return 2
    log = Path(argv[0])
    annotate = "--annotate" in argv[1:]
    text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
    if "--warnings" in argv[1:]:
        print(warnings(text))
        return 0
    lines = text.splitlines()

    located, seen = [], set()
    for line in lines:
        m = LOCATED.match(line.strip())
        if not m:
            continue
        key = (relative(m["path"]), m["line"], m["msg"].strip())
        if key in seen:
            continue
        seen.add(key)
        located.append({"path": key[0], "line": m["line"], "col": m["col"] or "", "msg": key[2]})

    if annotate:
        for e in located[:ANNOTATE_LIMIT]:
            # 注釈の本文は1行。`::` の決まりで % と改行を逃がす
            msg = e["msg"].replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            col = f",col={e['col']}" if e["col"] else ""
            print(f"::error file={e['path']},line={e['line']}{col}::{msg}")
        return 0

    out = ["### コンパイルのエラー"]
    if not text:
        out.append(f"ログ（{log}）がありません。組む前の段で落ちています（上の段のログを見る）")
    elif located:
        out.append(f"{len(located)} 件（同じ行の重なりは除いた）")
        out.append("")
        for e in located[:LIMIT]:
            out.append(f"- `{e['path']}:{e['line']}` {e['msg']}")
        if len(located) > LIMIT:
            out.append(f"- …ほか {len(located) - LIMIT} 件（残りは job のログの「コンパイルだけ」の段）")
    else:
        others = []
        for line in lines:
            s = line.strip()
            if "error:" in s and s not in others:
                others.append(s)
        failed = []
        if "The following build commands failed:" in text:
            tail = text.split("The following build commands failed:", 1)[1].splitlines()
            for line in tail[1:]:
                if not line.startswith("\t") and not line.startswith(" "):
                    break
                failed.append(line.strip())
        out.append("`file:line: error:` の形の行はありません。`error:` を含む行と、落ちた組み立ての手順:")
        out.append("")
        out.append("```")
        out.extend(others[:LIMIT] or ["（error: を含む行も無い）"])
        if failed:
            out.append("--- The following build commands failed:")
            out.extend(failed[:30])
        out.append("```")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
