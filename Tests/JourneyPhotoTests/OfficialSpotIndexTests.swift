import XCTest
@testable import JourneyPhoto

/// 撮影スポットの索引を**手元で引く**（通信しない）。名前で探す・近くを出す。
final class OfficialSpotIndexTests: XCTestCase {

    private func spot(_ slug: String, name: String, nameEn: String? = nil, reading: String? = nil,
                      prefecture: String? = nil, city: String? = nil,
                      lat: Double? = nil, lng: Double? = nil) throws -> OfficialSpot {
        var json = "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name)\",\"stage\":\"review\""
        if let nameEn { json += ",\"nameEn\":\"\(nameEn)\"" }
        if let reading { json += ",\"reading\":\"\(reading)\"" }
        if prefecture != nil || city != nil {
            let p = prefecture.map { "\"prefecture\":\"\($0)\"" }
            let c = city.map { "\"city\":\"\($0)\"" }
            json += ",\"region\":{\([p, c].compactMap { $0 }.joined(separator: ","))}"
        }
        if let lat, let lng { json += ",\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}" }
        json += "}"
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private func index() throws -> [OfficialSpot] {
        [
            try spot("takaya-jinja", name: "高屋神社", nameEn: "Takaya Shrine", reading: "たかやじんじゃ",
                     prefecture: "香川県", city: "観音寺市", lat: 34.14, lng: 133.68),
            try spot("abashiri-ryuhyo", name: "網走の流氷", nameEn: "Drift Ice of Abashiri", reading: "あばしりのりゅうひょう",
                     prefecture: "北海道", city: "網走市", lat: 44.02, lng: 144.28),
            try spot("kotohira", name: "金刀比羅宮", reading: "ことひらぐう", prefecture: "香川県", city: "仲多度郡琴平町",
                     lat: 34.18, lng: 133.81),
        ]
    }

    /// 空の語は何も当てない（「絞っていない」）
    func testEmptyQueryMatchesNothing() throws {
        XCTAssertTrue(OfficialSpotIndex.matches(try index(), query: "").isEmpty)
        XCTAssertTrue(OfficialSpotIndex.matches(try index(), query: "  \n").isEmpty)
    }

    /// 読み（ひらがな）で当たる
    func testMatchesByReading() throws {
        XCTAssertEqual(OfficialSpotIndex.matches(try index(), query: "たかや").map(\.slug), ["takaya-jinja"])
    }

    /// 全角半角・大小は区別しない（英語名でも）
    func testMatchesIgnoreWidthAndCase() throws {
        XCTAssertEqual(OfficialSpotIndex.matches(try index(), query: "ＴＡＫＡＹＡ").map(\.slug), ["takaya-jinja"])
        XCTAssertEqual(OfficialSpotIndex.matches(try index(), query: "drift ice").map(\.slug), ["abashiri-ryuhyo"])
    }

    /// 県名・市名でも当たる（同じ県のものが並ぶ）
    func testMatchesByPrefectureAndCity() throws {
        XCTAssertEqual(Set(OfficialSpotIndex.matches(try index(), query: "香川").map(\.slug)),
                       ["takaya-jinja", "kotohira"])
        XCTAssertEqual(OfficialSpotIndex.matches(try index(), query: "網走市").map(\.slug), ["abashiri-ryuhyo"])
    }

    /// 海外の行は国名でも当たる（Web の「さがす」と同じ。以前は「フランス」で県・市に
    /// 国名を含む行しか出なかった）
    func testMatchesByCountry() throws {
        let json = "{\"spotId\":\"sp_mont\",\"slug\":\"mont-saint-michel\",\"name\":\"モン・サン＝ミシェル\","
            + "\"stage\":\"review\",\"region\":{\"country\":\"フランス\",\"prefecture\":\"ノルマンディー\"}}"
        let mont = try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
        XCTAssertEqual(OfficialSpotIndex.matches(try index() + [mont], query: "フランス").map(\.slug),
                       ["mont-saint-michel"])
    }

    /// **名前で当たったものが先。** 地域だけで当たったものはその後ろ
    func testNameMatchesComeFirst() throws {
        let spots = [
            try spot("kagawa-tower", name: "香川タワー", prefecture: "香川県"),
            try spot("a-shrine", name: "神社A", prefecture: "香川県"),
        ]
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "香川").map(\.slug), ["kagawa-tower", "a-shrine"])
    }

    func testMatchesStopAtTheLimit() throws {
        let spots = try (0..<15).map { i in try spot("s\(i)", name: "神社\(i)") }
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "神社", limit: 10).count, 10)
    }

    // MARK: - 近くの撮影スポット

    /// 自分を除いて近い順。座標の無い行は出ない。件数は limit まで
    /// （上限の距離を外して測る——並びと件数の見張り）
    func testNearbyIsNearestFirstWithoutSelf() throws {
        var spots = try index()
        spots.append(try spot("nowhere", name: "座標なし"))
        let near = OfficialSpotIndex.nearby(spots[0], in: spots, maxKm: .infinity)
        XCTAssertEqual(near.map(\.spot.slug), ["kotohira", "abashiri-ryuhyo"])
        XCTAssertLessThan(near[0].km, near[1].km)
        XCTAssertEqual(OfficialSpotIndex.nearby(spots[0], in: spots, limit: 1, maxKm: .infinity).count, 1)
    }

    /// 🔴 **遠い場所を「近く」に出さない**（上限 `nearbyMaxKm`）。
    /// 高屋神社から見て金刀比羅宮（約20km）は近く、網走（1,000km 超）は近くではない。
    /// 足りなくても遠い場所で埋めない
    func testNearbyStopsAtTheDistanceCap() throws {
        let spots = try index()
        let near = OfficialSpotIndex.nearby(spots[0], in: spots)
        XCTAssertEqual(near.map(\.spot.slug), ["kotohira"])
        XCTAssertTrue(near.allSatisfy { $0.km <= OfficialSpotIndex.nearbyMaxKm })
        XCTAssertEqual(OfficialSpotIndex.nearbyMaxKm, DerivedSpot.nearbyMaxKm, "写真の撮影地とスポットで「近く」の距離が食い違う")
    }

    /// 境目: 上限の内側（約45km）は出て、外側（約56km）は出ない。値を大きく緩めたら落ちる
    func testNearbyCapBoundary() throws {
        let here = try spot("here", name: "起点", lat: 35.0, lng: 135.0)
        let inside = try spot("inside", name: "内側", lat: 35.4, lng: 135.0)   // 約44km 北
        let outside = try spot("outside", name: "外側", lat: 35.5, lng: 135.0) // 約56km 北
        let near = OfficialSpotIndex.nearby(here, in: [here, inside, outside])
        XCTAssertEqual(near.map(\.spot.slug), ["inside"])
    }

    /// 自分に座標が無ければ測れない
    func testNearbyNeedsCoordinates() throws {
        let nowhere = try spot("nowhere", name: "座標なし")
        XCTAssertTrue(OfficialSpotIndex.nearby(nowhere, in: try index() + [nowhere]).isEmpty)
    }

    /// 🔴 B9: **同じ spotId の札を2つ並べない**（画面は `id: \.spot.id` で並べる）。先勝ち
    func testNearbyDropsDuplicateSpotIds() throws {
        let spots = try index()
        let twin = try spot("kotohira", name: "金刀比羅宮（重複）", lat: 34.18, lng: 133.81)
        let near = OfficialSpotIndex.nearby(spots[0], in: spots + [twin], maxKm: .infinity)
        XCTAssertEqual(near.map(\.spot.spotId), ["sp_kotohira", "sp_abashiri-ryuhyo"])
        XCTAssertEqual(near[0].spot.name, "金刀比羅宮")
    }

    /// 🔴 B9: 索引を読むところでも同じ spotId の2行目を落とし、数に入れる
    func testListDropsDuplicateSpotIds() throws {
        let list = try JSONDecoder.api.decode(LenientOfficialSpotList.self, from: Data("""
        [{"spotId":"sp_a","slug":"a","name":"A","stage":"published"},
         {"spotId":"sp_b","slug":"b","name":"B","stage":"published"},
         {"spotId":"sp_a","slug":"a2","name":"A2","stage":"published"}]
        """.utf8))
        XCTAssertEqual(list.spots.map(\.slug), ["a", "b"])
        XCTAssertEqual(list.dropped, 1)
    }

    /// 🔴 B6: 経路は**丸めた座標のずれ（最大約0.7km）の内側**なら名前で探した地点へ。
    /// 地図で押した地点の拾い直し（0.3km）では、丸めのずれで本物を取りこぼす
    func testDirectionsPicksTheNamedPlaceWithinRoundingError() {
        let rounded = Photo.Coords(lat: 34.14, lng: 133.68)
        // 丸める前は 34.1447, 133.6848 のような位置（約0.65km 離れる）
        let real = Photo.Coords(lat: 34.1447, lng: 133.6848)
        let far = Photo.Coords(lat: 34.20, lng: 133.68)   // 約6.7km 先の同名の別地点
        XCTAssertGreaterThan(TravelDistance.kilometers(from: rounded, to: real), PlaceLookup.sameSpotKm)
        XCTAssertEqual(OfficialSpotIndex.directionsTargetIndex(of: [far, real], near: rounded), 1)
        XCTAssertNil(OfficialSpotIndex.directionsTargetIndex(of: [far], near: rounded))
        XCTAssertNil(OfficialSpotIndex.directionsTargetIndex(of: [], near: rounded))
    }

    /// 🔴 経路の検索の時間切れ。**取り消しに応じない処理でも、待たずに nil を返す**
    func testFirstWithinGivesUpWithoutWaitingForTheOperation() async {
        let start = Date()
        let value: Int? = await OfficialSpotIndex.firstWithin(seconds: 0.05) {
            // 取り消しに応じない遅い処理（地図の検索の代わり）
            await Task.detached { Thread.sleep(forTimeInterval: 1.0) }.value
            return 1
        }
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    /// 間に合えばその答え
    func testFirstWithinReturnsAnEarlyAnswer() async {
        let value: Int? = await OfficialSpotIndex.firstWithin(seconds: 2) { 7 }
        XCTAssertEqual(value, 7)
    }

    /// 呼んだ側が取り消されたら、すぐ nil
    func testFirstWithinStopsWhenCancelled() async {
        let task = Task { () -> Int? in
            await OfficialSpotIndex.firstWithin(seconds: 5) {
                await Task.detached { Thread.sleep(forTimeInterval: 1.0) }.value
                return 1
            }
        }
        task.cancel()
        let start = Date()
        let value = await task.value
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }
}
