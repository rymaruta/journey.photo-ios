#!/usr/bin/env bash
#
# Linux に Swift ツールチェーンを入れる。**公式の配布元が使えない環境向け。**
#
# `download.swift.org` も GitHub のリリース資産も遮断されている環境があり
# （この作業環境がそうだった）、そこでも公式の Docker イメージ
# `swift:6.0.3-noble` の中身は取り出せる。イメージの層を Google の
# Docker Hub ミラーから落として展開するだけで、docker は要らない。
#
# 入るのは**Linux 用の Swift**。iOS SDK は入らないので、SwiftUI に触る
# ファイルはビルドできない。検証できるのは `Package.swift` に並べた
# 「画面を持たない層」だけ。
#
#     sudo bash Tools/install-swift-linux.sh
#     export PATH=/opt/swift/bin:$PATH
set -euo pipefail

TAG="${1:-6.0.3-noble}"
DEST="${DEST:-/opt/swift}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== マニフェストを引く（${TAG}）"
TOKEN=$(curl -sS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/swift:pull" \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['token'])")
curl -sS -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
    "https://registry-1.docker.io/v2/library/swift/manifests/$TAG" -o "$WORK/index.json"

DIGEST=$(python3 -c "
import json
d = json.load(open('$WORK/index.json'))
for m in d['manifests']:
    p = m.get('platform', {})
    if p.get('os') == 'linux' and p.get('architecture') == 'amd64':
        print(m['digest']); break
")
curl -sS -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json" \
    "https://registry-1.docker.io/v2/library/swift/manifests/$DIGEST" -o "$WORK/manifest.json"

echo "== 層を落とす（およそ 1GB）"
# **blob は mirror.gcr.io から取る。** Docker Hub は blob を
# production.cloudfront.docker.com へ逃がすが、そちらは塞がれていることがある
COUNT=$(python3 -c "import json;print(len(json.load(open('$WORK/manifest.json'))['layers']))")
mkdir -p "$WORK/rootfs"
for i in $(seq 0 $((COUNT - 1))); do
    D=$(python3 -c "import json;print(json.load(open('$WORK/manifest.json'))['layers'][$i]['digest'])")
    echo "   層 $i"
    curl -sS -L "https://mirror.gcr.io/v2/library/swift/blobs/$D" -o "$WORK/layer.tar.gz" --max-time 900
    tar -xzf "$WORK/layer.tar.gz" -C "$WORK/rootfs" 2>/dev/null || true
done

echo "== $DEST へ置く"
mkdir -p "$DEST"
cp -a "$WORK/rootfs/usr/." "$DEST/"
"$DEST/bin/swift" --version
echo
echo "PATH に足してください: export PATH=$DEST/bin:\$PATH"
