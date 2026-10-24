#!/usr/bin/env python3
"""リポジトリの中で動く、最小のコーディングエージェント（Claude API・2026-10-24）。

Claude Code の上限に来たときの予備。コードを調べる・複数ファイルを直す・テストを流す・
ブランチを切ってコミット・push・PR を作る、までをターミナルから頼める。

使い方（リポジトリの直下で）:
    pip install anthropic
    export ANTHROPIC_API_KEY=...        # Codespaces なら Secrets に入れておけば不要
    python3 Tools/agent/agent.py                      # 対話（何度でも頼める）
    python3 Tools/agent/agent.py "テストが落ちる原因を調べて直して"   # 1回だけ

安全のための決まり:
  - ファイルの読み書きはリポジトリの中だけ（`safe_path`）
  - コマンドは毎回、実行前に確認する。読むだけのコマンド（ls・grep・git status 等）は
    `--yes-read` を付けたときだけ確認なしで流す
  - main / develop への直接 push と、force push は止める（`blocked`）
  - API キーは環境変数から読むだけで、表示もファイルへの書き出しもしない
費用: API は使った分だけかかる。1回の依頼で回る往復の上限を `--max-turns`（既定 40）で決める。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

try:
    import anthropic
except ImportError:
    sys.exit("anthropic が入っていません。`pip install anthropic` を流してください。")

MODEL = os.environ.get("AGENT_MODEL", "claude-opus-5-5")
ROOT = Path(os.environ.get("AGENT_ROOT", Path.cwd())).resolve()
MAX_OUT = 30_000  # ツールの結果として返す最大の文字数

# 確認なしで流してよい「読むだけ」のコマンド（--yes-read のときだけ）
READ_ONLY = re.compile(
    r"^(ls|cat|head|tail|wc|grep|rg|find|tree|pwd|git (status|diff|log|show|branch|remote -v)|gh pr (view|list|checks))\b"
)


def safe_path(path: str) -> Path:
    p = (ROOT / path).resolve()
    if p != ROOT and ROOT not in p.parents:
        raise ValueError(f"リポジトリの外は触れません: {path}")
    if ".git" in p.relative_to(ROOT).parts:
        raise ValueError(".git の中は触れません")
    return p


def clip(text: str) -> str:
    return text if len(text) <= MAX_OUT else text[:MAX_OUT] + f"\n…（{len(text) - MAX_OUT} 文字を省略）"


def blocked(command: str) -> str | None:
    """止めるコマンドなら理由を返す。"""
    if re.search(r"git\s+push\b.*(--force|-f\b|--force-with-lease)", command):
        return "force push は止めています"
    if re.search(r"git\s+push\b.*\b(main|master|develop)\b", command):
        return "main / develop への直接 push は止めています。新しいブランチに push して PR にしてください"
    if re.search(r"\brm\s+-[a-z]*r[a-z]*f|\brm\s+-[a-z]*f[a-z]*r", command) and re.search(r"(\s/|\s~|\s\.\s|\s\*)", command + " "):
        return "広い範囲の rm -rf は止めています"
    if re.search(r"(printenv|env\b|echo\s+\$ANTHROPIC|\$\{?ANTHROPIC_API_KEY)", command):
        return "環境変数・API キーの表示は止めています"
    return None


# ---- ツールの実装 -------------------------------------------------------------

def tool_list_files(pattern: str = "**/*") -> str:
    files = [
        str(p.relative_to(ROOT))
        for p in ROOT.glob(pattern)
        if p.is_file() and ".git" not in p.relative_to(ROOT).parts
    ]
    return clip("\n".join(sorted(files)[:2000]) or "（該当なし）")


def tool_search(pattern: str, path: str = ".") -> str:
    target = safe_path(path)
    cmd = ["grep", "-rnI", "--exclude-dir=.git", "--exclude-dir=node_modules", "--exclude-dir=.build", "-E", pattern, str(target)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    out = r.stdout.replace(str(ROOT) + "/", "")
    return clip(out or "（該当なし）")


def tool_read_file(path: str, start: int = 1, end: int = 0) -> str:
    lines = safe_path(path).read_text(errors="replace").splitlines()
    end = end or len(lines)
    body = "\n".join(f"{i}\t{l}" for i, l in enumerate(lines[start - 1:end], start))
    return clip(body or "（空のファイル）")


def tool_edit_file(path: str, old: str, new: str) -> str:
    p = safe_path(path)
    text = p.read_text()
    n = text.count(old)
    if n != 1:
        return f"エラー: old が {n} 回見つかりました。1回だけ当たるように前後を含めて長くしてください"
    p.write_text(text.replace(old, new))
    return f"編集しました: {path}"


def tool_write_file(path: str, content: str) -> str:
    p = safe_path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return f"書きました: {path}（{len(content)} 文字）"


def tool_run(command: str, auto_read: bool) -> str:
    reason = blocked(command)
    if reason:
        return f"止めました: {reason}"
    if not (auto_read and READ_ONLY.match(command.strip())):
        ans = input(f"\n\033[33m実行してよいですか？\033[0m $ {command}\n[y/N] ").strip().lower()
        if ans != "y":
            return "ユーザーが実行を断りました。別の方法を考えるか、ユーザーに聞いてください"
    try:
        r = subprocess.run(command, shell=True, cwd=ROOT, capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        return "15 分で打ち切りました"
    return clip(f"exit={r.returncode}\n--- stdout\n{r.stdout[-MAX_OUT:]}\n--- stderr\n{r.stderr[-5000:]}")


TOOLS = [
    {
        "name": "list_files",
        "description": "リポジトリ内のファイルを glob で一覧する（最大 2000 件）。",
        "input_schema": {
            "type": "object",
            "properties": {"pattern": {"type": "string", "description": "glob。例: Sources/**/*.swift"}},
            "required": [],
            "additionalProperties": False,
        },
    },
    {
        "name": "search",
        "description": "正規表現（grep -E）でリポジトリ内を探す。ファイル:行:中身 を返す。",
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string"},
                "path": {"type": "string", "description": "探す範囲（既定はリポジトリ全体）"},
            },
            "required": ["pattern"],
            "additionalProperties": False,
        },
    },
    {
        "name": "read_file",
        "description": "ファイルを行番号つきで読む。大きいファイルは start/end で範囲を絞る。",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "start": {"type": "integer", "description": "最初の行（1始まり）"},
                "end": {"type": "integer", "description": "最後の行（0 なら最後まで）"},
            },
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "edit_file",
        "description": "ファイルの old を new に置き換える。old はファイル中にちょうど1回だけ現れること（行番号は含めない）。",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string"}, "old": {"type": "string"}, "new": {"type": "string"}},
            "required": ["path", "old", "new"],
            "additionalProperties": False,
        },
    },
    {
        "name": "write_file",
        "description": "新しいファイルを作る、またはファイル全体を書き直す。",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
            "required": ["path", "content"],
            "additionalProperties": False,
        },
    },
    {
        "name": "run",
        "description": "シェルコマンドをリポジトリの直下で実行する（テスト・ビルド・git・gh など）。実行前にユーザーが確認する。",
        "input_schema": {
            "type": "object",
            "properties": {"command": {"type": "string"}},
            "required": ["command"],
            "additionalProperties": False,
        },
    },
]

SYSTEM = """あなたはこのリポジトリで働くコーディングエージェントです。ユーザーへの返事は日本語で書きます。
進め方:
1. まずリポジトリの決まり（CLAUDE.md・README・docs）と関係するコードを調べる。推測で直さない。
2. 直す前に、何をどう直すかを短く言う。
3. 直したら、そのリポジトリのテスト・検査を流して確かめる。流していないものを「通った」と言わない。
4. 頼まれたときだけ、新しいブランチを切ってコミットし、push して `gh pr create` で PR を作る。
   main / develop には直接 push しない。force push しない。
