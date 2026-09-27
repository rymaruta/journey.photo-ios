import XCTest
@testable import JourneyPhoto

/// 🔴 書いた直後の読み込み（結果整合・書く前に始めた回）で、アルバムの一覧を巻き戻さない。
final class AlbumMergeTests: XCTestCase {

    private func album(_ id: String, _ title: String = "旅") -> Album {
        Album(id: id, title: title, createdAt: nil, memberCount: nil, inviteToken: nil, inviteExpiresAt: nil)
    }

    func testCreatedAlbumIsKeptUntilTheListHasIt() {
        var writes = AlbumMerge.Writes()
        writes.created = [album("new")]
        XCTAssertEqual(AlbumMerge.merge(loaded: [album("old")], writes: writes).map(\.id), ["new", "old"])
        // 一覧に載ったら、以後はサーバーを信じる
        XCTAssertTrue(AlbumMerge.settled(writes, loaded: [album("new"), album("old")]).created.isEmpty)
    }

    func testDeletedAlbumDoesNotComeBack() {
        var writes = AlbumMerge.Writes()
        writes.deleted = ["gone"]
        XCTAssertEqual(AlbumMerge.merge(loaded: [album("gone"), album("old")], writes: writes).map(\.id), ["old"])
    }

    func testRenameIsNotRolledBack() {
        var writes = AlbumMerge.Writes()
        writes.renamed = ["a": "新しい名前"]
        XCTAssertEqual(AlbumMerge.merge(loaded: [album("a", "前の名前")], writes: writes).map(\.title), ["新しい名前"])
        XCTAssertEqual(AlbumMerge.settled(writes, loaded: [album("a", "前の名前")]).renamed, ["a": "新しい名前"])
        XCTAssertTrue(AlbumMerge.settled(writes, loaded: [album("a", "新しい名前")]).renamed.isEmpty)
    }
}
