# Cursor だけで TestFlight / Mac 確認まで完結する

owner:「iOS版でテストフライトなどもcursorだけで完結させたい」（2026-10-24）

## 結論

**Mac も GitHub の「Run workflow」画面も要らない。** Cursor の会話で
`/release`・`/mac-check` と言えば、Agent が Mac の CI を起こして結果を待つ。

実機での最終確認だけは、owner の iPhone（TestFlight アプリ）が要る。

## なぜこの形か

| 起動の口 | Cursor の連携トークン | 備考 |
|---|---|---|
| `workflow_dispatch`（Actions 画面・旧スキル） | **403** | 使えない |
| `repository_dispatch`（`Tools/cursor-dispatch-mac.sh`） | **通る** | 推奨 |
| 手元の Xcode Archive | — | 版のタグが付かないので使わない |

ビルド本体はこれまでどおり **公開リポの GitHub Actions macOS**（無料枠）。
Codemagic や自前 Mac への切り替えは不要。費用は増えない。

## 流れ（Agent 側）

1. 直し・機能を PR → マージ（Linux の `/verify`、必要なら `/mac-check`）
2. TestFlight に出すときは **owner に一言**（CLAUDE.md）
3. `bash Tools/cursor-dispatch-mac.sh testflight main`
4. `bash Tools/wait-mac-run.sh --run-id <run id>`
5. `testflight/<版>` のタグを確かめて報告

詳しい操作は `docs/GITHUB_ACTIONS.md` の「手順4」と
`.claude/skills/release/SKILL.md`・`mac-check/SKILL.md`。

## 確かめていないこと

- この文書を書いた時点では、main に `repository_dispatch` が入る前のため、
  本番 Secrets 付きの通し一発はまだ流していない（マージ後に `check … --screens none`
  で煙を見る）