5. 終わったら、変えたもの（ファイル）・確かめたこと・確かめていないことを短く報告する。
秘密情報（API キー・トークン）を表示・保存しない。リポジトリの外のファイルに触れない。"""


def run_tool(name: str, args: dict, auto_read: bool) -> str:
    try:
        if name == "list_files":
            return tool_list_files(**args)
        if name == "search":
            return tool_search(**args)
        if name == "read_file":
            return tool_read_file(**args)
        if name == "edit_file":
            return tool_edit_file(**args)
        if name == "write_file":
            return tool_write_file(**args)
        if name == "run":
            return tool_run(args["command"], auto_read)
        return f"知らない道具です: {name}"
    except Exception as e:  # 道具の失敗はモデルに返して、自分で直させる
        return f"エラー: {type(e).__name__}: {e}"


def show_call(name: str, args: dict) -> None:
    short = {k: (v if len(str(v)) < 80 else str(v)[:77] + "…") for k, v in args.items()}
    print(f"\033[36m→ {name} {json.dumps(short, ensure_ascii=False)}\033[0m")


def ask(client: anthropic.Anthropic, messages: list, max_turns: int, auto_read: bool) -> None:
    """ユーザーの1回の依頼について、道具を使い終わるまで回す。"""
    for _ in range(max_turns):
        with client.beta.messages.stream(
            model=MODEL,
            max_tokens=32_000,
            system=[{"type": "text", "text": SYSTEM, "cache_control": {"type": "ephemeral"}}],
            tools=TOOLS,
            messages=messages,
            output_config={"effort": "high"},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        ) as stream:
            for text in stream.text_stream:
                print(text, end="", flush=True)
            reply = stream.get_final_message()
        print()
        # 返ってきた中身はそのまま履歴に足す（考えた跡の塊も含めて、書き換えない）
        messages.append({"role": "assistant", "content": reply.content})

        if reply.stop_reason == "refusal":
            print("（安全確認で断られました。頼み方を変えてください）")
            return
        if reply.stop_reason == "max_tokens":
            print("（出力の上限に達しました。「続けて」と頼んでください）")
            return
        if reply.stop_reason == "pause_turn":
            continue
        tool_uses = [b for b in reply.content if b.type == "tool_use"]
        if not tool_uses:
            return
        results = []
        for b in tool_uses:
            show_call(b.name, b.input)
            out = run_tool(b.name, dict(b.input), auto_read)
            results.append({"type": "tool_result", "tool_use_id": b.id, "content": out})
        # 全部の結果を1つのメッセージで返す
        messages.append({"role": "user", "content": results})
    print(f"（往復の上限 {max_turns} 回に達したので止めました。続けるなら「続けて」と頼んでください）")


def main() -> None:
    ap = argparse.ArgumentParser(description="リポジトリの中で動く、最小のコーディングエージェント")
    ap.add_argument("task", nargs="*", help="頼みたいこと（省くと対話）")
    ap.add_argument("--max-turns", type=int, default=40, help="1回の依頼で回す往復の上限（費用の歯止め）")
    ap.add_argument("--yes-read", action="store_true", help="読むだけのコマンドは確認なしで流す")
    a = ap.parse_args()

    if not (os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN")):
        sys.exit("ANTHROPIC_API_KEY がありません。Codespaces の Secrets か環境変数に入れてください。")
    client = anthropic.Anthropic()
    messages: list = []
    print(f"リポジトリ: {ROOT}\nモデル: {MODEL}（AGENT_MODEL で変えられる）\n")

    if a.task:
        messages.append({"role": "user", "content": " ".join(a.task)})
        ask(client, messages, a.max_turns, a.yes_read)
        return
    while True:
        try:
            text = input("\n\033[32mあなた>\033[0m ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if text in ("exit", "quit", "終わり"):
            return
        if not text:
            continue
        messages.append({"role": "user", "content": text})
        try:
            ask(client, messages, a.max_turns, a.yes_read)
        except anthropic.RateLimitError:
            print("（API の利用上限に当たりました。しばらく待ってから続けてください）")
        except anthropic.APIStatusError as e:
            print(f"（API のエラー {e.status_code}: {e.message}）")
        except anthropic.APIConnectionError:
            print("（API につながりませんでした）")


if __name__ == "__main__":
    main()
