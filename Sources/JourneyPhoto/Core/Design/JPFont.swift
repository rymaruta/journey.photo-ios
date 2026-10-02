import SwiftUI

/// 書体。**見出しは明朝、本文はシステム、数字はシステムの等幅数字。**
///
/// | 役割 | 書体 | 同梱 |
/// |---|---|---|
/// | 見出し（写真の題・画面の題・名前） | Shippori Mincho B1 Bold | JIS 第1水準まで（2.9 MB・`Tools/make-display-font.py`） |
/// | 本文・ボタン・注記 | SF Pro ＋ ヒラギノ角ゴ（システム） | しない |
/// | 数字（撮影情報・距離・件数）・眉ラベル | SF Pro（システム）＋等幅の数字（`.monospacedDigit()`）。regular / medium、統計の大きい数字は semibold | しない（2026-10-02 に IBM Plex Mono から替えた） |
/// | ワードマーク | New York Bold 22・白1色（`docs/BRAND.md`） | しない |
/// | ストーリーの文字の「手書き風」 | Klee One SemiBold | JIS 第1水準まで（4.0 MB・同じスクリプト）。`TextOverlay.Face` だけが使う |
/// | ストーリーの文字の「マーカー」「丸文字」 | Yusei Magic・Hachi Maru Pop | JIS 第1水準まで（1.3 MB・1.8 MB・同じスクリプト）。`TextOverlay.Face` だけが使う |
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

    /// 見出し（明朝）。既定は画面の題の大きさ
    static func display(_ size: Double = 26, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(displayName, size: size, relativeTo: style)
    }

    /// 写真の題（詳細画面のいちばん大きい見出し・板 02 の 32px）
    static let photoTitle = display(32, relativeTo: .largeTitle)
    /// 画面の題・人の名前
    static let screenTitle = display(26, relativeTo: .title)
    /// カードの題（写真の上・大きい札）
    static let cardTitle = display(22, relativeTo: .title2)
    /// 格子・一覧の題。**明朝の下限**
    static let rowTitle = display(18, relativeTo: .title3)

    /// 数字。撮影情報・距離・件数。**SF Pro ＋ 等幅の数字**（桁がそろう・iOS の
    /// ヘルスケアや写真の数字と同じ素直な形）。名前は昔の等幅書体の名残で `mono` のまま
    /// （呼ぶ側 50 か所を触らないため）。
    ///
    /// **2026-10-02 判断: `Font.system(<文字の種類>, weight:)` に `.monospacedDigit()` を付ける。**
    /// `size` は「いちばん近い大きさの文字の種類」を選ぶのに使い（`numberStyle`）、
    /// 出る大きさはその種類の標準（大きさの設定が既定のとき 11/12/13/15/16/17/20/22/28/34pt）。
    /// 頼まれた大きさとは最大 2pt ずれるが、それを許して Dynamic Type への追従を取った。
    /// - `Font.system(size:weight:design:)` は文字サイズの設定に追従しないので使わない
    /// - `.custom` で SF を名前で引くのは非公開の名前に頼るので使わない
    /// - `UIFontMetrics` で拡大した `UIFont` から作る `Font` は作った時の大きさで止まり、
    ///   `static let` に置くと設定を変えても追従しない
    ///
    /// - Parameter style: 近さが同じ2つのどちらを取るか迷ったときの決め手（無ければ大きい方）
    static func mono(_ size: Double = 12, medium: Bool = false,
                     relativeTo style: Font.TextStyle = .caption) -> Font {
        number(size, weight: medium ? .medium : .regular, relativeTo: style)
    }

    static func number(_ size: Double, weight: Font.Weight,
                       relativeTo style: Font.TextStyle = .caption) -> Font {
        Font.system(numberStyle(size: size, relativeTo: style), weight: weight).monospacedDigit()
    }

    /// 文字の種類の標準の大きさ（大きさの設定が既定＝Large のとき。Apple の HIG の表）。
    /// `headline` は `body` と同じ 17pt で太さだけ違うので選ばない
    static let standardSizes: [(style: Font.TextStyle, size: Double)] = [
        (.caption2, 11), (.caption, 12), (.footnote, 13), (.subheadline, 15), (.callout, 16),
        (.body, 17), (.title3, 20), (.title2, 22), (.title, 28), (.largeTitle, 34),
    ]

    /// 頼まれた大きさにいちばん近い文字の種類。同じ近さなら `style`、それも無ければ大きい方
    static func numberStyle(size: Double, relativeTo style: Font.TextStyle) -> Font.TextStyle {
        var best = standardSizes[0]
        for candidate in standardSizes.dropFirst() {
            let d = abs(candidate.size - size), bestD = abs(best.size - size)
            if d < bestD || (d == bestD && best.style != style) {
                best = candidate
            }
        }
        return best.style
    }

    /// 統計の大きい数字（投稿・フォロワー・km）。**title3（20pt）の semibold**——白い大きい数字を
    /// SF らしく締める（2026-10-02 の owner の好み）
    static let statNumber = Font.system(.title3, weight: .semibold).monospacedDigit()

    /// ワードマーク「Journey Photo」。**サイトと同じ New York Bold 22・固定**
    /// （ロゴは文字サイズの設定で伸び縮みさせない。`docs/BRAND.md`）
    static let wordmark = Font.system(size: 22, weight: .bold, design: .serif)
}

extension View {

    /// 眉ラベル（`TODAY'S THEME`・`TRIP BOOK` の類）。SF Pro の medium・字間を空けた小さい大文字。
    /// 11pt（caption2）は本文系の最小 12pt の、眉ラベルだけの例外。
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
