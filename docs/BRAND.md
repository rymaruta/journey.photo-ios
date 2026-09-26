# ブランドの表記（サイトに揃える）

**出どころ**: `photo-gallery` の **main（本番）** と develop（2026-09-24 時点）。
サイトの見出しは `app/layout.tsx`、色は `app/globals.css` の `@theme`、
アイコンは `scripts/generate-icons.mjs`。**変わりうるので、揃え直すときは
そちらを読むこと**（ここは写し）。

---

## 1. ワードマーク

### サイトでの書き方（実物）

```html
<p class="font-serif text-[22px] font-bold tracking-tight text-white">
  <a class="inline-flex items-center gap-2">
    <img src="/logo-aperture.png" class="w-7 h-7" alt="" aria-hidden="true">
    <span>Journey Photo</span>
  </a>
</p>
```

| 項目 | サイトの値 | iOS（SwiftUI）で同じにするなら |
|---|---|---|
| 文字 | **`Journey Photo`**（半角スペース1つ・**ドット無し**） | `Text("Journey Photo")` |
| 書体 | `font-serif` ＝ Tailwind 4 の既定 `ui-serif, Georgia, …`。**iPhone の Safari では New York** | `.font(.system(size: 22, weight: .bold, design: .serif))`（＝New York） |
| 太さ | `font-bold`（700） | `.bold` |
| 字間 | `tracking-tight` ＝ **-0.025em**（22px なら -0.55px） | `.tracking(-0.55)` |
| 色 | **白1色**（`text-white`）。**「Photo」だけ色を変えていない** | `.foregroundStyle(.white)` |
| 大きさ | 22px。幅 360px 未満の端末だけ 20px、768px 以上で 26px | 22pt（アプリは電話の幅だけなので 22 固定でよい） |
| マーク | 白いアパーチャ 28px（768px 以上で 32px）、文字との間 8px | 余白なしの絵を 18pt（サイトの 28px の枠の中の絵と同じ大きさ）・`spacing: 8`・大文字の高さの真ん中に揃える |
| 読み上げ | マークは装飾（`aria-hidden`・空の `alt`）。読むのは文字だけ | 全体で1つの名前 `"Journey Photo"` |
| 下地 | ヘッダーは紺 `#0b1420`（`--color-bar`）の 70%＋ぼかし | アプリの `WebTheme.background` は黒。見出しの白文字はどちらでも読める |

**1つ注意**: `ui-serif` は**Apple の端末でだけ** New York になる。Windows や Android
では Georgia などに落ちる。**iPhone のサイトとアプリは同じ字形になる**が、PC で
見たサイトとは少し違う——それはサイト側の仕様。

### 🔴 「Journey.Photo」「.Photo がオレンジ」はサイトには無い

モック（デザイン案）に出てくる表記で、**サイトのコードには1か所も無い**
（main・develop とも `Journey.Photo` の検索は0件）。

| | 文字 | 書体 | 色 |
|---|---|---|---|
| **サイト（本番）** | Journey Photo | serif（iPhone では New York）Bold | 白1色 |
| アプリ（いま） | Journey Photo | システム（San Francisco）Semibold / Bold | 「Photo」だけ青 |
| モック | Journey.Photo | 明朝体 | 「.Photo」がオレンジ |

**「サイトに揃える」なら表の1行目**。モックの形にしたいなら、**サイトも一緒に
変える**必要がある（アプリだけ変えると、また2つの顔になる）。それは owner の判断。

アプリの「Photo だけ青」もサイトには無い。揃えるなら白1色にする。

---

## 2. マーク（`BrandMark`）

- `Sources/JourneyPhoto/Assets.xcassets/BrandMark.imageset`（44 / 88 / 132px）
- 白いアパーチャ・**テンプレート画像**（`foregroundStyle` で色を決められる）
- **絵の部分だけを切り出してある**（余白 2%・絵の中心が画像の中心）。
  2026-09-26 まではサイトの `public/logo-aperture.png` と同じく元絵を丸ごと縮めた版で、
  周りに約17%の透明な余白があり、絵は中心より約1%上にあった。28pt の枠に入れると
  見える絵は約18pt・文字との間は約13pt になり、owner に「アイコンと文字の位置が
  ズレてる」と指摘された。**サイトの方は今も余白込みの版**（直すかは別の判断）

以前アプリの `AppLogo` が描いていた**青い角丸に山の記号**は、サイトが以前
使っていたマークで、サイトは「同じサイトが2つのマークを名乗っていた」として
アパーチャに揃えている（`app/layout.tsx` の記録）。

---

## 3. アプリアイコン（2026-09-24 にサイトへ揃えた）

- **黒地に白いアパーチャ・枠なし**。サイトの favicon / `icon-512.png` と同じ絵
- 1024px・**透明なし**（App Store の要件。`Tools/check-config.py` が見張る）
- サイトの `icon-512.png` と突き合わせて、明るさの差は**平均 0.08 / 255**

**なぜ揃えたか**:
- **owner がこの絵を選んでいる**——サイトのアイコンは一度「枠あり」で出して、
  「こんな感じのが載ると思ってた」で**枠なし**に直した（2026-09-20・
  `generate-icons.mjs` の記録）
- App Store・ホーム画面・検索結果の favicon で**別の顔を名乗らない**。サイトが
  マークを揃えた理由と同じ
- 夕日と山の絵は、サイトが捨てた「山」のマークと地続きだった

**戻すのは簡単**: 以前の絵は git の履歴にある（`Tools/make_app_icon.py` も履歴に）。
ただし**利用者の端末に届くのは次の TestFlight／審査の提出から**なので、それまでは
何も変わらない。

### 作り直し方

```bash
# photo-gallery で npm ci 済みであること（sharp を借りる）
NODE_PATH=../photo-gallery/node_modules node Tools/make-brand-assets.cjs
```

アイコンとマークを**同じ元絵**（`photo-gallery/scripts/icon-source/aperture.png`）から
一度に作る。**絵は描き直さない**——切り出しと縮小だけ。

### 残っていること（owner の判断）

**起動画面の背景（`LaunchBackground`）が紺のまま。** 夕日のアイコンの空と
「地続きの色」にしてあった（`#1a2a4e`、ダークで `#132038`）。アイコンが黒になった
ので、起動の一瞬だけ紺→黒と切り替わる。揃えるなら黒か、サイトの下地
`#050e17`（`--color-bg`）。**見た目の変更なので、ここでは触っていない。**
