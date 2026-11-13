import SwiftUI

/// 行動の札（`SpotDetailParts.actionLabel`）の並び。観光スポットの頁と写真の詳細「次の旅へ」で同じもの。
///
/// **名前が切れずに入るなら1段に同じ幅で並べ、入らなければ縦に積む**（板 06「アクセシビリティの大きさでは
/// 横に並べた札、ボタンを縦に積む」）。入るかは、札それぞれの理想の幅（名前を1行に組んだ幅）のいちばん大きいものを、
/// 部品の縮める下限（`minimumScaleFactor`）まで縮めて、等分した札1つの幅に入るかで決める。
///
/// 2026-11-13 判断（確かめ役の指摘・Mac run 1213 の数）: 1段に固定した並びでは、「旅行プランに入れる」の要る幅が
/// 札1つの幅を超えた——390 の画面は1段上の文字（xLarge）で 130.3 × 0.923 = 120.3 > 114.0、440 の画面は 2段上（xxLarge）
/// で 147.3 × 0.923 = 136.0 > 130.7、アクセシビリティの大きさ（AXL）では両方の画面で 278.0 に対し 130.7。
/// `ViewThatFits` は理想の幅の**合計**で選ぶので、同じ幅に割る並びとは食い違う（`TabRowLayout` の注記と同じ件）。
/// ここでは等分した幅で決める
struct ActionTilesLayout: Layout {

    var spacing: CGFloat = JPSpace.xs

    /// 縮める下限（`SpotDetailParts.actionLabel` の名前の `minimumScaleFactor` と同じ値）
    static var minScale: CGFloat { WebTheme.minimumScale(forTextSize: JPTypeScale.footnote) }

    /// 等分した札1つの幅
    nonisolated static func column(available: CGFloat, count: Int, spacing: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return (available - spacing * CGFloat(count - 1)) / CGFloat(count)
    }

    /// 1段に並べてよいか（いちばん長い名前を下限まで縮めて、等分した幅に入る）。誤差の 0.5 は許す
    nonisolated static func fitsInOneRow(ideals: [CGFloat], available: CGFloat, spacing: CGFloat,
                                         minScale: CGFloat) -> Bool {
        guard let widest = ideals.max() else { return true }
        return widest * minScale <= column(available: available, count: ideals.count, spacing: spacing) + 0.5
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        let available = proposal.width ?? (ideals.reduce(0, +) + spacing * CGFloat(max(0, ideals.count - 1)))
        if Self.fitsInOneRow(ideals: ideals, available: available, spacing: spacing, minScale: Self.minScale) {
            let column = Self.column(available: available, count: subviews.count, spacing: spacing)
            let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
            return CGSize(width: available, height: height)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: available, height: nil)).height }
        return CGSize(width: available, height: heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        if Self.fitsInOneRow(ideals: ideals, available: bounds.width, spacing: spacing, minScale: Self.minScale) {
            let column = Self.column(available: bounds.width, count: subviews.count, spacing: spacing)
            var x = bounds.minX
            for subview in subviews {
                subview.place(at: CGPoint(x: x, y: bounds.minY),
                              proposal: ProposedViewSize(width: column, height: bounds.height))
                x += column + spacing
            }
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }
}
