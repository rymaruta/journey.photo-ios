import XCTest
@testable import JourneyPhoto

/// 行った県マップの地図の形・当たり判定・色の段（札 #503）。既存の `japan-prefectures.json` を読む。
final class PrefectureMapGeometryTests: XCTestCase {

    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/JourneyPhoto/Resources")

    private func geometry() throws -> PrefectureMapGeometry {
        let data = try Data(contentsOf: Self.resources.appendingPathComponent("japan-prefectures.json"))
        let shapes = try JSONDecoder().decode([ShareCardMap.Shape].self, from: data)
        return try XCTUnwrap(PrefectureMapGeometry.build(shapes: shapes))
    }

    func testAll47PrefecturesInJISOrder() throws {
        let g = try geometry()
        XCTAssertEqual(g.pieces.map(\.prefecture), RegionList.prefectures)
        XCTAssertEqual(g.size.width, 1000)
        XCTAssertTrue((900...1400).contains(g.size.height), "縦横比が想定外: \(g.size)")
    }

    func testTapsLandOnTheRightPrefecture() throws {
        let g = try geometry()
        func hit(_ lat: Double, _ lng: Double, tolerance: CGFloat = 0) -> String? {
            g.prefecture(at: g.projection.point(latitude: lat, longitude: lng), tolerance: tolerance)
        }
        XCTAssertEqual(hit(43.06, 141.35), "北海道")
        XCTAssertEqual(hit(35.69, 139.70), "東京都")
        XCTAssertEqual(hit(35.01, 135.77), "京都府")
        XCTAssertEqual(hit(36.24, 137.97), "長野県")
        XCTAssertEqual(hit(33.59, 130.40), "福岡県")
        // 日本海の真ん中は、許す距離が 0 なら何も押していない
        XCTAssertNil(hit(38.0, 133.0))
    }

    /// 小さな県を押しやすくする: 外側でも許す距離の中でいちばん近い県を採る
    func testToleranceTakesTheNearestPrefecture() throws {
        let g = try geometry()
        let kyoto = try XCTUnwrap(g.piece("京都府"))
        // 京都府の形の頂点を、重心と反対の外側へ 6 ずらす（形の外）。近い県は京都府のはず
        let polygon = try XCTUnwrap(kyoto.polygons.max { $0.count < $1.count })
        let v = polygon[0]
        let c = kyoto.anchor
        let dx = v.x - c.x, dy = v.y - c.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let outside = CGPoint(x: v.x + dx / length * 6, y: v.y + dy / length * 6)
        let name = g.prefecture(at: outside, tolerance: 12)
        XCTAssertNotNil(name)
        XCTAssertNil(g.prefecture(at: CGPoint(x: -50, y: -50), tolerance: 12), "遠い点は何も押していない")
    }

    // MARK: - 沖縄の挿入図

    func testOkinawaIsAnInsetThatDoesNotCoverTheMainIslands() throws {
        let g = try geometry()
        let okinawa = try XCTUnwrap(g.piece("沖縄県"))
        let inset = try XCTUnwrap(g.inset)
        XCTAssertTrue(okinawa.inInset)
        XCTAssertTrue(inset.insetBy(dx: -1, dy: -1).contains(okinawa.bounds), "沖縄の形が枠からはみ出す")
        XCTAssertEqual(g.prefecture(at: okinawa.anchor, tolerance: 25), "沖縄県")
        XCTAssertEqual(g.prefecture(at: CGPoint(x: inset.minX + 2, y: inset.minY + 2), tolerance: 0), "沖縄県",
                       "枠の中の海を押しても沖縄県")
        // 🔴 枠は本州・北海道の線に重ならない（左上の空いた海に置く）
        let padded = inset.insetBy(dx: -10, dy: -10)
        for piece in g.pieces where !piece.inInset {
            for polygon in piece.polygons {
                XCTAssertFalse(polygon.contains { padded.contains($0) }, "\(piece.prefecture) が挿入図の枠に掛かる")
            }
        }
    }

