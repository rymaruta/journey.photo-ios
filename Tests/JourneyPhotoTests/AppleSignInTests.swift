import XCTest
import Amplify
import AuthenticationServices
@testable import JourneyPhoto

/// Apple でサインイン（2026-10-21）。サーバー側の対は photo-gallery の
/// `api/src/__tests__/appleSignIn.test.ts`・`appleChallenge.test.ts`・`api-user/src/__tests__/appleRevoke.test.ts`
final class AppleSignInTests: XCTestCase {

    // MARK: - nonce

    /// 🔴 **サーバーの `hashNonce`（Node の SHA-256）と同じ値でないと、全員が「nonce が合わない」で落ちる。**
    /// 既知の値（FIPS 180-4 の例）で縛る
    func testSHA256MatchesKnownVectors() {
        XCTAssertEqual(AppleNonce.sha256Hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(AppleNonce.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(AppleNonce.sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        // 64 バイトちょうど（詰め物が次のブロックに溢れる形）と、日本語（UTF-8）
        XCTAssertEqual(AppleNonce.sha256Hex(String(repeating: "a", count: 64)),
                       "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")
        XCTAssertEqual(AppleNonce.sha256Hex("あ"), "dc5a4d3d82f7e15792959dc661538ae0e541ce66494516f5c9cfd9cd3308494d")
    }

    func testNonceIsLongAndFresh() {
        let a = AppleNonce.make(), b = AppleNonce.make()
        XCTAssertEqual(a.count, 64, "サーバーは16字未満を断る")
        XCTAssertNotEqual(a, b, "毎回作り直す（使い回しを止めるため）")
        XCTAssertTrue(a.allSatisfy { $0.isHexDigit })
    }

    // MARK: - シートの答えの読み方

    func testReadsTokenAndName() {
        var name = PersonNameComponents()
        name.givenName = "太郎"
        name.familyName = "山田"
        let outcome = AppleProof.read(identityToken: Data("a.b.c".utf8), fullName: name, nonce: "n" + String(repeating: "0", count: 20))
        guard case .proof(let proof) = outcome else { return XCTFail("読めていない: \(outcome)") }
        XCTAssertEqual(proof.identityToken, "a.b.c")
        XCTAssertEqual(AppleProof.displayName(of: name, language: "ja"), "山田 太郎")
        XCTAssertEqual(AppleProof.displayName(of: name, language: "en"), "太郎 山田")
        XCTAssertNil(AppleProof.displayName(of: PersonNameComponents(), language: "ja"), "空の名前は入れない")
    }

    func testNoTokenOrNonceIsFailure() {
        XCTAssertEqual(AppleProof.read(identityToken: nil, fullName: nil, nonce: "nonce"), .failed)
        XCTAssertEqual(AppleProof.read(identityToken: Data("t".utf8), fullName: nil, nonce: ""), .failed,
                       "nonce が無いとサーバーで必ず落ちる（送らない）")
    }

    /// 本人がシートを閉じたときは**何も言わない**（失敗の赤い文を出さない）
    func testCancelIsQuiet() {
        XCTAssertEqual(AppleProof.read(.failure(ASAuthorizationError(.canceled)), nonce: "n"), .canceled)
        XCTAssertEqual(AppleProof.read(.failure(ASAuthorizationError(.failed)), nonce: "n"), .failed)
        XCTAssertEqual(AppleProof.read(.failure(URLError(.notConnectedToInternet)), nonce: "n"), .failed)
    }

    /// カスタム認証の答えの形（サーバーの `appleChallenge.ts` の `isCorrectAnswer` が読む）
    func testChallengeAnswerShape() throws {
        let proof = AppleProof(identityToken: "tok", nonce: "raw")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(proof.challengeAnswer.utf8)) as? [String: String])
        XCTAssertEqual(json, ["identityToken": "tok", "nonce": "raw"])
    }

    // MARK: - サーバーの答え

    func testServerErrorsMapToKinds() {
        XCTAssertEqual(AppleSignInError.from(serverError: JourneyPhoto.APIError.server(status: 409, message: "x")) as? AppleSignInError, .conflict)
        XCTAssertEqual(AppleSignInError.from(serverError: JourneyPhoto.APIError.server(status: 503, message: "")) as? AppleSignInError, .unavailable)
        XCTAssertEqual(AppleSignInError.from(serverError: JourneyPhoto.APIError.server(status: 401, message: "")) as? AppleSignInError, .rejected)
        XCTAssertEqual(AppleSignInError.from(serverError: JourneyPhoto.APIError.unreachable) as? JourneyPhoto.APIError, .unreachable,
                       "通信できない回は「通信できません」のまま")
    }

    /// 答えたのにもう一度問いが来た＝断られた（Define は外れたら問いを出し直す）
    func testSecondChallengeIsRejection() throws {
        XCTAssertThrowsError(try AuthGateway.appleOutcome(of: .confirmSignInWithCustomChallenge(nil), isSignedIn: false)) {
            XCTAssertEqual($0 as? AppleSignInError, .rejected)
        }
        XCTAssertTrue(try AuthGateway.appleOutcome(of: .done, isSignedIn: true))
    }

    // MARK: - AuthStore

    @MainActor
    private func store(apple: @escaping @Sendable (AppleProof) async throws -> AppleAccountLink,
                       signOuts: SignOutTally = SignOutTally(), latch: SignOutLatch = .forTesting()) -> AuthStore {
        var gateway = AuthStoreGateway(
            isSignedIn: { false }, currentUserId: { "user-1" }, currentUsername: { "uuid-1" },
            isSessionExpired: { false }, signOut: { await signOuts.note(); return .signedOut }, deleteUser: {},
            latch: latch)
        gateway.signInWithApple = apple
        return AuthStore(gateway: gateway)
    }

    @MainActor
    func testAppleSignInSignsIn() async {
        let auth = store(apple: { _ in AppleAccountLink(username: "uuid-1", created: true, linked: false) })
        let link = await auth.signInWithApple(AppleProof(identityToken: "t", nonce: "n"))
        XCTAssertEqual(link?.created, true)
        XCTAssertEqual(auth.userId, "user-1")
        XCTAssertNil(auth.errorMessage)
    }

    @MainActor
    func testAppleConflictSaysUseEmail() async {
        let auth = store(apple: { _ in throw AppleSignInError.conflict })
        let link = await auth.signInWithApple(AppleProof(identityToken: "t", nonce: "n"))
        XCTAssertNil(link)
        XCTAssertEqual(auth.lastFailure, .appleConflict)
        XCTAssertEqual(auth.errorMessage, AuthMessage.text(for: .appleConflict))
        XCTAssertEqual(auth.state, .unknown, "ログイン中にしない")
    }

    /// 🔴 カスタム認証を断られると Cognito は NotAuthorized で返す。**「メールアドレスかパスワードが違います」を出さない**
    @MainActor
    func testCognitoRejectionIsNotWrongPassword() async {
        let auth = store(apple: { _ in throw AuthError.notAuthorized("", "", nil) })
        _ = await auth.signInWithApple(AppleProof(identityToken: "t", nonce: "n"))
        XCTAssertEqual(auth.lastFailure, .appleFailed)
        XCTAssertNotEqual(auth.errorMessage, AuthMessage.text(for: .notAuthorized))
        XCTAssertEqual(auth.errorMessage, AuthMessage.text(for: .appleFailed))
    }

    @MainActor
    func testUnreachableSaysNoConnection() async {
        let auth = store(apple: { _ in throw JourneyPhoto.APIError.unreachable })
        _ = await auth.signInWithApple(AppleProof(identityToken: "t", nonce: "n"))
        XCTAssertEqual(auth.lastFailure, .network)
    }

    /// 前のログアウトで端末の中のログインを消せなかった回は、メールのログインと同じく先に外す
    @MainActor
    func testLeftoverSessionIsClearedFirst() async {
        let latch = SignOutLatch.forTesting()
        latch.set()
        let tally = SignOutTally()
        let auth = store(apple: { _ in AppleAccountLink(username: "u", created: false, linked: false) }, signOuts: tally, latch: latch)
        _ = await auth.signInWithApple(AppleProof(identityToken: "t", nonce: "n"))
        let count = await tally.count
        XCTAssertEqual(count, 1)
        XCTAssertFalse(latch.isSet, "入れたら印を外す")
    }

    // MARK: - 退会のときの取り消し

    private func jwt(_ claims: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: claims)
        let body = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "h.\(body).s"
    }

