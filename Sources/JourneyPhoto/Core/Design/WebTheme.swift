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
/// **規則は1行: 白＝位置と選択、真鍮＝合図と手がかり。
/// 写真の上には白しか置かない。**
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
    /// さらに弱い文字（説明・日付）。`--muted-2` と、実際の部品で多い `white/60`
    static let muted2 = Color.white.opacity(0.72)
    static let faint = Color.white.opacity(0.6)
    /// 入力欄のプレースホルダ。**35% → 50%**（35% は入力欄の上で 3.0 しか無く、
    /// 文字の線 4.5 に届かなかった）
    static let placeholder = Color.white.opacity(0.5)

    /// 境目（装飾の髪線）。**部品の縁には使わない**（黒の上で 1.27）
    static let border = Color.white.opacity(0.12)
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

    /// **写真を持つ画面の主ボタンと選択中のチップ**の地（白 92%）と、その上の墨。
    /// 名前は歴史的なもの——ここは真鍮ではなく白。1画面に白の塗りは1つ
    static let accentBackground = Color.white.opacity(0.92)
    static let accentText = rgb(BrandPalette.ink)

    /// 選ばれていないチップ・入力欄の地（`bg-white/[0.07]`・`bg-white/[0.06]`）
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
    static let minTapTarget: CGFloat = 44
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
    /// **ここは「当たり判定だけ広げる」では足りない。** owner の指摘は
    /// 地図・「…」・歯車のような**絵そのものが小さい**という話で、
    /// 押しやすさの前に**見つけにくい**。既定は 17pt 相当で、
    /// 黒地の上では特に沈む。
    ///
    /// 22pt の太めにして、当たりは 44pt。
    func webToolbarIcon() -> some View {
        self
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(WebTheme.foreground)
            .webTappable()
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
