// 本物の SwiftUI で大きさを測るので iOS（Mac の模擬機）だけ。Linux の模型（Shims）には UIHostingController が無い
#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import JourneyPhoto

/// **行動の札（行きたい・旅行プランに入れる・経路）に名前が切れずに入るかを測る**（2026-11-13 確かめ役の指摘）。
///
/// 写真の詳細「次の旅へ」と観光スポットの頁は、同じ札（`SpotDetailParts.actionLabel`）を同じ幅に割って1段に並べる。
/// 字の大きさの設定ごとに「いちばん長い名前の要る幅（縮める前）」と「札1つの幅」を出す（`measured actionRow` の行）。
/// あわせて、前の写真の詳細の並び（横の札・`ViewThatFits` で2段へ組み替え）が、なぜ2段に替わらなかったかを、
/// 前の形をここで組み直して測る（`measured oldTripRow` の行）。並びの幅は 390 と 440 の画面から左右 16 を引いた幅
@MainActor
final class ActionRowFitMeasureTests: XCTestCase {

    private static let sizes: [DynamicTypeSize] = [.large, .xLarge, .xxLarge, .xxxLarge, .accessibility1, .accessibility3]
    private static let rowWidths: [CGFloat] = [358, 408]
    private static let titles = ["行きたい", "旅行プランに入れる", "経路"]

    private func fit<V: View>(_ view: V, width: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    /// 今の札: 名前の要る幅と札1つの幅
    func testMeasureActionRow() {
        for size in Self.sizes {
            let need = Self.titles.map { title in
                fit(Text(title).font(SpotDetailParts.actionTitleFont).lineLimit(1).fixedSize()
                        .environment(\.dynamicTypeSize, size)).width
            }.max() ?? 0
            for row in Self.rowWidths {
                let column = ActionRowFitProbe.column(rowWidth: row, count: Self.titles.count)
                let scale = WebTheme.minimumScale(forTextSize: JPTypeScale.footnote)
                print(String(format: "measured actionRow size=%@ row=%.0f need=%.1f column=%.1f minScale=%.3f fits=%@",
                             "\(size)", row, need, column, scale, need * scale <= column + 0.5 ? "yes" : "no"))
            }
            XCTAssertGreaterThan(need, 0)
        }
    }

    // MARK: - 前の写真の詳細の並び（2026-11-13 の直しの前・`PhotoTripSection` の `chip`）

    private func oldChip(_ icon: String, _ title: String) -> some View {
        HStack(spacing: JPSpace.xs) {
            Image(systemName: icon).font(.subheadline.weight(.medium))
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, JPSpace.m)
        .frame(maxWidth: .infinity, minHeight: JPHeight.field)
    }

    private var oldChips: [(String, String)] {
        [("flag", "行きたい"), ("calendar.badge.plus", "旅行プランに入れる"),
         ("arrow.triangle.turn.up.right.diamond", "経路")]
    }

    /// 前の並び: 札それぞれの理想の幅と合計、`ViewThatFits` が選んだ形（高さ 48 なら1段・それより高ければ2段）
    func testMeasureOldTripRowViewThatFits() {
        let chips = oldChips
        for size in Self.sizes {
            let ideals = chips.map { fit(oldChip($0.0, $0.1).fixedSize().environment(\.dynamicTypeSize, size)).width }
            let sum = ideals.reduce(0, +) + JPSpace.xs * CGFloat(chips.count - 1)
            for row in Self.rowWidths {
                let picked = fit(ViewThatFits(in: .horizontal) {
                    HStack(spacing: JPSpace.xs) {
                        oldChip(chips[0].0, chips[0].1)
                        oldChip(chips[1].0, chips[1].1)
                        oldChip(chips[2].0, chips[2].1)
                    }
                    VStack(spacing: JPSpace.xs) {
                        HStack(spacing: JPSpace.xs) {
                            oldChip(chips[0].0, chips[0].1)
                            oldChip(chips[1].0, chips[1].1)
                        }
                        oldChip(chips[2].0, chips[2].1)
                    }
                }.environment(\.dynamicTypeSize, size), width: row)
                let oneRow = fit(HStack(spacing: JPSpace.xs) {
                    oldChip(chips[0].0, chips[0].1)
                    oldChip(chips[1].0, chips[1].1)
                    oldChip(chips[2].0, chips[2].1)
                }.environment(\.dynamicTypeSize, size), width: row)
                print(String(format: "measured oldTripRow size=%@ row=%.0f ideals=%@ idealSum=%.1f pickedHeight=%.1f oneRowHeight=%.1f picked=%@",
                             "\(size)", row, ideals.map { String(format: "%.1f", $0) }.joined(separator: "/"),
                             sum, picked.height, oneRow.height, abs(picked.height - oneRow.height) < 0.5 ? "oneRow" : "twoRows"))
            }
        }
    }
}
#endif