    func testAppleSubjectClaim() {
        XCTAssertEqual(IdTokenClaims.appleSubject(fromJWT: jwt(["custom:apple_sub": "001.a.1"])), "001.a.1")
        XCTAssertNil(IdTokenClaims.appleSubject(fromJWT: jwt(["sub": "u"])))
    }

    /// パスワードだけの人には**シートを出さない**
    func testRevokeSkipsNonAppleUsers() async {
        var asked = false
        let outcome = await AppleSignInRevoke.beforeDeletion(
            idToken: jwt(["sub": "u"]), authorize: { asked = true; return "c" }, revoke: { _ in })
        XCTAssertEqual(outcome, .notAppleUser)
        XCTAssertFalse(asked)
        let none = await AppleSignInRevoke.beforeDeletion(idToken: nil, authorize: { "c" }, revoke: { _ in })
        XCTAssertEqual(none, .notAppleUser)
    }

    func testRevokeSendsTheFreshCode() async {
        var sent: String?
        let outcome = await AppleSignInRevoke.beforeDeletion(
            idToken: jwt(["custom:apple_sub": "001.a.1"]), authorize: { "code-1" }, revoke: { sent = $0 })
        XCTAssertEqual(outcome, .revoked)
        XCTAssertEqual(sent, "code-1")
    }