    /// 北緯30度より南の他県の島（小笠原・奄美ほか）は描かない——描くと南へ大きく伸びる
    func testFarSouthernIslandsOfOtherPrefecturesAreNotDrawn() throws {
        let g = try geometry()
        for piece in g.pieces where !piece.inInset {
            XCTAssertLessThanOrEqual(piece.bounds.maxY, g.size.height + 0.5, "\(piece.prefecture) が地図の南に伸びる")
            XCTAssertGreaterThanOrEqual(piece.bounds.minX, -0.5)
            XCTAssertLessThanOrEqual(piece.bounds.maxX, g.size.width + 0.5)
        }
        XCTAssertNotNil(g.piece("東京都"))
        XCTAssertNotNil(g.piece("鹿児島県"))
    }

    // MARK: - 近くの県

    func testNearbyAreThreeNeighboursWithoutTheTappedOne() throws {
        let g = try geometry()
        let tap = g.projection.point(latitude: 35.01, longitude: 135.77)
        let near = g.nearby(to: tap, excluding: "京都府")
        XCTAssertEqual(near.count, 3)
        XCTAssertFalse(near.contains("京都府"))
        XCTAssertFalse(near.contains("沖縄県"))
        let neighbours: Set<String> = ["大阪府", "滋賀県", "奈良県", "福井県", "兵庫県", "三重県", "和歌山県"]
        XCTAssertTrue(Set(near).isSubset(of: neighbours), "近くの県が遠い: \(near)")
        XCTAssertEqual(g.nearby(to: .zero, excluding: "沖縄県"), [])
    }

    // MARK: - 図形の計算

