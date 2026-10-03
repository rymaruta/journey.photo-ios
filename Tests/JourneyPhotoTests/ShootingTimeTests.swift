import XCTest
@testable import JourneyPhoto

/// 探すの「季節・時間帯で絞る」（`ShootingTime`・2026-10-03・戦略の計画6）。
final class ShootingTimeTests: XCTestCase {

    private func photo(_ fields: [String: Any]) throws -> Photo {
        var row = fields
        row["src"] = "https://x/\(fields["id"] ?? "").jpg"
        let data = try JSONSerialization.data(withJSONObject: row)
        return try JSONDecoder.api.decode(Photo.self, from: data)
    }

    private func spot(_ id: String, stage: String = "published", seasons: [String] = [], times: [String]? = nil) throws -> OfficialSpot {
        var row: [String: Any] = ["spotId": id, "slug": id, "name": id, "stage": stage,
                                  "seasonalGuide": seasons.map { ["season": $0, "text": "\($0)の案内"] }]
        if let times { row["timeOfDayGuide"] = times.map { ["time": $0, "text": "\($0)の案内"] } }
        let data = try JSONSerialization.data(withJSONObject: row)
        return try JSONDecoder().decode(OfficialSpot.self, from: data)
    }

    // MARK: - 季節

    /// 季節は撮影日の月（台帳と同じ区切り）。`date` が無ければ EXIF の日付から
    func testSeasonComesFromTheDateTaken() throws {
        XCTAssertEqual(ShootingTime.season(of: try photo(["id": "a", "date": "2026-09-26"])), .autumn)
        XCTAssertEqual(ShootingTime.season(of: try photo(["id": "b", "date": "2026-03-01"])), .spring)
        XCTAssertEqual(ShootingTime.season(of: try photo(["id": "c", "date": "2026-08-31"])), .summer)
        XCTAssertEqual(ShootingTime.season(of: try photo(["id": "d", "date": "2025-12-26T20:43:36"])), .winter)
        XCTAssertEqual(ShootingTime.season(of: try photo(["id": "e", "date": "2026-02-28"])), .winter)
        // アプリが送る EXIF の生の書式（`2026:09:17 19:57:38`）
        XCTAssertEqual(ShootingTime.season(of: try photo(["id": "f", "exif": ["dateTimeOriginal": "2026:05:17 19:57:38"]])), .spring)
    }

    /// 🔴 **撮影日の分からない写真はどの季節にも入れない**（「分からない」を数えない）
    func testUnknownDateHasNoSeason() throws {
        XCTAssertNil(ShootingTime.season(of: try photo(["id": "a"])))
        XCTAssertNil(ShootingTime.season(of: try photo(["id": "b", "date": "2026-13-40"])))
        // 投稿した日（createdAt）は撮影日ではない
        XCTAssertNil(ShootingTime.season(of: try photo(["id": "c", "createdAt": "2026-10-01T00:00:00Z"])))
    }

    /// 南半球の写真は、その土地の季節（半年ずらす）
    func testSouthernHemisphereFlipsTheSeason() throws {
        let sydney = try photo(["id": "a", "date": "2026-07-10", "coords": ["lat": -33.9, "lng": 151.2]])
        XCTAssertEqual(ShootingTime.season(of: sydney), .winter)
        let tokyo = try photo(["id": "b", "date": "2026-07-10", "coords": ["lat": 35.7, "lng": 139.7]])
        XCTAssertEqual(ShootingTime.season(of: tokyo), .summer)
    }

    // MARK: - 時間帯

    /// 区切り: 朝 5〜9・日中 10〜15・夕 16〜18・夜 19〜4（端を確かめる）
    func testDayPartBoundaries() {
        let expected: [(Int, ShootingTime.DayPart)] = [
            (4, .night), (5, .morning), (9, .morning), (10, .day), (15, .day),
            (16, .evening), (18, .evening), (19, .night), (23, .night), (0, .night),
        ]
        for (hour, part) in expected {
            XCTAssertEqual(ShootingTime.DayPart.of(hour: hour), part, "\(hour)時")
        }
        XCTAssertNil(ShootingTime.DayPart.of(hour: 24))
    }

