#!/usr/bin/env python3
"""xcodebuild の全文ログから、コンパイルのエラーの行だけを Markdown で出す（2026-11-18・ビルドだけの回）。

    python3 Tools/compile-errors.py <xcodebuild の全文ログ> [--annotate]

- `file:line:col: error: …` の行を、重なりを除いて出た順に並べる（置き場はリポジトリからの相対にする）
- その形の行が無いとき（リンク・依存の解決・署名など）は、`error:` を含む行と
  「The following build commands failed:」の下の行を出す
- `--annotate` を付けると、Markdown の代わりに先頭10件を GitHub の `::error file=…,line=…::` で出す
  （run の画面の注釈。注釈の命令は標準出力から読まれるので、要約とは別に呼ぶ）

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


def main(argv):
    if not argv:
        print("使い方: compile-errors.py <xcodebuild の全文ログ> [--annotate]", file=sys.stderr)
        return 2
    log = Path(argv[0])
    annotate = "--annotate" in argv[1:]
    text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
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
