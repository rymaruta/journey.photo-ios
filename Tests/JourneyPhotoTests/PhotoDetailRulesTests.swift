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

    /// 🔴 **詳細の上の送りにも、通報した写真を残さない**（大きく見る画面と同じ絞り方）。
    /// 今の1枚は残し、位置は落とした後の束で引く
    func testHeroGroupDropsReportedLikeTheViewer() async throws {
        func grouped(_ id: String, _ at: String) throws -> Photo {
            try JSONDecoder.api.decode(Photo.self, from: Data(
                "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"userId\":\"me\",\"createdAt\":\"\(at)\",\"groupId\":\"g\"}".utf8))
        }
        let group = [try grouped("g1", "2026-09-01T10:00:00.000Z"),
                     try grouped("g2", "2026-09-01T10:00:01.000Z"),
                     try grouped("g3", "2026-09-01T10:00:02.000Z")]
        let hiding = ModerationSnapshot(reported: ["g1", "g2"])

        // g1・g2 を通報したあと g3 を見ている: 2枚は落ち、位置は落とした後の束で 0
        let hero = PhotoDetailRules.heroGroup(group, current: group[2], hiding: hiding)
        XCTAssertEqual(hero.photos.map(\.id), ["g3"])
        XCTAssertEqual(hero.index, 0)

        // 通報した1枚そのものを見ている間は残す
        let own = PhotoDetailRules.heroGroup(group, current: group[1], hiding: hiding)
        XCTAssertEqual(own.photos.map(\.id), ["g2", "g3"])
        XCTAssertEqual(own.index, 0)

        // 大きく見る画面の束と同じ並び
        let lineup = PhotoDetailRules.viewerLineup(group, current: group[1], hiding: hiding)
        XCTAssertEqual(own.photos.map(\.id), lineup.photos.map(\.id))
    }

    /// 🔴 **束の1枚を非公開に編集してから隣へ送っても、上の送りに残す**（大きく見る画面と同じ）。
    /// 上の束だけ素の並び（`published` が古い）で絞っていて、消した印（`gone`）でその1枚が落ちた
    func testHeroGroupKeepsASiblingEditedToPrivate() async throws {
        func grouped(_ id: String, _ at: String, published: Bool) throws -> Photo {
            try JSONDecoder.api.decode(Photo.self, from: Data(
                "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"userId\":\"me\",\"createdAt\":\"\(at)\",\"groupId\":\"g\",\"published\":\(published)}".utf8))
        }
        let group = [try grouped("g1", "2026-09-01T10:00:00.000Z", published: true),
                     try grouped("g2", "2026-09-01T10:00:01.000Z", published: true)]
        let edits = ["g1": try grouped("g1", "2026-09-01T10:00:00.000Z", published: false)]
        let hiding = ModerationSnapshot(gone: ["g1"])

        // g1 を非公開にしてから g2 へ送った
        let hero = PhotoDetailRules.heroGroup(group, current: group[1], hiding: hiding, edits: edits)
        XCTAssertEqual(hero.photos.map(\.id), ["g1", "g2"])
        XCTAssertEqual(hero.index, 1)
        XCTAssertEqual(hero.photos.first?.published, false, "編集後の姿で出す")
        // 大きく見る画面と同じ並び
        let lineup = PhotoDetailRules.viewerLineup(group, current: group[1], hiding: hiding, edits: edits)
        XCTAssertEqual(hero.photos.map(\.id), lineup.photos.map(\.id))
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

    // MARK: - 大きく見る画面を閉じた後の読み直し（2026-10-03）

    /// 🔴 **読み直しを省くのは、大きく見る画面を閉じた直後で、中身が今の1枚のものとして入っているときだけ**
    func testRereadIsSkippedOnlyRightAfterClosingTheViewer() async {
        let closed = Date(timeIntervalSince1970: 1_000)
        let soon = closed.addingTimeInterval(0.6)
        XCTAssertEqual(PhotoDetailRules.rereadPlan("p1", contentFor: "p1", viewerClosedAt: closed, now: soon), .keep,
                       "閉じた直後に、同じ1枚のコメント・近くの写真を読み直している")
        // 閉じていない（写真の主・近くの写真・タブから戻った）回は読む
        XCTAssertEqual(PhotoDetailRules.rereadPlan("p1", contentFor: "p1", viewerClosedAt: nil, now: soon), .reread,
                       "大きく見る画面と関係ない戻りで、読み直しを省いている")
        // 閉じてから時間が経った戻り（印を消し忘れても）は読む
        let later = closed.addingTimeInterval(PhotoDetailRules.viewerReturnWindow + 1)
        XCTAssertEqual(PhotoDetailRules.rereadPlan("p1", contentFor: "p1", viewerClosedAt: closed, now: later), .reread,
                       "閉じた印が残り、後の別の戻りでも読み直しを省いている")
    }

    /// 🔴 **中身が無い（取り消し・失敗で抜けた）・別の1枚の中身なら、閉じた直後でも読む**。
    /// 読み済みの印が前の1枚のまま残り、戻った1枚のコメント・近くの写真が空のままだった
    func testRereadHappensWhenContentIsMissingOrForAnotherPhoto() async {
        let closed = Date(timeIntervalSince1970: 1_000)
        let soon = closed.addingTimeInterval(0.3)
        XCTAssertEqual(PhotoDetailRules.rereadPlan("p1", contentFor: nil, viewerClosedAt: closed, now: soon), .reread,
                       "中身の無い1枚を読み直さない")
        XCTAssertEqual(PhotoDetailRules.rereadPlan("p1", contentFor: "p2", viewerClosedAt: closed, now: soon), .reread,
                       "前の1枚の中身を、今の1枚の読み済みと扱っている")
        XCTAssertEqual(PhotoDetailRules.rereadPlan("", contentFor: nil, viewerClosedAt: closed, now: soon), .reread)
    }

    /// 🔴 **読まない回は控えからハートも入れない**（確かめた♥を控えの白で上書きして固まっていた）
    func testKeepPlanDoesNotSyncFromStores() async {
        XCTAssertFalse(PhotoDetailRules.ReloadPlan.keep.syncFromStores, "読み直さない回に控えでハートを上書きする")
        XCTAssertFalse(PhotoDetailRules.ReloadPlan.keep.read)
        XCTAssertTrue(PhotoDetailRules.ReloadPlan.reread.syncFromStores)
        XCTAssertTrue(PhotoDetailRules.ReloadPlan.reread.read)
    }

    /// 🔴 **同じ鍵で取り直す間は、分かっているフォローの状態を残す**（ボタンが一瞬消えていた）。
    /// 人・自分・ブロックが替わったら「分からない」に戻す
    func testFollowStateIsKeptWhileRefetchingTheSameKey() async {
        let kept = PhotoDetailRules.followStart(me: "me", owner: "a", blocked: false, known: true, knownFor: "me|a|false")
        XCTAssertEqual(kept, .init(isFollowing: true, knownFor: "me|a|false", fetchKey: "me|a|false"),
                       "同じ人を取り直す間に、フォロー中のボタンを消している")
        XCTAssertNil(PhotoDetailRules.followStart(me: "me", owner: "b", blocked: false, known: true,
                                                  knownFor: "me|a|false").isFollowing,
                     "前の人の状態で次の人のボタンを出している")
        XCTAssertNil(PhotoDetailRules.followStart(me: "me", owner: "a", blocked: true, known: true,
                                                  knownFor: "me|a|false").isFollowing,
                     "ブロックした相手に前の状態を残している")
        XCTAssertNil(PhotoDetailRules.followStart(me: "me", owner: "a", blocked: false, known: true,
                                                  knownFor: nil).isFollowing)
    }

    /// 🔴 **ログアウト中は覚えた鍵も捨てる。** 残すと、ログアウトで false にした値を、
    /// 同じ人で入り直した直後に「分かっている値」として出していた（フォロー中の人に「フォロー」）
    func testSigningOutForgetsTheKnownFollowKey() async {
        let out = PhotoDetailRules.followStart(me: nil, owner: "a", blocked: false, known: true, knownFor: "me|a|false")
        XCTAssertEqual(out, .init(isFollowing: false, knownFor: nil, fetchKey: nil),
                       "ログアウト中に、前の人で覚えた鍵を残している")
        let back = PhotoDetailRules.followStart(me: "me", owner: "a", blocked: false,
                                                known: out.isFollowing, knownFor: out.knownFor)
        XCTAssertNil(back.isFollowing, "入り直した直後に、ログアウト中の false を「分かっている値」として出している")
        XCTAssertEqual(back.fetchKey, "me|a|false")
        let mine = PhotoDetailRules.followStart(me: "a", owner: "a", blocked: false, known: true, knownFor: "a|a|false")
        XCTAssertEqual(mine, .init(isFollowing: false, knownFor: nil, fetchKey: nil))
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
