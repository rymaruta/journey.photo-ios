import XCTest
@testable import JourneyPhoto

final class LikedPhotosTests: XCTestCase {

    private func photo(_ id: String, createdAt: String? = nil) throws -> Photo {
        let created = createdAt.map { ",\"createdAt\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(created)}".utf8))
    }

    /// **「まだ」と「0件」を混ぜない。** 引き当て先を読み終える前は、ID が0でも
    /// 「ありません」と言わない（以前の「いいねした写真」は取得中に空の格子だった）
    func testLoadingWhileThePoolsAreNotLoaded() {
        XCTAssertEqual(LikedPhotos.emptyState(idCount: 0, loaded: false, failed: false), .loading)
        XCTAssertEqual(LikedPhotos.emptyState(idCount: 3, loaded: false, failed: true), .loading)
    }

    func testNoneOnlyWhenThereAreNoIds() {
        XCTAssertEqual(LikedPhotos.emptyState(idCount: 0, loaded: true, failed: false), .none)
        XCTAssertEqual(LikedPhotos.emptyState(idCount: 0, loaded: true, failed: true), .none)
    }

    /// **引き当て先の読み込みが失敗した回だけ「読み込めませんでした」。**
    /// 「まだありません」と言うと、保存やいいねが消えたように読める
    func testUnresolvedOnlyWhenThePoolsFailedToLoad() {
        XCTAssertEqual(LikedPhotos.emptyState(idCount: 2, loaded: true, failed: true), .unresolved)
    }

    /// 🔴 **公開一覧はブロック・通報を落として返る**（`PublicGalleryService` の
    /// `visible`）。画面の持つ feed には非表示の写真が最初から無い——その形で、
    /// 保存した写真が全部非表示の人に「読み込めませんでした」と再試行を出さない
    /// （ddccc38 は絞る前の束がある前提で数え分けていて、実際の形では効かなかった）
    func testIdsOnlyHiddenFromTheFilteredFeedAreNotAnError() throws {
        let feed = [try photo("shown-to-others", createdAt: "2026-01-01")]  // 絞り済み
        let ids: Set<String> = ["blocked-author", "reported"]
        let photos = LikedPhotos.resolve(ids, in: [feed, []])
        XCTAssertTrue(photos.isEmpty, "前提: 引き当て先に無い")
        XCTAssertEqual(LikedPhotos.emptyState(idCount: ids.count, loaded: true, failed: false), .nothingShown)
    }

    /// **他人の写真が出る。** 自分の写真だけを探していたのが元のバグ
    func testFindsOtherPeoplesPhotosFromThePublicFeed() throws {
        let feed = [try photo("other", createdAt: "2026-01-02")]
        let mine = [try photo("mine", createdAt: "2026-01-01")]
        let found = LikedPhotos.resolve(["other", "mine"], in: [feed, mine])
        XCTAssertEqual(found.map(\.id), ["other", "mine"])
    }

    /// 同じ写真が両方にあっても1回だけ
    func testNoDuplicates() throws {
        let same = try photo("x", createdAt: "2026-01-01")
        XCTAssertEqual(LikedPhotos.resolve(["x"], in: [[same], [same]]).map(\.id), ["x"])
    }

    /// 引き当てられない ID は落とす（空の枠を置かない）
    func testDropsIdsThatHaveNoPhoto() throws {
        let feed = [try photo("a", createdAt: "2026-01-01")]
        XCTAssertEqual(LikedPhotos.resolve(["a", "gone"], in: [feed]).map(\.id), ["a"])
    }

    func testNewestFirst() throws {
        let feed = [
            try photo("old", createdAt: "2026-01-01"),
            try photo("new", createdAt: "2026-05-01"),
        ]
        XCTAssertEqual(LikedPhotos.resolve(["old", "new"], in: [feed]).map(\.id), ["new", "old"])
    }

    /// 🔴 **自分の写真の束だけから引き当てた写真は、個別ページが在るとみなさない。**
    /// 投稿直後・非公開の自分の写真は `/photo/<id>` がまだ無い（`PhotoLink`）。
    /// 以前は保存・いいねの一覧から開くと既定の `true` のままで、共有が 404 を指した
    func testOnlyPhotosFoundInThePublicFeedHaveAPage() throws {
        let feed = [try photo("public", createdAt: "2026-01-01")]
        let mine = [try photo("just-posted", createdAt: "2026-09-30"),
                    try photo("public", createdAt: "2026-01-01")]
        let found = LikedPhotos.resolve(["public", "just-posted"], in: [feed, mine])
        let isPublic = LikedPhotos.fromPublicFeed(feed)
        XCTAssertEqual(found.map(\.id), ["just-posted", "public"])
        XCTAssertFalse(isPublic(found[0]), "自分の写真の束だけに在る写真にページは無い")
        XCTAssertTrue(isPublic(found[1]), "公開一覧に在る写真はページが在る")
        XCTAssertFalse(LikedPhotos.fromPublicFeed([])(found[1]), "公開一覧が取れていない回は無いとみなす")
    }
}
