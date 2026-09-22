import XCTest
@testable import JourneyPhoto

@MainActor
final class SeenStoriesStoreTests: XCTestCase {

    private func make() -> (SeenStoriesStore, UserDefaults) {
        let suite = UserDefaults(suiteName: "seen-stories-\(UUID().uuidString)")!
        return (SeenStoriesStore(defaults: suite), suite)
    }

    private func story(_ id: String) throws -> Story {
        try JSONDecoder.api.decode(Story.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"}".utf8))
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// **ログインし直しても既読のまま**（owner が Web で踏んだ形）
    func testStaysSeenAfterSigningInAgain() async {
        let (store, defaults) = make()
        store.use(userId: "u1", now: now)
        store.markSeen("s1", now: now)

        // ログアウト → もう一度ログイン
        store.use(userId: nil, now: now)
        store.use(userId: "u1", now: now)
        XCTAssertTrue(store.contains("s1"))

        let reopened = SeenStoriesStore(defaults: defaults)
        reopened.use(userId: "u1", now: now)
        XCTAssertTrue(reopened.contains("s1"))
    }

    /// **前の人の既読リングを次の人に見せない**
    func testDoesNotLeakBetweenAccounts() async {
        let (store, _) = make()
        store.use(userId: "u1", now: now)
        store.markSeen("s1", now: now)
        store.use(userId: "u2", now: now)
        XCTAssertFalse(store.contains("s1"))
    }

    /// 25時間より古い印は捨てる（ストーリー自体が24時間で消える）
    func testForgetsOldMarks() async {
        let (store, defaults) = make()
        store.use(userId: "u1", now: now)
        store.markSeen("old", now: now)

        let later = now.addingTimeInterval(SeenStoriesStore.lifetime + 60)
        let reopened = SeenStoriesStore(defaults: defaults)
        reopened.use(userId: "u1", now: later)
        XCTAssertFalse(reopened.contains("old"))
    }

    /// 印を付けるときにも古いものを掃除する（増え続けさせない）
    func testMarkingAlsoSweeps() async {
        let (store, _) = make()
        store.use(userId: "u1", now: now)
        store.markSeen("old", now: now)
        store.markSeen("new", now: now.addingTimeInterval(SeenStoriesStore.lifetime + 60))
        XCTAssertFalse(store.contains("old"))
        XCTAssertTrue(store.contains("new"))
    }

    /// 1本でも未読があればリングを点ける
    func testUnseenWhenAnyIsUnread() async throws {
        let (store, _) = make()
        store.use(userId: "u1", now: now)
        let stories = [try story("a"), try story("b")]
        XCTAssertTrue(store.hasUnseen(stories))
        store.markSeen("a", now: now)
        XCTAssertTrue(store.hasUnseen(stories))
        store.markSeen("b", now: now)
        XCTAssertFalse(store.hasUnseen(stories))
    }
}
