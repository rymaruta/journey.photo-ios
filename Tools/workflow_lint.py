#!/usr/bin/env python3
"""GitHub Actions のワークフローと CI スクリプトの「書き間違い」を、Linux で数秒で見つける。

2026-11-04 の調べ（直近60回）で、TestFlight の失敗 23 件のうち 6 件は、ワークフローや
CI スクリプト自体の書き間違いだった。UI テストを 156 分流してから `run:` の構文エラーで落ちた回もある。
actionlint は入れられない（ダウンロードが拒否された）ので、**実際に踏んだ事故の再発防止を
1つずつ検査にする**（Web 側 `scripts/__tests__/workflowShell.test.ts` と同じ考え方）。

  1. `run:` の各段を `bash -n`（`${{ … }}` は `X` に置換。bash 以外の `shell:` の段は飛ばす）
     ——#451 で入った `find … \\( -iname …` が macOS の bash で構文エラーになった（#818・#819・#825）
  2. `Tools/*.py` を `py_compile`——#466 で `pick-ui-tests.py` に文字どおりの `\\n` が入った（#824）
  3. 参照先の実在——`uses: ./.github/actions/…`、`run:` 中の `bash Tools/…`・`python3 Tools/…`
  4. `secrets.X` の X が `docs/GITHUB_ACTIONS.md` に書いてある名前か（綴り違い）
  5. 全 job に `permissions`（workflow 全体の指定でもよい）と `timeout-minutes`
     （`uses:` で別のワークフローを呼ぶ job は後者の対象外。呼ぶ先に書く）

`check-config.py` から呼ぶ。単体でも `python3 Tools/workflow_lint.py` で流せる。
"""
import py_compile
import re
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# GitHub が自動で渡す Secrets（docs には書かない）
BUILTIN_SECRETS = {"GITHUB_TOKEN"}

EXPR = re.compile(r"\$\{\{.*?\}\}", re.DOTALL)
# `steps.secrets.outputs` のような別の式の一部を拾わない（前が `.` や英数字でないものだけ）
SECRET_REF = re.compile(r"(?<![\w.])secrets\.([A-Za-z_][A-Za-z0-9_]*)")
# `bash Tools/x.sh`・`python3 Tools/x.py`・`node Tools/x.js`（先頭の env 指定や `-u` などの旗は許す）
TOOL_REF = re.compile(r"(?:^|[\s;&|(])(?:bash|sh|python3?|node)\s+(?:-[A-Za-z]+\s+)*(\.?/?Tools/[A-Za-z0-9_./-]+)")


def _yaml():
    try:
        import yaml  # type: ignore
        return yaml
    except ModuleNotFoundError:
        return None


def workflow_files(root=ROOT):
    return sorted((root / ".github/workflows").glob("*.y*ml")) + sorted((root / ".github/actions").glob("*/action.y*ml"))


def run_steps(doc):
    """(場所, run の文, shell) を全部返す。workflow は jobs.*.steps、composite action は runs.steps。"""
    out = []
    wf_shell = ((doc.get("defaults") or {}).get("run") or {}).get("shell")
    for name, job in (doc.get("jobs") or {}).items():
        job_shell = (((job or {}).get("defaults") or {}).get("run") or {}).get("shell") or wf_shell
        for i, step in enumerate((job or {}).get("steps") or []):
            if isinstance(step, dict) and isinstance(step.get("run"), str):
                out.append((f"job {name} の段 {i + 1}（{step.get('name', '名前なし')}）", step["run"], step.get("shell") or job_shell))
    steps = (doc.get("runs") or {}).get("steps") or []
    for i, step in enumerate(steps):
        if isinstance(step, dict) and isinstance(step.get("run"), str):
            out.append((f"段 {i + 1}（{step.get('name', '名前なし')}）", step["run"], step.get("shell")))
    return out


def is_bash(shell):
    # 指定なし（Linux/macOS の既定は bash）・bash・sh は検査する。python・pwsh など別の言語は飛ばす
    return shell is None or str(shell).split()[0] in ("bash", "sh")


def bash_syntax_errors(script):
    """`bash -n` に掛ける。`${{ }}` は X に置換。構文エラーの文（なければ空）を返す。"""
    text = EXPR.sub("X", script)
    p = subprocess.run(["bash", "-n"], input=text, capture_output=True, text=True)
    return p.stderr.strip() if p.returncode != 0 else ""


