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

    /// 51人目以降の名前引きは上限で止める。選んでいる人は上限を超えても必ず引く
    func testLookupIsCappedButChosenAreAlwaysKept() {
        let beyond = (51...500).map { "u\($0)" }
        let picked = CloseFriendsView.beyondToLookUp(beyond, others: 3,
                                                     chosen: ["u499", "u60"], cap: 10)
        XCTAssertEqual(picked.count, 10 - 3)
        XCTAssertTrue(picked.contains("u499"))
        XCTAssertTrue(picked.contains("u60"))
        // フォローした順のまま
        XCTAssertEqual(picked, ["u51", "u52", "u53", "u54", "u55", "u60", "u499"])
    }

    /// 選んでいる人だけで上限を超えても、選んでいる人は落とさない
    func testChosenExceedingTheCapAreAllKept() {
        let picked = CloseFriendsView.beyondToLookUp(["a", "b", "c"], others: 5,
                                                     chosen: ["a", "c"], cap: 4)
        XCTAssertEqual(picked, ["a", "c"])
    }
}