    /// 時間帯は**EXIF の撮影時刻だけ**から。`date` に付いた時刻は使わない（撮った時刻とは限らない）
    func testDayPartUsesOnlyTheCameraTime() throws {
        let exif = try photo(["id": "a", "date": "2026-09-26", "exif": ["dateTimeOriginal": "2026-09-26T16:37:31"]])
        XCTAssertEqual(ShootingTime.dayPart(of: exif), .evening)
        let appExif = try photo(["id": "b", "date": "2026-09-17", "exif": ["dateTimeOriginal": "2026:09:17 19:57:38"]])
        XCTAssertEqual(ShootingTime.dayPart(of: appExif), .night)
        // `date` にだけ時刻（実データの「2023-06-21T19:11:07.000Z」の形）
        let dateOnly = try photo(["id": "c", "date": "2023-06-21T19:11:07.000Z"])
        XCTAssertNil(ShootingTime.dayPart(of: dateOnly))
        // EXIF に日付だけ
        XCTAssertNil(ShootingTime.dayPart(of: try photo(["id": "d", "exif": ["dateTimeOriginal": "2026-09-26"]])))
    }

    /// 🔴 **EXIF の日付が撮影日と食い違えば時刻を使わない**（持ち主が撮影日を直した写真）
    func testMismatchedExifDateIsIgnored() throws {
        let edited = try photo(["id": "a", "date": "2026-09-20", "exif": ["dateTimeOriginal": "2026-09-26T16:37:31"]])
        XCTAssertNil(ShootingTime.dayPart(of: edited))
        // 撮影日が無ければ EXIF の時刻をそのまま使う
        let noDate = try photo(["id": "b", "exif": ["dateTimeOriginal": "2026-09-26T07:10:00"]])
        XCTAssertEqual(ShootingTime.dayPart(of: noDate), .morning)
    }

    // MARK: - 絞り込み

    /// 季節と時間帯は重ねられる（「秋の夕方」）。選んでいない軸は問わない
    func testFilterCombinesSeasonAndDayPart() throws {
        let photos = [
            try photo(["id": "autumnEvening", "date": "2026-09-26", "exif": ["dateTimeOriginal": "2026-09-26T16:37:31"]]),
            try photo(["id": "autumnNoon", "date": "2026-09-23", "exif": ["dateTimeOriginal": "2026-09-23T14:29:02"]]),
            try photo(["id": "autumnUnknownTime", "date": "2024-10-12"]),
            try photo(["id": "summerEvening", "date": "2026-08-07", "exif": ["dateTimeOriginal": "2026-08-07T17:49:56"]]),
            try photo(["id": "bare"]),
        ]
        func ids(_ filter: ShootingTime.Filter) -> [String] { ShootingTime.photos(photos, filter: filter).map(\.id) }
        XCTAssertEqual(ids(.init()), photos.map(\.id), "絞っていないのに落としている")
        XCTAssertEqual(ids(.init(season: .autumn)), ["autumnEvening", "autumnNoon", "autumnUnknownTime"])
        XCTAssertEqual(ids(.init(dayPart: .evening)), ["autumnEvening", "summerEvening"])
        XCTAssertEqual(ids(.init(season: .autumn, dayPart: .evening)), ["autumnEvening"])
        XCTAssertEqual(ids(.init(season: .winter)), [])
    }

