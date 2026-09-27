import XCTest
@testable import JourneyPhoto

/// 親しい友達: フォロー中の名前つき一覧は50人で切れる。51人目以降も選べ、
/// 選んだ人が「外した人など」に誤って分類されないこと。
final class CloseFriendsBeyondPageTests: XCTestCase {

    private func user(_ id: String) -> FollowUser { FollowUser(id: id, name: id, deleted: nil) }

    func testFollowingBeyondTheFirstPageIsSelectableAndNotOther() {
        let page = (1...50).map { user("u\($0)") }
        let all = (1...60).map { "u\($0)" }
        let rows = CloseFriendsView.rows(page: page, allFollowing: all, chosen: ["u55", "gone"])
        XCTAssertEqual(rows.beyondPage, (51...60).map { "u\($0)" })
        // u55 はフォロー中（一覧に載らなかっただけ）。外した人は gone だけ
        XCTAssertEqual(rows.others, ["gone"])
    }

    /// 全員の ID が取れないときは、一覧に居ない選んだ人を全部残す（外せるように）
    func testWithoutAllIdsFallsBackToOthers() {
        let rows = CloseFriendsView.rows(page: [user("a")], allFollowing: nil, chosen: ["a", "b"])
        XCTAssertEqual(rows.beyondPage, [])
        XCTAssertEqual(rows.others, ["b"])
    }
}
