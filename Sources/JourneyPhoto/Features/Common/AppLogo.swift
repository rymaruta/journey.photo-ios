import SwiftUI

/// 見出しのロゴ（モック1・2・3・5 の左上）。
///
/// **記号はサイトと同じアパーチャ（`BrandMark`）。** 以前は青い角丸に
/// 山の記号を描いていたが、それはサイトが以前使っていたマークで、サイトは
/// アパーチャに揃え直している（`photo-gallery/app/layout.tsx`）。
/// 素材は `template` なので、色は `foregroundStyle` で決まる——
/// ライト／ダークで2枚持たなくてよい。
///
/// **大きさは枠で決める（`resizable`）。** 記号の文字（SF Symbols）だと、
/// ナビゲーションバーの中では指定より大きく描かれ、角丸からはみ出した
/// （実機の絵・2026-09-25）。
///
/// **文字もサイトと同じ**（`docs/BRAND.md`）: `Journey Photo`（ドット無し）、
/// serif の Bold（iPhone では New York）、字間 -0.025em、白1色、22pt。
/// 間 8pt もサイトの値。マークは**見える絵で文字の大きさの約0.9倍**（`markRatio`・
/// 2026-11-25 owner「このロゴが小さい」で大きくした）。以前の「Photo だけ青」はサイトに無い。
struct AppLogo: View {

    /// 見出しのロゴ（22pt）と、ログイン画面の大きいロゴ（40pt・板 41）。ログイン画面は画面の大きさで
    /// 40・32・28 を使い分ける（`points`・`SignInLayout.Metrics.brand`・2026-11-25）
    enum Size: Equatable { case header, hero, points(Double) }

    var size: Size = .header

    /// 文字の大きさ（見出しはサイトと同じ 22pt 固定）
    nonisolated static func fontPoints(_ size: Size) -> Double {
        switch size {
        case .header: return 22
        case .hero: return 40
        case .points(let points): return points
        }
    }
    private var fontSize: Double { Self.fontPoints(size) }

    /// **絵の枠は文字の大きさの 0.94 倍（見出しも大きいロゴも同じ比）。** 絵は余白 2% で
    /// 切り出してあるので、見える絵は枠の約96%＝文字の大きさの約0.9倍
    /// （大文字の高さ 0.70 より上下に少しずつ出て、「J」「y」の上下の幅に近い）。
    ///
    /// 2026-11-25 owner「このロゴが小さい」（ログイン画面の画面写真に赤丸）。以前は枠が
    /// 見出し 19・大きいロゴ 29.5 で、比が 0.86 と 0.74 に割れていた——大きいロゴの方が
    /// 文字に比べて小さく、見える絵は大文字の高さ（28pt）と同じで字に負けて見えた。
    /// 2026-11-25 判断: 比を1つにそろえ、見える絵を字の大きさの約0.9倍にする
    /// （見出し 19 → 20.7、大きいロゴ 29.5 → 37.6）。絵の中心は大文字の真ん中のままなので、
    /// 上下は行の高さの中に収まり、ログイン画面の高さ（`SignInLayout`）は変わらない
    nonisolated static let markRatio = 0.94
    nonisolated static func markPoints(_ size: Size) -> Double { fontPoints(size) * markRatio }
    private var markSize: Double { Self.markPoints(size) }
    /// 絵と文字の間。見出しはサイトの `gap-2` = 8px、大きいロゴは板 41 の 12px。
    /// 以前は透明な余白のぶん、これより約5〜8pt 広く見えていた
    /// ほかの大きさは字の 0.3 倍（32 → 10、28 → 8）
    private var spacing: Double {
        switch size {
        case .header: return 8
        case .hero: return 12
        case .points(let points): return max(8, (points * 0.3).rounded())
        }
    }
    /// New York Bold の大文字の高さ（字の大きさに対する割合）。
    /// **文字が縮んだとき（minimumScaleFactor）は縮む前の大きさで計算する**ので、
    /// 絵は最大で見出し 1.5pt・大きいロゴ 3pt ほど上に寄る。縮むのは狭い端末で
    /// 文字が入り切らないときだけ（見積もり・実機で未確認）
    private static let capHeightRatio = 0.70
    /// 見出しのロゴの字を縮めてよい深さ（22pt → 最小 約15.4pt。本文の最小 12 より大きい）。
    /// 2026-11-25 判断: 右の当たりの間を 6pt ずつ空けた（`AppHeaderItems.buttonGap`）ので、375pt の iPhone で
    /// ロゴに残る幅が約151 から約133 に減った。0.8（約147）のままだと右の丸に重なるので 0.7（約132）にした。
    /// 縮むのは入り切らない狭い端末だけで、402pt 以上の見た目は変わらない（見積もり・実機で未確認）
    nonisolated static let headerMinimumScale: CGFloat = 0.7

    var body: some View {
        // 🔴 **絵の中心は大文字の高さの真ん中に揃える。** 行の箱の中心で揃えると
        // 下の余白（J や y の下がり）の分だけ絵が上下にずれて見える
        // （owner の指摘 2026-09-26「アイコンと文字の位置がズレてる」）
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            mark
                .alignmentGuide(.firstTextBaseline) { d in
                    d.height / 2 + fontSize * Self.capHeightRatio / 2
                }
            Text("Journey Photo")
                .font(size == .header ? JPFont.wordmark : .system(size: fontSize, weight: .bold, design: .serif))
                // 字間 -0.025em（サイトと同じ）
                .tracking(-fontSize * 0.025)
                .foregroundStyle(WebTheme.foreground)
                // 見出しの幅が足りない端末で2行に割れないように
                .lineLimit(1)
                // **狭い端末では少しだけ縮める。** ロゴは左寄せで、右にホームなら
                // 探す・お知らせ・メニュー（44pt×3）が並ぶ。375pt 幅だと左に使えるのは
                // 約190pt。縮めずに固定すると右の丸に重なる（見積もり・実機で未確認）
                .minimumScaleFactor(size == .header ? Self.headerMinimumScale : 0.6)
        }
        // **読み上げは1つの名前として。** 記号と2つの語がばらばらに
        // 読まれると、開くたびに3回喋る
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journey Photo")
    }

    /// **絵は余白なしで切り出してある**（`Tools/make-brand-assets.cjs`）。
    /// 以前は元絵を丸ごと縮めた版で、周りに約17%の透明な余白があり、
    /// 文字との間が指定の 8pt ではなく約13pt に見えていた
    private var mark: some View {
        Image("BrandMark")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: markSize, height: markSize)
            .foregroundStyle(WebTheme.foreground)
    }
}
