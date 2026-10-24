import XCTest
@testable import JourneyPhoto

/// マイページの「旅の記録」の線（`TravelRoute`・案 H1「星図」2026-10-14）。
/// 線と距離が同じ写真・同じ順でつながっていること、形の収め方を見張る
final class TravelRouteTests: XCTestCase {

    private func photo(_ id: String, date: String?, lat: Double?, lng: Double?,
                       location: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        if let location { fields.append("\"location\":\"\(location)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 🔴 **距離と同じ写真・同じ順**（日時の無い写真・座標の無い写真は入れない）
    func testUsesTheSamePhotosAsTheDistance() throws {
        let photos = [
            try photo("c", date: "2026-05-03", lat: 34.69, lng: 135.50),
            try photo("a", date: "2026-05-01", lat: 35.68, lng: 139.76),
            try photo("nodate", date: nil, lat: 25.03, lng: 121.56),
            try photo("nocoords", date: "2026-05-02", lat: nil, lng: nil),
        ]
        let coords = TravelRoute.coordinates(of: photos)
        XCTAssertEqual(coords, [Photo.Coords(lat: 35.68, lng: 139.76), Photo.Coords(lat: 34.69, lng: 135.50)])
        var total = 0.0
        for i in 1..<coords.count { total += TravelDistance.kilometers(from: coords[i - 1], to: coords[i]) }
        XCTAssertEqual(total, TravelDistance.total(of: photos), accuracy: 1e-9)
    }

    /// 線は 0〜1 に収まり、古い順。北が上（緯度が高いほど y が小さい）
    func testShapeFitsTheBoxNorthUp() throws {
        let shape = try XCTUnwrap(TravelRoute.shape(of: [
            Photo.Coords(lat: 35.68, lng: 139.76),  // 東京
            Photo.Coords(lat: 25.03, lng: 121.56),  // 台北
            Photo.Coords(lat: 48.86, lng: 2.35),    // パリ
        ]))
        XCTAssertEqual(shape.points.count, 3)
        for p in shape.points {
            XCTAssertGreaterThanOrEqual(p.x, 0); XCTAssertLessThanOrEqual(p.x, 1)
            XCTAssertGreaterThanOrEqual(p.y, 0); XCTAssertLessThanOrEqual(p.y, 1)
        }
        XCTAssertEqual(shape.points[0].x, 1, accuracy: 1e-9, "東京が一番東")
        XCTAssertEqual(shape.points[2].x, 0, accuracy: 1e-9, "パリが一番西")
        XCTAssertEqual(shape.points[2].y, 0, accuracy: 1e-9, "パリが一番北（上）")
        XCTAssertEqual(shape.points[1].y, 1, accuracy: 1e-9, "台北が一番南（下）")
        // 経度 30° ごと（30・60・90・120）と緯度 10° ごと（30・40）
        XCTAssertEqual(shape.meridians.count, 4)
        XCTAssertEqual(shape.parallels.count, 2)
    }

    /// 🔴 **日付変更線をまたいでも、線が地球の裏を回らない**（東京→ホノルル）
    func testCrossingTheDateLineStaysContinuous() {
        let unwrapped = TravelRoute.unwrapped([Photo.Coords(lat: 35.68, lng: 139.76),
                                               Photo.Coords(lat: 21.31, lng: -157.86)])
        XCTAssertEqual(unwrapped[1].lng, 202.14, accuracy: 1e-9)
    }

    /// 1点だけ・点が無いときは線を出さない
    func testNeedsTwoPoints() {
        XCTAssertNil(TravelRoute.shape(of: []))
        XCTAssertNil(TravelRoute.shape(of: [Photo.Coords(lat: 35, lng: 139)]))
    }

    /// 同じ町の中だけの線は、枠いっぱいに引き伸ばさない（大旅行に見せない）。
    /// 2° の幅に広げて真ん中に置くと点が重なるので、1点にまとまって線は出ない
    func testTinySpanIsNotStretched() {
        XCTAssertNil(TravelRoute.shape(of: [Photo.Coords(lat: 35.680, lng: 139.760),
                                            Photo.Coords(lat: 35.690, lng: 139.770)]))
        let shape = TravelRoute.shape(of: [Photo.Coords(lat: 35.0, lng: 139.0),
                                           Photo.Coords(lat: 35.0, lng: 140.5)])
        XCTAssertEqual(shape?.points.count, 2)
        XCTAssertLessThan(abs((shape?.points[1].x ?? 0) - (shape?.points[0].x ?? 0)), 0.8, "2° の幅の中に置く")
    }

    /// 続けて同じ所の点は1つに。一番新しい点は残す
    func testNearbyPointsMerge() {
        let merged = TravelRoute.deduplicated([CGPoint(x: 0, y: 0), CGPoint(x: 0.001, y: 0),
                                               CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.505, y: 0.5)])
        XCTAssertEqual(merged, [CGPoint(x: 0, y: 0), CGPoint(x: 0.505, y: 0.5)])
    }

    private let box = CGSize(width: 338, height: 52)

    /// 🔴 東へ進む区間は上へ、西へ進む区間は下へふくらむ（往復が目の形に開く）。長いほど大きく、
    /// 頂点は上下の余白（16pt）に収まる
    func testArcBulgesByDirection() {
        let east = TravelRoute.arcControl(from: CGPoint(x: 0.2, y: 0.5), to: CGPoint(x: 0.8, y: 0.5), size: box, band: 16)
        let west = TravelRoute.arcControl(from: CGPoint(x: 0.8, y: 0.5), to: CGPoint(x: 0.2, y: 0.5), size: box, band: 16)
        XCTAssertLessThan(east.y, 0.5, "東へは上")
        XCTAssertGreaterThan(west.y, 0.5, "西へは下")
        XCTAssertEqual(east.x, 0.5, accuracy: 1e-9)
        let short = TravelRoute.arcControl(from: CGPoint(x: 0.45, y: 0.5), to: CGPoint(x: 0.55, y: 0.5), size: box, band: 16)
        XCTAssertLessThan(east.y, short.y, "長い区間ほど高い")
        let most = TravelRoute.arcControl(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 1, y: 0), occurrence: 9, size: box, band: 16)
        // 頂点（曲げの点の半分の高さ）は余白の 16pt まで
        XCTAssertGreaterThanOrEqual(most.y * 52 / 2, -16 - 1e-9)
    }

    /// 🔴 同じ2か所を何度も行き来すると、回ごとに大きくふくらむ（束に潰れない・run 438）
    func testRepeatedLegsFanOut() {
        let jp = CGPoint(x: 1, y: 0.9), eu = CGPoint(x: 0, y: 0.4)
        let controls = TravelRoute.arcControls([jp, eu, jp, eu, jp], size: box, band: 16)
        XCTAssertEqual(controls.count, 4)
        XCTAssertGreaterThan(controls[2].y, controls[0].y, "西へ: 2回目はもっと下")
        XCTAssertLessThan(controls[3].y, controls[1].y, "東へ: 2回目はもっと上")
    }

    /// 間引いても最初と最後の点は残る
    func testThinningKeepsEnds() {
        let many = Array(0..<1000)
        let thin = TravelRoute.thinned(many, limit: 240)
        XCTAssertEqual(thin.count, 240)
        XCTAssertEqual(thin.first, 0)
        XCTAssertEqual(thin.last, 999)
        XCTAssertEqual(TravelRoute.thinned([1, 2, 3], limit: 240), [1, 2, 3])
    }

    /// 国・地域は初めて訪れた順で、数は `VisitedCountries.count` と同じ
    func testCountriesInVisitOrder() throws {
        let photos = [
            try photo("p", date: "2026-03-01", lat: nil, lng: nil, location: "パリ, フランス"),
            try photo("t", date: "2026-01-01", lat: nil, lng: nil, location: "東京, 日本"),
            try photo("f", date: "2026-02-01", lat: nil, lng: nil, location: "台北, 台湾"),
            try photo("t2", date: "2026-04-01", lat: nil, lng: nil, location: "京都, 日本"),
        ]
        let names = TravelRoute.countriesInOrder(photos)
        XCTAssertEqual(names.count, VisitedCountries.count(in: photos))
        XCTAssertEqual(names.first, VisitedCountries.country(in: "東京, 日本"))
        XCTAssertEqual(TravelRoute.countriesLine(["日本", "台湾", "フランス"]), "日本/台湾/フランス")
        XCTAssertTrue(TravelRoute.countriesLine(["a", "b", "c", "d", "e"]).hasSuffix(L(" ほか2", " +2")))
    }

    /// 🔴 国の並びの区切りは「/」（2026-10-24 owner の要望）。日本語・英語とも同じで、前後に空きを入れない。
    /// 4つ以上は今までどおり3つまで＋「ほか N」
    func testCountriesAreSeparatedBySlash() {
        XCTAssertEqual(TravelRoute.countriesSeparator, "/")
        XCTAssertEqual(TravelRoute.countriesLine(["フランス", "スペイン", "イギリス"]), "フランス/スペイン/イギリス")
        XCTAssertEqual(TravelRoute.countriesLine(["France", "Spain", "UK"]), "France/Spain/UK")
        XCTAssertEqual(TravelRoute.countriesLine(["日本"]), "日本")
        XCTAssertEqual(TravelRoute.countriesLine([]), "")
        XCTAssertEqual(TravelRoute.countriesLine(["フランス", "フィンランド", "日本", "台湾"]),
                       "フランス/フィンランド/日本" + L(" ほか1", " +1"))
        for line in [TravelRoute.countriesLine(["フランス", "フィンランド", "日本", "台湾", "韓国"])] {
            XCTAssertFalse(line.contains("・"), "国の並びに「・」が残っている: \(line)")
            XCTAssertFalse(line.contains(", "), "国の並びに「, 」が残っている: \(line)")
        }
    }

    /// 一番古い写真の年
    func testFirstYear() throws {
        let photos = [try photo("b", date: "2025-06-01", lat: 1, lng: 1),
                      try photo("a", date: "2024-11-03", lat: 2, lng: 2)]
        XCTAssertEqual(TravelRoute.firstYear(of: photos), 2024)
    }
}