    func testPolygonMath() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        XCTAssertEqual(abs(PrefectureMapGeometry.signedArea(square)), 100, accuracy: 0.001)
        let c = PrefectureMapGeometry.centroid(square)
        XCTAssertEqual(c.x, 5, accuracy: 0.001)
        XCTAssertEqual(c.y, 5, accuracy: 0.001)
        XCTAssertTrue(PrefectureMapGeometry.contains(square, CGPoint(x: 5, y: 5)))
        XCTAssertFalse(PrefectureMapGeometry.contains(square, CGPoint(x: 11, y: 5)))
        XCTAssertEqual(PrefectureMapGeometry.distance(from: CGPoint(x: 13, y: 5), toSegment: square[1], square[2]),
                       3, accuracy: 0.001)
    }

    // MARK: - 地方・色の段

    func testRegionsCoverAll47Once() {
        XCTAssertEqual(PrefectureRegions.all.flatMap(\.prefectures), RegionList.prefectures)
        XCTAssertEqual(PrefectureRegions.all.map { $0.prefectures.count }, [1, 6, 7, 9, 7, 5, 4, 8])
        XCTAssertEqual(PrefectureRegions.region(of: "東京都")?.name, "関東")
        XCTAssertEqual(PrefectureRegions.region(of: "沖縄県")?.name, "九州・沖縄")
        XCTAssertNil(PrefectureRegions.region(of: "パリ"))
    }

    func testMixAndFill() {
        XCTAssertEqual(VisitedMapStyle.mix(0x000000, 0xFFFFFF, 0.5), 0x808080)
        XCTAssertEqual(VisitedMapStyle.mix(0x796440, 0xC9A66B, 0), 0x796440)
        XCTAssertEqual(VisitedMapStyle.mix(0x796440, 0xC9A66B, 1), 0xC9A66B)
        XCTAssertEqual(VisitedMapStyle.mix(0x796440, 0xC9A66B, 9), 0xC9A66B, "割合は 0〜1 に収める")
        XCTAssertEqual(VisitedMapStyle.fill(forLevel: 0), VisitedMapStyle.baseFill)
        XCTAssertEqual(VisitedMapStyle.fill(forLevel: 3), 0xF3DCA6)
        XCTAssertEqual(VisitedMapStyle.fill(forLevel: 99), 0xF3DCA6)
    }

    /// 段ごとの色（2026-11-09 owner: 0 回・1 回・2 回・3 回以上の4段・模様なし・色だけ）。値は板 04b の段の色
    func testStyleLevels() {
        XCTAssertEqual(VisitedMapStyle.fills.count, 4, "段は 0 回・1 回・2 回・3 回以上の4つ")
        XCTAssertNil(VisitedMapStyle.fills[0])
        XCTAssertEqual(VisitedMapStyle.baseFill, 0x1A1A1C, "0 回は scale0（surface-3 と同値）")
        XCTAssertEqual(VisitedMapStyle.fills[1], 0x705523)
        XCTAssertEqual(VisitedMapStyle.fills[2], 0xB08E55)
        XCTAssertEqual(VisitedMapStyle.fills[3], 0xF3DCA6)
        XCTAssertEqual((0...6).map(VisitedMapStyle.fill(forLevel:)),
                       [0x1A1A1C, 0x705523, 0xB08E55, 0xF3DCA6, 0xF3DCA6, 0xF3DCA6, 0xF3DCA6],
                       "3 回以上は同じ色")
        XCTAssertEqual((0...3).map(VisitedMapStyle.fill(forLevel:)), BrandPalette.scaleSteps,
                       "地図の段は板の段の色の表をそのまま使う")
    }

    /// 色だけで分けるので、明るさの順と差を縛る（色覚が違っても明るさで分かる）。
    /// 板 04b: 1 段目は黒地に 3:1 以上・隣り合う段（0 の地を含む）どうし ×2.2 以上
    func testPaintedFillsAreSeparatedByLuminance() {
        let fills = VisitedMapStyle.paintedFills
        XCTAssertEqual(fills.count, 3)
        for hex in fills {
            XCTAssertGreaterThanOrEqual(VisitedMapStyle.contrastOnBlack(hex), 3.0, "黒地に 3:1 以上: \(String(hex, radix: 16))")
        }
        let steps = [VisitedMapStyle.baseFill] + fills
        for (lower, higher) in zip(steps, steps.dropFirst()) {
            XCTAssertGreaterThan(BrandPalette.luminance(higher), BrandPalette.luminance(lower), "段が上がるほど明るい")
            XCTAssertGreaterThanOrEqual(VisitedMapStyle.adjacentRatio(lower, higher), 2.2,
                                        "隣り合う段の比: \(String(lower, radix: 16)) → \(String(higher, radix: 16))")
        }
        XCTAssertEqual(VisitedMapStyle.contrastOnBlack(0x1A1A1C), 1.21, accuracy: 0.01)
        XCTAssertEqual(VisitedMapStyle.contrastOnBlack(0x705523), 3.01, accuracy: 0.01)
        XCTAssertEqual(VisitedMapStyle.contrastOnBlack(0xB08E55), 6.85, accuracy: 0.01)
        XCTAssertEqual(VisitedMapStyle.contrastOnBlack(0xF3DCA6), 15.60, accuracy: 0.01)
    }

    /// 板 04b「縁と状態」の値。押している間の 0 の県（白 8%）は surface-8 と同じ色になる
    func testEdgesAndStates() {
        XCTAssertEqual(VisitedMapStyle.paintedEdgeWidth, 1)
        XCTAssertEqual(VisitedMapStyle.zeroEdgeWidth, 0.6)
        XCTAssertEqual(VisitedMapStyle.zeroEdgeWhite, 0.2)
        XCTAssertEqual(VisitedMapStyle.candidateInsideWidth, 1.5)
        XCTAssertEqual(VisitedMapStyle.candidateDash, [3, 3])
        XCTAssertEqual(VisitedMapStyle.selectedRingWidth, 2)
        XCTAssertEqual(VisitedMapStyle.selectedGapWidth, 1.5)
        XCTAssertEqual(VisitedMapStyle.pressedFill(forLevel: 0), BrandPalette.surface8, "0 の県を押す間は白 8% ＝ surface-8")
        XCTAssertEqual(VisitedMapStyle.pressedFill(forLevel: 3), VisitedMapStyle.mix(0xF3DCA6, 0x000000, 0.2), "塗った県は黒 20%")
        for level in 1...3 {
            XCTAssertLessThan(BrandPalette.luminance(VisitedMapStyle.pressedFill(forLevel: level)),
                              BrandPalette.luminance(VisitedMapStyle.fill(forLevel: level)), "押す間は暗くなる")
        }
        // 候補の破線は 0 の地の上（7.57）。2 段目の上だと 1.34 で溶けるので、内側だけに描く
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(BrandPalette.accent, VisitedMapStyle.baseFill), 7.5)
    }
}
