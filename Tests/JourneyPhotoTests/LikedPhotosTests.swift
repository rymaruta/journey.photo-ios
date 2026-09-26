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
        XCTAssertEqual(LikedPhotos.emptyState(idCount: 0, loaded: false), .loading)
        XCTAssertEqual(LikedPhotos.emptyState(idCount: 3, loaded: false), .loading)
    }

    func testNoneOnlyWhenThereAreNoIds() {
        XCTAssertEqual(LikedPhotos.emptyState(idCount: 0, loaded: true), .none)
    }

    /// **ID があるのに1枚も引き当てられない回は「まだありません」ではない。**
    /// 読み込みに失敗しただけの人に「保存が消えた」と読ませない
    func testUnresolvedWhenIdsExistButNothingMatched() {
        XCTAssertEqual(LikedPhotos.emptyState(idCount: 2, loaded: true), .unresolved)
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

    /// 🔴 **非表示（ブロック・通報）で落ちただけの ID は数えない。** 数えると、
    /// 全部が非表示で消えた人に「読み込めませんでした」と再試行が出続ける
    /// （読み直しても出ない）
    func testHiddenOnlyIdsAreNotCountedAsUnresolved() throws {
        let blocked = try photo("blocked", createdAt: "2026-01-01")
        let n = LikedPhotos.countExcludingHidden(["blocked"], pools: [[blocked], []], visiblePools: [[], []])
        XCTAssertEqual(n, 0)
        XCTAssertEqual(LikedPhotos.emptyState(idCount: n, loaded: true), .none)
    }

    /// 引き当て先に**無い** ID（読み込みの失敗・消された写真）は数える
    /// ——こちらは読み直せば出るかもしれない
    func testMissingIdsAreStillCounted() throws {
        let blocked = try photo("blocked", createdAt: "2026-01-01")
        let n = LikedPhotos.countExcludingHidden(["blocked", "missing"],
                                                 pools: [[blocked]], visiblePools: [[]])
        XCTAssertEqual(n, 1)
        XCTAssertEqual(LikedPhotos.emptyState(idCount: n, loaded: true), .unresolved)
    }

    /// 非表示でも、別の束（自分の写真）で出せるなら落ちていない
    func testIdShownFromAnotherPoolIsNotHidden() throws {
        let p = try photo("x", createdAt: "2026-01-01")
        XCTAssertEqual(LikedPhotos.countExcludingHidden(["x"], pools: [[p], [p]], visiblePools: [[], [p]]), 1)
    }
}
