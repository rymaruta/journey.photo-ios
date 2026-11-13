import SwiftUI

/// **UI テストの事実取りだけの見えない要素**（`PreviewSession.layoutProbe`・`-JPPreviewLayoutProbe YES`・Debug のみ）。
///
/// 字が切れたか・押せる範囲が重なるか・状態バーの下にあるかは、UI テストの画面の木から決められない
/// （`Text` の切れは木に出ない・当たりの範囲は frame と違う・安全な範囲の上端は木に無い）。
/// 推定で直さないために、寸法を値に出して UI テストが読む（2026-11-13 デザインの点検の確かめ役の指摘）。
/// Release では何も出ない
struct LayoutProbe: View {
    let identifier: String
    let value: String

    var body: some View {
        if PreviewSession.layoutProbe {
            Text(" ")
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityIdentifier(identifier)
                .accessibilityValue(value)
        }
    }
}

/// 行動の札（`SpotDetailParts.actionLabel`・並びは `ActionTilesLayout`）に、いちばん長い名前が切れずに入るか。
///
/// 値は `need=<名前の要る幅> column=<札1つの幅> minScale=<縮める下限> layout=<row|stack> fits=<yes|no>`。
/// `need` は今の字の大きさで1行に組んだ幅（縮める前）。`column` は1段に並べるなら等分した幅（すき間 `JPSpace.xs` を引く）、
/// 縦に積むなら並びの幅（`ActionTilesLayout.fitsInOneRow` と同じ決め方）。`fits` は `need × minScale ≤ column`
struct ActionRowFitProbe: View {
    let identifier: String
    let titles: [String]

    @State private var rowWidth: CGFloat = 0
    @State private var need: CGFloat = 0

    var body: some View {
        if PreviewSession.layoutProbe {
            GeometryReader { g in
                Color.clear
                    .onAppear { rowWidth = g.size.width }
                    .onChange(of: g.size.width) { _, width in rowWidth = width }
            }
            .background(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(titles, id: \.self) { title in
                        Text(title)
                            .font(SpotDetailParts.actionTitleFont)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .fixedSize()
                .hidden()
                .background {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { need = g.size.width }
                            .onChange(of: g.size.width) { _, width in need = width }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                LayoutProbe(identifier: identifier,
                            value: Self.describe(need: need, rowWidth: rowWidth, count: titles.count))
            }
            .allowsHitTesting(false)
        }
    }

    /// 1段に並べたときの札1つの幅（並びの幅から、すき間を引いて等分）
    nonisolated static func column(rowWidth: CGFloat, count: Int) -> CGFloat {
        ActionTilesLayout.column(available: rowWidth, count: count, spacing: JPSpace.xs)
    }

    static func describe(need: CGFloat, rowWidth: CGFloat, count: Int) -> String {
        let scale = ActionTilesLayout.minScale
        // 並びと同じ決め方（いちばん長い名前を下限まで縮めて、等分した幅に入れば1段）
        let row = ActionTilesLayout.fitsInOneRow(ideals: Array(repeating: need, count: max(count, 1)),
                                                 available: rowWidth, spacing: JPSpace.xs, minScale: scale)
        let placed = row ? column(rowWidth: rowWidth, count: count) : rowWidth
        let fits = need * scale <= placed + 0.5
        return String(format: "need=%.1f column=%.1f minScale=%.3f layout=%@ fits=%@",
                      need, placed, scale, row ? "row" : "stack", fits ? "yes" : "no")
    }
}
