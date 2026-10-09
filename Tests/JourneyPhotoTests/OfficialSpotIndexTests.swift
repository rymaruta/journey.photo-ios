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

    /// 国が「日本」の行は国では当てない（「本」で国内のほぼ全部が当たる）
    func testJapanIsNotMatchedAsCountry() throws {
        let json = "{\"spotId\":\"sp_x\",\"slug\":\"x\",\"name\":\"X\","
            + "\"stage\":\"review\",\"region\":{\"country\":\"日本\",\"prefecture\":\"香川県\"}}"
        let x = try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
        XCTAssertTrue(OfficialSpotIndex.matches([x], query: "本").isEmpty)
    }

    /// 🔴 2026-10-07: 「京都」で**東京都**のスポットが混ざっていた（県＋市をつないだ
    /// 「東京都千代田区」に部分一致）。県名・市区町村名を名前として見る
    func testKyotoDoesNotMatchTokyoTo() throws {
        let spots = [
            try spot("tokyo-station", name: "東京駅", prefecture: "東京都", city: "千代田区"),
            try spot("kiyomizu", name: "清水寺", prefecture: "京都府", city: "京都市東山区"),
            try spot("fukuchiyama", name: "福知山城", prefecture: "京都府", city: "福知山市"),
        ]
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "京都").map(\.slug), ["kiyomizu", "fukuchiyama"])
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "京都府").map(\.slug), ["kiyomizu", "fukuchiyama"])
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "東京").map(\.slug), ["tokyo-station"])
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "千代田").map(\.slug), ["tokyo-station"])
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "東京都千代田区").map(\.slug), ["tokyo-station"])
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "東山").map(\.slug), ["kiyomizu"])
        // 地図のピン・リストの札も同じ当て方（索引を通る）
        XCTAssertEqual(RegionList.filter(photos: [], spots: spots, query: "京都", category: nil).spots.map(\.slug),
                       ["kiyomizu", "fukuchiyama"])
    }

    /// 2026-10-07（レビュー）: 海外の「〜州」「〜地方」と、打ちかけの県名・県と町を並べた語が
    /// 地域で当たらなくなっていた。欄の頭からの一致と、州・地方の切れ目を数える。京都≠東京都は保つ
    func testRegionMatchesPrefixesForeignRegionsAndWords() throws {
        func region(_ country: String?, _ prefecture: String, _ city: String?) throws -> OfficialSpot {
            let c = country.map { "\"country\":\"\($0)\"," } ?? ""
            let ci = city.map { ",\"city\":\"\($0)\"" } ?? ""
            let json = "{\"spotId\":\"sp_r\",\"slug\":\"r\",\"name\":\"R\",\"stage\":\"review\","
                + "\"region\":{\(c)\"prefecture\":\"\(prefecture)\"\(ci)}}"
            return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
        }
        XCTAssertTrue(OfficialSpotIndex.regionMatches(try region("スペイン", "アンダルシア州", "セビリア"), query: "アンダルシア"))
        XCTAssertTrue(OfficialSpotIndex.regionMatches(try region("イタリア", "トスカーナ州", "フィレンツェ"), query: "トスカーナ"))
        XCTAssertTrue(OfficialSpotIndex.regionMatches(try region("フランス", "ブルターニュ地方", nil), query: "ブルターニュ"))
        XCTAssertTrue(OfficialSpotIndex.regionMatches(try region("スペイン", "カタルーニャ州", "バルセロナ"), query: "カタルーニャ州 バルセロナ"))
        let hakone = try region(nil, "神奈川県", "足柄下郡箱根町")
        XCTAssertTrue(OfficialSpotIndex.regionMatches(hakone, query: "神奈"))
        XCTAssertTrue(OfficialSpotIndex.regionMatches(hakone, query: "神奈川 箱根"))
        XCTAssertTrue(OfficialSpotIndex.regionMatches(hakone, query: "箱根"))
        XCTAssertFalse(OfficialSpotIndex.regionMatches(hakone, query: "神奈川 京都"))
        let tokyo = try region(nil, "東京都", "千代田区")
        XCTAssertFalse(OfficialSpotIndex.regionMatches(tokyo, query: "京都"))
        XCTAssertTrue(OfficialSpotIndex.regionMatches(tokyo, query: "東京"))
        XCTAssertTrue(OfficialSpotIndex.regionMatches(try region(nil, "京都府", "京都市"), query: "京都"))
        // 州・地方は切れ目（県＋市をつないだ字の中でも当たる）
        XCTAssertTrue(OfficialSpotIndex.regionMatches(try region("スペイン", "アンダルシア州", "セビリア県"),
                                                      query: "アンダルシア州セビリア"))
        XCTAssertTrue(OfficialSpotIndex.regionMatches(try region("ドイツ", "バイエルン州オーバーバイエルン", nil),
                                                      query: "オーバーバイエルン"))
        XCTAssertTrue(LocationMatch.nameIn("ブルターニュ地方レンヌ", "レンヌ", boundaries: ["州", "地方"]))
        XCTAssertFalse(LocationMatch.nameIn("ブルターニュ地方レンヌ", "レンヌ"))
    }

    /// **名前で当たったものが先。** 地域だけで当たったものはその後ろ
    func testNameMatchesComeFirst() throws {
        let spots = [
            try spot("kagawa-tower", name: "香川タワー", prefecture: "香川県"),
            try spot("a-shrine", name: "神社A", prefecture: "香川県"),
        ]
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "香川").map(\.slug), ["kagawa-tower", "a-shrine"])
    }

    /// 空白・括弧・読点は見ない（Web の `normalizeSpotName`）。スポットの側と打った語の両方
    func testMatchesIgnoreSpacesAndBrackets() throws {
        let spots = [
            try spot("togetsukyo", name: "嵐山 渡月橋"),
            try spot("ginzan", name: "銀山温泉"),
            try spot("garnier", name: "オペラ・ガルニエ（パリ）"),
        ]
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "嵐山渡月橋").map(\.slug), ["togetsukyo"])
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "銀山　温泉").map(\.slug), ["ginzan"])
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "オペラ・ガルニエ (パリ)").map(\.slug), ["garnier"])
        XCTAssertEqual(OfficialSpotIndex.matches([try spot("x", name: "X", prefecture: "香川県", city: "観音寺市")],
                                                 query: "香川県 観音寺").map(\.slug), ["x"])
        XCTAssertTrue(OfficialSpotIndex.matches(spots, query: "（）").isEmpty)
    }

    /// 並びは Web の `searchSpotRows`: 完全一致 → 前方一致 → 部分一致 → 地域。段の中は索引の順（slug 順ではない）
    func testRanksExactThenPrefixThenContainsThenRegion() throws {
        let spots = [
            try spot("z-region", name: "別の場所", prefecture: "滝県"),
            try spot("y-contains", name: "那智の滝"),
            try spot("x-prefix", name: "滝見台"),
            try spot("w-exact", name: "滝"),
            try spot("b-contains", name: "袋田の滝"),
            try spot("a-reading", name: "ほか", reading: "滝の上"),
        ]
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "滝").map(\.slug),
                       ["w-exact", "x-prefix", "a-reading", "y-contains", "b-contains", "z-region"])
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
        let value: Int? = await AsyncTimeout.firstWithin(seconds: 0.05) {
            // 取り消しに応じない遅い処理（地図の検索の代わり）
            await Task.detached { Thread.sleep(forTimeInterval: 1.0) }.value
            return 1
        }
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    /// 間に合えばその答え
    func testFirstWithinReturnsAnEarlyAnswer() async {
        let value: Int? = await AsyncTimeout.firstWithin(seconds: 2) { 7 }
        XCTAssertEqual(value, 7)
    }

    /// 🔴 **時間切れなら、止めた処理がすぐ答えを返しても nil**（2026-10-09）。止めてから門を閉めていた頃は、
    /// 止めた瞬間に返る答え（取り消しに応えて値を返す処理）が先に門を通り、時間切れなのに答えが返った
    /// （手元で `swift test` を3つ並べて流したとき `PlaceCoordsRuleTests` が時々落ちた）。
    /// 「門を閉める」と「止める」の間で、止められた処理が答えを返し終えるまで待ち、その順を必ず作る
    func testTimeoutWinsOverAnswerReturnedOnCancellation() async {
        let returned = DispatchSemaphore(value: 0)
        let value: Int? = await AsyncTimeout.firstWithin(seconds: 0, sleep: { _ in }, betweenTimeoutSteps: {
            // 直す前の順（止める → 閉める）なら、ここに来る前に止められた処理が答えを返している。
            // 直した順（閉める → 止める）では処理はまだ止められていないので、待たずに進む
            if returned.wait(timeout: .now() + 0.05) == .success {
                Thread.sleep(forTimeInterval: 0.02)   // 返した答えが門に届くまで
            }
        }) {
            while !Task.isCancelled { await Task.yield() }
            defer { returned.signal() }
            return 1
        }
        XCTAssertNil(value, "時間切れなのに、止めた処理の答えが返った")
    }

    /// 呼んだ側が取り消されたら、すぐ nil
    func testFirstWithinStopsWhenCancelled() async {
        let task = Task { () -> Int? in
            await AsyncTimeout.firstWithin(seconds: 5) {
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

