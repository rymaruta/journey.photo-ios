import XCTest
@testable import JourneyPhoto

/// ログイン・登録の言い分け（バグ探し 2026-09-27 夕）
final class AuthFlowFixTests: XCTestCase {

    /// 🔴 **ログインで「アカウントが無い」と「違います」を同じ文にする**（Web と同じ）。
    /// 分けると、ログイン画面でアカウントの有無を確かめられる
    func testUserNotFoundReadsLikeWrongPassword() {
        XCTAssertEqual(AuthMessage.text(for: .userNotFound), AuthMessage.text(for: .notAuthorized),
                       "アカウントの有無を漏らしている")
    }

    /// 🔴 **確認の押し直しの NotAuthorized は「もう確認済み」**（成功として扱う）。
    /// 返事が届かなかった回に押し直すと、確認画面から出られなくなっていた
    func testNotAuthorizedOnConfirmMeansAlreadyConfirmed() {
        XCTAssertTrue(AuthFailure.notAuthorized.meansAlreadyConfirmed)
        XCTAssertFalse(AuthFailure.codeMismatch.meansAlreadyConfirmed, "コード違いを成功にしている")
        XCTAssertFalse(AuthFailure.codeExpired.meansAlreadyConfirmed)
        XCTAssertFalse(AuthFailure.network.meansAlreadyConfirmed)
    }
}
