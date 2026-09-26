import XCTest
@testable import JourneyPhoto

/// 「旅した距離」。**実際に移動した距離ではない**（指示書 8-3）。
/// Web（`lib/utils/journey.ts` の `haversineKm`）と同じ計算かを見張る。
final class TravelDistanceTests: XCTestCase {

    private func photo(_ id: String, date: String?, created: String? = nil,
                       lat: Double?, lng: Double?) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let created { fields.append("\"createdAt\":\"\(created)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 東京→大阪はおよそ 400km（大円距離）。Web と同じ式かを確かめる
    func testKnownDistance() {
        let tokyo = Photo.Coords(lat: 35.68, lng: 139.76)
        let osaka = Photo.Coords(lat: 34.69, lng: 135.50)
        let km = TravelDistance.kilometers(from: tokyo, to: osaka)
        XCTAssertEqual(km, 400, accuracy: 15)
    }

    /// 古い順につなぐ（並びが変われば距離も変わる）
    func testConnectsOldestFirst() throws {
        let photos = [
            try photo("new", date: "2026-05-03", lat: 34.69, lng: 135.50),
            try photo("old", date: "2026-05-01", lat: 35.68, lng: 139.76),
        ]
        XCTAssertEqual(TravelDistance.total(of: photos), 400, accuracy: 15)
    }

    /// **座標の無い写真は数えない**（撮っていない区間は飛ぶ）
    func testPhotosWithoutCoordsAreSkipped() throws {
        let photos = [
            try photo("a", date: "2026-05-01", lat: 35.68, lng: 139.76),
            try photo("none", date: "2026-05-02", lat: nil, lng: nil),
            try photo("b", date: "2026-05-03", lat: 34.69, lng: 135.50),
        ]
        XCTAssertEqual(TravelDistance.total(of: photos), 400, accuracy: 15)
    }

    /// **日時の読めない写真も入れない。** つなぐ順が決まらない写真を
    /// 「いちばん古い場所」として数えると、そこから1脚ぶん距離が増える
    /// （Web 側が踏んでいる穴）
    func testPhotosWithoutADateAreSkipped() throws {
        let photos = [
            try photo("a", date: "2026-05-01", lat: 35.68, lng: 139.76),
            try photo("b", date: "2026-05-02", lat: 34.69, lng: 135.50),
            try photo("undated", date: nil, lat: 60.17, lng: 24.94),
        ]
        XCTAssertEqual(TravelDistance.total(of: photos), 400, accuracy: 15)
    }

    /// **並びは Web の `compareOldest` と同じ**（`app/users/UserProfileClient.tsx` の
    /// `footprint`）。キーは `date || createdAt` を文字列のまま比べるので、
    /// 日付だけの撮影日（`2026-05-02`）は同じ日の投稿日時（`2026-05-02T03:00:00Z`）
    /// より先に来る。**端末の時刻帯では変わらない**——旅の一冊の並び
    /// （`TripBook.inOrder`）でつなぐと、東京とロサンゼルスで順が変わり、
    /// 同じ写真のプロフィールの距離が見る端末で変わっていた（レビューの指摘）
    func testOrderMatchesTheWebAndIgnoresTheTimeZone() throws {
        let tokyo = Photo.Coords(lat: 35.68, lng: 139.76)
        let osaka = Photo.Coords(lat: 34.69, lng: 135.50)
        let helsinki = Photo.Coords(lat: 60.17, lng: 24.94)
        let paris = Photo.Coords(lat: 48.86, lng: 2.35)
        let photos = [
            try photo("d", date: nil, created: "2026-05-02T20:00:00.000Z", lat: paris.lat, lng: paris.lng),
            try photo("b", date: nil, created: "2026-05-02T03:00:00.000Z", lat: helsinki.lat, lng: helsinki.lng),
            try photo("a", date: "2026-05-02", created: "2026-05-03T00:00:00.000Z", lat: osaka.lat, lng: osaka.lng),
            try photo("c", date: "2026-05-01", lat: tokyo.lat, lng: tokyo.lng),
        ]
        // 前提: この組は旅の一冊の並びだと時刻帯で順が変わる（効いている組か）
        let inTokyo = TripBook.inOrder(photos, timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo")))
        let inLA = TripBook.inOrder(photos, timeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")))
        XCTAssertNotEqual(inTokyo.map(\.id), inLA.map(\.id))

        // Web: "2026-05-01" < "2026-05-02" < "2026-05-02T03:00:00" < "2026-05-02T20:00:00"
        XCTAssertEqual(TravelDistance.webOldestFirst(photos).map(\.id), ["c", "a", "b", "d"])
        let expected = TravelDistance.kilometers(from: tokyo, to: osaka)
            + TravelDistance.kilometers(from: osaka, to: helsinki)
            + TravelDistance.kilometers(from: helsinki, to: paris)
        XCTAssertEqual(TravelDistance.total(of: photos), expected, accuracy: 0.001)
        XCTAssertEqual(TravelDistance.total(of: photos.reversed()), expected, accuracy: 0.001,
                       "入力の順で変わらない")
    }

    /// 同じキーは投稿日時の古い順 → id の昇順（Web の `tieBreak`）。
    /// ゾーン指定子の違い（`Z` の有無）ではキーが変わらない
    func testTiesFollowTheWebTieBreak() throws {
        let photos = [
            try photo("z", date: "2026-05-02T09:00:00Z", created: "2026-05-04T00:00:00.000Z", lat: 1, lng: 1),
            try photo("y", date: "2026-05-02T09:00:00", created: "2026-05-03T00:00:00.000Z", lat: 2, lng: 2),
            try photo("x", date: "2026-05-02T09:00:00", created: "2026-05-03T00:00:00.000Z", lat: 3, lng: 3),
            try photo("w", date: "", created: "2026-05-02T08:00:00.000Z", lat: 4, lng: 4),
        ]
        let ordered = TravelDistance.webOldestFirst(photos)
        XCTAssertEqual(ordered.map(\.id), ["w", "x", "y", "z"])
        XCTAssertEqual(TravelDistance.total(of: photos), TravelDistance.connect(ordered), accuracy: 0.001)
    }

    /// 1点だけ、あるいは0点なら 0（区間が無い）
    func testFewerThanTwoPointsIsZero() throws {
        XCTAssertEqual(TravelDistance.total(of: []), 0)
        XCTAssertEqual(TravelDistance.total(of: [try photo("a", date: "2026-05-01", lat: 1, lng: 1)]), 0)
    }

    func testFormatsWithSeparators() {
        XCTAssertEqual(TravelDistance.formatted(74164.4), "74,164")
    }
}
