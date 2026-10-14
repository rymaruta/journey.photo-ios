import SwiftUI

/// 画面の見た目の決まりごと。
///
/// **出どころはデザインシステム「黒塗りの真鍮」（2026-09-25）。** 値そのものは
/// `BrandPalette`（比をテストで見張っている）。ここはそれを `Color` にして
/// 部品に配る場所。
///
/// 以前は `photo-gallery/app/globals.css` の黒地・白の透過を写していたが、
/// サイトはその後 紺＋青（`#050e17` / `#2080f6`）に変わり、アプリと割れていた。
/// 0から考え直して**黒＋白＋真鍮**に決めた（サイトも同じ値に揃える予定）。
///
/// **規則: 真鍮は合図と手がかり、写真の上には白しか置かない。**
/// owner の好み（2026-09-29）で、選んだ印・いいね・選んでいるタブなど
/// 「デザインの箇所」は白より真鍮に寄せる（黒い地の上だけ・詳しくは CLAUDE.md）
///
/// **端末の明暗設定には従わない。** Web が従っていないので、ここで
/// 従うと「iPhone をライトにしている人だけ別アプリ」になる。
@MainActor
enum WebTheme {

    static let background = Color.black
    static let foreground = Color.white

    /// 本文。`--fg`
    static let text = Color.white.opacity(0.95)
    /// 副次の文字。`--muted`
    static let muted = Color.white.opacity(0.82)
    /// さらに弱い文字（説明・日付）。`--muted-2` と、実際の部品で多い `white/60`。
    ///
    /// 🔴 **白の透過のまま持つ。** 写真の上（ストーリー・写真の詳細）でも使っていて、不透明の灰にすると
    /// 明るい写真の上で沈む（2026-10-14 のレビュー: 白地＋黒 65% の影で 4.56 → 3.53）。
    /// 黒地の上の v2 の灰は `text2`・`text3`
    static let muted2 = Color.white.opacity(0.72)
    static let faint = Color.white.opacity(0.6)
    /// **v2 の text-2（#B8B8B8・黒の上 10.6:1）。黒地・札の上だけ**——写真の上は `muted2`（透過）
    static let text2 = rgb(BrandPalette.text2)
    /// **v2 の text-3（#9A9A9A・黒の上 7.46:1）。黒地・札の上だけ**——写真の上は `faint`（透過）
    static let text3 = rgb(BrandPalette.text3)
    /// 入力欄のプレースホルダ。**35% → 50%**（35% は入力欄の上で 3.0 しか無く、
    /// 文字の線 4.5 に届かなかった）
    static let placeholder = Color.white.opacity(0.5)

    /// 境目（装飾の髪線）。**部品の縁には使わない**（黒の上で 1.27）
    static let border = Color.white.opacity(0.12)
    /// **v2 の区切り線（白 8%）。** 札の縁・札の中の行の間・画面の節の間
    static let hairline = Color.white.opacity(0.08)
    /// **v2 の線（白 14%）。** 線のボタン（副ボタン・「もう一度」）の縁だけ。
    /// 押せることは字で分かるので、縁は 3:1 を要しない（入力欄の縁は `outline`）
    static let line = Color.white.opacity(0.14)

    /// **v2 の札の面（surface-1・#0E0E0F）。** `JPCard` の地。
    /// ⚠️ いまは同じ画面に白 7% の `surface` の札も残っている（マイページ・探す・投稿）。
    /// 画面ごとの作り替え（v2 の次の段）でこちらへそろえる
    static let card = rgb(BrandPalette.surface)
    /// **v2 のシート・入力欄の地（surface-2・#161617）。** 通報のシートの地。
    /// この上の札は `card` だと沈んで見えるので、`JPCard(fill: surface)` で浮かせる
    static let sheet = rgb(BrandPalette.surface2)
    /// 入力欄・枠線ボタンの縁。部品の縁は 3:1 が要る（黒 3.66・入力欄 3.03）
    static let outline = rgb(BrandPalette.outline)

    // MARK: 真鍮（合図と手がかり）

