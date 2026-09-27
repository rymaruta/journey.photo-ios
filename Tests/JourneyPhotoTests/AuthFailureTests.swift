import XCTest
import Amplify
import AWSCognitoAuthPlugin
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

    /// 🔴 **ログインの「続き」を捨てない。** Amplify 2.x は未確認・再設定待ちを
    /// 例外でなく `nextStep` で返す。再設定待ちを捨てると「うまくいきませんでした」
    /// だけが出て、「パスワードを忘れた」へ進むことに気づけない
    func testUnfinishedSignInBecomesAKnownFailure() throws {
        XCTAssertNil(AuthGateway.unfinishedSignIn(.done))
        let unconfirmed = try XCTUnwrap(AuthGateway.unfinishedSignIn(.confirmSignUp(nil)))
        XCTAssertEqual(AuthFailure(unconfirmed), .userNotConfirmed)
        let reset = try XCTUnwrap(AuthGateway.unfinishedSignIn(.resetPassword(nil)))
        XCTAssertEqual(AuthFailure(reset), .passwordResetRequired)
        XCTAssertTrue(AuthMessage.text(for: .passwordResetRequired).contains("パスワードを忘れた")
                      || AuthMessage.text(for: .passwordResetRequired).contains("Forgot password"))
    }

    /// 確認の画面で `aliasExists`＝別のアカウントで確認済み。「すでに登録されています」
    /// では先へ進めないので、ログインへ戻るよう案内する。それ以外はふつうの文言
    func testConfirmScreenExplainsAnAliasTakenByAVerifiedAccount() {
        let text = AuthMessage.confirmSignUpText(for: .aliasExists)
        XCTAssertNotNil(text)
        XCTAssertNotEqual(text, AuthMessage.text(for: .aliasExists))
        XCTAssertNil(AuthMessage.confirmSignUpText(for: .codeMismatch))
    }

    /// パスワード変更の画面にメールの欄は無い。短すぎる（`invalidParameter`）には
    /// パスワードの決まりだけを出す
    func testChangePasswordDoesNotMentionTheEmail() {
        XCTAssertEqual(AuthMessage.changePasswordText(for: .invalidParameter), AuthMessage.passwordRule)
        XCTAssertNil(AuthMessage.changePasswordText(for: .limitExceeded))
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

/// 🔴 **トークンが取れない理由（Amplify の `AuthError`）を、画面が分岐できる形に畳む。**
/// 圏外でトークンを更新できなかった回にそのまま投げると、画面は `APIError` として
/// 読めず、「圏外」ではなく「読み込めませんでした」を出していた。
///
/// **`JourneyPhoto.APIError` と書く。** Amplify も `APIError` を持っているので、
/// 両方を読むこのファイルでは素の `APIError` が取り違えになる（Linux の模型には
/// 無いので、ここでは通っても Mac で落ちる）
final class APIClientTokenFailureTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private struct Payload: Decodable { let ok: Bool }

    private func call(throwing error: Error) async -> Error? {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: ThrowingTokenProvider(error: error),
                            session: session)
        do {
            _ = try await api.authorized(.get, "/user/profile", as: Payload.self)
            return nil
        } catch {
            return error
        }
    }

    /// 圏外でトークンを更新できなかった回（Cognito プラグインは `AWSCognitoAuthError.network` を付ける）
    func testTokenRefreshFailingOfflineIsUnreachable() async {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        let thrown = await call(throwing: AuthError.service("", "", AWSCognitoAuthError.network))
        XCTAssertEqual(thrown as? JourneyPhoto.APIError, .unreachable,
                       "圏外を圏外として出していない: \(String(describing: thrown))")
        XCTAssertNil(StubProtocol.lastRequest, "トークンが無いのに要求を投げている")
    }

    /// サインアウト済み・（`idToken` の外で投げられた）期限切れは「ログインしていない」
    func testSignedOutOrExpiredMeansNotAuthenticated() async {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        for failure in [AuthError.signedOut("", "", nil), AuthError.sessionExpired("", "", nil)] {
            let thrown = await call(throwing: failure)
            XCTAssertEqual(thrown as? JourneyPhoto.APIError, .notAuthenticated,
                           "\(failure) を畳んでいない: \(String(describing: thrown))")
        }
    }

    /// 直し方の決まらない失敗は、別の名前で隠さない
    func testOtherTokenFailuresArePassedThrough() async {
        let thrown = await call(throwing: AuthError.configuration("", "", nil))
        XCTAssertNil(thrown as? JourneyPhoto.APIError, "設定の誤りを別の失敗に言い換えた")
        XCTAssertTrue(thrown is AuthError)
    }

    /// 🔴 **期限切れは、Cognito の種別を抱えていても期限切れ**（`idToken` がログアウトに
    /// 倒す判定 `.notAuthorized`）。抱えた種別を先に見て `.other` にしていた
    func testExpiredSessionWithACognitoCauseIsStillExpired() {
        XCTAssertEqual(AuthFailure(AuthError.sessionExpired("", "", AWSCognitoAuthError.userNotFound)),
                       .notAuthorized)
    }
}
