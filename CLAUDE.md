# journey.photo iOS — Claude 向けメモ

日本語で答える。推奨を1つ先に言う。確かめていないことは「確かめていない」と書く。

## リリースのたびに版を上げる（2026-09-26 owner のルール）

**TestFlight・App Store に出すたびに、表に出る版（`MARKETING_VERSION`）を必ず上げる。**
同じ版のまま出さない——どのビルドに何が入っているか、owner が TestFlight の一覧で
見分けられなくなる。

- **出すのは GitHub Actions の `ios-testflight.yml`（`workflow_dispatch`）から。**
  この経路なら上げるのは自動:
  - 表に出る版の最後の数字が毎回 +1（1.0.0 → 1.0.1 → 1.0.2 …）。
    決めるのは `Tools/next-marketing-version.sh`、出した版は
    `testflight/<版>` のタグで覚える（上げるのに成功した回だけタグが付く）
  - ビルド番号（`CURRENT_PROJECT_VERSION`）は TestFlight の最新 +1
- **真ん中・先頭の数字（1.1.0・2.0.0）は人が決める。** 見た目や機能が大きく
  変わる版のときに `bash Tools/bump-build.sh 1.1.0` でコミットしてから流す。
  自動で上げない
- **手元の Xcode から Archive して出すときだけ**、`bash Tools/bump-build.sh <版>` で
  版とビルド番号を自分で上げる。この経路はタグが付かないので、次に Actions で
  出すときに同じ版を二度使わないよう、出した版を owner に伝える
- 詳しい手順は `docs/RELEASE.md`・`docs/TESTFLIGHT.md`

## 検査

`bash Tools/verify.sh`（構文・参照・Web 版との突き合わせ・設定）。この環境では
本物の Xcode でのコンパイルはできない——最初の確認は TestFlight のワークフローの
テスト段になる。`check-config.py` の APNs の NG 2件は隣の photo-gallery 側の設定との
突き合わせで、前から出ている。
