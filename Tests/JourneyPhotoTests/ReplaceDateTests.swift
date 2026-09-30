import XCTest
@testable import JourneyPhoto

/// 写真の差し替えに載せる撮影日。
///
/// 🔴 サーバーが弾く日付（1990年より前・未来）をそのまま送ると、
/// `photoUpdate.ts` の `dateWasRejected` で**差し替えごと 400** になっていた。
final class ReplaceDateTests: XCTestCase {

    private func utc(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }

    func testNormalDateIsSent() {
        let now = utc("2026-09-30T00:00:00Z")
        XCTAssertEqual(PhotoService.replaceDate("2024-11-01", now: now), "2024-11-01")
        XCTAssertEqual(PhotoService.replaceDate("1990-01-01", now: now), "1990-01-01")
    }

    /// カメラの日付未設定（1970・1980）や 1989年は載せない
    func testBefore1990IsDropped() {
        let now = utc("2026-09-30T00:00:00Z")
        XCTAssertNil(PhotoService.replaceDate("1989-12-31", now: now))
        XCTAssertNil(PhotoService.replaceDate("1980-01-01", now: now))
        XCTAssertNil(PhotoService.replaceDate("1970-01-01", now: now))
    }

    /// 今より24時間先までは通す（サーバーと同じ）。それより先は載せない
    func testFutureBeyondOneDayIsDropped() {
        let now = utc("2026-09-30T12:00:00Z")
        XCTAssertEqual(PhotoService.replaceDate("2026-10-01", now: now), "2026-10-01")
        XCTAssertNil(PhotoService.replaceDate("2026-10-02", now: now))
        XCTAssertNil(PhotoService.replaceDate("2030-01-01", now: now))
    }

    func testMissingOrUnreadableIsNil() {
        XCTAssertNil(PhotoService.replaceDate(nil))
        XCTAssertNil(PhotoService.replaceDate("読めない"))
    }
}
