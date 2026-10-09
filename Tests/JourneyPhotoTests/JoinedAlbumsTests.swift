import XCTest
@testable import JourneyPhoto

/// 招待リンクから参加したアルバムの控え。
///
/// **サーバーは教えてくれない**（`GET /albums` は自分が作ったものだけ）。
/// ここが空になると、参加した人にはアルバムへの入口が消える。
final class JoinedAlbumsTests: XCTestCase {

    @MainActor
    private func store(_ suite: String) -> (JoinedAlbumsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (JoinedAlbumsStore(defaults: defaults), defaults)
    }

    @MainActor
    func testRememberedAlbumSurvivesReload() async throws {
        let (first, defaults) = store("joined-1")
        first.use(userId: "u1")
        first.remember(id: "a1", title: "北欧の旅", token: "t1")

        let second = JoinedAlbumsStore(defaults: defaults)
        second.use(userId: "u1")
        XCTAssertEqual(second.entries.map(\.id), ["a1"])
        XCTAssertEqual(second.entries.first?.token, "t1")
    }

    /// **別の人のぶんが見えてはいけない**（`FavoritesStore` と同じ理由）。
    @MainActor
    func testAnotherAccountSeesNothing() async throws {
        let (joined, defaults) = store("joined-2")
        joined.use(userId: "u1")
        joined.remember(id: "a1", title: "北欧の旅", token: "t1")

        let other = JoinedAlbumsStore(defaults: defaults)
        other.use(userId: "u2")
        XCTAssertTrue(other.entries.isEmpty)
    }

    /// 🔴 2026-10-09: 参加の答えを待つ間にアカウントを替えると、**替わった後の人**の控えに
    /// 書いていた。送る前の人（`owner`）を取って渡し、その人の控えに書く
    @MainActor
    func testJoinFinishingAfterAccountSwitchGoesToTheJoiner() async throws {
        let (joined, defaults) = store("joined-switch")
        joined.use(userId: "u1")
        let owner = joined.owner
        // 答えを待つ間に替わった
        joined.use(userId: "u2")
        joined.remember(id: "a1", title: "北欧の旅", token: "t1", for: owner)
        XCTAssertTrue(joined.entries.isEmpty, "替わった後の人の一覧に入った")

        let u2 = JoinedAlbumsStore(defaults: defaults)
        u2.use(userId: "u2")
        XCTAssertTrue(u2.entries.isEmpty, "替わった後の人の控えに書いた")
        let u1 = JoinedAlbumsStore(defaults: defaults)
        u1.use(userId: "u1")
        XCTAssertEqual(u1.entries.map(\.id), ["a1"], "参加した人の控えから落ちた")

        // 替わっていなければ今までどおり一覧にも入る
        joined.remember(id: "a2", title: "B", token: "t2", for: joined.owner)
        XCTAssertEqual(joined.entries.map(\.id), ["a2"])
    }

    /// 送ったときに人が分からない（`owner` が nil）回は書かない。共通の鍵（ログインしていない
    /// 状態の控え）に入れない（レビュー）
    @MainActor
    func testJoinWithoutAKnownOwnerIsNotWritten() async throws {
        let (joined, defaults) = store("joined-nil-owner")
        joined.use(userId: "u2")
        joined.remember(id: "a1", title: "北欧の旅", token: "t1", for: nil)
        XCTAssertTrue(joined.entries.isEmpty, "いまの人の一覧に入った")
        let signedOut = JoinedAlbumsStore(defaults: defaults)
        signedOut.use(userId: nil)
        XCTAssertTrue(signedOut.entries.isEmpty, "共通の鍵に書いた")
    }

    /// 同じアルバムのリンクを開き直しても増えない（合図は新しい方で上書き）。
    @MainActor
    func testReJoiningReplacesInsteadOfDuplicating() async throws {
        let (joined, _) = store("joined-3")
        joined.use(userId: "u1")
        joined.remember(id: "a1", title: "古い名前", token: "t1")
        joined.remember(id: "a1", title: "新しい名前", token: "t2")

        XCTAssertEqual(joined.entries.count, 1)
        XCTAssertEqual(joined.entries.first?.title, "新しい名前")
        XCTAssertEqual(joined.entries.first?.token, "t2")
    }

    @MainActor
    func testForgettingRemovesItFromTheList() async throws {
        let (joined, defaults) = store("joined-4")
        joined.use(userId: "u1")
        joined.remember(id: "a1", title: "A", token: "t1")
        joined.remember(id: "a2", title: "B", token: "t2")
        joined.forget(id: "a1")

        XCTAssertEqual(joined.entries.map(\.id), ["a2"])
        let reloaded = JoinedAlbumsStore(defaults: defaults)
        reloaded.use(userId: "u1")
        XCTAssertEqual(reloaded.entries.map(\.id), ["a2"], "消したことが残っていない")
    }
}
