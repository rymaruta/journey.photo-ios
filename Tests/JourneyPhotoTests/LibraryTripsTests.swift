import XCTest
@testable import JourneyPhoto

/// 端末の写真ライブラリから旅を見つける（`LibraryTrips`）。
/// **ここが間違うと、家の近くの日常の写真が「旅」として並ぶ**——規則ごとに見張る。
final class LibraryTripsTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    /// 2026-09-12 00:00 JST
    private let base = Date(timeIntervalSince1970: 1_789_138_800)

    private let home = (lat: 35.68, lng: 139.76)    // 東京
    private let kyoto = (lat: 35.01, lng: 135.77)   // 約370km
    private let hakone = (lat: 35.23, lng: 139.02)  // 約80km
    private let yokohama = (lat: 35.44, lng: 139.64) // 約29km（旅先ではない）

    /// `hours` は 2026-09-12 00:00 JST からの時間
    private func shot(_ id: String, hours: Double, _ place: (lat: Double, lng: Double)?) -> LibraryShot {
        LibraryShot(id: id, date: base.addingTimeInterval(hours * 3600), lat: place?.lat, lng: place?.lng)
    }

    /// 家で撮った日常の写真（いちばん多い升＝家になる）
    private func homeShots(_ count: Int, startHours: Double = -24 * 30) -> [LibraryShot] {
        (0..<count).map { shot("h\($0)", hours: startHours + Double($0) * 5, home) }
    }

    private func kyotoShots(_ count: Int, startHours: Double = 10, prefix: String = "k") -> [LibraryShot] {
        (0..<count).map { shot("\(prefix)\($0)", hours: startHours + Double($0), kyoto) }
    }

    // MARK: - 家

    /// 家を渡さなければ、位置のある写真でいちばん多い約10kmの升を家とみなす
    func testHomeIsTheBusiestCell() {
        let trips = LibraryTrips.find(homeShots(20) + kyotoShots(6), timeZone: tokyo)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.shots.map(\.id), (0..<6).map { "k\($0)" }, "家の写真が旅に混ざった")
    }

    /// 京都の方が多ければ、京都が家（東京の数枚が旅になる）
    func testHomeFollowsWhereMostPhotosAre() {
        let trips = LibraryTrips.find(kyotoShots(30) + homeShots(5, startHours: 24 * 20), timeZone: tokyo)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(Set(trips.first?.shots.map(\.id) ?? []), Set((0..<5).map { "h\($0)" }))
    }

    /// 渡した家が優先される
    func testGivenHomeWins() {
        let trips = LibraryTrips.find(kyotoShots(30), home: home, timeZone: tokyo)
        XCTAssertEqual(trips.count, 1, "家を渡したのに、京都の写真を家と見なした")
    }

    /// 50km 未満は旅先ではない（横浜の写真だけでは旅にならない）
    func testNearbyIsNotATrip() {
        let near = (0..<8).map { shot("y\($0)", hours: Double($0), yokohama) }
        XCTAssertTrue(LibraryTrips.find(near, home: home, timeZone: tokyo).isEmpty)
    }

    /// 位置のある写真が無ければ旅は決められない
    func testNoLocationNoTrips() {
        let shots = (0..<10).map { shot("n\($0)", hours: Double($0), nil) }
        XCTAssertTrue(LibraryTrips.find(shots, timeZone: tokyo).isEmpty)
    }

    // MARK: - 区切り

    /// 3日（72時間）までの空きは同じ旅。超えたら別の旅
    func testGapOfMoreThanThreeDaysSplits() {
        let a = kyotoShots(5, startHours: 0, prefix: "a")       // 0〜4時間
        let b = kyotoShots(5, startHours: 4 + 72, prefix: "b")  // ちょうど72時間後から
        let c = kyotoShots(5, startHours: 80 + 72.5, prefix: "c") // 72時間を超えて空く
        let trips = LibraryTrips.find(homeShots(40) + a + b + c, home: home, timeZone: tokyo)
        XCTAssertEqual(trips.count, 2, "3日を超えた空きで切れていない")
        XCTAssertEqual(trips.map { $0.shots.count }, [5, 10])
        XCTAssertEqual(trips.first?.shots.first?.id, "c0")
    }

    /// 区切りは TripBook と同じ値を使う
    func testGapIsTripBooks() {
        XCTAssertEqual(TripBook.maxGapDays, 3)
    }

    /// 旅の期間に入る位置の無い写真は含める。期間の外は含めない
    func testUnlocatedShotsInsideTheTripAreIncluded() {
        let trip = kyotoShots(5, startHours: 10)  // 10〜14時間
        let inside = shot("n-in", hours: 12.5, nil)
        let before = shot("n-before", hours: 9, nil)
        let after = shot("n-after", hours: 15, nil)
        let found = LibraryTrips.find(homeShots(10) + trip + [inside, before, after], home: home, timeZone: tokyo)
        XCTAssertEqual(found.count, 1)
        let ids = found.first?.shots.map(\.id) ?? []
        XCTAssertTrue(ids.contains("n-in"), "旅の最中の位置の無い写真が落ちた")
        XCTAssertFalse(ids.contains("n-before"))
        XCTAssertFalse(ids.contains("n-after"))
        XCTAssertEqual(ids, ids.sorted { a, b in
            let order = ["k0", "k1", "k2", "n-in", "k3", "k4"]
            return order.firstIndex(of: a)! < order.firstIndex(of: b)!
        }, "日時順に並んでいない")
    }

    /// 位置の無い写真では5枚に届かせない（旅の写真か確かでない）
    func testUnlocatedShotsDoNotCountTowardTheMinimum() {
        let located = kyotoShots(3, startHours: 0)  // 0〜2時間
        let unlocated = [shot("n1", hours: 0.5, nil), shot("n2", hours: 1.5, nil)]
        XCTAssertTrue(LibraryTrips.find(located + unlocated, home: home, timeZone: tokyo).isEmpty,
                      "位置のある写真3枚を、位置の無い写真で旅にした")
    }

    /// 位置の無い写真は表紙にも、最初の選びにも使わない（一覧には並ぶ）
    func testUnlocatedShotsAreNotCoverOrPicked() throws {
        // 位置の無い写真を真ん中に多く置く（並びの真ん中は位置の無い写真になる）
        let located = kyotoShots(5, startHours: 0)  // 0〜4時間
        let unlocated = (0..<9).map { shot("n\($0)", hours: 1.05 + Double($0) * 0.1, nil) }
        let trip = try XCTUnwrap(LibraryTrips.find(located + unlocated, home: home, timeZone: tokyo).first)
        XCTAssertEqual(trip.shots.count, 14, "位置の無い写真が一覧から落ちた")
        XCTAssertNotNil(trip.cover?.coords, "表紙が位置の無い写真")
        let picked = LibraryTrips.spreadPick(trip, limit: 10)
        XCTAssertEqual(Set(picked), Set(located.map(\.id)), "位置の無い写真を最初から選んだ")
    }

    /// 30日を超えるまとまりは旅にしない（引っ越す前の家で撮りためた何か月も）
    func testLongerThanThirtyDaysIsNotATrip() {
        // 2日おきに撮る: 0, 48, 96 … 時間
        func run(_ count: Int) -> [LibraryShot] {
            (0..<count).map { shot("r\($0)", hours: Double($0) * 48, kyoto) }
        }
        XCTAssertEqual(LibraryTrips.maxDays, 30)
        XCTAssertEqual(LibraryTrips.find(run(16), home: home, timeZone: tokyo).count, 1, "ちょうど30日を落とした")
        XCTAssertTrue(LibraryTrips.find(run(17), home: home, timeZone: tokyo).isEmpty, "32日のまとまりを旅にした")
    }

    /// 5枚未満は旅にしない
    func testFewerThanFiveShotsAreDropped() {
        let trips = LibraryTrips.find(homeShots(10) + kyotoShots(4), home: home, timeZone: tokyo)
        XCTAssertTrue(trips.isEmpty, "4枚の遠出を旅にした")
    }

    /// 新しい旅が先頭
    func testNewestTripFirst() {
        let old = kyotoShots(5, startHours: 0, prefix: "old")
        let hakoneTrip = (0..<5).map { shot("hk\($0)", hours: 24 * 10 + Double($0), hakone) }
        let trips = LibraryTrips.find(hakoneTrip + old, home: home, timeZone: tokyo)
        XCTAssertEqual(trips.map(\.id), ["hk0", "old0"])
    }

    private let sapporo = (lat: 43.06, lng: 141.35)  // 京都からも東京からも遠い

    /// 🔴 引っ越した人: 前の家（東京）から見ると、新しい家（京都）の日常が何か月もつながる。
    /// その中の本当の旅（札幌の3日）は、まとまりの中の仮の家（京都）から探し直して残す
    func testTripInsideMonthsAfterMovingSurvives() throws {
        var shots: [LibraryShot] = []
        for day in 0..<120 where !(50...52).contains(day) {
            shots.append(shot("kyoto\(day)", hours: Double(day) * 24 + 12, kyoto))
        }
        let trip = (0..<6).map { shot("sap\($0)", hours: 50 * 24 + 9 + Double($0) * 12, sapporo) }
        let found = LibraryTrips.find(shots + trip, home: home, timeZone: tokyo)
        XCTAssertEqual(found.count, 1, "引っ越し後の日常の中の旅が消えた")
        XCTAssertEqual(found.first?.shots.map(\.id), trip.map(\.id), "新しい家の日常が旅に混ざった")
    }

    /// 31日以上同じ場所に居続けるまとまりは出ない。探し直しても長すぎるまとまりも出ない（1段だけ）
    func testLongStaysAreNotTripsEvenAfterRetry() {
        let stay = (0..<40).map { shot("stay\($0)", hours: Double($0) * 24 + 12, kyoto) }
        XCTAssertTrue(LibraryTrips.find(stay, home: home, timeZone: tokyo).isEmpty, "40日の滞在を旅にした")
        // 京都に住みつつ、2日おきに札幌へ（札幌のまとまりも40日つながる）
        let commute = (0..<20).map { shot("sap\($0)", hours: Double($0) * 48 + 18, sapporo) }
        XCTAssertTrue(LibraryTrips.find(stay + commute, home: home, timeZone: tokyo).isEmpty,
                      "探し直しても長すぎるまとまりを旅にした")
    }

    /// 引けなかった地名は10分は引き直さない
    func testFailedNameIsNotRetriedForTenMinutes() {
        let failed = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(LibraryTrips.shouldLookUpName(failedAt: nil, now: failed))
        XCTAssertFalse(LibraryTrips.shouldLookUpName(failedAt: failed, now: failed.addingTimeInterval(599)))
        XCTAssertTrue(LibraryTrips.shouldLookUpName(failedAt: failed, now: failed.addingTimeInterval(600)))
    }

    // MARK: - 日

    /// 日ごとの束と「DAY n」の数（撮らなかった日も数に入る）
    func testDaysAreGroupedByLocalDay() {
        let shots = [
            shot("d1a", hours: 10, kyoto), shot("d1b", hours: 20, kyoto),
            // 9/13 は撮っていない
            shot("d3a", hours: 48 + 9, kyoto), shot("d3b", hours: 48 + 23.5, kyoto),
            shot("d4a", hours: 72 + 1, kyoto),
        ]
        let trip = LibraryTrips.find(shots, home: home, timeZone: tokyo).first
        XCTAssertEqual(trip?.days.map(\.key), ["2026-09-12", "2026-09-14", "2026-09-15"])
        XCTAssertEqual(trip?.days.map(\.number), [1, 3, 4])
        XCTAssertEqual(trip?.days.first?.month, 9)
        XCTAssertEqual(trip?.days.first?.day, 12)
        XCTAssertEqual(trip?.days.map { $0.shots.count }, [2, 2, 1])
        XCTAssertEqual(trip?.center?.lat ?? 0, kyoto.lat, accuracy: 0.001)
    }

    /// 期間と日の眉ラベルの書き方
    func testPeriodAndDayLabel() throws {
        let shots = [
            shot("a", hours: 10, kyoto), shot("b", hours: 11, kyoto), shot("c", hours: 12, kyoto),
            shot("d", hours: 48 + 10, kyoto), shot("e", hours: 48 + 11, kyoto),
        ]
        let trip = try XCTUnwrap(LibraryTrips.find(shots, home: home, timeZone: tokyo).first)
        XCTAssertEqual(LibraryTrips.periodText(trip, timeZone: tokyo), "2026.09.12 — 09.14")
        let first = try XCTUnwrap(trip.days.first)
        XCTAssertEqual(LibraryTrips.dayLabel(first, place: "京都市"), "DAY 1 · 9.12 · 京都市")
        XCTAssertEqual(LibraryTrips.dayLabel(first, place: nil), "DAY 1 · 9.12", "地名が無いときは日付だけ")
        let oneDay = try XCTUnwrap(LibraryTrips.find(Array(shots.prefix(3)) + [shot("x", hours: 13, kyoto), shot("y", hours: 14, kyoto)],
                                                     home: home, timeZone: tokyo).first)
        XCTAssertEqual(LibraryTrips.periodText(oneDay, timeZone: tokyo), "2026.09.12")
    }

    // MARK: - 投稿済みの日

    func testPostedDays() throws {
        let shots = (0..<6).map { shot("k\($0)", hours: Double($0) * 12, kyoto) }  // 9/12〜9/14
        let trip = try XCTUnwrap(LibraryTrips.find(shots, home: home, timeZone: tokyo).first)
        XCTAssertEqual(LibraryTrips.postedDays(trip: trip, postedDayKeys: ["2026-09-13", "2026-01-01"]), 1)
        XCTAssertEqual(LibraryTrips.postedDays(trip: trip, postedDayKeys: []), 0)
    }

    /// 投稿の撮影日だけを見る（時刻付きの値も日に丸める・撮影日の無い写真は数えない）
    func testDayKeysOfPostedPhotos() throws {
        func photo(_ id: String, date: String?) throws -> Photo {
            var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                          "\"createdAt\":\"2026-09-20T01:00:00Z\""]
            if let date { fields.append("\"date\":\"\(date)\"") }
            return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
        }
        let keys = LibraryTrips.dayKeys(ofPosted: [
            try photo("a", date: "2026-09-13"),
            try photo("b", date: "2026-09-14T17:46:27"),
            try photo("c", date: nil),
        ])
        XCTAssertEqual(keys, ["2026-09-13", "2026-09-14"])
    }

    // MARK: - 最初に選ぶ写真

    private func trip(dayCounts: [Int]) throws -> LibraryTrip {
        var shots: [LibraryShot] = []
        for (day, count) in dayCounts.enumerated() {
            for i in 0..<count {
                shots.append(shot("d\(day)-\(i)", hours: Double(day) * 24 + 8 + Double(i) * 0.1, kyoto))
            }
        }
        return try XCTUnwrap(LibraryTrips.find(shots, home: home, timeZone: tokyo).first)
    }

    /// 少なければ全部
    func testSpreadPickTakesAllWhenFew() throws {
        let trip = try trip(dayCounts: [3, 3])
        XCTAssertEqual(LibraryTrips.spreadPick(trip, limit: 10).count, 6)
    }

    /// どの日からも選ぶ（1日目が多くても1日目だけで埋めない）
    func testSpreadPickCoversEveryDay() throws {
        let trip = try trip(dayCounts: [40, 2, 3])
        let picked = LibraryTrips.spreadPick(trip, limit: 10)
        XCTAssertEqual(picked.count, 10)
        XCTAssertEqual(picked.filter { $0.hasPrefix("d1-") }.count, 2)
        XCTAssertEqual(picked.filter { $0.hasPrefix("d2-") }.count, 3)
        XCTAssertEqual(picked.filter { $0.hasPrefix("d0-") }.count, 5)
        XCTAssertEqual(picked, picked.sorted { a, b in
            trip.shots.firstIndex { $0.id == a }! < trip.shots.firstIndex { $0.id == b }!
        }, "旅の並びで返っていない")
        // 日の中は均等に（40枚から5枚: 4, 12, 20, 28, 36 枚目）
        XCTAssertEqual(picked.filter { $0.hasPrefix("d0-") }, ["d0-4", "d0-12", "d0-20", "d0-28", "d0-36"])
    }

    /// 日が上限より多ければ、日を均等に飛ばして1日1枚
    func testSpreadPickSkipsDaysEvenly() throws {
        let trip = try trip(dayCounts: [2, 2, 2])
        XCTAssertEqual(LibraryTrips.spreadPick(trip, limit: 2), ["d0-1", "d2-1"], "1日目と3日目から1枚ずつ")
        let long = try self.trip(dayCounts: Array(repeating: 1, count: 12))
        let picked = LibraryTrips.spreadPick(long, limit: 10)
        XCTAssertEqual(picked.count, 10)
        XCTAssertEqual(Set(picked).count, 10, "同じ日から2枚選んだ")
    }

    // MARK: - 地名を引く座標

    /// Apple の地図へ渡すのは約1km（小数第2位）に丸めた座標だけ
    func testLookupIsRoundedToAboutOneKilometer() {
        let rounded = LibraryTrips.roundedForLookup(Photo.Coords(lat: 35.01234, lng: 135.76789))
        XCTAssertEqual(rounded.lat, 35.01, accuracy: 1e-9)
        XCTAssertEqual(rounded.lng, 135.77, accuracy: 1e-9)
        XCTAssertEqual(LibraryTrips.lookupKey(Photo.Coords(lat: 35.0149, lng: 135.7651)), "35.01,135.77")
    }

    // MARK: - 選ぶ・外す

    func testToggleRespectsTheLimit() {
        var result = LibraryTrips.toggle("a", in: [], limit: 2)
        XCTAssertEqual(result.selected, ["a"])
        result = LibraryTrips.toggle("b", in: result.selected, limit: 2)
        result = LibraryTrips.toggle("c", in: result.selected, limit: 2)
        XCTAssertEqual(result.selected, ["a", "b"])
        XCTAssertTrue(result.overLimit, "上限を超えて選べた")
        result = LibraryTrips.toggle("a", in: result.selected, limit: 2)
        XCTAssertEqual(result.selected, ["b"])
        XCTAssertFalse(result.overLimit)
    }
}
