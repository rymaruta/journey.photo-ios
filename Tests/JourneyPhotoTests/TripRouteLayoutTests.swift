import XCTest
@testable import JourneyPhoto

/// 旅の本のルート図の置き方（`TripRouteLayout`）
final class TripRouteLayoutTests: XCTestCase {

    /// 札の左右の端
    private func edges(_ label: TripRouteLayout.Label) -> (left: CGFloat, right: CGFloat) {
        (label.centerX - label.width / 2, label.centerX + label.width / 2)
    }

    /// 札の上下の端
    private func verticalEdges(_ label: TripRouteLayout.Label, labelHeight: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        (label.centerY - labelHeight / 2, label.centerY + labelHeight / 2)
    }

    /// 端の札も図の外へはみ出さない（iPhone SE の幅〜iPad の幅・点2〜4つ）
    func testLabelsStayInside() {
        for width in [280.0, 335.0, 350.0, 700.0] as [CGFloat] {
            for count in 1...4 {
                let layout = TripRouteLayout.layout(count: count, width: width, labelHeight: 32)
                for label in layout.labels {
                    let edge = edges(label)
                    XCTAssertGreaterThanOrEqual(edge.left, TripRouteLayout.margin - 0.001, "w=\(width) n=\(count)")
                    XCTAssertLessThanOrEqual(edge.right, width - TripRouteLayout.margin + 0.001, "w=\(width) n=\(count)")
                }
            }
        }
    }

    /// 同じ側の札どうしは重ならない
    func testSameSideLabelsDoNotOverlap() {
        for width in [280.0, 335.0, 350.0, 700.0] as [CGFloat] {
            for count in 2...4 {
                let labels = TripRouteLayout.layout(count: count, width: width, labelHeight: 32).labels
                for index in labels.indices where index + 2 < labels.count {
                    XCTAssertEqual(labels[index].above, labels[index + 2].above)
                    XCTAssertLessThanOrEqual(edges(labels[index]).right, edges(labels[index + 2]).left,
                                             "w=\(width) n=\(count) i=\(index)")
                }
            }
        }
    }

    /// 地名が読める幅がある（4か所・iPhone の幅で 110pt 以上＝12pt の字で9字ほど）
    func testLabelsAreWideEnoughForPlaceNames() {
        let labels = TripRouteLayout.layout(count: 4, width: 350, labelHeight: 32).labels
        for label in labels {
            XCTAssertGreaterThanOrEqual(label.width, 110)
        }
    }

    /// 大きな字（札が高い）でも、札は点に重ならず図の中に収まる
    func testTallLabelsClearDotsAndFitHeight() {
        for labelHeight in [32.0, 48.0, 106.0] as [CGFloat] {
            let layout = TripRouteLayout.layout(count: 4, width: 350, labelHeight: labelHeight)
            XCTAssertEqual(layout.height, TripRouteLayout.height(labelHeight: labelHeight))
            let half = TripRouteLayout.dot / 2
            for (label, point) in zip(layout.labels, layout.points) {
                let edge = verticalEdges(label, labelHeight: labelHeight)
                XCTAssertGreaterThanOrEqual(edge.top, 0)
                XCTAssertLessThanOrEqual(edge.bottom, layout.height)
                if label.above {
                    XCTAssertLessThanOrEqual(edge.bottom, point.y - half)
                } else {
                    XCTAssertGreaterThanOrEqual(edge.top, point.y + half)
                }
            }
        }
    }
}