    /// 撮影地: 季節は季節の案内、時間帯は時間帯の案内（台帳の6つを4つに寄せる）に文があるもの
    func testSpotsMatchTheirGuides() throws {
        let spots = [
            try spot("momiji", seasons: ["autumn", "winter"], times: ["goldenHour"]),
            try spot("sakura", seasons: ["spring"], times: ["dawn"]),
            try spot("plain"),
        ]
        func ids(_ filter: ShootingTime.Filter) -> [String] { ShootingTime.spots(spots, filter: filter).map(\.spotId) }
        XCTAssertEqual(ids(.init(season: .autumn)), ["momiji"])
        XCTAssertEqual(ids(.init(dayPart: .evening)), ["momiji"], "夕方の斜光は「夕」")
        XCTAssertEqual(ids(.init(dayPart: .morning)), ["sakura"], "夜明けは「朝」")
        XCTAssertEqual(ids(.init(season: .spring, dayPart: .evening)), [])
        XCTAssertEqual(ids(.init()), ["momiji", "sakura", "plain"])
    }

    /// 🔴 **いまの索引は時間帯を載せていない。** 載っていない撮影地は時間帯で絞ると当たらない
    /// （作り話で「夕方の撮影地」と並べない）。季節では今までどおり当たる
    func testSpotsWithoutTimeGuidesDoNotMatchADayPart() throws {
        let indexToday = try spot("momiji", seasons: ["autumn"])
        XCTAssertTrue(indexToday.times.isEmpty)
        XCTAssertTrue(ShootingTime.spots([indexToday], filter: .init(dayPart: .evening)).isEmpty)
        XCTAssertEqual(ShootingTime.spots([indexToday], filter: .init(season: .autumn)).count, 1)
    }

    /// 時間帯の案内は本文と同じく、壊れた項目・知らない時間帯・空の文を落とし、行ごとは落とさない
    func testTimeGuideDecodesLeniently() throws {
        let json = #"{"spotId":"a","slug":"a","name":"A","stage":"published","timeOfDayGuide":[{"time":"night","text":"夜景"},{"time":"noon","text":"?"},{"time":"dusk","text":"  "},{"bad":1}]}"#
        let decoded = try JSONDecoder().decode(OfficialSpot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.times.map(\.time), ["night"])
        let broken = #"{"spotId":"b","slug":"b","name":"B","stage":"published","timeOfDayGuide":"oops"}"#
        XCTAssertEqual(try JSONDecoder().decode(OfficialSpot.self, from: Data(broken.utf8)).times, [])
    }

    /// 行に添える文は選んだ季節の文（無ければ選んだ時間帯の文）
    func testGuideTextFollowsTheFilter() throws {
        let s = try spot("momiji", seasons: ["autumn"], times: ["dusk", "goldenHour"])
        XCTAssertEqual(ShootingTime.guide(for: s, filter: .init(season: .autumn, dayPart: .evening)), "autumnの案内")
        // 時間帯は夜明け→夜の順で先のもの（台帳の並びに頼らない）
        XCTAssertEqual(ShootingTime.guide(for: s, filter: .init(dayPart: .evening)), "goldenHourの案内")
        XCTAssertNil(ShootingTime.guide(for: s, filter: .init()))
    }

    /// 見出しの頭と注記（分け方を隠さない）
    func testPrefixAndNote() {
        XCTAssertEqual(ShootingTime.Filter().prefix, "")
        XCTAssertNil(ShootingTime.Filter().note)
        let both = ShootingTime.Filter(season: .autumn, dayPart: .evening)
        XCTAssertEqual(both.prefix, L("秋・夕方の", "Autumn evening "))
        XCTAssertTrue(both.note?.contains(L("16〜18時", "16–18")) ?? false)
    }

    /// 段を出すのは、季節か時間帯の分かる写真か、案内のある公開済みの撮影地があるときだけ
    func testSectionAppearsOnlyWithSomethingToShow() throws {
        let bare = try photo(["id": "a"])
        XCTAssertFalse(ShootingTime.hasAnything(photos: [bare], spots: [try spot("draft", stage: "review", seasons: ["autumn"])]))
        XCTAssertTrue(ShootingTime.hasAnything(photos: [try photo(["id": "b", "date": "2026-09-26"])], spots: []))
        XCTAssertTrue(ShootingTime.hasAnything(photos: [], spots: [try spot("p", seasons: ["autumn"])]))
    }
}
