import XCTest
@testable import JourneyPhoto

/// トップの「自分 / フォロー中 / すべて」（Web の `?scope=`）。
final class GalleryScopeTests: XCTestCase {

    private func photo(_ id: String, owner: String?, published: Bool = true) -> Photo {
        let ownerPart = owner.map { ",\"userId\":\"\($0)\"" } ?? ""
        let json = #"{"id":"\#(id)","src":"https://x.test/\#(id).jpg"\#(ownerPart),"published":\#(published)}"#
        return try! JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    private var sample: [Photo] {
        [photo("a", owner: "me"), photo("b", owner: "friend"),
         photo("c", owner: "stranger"), photo("d", owner: nil)]
    }

    func testMineKeepsOnlyYourPhotos() {
        let out = GalleryScope.mine.photos(sample, viewerId: "me", followingIds: ["friend"])
        XCTAssertEqual(out.map { $0.id }, ["a"])
    }

    /// **自分の写真は「フォロー中」に入らない**（自分はフォローできない。
    /// 自分の投稿はマイページが持ち場——Web の `timelinePhotos` と同じ）。
    func testFollowingExcludesYourOwnPhotos() {
        let out = GalleryScope.following.photos(sample, viewerId: "me", followingIds: ["friend"])
        XCTAssertEqual(out.map { $0.id }, ["b"])
    }

    /// 誰もフォローしていなければ空（「すべて」に化けない）。
    func testFollowingNobodyShowsNothing() {
        let out = GalleryScope.following.photos(sample, viewerId: "me", followingIds: [])
        XCTAssertTrue(out.isEmpty)
    }

    /// **未ログインでは絞らない**（絞れないので絞らない）。
    func testSignedOutFallsBackToEverything() {
        XCTAssertEqual(GalleryScope.mine.photos(sample, viewerId: nil, followingIds: []).count, 4)
        XCTAssertEqual(GalleryScope.following.photos(sample, viewerId: nil, followingIds: []).count, 4)
    }

    /// 下書きはどの範囲にも出さない。
    func testDraftsAreNeverShown() {
        let photos = [photo("a", owner: "me"), photo("draft", owner: "me", published: false)]
        XCTAssertEqual(GalleryScope.mine.photos(photos, viewerId: "me", followingIds: []).map { $0.id }, ["a"])
        XCTAssertEqual(GalleryScope.all.photos(photos, viewerId: "me", followingIds: []).map { $0.id }, ["a"])
    }
}

/// ストーリーの表示秒数。**既定（5秒）なら送らない**——サーバーも
/// 既定は保存しない（`stories.ts` の `STORY_DEFAULT_DURATION_SEC`）。
final class StoryDurationTests: XCTestCase {

    func testDefaultIsNotSent() {
        XCTAssertNil(StoryService.storedDuration(5))
        XCTAssertNil(StoryService.storedDuration(nil))
    }

    func testOutOfRangeIsClamped() {
        XCTAssertEqual(StoryService.storedDuration(1), 3, "3秒未満は読み切れない")
        XCTAssertEqual(StoryService.storedDuration(60), 15, "15秒を超えると見る側が飽きる")
    }

    func testOtherValuesAreSentAsIs() {
        XCTAssertEqual(StoryService.storedDuration(3), 3)
        XCTAssertEqual(StoryService.storedDuration(10), 10)
    }
}
