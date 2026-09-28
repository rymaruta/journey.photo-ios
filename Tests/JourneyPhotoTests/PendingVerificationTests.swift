import XCTest
@testable import JourneyPhoto

/// 「登録したが、まだ確認していない」人の控え。
///
/// **これが無いと永久に入れない。** 登録 → アプリを閉じる → ログイン →
/// UserNotConfirmed → 登録し直すと「すでに登録されています」→
/// パスワード再設定も未確認には効かない、で詰む。Web が
/// `localStorage` で塞いでいる穴（`app/signup/page.tsx`）と同じもの。
final class PendingVerificationTests: XCTestCase {

    private func store(_ suite: String) -> (PendingVerificationStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (PendingVerificationStore(defaults: defaults), defaults)
    }

    func testRememberedUsernameComesBackAfterRelaunch() {
        let (first, defaults) = store("pending-1")
        first.remember(email: "taro@example.com", username: "uuid-1")

        let second = PendingVerificationStore(defaults: defaults)
        XCTAssertEqual(second.username(for: "taro@example.com"), "uuid-1")
    }

    /// **大小を区別しない。** Cognito のメールエイリアスが区別しないので、
    /// `Taro@Example.com` で登録して `taro@example.com` でログインが成立する
    /// ——生の入力を鍵にすると、その場合だけ控えを拾えず行き止まりに戻る。
    func testEmailCaseAndSpacesDoNotHideTheEntry() {
        let (pending, _) = store("pending-2")
        pending.remember(email: "Taro@Example.com", username: "uuid-1")

        XCTAssertEqual(pending.username(for: "  taro@example.com "), "uuid-1")
    }

    /// 24時間で切れる（Web の `PENDING_TTL` と同じ）。
    func testEntryExpiresAfterADay() {
        let (pending, _) = store("pending-3")
        let yesterday = Date().addingTimeInterval(-PendingVerification.ttl - 60)
        pending.remember(email: "taro@example.com", username: "uuid-1", now: yesterday)

        XCTAssertNil(pending.username(for: "taro@example.com"))
    }

    func testConfirmingClearsTheEntry() {
        let (pending, _) = store("pending-4")
        pending.remember(email: "taro@example.com", username: "uuid-1")
        pending.forget(email: "TARO@example.com")

        XCTAssertNil(pending.username(for: "taro@example.com"))
    }
}

/// 登録のときに入れた表示名。
///
/// **確認が済むまで預かる。** プロフィール行は登録時に作られるが名前は
/// 入らない（`api/src/cognitoTrigger.ts` が書くのは `userId` と `createdAt`
/// だけ）ので、入れないとその人はしばらく ID の頭8文字で呼ばれる。
extension PendingVerificationTests {

    func testDisplayNameIsHeldUntilConfirmed() {
        let defaults = UserDefaults(suiteName: "pending-name-1")!
        defaults.removePersistentDomain(forName: "pending-name-1")
        let pending = PendingVerificationStore(defaults: defaults)

        pending.remember(email: "taro@example.com", username: "uuid-1", displayName: "旅人")

        XCTAssertEqual(pending.displayName(for: "TARO@example.com"), "旅人")
    }

    /// **別の人の名前を引き継がない。** 共有の端末で、次にログインした人の
    /// プロフィールに前の人の名前が付く事故が Web で起きている。
    func testAnotherEmailDoesNotInheritTheName() {
        let defaults = UserDefaults(suiteName: "pending-name-2")!
        defaults.removePersistentDomain(forName: "pending-name-2")
        let pending = PendingVerificationStore(defaults: defaults)

        pending.remember(email: "taro@example.com", username: "uuid-1", displayName: "旅人")

        XCTAssertNil(pending.displayName(for: "hanako@example.com"))
    }

    func testNameIsGoneOnceTheEntryExpires() {
        let defaults = UserDefaults(suiteName: "pending-name-3")!
        defaults.removePersistentDomain(forName: "pending-name-3")
        let pending = PendingVerificationStore(defaults: defaults)
        let yesterday = Date().addingTimeInterval(-PendingVerification.ttl - 60)

        pending.remember(email: "taro@example.com", username: "uuid-1",
                         displayName: "旅人", now: yesterday)

        XCTAssertNil(pending.displayName(for: "taro@example.com"))
    }

    /// 🔴 **ログイン・確認・aliasExists で、登録の ID だけ捨てる（名前は残す）。** ID が残ると、
    /// 確認済みの人がパスワードを打ち間違えたときに「確認」へ誘い、押すと確認済み・別アカウント
    /// への送り直しに進んでいた
    func testForgetSignUpDropsTheIdButKeepsTheName() {
        let (pending, _) = store("pending-forget-signup")
        pending.remember(email: "taro@example.com", username: "uuid-1", displayName: "たろう")
        pending.forgetSignUp(email: "Taro@Example.com")
        XCTAssertNil(pending.username(for: "taro@example.com"), "登録の ID が残っている")
        XCTAssertEqual(pending.displayName(for: "taro@example.com"), "たろう", "預かった名前まで捨てた")

        // 🔴 **退会の後始末は、使い終えた控えも ID で探して消す**（9544a43 のレビュー）。
        // ID を空にしていたので、確認のあと名前を入れられなかった控えが退会しても残った
        pending.forget(username: "uuid-1")
        XCTAssertNil(pending.displayName(for: "taro@example.com"), "退会しても控え（名前）が残った")

        // 名前の無い控えは丸ごと捨てる
        pending.remember(email: "hana@example.com", username: "uuid-2")
        pending.forgetSignUp(email: "hana@example.com")
        XCTAssertNil(pending.username(for: "hana@example.com"))
        XCTAssertNil(pending.displayName(for: "hana@example.com"))
    }

    /// 確認への入口は、端末に登録の ID の控えがあり、ログインが「違います」「見つかりません」で
    /// 落ちた回だけ（控えが無ければアカウントの有無を匂わせない）
    func testVerificationOfferNeedsAPendingSignUp() {
        XCTAssertTrue(SignInRecovery.offersVerification(after: .notAuthorized, hasPendingSignUp: true))
        XCTAssertTrue(SignInRecovery.offersVerification(after: .userNotFound, hasPendingSignUp: true))
        XCTAssertFalse(SignInRecovery.offersVerification(after: .notAuthorized, hasPendingSignUp: false))
        XCTAssertFalse(SignInRecovery.offersVerification(after: .network, hasPendingSignUp: true))
        XCTAssertFalse(SignInRecovery.offersVerification(after: .none, hasPendingSignUp: true))
    }
}
