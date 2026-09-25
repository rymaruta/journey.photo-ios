import SwiftUI

/// 書体。**見出しは明朝、本文はシステム、数字は等幅。**
///
/// | 役割 | 書体 | 同梱 |
/// |---|---|---|
/// | 見出し（写真の題・画面の題・名前） | Shippori Mincho B1 Bold | JIS 第1水準まで（2.9 MB・`Tools/make-display-font.py`） |
/// | 本文・ボタン・注記 | SF Pro ＋ ヒラギノ角ゴ（システム） | しない |
/// | 数字（撮影情報・距離・件数）・眉ラベル | IBM Plex Mono 400 / 500 | 原本のまま（0.26 MB） |
/// | ワードマーク | New York Bold 22・白1色（`docs/BRAND.md`） | しない |
///
/// **どれも `relativeTo:` を付けて、文字サイズの設定（Dynamic Type）に追従させる。**
/// 固定の大きさにすると、大きい文字を選んでいる人にだけ見出しが小さく残る。
///
/// ⚠️ **削った明朝に無い字は、端末のゴシックで出る。** 第1水準の外
/// （髙・﨑・第2水準の地名）がそれに当たる。本番の39枚の題と撮影地では
/// 212字中「諧」の1字だけ（2026-09-25 に数えた）。明朝へ落とす
/// （`UIFontDescriptor.cascadeList`）には `UIFont` を経由する必要があり、
/// そうすると Dynamic Type への追従を画面ごとに自前で書くことになる。
/// **追従の方を取った。**
///
/// ⚠️ **明朝は 18pt 未満に使わない。** 黒地の上の細い横画は小さいと潰れる。
enum JPFont {

    /// 見出しの明朝。`Info.plist` の `UIAppFonts` に載っている名前（PostScript 名）
    static let displayName = "ShipporiMinchoB1-Bold"
    static let monoRegularName = "IBMPlexMono-Regular"
    static let monoMediumName = "IBMPlexMono-Medium"

    /// 見出し（明朝）。既定は画面の題の大きさ
    static func display(_ size: Double = 26, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(displayName, size: size, relativeTo: style)
    }

    /// 写真の題（詳細画面のいちばん大きい見出し）
    static let photoTitle = display(30, relativeTo: .largeTitle)
    /// 画面の題・人の名前
    static let screenTitle = display(26, relativeTo: .title)
    /// カードの題（写真の上・大きい札）
    static let cardTitle = display(22, relativeTo: .title2)
    /// 格子・一覧の題。**明朝の下限**
    static let rowTitle = display(18, relativeTo: .title3)

    /// 数字（等幅）。撮影情報・距離・件数
    static func mono(_ size: Double = 12, medium: Bool = false,
                     relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom(medium ? monoMediumName : monoRegularName, size: size, relativeTo: style)
    }

    /// 統計の大きい数字（投稿・フォロワー・km）
    static let statNumber = mono(18, medium: true, relativeTo: .title3)

    /// ワードマーク「Journey Photo」。**サイトと同じ New York Bold 22・固定**
    /// （ロゴは文字サイズの設定で伸び縮みさせない。`docs/BRAND.md`）
    static let wordmark = Font.system(size: 22, weight: .bold, design: .serif)
}

extension View {

    /// 眉ラベル（`TODAY'S THEME`・`TRIP BOOK` の類）。等幅・字間を空けた小さい大文字。
    ///
    /// **色は呼ぶ側が決める。** 黒地の上なら真鍮、**写真の上なら白**
    /// （真鍮は夕日の写真の上で 1.03 まで落ちる）。
    func jpEyebrow() -> some View {
        self
            .font(JPFont.mono(11, medium: true, relativeTo: .caption2))
            .tracking(1.5)
            .textCase(.uppercase)
    }
}