    /// 文字・アイコン・未読の点・ストーリーの輪・リンク・眉ラベル。**黒か面の上だけ**
    static let accent = rgb(BrandPalette.accent)
    static let accentStrong = rgb(BrandPalette.accentStrong)
    /// 写真の無い画面の主ボタン（ログイン・送信）。**上の字は墨**（`accentText`）
    static let accentFill = rgb(BrandPalette.accentFill)
    /// 白を載せる暗い真鍮。トグルの軌道・地図の印
    static let accentDeep = rgb(BrandPalette.accentDeep)
    /// 案内の帯（今日のテーマ）。選択状態は担わない
    static let accentSoft = rgb(BrandPalette.accentSoft)
    /// 輪・メダル・Pro の印の金属の光（v2 の brass-hi → 真鍮 → brass-lo）。**字には使わない**
    static let accentMetal = [rgb(BrandPalette.accentHighlight), accent, rgb(BrandPalette.accentShadow)]

    // MARK: 意味の色

    /// 削除・通報・エラーの文字とアイコン（`.red` の代わり）
    static let danger = rgb(BrandPalette.danger)
    /// 「アカウントを削除」の確定ボタンだけ（白文字）
    static let dangerFill = rgb(BrandPalette.dangerFill)
    static let success = rgb(BrandPalette.success)
    /// 地図の現在地だけ
    static let location = rgb(BrandPalette.location)

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    /// **写真を持つ画面の主ボタンと選択中のチップ**の地（白 94%）と、その上の墨。
    /// 名前は歴史的なもの——ここは真鍮ではなく白。1画面に白の塗りは1つ。
    /// **v2 で 92% → 94%**（黒に重ねた値が `BrandPalette.primary`・比はそちらで見張る）
    nonisolated static let primaryFillOpacity = 0.94
    static let accentBackground = Color.white.opacity(primaryFillOpacity)
    static let accentText = rgb(BrandPalette.ink)

    /// 選ばれていないチップ・入力欄の地（`bg-white/[0.07]`・`bg-white/[0.06]`）。
    /// ⚠️ 札の地にも使っている所がある（`JPCard` は v2 の `card`）。次の段でそろえる
    static let surface = Color.white.opacity(0.07)
    /// 少し浮かせる面（ピル・カード。`bg-black/30` ＋ `ring-white/10`）
    static let raised = Color.white.opacity(0.10)

    /// 写真の格子の隙間。Web は `gap-1`（4px）で、角も丸めない
    static let gridSpacing: CGFloat = 4
    /// スマホの列数。Web は `grid-cols-2`（`sm:` 以上で3〜4列）
    static let gridColumns = 2

    /// **押せるものは 44pt 以上。**
    ///
    /// Apple のガイドライン（HIG）が指で押す最小として挙げている寸法。
    /// Web の寸法をそのまま写していたので、チップは上下 6pt ＋ 13pt の字＝
    /// **約26pt しかなく、指では狙いにくかった**（owner の指摘。実測）。
    /// マウスの Web と違い、指は当たりが太い。
    ///
    /// **見た目は太らせない。** 当たり判定だけを広げるので、並びの詰まりは
    /// そのまま（`contentShape` で余白まで押せるようにする）。
    nonisolated static let minTapTarget: CGFloat = 44

    /// **上のバー（ツールバー）のアイコンの大きさ（17pt・regular）**（2026-10-14）。
    ///
    /// 経緯: 既定の 17pt では黒地で沈む（owner）→ 22pt semibold にした →
    /// iOS 26 のガラスの帯に入れると「デカすぎる」（owner・実機）→ 19pt regular・箱 28 にした →
    /// まだ「アイコン自体も含めてデカイ」（owner・Mac run 433 の絵）→ **17pt regular・箱 24**
    /// （システムの標準の大きさ。owner の好みが板の約 19px より優先）。太字には戻さない
    nonisolated static let toolbarIconSize: CGFloat = 17
    /// アイコンの箱の**幅**（並びの寸法）。17pt の絵（約 19〜21pt）が収まる最小。
    /// **高さは `minTapTarget`（44）**（`webToolbarIcon` の注記・箱の外は押せなかった）
    nonisolated static let toolbarIconBox: CGFloat = 24
    /// お知らせの未読の点（8pt）を、箱の右上の角からずらす量。板の点は絵の右上の角に
    /// 中心が来て、線画の肩に少し掛かる（板 01: 44 の枠で top/right 10・絵 22）。
    /// 24 の箱では角そのものがほぼ絵の角なので、ほとんどずらさない
    nonisolated static let toolbarBadgeOffset: (x: CGFloat, y: CGFloat) = (1, -1)

    /// **本文系の字の最小（12pt）。** 11pt は眉ラベルだけ（CLAUDE.md・デザインの板）
    nonisolated static let minBodyText: CGFloat = 12

