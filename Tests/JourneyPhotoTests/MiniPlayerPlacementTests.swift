import XCTest
@testable import JourneyPhoto

/// 全体の再生器を指で動かす決まり（`MiniPlayerPlacement`・2026-10-28 owner「再生中の音楽自由に動かせるといいね」）。
/// 端への寄せ・範囲に収める計算・払って消す判定
final class MiniPlayerPlacementTests: XCTestCase {

    /// iPhone 15 の安全領域の内側に近い枠
    private let container = CGSize(width: 390, height: 763)
    private var bar: CGSize { CGSize(width: MiniPlayerPlacement.barWidth(container: container), height: 60) }

    private func center(_ spot: MiniPlayerPlacement.Spot) -> CGPoint {
        MiniPlayerPlacement.center(of: spot, container: container, barSize: bar)
    }

    private func settle(_ translation: CGSize, predicted: CGSize? = nil,
                        from spot: MiniPlayerPlacement.Spot = .initial) -> MiniPlayerPlacement.Outcome {
        MiniPlayerPlacement.settle(from: spot, translation: translation, predicted: predicted ?? translation,
                                   container: container, barSize: bar)
    }

    /// 全幅にしない（全幅だと左右へ寄せられない）。狭い枠では端の間を残して縮める
    func testBarIsNarrowerThanScreen() {
        XCTAssertEqual(MiniPlayerPlacement.barWidth(container: container), 280)
        XCTAssertLessThan(MiniPlayerPlacement.barWidth(container: container), container.width - 24)
        XCTAssertEqual(MiniPlayerPlacement.barWidth(container: CGSize(width: 300, height: 600)), 276)
        XCTAssertEqual(MiniPlayerPlacement.barWidth(container: CGSize(width: 10, height: 600)), 0)
    }

    /// 初めは右下・タブバーのすぐ上（前の全幅のバーと同じ高さ）
    func testInitialSpotIsBottomTrailing() {
        let point = center(.initial)
        XCTAssertEqual(point.x, 390 - 12 - 140)
        XCTAssertEqual(point.y + 30, container.height - MiniPlayerPlacement.bottomReserved, "下端がタブバーの上")
    }

    /// 離したら、左右の近い端へ寄せる。縦は離した所
    func testSnapsToNearestEdgeKeepingHeight() {
        // 左へ少し（中央を越えない）→ 右のまま
        guard case .place(let stay) = settle(CGSize(width: -40, height: -200)) else { return XCTFail("消えた") }
        XCTAssertEqual(stay.side, .trailing)
        XCTAssertEqual(center(stay).y, center(.initial).y - 200, accuracy: 0.001, "縦は離した所")
        // 中央を越えて左へ → 左の端
        guard case .place(let left) = settle(CGSize(width: -120, height: -200)) else { return XCTFail("消えた") }
        XCTAssertEqual(left.side, .leading)
        XCTAssertEqual(center(left).x, 12 + 140, "左の端から 12pt")
        XCTAssertEqual(center(left).y, center(.initial).y - 200, accuracy: 0.001)
    }

    /// 速く払ったら、離した所が中央の手前でも払った向きの端へ
    func testFlingDecidesSide() {
        guard case .place(let spot) = settle(CGSize(width: -30, height: -100),
                                             predicted: CGSize(width: -400, height: -120)) else {
            return XCTFail("消えた")
        }
        XCTAssertEqual(spot.side, .leading)
        XCTAssertEqual(center(spot).y, center(.initial).y - 100, accuracy: 0.001, "縦は勢いではなく離した所")
    }

