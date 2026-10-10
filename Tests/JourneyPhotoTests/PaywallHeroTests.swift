import XCTest
@testable import JourneyPhoto

/// Pro の案内の上の写真（`ProPaywallStyle.heroPhoto`）
final class PaywallHeroTests: XCTestCase {

    private func photo(_ id: String, taken: String? = nil, width: Double? = nil, height: Double? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"/uploads/\(id).jpg\""]
        if let taken { fields.append("\"exif\":{\"dateTimeOriginal\":\"\(taken)\"}") }
        if let width { fields.append("\"width\":\(width)") }
        if let height { fields.append("\"height\":\(height)") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 朝の写真があれば、朝の横長が先
    func testPrefersMorningLandscape() throws {
        let hero = ProPaywallStyle.heroPhoto([
            try photo("evening", taken: "2026:09:19 18:10:00", width: 3000, height: 2000),
            try photo("morningTall", taken: "2026:09:19 06:10:00", width: 2000, height: 3000),
            try photo("morningWide", taken: "2026:09:19 06:20:00", width: 3000, height: 2000),
        ])
        XCTAssertEqual(hero?.id, "morningWide")
    }

    /// 朝の写真が縦長しか無ければ、ほかの時間帯の横長より朝を選ぶ
    func testMorningBeatsOtherTimes() throws {
        let hero = ProPaywallStyle.heroPhoto([
            try photo("evening", taken: "2026:09:19 18:10:00", width: 3000, height: 2000),
            try photo("morningTall", taken: "2026:09:19 06:10:00", width: 2000, height: 3000),
        ])
        XCTAssertEqual(hero?.id, "morningTall")
    }

    /// **朝の写真が1枚も無くても、地の色だけにしない**（時間帯を問わず横長を先に）
    func testFallsBackWhenNoMorningPhoto() throws {
        let hero = ProPaywallStyle.heroPhoto([
            try photo("noTimeTall", width: 2000, height: 3000),
            try photo("eveningWide", taken: "2026:09:19 18:10:00", width: 3000, height: 2000),
        ])
        XCTAssertEqual(hero?.id, "eveningWide")
    }

    /// 写真が無ければ nil（地の色）
    func testEmpty() {
        XCTAssertNil(ProPaywallStyle.heroPhoto([]))
    }
}
