#!/usr/bin/env bash
#
# テストが撮った画面の絵を `.xcresult` から取り出し、`screenshots` の枝に置く。
#
# **成果物（artifact）では受け取れない。** GitHub の保管先は Azure の blob で、
# 開発環境の外向き通信がそこを通さない（実測で `connect_rejected`）。
# **git は通る**ので、絵だけを持つ枝に力押しで置く——毎回まるごと
# 置き換えるので履歴は太らない。
#
# **落とさない。** 絵は「見る」ためのもの。取り出せなかったからといって
# ビルドを赤くすると、本来の見張り（テストの結果）が読めなくなる。
#
#     bash Tools/export-screenshots.sh build/ios/test/Test.xcresult
set -uo pipefail

XCRESULT="${1:-build/ios/test/Test.xcresult}"
SRC=/tmp/shots
OUT=/tmp/shots-out

if [ ! -d "$XCRESULT" ]; then
    echo "::warning::$XCRESULT がありません（テストが走らなかった？）"
    exit 0
fi

rm -rf "$SRC" "$OUT"
mkdir -p "$SRC" "$OUT"

if ! xcrun xcresulttool export attachments --path "$XCRESULT" --output-path "$SRC"; then
    echo "::warning::添付を取り出せませんでした（xcresulttool の版違い？）"
    exit 0
fi

# 取り出したファイル名は機械向け。manifest から人が読める名前に戻す
python3 - "$SRC" "$OUT" <<'PY'
import json, pathlib, shutil, sys

src, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
manifest = src / "manifest.json"
if not manifest.exists():
    print("::warning::manifest.json がありません")
    raise SystemExit(0)

for test in json.loads(manifest.read_text()):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName") or a.get("exportedFileName")
        f = src / a["exportedFileName"]
        if f.exists():
            shutil.copy(f, out / f"{name}.png")
PY

count=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" = "0" ]; then
    echo "::warning::絵が1枚も取れませんでした"
    exit 0
fi

# **軽くする。** 素の絵は1枚3MB近い。見るだけなので幅700の JPEG にする
for f in "$OUT"/*.png; do
    sips -Z 700 -s format jpeg -s formatOptions 60 "$f" --out "${f%.png}.jpg" >/dev/null 2>&1 \
        && rm -f "$f"
done

# 🔴 **撮れなかった画面を、ここで名指しにする。**
#
# 巡回は「出なければ撮らない」作りなので、画面が1つ撮れなくても**赤くならない**。
# run 62 は `20-写真の詳細`・`21-人のページ` が、run 65 は `30-旅の一冊`・
# `31-旅の足取り` が黙って消えた。どちらも**枚数を数えるまで気づかなかった**。
#
# `check-swift-refs.js` の 4.6f が見るのは「撮る**手**が消えていないか」
# （手元で読める）。ここが見るのは**手はあるのに絵が出なかった**回。
#
# **落とさない**（この台本の約束）。出すのは警告と、まとめへの1行。
python3 - "$OUT" <<'SHOTS'
import pathlib, sys

out = pathlib.Path(sys.argv[1])
# **条件つきの1枚**。送って動いたときだけ撮るので、無くても異常ではない
optional = {"15-マイページ（下）"}
wanted = [
    "01-同意画面", "10-ホーム", "11-探す", "13-マップ", "14-マイページ",
    "15-マイページ（下）", "20-写真の詳細", "21-人のページ",
    "30-旅の一冊", "31-旅の足取り", "40-投稿の2択", "41-ストーリー作成",
    "60-撮影スポット", "61-撮影スポット（下）",
]
got = [f.name for f in out.iterdir()]
missing = [w for w in wanted
           if w not in optional and not any(n.startswith(w) for n in got)]
skipped = [w for w in wanted
           if w in optional and not any(n.startswith(w) for n in got)]
if missing:
    print("::warning::撮れなかった画面: " + " / ".join(missing))
line = "撮れなかった画面: " + (" / ".join(missing) if missing else "なし")
if skipped:
    line += "（条件つきで撮らなかった: " + " / ".join(skipped) + "）"
pathlib.Path("/tmp/shots-report.md").write_text(line + "\n")
SHOTS

cd "$OUT"
{
    echo "# 画面の絵（$(date -u +%Y-%m-%dT%H:%MZ)）"
    echo
    echo "- コミット: ${GITHUB_SHA:-?}"
    echo "- 実行: ${GITHUB_RUN_NUMBER:-?}"
    echo
    echo "**この枝は毎回まるごと置き換わる。** 手で何かを足さないこと。"
    echo
    cat /tmp/shots-report.md 2>/dev/null || true
} > README.md

git init -q
git checkout -qb screenshots
git add -A
git -c user.email=actions@github.com -c user.name="GitHub Actions" \
    commit -qm "run ${GITHUB_RUN_NUMBER:-?} / ${GITHUB_SHA:-?} の画面"
git push -q -f \
    "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
    screenshots

echo "画面の絵 $count 枚を screenshots の枝に置きました"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && \
    {
        echo "### 画面の絵 $count 枚を \`screenshots\` の枝に置きました"
        cat /tmp/shots-report.md 2>/dev/null || true
    } >> "$GITHUB_STEP_SUMMARY"
exit 0
