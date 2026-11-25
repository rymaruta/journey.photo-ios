#!/usr/bin/env bash
#
# Linux に Swift ツールチェーンを入れる。**公式の配布元が使えない環境向け。**
#
# `download.swift.org` も GitHub のリリース資産も遮断されている環境があり
# （この作業環境がそうだった）、そこでも公式の Docker イメージ
# `swift:<版>-noble` の中身は取り出せる。イメージの層を Google の
# Docker Hub ミラーから落として展開するだけで、docker は要らない。
#
# 入るのは**Linux 用の Swift**。iOS SDK は入らないので、SwiftUI に触る
# ファイルはビルドできない。検証できるのは `Package.swift` に並べた
# 「画面を持たない層」だけ。
#
#     sudo bash Tools/install-swift-linux.sh           # Tools/toolchain.env の JP_SWIFT の版
#     sudo bash Tools/install-swift-linux.sh 6.4.2-noble
#     export PATH=/opt/swift/bin:$PATH
#
# 2026-11-25 判断: 版は Tools/toolchain.env の1か所で決める（Mac の Xcode と PR の検証の Linux の段とそろえる）。
# 入れ替えは短い時間で済ませる: 新しい版を `$DEST.new` に置いて動くのを確かめてから、名前の付け替え（mv）で入れ替える。
# ほかの担当が `swift` を使っている最中でも、使えない時間は付け替えの一瞬だけ。
# ディスクを食わないように、層は落としながら展開し（1GB の tar を置かない）、`swift build`・`swift test` に
# 要らない大きな物（デバッガ、エディタ用の言語サーバー）は入れない
set -euo pipefail

TAG="${1:-$(bash "$(dirname "$0")/toolchain.sh" swift)-noble}"
DEST="${DEST:-/opt/swift}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$DEST.new.partial"' EXIT

echo "== マニフェストを引く（${TAG}）"
# マニフェストも mirror.gcr.io から引く（2026-11-25: Docker Hub は回数の制限（1時間 100 回・同じ出口の全員で数える）で
# ときどき空の答えを返し、展開の前で止まった。ミラーは鍵が要らない）
REG="https://mirror.gcr.io/v2/library/swift"
curl -fsS --retry 3 \
    -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
    "$REG/manifests/$TAG" -o "$WORK/index.json"

DIGEST=$(python3 -c "
import json
d = json.load(open('$WORK/index.json'))
for m in d['manifests']:
    p = m.get('platform', {})
    if p.get('os') == 'linux' and p.get('architecture') == 'amd64':
        print(m['digest']); break
")
curl -fsS --retry 3 \
    -H "Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json" \
    "$REG/manifests/$DIGEST" -o "$WORK/manifest.json"

echo "== 層を落としながら展開する（およそ 1GB）"
# **blob は mirror.gcr.io から取る。** Docker Hub は blob を
# production.cloudfront.docker.com へ逃がすが、そちらは塞がれていることがある
COUNT=$(python3 -c "import json;print(len(json.load(open('$WORK/manifest.json'))['layers']))") || {
    echo "マニフェストが読めません:"; head -c 400 "$WORK/manifest.json"; echo; exit 1; }
rm -rf "$DEST.new.partial"
mkdir -p "$DEST.new.partial"
for i in $(seq 0 $((COUNT - 1))); do
    D=$(python3 -c "import json;print(json.load(open('$WORK/manifest.json'))['layers'][$i]['digest'])")
    echo "   層 $i"
    # /usr の下だけ。デバッガ（lldb）と言語サーバー（sourcekit-lsp・clangd）は入れない（約 700MB）
    curl -fsS -L --retry 3 "$REG/blobs/$D" --max-time 900 \
        | tar -xz -C "$DEST.new.partial" --wildcards \
            --exclude='usr/bin/lldb*' --exclude='usr/lib/liblldb*' \
            --exclude='usr/bin/sourcekit-lsp' --exclude='usr/lib/libsourcekitdInProc*' \
            --exclude='usr/bin/clangd' 'usr/*' 2>/dev/null || true
done

# **`usr/` の形のまま置き、`bin` は `usr/bin` への近道にする**（2026-11-25・Swift 6.4.2）。6.4 の `swift build` の
# 既定の作り方（swiftbuild）は、道具を `<根>/usr/bin` の形で探す。`usr` を外して置くと swiftc が見つからず
#「/作業の場所/swiftc is not an executable file」で落ちた。PATH は今までどおり `$DEST/bin` でよい
ln -s usr/bin "$DEST.new.partial/bin"
"$DEST.new.partial/bin/swift" --version
echo "== $DEST を入れ替える"
rm -rf "$DEST.old"
mv "$DEST.new.partial" "$DEST.new"
if [ -d "$DEST" ]; then mv "$DEST" "$DEST.old"; fi
mv "$DEST.new" "$DEST"
rm -rf "$DEST.old"
"$DEST/bin/swift" --version
echo
echo "PATH に足してください: export PATH=$DEST/bin:\$PATH"
