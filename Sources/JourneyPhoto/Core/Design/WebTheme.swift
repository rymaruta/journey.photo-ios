import SwiftUI

/// Web 版（journey-photo.com）と同じ見た目の決まりごと。
///
/// **出どころは `photo-gallery/app/globals.css` の design tokens。**
/// あちらは「dark fixed」と書いてあるとおり、明暗の切り替えを持たない
/// **黒地・白文字の固定**。アプリだけ白地＋橙だったので、同じサイトの
/// アプリに見えなかった。値は勝手に決めず、向こうの CSS から写す。
///
///     --color-background: #000000
///     --color-foreground: #ffffff
///     --fg:        rgba(255,255,255,0.95)
///     --muted:     rgba(255,255,255,0.82)
///     --muted-2:   rgba(255,255,255,0.72)
///     --outer-border: rgba(255,255,255,0.12)
///     --accent-bg: rgba(255,255,255,0.92)
///     --accent-text: #07090a
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
    /// 入力欄のプレースホルダ（`placeholder:text-white/35`）
    static let placeholder = Color.white.opacity(0.35)

    /// 境目。`--outer-border`（部品では `ring-white/10`〜`border-white/15`）
    static let border = Color.white.opacity(0.12)

    /// 押せるものの地。`--accent-bg` / `--accent-text`
    static let accentBackground = Color.white.opacity(0.92)
    static let accentText = Color(red: 0x07 / 255, green: 0x09 / 255, blue: 0x0a / 255)

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
