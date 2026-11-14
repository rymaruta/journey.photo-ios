import XCTest
@testable import JourneyPhoto

/// 写真を紹介するストーリーの地（2026-11-14 owner「投稿した後にストーリーに載せるの背景寂しいね」・`SharedPhotoStoryBackdrop`）。
/// 明るい写真でも上下の白い字が読め、暗い写真は沈めすぎない（前の一様な黒 45% に戻すと落ちる）
final class StoryShareBackdropTests: XCTestCase {
    typealias B = SharedPhotoStoryBackdrop

    /// 升目を行ごとの色で作る（`colorAt(行)`）
    private func grid(_ colorAt: (Int) -> UInt32) -> [UInt32] {
        (0..<B.gridRows).flatMap { row in Array(repeating: colorAt(row), count: B.gridColumns) }
    }

    /// どの升目でも、その升目の範囲でいちばん薄い黒を重ねたときの、白の字との比
    private func worstContrast(_ grid: [UInt32], rows: Range<Int>, _ shades: B.Shades) -> Double {
        var worst = Double.infinity
        for row in rows {
            let top = CGFloat(row) / CGFloat(B.gridRows)
            let bottom = CGFloat(row + 1) / CGFloat(B.gridRows)
            let alpha = Double(min(B.alpha(at: top, shades), B.alpha(at: bottom, shades)))
            for column in 0..<B.gridColumns {
                let shaded = B.shaded(grid[row * B.gridColumns + column], lift: B.glowAlpha, shade: alpha)
                worst = min(worst, BrandPalette.contrast(0xFFFFFF, shaded))
            }
        }
        return worst
    }

    private func assertReadable(_ grid: [UInt32], _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let shades = B.shades(grid: grid)
        XCTAssertGreaterThanOrEqual(worstContrast(grid, rows: B.topRows, shades), 4.5,
                                    "\(name): 上の帯（名前・進み線）の白い字が 4.5:1 に届かない", file: file, line: line)
        XCTAssertGreaterThanOrEqual(worstContrast(grid, rows: B.bottomRows, shades), 4.5,
                                    "\(name): 下の帯（写真を見る・返信欄）の白い字が 4.5:1 に届かない", file: file, line: line)
        XCTAssertGreaterThanOrEqual(worstContrast(grid, rows: B.topRows.upperBound..<B.bottomRows.lowerBound, shades), 3,
                                    "\(name): 札の周りが 3:1 に届かない", file: file, line: line)
    }

    /// 明るい写真（雪・白い壁・昼の空）でも、上と下の白い字が読める。**前の一様な黒 45% では届かない**
    func testBrightPhotosStayReadable() {
        assertReadable(grid { _ in 0xFFFFFF }, "真っ白")
        assertReadable(grid { _ in 0xF2EAD8 }, "生成りの壁")
        assertReadable(grid { $0 < 12 ? 0x9CD2FF : 0x6B5A3A }, "上が明るい空・下が地面")
        assertReadable(grid { $0 > 20 ? 0xFFF4C0 : 0x202020 }, "下だけ明るい（砂浜）")
        assertReadable(grid { (8..<20).contains($0) ? 0xFFFFFF : 0x101010 }, "真ん中だけ明るい")
        // 前の作り（一様な黒 45%・光なし）では、明るい写真の上の白い字が読めなかった
        let old = B.shaded(0xFFFFFF, lift: 0, shade: 0.45)
        XCTAssertLessThan(BrandPalette.contrast(0xFFFFFF, old), 4.5, "前の作りの確かめ（この試験が直しを見ている）")
    }

    /// 暗い写真（夜景）は沈めすぎない。真ん中は前の 45% よりずっと薄く、上下は札を浮かせる程度に落とす
    func testDarkPhotosAreNotBuried() {
        let shades = B.shades(grid: grid { _ in 0x141824 })
        XCTAssertEqual(shades.middle, B.minimumMiddle, accuracy: 0.001)
        XCTAssertEqual(shades.top, B.minimumTop, accuracy: 0.001)
        XCTAssertEqual(shades.bottom, B.minimumBottom, accuracy: 0.001)
        XCTAssertLessThan(shades.middle, 0.45, "暗い写真の札の周りを、前と同じ 45% で沈めている")
        XCTAssertLessThan(shades.middle, shades.top, "上下が真ん中より明るい（札が浮かない）")
        XCTAssertLessThan(shades.middle, shades.bottom)
    }

    /// 測れなかったら（升目が足りない）白とみなして暗くする（字を読めなくしない）
    func testUnmeasuredGridIsTreatedAsBright() {
        XCTAssertEqual(B.shades(grid: []), B.shades(grid: grid { _ in 0xFFFFFF }))
        XCTAssertEqual(B.shades(grid: [0x000000]), B.shades(grid: grid { _ in 0xFFFFFF }))
    }

    /// 上下は真ん中より薄くならない。段は 0 から 1 へ並び、上の帯と下の帯は升目の境まで同じ濃さ
    func testStopsKeepEdgesAtLeastAsDarkAsTheMiddle() {
        let shades = B.shades(grid: grid { (8..<20).contains($0) ? 0xFFFFFF : 0x101010 })
        XCTAssertGreaterThanOrEqual(shades.top, shades.middle)
        XCTAssertGreaterThanOrEqual(shades.bottom, shades.middle)
        let stops = B.stops(shades)
        XCTAssertEqual(stops.first?.location, 0)
        XCTAssertEqual(stops.last?.location, 1)
        XCTAssertEqual(stops.map(\.location), stops.map(\.location).sorted())
        let topEnd = CGFloat(B.topRows.upperBound) / CGFloat(B.gridRows)
        let bottomStart = CGFloat(B.bottomRows.lowerBound) / CGFloat(B.gridRows)
        XCTAssertEqual(Double(B.alpha(at: topEnd, shades)), shades.top, accuracy: 0.0001)
        XCTAssertEqual(Double(B.alpha(at: bottomStart, shades)), shades.bottom, accuracy: 0.0001)
        XCTAssertEqual(Double(B.alpha(at: 0.45, shades)), shades.middle, accuracy: 0.0001)
    }

    /// 「写真を見る」（`buttonCenterY`）は下の帯の中（白の字 4.5:1 を守る所）
    func testViewPhotoButtonSitsInTheBottomBand() {
        let row = Int(SharedPhotoStoryCard.buttonCenterY * Double(B.gridRows))
        XCTAssertTrue(B.bottomRows.contains(row), "「写真を見る」が下の帯の外（字の読みやすさを守れていない）")
    }
}
