---
name: verify
description: 手元（Linux）で iOS のビルド・テスト・検査を流す決まった手順。push の前に必ず使う。
---

# 手元の確かめ

```bash
export PATH=/opt/swift/bin:$PATH
swift build --build-tests && swift test --skip-build     # Linux の模型（Shims）向けの型検査とテスト
bash Tools/verify.sh                                     # 構文・参照・Web 版との突き合わせ・設定。NG は 0 が正しい
```

## verify.sh の前に

- `Tools/node_modules` が無ければ、既にある作業ツリーからコピーする（git の管理外）。
- Web 版との突き合わせは隣の photo-gallery を読む。**古い枝だと「サーバーに無い」と誤報する**。
  `PHOTO_GALLERY=<photo-gallery の最新 develop の作業ツリー>` を渡すか、
  `git -C ../photo-gallery checkout origin/develop` でそろえる。
  まだ develop に入っていない口をアプリが使うときは、その PR の枝の作業ツリーを渡す。

## 結果の読み方

- テストが固まったら（返ってこない）、Linux の URLSession の取り消しの不具合を疑う
  （`CancellableData.swift` の注記）。`timeout` を付けて流し、固まったら固まったと書く。
- 「不安定」で片づけない。テストを skip・無効化・削除しない。
- 直したら、**直しを戻すとテストが落ちる**ことを確かめる（テストが本当に守っているか）。

## 報告に書くこと

テストの件数・失敗数、verify の NG 数、確かめていないこと（本物の Xcode・実機は確かめられない）。
