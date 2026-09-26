import XCTest
@testable import JourneyPhoto

/// 「親しい友達」の画面に並べる人（`CloseFriendsRows`）。
final class CloseFriendsRowsTests: XCTestCase {

    private func user(_ id: String) -> FollowUser {
        FollowUser(id: id, name: id, deleted: nil)
    }

    /// 🔴 **フォロー中に居ない親しい友達も並べる。** 並べないと外せず、
    /// フォローを外した相手が「親しい友達」の写真を見続けられた
    func testChosenPeopleOutsideTheFollowingListAreListed() {
        let rows = CloseFriendsRows.split(following: [user("a"), user("b")],
                                          chosen: ["b", "gone", "past50"])
        XCTAssertEqual(rows.others, ["gone", "past50"])
        XCTAssertEqual(rows.following.map(\.id), ["a", "b"])
    }

    /// フォロー中の人は二重に並べない（上の段に出すのは一覧に居ない人だけ）
    func testFollowedPeopleAreNotDuplicated() {
        let rows = CloseFriendsRows.split(following: [user("a")], chosen: ["a"])
        XCTAssertTrue(rows.others.isEmpty)
    }

    /// 同じ id が2回来ても1行（`ForEach` の id が重なると表示が崩れる）
    func testDuplicateIdsBecomeOneRow() {
        let rows = CloseFriendsRows.split(following: [], chosen: ["x", "x"])
        XCTAssertEqual(rows.others, ["x"])
    }

    /// フォローが0人でも、選んでいる人がいれば並ぶ（「まだいません」で隠さない）
    func testWorksWithNoFollowing() {
        let rows = CloseFriendsRows.split(following: [], chosen: ["x"])
        XCTAssertEqual(rows.others, ["x"])
    }
}

/// 「保存」で送る差分と、1件ずつ送る流れ（板 39）。
final class CloseFriendsSaveTests: XCTestCase {

    private struct Boom: Error {}

    /// 変えた人だけを送る。**外す方を先に**（満杯のとき、足す方を先に送ると
    /// サーバーが古い人を黙って押し出す）
    func testChangesAreOnlyTheDifferenceRemovalsFirst() {
        let changes = CloseFriendsRows.changes(saved: ["a", "b", "c"], picked: ["b", "c", "d", "e"],
                                               order: ["e", "d", "c", "b", "a"])
        XCTAssertEqual(changes, [
            .init(userId: "a", wanted: false),
            .init(userId: "e", wanted: true),
            .init(userId: "d", wanted: true),
        ])
    }

    /// 何も変えていなければ送るものは無い（「保存」は押せない）
    func testNoChangesWhenUntouched() {
        XCTAssertTrue(CloseFriendsRows.changes(saved: ["a"], picked: ["a"], order: ["a"]).isEmpty)
    }

    /// 並びに居ない id も落とさない（id 順で後ろに）
    func testIdsOutsideTheOrderAreKept() {
        let changes = CloseFriendsRows.changes(saved: [], picked: ["z", "y", "a"], order: ["a"])
        XCTAssertEqual(changes.map(\.userId), ["a", "y", "z"])
    }

    /// 全部送れたら、保存済みは選んだとおりになる
    func testSavesEveryChangeInOrder() async {
        let changes = CloseFriendsRows.changes(saved: ["a"], picked: ["b"], order: ["a", "b"])
        var sent: [String] = []
        let outcome = await CloseFriendsRows.save(saved: ["a"], changes: changes) { change in
            sent.append(change.userId)
            return change.wanted
        }
        XCTAssertEqual(sent, ["a", "b"])
        XCTAssertEqual(outcome.saved, ["b"])
        XCTAssertTrue(outcome.finished)
        XCTAssertNil(CloseFriendsRows.partialMessage(outcome))
    }

    /// 🔴 **最初に失敗したところで止める。** 送れたぶんだけが保存済みに入り、
    /// その先は送らない。知らせは「何件保存できたか」を言う
    func testStopsAtTheFirstFailureAndReportsHowFarItGot() async {
        let changes: [CloseFriendsRows.Change] = [
            .init(userId: "a", wanted: false),
            .init(userId: "b", wanted: true),
            .init(userId: "c", wanted: true),
        ]
        var sent: [String] = []
        let outcome = await CloseFriendsRows.save(saved: ["a"], changes: changes) { change in
            sent.append(change.userId)
            if change.userId == "b" { throw Boom() }
            return change.wanted
        }
        XCTAssertEqual(sent, ["a", "b"])
        XCTAssertEqual(outcome.saved, [])
        XCTAssertEqual(outcome.done, 1)
        XCTAssertEqual(outcome.total, 3)
        XCTAssertFalse(outcome.finished)
        let message = CloseFriendsRows.partialMessage(outcome) ?? ""
        XCTAssertTrue(message.contains("1") && message.contains("3") && message.contains("2"), message)
        // もう一度押したときに送るのは残りだけ
        let rest = CloseFriendsRows.changes(saved: outcome.saved, picked: ["b", "c"], order: ["a", "b", "c"])
        XCTAssertEqual(rest.map(\.userId), ["b", "c"])
    }

    /// 状態は**返ってきた値**を使う（送ったつもりの値で決めない）
    func testUsesTheStateTheServerReturned() async {
        let outcome = await CloseFriendsRows.save(saved: [], changes: [.init(userId: "a", wanted: true)]) { _ in
            false
        }
        XCTAssertEqual(outcome.saved, [])
        XCTAssertTrue(outcome.finished)
    }
}
