import XCTest
@testable import JourneyPhoto

/// ログイン・登録の言い分け（バグ探し 2026-09-27 夕）
final class AuthFlowFixTests: XCTestCase {

    /// 送り直し・確認で「アカウントが無い」は、そのまま言う（ログインだけ「違います」に寄せる）
    func testUserNotFoundKeepsItsOwnTextOutsideSignIn() {
        XCTAssertNotEqual(AuthMessage.text(for: .userNotFound), AuthMessage.text(for: .notAuthorized),
                          "パスワード欄の無い画面で「パスワードが違います」と言う")
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
