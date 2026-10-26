# 実装後の見え方プレビュー

板（ia-v2）を実機に近い見た目で起こした HTML。写真は仮（Unsplash）。

**据え置き（板・実装に合わせる）:**

- 距離・か国・地域 = `TravelRecordView`（カード化しない）
- BGM = ひとことの下の1行
- 足元タブ = 浮きカプセル・選択は真鍮（`TabBarStyle`）
- 内タブ = 名前だけ・真鍮字＋真鍮下線（`ProfileTabBar`）。白下線やアイコン付きにしない

見た目を変える前に `DesignSystem.dc.html` と対象画面の板・上記の Swift を読む。

**進め方:** 親の `../PHASE.md`。反映前に確定スクショを owner へ。

```bash
cd docs/design/ios-artifact-ia-v2/device-preview
python3 -m http.server 8765
# ブラウザで http://127.0.0.1:8765/01-mypage.html など
```

| ファイル | 画面 |
|---|---|
| `01-mypage.html` | マイページ（投稿タブ） |
| `02-trips.html` | 旅の記録（先頭チップ） |
| `03-wanted.html` | 行きたい場所 |
| `04-postsheet.html` | 投稿シート |
| `05-menu.html` | メニュー |
