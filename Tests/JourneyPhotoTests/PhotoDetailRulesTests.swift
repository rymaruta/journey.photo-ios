import XCTest
@testable import JourneyPhoto

/// 写真詳細の判断（`PhotoDetailRules`）
@MainActor
final class PhotoDetailRulesTests: XCTestCase {

    private func photo(_ id: String, userId: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"userId\":\"\(userId)\"}".utf8))
    }

    /// 🔴 **ブロックした相手の写真が、大きく見る画面の送りに残っていた**
    /// （素の `siblings` を渡していた）
    func testViewerLineupDropsBlockedAndReported() async throws {
        let siblings = [try photo("p1", userId: "a"), try photo("p2", userId: "b"),
                        try photo("p3", userId: "c"), try photo("p4", userId: "a")]
        let lineup = PhotoDetailRules.viewerLineup(
            siblings, current: siblings[2],
            hiding: ModerationSnapshot(blocked: ["a"], reported: ["p2"]))
        XCTAssertEqual(lineup.photos.map(\.id), ["p3"])
        XCTAssertEqual(lineup.index, 0)

        let open = PhotoDetailRules.viewerLineup(siblings, current: siblings[3],
                                                 hiding: ModerationSnapshot(blocked: ["b"]))
        XCTAssertEqual(open.photos.map(\.id), ["p1", "p3", "p4"])
        XCTAssertEqual(open.index, 2, "落としたあとの並びで位置を引き直す")
    }

    /// **押した1枚が落ちる側でも範囲外にしない。** 詳細の上に出ている1枚は残す
    func testViewerLineupKeepsShownPhotoAndIndexInRange() async throws {
        let siblings = [try photo("p1", userId: "a"), try photo("p2", userId: "b"),
                        try photo("p3", userId: "a")]
        let lineup = PhotoDetailRules.viewerLineup(siblings, current: siblings[2],
                                                   hiding: ModerationSnapshot(blocked: ["a"]))
        XCTAssertEqual(lineup.photos.map(\.id), ["p2", "p3"])
        XCTAssertEqual(lineup.index, 1)
        XCTAssertTrue(lineup.photos.indices.contains(lineup.index))

        // 並びに居ない1枚（渡された context の外）でも空にしない
        let stray = try photo("x", userId: "a")
        let alone = PhotoDetailRules.viewerLineup([siblings[0]], current: stray,
                                                  hiding: ModerationSnapshot(blocked: ["a"]))
        XCTAssertEqual(alone.photos.map(\.id), ["x"])
        XCTAssertEqual(alone.index, 0)
    }

    /// 🔴 **ブロックした相手にフォローのボタンを出さない。** 通報シートから「ブロックもする」を
    /// 選んだ回は、前に取った「フォロー中」が残っていて、ブロックした相手に送れていた
    func testFollowButtonIsHiddenForABlockedOwner() async {
        XCTAssertFalse(PhotoDetailRules.showsFollow(isMine: false, signedIn: true, isFollowing: true,
                                                    lookupFailed: false, ownerBlocked: true))
        XCTAssertFalse(PhotoDetailRules.showsFollow(isMine: false, signedIn: true, isFollowing: nil,
                                                    lookupFailed: true, ownerBlocked: true))
        // ブロックしていなければ今までどおり（取れた回・取れなかった回は出す、まだ取っていない回は出さない）
        XCTAssertTrue(PhotoDetailRules.showsFollow(isMine: false, signedIn: true, isFollowing: false,
                                                   lookupFailed: false, ownerBlocked: false))
        XCTAssertTrue(PhotoDetailRules.showsFollow(isMine: false, signedIn: true, isFollowing: nil,
                                                   lookupFailed: true, ownerBlocked: false))
        XCTAssertFalse(PhotoDetailRules.showsFollow(isMine: false, signedIn: true, isFollowing: nil,
                                                    lookupFailed: false, ownerBlocked: false))
        XCTAssertFalse(PhotoDetailRules.showsFollow(isMine: true, signedIn: true, isFollowing: false,
                                                    lookupFailed: false, ownerBlocked: false))
        XCTAssertFalse(PhotoDetailRules.showsFollow(isMine: false, signedIn: false, isFollowing: false,
                                                    lookupFailed: false, ownerBlocked: false))
    }
}
