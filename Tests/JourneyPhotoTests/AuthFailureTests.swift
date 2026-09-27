import XCTest
import Amplify
import AWSCognitoAuthPlugin
@testable import JourneyPhoto

/// Cognito の失敗の種類。
///
/// **綴りで照合していたので、どの分岐も一度も当たらなかった。**
/// Amplify Swift が持っているのは `AWSCognitoAuthError`（lowerCamel の
/// `userNotConfirmed`）で、Web から写した `UserNotConfirmedException` とは
/// 別物——`String(describing:)` に含まれないので、
/// 「未確認だから確認画面へ送る」も「すでに登録されている＝確認前の自分」も
/// **本番で一度も走らない**状態だった。型で見れば綴りに依存しない。
final class AuthFailureTests: XCTestCase {

    private func service(_ cognito: AWSCognitoAuthError) -> AuthError {
        .service("", "", cognito)
    }

    func testUnconfirmedAccountIsRecognised() {
        XCTAssertEqual(AuthFailure(service(.userNotConfirmed)), .userNotConfirmed)
    }

    func testExistingAccountIsRecognised() {
        XCTAssertEqual(AuthFailure(service(.usernameExists)), .usernameExists)
        XCTAssertEqual(AuthFailure(service(.aliasExists)), .aliasExists)
    }

    /// 種別が入っていない回は、`AuthError` そのものの種類で見る。
    func testNotAuthorizedWithoutCognitoDetail() {
        XCTAssertEqual(AuthFailure(.notAuthorized("", "", nil)), .notAuthorized)
    }

    /// 退会の押し直し: Cognito 側で消えていれば「消せた」扱い。
    /// **通信や認可の失敗まで「消せた」にしない**——アカウントが残ったまま
    /// サインアウトさせてしまう
    func testOnlyMissingUserCountsAsAlreadyDeleted() {
        XCTAssertTrue(AuthFailure(service(.userNotFound)).meansUserAlreadyGone)
        XCTAssertFalse(AuthFailure(service(.network)).meansUserAlreadyGone)
        XCTAssertFalse(AuthFailure(.notAuthorized("", "", nil)).meansUserAlreadyGone)
        XCTAssertFalse(AuthFailure(service(.limitExceeded)).meansUserAlreadyGone)
    }

    /// **回数制限は「恒久的」ではない**——ここで控えを捨てると、
    /// 確認画面に二度と戻れない（Web が踏んだ穴）。
    func testOnlyPermanentFailuresAllowForgettingThePendingEntry() {
        XCTAssertTrue(AuthFailure(service(.userNotFound)).isPermanent)
        XCTAssertTrue(AuthFailure(.notAuthorized("", "", nil)).isPermanent)
        XCTAssertFalse(AuthFailure(service(.limitExceeded)).isPermanent)
        XCTAssertFalse(AuthFailure(service(.network)).isPermanent)
    }

    /// 文言は種類から引く（言い回しを直しても判定は壊れない）。
    func testMessagesAreChosenByKind() {
        XCTAssertEqual(AuthMessage.text(for: .codeMismatch),
                       AuthMessage.text(for: AuthFailure(service(.codeMismatch))))
        XCTAssertNotEqual(AuthMessage.text(for: .codeMismatch), AuthMessage.text(for: .network))
    }
}

/// 退会の確認語。
final class DeleteConfirmWordTests: XCTestCase {

    /// **大小を区別しない。** 英語側は `DELETE` だが、入力欄は自動大文字化を
    /// 切ってあるので `delete` と打つ人が出る——灰色のまま理由も出ない画面に
    /// しない（審査 5.1.1(v) を見るのはたいてい英語の審査官）。
    func testTypedWordIsAcceptedRegardlessOfCase() {
        let word = Locale.preferredAppLanguage == "ja" ? "削除" : "delete"
        XCTAssertTrue(ConfirmWord.matches(word, word: ConfirmWord.delete))
        XCTAssertTrue(ConfirmWord.matches("  \(word) ", word: ConfirmWord.delete))
    }

    func testOtherWordsAreRefused() {
        XCTAssertFalse(ConfirmWord.matches("", word: ConfirmWord.delete))
        XCTAssertFalse(ConfirmWord.matches("やめる", word: ConfirmWord.delete))
    }
}

/// ログインの返事（`SignInOutcome`）と、確認コードの画面の文言。
final class SignInOutcomeTests: XCTestCase {

    /// 🔴 **Amplify 2.x は未確認のアカウントで例外を投げず、`.confirmSignUp` を返す。**
    /// 返事を捨てていた頃は「ログインできた」と見なし、確認画面へ送る分岐が
    /// 一度も走らなかった
    func testUnconfirmedSignInIsNotTreatedAsSignedIn() {
        let outcome = SignInOutcome(AuthSignInResult(nextStep: .confirmSignUp(nil)).nextStep)
        XCTAssertEqual(outcome, .needsConfirmation)
        XCTAssertEqual(outcome.failure, .userNotConfirmed,
                       "確認コード待ちを失敗として残していない（確認画面へ送れない）")
    }

    func testResetPasswordStepIsNotSignedIn() {
        let outcome = SignInOutcome(.resetPassword(nil))
        XCTAssertEqual(outcome, .needsPasswordReset)
        XCTAssertEqual(outcome.failure, .passwordResetRequired)
    }

    /// **ログイン済みにしてよいのは完了のときだけ**
    func testOnlyDoneSignsIn() {
        XCTAssertEqual(SignInOutcome(.done), .done)
        XCTAssertNil(SignInOutcome(.done).failure)
        XCTAssertEqual(SignInOutcome(.confirmSignInWithNewPassword(nil)), .other)
        XCTAssertNotNil(SignInOutcome(.confirmSignInWithTOTPCode).failure)
    }

    /// 確認の画面の「すでに使われている」は、ログインへ案内する
    /// （「すでに登録されています」だけでは、確認画面から先へ進めない）
    func testAliasExistsOnConfirmPointsToSignIn() {
        let text = AuthMessage.confirmSignUpText(for: .aliasExists)
        XCTAssertNotEqual(text, AuthMessage.text(for: .aliasExists))
        XCTAssertTrue(text.contains("ログイン") || text.lowercased().contains("sign in"))
        XCTAssertEqual(AuthMessage.confirmSignUpText(for: .codeMismatch),
                       AuthMessage.text(for: .codeMismatch))
    }
}
