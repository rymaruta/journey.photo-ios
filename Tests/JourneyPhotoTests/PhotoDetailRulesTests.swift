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

    /// 🔴 **束の写真は詳細の上と同じ選んだ順（`createdAt` の古い順）で送る。**
    /// 渡された順（人気順など）のままだと、上と大きく見る画面で送る向きが逆になった。
    /// 束ねていない写真の場所は動かさない
    func testViewerLineupOrdersGroupMembersLikeTheHero() async throws {
        func dated(_ id: String, _ at: String, group: String?) throws -> Photo {
            let g = group.map { ",\"groupId\":\"\($0)\"" } ?? ""
            return try JSONDecoder.api.decode(Photo.self, from: Data(
                "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"userId\":\"me\",\"createdAt\":\"\(at)\"\(g)}".utf8))
        }
        let context = [
            try dated("g3", "2026-09-01T10:00:02.000Z", group: "g"),
            try dated("solo", "2026-09-05T00:00:00.000Z", group: nil),
            try dated("g1", "2026-09-01T10:00:00.000Z", group: "g"),
            try dated("g2", "2026-09-01T10:00:01.000Z", group: "g"),
        ]
        let lineup = PhotoDetailRules.viewerLineup(context, current: context[0], hiding: ModerationSnapshot())
        XCTAssertEqual(lineup.photos.map(\.id), ["g1", "solo", "g2", "g3"])
        XCTAssertEqual(lineup.index, 3)
        // 詳細の上の束と同じ向き
        XCTAssertEqual(lineup.photos.filter { $0.groupId == "g" }.map(\.id),
                       PhotoGroups.siblings(of: context[0], in: context).map(\.id))
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

/// 下書きにはコメント・いいねを出さない（サーバーが断る）
final class PhotoDetailDraftTests: XCTestCase {
    func testDraftsDoNotAcceptReactions() {
        XCTAssertFalse(PhotoDetailRules.acceptsReactions(published: false))
        XCTAssertTrue(PhotoDetailRules.acceptsReactions(published: true))
        XCTAssertTrue(PhotoDetailRules.acceptsReactions(published: nil), "未指定は公開（サーバーの既定）")
    }

    /// 🔴 **下書きを公開したら読み直す。** 人と写真が同じでも、受け付けるかどうかが変われば鍵が変わる
    func testPublishingADraftReloadsReactions() {
        XCTAssertNotEqual(PhotoDetailRules.reloadKey(userId: "me", photoId: "p1", published: false),
                          PhotoDetailRules.reloadKey(userId: "me", photoId: "p1", published: true),
                          "公開しても読み直さず、コメントの失敗と空のいいねの数が残る")
        // 公開のまま（未指定＝公開）なら読み直さない
        XCTAssertEqual(PhotoDetailRules.reloadKey(userId: "me", photoId: "p1", published: nil),
                       PhotoDetailRules.reloadKey(userId: "me", photoId: "p1", published: true))
        XCTAssertNotEqual(PhotoDetailRules.reloadKey(userId: "me", photoId: "p1", published: true),
                          PhotoDetailRules.reloadKey(userId: nil, photoId: "p1", published: true))
        XCTAssertNotEqual(PhotoDetailRules.reloadKey(userId: "me", photoId: "p1", published: true),
                          PhotoDetailRules.reloadKey(userId: "me", photoId: "p2", published: true))
    }
}
