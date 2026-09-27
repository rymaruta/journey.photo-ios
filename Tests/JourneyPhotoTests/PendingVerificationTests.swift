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

    /// 🔴 **送り直しが回数制限・圏外で落ちても、確認画面には入れる。**
    /// 送れたときだけ入れていたので、手元に届いている有効なコードを入れる欄に
    /// 辿り着けなかった。入れないのは、控えがもう使えない失敗のときだけ
    func testResendFailureStillEntersConfirmation() {
        XCTAssertTrue(PendingVerification.entersConfirmation(resent: true, failure: .none))
        XCTAssertTrue(PendingVerification.entersConfirmation(resent: false, failure: .limitExceeded),
                      "回数制限で確認画面に入れない")
        XCTAssertTrue(PendingVerification.entersConfirmation(resent: false, failure: .network),
                      "圏外で確認画面に入れない")
        XCTAssertFalse(PendingVerification.entersConfirmation(resent: false, failure: .userNotFound),
                       "消えたアカウントの控えで確認画面に入れている")
        XCTAssertFalse(PendingVerification.entersConfirmation(resent: false, failure: .notAuthorized))
    }

    /// 🔴 **ふつうのログインでも、預かっている表示名を入れる。** 確認は通ったのに
    /// 自動ログインが落ちた人・名前の送信が落ちた人は、控えを「次のログインで
    /// 試せる」と残していたのに、ふつうのログインは控えを読んでいなかった
    @MainActor
    func testSignInAppliesTheHeldNameAndForgetsOnlyOnSuccess() async {
        let defaults = UserDefaults(suiteName: "pending-name-4")!
        defaults.removePersistentDomain(forName: "pending-name-4")
        let pending = PendingVerificationStore(defaults: defaults)
        pending.remember(email: "taro@example.com", username: "uuid-1", displayName: "旅人")

        var sent: [String?] = []
        // 1回目は送れない（圏外）→ 控えを残す
        await pending.settleAfterSignIn(email: "Taro@example.com") { sent.append($0); return false }
        XCTAssertEqual(sent, ["旅人"], "預かっている名前を入れにいっていない")
        XCTAssertEqual(pending.displayName(for: "taro@example.com"), "旅人", "落ちたのに控えを捨てた")

        // 2回目で入った → 捨てる
        await pending.settleAfterSignIn(email: "taro@example.com") { sent.append($0); return true }
        XCTAssertEqual(sent, ["旅人", "旅人"])
        XCTAssertNil(pending.username(for: "taro@example.com"), "入れ終えたのに控えが残っている")

        // 控えが無ければ何もしない（ログインのたびにプロフィールを書かない）
        let before = sent.count
        await pending.settleAfterSignIn(email: "taro@example.com") { sent.append($0); return true }
        XCTAssertEqual(sent.count, before, "控えが無いのに名前を送った")
    }
}
