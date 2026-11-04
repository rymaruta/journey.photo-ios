import XCTest
@testable import JourneyPhoto

/// SNS 共有カードの地図（案A-3・2026-11-04 owner 了承）と撮影地の折り返しの計算。
/// 描く処理は Linux では空なので、計算だけを切り出して試す（`ShareCardMap`・`ShareCardText`）。
final class ShareCardMapTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/JourneyPhoto/Resources")

    private static func shapes(_ name: String) throws -> [ShareCardMap.Shape] {
        let data = try Data(contentsOf: resources.appendingPathComponent("\(name).json"))
        return try JSONDecoder().decode([ShareCardMap.Shape].self, from: data)
    }

    private static let countries: [ShareCardMap.Shape] = (try? shapes("country-outlines")) ?? []

    private func country(_ name: String) throws -> ShareCardMap.Shape {
        try XCTUnwrap(Self.countries.first { $0.n == name }, "\(name) が国の輪郭に無い")
    }

    // MARK: - 枠の寸法

    func testMapFrameIsLargestThatAvoidsSeparatorAndPhotoInEveryRatio() {
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.Layout(ratio: ratio)
            let map = layout.mapRect
            // 板（MapASize）の 290×245 以上
            XCTAssertGreaterThanOrEqual(map.width, 290, "\(ratio)")
            XCTAssertGreaterThanOrEqual(map.height, 245, "\(ratio)")
            // 下: 区切り線に当たらない
            XCTAssertLessThan(map.maxY, layout.separatorY, "\(ratio) 区切り線に当たる")
            // 上: 写真の裾の黒が 78% より薄い所（写真が透ける所）に掛からない
            XCTAssertGreaterThanOrEqual(layout.fadeAlpha(atY: map.minY), 0.78, "\(ratio) 写真に掛かる")
            XCTAssertGreaterThanOrEqual(map.minY, layout.fadeY(reaching: 0.78), "\(ratio)")
            XCTAssertGreaterThan(map.minY, layout.photoRect.minY)
            // 横: 撮影地の字（140 幅）と、写真の黒の面の右端の内側
            XCTAssertGreaterThan(map.minX, ShareCardMap.Layout.placeX + ShareCardMap.Layout.placeWidthWithMap)
            XCTAssertLessThanOrEqual(map.maxX, ShareCardMap.Layout.width - ShareCardMap.Layout.margin)
        }
    }

    func testMapFrameMeasuredValues() {
        // 4:5（1080×1350）: rowY 1032・区切り線 1206・帯の 86% は y 946.6
        let portrait = ShareCardMap.Layout(ratio: .portrait)
        XCTAssertEqual(portrait.rowY, 1032)
        XCTAssertEqual(portrait.mapRect, CGRect(x: 722, y: 947, width: 290, height: 250))
        // 9:16 は下の段が高いが、区切り線も帯も撮影者の段から測るので同じ大きさ（縦 300 は取れない）
        let story = ShareCardMap.Layout(ratio: .story)
        XCTAssertEqual(story.mapRect, CGRect(x: 722, y: 1442, width: 290, height: 250))
        let square = ShareCardMap.Layout(ratio: .square)
        XCTAssertEqual(square.mapRect, CGRect(x: 722, y: 677, width: 290, height: 250))
    }

    // MARK: - 残す島

    private func focusBounds(_ name: String, _ latitude: Double, _ longitude: Double) throws
        -> (bounds: ShareCardMap.Bounds, zoom: Double) {
        let shape = try country(name)
        let rect = ShareCardMap.Layout(ratio: .portrait).mapRect
        let focused = try XCTUnwrap(ShareCardMap.focus(shape, latitude: latitude, longitude: longitude, in: rect))
        // 前の描き方（国の全体を 250×185 に収める）と比べた縮尺
        let rings = ShareCardMap.unwrap(shape.r, aroundLongitude: longitude)
        let whole = ShareCardMap.Projection(bounds: try XCTUnwrap(ShareCardMap.Bounds(rings)),
                                            rect: CGRect(x: 0, y: 0, width: 250, height: 185))
        return (focused.projection.bounds, focused.projection.scale / whole.scale)
    }

    func testJapanMainlandDropsRemoteIslands() throws {
        // 山梨（0.5° に丸めたピン）。小笠原（27°N）・沖ノ鳥島（20°N）・南鳥島（154°E）を外す
        let (bounds, zoom) = try focusBounds("Japan", 35.5, 138.5)
        XCTAssertGreaterThan(bounds.south, 30, "小笠原・沖縄が残っている")
        XCTAssertLessThan(bounds.east, 146.5, "南鳥島が残っている")
        XCTAssertGreaterThan(bounds.north, 45, "北海道が外れている")
        XCTAssertLessThan(bounds.west, 130, "九州が外れている")
        XCTAssertEqual(zoom, 1.93, accuracy: 0.03, "板（290×245）では 1.88。枠を測って 250 にした分")
    }

    func testOkinawaKeepsOkinawa() throws {
        // 那覇（26.21, 127.68）は丸めると海の上（26.0, 127.5）。いちばん近い島＝沖縄本島が残る
        let pin = try XCTUnwrap(SignatureShareCardRenderer.approximateShareCoordinate(
            Photo.Coords(lat: 26.2124, lng: 127.6809)))
        let (bounds, zoom) = try focusBounds("Japan", pin.latitude, pin.longitude)
        XCTAssertLessThanOrEqual(bounds.south, 26.2)
        XCTAssertLessThanOrEqual(bounds.west, 127.7)
        XCTAssertGreaterThan(bounds.north, 45, "本土（一番大きい陸）も残す")
        XCTAssertEqual(zoom, 1.51, accuracy: 0.03)
    }

    func testOgasawaraKeepsOgasawara() throws {
        let (bounds, _) = try focusBounds("Japan", 27.0, 142.0)
        XCTAssertLessThanOrEqual(bounds.south, 27.0, "撮った小笠原が外れている")
        XCTAssertGreaterThanOrEqual(bounds.east, 142.1)
        XCTAssertLessThan(bounds.east, 146.5, "南鳥島は 60km より遠い")
    }

    func testFranceDropsOverseasDepartments() throws {
        let (bounds, zoom) = try focusBounds("France", 48.5, 2.5)
        XCTAssertGreaterThan(bounds.west, -6)
        XCTAssertLessThan(bounds.east, 10)
        XCTAssertGreaterThan(bounds.south, 41)
        XCTAssertLessThan(bounds.north, 52)
        XCTAssertEqual(zoom, 12.98, accuracy: 0.2)
    }

    func testHawaiiKeepsHawaiiAndMainland() throws {
        let (bounds, _) = try focusBounds("United States of America", 21.5, -158.0)
        XCTAssertLessThanOrEqual(bounds.west, -158, "撮ったハワイが外れている")
        XCTAssertLessThan(bounds.south, 21.5)
        XCTAssertGreaterThan(bounds.east, -70, "一番大きい陸（本土）も残す")
        XCTAssertLessThan(bounds.north, 50, "アラスカは 60km より遠い")
    }

    func testUSMainlandDropsHawaiiAndAlaska() throws {
        let (bounds, _) = try focusBounds("United States of America", 40.5, -74.0)
        XCTAssertGreaterThan(bounds.west, -125)
        XCTAssertGreaterThan(bounds.south, 24)
        XCTAssertLessThan(bounds.north, 50)
    }

    func testItalyKeepsSicilyAndSardinia() throws {
        let (bounds, zoom) = try focusBounds("Italy", 41.5, 12.5)
        XCTAssertLessThan(bounds.south, 37, "シチリア")
        XCTAssertLessThan(bounds.west, 8.5, "サルデーニャ")
        XCTAssertEqual(zoom, 1.38, accuracy: 0.03)
    }

    func testFocusAcrossAntimeridianStaysNarrow() throws {
        // フィジーは ±180° をまたぐ。開いて 360° 幅にならない
        let (bounds, _) = try focusBounds("Fiji", -16.5, 179.8)
        XCTAssertLessThan(bounds.east - bounds.west, 10)
        let (russia, _) = try focusBounds("Russia", 66.0, -179.0)
        XCTAssertLessThan(russia.east - russia.west, 200)
    }

    // MARK: - 塗る県

    func testPrefectureNameFromShareCardLocation() {
        XCTAssertEqual(ShareCardMap.prefectureName(in: "千葉県（市原市）"), "千葉県")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "山梨県（山中湖村）"), "山梨県")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "北海道（札幌市）"), "北海道")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "東京都"), "東京都")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "清水寺 (京都府, 京都市)"), "京都府")
        XCTAssertNil(ShareCardMap.prefectureName(in: "Florence, Italy"))
        XCTAssertNil(ShareCardMap.prefectureName(in: "Versailles, Île-de-France, フランス"))
        XCTAssertNil(ShareCardMap.prefectureName(in: "イヴリーヌ県（フランス）"), "海外の「県」は塗らない")
        XCTAssertNil(ShareCardMap.prefectureName(in: "千葉"), "県名がそのまま無ければ塗らない")
        XCTAssertNil(ShareCardMap.prefectureName(in: nil))
    }

    func testBundledPrefecturesMatchRegionList() throws {
        let prefectures = try Self.shapes("japan-prefectures")
        XCTAssertEqual(prefectures.map(\.n), RegionList.prefectures)
        let yamanashi = try XCTUnwrap(prefectures.first { $0.n == "山梨県" })
        // 山中湖（35.42, 138.87）が山梨県の輪の中
        XCTAssertTrue(yamanashi.r.contains {
            ShareCardMap.ringContains($0, longitude: 138.87, latitude: 35.42)
        })
        let okinawa = try XCTUnwrap(prefectures.first { $0.n == "沖縄県" })
        XCTAssertFalse(okinawa.r.contains {
            ShareCardMap.ringContains($0, longitude: 138.87, latitude: 35.42)
        })
    }

    func testPrefectureShapeRequiresNearbyPin() throws {
        let prefectures = try Self.shapes("japan-prefectures")
        XCTAssertEqual(ShareCardMap.prefectureShape(named: "千葉県", among: prefectures,
                                                    latitude: 35.5, longitude: 140.0)?.n, "千葉県")
        // 文字は千葉県なのにピンが沖縄: 食い違うので塗らない
        XCTAssertNil(ShareCardMap.prefectureShape(named: "千葉県", among: prefectures,
                                                  latitude: 26.0, longitude: 127.5))
        XCTAssertNil(ShareCardMap.prefectureShape(named: nil, among: prefectures,
                                                  latitude: 35.5, longitude: 140.0))
    }

    // MARK: - 撮影地の折り返し（語の途中で折らない）

    /// 和文は1字＝字の大きさ、欧文は半分で測る（Linux には字の形が無いため）
    private func measure(_ text: String, _ size: CGFloat) -> CGFloat {
        text.reduce(CGFloat(0)) { width, character in
            width + (character.isASCII || "Îé".contains(character) ? size * 0.5 : size)
        }
    }

    private func fitPlace(_ text: String) -> ShareCardText.Fitted {
        ShareCardText.fit(text, maxWidth: 140, preferredSize: 26, minimumSize: max(16, 26 * 0.72),
                          maxLines: { _ in 3 }, measure: measure)
    }

    func testSegmentsBreakOnlyAtSeparators() {
        XCTAssertEqual(ShareCardText.segments("山梨県（山中湖村）"), ["山梨県", "（山中湖村）"])
        XCTAssertEqual(ShareCardText.segments("Versailles, Île-de-France, フランス"),
                       ["Versailles, ", "Île-de-France, ", "フランス"])
        XCTAssertEqual(ShareCardText.segments("清水寺 (京都府, 京都市)"), ["清水寺 ", "(京都府, 京都市)"],
                       "括弧の中では折らない")
        XCTAssertEqual(ShareCardText.segments("東京・浅草、雷門"), ["東京・", "浅草、", "雷門"])
        XCTAssertEqual(ShareCardText.segments("山中湖村"), ["山中湖村"])
    }

    func testPlaceBreaksBetweenPrefectureAndCity() {
        // 「（山中湖村）」は 26pt で 156 > 140。語の途中で折らず、字を小さくして1行に収める
        let yamanashi = fitPlace("山梨県（山中湖村）")
        XCTAssertEqual(yamanashi.lines, ["山梨県", "（山中湖村）"])
        XCTAssertEqual(yamanashi.size, 23)
        XCTAssertFalse(yamanashi.truncated)
        XCTAssertEqual(fitPlace("千葉県（市原市）").lines, ["千葉県", "（市原市）"])
        XCTAssertEqual(fitPlace("千葉県（市原市）").size, 26)
        XCTAssertEqual(fitPlace("北海道（札幌市）").lines, ["北海道", "（札幌市）"])
        let france = fitPlace("Versailles, Île-de-France, フランス")
        XCTAssertEqual(france.lines, ["Versailles,", "Île-de-France,", "フランス"])
        XCTAssertFalse(france.truncated)
        for fitted in [yamanashi, france] {
            for line in fitted.lines {
                XCTAssertLessThanOrEqual(measure(line, fitted.size), 140)
            }
        }
    }

    func testOverlongChunkShrinksThenTruncatesWithoutMidWordBreak() {
        // 下限（18.72）でも 140 に入らない塊は、次の行へ送らず末尾を「…」で切る
        let fitted = fitPlace("北海道（上川郡東川町字東七号北）")
        XCTAssertTrue(fitted.truncated)
        XCTAssertEqual(fitted.size, max(16, 26 * 0.72))
        XCTAssertEqual(fitted.lines.first, "北海道")
        XCTAssertEqual(fitted.lines.count, 2)
        XCTAssertTrue(fitted.lines[1].hasPrefix("（上川郡"))
        XCTAssertTrue(fitted.lines[1].hasSuffix("…"))
        XCTAssertLessThanOrEqual(measure(fitted.lines[1], fitted.size), 140)
    }

    func testTooManySegmentsCollapseIntoLastLine() {
        let fitted = ShareCardText.fit("あいうえお、かきくけこ、さしすせそ、たちつてと", maxWidth: 140,
                                       preferredSize: 26, minimumSize: 18.72,
                                       maxLines: { _ in 3 }, measure: measure)
        XCTAssertLessThanOrEqual(fitted.lines.count, 3)
        XCTAssertEqual(fitted.lines.first, "あいうえお、")
        for line in fitted.lines { XCTAssertLessThanOrEqual(measure(line, fitted.size), 140) }
    }
}
