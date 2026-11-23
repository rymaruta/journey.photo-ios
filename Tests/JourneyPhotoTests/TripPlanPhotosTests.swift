import XCTest
@testable import JourneyPhoto

/// 旅行プランが写真で埋まる（札 #710 の案3）。自分の写真だけを、プランのその日の場所に並べる
final class TripPlanPhotosTests: XCTestCase {

    private func photo(_ id: String, spotId: String? = nil, location: String? = nil, date: String?,
                       time: String? = nil) throws -> Photo {
        var obj: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg"]
        if let spotId { obj["spotId"] = spotId }
        if let location { obj["location"] = location }
        if let date { obj["date"] = date }
        if let time, let date { obj["exif"] = ["dateTimeOriginal": "\(date)T\(time)"] }
        return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    /// 観光スポットの場所は `spotId`、撮影地の場所は撮影地の鍵で、**その日に撮った**写真だけ
    func testMatchesBySpotAndDay() throws {
        let mine = [
            try photo("a", spotId: "sp_1", date: "2026-11-23", time: "08:12:00"),
            try photo("b", spotId: "sp_1", date: "2026-11-23", time: "09:40:00"),
            try photo("c", spotId: "sp_1", date: "2026-11-22", time: "10:00:00"),
            try photo("d", location: "渡月橋", date: "2026-11-23"),
        ]
        XCTAssertEqual(TripPlanPhotos.mine(for: .spot(spotId: "sp_1", note: nil), on: "2026-11-23", mine: mine)?.id, "b",
                       "その日のいちばん新しい1枚")
        XCTAssertEqual(TripPlanPhotos.mine(for: .spot(spotId: "sp_1", note: nil), on: "2026-11-22", mine: mine)?.id, "c")
        XCTAssertNil(TripPlanPhotos.mine(for: .spot(spotId: "sp_2", note: nil), on: "2026-11-23", mine: mine))
        XCTAssertEqual(TripPlanPhotos.mine(for: .location(slug: LocationSlug.make("渡月橋"), note: nil),
                                           on: "2026-11-23", mine: mine)?.id, "d")
    }

    /// 日付の無い日は突き合わせない（どの日の写真か言えない）
    func testNoDayNoPhoto() throws {
        let mine = [try photo("a", spotId: "sp_1", date: "2026-11-23")]
        XCTAssertNil(TripPlanPhotos.mine(for: .spot(spotId: "sp_1", note: nil), on: nil, mine: mine))
    }

    /// 点線の枠は、今日の日の、まだ写真の無い観光スポットだけ
    func testInviteOnlyTodayAndOnlySpots() {
        let spot = TripItem.spot(spotId: "sp_1", note: nil)
        XCTAssertTrue(TripPlanPhotos.invites(spot, on: "2026-11-23", today: "2026-11-23", hasPhoto: false))
        XCTAssertFalse(TripPlanPhotos.invites(spot, on: "2026-11-23", today: "2026-11-23", hasPhoto: true))
        XCTAssertFalse(TripPlanPhotos.invites(spot, on: "2026-11-24", today: "2026-11-23", hasPhoto: false))
        XCTAssertFalse(TripPlanPhotos.invites(spot, on: nil, today: "2026-11-23", hasPhoto: false))
        XCTAssertFalse(TripPlanPhotos.invites(.location(slug: "x", note: nil), on: "2026-11-23", today: "2026-11-23",
                                              hasPhoto: false))
    }

    /// 行の下の一行。中黒で区切らない
    func testLine() throws {
        let line = TripPlanPhotos.line(try photo("a", date: "2026-11-23", time: "08:12:00"))
        XCTAssertEqual(line, L("あなたの1枚\u{3000}8:12", "Your photo\u{3000}8:12"))
        XCTAssertFalse(line.contains("・"))
        XCTAssertEqual(TripPlanPhotos.line(try photo("b", date: "2026-11-23")), L("あなたの1枚", "Your photo"))
    }

    /// 行の写真: 自分の写真があればそれ、無ければ観光スポットの写真、どちらも無ければ置かない
    /// （owner 2026-11-23「AIでプラン作った時に画像出てこないぞ」: 作り終えた日程の行にも写真を出す）
    func testThumbPrefersMineThenSpotPhoto() throws {
        let spot = try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            #"{"spotId":"sp_1","slug":"a","name":"宝厳院","stage":"published","image":{"url":"https://journey-photo.com/images/spots/a.jpg","author":"A","license":"CC BY 4.0"}}"#.utf8))
        let mine = try photo("m", spotId: "sp_1", date: "2026-11-23")
        XCTAssertTrue(TripPlanPhotos.thumb(mine: mine, spot: spot)?.isMine == true)
        XCTAssertNotNil(spot.photo, "前提: 観光スポットの写真を読めていない")
        XCTAssertEqual(TripPlanPhotos.thumb(mine: nil, spot: spot)?.isMine, false, "観光スポットの写真が出ていない")
        XCTAssertNil(TripPlanPhotos.thumb(mine: nil, spot: nil), "撮影地だけの行は今の形")
        // 日程の画面は行に写真を渡す（番号の丸の右・作っている途中の行と同じ 44）
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto/Features/Trips")
        let detail = try String(contentsOf: url.appendingPathComponent("TripPlanDetailView.swift"), encoding: .utf8)
        XCTAssertTrue(detail.contains("TripPlanPhotos.thumb(mine: mine, spot: spotFor(item))"))
        let parts = try String(contentsOf: url.appendingPathComponent("TripParts.swift"), encoding: .utf8)
        XCTAssertTrue(parts.contains("TripStopThumbView(thumb: thumb)"))
        XCTAssertEqual(TripStopThumbView.side, 44)
    }

    /// 他人の写真は並べない: 日程の画面は自分の写真（`myPhotos`）だけを渡す
    func testScreenPassesOnlyMyPhotos() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("TripPlanPhotos.mine(for: item, on: ymd, mine: myPhotos)"))
        XCTAssertTrue(text.contains("environment.photos.myPhotos()"))
    }
}
