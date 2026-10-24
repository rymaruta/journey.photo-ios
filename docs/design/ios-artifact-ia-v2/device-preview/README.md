# 実装後の見え方プレビュー

板（ia-v2）を実機に近い見た目で起こした HTML。写真は仮（Unsplash）。

**据え置き:** `01-mypage.html` の距離・か国・地域は現行 `TravelRecordView` と同じ並び（大きな数字＋説明）。カード化しない。

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
