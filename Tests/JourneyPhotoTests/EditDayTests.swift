import XCTest
@testable import JourneyPhoto

/// 写真の編集の撮影日。
///
/// 🔴 以前は EXIF から欄に出して**毎回送っていた**——Web で直した撮影日が
/// EXIF の日付に戻り、時刻付きの撮影日は保存のたびに時刻が落ちていた。
final class EditDayTests: XCTestCase {

    /// 欄は保存されている撮影日から出す
    func testFieldPrefersStoredDate() {
        XCTAssertEqual(EditDay.field(date: "2024-11-01T07:30:00"),
                       "2024-11-01")
        XCTAssertEqual(EditDay.field(date: "2024-11-01"), "2024-11-01")
    }

    /// 保存された撮影日が無い写真は空（EXIF に落とさない——落とすと、
    /// 欄に見えている日付が保存されない。1980年などは保存ごと 400 になる）
    func testFieldIsEmptyWithoutStoredDate() {
        XCTAssertEqual(EditDay.field(date: nil), "")
        XCTAssertEqual(EditDay.field(date: "読めない"), "")
    }

    /// 触っていなければ送らない（時刻が保たれる）
    func testUntouchedDayIsNotSent() {
        let opened = EditDay.field(date: "2024-11-01T07:30:00")
        XCTAssertNil(EditDay.toSend(opened: opened, field: opened))
        XCTAssertNil(EditDay.toSend(opened: opened, field: " 2024-11-01 "))
    }

    func testChangedDayIsSent() {
        XCTAssertEqual(EditDay.toSend(opened: "2024-11-01", field: "2024-11-02"), "2024-11-02")
    }

    /// 🔴 **入っていた日付を消したら空文字を送る**（サーバーは空文字で撮影日を消す）。
    /// 送らずにいたので、消して保存しても黙って残っていた
    func testClearedDayIsSentAsEmpty() {
        XCTAssertEqual(EditDay.toSend(opened: "2024-11-01", field: "  "), "")
    }

    /// もともと無かった日付の欄を空のまま保存しても、何も送らない
    func testEmptyStaysUnsentWhenThereWasNoDay() {
        XCTAssertNil(EditDay.toSend(opened: "", field: " "))
    }
}
