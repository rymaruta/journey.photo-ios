import XCTest
@testable import JourneyPhoto

/// 日時の文字列の読みを控える直し（2026-11-26・`NotificationGroups.parse`・`ParsedDates`）の試験
final class ParsedDatesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ParsedDates.shared.removeAll()
    }

    /// 🔴 同じ文字列は2回目から読まない（DM の1通を描くたびに 4〜8 回読んでいた）。答えは控える前と同じ
    func testSameTextIsParsedOnce() {
        let text = "2026-11-26T09:30:15.250Z"
        let before = ParsedDates.shared.misses
        let first = NotificationGroups.parse(text)
        for _ in 0..<20 { XCTAssertEqual(NotificationGroups.parse(text), first) }
        XCTAssertEqual(ParsedDates.shared.misses, before + 1, "同じ文字列を何度も読んでいる")
        XCTAssertEqual(first?.timeIntervalSince1970 ?? 0, 1_795_685_415.25, accuracy: 0.001)
        // 小数秒の無い書き方も読める（前と同じ）
        XCTAssertEqual(NotificationGroups.parse("2026-11-26T09:30:15Z")?.timeIntervalSince1970 ?? 0, 1_795_685_415, accuracy: 0.001)
    }

    /// 読めない文字列も「読めない」と控える（日付だけ・空は nil のまま）
    func testUnreadableTextStaysNilAndIsCached() {
        let before = ParsedDates.shared.misses
        for _ in 0..<5 {
            XCTAssertNil(NotificationGroups.parse("2026-11-26"))
            XCTAssertNil(NotificationGroups.parse(""))
        }
        XCTAssertEqual(ParsedDates.shared.misses, before + 2, "読めない文字列を何度も読んでいる")
    }

    /// 増えすぎたら空にする（際限なく増えない）。空にした後も答えは同じ
    func testCacheIsBounded() {
        for i in 0..<(ParsedDates.limit + 10) {
            _ = ParsedDates.shared.value(for: "k\(i)") { nil }
        }
        XCTAssertLessThanOrEqual(ParsedDates.shared.count, ParsedDates.limit)
        XCTAssertEqual(NotificationGroups.parse("2026-01-02T03:04:05Z")?.timeIntervalSince1970 ?? 0, 1_767_323_045, accuracy: 0.001)
    }
}
