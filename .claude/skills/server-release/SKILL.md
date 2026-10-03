---
name: server-release
description: photo-gallery（Web と API）の変更を staging → 本番に出す。develop には溜まった別の変更があるので、本番には出したい分だけを載せる。
---

# photo-gallery を出す

- `deploy-api.yml`: develop に push → **staging**、main に push → **本番**（api/・api-user/ を触ったとき）。
- `deploy.yml`: main に push → 本番の Web。
- develop には別の作業の変更が溜まっている。**develop をそのまま main に入れない。**

## 手順

1. 枝で作り、PR（base は develop）。別の担当に確かめさせる（`/review` の考え方で）。
2. develop にマージ → staging のデプロイを待つ → staging の API を `curl` で叩いて確かめる
   （staging の user API: `https://y9f8ajacc2.execute-api.ap-northeast-1.amazonaws.com`）。
3. 本番用の枝を main から切り、出したいコミットだけ `git cherry-pick -x`。
   - 手元の `origin/main` が古いことがある。`git fetch origin main:refs/remotes/origin/main` で更新してから。
   - テスト（最上位で `npx vitest run`・`npx tsc --noEmit`）を流してから push。
4. 本番用の PR（base は main）を作り、本文に「入るもの・入らないもの・確かめたこと」。
5. **本番へのマージは owner が押す**（こちらから押すと止められることがある）。押してもらったら、
   本番のデプロイを待ち、本番の API を叩いて確かめる
   （本番の user API: `https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com`）。

## AWS の保守作業（索引の作成など）

- Maintenance ワークフロー。**apply=false（試すだけ）はこちらで流してよい。apply=true は owner が押す。**
- ログは `mcp__github__get_job_logs` で読む。

## 本番の DB・新しい GSI・有料サービス

owner の明示の承認が要る。先に影響と費用を書いて確認を取る。
