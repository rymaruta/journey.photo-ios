#!/usr/bin/env python3
"""「この木は Mac で通っているか」の判定を1か所にまとめる（GitHub の API を読むだけ・Linux で数秒）。

使う所は2つ。**同じ判定を2つ作らない**ためにここへ置いた:

  - `ios-pr.yml` の「同じコミットが Mac でテスト済みかを見る」（`tested` の job）
      → `mac-run <sha>`: そのコミットで、Mac の全部のテストが通った TestFlight の回があれば、その run 番号を出す
  - `ios-testflight.yml` の「上げる前の関門」（`gate` の job・`submit=true` の回）
      → `gate <sha> <木>`: その木が、PR の検証の Xcode の段で success になっているか
        （または同じ木を Mac で通した別の回があるか）。無ければ日本語で理由を書いて exit 1

考え方（`tested` と同じ）: **コミットではなく木（tree）で同じかを見る。** マージの印のコミットは
PR の先頭と別でも、中身（木）が同じなら同じものを試している。1つでも読めなければ「通っていない」に倒す。

2026-11-04 の事故: PR #476 は Mac の単体テストが4件落ちる（Xcode の検査が終わる前に）マージされ、
main の 1d12c76 から TestFlight 1.1.60 が `組む・単体・UI` を skipped のまま上がった。
上げる回は既定でテストを流さないので、**ここで止めないと検査を通っていない木が TestFlight に出る**。
"""
import json
import os
import subprocess
import sys

# 名前は ios-testflight.yml / ios-pr.yml と揃える（`test_tested_gate.py` が突き合わせる）
MARK_STEP = "全部のテストが通った（PR の検証が数える印）"
XCODE_JOB = "Xcode のビルドとテスト（シミュレータ）"
MAC_OK_CONCLUSIONS = ("success", "cancelled")  # failure の回は数えない（どこかが落ちた回）
LOOK_BACK = 40  # 木で探すときに見る直近の回の数（API を打ちすぎない）


def gh_api(path):
    """`gh api` で読む。読めなければ None（呼び出し側は「通っていない」に倒す）。"""
    p = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if p.returncode != 0:
        return None
    try:
        return json.loads(p.stdout)
    except ValueError:
        return None


def _runs(api, repo, workflow, query):
    data = api(f"repos/{repo}/actions/workflows/{workflow}/runs?{query}")
    return (data or {}).get("workflow_runs") or []


def _jobs(api, repo, run_id):
    data = api(f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")
    return (data or {}).get("jobs") or []


def has_mark(jobs):
    """印の段は2か所にある（1台で流す回は `build`、分けて流す回は「まとめ」の job）。どれか1つが success ならよい。"""
    return any(s.get("name") == MARK_STEP and s.get("conclusion") == "success"
               for j in jobs for s in (j.get("steps") or []))


def xcode_passed(jobs):
    return any(j.get("name") == XCODE_JOB and j.get("conclusion") == "success" for j in jobs)


def mac_run_for_sha(sha, repo, api=gh_api):
    """そのコミットで Mac の全部のテストが通った TestFlight の回の run 番号（無ければ None）。"""
    for run in _runs(api, repo, "ios-testflight.yml", f"head_sha={sha}&status=completed&per_page=30"):
        if run.get("conclusion") in MAC_OK_CONCLUSIONS and has_mark(_jobs(api, repo, run["id"])):
            return run["id"]
    return None


def tree_of(sha, repo, api=gh_api):
    if not sha:
        return None
    data = api(f"repos/{repo}/commits/{sha}")
    return ((data or {}).get("commit") or {}).get("tree", {}).get("sha")


def memoized(api):
    """同じ path を2度打たない（木の探し方が、同じコミットを何度も引く）。"""
    seen = {}

    def call(path):
        if path not in seen:
            seen[path] = api(path)
        return seen[path]
    return call


def mac_run_for_tree(tree, repo, api=gh_api):
    """同じ木を Mac で通した TestFlight の回（コミットは違ってもよい）。"""
    for run in _runs(api, repo, "ios-testflight.yml", f"status=completed&per_page={LOOK_BACK}"):
        if run.get("conclusion") not in MAC_OK_CONCLUSIONS:
            continue
        if tree_of(run.get("head_sha", ""), repo, api) == tree and has_mark(_jobs(api, repo, run["id"])):
            return run["id"]
    return None


def pr_run_for_tree(tree, repo, api=gh_api):
    """同じ木の PR の先頭で、PR の検証の Xcode の段が success になった回。"""
    for run in _runs(api, repo, "ios-pr.yml", f"event=pull_request&status=completed&per_page={LOOK_BACK}"):
        if tree_of(run.get("head_sha", ""), repo, api) == tree and xcode_passed(_jobs(api, repo, run["id"])):
            return run["id"]
    return None


def judge(sha, tree, repo, api=gh_api):
    """(通ったか, 理由) を返す。通ったのは Mac で確かめた証拠が1つでも見つかったとき。"""
    if not tree:
        return False, "上げる sha の木が読めない"
    api = memoized(api)
    run = mac_run_for_sha(sha, repo, api)
    if run:
        return True, f"このコミットで Mac の全部のテストが通った TestFlight の run {run}"
    run = pr_run_for_tree(tree, repo, api)
    if run:
        return True, f"同じ木が PR の検証の Xcode の段で success（run {run}）"
    run = mac_run_for_tree(tree, repo, api)
    if run:
        return True, f"同じ木を Mac で通した TestFlight の run {run}"
    return False, "この木が Mac のテストを通った記録が見つからない"


def refusal_message(sha, tree, reason):
    return (
        f"TestFlight に上げるのを止めました: {reason}。\n"
        f"  上げようとした sha: {sha}\n  その木: {tree or '不明'}\n"
        f"  足りない検査: PR の検証（ios-pr.yml）の「{XCODE_JOB}」が、この木で success になっていること\n"
        "    （または同じ木を Mac で通した別の TestFlight の回があること）。\n"
        "  上げるには、次のどれか:\n"
        "    1. PR の検証の Xcode の段が緑になるまで待ってから、もう一度流す（普通はこれ）\n"
        "    2. main が動いて木が変わっているなら、tests=true で流す（この回の Mac でテストしてから上げる）\n"
        "    3. 理由があって検査なしで上げるなら、skip_tested_gate=true で流す（理由は Summary に残る）"
    )


def main(argv):
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    if len(argv) == 2 and argv[0] == "mac-run":
        run = mac_run_for_sha(argv[1], repo)
        if run:
            print(run)
        return 0
    if len(argv) == 3 and argv[0] == "gate":
        ok, reason = judge(argv[1], argv[2], repo)
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if ok:
            print(f"関門を通過: {reason}")
            if summary:
                with open(summary, "a", encoding="utf-8") as f:
                    f.write(f"### 上げる前の関門: 通過\n{reason}\n")
            return 0
        msg = refusal_message(argv[1], argv[2], reason)
        print(f"::error::{msg.splitlines()[0]}")
        print(msg)
        if summary:
            with open(summary, "a", encoding="utf-8") as f:
                f.write("### 上げる前の関門: 止めました\n```\n" + msg + "\n```\n")
        return 1
    print("使い方: tested_gate.py mac-run <sha> | tested_gate.py gate <sha> <木>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
