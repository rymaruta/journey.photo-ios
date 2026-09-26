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
}