def lint_doc(path, doc, root=ROOT, known_secrets=None, raw_text=""):
    """1つのワークフロー（か action）の NG の文を返す。"""
    rel = path.relative_to(root) if path.is_absolute() and root in path.parents else path
    errs = []
    if not isinstance(doc, dict):
        return [f"{rel} が YAML の辞書として読めません"]
    # 1. bash -n / 3. 参照先
    for where, script, shell in run_steps(doc):
        if is_bash(shell):
            e = bash_syntax_errors(script)
            if e:
                errs.append(f"{rel} の {where} が bash の構文エラー（bash -n）: {e.splitlines()[0]}")
        for m in TOOL_REF.finditer(EXPR.sub("X", script)):
            ref = m.group(1).lstrip("./")
            if re.search(r"(^|/)X(\.|/|$)", ref):
                continue  # 式で組んだ名前は確かめられない
            if not (root / ref).exists():
                errs.append(f"{rel} の {where} が、無いファイルを呼んでいます: {ref}")
    jobs = doc.get("jobs") or {}
    for name, job in jobs.items():
        job = job or {}
        for i, step in enumerate(job.get("steps") or []):
            uses = step.get("uses") if isinstance(step, dict) else None
            if isinstance(uses, str) and uses.startswith("./"):
                if not (root / uses / "action.yml").exists() and not (root / uses / "action.yaml").exists():
                    errs.append(f"{rel} の job {name} の段 {i + 1} が、無い action を使っています: {uses}")
        # 5. permissions と timeout-minutes
        if "permissions" not in job and "permissions" not in doc:
            errs.append(f"{rel} の job {name} に permissions がありません（workflow 全体にも無い）")
        if "uses" not in job and "timeout-minutes" not in job:
            errs.append(f"{rel} の job {name} に timeout-minutes がありません（止まったとき既定の 360 分待つ）")
        if isinstance(job.get("uses"), str) and job["uses"].startswith("./"):
            if not (root / job["uses"]).exists():
                errs.append(f"{rel} の job {name} が、無いワークフローを呼んでいます: {job['uses']}")
    for step in (doc.get("runs") or {}).get("steps") or []:
        uses = step.get("uses") if isinstance(step, dict) else None
        if isinstance(uses, str) and uses.startswith("./") and not (root / uses / "action.yml").exists():
            errs.append(f"{rel} が、無い action を使っています: {uses}")
    return errs


def documented_secrets(root=ROOT):
    """docs/GITHUB_ACTIONS.md に `名前` の形で書いてある大文字の名前。"""
    doc = root / "docs/GITHUB_ACTIONS.md"
    if not doc.exists():
        return None
    return set(re.findall(r"`([A-Z][A-Z0-9_]{3,})`", doc.read_text(encoding="utf-8")))


def secret_errors(files_text, known):
    """files_text: {パス: 文字列}。使っている secrets.X が known に無ければ NG（綴り違い）。"""
    errs = []
    for rel, text in files_text.items():
        no_comment = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
        for name in sorted(set(SECRET_REF.findall(no_comment))):
            if name not in known and name not in BUILTIN_SECRETS:
                errs.append(f"{rel} が、docs/GITHUB_ACTIONS.md に無い Secrets を使っています: secrets.{name}（綴り違いか、docs の追記漏れ）")
    return errs


def python_errors(root=ROOT):
    errs = []
    for py in sorted((root / "Tools").glob("*.py")):
        with tempfile.TemporaryDirectory() as tmp, warnings.catch_warnings():
            # docstring の `\(` などの「将来エラーになる警告」は、いまの構文エラーではないので黙らせる
            warnings.simplefilter("ignore")
            try:
                py_compile.compile(str(py), cfile=str(Path(tmp) / "x.pyc"), doraise=True)
            except py_compile.PyCompileError as e:
                errs.append(f"Tools/{py.name} が Python の構文エラー: {str(e.msg).strip().splitlines()[-1] if e.msg else e}")
    return errs


def lint(root=ROOT):
    """全部の検査を流して NG の文のリストを返す。PyYAML が無ければ (errs, 飛ばした理由)。"""
    yaml = _yaml()
    errs = python_errors(root)
    if yaml is None:
        return errs, "PyYAML が無いのでワークフローの検査は飛ばした（py_compile だけ行った）"
    texts = {}
    for path in workflow_files(root):
        text = path.read_text(encoding="utf-8")
        rel = str(path.relative_to(root))
        texts[rel] = text
        try:
            doc = yaml.safe_load(text)
        except Exception as e:  # noqa: BLE001
            errs.append(f"{rel} が YAML として読めません: {str(e).splitlines()[0]}")
            continue
        errs.extend(lint_doc(path, doc, root))
    known = documented_secrets(root)
    if known is None:
        errs.append("docs/GITHUB_ACTIONS.md が無いので Secrets の名前を突き合わせられません")
    else:
        errs.extend(secret_errors(texts, known))
    return errs, ""


def main():
    errs, skipped = lint()
    if skipped:
        print(f"[skip] {skipped}")
    for e in errs:
        print(f"NG  {e}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
