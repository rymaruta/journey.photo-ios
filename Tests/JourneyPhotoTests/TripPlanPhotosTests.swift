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

    /// 行の写真は飾り（読み上げから外す）。行をまとめると中の識別子は消えるので、写真の種類は**行の識別子**で出す
    /// （UI テスト `testCapturesTripPlanStopPhotos` が見つけられず、何も撮らずに抜けていた・2026-11-23 確かめ役の指摘）
    func testRowIdentifierTellsThePhotoKind() throws {
        let spot = try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            #"{"spotId":"sp_1","slug":"a","name":"宝厳院","stage":"published","image":{"url":"https://journey-photo.com/images/spots/a.jpg","author":"A","license":"CC BY 4.0"}}"#.utf8))
        let mine = try photo("m", spotId: "sp_1", date: "2026-11-23")
        XCTAssertEqual(TripStopLabel.identifier(TripPlanPhotos.thumb(mine: nil, spot: spot)), "tripPlan.stopSpotPhoto")
        XCTAssertEqual(TripStopLabel.identifier(TripPlanPhotos.thumb(mine: mine, spot: spot)), "tripPlan.stopPhoto")
        XCTAssertEqual(TripStopLabel.identifier(nil), "tripPlan.stop")
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto/Features/Trips")
        let parts = try String(contentsOf: url.appendingPathComponent("TripParts.swift"), encoding: .utf8)
        XCTAssertTrue(parts.contains(".accessibilityIdentifier(Self.identifier(thumb))"), "行に写真の種類の識別子を付けていない")
        let ui = try String(contentsOf: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"), encoding: .utf8)
        XCTAssertTrue(ui.contains(#"["tripPlan.stopSpotPhoto", "tripPlan.stopPhoto"]"#), "UI テストが行の識別子で探していない")
        // 足した試験を既存の試験の注記と関数の間に入れない（注記がその関数の真上にある）
        XCTAssertTrue(ui.contains("（札 #531）\n    func testCapturesSpotAutoNotice()"), "撮影スポットの自動の試験の注記が離れている")
        XCTAssertTrue(ui.contains("（この iPhone に覚えるため）\n    func testCapturesTripPlanTimes()"), "日程の時刻の試験の注記が離れている")
    }

    /// 他人の写真は並べない: 日程の画面は自分の写真（`myPhotos`）だけを渡す
    func testScreenPassesOnlyMyPhotos() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("TripPlanPhotos.mine(for: item, on: ymd, mine: myPhotos)"))
        XCTAssertTrue(text.contains("environment.photos.myPhotos()"))
        // 🔴 読んだ写真は持ち主を `PhotoOwnership` で確かめてから入れる（2026-11-23・他人の写真は、その人のもの）
        XCTAssertEqual(text.components(separatedBy: "myPhotos = PhotoOwnership.mine(mine, me: auth.userId)").count - 1, 2,
                       "自分の写真の読み込みが持ち主を確かめていない")
        XCTAssertFalse(text.contains("if let mine { myPhotos = mine }"), "持ち主を確かめずに入れている")
    }

    /// 持ち主の確かめ（`PhotoOwnership.mine`）: 自分の写真だけ残り、他人の写真・持ち主の分からない写真は落ちる
    func testOwnershipKeepsOnlyMine() throws {
        func row(_ id: String, _ owner: String?) throws -> Photo {
            var obj: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg", "spotId": "sp_1", "date": "2026-11-23"]
            if let owner { obj["userId"] = owner }
            return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: obj))
        }
        let loaded = [try row("me1", "me"), try row("other", "mika"), try row("unknown", nil)]
        let kept = PhotoOwnership.mine(loaded, me: "me")
        XCTAssertEqual(kept.map(\.id), ["me1"])
        XCTAssertTrue(PhotoOwnership.mine(loaded, me: nil).isEmpty, "ログインしていないのに写真を入れた")
        XCTAssertEqual(TripPlanPhotos.mine(for: .spot(spotId: "sp_1", note: nil), on: "2026-11-23", mine: kept)?.id, "me1")
    }
}