    /// 🔴 **取り消しが落ちても退会は止めない**（閉じた・通信できない・サーバーが断った）
    func testRevokeFailureDoesNotBlockDeletion() async {
        var sent = false
        let canceled = await AppleSignInRevoke.beforeDeletion(
            idToken: jwt(["custom:apple_sub": "x"]), authorize: { throw ASAuthorizationError(.canceled) }, revoke: { _ in sent = true })
        XCTAssertEqual(canceled, .skipped)
        XCTAssertFalse(sent)
        let refused = await AppleSignInRevoke.beforeDeletion(
            idToken: jwt(["custom:apple_sub": "x"]), authorize: { "c" }, revoke: { _ in throw JourneyPhoto.APIError.server(status: 502, message: "") })
        XCTAssertEqual(refused, .skipped)
    }

    // MARK: - 設定

    /// **既定は出さない**（サーバーと Apple の設定が揃う前にボタンだけ出さない）
    func testButtonIsOffUnlessYes() {
        defer { AppConfig.testOverrides = nil }
        AppConfig.testOverrides = [:]
        XCTAssertFalse(AppConfig.appleSignInEnabled)
        AppConfig.testOverrides = ["JPAppleSignIn": "NO"]
        XCTAssertFalse(AppConfig.appleSignInEnabled)
        AppConfig.testOverrides = ["JPAppleSignIn": "YES"]
        XCTAssertTrue(AppConfig.appleSignInEnabled)
    }

    func testMessagesAreBilingual() {
        for failure in [AuthFailure.appleConflict, .appleFailed, .appleUnavailable] {
            XCTAssertFalse(AuthMessage.text(for: failure).isEmpty)
            XCTAssertNotEqual(AuthMessage.text(for: failure), AuthMessage.text(for: .other), "\(failure) が汎用の文に落ちている")
        }
    }
}

/// ログアウトを頼まれた回数
actor SignOutTally {
    private(set) var count = 0
    func note() { count += 1 }
}