    /// 上の見出し・下のタブバーに重ならない範囲に収める
    func testClampsInsideHeaderAndTabBar() {
        guard case .place(let top) = settle(CGSize(width: 0, height: -2000)) else { return XCTFail("消えた") }
        XCTAssertEqual(top.height, 1)
        XCTAssertEqual(center(top).y - 30, MiniPlayerPlacement.topReserved, accuracy: 0.001, "上端が見出しの下")
        // 下へゆっくり引いた（払っていない）だけでは消さず、タブバーの上に収める
        guard case .place(let bottom) = settle(CGSize(width: 0, height: 900),
                                               from: .init(side: .trailing, height: 0.5)) else {
            return XCTFail("ゆっくり引いただけで消えた")
        }
        XCTAssertEqual(bottom.height, 0)
        XCTAssertEqual(center(bottom).y + 30, container.height - MiniPlayerPlacement.bottomReserved, accuracy: 0.001)
        // 範囲の外の割合も中に収める
        XCTAssertEqual(center(.init(side: .leading, height: 5)).y, center(top).y)
        XCTAssertEqual(center(.init(side: .leading, height: -5)).y, center(.initial).y)
    }

    /// 狭すぎる枠ではいちばん下に揃える（範囲が逆さにならない）
    func testTinyContainerDoesNotInvertRange() {
        let tiny = CGSize(width: 320, height: 120)
        let range = MiniPlayerPlacement.verticalRange(container: tiny, barHeight: 60)
        XCTAssertLessThanOrEqual(range.lowerBound, range.upperBound)
        XCTAssertEqual(MiniPlayerPlacement.height(forCenterY: 0, container: tiny, barHeight: 60), 0)
    }

    /// 下へ素早く払って外へ出したら消す。ゆっくり・横向き・少しだけでは消さない
    func testFlingDownDismisses() {
        // 離した所が範囲の下端より再生器半分（30）以上外・勢い 200
        XCTAssertEqual(settle(CGSize(width: 0, height: 70), predicted: CGSize(width: 0, height: 270)), .dismiss)
        // 勢いが下限（160）に届かない
        XCTAssertNotEqual(settle(CGSize(width: 0, height: 70), predicted: CGSize(width: 0, height: 200)), .dismiss)
        // 勢いが足りない（行き着く先が離した所と同じ）
        XCTAssertNotEqual(settle(CGSize(width: 0, height: 200), predicted: CGSize(width: 0, height: 210)), .dismiss)
        // 横へ払った（下へも動いたが横が主）
        XCTAssertNotEqual(settle(CGSize(width: -60, height: 30), predicted: CGSize(width: -500, height: 200)), .dismiss)
        // 上の方から払ったが、行き着く先が範囲の下より外に出ない
        let high = MiniPlayerPlacement.Spot(side: .trailing, height: 1)
        XCTAssertNotEqual(settle(CGSize(width: 0, height: 20), predicted: CGSize(width: 0, height: 200), from: high), .dismiss)
        // 上へ払っても消さない
        XCTAssertNotEqual(settle(CGSize(width: 0, height: -40), predicted: CGSize(width: 0, height: -400)), .dismiss)
    }

    /// 🔴 **範囲の中で離したら、勢いがあっても止めない**（確かめ役の指摘: 下へ引き下ろしただけで止まった）
    func testReleaseInsideRangeNeverDismisses() {
        // 範囲の下端（再生器の下端がタブバーの上）から少しだけ下で離し、強く払った
        XCTAssertNotEqual(settle(CGSize(width: 0, height: 20), predicted: CGSize(width: 0, height: 900)), .dismiss)
        // 上の方から下端の手前まで勢いよく引き下ろした
        let middle = MiniPlayerPlacement.Spot(side: .trailing, height: 0.6)
        let pull = center(.initial).y - center(middle).y
        guard case .place(let spot) = settle(CGSize(width: 0, height: pull),
                                             predicted: CGSize(width: 0, height: pull + 800), from: middle) else {
            return XCTFail("引き下ろしただけで止まった")
        }
        XCTAssertEqual(spot.height, 0, accuracy: 0.0001, "いちばん下に収まる")
    }

