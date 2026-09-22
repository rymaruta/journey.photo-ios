import XCTest
@testable import JourneyPhoto

/// 撮影日の出し方。
final class TakenDayTests: XCTestCase {

    /// 🔴 **生の値を出さない。** 実機の絵に `2026-09-19T17:46:27` と
    /// 出ていた（run 51）。時刻まで入っている行が実在する
    func testTimestampIsNotShownRaw() {
        let label = TakenDay.label("2026-09-19T17:46:27", locale: "ja")
        XCTAssertEqual(label, "2026年9月19日")
        XCTAssertFalse(label?.contains("T") ?? true)
        XCTAssertFalse(label?.contains(":") ?? true)
    }

    func testPlainDay() {
        XCTAssertEqual(TakenDay.label("2024-05-12", locale: "ja"), "2024年5月12日")
        XCTAssertEqual(TakenDay.label("2024-05-12", locale: "en"), "May 12, 2024")
    }

    /// **読めない値は出さない**（生のまま出すくらいなら出さない）
    func testUnreadableValuesAreDropped() {
        XCTAssertNil(TakenDay.label(nil))
        XCTAssertNil(TakenDay.label(""))
        XCTAssertNil(TakenDay.label("きのう"))
        XCTAssertNil(TakenDay.label("2024/05/12"))
    }

    /// **月日の妥当さまで見る。** 「13月40日」と書かない
    func testImpossibleMonthOrDayIsDropped() {
        XCTAssertNil(TakenDay.label("2026-13-01"))
        XCTAssertNil(TakenDay.label("2026-01-40"))
        XCTAssertNil(TakenDay.label("2026-00-10"))
    }

    /// 写真が生まれる前の年は出さない（`1826` は最初の写真の年）
    func testYearsBeforePhotographyAreDropped() {
        XCTAssertNil(TakenDay.label("1500-01-01"))
        XCTAssertNotNil(TakenDay.label("1826-01-01"))
    }
}

/// 名前の出し方。
final class UnnamedUserTests: XCTestCase {

    /// 🔴 **利用者 ID を名前として出さない。** 実機の絵（run 51）に
    /// `d7e4da78` と人の名前の場所に出ていた
    func testProfileWithoutNamesDoesNotShowTheId() throws {
        let p = try JSONDecoder.api.decode(UserProfile.self, from: Data(
            #"{"userId":"d7e4da78-1111-2222-3333-444444444444"}"#.utf8))
        XCTAssertEqual(p.name, Labels.Common.unnamedUser)
        XCTAssertFalse(p.name.contains("d7e4da78"))
    }

    /// 名前があればそれを出す（ユーザー名でも代用する）
    func testNamesAreUsedWhenPresent() throws {
        let named = try JSONDecoder.api.decode(UserProfile.self, from: Data(
            #"{"userId":"u1","displayName":"ゆき"}"#.utf8))
        XCTAssertEqual(named.name, "ゆき")
        let handle = try JSONDecoder.api.decode(UserProfile.self, from: Data(
            #"{"userId":"u1","username":"yuki_travel"}"#.utf8))
        XCTAssertEqual(handle.name, "yuki_travel")
    }

    /// ストーリーの投稿者も同じ（同じ言葉に揃える）
    func testStoryAuthorDoesNotShowTheId() throws {
        let story = try JSONDecoder.api.decode(Story.self, from: Data(
            #"{"id":"s1","src":"/uploads/s1.jpg","userId":"d7e4da78-1111"}"#.utf8))
        XCTAssertEqual(story.authorName, Labels.Common.unnamedUser)
    }
}
