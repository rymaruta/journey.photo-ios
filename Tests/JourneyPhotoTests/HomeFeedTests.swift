import XCTest
@testable import JourneyPhoto

/// ホームのフィード（おすすめ / フォロー中 / 新着）。
///
/// **指示書 5-2**:「バックエンドが対応していないフィードを、実装済みで
/// あるかのように表示しない」。推薦の口は無いので、おすすめは
/// 「owner が選んだ写真 → いいねの多い順」で作り、規則を画面にも出す。
final class HomeFeedTests: XCTestCase {

    private func photo(_ id: String, likes: Int? = nil, featured: Bool? = nil,
                       at date: String = "2026-01-01") throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"createdAt\":\"\(date)\""]
        if let likes { fields.append("\"likes\":\(likes)") }
        if let featured { fields.append("\"featured\":\(featured)") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// **選ばれた写真が先。** その後はいいねの多い順
    func testRecommendedPutsFeaturedFirst() throws {
        let photos = [
            try photo("popular", likes: 99),
            try photo("picked", likes: 1, featured: true),
            try photo("plain", likes: 5),
        ]
        XCTAssertEqual(HomeFeed.recommended.arrange(photos).map(\.id),
                       ["picked", "popular", "plain"])
    }

    /// 新着は日付順（いいねは見ない）
    func testLatestIsByDate() throws {
        let photos = [
            try photo("old", likes: 99, at: "2026-01-01"),
            try photo("new", likes: 0, at: "2026-05-01"),
        ]
        XCTAssertEqual(HomeFeed.latest.arrange(photos).map(\.id), ["new", "old"])
    }

    /// フォロー中は**範囲**で絞る側（並びは新着）
    func testFollowingUsesTheFollowingScope() {
        XCTAssertEqual(HomeFeed.following.scope, .following)
        XCTAssertEqual(HomeFeed.following.sort, .new)
        XCTAssertTrue(HomeFeed.following.needsSignIn)
    }

    /// **おすすめには注釈を出す。** 推薦の仕組みがあるように見せない
    func testRecommendedExplainsItself() {
        XCTAssertNotNil(HomeFeed.recommended.note)
        XCTAssertNil(HomeFeed.latest.note, "説明の要らないものに注釈を足さない")
    }
}

/// フィードの切り替えが、ログイン状態の反映で打ち消されないこと。
@MainActor
final class HomeFeedSelectionTests: XCTestCase {

    // `GalleryViewModel` は `PublicGalleryService` を既定で作り、
    // その既定引数が `AppConfig` を読む。Info.plist の無い Linux では
    // ここを差し替えないと落ちる
    override func setUp() {
        super.setUp()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
    }

    override func tearDown() {
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    /// **押したフィードが即座に打ち消されないこと。**
    /// 組み込んだ直後に踏んだ穴——ログイン状態の反映が範囲を
    /// 「自分」へ倒していた
    func testSelectingAFeedSurvivesTheSignedInUpdate() async {
        let model = GalleryViewModel()
        model.select(feed: .latest, viewerId: "me")
        model.use(viewerId: "me", following: [])
        XCTAssertEqual(model.feed, .latest)
        XCTAssertEqual(model.scope, .all, "範囲がフィードの指定と食い違っている")
    }

    /// **未ログインで「フォロー中」に居たら、おすすめへ戻す**
    /// （空の画面に置き去りにしない）
    func testFollowingFallsBackWhenSignedOut() async {
        let model = GalleryViewModel()
        model.select(feed: .following, viewerId: "me")
        model.use(viewerId: nil, following: [])
        XCTAssertEqual(model.feed, .recommended)
    }

    // MARK: - フォロー一覧を取れなかった回（バグ探し 2026-09-27 #7）

    /// **取れなかった回を「まだありません」にしない。** 以前は空の集合を
    /// 渡していたので、画面は「フォロー中の人の写真はまだありません」と出した
    func testFailedFollowingIsNotAnEmptyFollowing() async {
        let model = GalleryViewModel()
        model.select(feed: .following, viewerId: "me")
        model.use(viewerId: "me", following: nil)
        XCTAssertTrue(model.followingFailed, "取れなかったのに「まだありません」と区別できない")
        XCTAssertTrue(model.followingIds.isEmpty)
        XCTAssertEqual(model.feed, .following, "取れなかっただけでフィードを戻している")
    }

    /// 引き下げ・札の押し直しで取れたら失敗を外す。**取れなかった回は何も潰さない**
    func testRefreshingFollowingClearsTheFailureOnlyWhenFetched() async {
        let model = GalleryViewModel()
        model.use(viewerId: "me", following: nil)
        model.refreshFollowing(nil)
        XCTAssertTrue(model.followingFailed, "取れなかった回に失敗を外している")

        model.refreshFollowing(["u1"])
        XCTAssertFalse(model.followingFailed)
        XCTAssertEqual(model.followingIds, ["u1"])

        // 取れていた集合は、あとで取れなかった回にも残す
        model.refreshFollowing(nil)
        XCTAssertEqual(model.followingIds, ["u1"], "取れなかった回に手元の集合を潰している")
        XCTAssertFalse(model.followingFailed)
    }

    /// **人が替わって取れなかった回は、前の人の集合を残さない**
    func testFailedFollowingForANewUserDropsThePreviousSet() async {
        let model = GalleryViewModel()
        model.use(viewerId: "a", following: ["u1"])
        model.use(viewerId: "b", following: nil)
        XCTAssertTrue(model.followingIds.isEmpty, "前の人のフォロー先が残っている")
        XCTAssertTrue(model.followingFailed)
    }

    /// 未ログインは「取れなかった」ではない（そもそも引かない）
    func testSignedOutIsNotAFailure() async {
        let model = GalleryViewModel()
        model.use(viewerId: "me", following: nil)
        model.use(viewerId: nil, following: nil)
        XCTAssertFalse(model.followingFailed)
    }
}
