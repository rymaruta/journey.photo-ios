import XCTest
@testable import JourneyPhoto

/// 戻るスワイプ途中の `onAppear` で一覧を差し替えない印（`FrontConfirm`）
final class FrontConfirmTests: XCTestCase {

    func testFirstAppearIsConfirmedImmediately() {
        var front = FrontConfirm()
        XCTAssertEqual(front.appear(), .first)
        XCTAssertTrue(front.isConfirmed)
        XCTAssertFalse(front.confirm(), "初回はすでに確定済み")
    }

    /// 戻り appear → すぐ disappear（スワイプキャンセル）では確定しない
    func testReturningAppearNeedsConfirmAndCancelDropsIt() {
        var front = FrontConfirm()
        _ = front.appear()
        front.disappear()
        XCTAssertEqual(front.appear(), .returning)
        XCTAssertFalse(front.isConfirmed)
        front.disappear()
        XCTAssertFalse(front.confirm(), "キャンセル後に確定してはいけない")
        XCTAssertFalse(front.isConfirmed)
    }

    /// 本当に戻った回は confirm で確定する
    func testConfirmAfterReturningAppear() {
        var front = FrontConfirm()
        _ = front.appear()
        front.disappear()
        _ = front.appear()
        XCTAssertTrue(front.confirm())
        XCTAssertTrue(front.isConfirmed)
        XCTAssertFalse(front.confirm(), "二重確定しない")
    }
}
