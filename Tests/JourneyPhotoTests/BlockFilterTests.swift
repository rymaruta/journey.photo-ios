import XCTest
@testable import JourneyPhoto

/// ブロックした人を、サーバーが絞らない口（コメント・人の検索）から外す（審査 1.2）
final class BlockFilterTests: XCTestCase {

    /// 🔴 **ブロックした人のコメントが写真の詳細に出続けていた**
    /// （`GET /photos/{id}/comments` はログイン不要でブロックを知らない）
    func testBlockedCommentersAreHidden() {
        let comments = [
            PhotoComment(id: "c1", uid: "a", name: "A", text: "x", t: nil, deleted: nil),
            PhotoComment(id: "c2", uid: "b", name: "B", text: "y", t: nil, deleted: nil),
        ]
        XCTAssertEqual(BlockFilter.comments(comments, blocked: ["a"]).map(\.id), ["c2"])
        XCTAssertEqual(BlockFilter.comments(comments, blocked: []).map(\.id), ["c1", "c2"])
    }

    /// 🔴 **ブロックした人が検索の「人」に出ていた**（`/users/search` もブロックを知らない）
    func testBlockedUsersAreHiddenFromPeopleSearch() throws {
        let json = #"[{"userId":"a","displayName":"A"},{"userId":"b","displayName":"B"}]"#
        let users = try JSONDecoder().decode([UserProfile].self, from: Data(json.utf8))
        XCTAssertEqual(BlockFilter.users(users, blocked: ["a"]).map(\.userId), ["b"])
        XCTAssertEqual(BlockFilter.users(users, blocked: []).map(\.userId), ["a", "b"])
    }

    private func photo(_ id: String, userId: String? = nil, uploadedBy: String? = nil) throws -> Photo {
        let u = userId.map { ",\"userId\":\"\($0)\"" } ?? ""
        let b = uploadedBy.map { ",\"uploadedBy\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(u)\(b)}".utf8))
    }

    /// 🔴 **ブロックした人の写真が地図・タグ・お気に入り・スポットに残っていた**
    /// （読み込み済みの画面は公開一覧を読み直さない）。基準は公開一覧と同じ:
    /// 通報した1枚・ブロックした人の写真（`uploadedBy` しか無い行も）を落とす
    func testHiddenPhotosAreDropped() throws {
        let photos = [
            try photo("p1", userId: "a"),
            try photo("p2", uploadedBy: "a"),
            try photo("p3", userId: "b"),
            try photo("p4"),
        ]
        XCTAssertEqual(BlockFilter.photos(photos, blocked: ["a"], reported: ["p3"]).map(\.id), ["p4"])
        XCTAssertEqual(BlockFilter.photos(photos, blocked: [], reported: []).map(\.id), ["p1", "p2", "p3", "p4"])
    }

    /// 画面が使う入口（`ModerationStore.visible`）が、その人の控えを通すこと
    @MainActor
    func testStoreDropsWhatItHides() async throws {
        let store = ModerationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.use(userId: "me")
        // 画面が開いた時点の写しは、あとのブロックで**変わらない**（見ている最中に縮めない）
        let before = store.snapshot
        store.block("a")
        store.markReported("p3")
        let photos = [try photo("p1", userId: "a"), try photo("p3", userId: "b"), try photo("p4", userId: "b")]
        XCTAssertEqual(store.visible(photos).map(\.id), ["p4"])
        XCTAssertEqual(store.snapshot.visible(photos).map(\.id), ["p4"])
        XCTAssertEqual(before.visible(photos).map(\.id), ["p1", "p3", "p4"])
    }

    /// 🔴 **人・コメント・見た人も写しで落とす。** 探すの人の結果・写真の詳細のコメント・
    /// ストーリーの反応は、描くたびに今のブロックの集合で絞っていた。行から開いた
    /// その人のページでブロックすると、元の行（`NavigationLink`）が消えてページが閉じた。
    /// **ブロックの変更の回数は、元に戻っても進み、通報では進まない**
    /// （起動時の同期が「待っている間に手元で変えたか」を見る。集合の比較だと
    /// ブロックして解除した回をすり抜け、古い一覧で解除を戻していた）
    @MainActor
    func testBlockRevisionCountsBlockChangesOnly() async throws {
        let store = ModerationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.use(userId: "me")
        let start = store.blockRevision
        store.markReported("p1")
        XCTAssertEqual(store.blockRevision, start, "通報で進んだ")
        store.block("x")
        store.unblock("x")
        XCTAssertEqual(store.blockRevision, start + 2, "ブロックして解除した回を数えていない")
    }

    /// 開いた時点の写しは後のブロックで変わらず、取り直した写しは落とす
    @MainActor
    func testSnapshotKeepsPeopleUntilRetaken() async throws {
        let store = ModerationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.use(userId: "me")
        let before = store.snapshot
        store.block("a")
        let after = store.snapshot

        let users = try JSONDecoder().decode([UserProfile].self, from: Data(
            #"[{"userId":"a","displayName":"A"},{"userId":"b","displayName":"B"}]"#.utf8))
        XCTAssertEqual(before.users(users).map(\.userId), ["a", "b"])
        XCTAssertEqual(after.users(users).map(\.userId), ["b"])

        let comments = [
            PhotoComment(id: "c1", uid: "a", name: "A", text: "x", t: nil, deleted: nil),
            PhotoComment(id: "c2", uid: "b", name: "B", text: "y", t: nil, deleted: nil),
        ]
        XCTAssertEqual(before.comments(comments).map(\.id), ["c1", "c2"])
        XCTAssertEqual(after.comments(comments).map(\.id), ["c2"])

        let viewers = try JSONDecoder().decode([StoryViewer].self, from: Data(
            #"[{"userId":"a"},{"userId":"b"}]"#.utf8))
        XCTAssertEqual(before.viewers(viewers).map(\.userId), ["a", "b"])
        XCTAssertEqual(after.viewers(viewers).map(\.userId), ["b"])
    }
}