    /// `minimumScaleFactor` に渡す値。**縮めても `minBodyText` を割らず、0.8 より深く縮めない**。
    /// 12/字の大きさ だけにすると、字の大きさの設定で大きくしている人ほど深く縮んだ
    /// （xxxLarge の 19pt が 12pt まで）。字がもともと 12pt 以下なら縮めない（1）
    nonisolated static let deepestScale: CGFloat = 0.8

    nonisolated static func minimumScale(forTextSize size: CGFloat) -> CGFloat {
        guard size > minBodyText else { return 1 }
        return max(deepestScale, minBodyText / size)
    }
    /// 地図の右の操作（方位磁針・現在地・拡大縮小）の間隔。
    /// 8pt では丸いボタンどうしが接して見え、押し間違えやすかった
    static let mapControlSpacing: CGFloat = 12
}

/// 画面ぜんぶを黒地にする。
///
/// **`preferredColorScheme(.dark)` だけでは黒にならない。** `List` /
/// `Form` の地は「暗い灰（`systemGroupedBackground`）」で、Web の
/// 真っ黒とは別の色。地を消してから敷き直す。
///
/// （`ViewModifier` では書かない——`Shims/` の模型が持っておらず、
/// Linux での型検査が通らなくなる。素の `extension` で足りる）
extension View {

    func webScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(WebTheme.background)
            // **バーも黒に。** 既定の半透明は白っぽく浮き、黒地の上で
            // 帯だけ明るく見える。Web のヘッダーは `bg-black/60` に
            // 下辺 `border-white/10`
            .toolbarBackground(WebTheme.background, for: .navigationBar, .tabBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .tabBar)
    }


    /// バー（上のツールバー）の中のアイコン。
    ///
    /// **大きさの経緯**（`WebTheme.toolbarIconSize`）:
    /// 1. 既定の 17pt 相当では黒地で沈み、見つけにくい（owner の指摘。地図・「…」・歯車）
    /// 2. 22pt semibold ＋ 44pt の枠にした → iOS 26 のガラスの丸い帯に入れると
    ///    **帯が文字の行よりずっと高く、絵も太く大きい**（2026-10-14 owner「デカすぎる」）
    /// 3. 19pt regular・箱 28 にしても「アイコン自体も含めてデカイ」（owner）
    /// 4. いま: **17pt regular・箱 24**（システムの標準の大きさ）
    ///
    /// **帯が太っていた訳**: iOS 26 はバーの右の項目を、ラベルの寸法に**システムの余白を足して**
    /// ガラスの帯に入れる。こちらが `frame(minWidth: 44, minHeight: 44)` で並びの寸法そのものを
    /// 44 にしていたので、帯は「44 ＋ システムの余白」になり、標準の帯より太く・長くなっていた。
    ///
    /// **箱は幅 24・高さ 44**: 帯を長くするのは幅なので、幅だけを `toolbarIconBox`（24）に詰め、
    /// 高さは 44 のまま当たりにする（`contentShape`）。
    /// 🔴 **箱の外へ当たりを広げる作り（44 の余白で当たりを取り、負の余白で箱に戻す）は効かなかった**
    /// （Mac run 432: 絵の中心から 19pt 下を押してもお知らせが開かない。バーの項目は UIKit の枠の中しか
    /// 押せない）。当たりは並びの寸法の中にしか作れない
    func webToolbarIcon() -> some View {
        self
            .font(.system(size: WebTheme.toolbarIconSize, weight: .regular))
            .foregroundStyle(WebTheme.foreground)
            .frame(minWidth: WebTheme.toolbarIconBox, minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
    }

    /// 押せるものの当たり判定を 44pt 以上にする（見た目は変えない）。
    func webTappable() -> some View {
        self
            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
    }

    /// Web の丸いチップ。`bg-white/5`＋`ring-white/10`＋小さめの字。
    /// タグ・撮影地・カテゴリで同じ形を使っている。
    func webChip(prominent: Bool = false) -> some View {
        self
            .padding(.horizontal, prominent ? 10 : 12)
            .padding(.vertical, prominent ? 4 : 6)
            .background(prominent ? WebTheme.raised : Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    /// Web の「押せるもの」の形（白地・黒字・丸）。
    /// `FilterBar` の選択中チップ（`bg-white text-black font-medium`）と同じ。
    func webPrimaryButton() -> some View {
        self
            .font(.callout.weight(.medium))
            .foregroundStyle(WebTheme.accentText)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(WebTheme.accentBackground, in: Capsule())
    }
}
