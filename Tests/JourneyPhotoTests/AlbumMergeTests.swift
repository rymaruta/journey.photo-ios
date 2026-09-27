import XCTest
@testable import JourneyPhoto

/// 🔴 書いた直後の読み込み（結果整合・書く前に始めた回）で、アルバムの一覧を巻き戻さない。
/// ただし重ねるのは反映されるまでか `window` 秒まで（他の端末の変更に負け続けない）
final class AlbumMergeTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func album(_ id: String, _ title: String = "旅", token: String? = nil) -> Album {
        Album(id: id, title: title, createdAt: nil, memberCount: nil, inviteToken: token, inviteExpiresAt: nil)
    }

    func testCreatedAlbumIsKeptUntilTheListHasIt() {
        var writes = AlbumMerge.Writes()
        writes.created = [.init(value: album("new"), at: now)]
        XCTAssertEqual(AlbumMerge.merge(loaded: [album("old")], writes: writes).map(\.id), ["new", "old"])
        XCTAssertEqual(AlbumMerge.settled(writes, loaded: [album("old")], now: now).created.count, 1)
        // 一覧に載ったら、以後はサーバーを信じる
        XCTAssertTrue(AlbumMerge.settled(writes, loaded: [album("new"), album("old")], now: now).created.isEmpty)
    }

    /// 作った後に別の端末で消されたら、しばらくして重ねるのをやめる（開けない行を残さない）
    func testCreatedAlbumExpires() {
        var writes = AlbumMerge.Writes()
        writes.created = [.init(value: album("new"), at: now)]
        let later = now.addingTimeInterval(AlbumMerge.window + 1)
        XCTAssertTrue(AlbumMerge.settled(writes, loaded: [], now: later).created.isEmpty)
    }

    func testDeletedAlbumDoesNotComeBack() {
        var writes = AlbumMerge.Writes()
        writes.deleted = ["gone"]
        XCTAssertEqual(AlbumMerge.merge(loaded: [album("gone"), album("old")], writes: writes).map(\.id), ["old"])
    }

    func testRenameIsNotRolledBack() {
        var writes = AlbumMerge.Writes()
        writes.renamed = ["a": .init(value: "新しい名前", at: now)]
        XCTAssertEqual(AlbumMerge.merge(loaded: [album("a", "前の名前")], writes: writes).map(\.title), ["新しい名前"])
        XCTAssertEqual(AlbumMerge.settled(writes, loaded: [album("a", "前の名前")], now: now).renamed.count, 1)
        XCTAssertTrue(AlbumMerge.settled(writes, loaded: [album("a", "新しい名前")], now: now).renamed.isEmpty)
    }

    /// 🔴 その後に Web で名前を変えたら、そちらが勝つ（画面を出るまで古い名前を出さない）
    func testLaterRenameElsewhereWins() {
        var writes = AlbumMerge.Writes()
        writes.renamed = ["a": .init(value: "アプリで付けた名前", at: now)]
        let later = now.addingTimeInterval(AlbumMerge.window + 1)
        let settled = AlbumMerge.settled(writes, loaded: [album("a", "Web で付けた名前")], now: later)
        XCTAssertEqual(AlbumMerge.merge(loaded: [album("a", "Web で付けた名前")], writes: settled).map(\.title),
                       ["Web で付けた名前"])
    }

    /// 作った招待リンクは、古い一覧が届いても出す。取り消したリンクも戻さない
    func testInviteIsNotRolledBack() {
        var writes = AlbumMerge.Writes()
        writes.invites = ["a": .init(value: AlbumService.Invite(token: "t1", expiresAt: nil), at: now)]
        XCTAssertEqual(AlbumMerge.merge(loaded: [album("a")], writes: writes).first?.inviteToken, "t1")
        writes.invites = ["a": .init(value: nil, at: now)]
        XCTAssertNil(AlbumMerge.merge(loaded: [album("a", token: "t1")], writes: writes).first?.inviteToken)
        XCTAssertTrue(AlbumMerge.settled(writes, loaded: [album("a")], now: now).invites.isEmpty)
    }
}
