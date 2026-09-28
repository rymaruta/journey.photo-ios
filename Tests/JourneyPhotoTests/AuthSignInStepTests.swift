import XCTest
import Amplify
import AWSCognitoAuthPlugin
@testable import JourneyPhoto

/// ログインの答えの「次の段」（`AuthGateway.outcome`）
final class AuthSignInStepTests: XCTestCase {

    /// 🔴 **パスワードの再設定が要る人を「しばらくしてから」で止めない。** 次の段を捨てていたので、
    /// 待っても押し直しても進めなかった。再設定へ案内する
    func testResetPasswordStepAsksToResetThePassword() {
        XCTAssertThrowsError(try AuthGateway.outcome(of: .resetPassword(nil), isSignedIn: false)) { error in
            XCTAssertEqual(error as? SignInIncomplete, .passwordResetRequired)
            XCTAssertEqual((error as? SignInIncomplete)?.failure, .passwordResetRequired)
        }
        XCTAssertTrue(AuthMessage.text(for: .passwordResetRequired).contains(L("パスワードを忘れた", "Forgot password?")),
                      "画面のボタンの名前で案内していない")
    }

    /// 未確認の人は今までどおり確認へ（`userNotConfirmed` として投げる）
    func testConfirmSignUpStepIsUnconfirmed() {
        XCTAssertThrowsError(try AuthGateway.outcome(of: .confirmSignUp(nil), isSignedIn: false)) { error in
            guard let auth = error as? AuthError else { return XCTFail("AuthError ではない") }
            XCTAssertEqual(AuthFailure(auth), .userNotConfirmed)
        }
    }

    func testDoneReturnsSignedIn() throws {
        XCTAssertTrue(try AuthGateway.outcome(of: .done, isSignedIn: true))
    }
}
