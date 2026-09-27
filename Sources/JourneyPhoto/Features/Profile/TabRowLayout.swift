import SwiftUI

/// 札を横に並べる（板 05c のタブ: `flex-grow: 1`）。**それぞれ中身の幅を取り、
/// 余りを均等に足す。**
///
/// 等分（`frame(maxWidth: .infinity)` を並べた HStack）にしない。等分だと
/// 「合わせて入るか」（`ViewThatFits` が見る理想の幅の和）と実際の幅が食い違い、
/// 合計は入るのに「行きたい場所」だけが 1/4 の枠に収まらずに切れた
struct TabRowLayout: Layout {

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let ideal = sizes.reduce(0) { $0 + $1.width }
        let height = sizes.map(\.height).max() ?? 0
        return CGSize(width: proposal.width ?? ideal, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        var x = bounds.minX
        for (subview, width) in zip(subviews, Self.widths(ideals: ideals, available: bounds.width)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY),
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }

    /// 各札の幅。入るなら中身の幅＋余りの等分。入らなければ中身の幅の比で縮める
    /// （長い名前ほど広く残す）
    static func widths(ideals: [CGFloat], available: CGFloat) -> [CGFloat] {
        guard !ideals.isEmpty else { return [] }
        let total = ideals.reduce(0, +)
        if total <= available {
            let extra = (available - total) / CGFloat(ideals.count)
            return ideals.map { $0 + extra }
        }
        guard total > 0 else { return ideals.map { _ in available / CGFloat(ideals.count) } }
        return ideals.map { $0 * available / total }
    }
}