    /// 読み上げの「左の端へ」「右の端へ」は高さを変えない
    func testAccessibilitySideMoves() {
        let spot = MiniPlayerPlacement.Spot(side: .trailing, height: 0.5)
        XCTAssertEqual(MiniPlayerPlacement.moved(spot, to: .leading), .init(side: .leading, height: 0.5))
        XCTAssertEqual(MiniPlayerPlacement.moved(spot, to: .trailing), spot)
    }

    /// いちばん上でも、上の見出しとその下の1段（探すの入力欄など）にかぶらない
    func testTopLeavesHeaderAndFirstRow() {
        // 探すの入力欄の下端は安全領域の上から 154pt（run 736 の実測）
        XCTAssertGreaterThanOrEqual(MiniPlayerPlacement.topReserved, 154, "探すの入力欄にかぶる")
    }

    /// 読み上げの「上へ移す／下へ移す」は範囲の中で動く
    func testAccessibilityMoves() {
        var spot = MiniPlayerPlacement.Spot.initial
        spot = MiniPlayerPlacement.moved(spot, up: false)
        XCTAssertEqual(spot.height, 0, "いちばん下より下へは行かない")
        for _ in 0..<3 { spot = MiniPlayerPlacement.moved(spot, up: true) }
        XCTAssertEqual(spot.height, 1, accuracy: 0.0001, "3回でいちばん上")
        spot = MiniPlayerPlacement.moved(spot, up: true)
        XCTAssertEqual(spot.height, 1, accuracy: 0.0001)
        XCTAssertEqual(spot.side, .trailing, "左右は変えない")
    }

    /// 置き場所は再生の間覚える（同じ1つの入れ物）
    func testPlacementIsShared() {
        let store = MiniPlayerPlacementStore.shared
        let before = store.spot
        defer { store.spot = before }
        store.spot = .init(side: .leading, height: 0.4)
        XCTAssertEqual(MiniPlayerPlacementStore.shared.spot, .init(side: .leading, height: 0.4))
    }

    // MARK: - 見た目の決まり

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line }
            .joined(separator: "\n")
    }

    /// 地を透けさせない（白 10% の地は下の文字と曲名が重なって読めなかった）・停止は 44pt・
    /// 読み上げに移動の代わりの操作・ドラッグは少し動いてから
    func testBarIsOpaqueAndAccessible() throws {
        let bar = try source("Sources/JourneyPhoto/Features/Common/MiniPlayerBar.swift")
        XCTAssertFalse(bar.contains("WebTheme.raised"), "透ける地に戻っている")
        XCTAssertTrue(bar.contains(".background(Self.pickerBarFill, in:"), "不透明の面でない")
        XCTAssertTrue(bar.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"), "停止が 44pt でない")
        for text in ["L(\"再生中の曲\", \"Now playing\")", "長押ししてドラッグで移動", "上へ移す", "下へ移す",
                     "左の端へ", "右の端へ", "joined(separator: L("] {
            XCTAssertTrue(bar.contains(text), "読み上げの「\(text)」が無い")
        }
        XCTAssertTrue(bar.contains(".accessibilityHint("), "操作の説明がラベルに混ざっている")
        XCTAssertFalse(bar.contains("再生中の曲。ドラッグで移動"), "操作の説明がラベルに混ざっている")
        // スクロールの指で動かないよう、長押しが済んでから引く
        XCTAssertTrue(bar.contains("LongPressGesture(minimumDuration: Self.liftDelay)"), "長押しせずに動く")
        XCTAssertTrue(bar.contains(".sequenced(before: DragGesture("), "長押しせずに動く")
        XCTAssertTrue(bar.contains(".sensoryFeedback(.impact(weight: .light), trigger: dragging)"), "持ち上げの合図が無い")
        XCTAssertTrue(bar.contains("dragging && !reduceMotion ? Self.liftedScale : 1"), "動きを減らすで縮める")
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertFalse(root.contains("MiniPlayerBar().padding"), "置き場所を外から固定している")
    }
}
