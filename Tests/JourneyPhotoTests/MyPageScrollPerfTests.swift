import XCTest
@testable import JourneyPhoto

/// マイページ（と人のページ）の縦の送りの重さの直し（2026-10-28・owner 実機 1.1.43「音楽を流していないときも重い」）。
/// 札の行の位置を毎フレーム状態に書いていた件（①）は `claude/music-playback-perf` 側の直し（`ProfileTabRowSpot`）。
/// 見た目・振る舞いは変えない。画面は Linux では描けないので、計算は型で・配線はソースの形で押さえる
/// （直しを戻すと落ちる）
final class MyPageScrollPerfTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func photo(_ id: String, date: String? = nil, created: String? = nil, lat: Double? = nil, lng: Double? = nil,
                       location: String? = nil, groupId: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"u1\""]
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let created { fields.append("\"createdAt\":\"\(created)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        if let location { fields.append("\"location\":\"\(location)\"") }
        if let groupId { fields.append("\"groupId\":\"\(groupId)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    // MARK: ② 旅の記録の数え直し

    private func sample() throws -> [Photo] {
        [
            try photo("b", date: "2026-05-02T10:00:00+09:00", lat: 34.69, lng: 135.50, location: "日本 大阪"),
            try photo("a", date: "2026-05-02", created: "2026-05-03T00:00:00Z", lat: 35.68, lng: 139.76, location: "日本 東京",
                      groupId: "g1"),
            try photo("c", created: "2025-12-31T23:00:00Z", lat: 48.86, lng: 2.35, location: "パリ, France", groupId: "g1"),
            try photo("d", date: "2026-05-02", created: "2026-05-02T00:00:00Z", location: "南アフリカ ケープタウン"),
            try photo("e", location: "中国地方 広島"),
            try photo("f", date: "2024-01-01Z", lat: 25.03, lng: 121.56, location: "Taiwan"),
            try photo("g", date: "2026-05-02", created: "2026-05-02T00:00:00Z", lat: 1, lng: 1),
        ]
    }

    /// 🔴 マイページの旅の記録は控えから（同じ写真で描き直しても数え直さない）。複数枚の印も同じ
    func testTravelSummaryAndMultipleAreMemoized() throws {
        let memo = MyPageTabMemo()
        let photos = try sample()
        let first = memo.travelSummary(photos)
        XCTAssertEqual(memo.travelSummary(photos), first)
        XCTAssertEqual(memo.travelSummary(photos), first)
        XCTAssertEqual(memo.travel.computeCount, 1, "同じ写真で旅の記録を数え直している")
        XCTAssertEqual(first, ProfileTravelRecord.Summary(photos: photos), "控えの答えが違う")
        _ = memo.travelSummary(Array(photos.dropLast()))
        XCTAssertEqual(memo.travel.computeCount, 2, "写真が変わったのに前の答えを返している")

        XCTAssertEqual(memo.multiPhotoIds(photos), PhotoGroups.multiPhotoIds(photos))
        _ = memo.multiPhotoIds(photos)
        XCTAssertEqual(memo.multiple.computeCount, 1)
        XCTAssertEqual(memo.multiPhotoIds(photos), ["a", "c"])

        let view = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        XCTAssertFalse(view.contains("ProfileTravelRecord.Summary(photos: model.photos)"), "描き直しのたびに旅の記録を数えている")
        XCTAssertFalse(view.contains("PhotoGroups.multiPhotoIds(model.photos)"), "描き直しのたびに複数枚を数えている")
        XCTAssertTrue(view.contains("let summary = tabMemo.travelSummary(model.photos)"))
        XCTAssertTrue(view.contains("let multiple = tabMemo.multiPhotoIds(model.photos)"))
    }

    /// 人のページの旅の記録・棚も控えから（写真かブロックが変わったときだけ）
    func testOthersTravelIsMemoized() throws {
        let memo = OthersTravelMemo()
        let photos = try sample()
        XCTAssertEqual(memo.othersSummary(photos, blocked: false), ProfileTravelRecord.othersSummary(photos, blocked: false))
        _ = memo.othersSummary(photos, blocked: false)
        XCTAssertEqual(memo.summary.computeCount, 1)
        XCTAssertTrue(memo.othersSummary(photos, blocked: true).isEmpty)
        XCTAssertEqual(memo.summary.computeCount, 2, "ブロックしたのに前の答えを返している")
        _ = memo.othersShelf(photos, blocked: false)
        _ = memo.othersShelf(photos, blocked: false)
        XCTAssertEqual(memo.shelf.computeCount, 1)
    }

    /// 🔴 並べ替えを1回にした数え方が、今までの別々の数え方と同じ答え
    func testSummarySharesOneSortWithTheSameResult() throws {
        let photos = try sample()
        let summary = ProfileTravelRecord.Summary(photos: photos)
        XCTAssertEqual(summary.kilometers, TravelDistance.total(of: photos))
        XCTAssertEqual(summary.coordinates, TravelRoute.coordinates(of: photos))
        XCTAssertEqual(summary.firstYear, TravelRoute.firstYear(of: photos))
        XCTAssertEqual(summary.countries, TravelRoute.countriesInOrder(photos))
        XCTAssertEqual(summary.firstYear, 2024)
        // 日時の無い写真（鍵が空）がいちばん古い。「中国地方」は「中国」に当たる（今までの決まりのまま）
        XCTAssertEqual(summary.countries, ["中国", "台湾", "フランス", "南アフリカ", "日本"])
        // 並べ替えの比べ方の中で正規表現を走らせない（並べる前に写真ごとに1回）
        let distance = try source("Sources/JourneyPhoto/Core/Text/TravelDistance.swift")
        let sort = String(distance[try XCTUnwrap(distance.range(of: "static func webOldestFirst")).lowerBound...].prefix(900))
        XCTAssertFalse(sort.contains("stripZone(lhs"), "比べるたびにゾーンを落としている")
        XCTAssertFalse(sort.contains("timeKey(lhs)"), "比べるたびに鍵を作っている")
    }

    /// 国の表は1度だけ長い順に並べる（写真ごとに並べ直さない）。当たる国は同じ
    func testCountryTableIsSortedOnce() throws {
        let sorted = VisitedCountries.table.sorted { max($0.ja.count, $0.en.count) > max($1.ja.count, $1.en.count) }
        XCTAssertEqual(VisitedCountries.longestFirst.map(\.ja), sorted.map(\.ja))
        XCTAssertEqual(VisitedCountries.country(in: "南アフリカ ケープタウン"), "南アフリカ")
        XCTAssertEqual(VisitedCountries.country(in: "United Arab Emirates, Dubai"), "アラブ首長国連邦")
        XCTAssertNil(VisitedCountries.country(in: "山中湖"))
        let text = try source("Sources/JourneyPhoto/Core/Text/VisitedCountries.swift")
        let lookup = String(text[try XCTUnwrap(text.range(of: "static func country(in text: String)")).lowerBound...].prefix(300))
        XCTAssertFalse(lookup.contains(".sorted"), "写真ごとに表を並べ直している")
    }

    // MARK: ⑤ 端末の一冊の見張り

    /// 端末の一冊の店を見張るのは旅の記録の札の中だけ（マイページ全体を描き直さない）
    func testDeviceTripsIsObservedOnlyInsideTheTripsTab() throws {
        let view = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        XCTAssertFalse(view.contains("@ObservedObject private var deviceTrips"), "マイページ全体が端末の一冊を見張っている")
        XCTAssertTrue(view.contains("private struct MyPageTripsShelf<Tools: View>: View {\n    @ObservedObject var deviceTrips: DeviceTripShelfStore"))
        XCTAssertTrue(view.contains("MyPageTripsShelf(deviceTrips: deviceTrips,"))
        // 「まだ旅はありません」を出す決まりは今までどおり（投稿した一冊が0で端末の一冊があるときは出さない）
        XCTAssertTrue(view.contains("if !trips.isEmpty || !hasDeviceBooks {\n                TripShelfList(trips: trips, isPublic: isPublic)"))
    }
}
