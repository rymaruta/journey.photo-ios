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

    /// **捨てるのは「この控えはもう使えない」ときだけ。**
    /// 回数制限や圏外で捨てると、唯一の手がかりを失う（Web の反省）。
    func testOnlyPermanentFailuresDiscardTheEntry() {
        XCTAssertTrue(PendingVerification.shouldForget(afterResendError: "UserNotFoundException"))
        XCTAssertTrue(PendingVerification.shouldForget(afterResendError: "NotAuthorizedException"))
        XCTAssertFalse(PendingVerification.shouldForget(afterResendError: "LimitExceededException"),
                       "回数制限で唯一の手がかりを捨てない")
        XCTAssertFalse(PendingVerification.shouldForget(afterResendError: "NetworkError"))
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
}
