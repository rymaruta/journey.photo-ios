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

    /// 🔴 **フォロー一覧が取れなかった回（圏外・画面を離れて取り消された回）に、
    /// 同じ人の一覧を空で上書きしない。** 別の人になったら前の人の一覧は使わない
    func testFailedFollowListKeepsTheSameViewersList() async {
        let model = GalleryViewModel()
        model.use(viewerId: "me", following: ["a"])
        model.use(viewerId: "me", following: nil)
        XCTAssertEqual(model.followingIds, ["a"], "取れなかった回に空で上書きした")
        model.use(viewerId: "other", following: nil)
        XCTAssertEqual(model.followingIds, [], "前の人のフォロー一覧を次の人に使った")
        model.use(viewerId: "other", following: ["b"])
        XCTAssertEqual(model.followingIds, ["b"])
    }

    /// 🔴 **後から始めた取得の答えを、先に始めた取得の遅れた答えで戻さない。**
    /// 「フォロー中」を押した取得（古い一覧）の答えが、引き下げの取得（フォローしたばかりの
    /// 人を含む一覧）より後に着くと、その人が「フォロー中」から消えていた
    func testOlderFollowingFetchDoesNotOverwriteANewerOne() async {
        let model = GalleryViewModel()
        model.use(viewerId: "me", following: ["a"])
        let older = model.beginFollowingFetch()
        let newer = model.beginFollowingFetch()
        model.refreshFollowing(["a", "b"], viewerId: "me", ticket: newer)
        model.refreshFollowing(["a"], viewerId: "me", ticket: older)
        XCTAssertEqual(model.followingIds, ["a", "b"], "先に始めた取得の古い一覧で戻した")

        // `.task` の取得（use）も同じ
        let late = model.beginFollowingFetch()
        let latest = model.beginFollowingFetch()
        model.refreshFollowing(["a", "b", "c"], viewerId: "me", ticket: latest)
        model.use(viewerId: "me", following: ["a"], ticket: late)
        XCTAssertEqual(model.followingIds, ["a", "b", "c"])

        // 後から始めた取得が取れなかった回は、先に始めた取得の答えを入れる（手元より新しい）
        let first = model.beginFollowingFetch()
        let second = model.beginFollowingFetch()
        model.refreshFollowing(nil, viewerId: "me", ticket: second)
        model.refreshFollowing(["a", "b", "c", "d"], viewerId: "me", ticket: first)
        XCTAssertEqual(model.followingIds, ["a", "b", "c", "d"])
    }

    /// **A→B→A と戻った回、A の古い取得の答えで一覧を空にして失敗を出さない**（26c2d0c のレビュー）
    func testStaleFollowingAnswerAfterSwitchingBackDoesNotClearTheList() async {
        let model = GalleryViewModel()
        model.use(viewerId: "A", following: ["x"])
        let forA = model.beginFollowingFetch()
        let forB = model.beginFollowingFetch()
        model.use(viewerId: "B", following: ["y"], ticket: forB)
        model.use(viewerId: "A", following: ["x"], ticket: forA)
        XCTAssertFalse(model.followingFailed, "古い答えを「取れなかった」にした")
        XCTAssertEqual(model.followingIds, ["x"], "B の一覧を A に残した")

        // A の古い答えのあとに、A の新しい答えが着く（B の番号で捨てない）
        let olderA = model.beginFollowingFetch()
        let newerA = model.beginFollowingFetch()
        let forB2 = model.beginFollowingFetch()
        model.use(viewerId: "B", following: ["y"], ticket: forB2)
        model.use(viewerId: "A", following: ["old"], ticket: olderA)
        model.refreshFollowing(["old", "new"], viewerId: "A", ticket: newerA)
        XCTAssertEqual(model.followingIds, ["old", "new"], "別の人の番号で、同じ人の新しい答えを捨てた")
    }

    /// 🔴 **札を押して人が替わった回、前の人のフォロー一覧を持ち越さない。**
    /// 持ち越すと、次の人の一覧が取れなかったとき前の人の一覧が「フォロー中」に残る
    func testSelectingAFeedAsAnotherViewerDropsThePreviousList() async {
        let model = GalleryViewModel()
        model.use(viewerId: "a", following: ["x"])
        model.select(feed: .following, viewerId: "b")
        model.use(viewerId: "b", following: nil)
        XCTAssertEqual(model.followingIds, [], "前の人のフォロー一覧が次の人に残った")
        model.refreshFollowing(["x"], viewerId: "a")
        XCTAssertEqual(model.followingIds, [], "前の人に取りに行った一覧を次の人に書いた")
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
        model.refreshFollowing(nil, viewerId: "me")
        XCTAssertTrue(model.followingFailed, "取れなかった回に失敗を外している")

        model.refreshFollowing(["u1"], viewerId: "me")
        XCTAssertFalse(model.followingFailed)
        XCTAssertEqual(model.followingIds, ["u1"])

        // 取れていた集合は、あとで取れなかった回にも残す
        model.refreshFollowing(nil, viewerId: "me")
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

    /// **同じ人で取れなかった回は、手元の集合を潰さない。** 詳細から戻って
    /// `.task` が走り直した回に空にすると、「フォロー中」の一覧が空になり、
    /// 開いた詳細の元のタイルが消えて閉じる（3d75af1 のレビュー）
    func testFailedFollowingForTheSameUserKeepsTheSet() async {
        let model = GalleryViewModel()
        model.use(viewerId: "me", following: ["u1"])
        model.use(viewerId: "me", following: nil)
        XCTAssertEqual(model.followingIds, ["u1"], "同じ人の集合を空で潰している")
        XCTAssertFalse(model.followingFailed)
    }

    /// フィードを先に選んでいても（`select` が viewerId を入れる）、一度も取れていなければ失敗
    func testFailureBeforeAnyFetchIsAFailureEvenAfterSelecting() async {
        let model = GalleryViewModel()
        model.select(feed: .following, viewerId: "me")
        model.use(viewerId: "me", following: nil)
        model.use(viewerId: "me", following: nil)
        XCTAssertTrue(model.followingFailed)
    }

    /// **`use` の前に引き下げで取れた集合も、持ち主つきで残す。** 持ち主を
    /// `self.viewerId`（まだ nil）から取っていたので、次の `.task` の失敗で空に潰れた（e83a88d のレビュー）
    func testFollowingFetchedBeforeUseSurvivesALaterFailure() async {
        let model = GalleryViewModel()
        model.refreshFollowing(["u1"], viewerId: "me")
        model.use(viewerId: "me", following: nil)
        XCTAssertEqual(model.followingIds, ["u1"], "取れた集合を後の失敗で潰している")
        XCTAssertFalse(model.followingFailed)
    }

    /// **人が替わった直後（`use` の前）に取れた今の人の集合を捨てない。** 前の人の集合を
    /// 捨てるのは画面の `auth.userId` の見比べ——モデルが `self.viewerId` と比べると
    /// ここで今の人の正しい集合まで捨てていた（ccb3390 のレビュー）
    func testFollowingForTheNewUserBeforeUseIsKept() async {
        let model = GalleryViewModel()
        model.use(viewerId: "a", following: ["a1"])
        model.refreshFollowing(["b1"], viewerId: "b")
        model.use(viewerId: "b", following: nil)
        XCTAssertEqual(model.followingIds, ["b1"], "今の人の集合を捨てている")
        XCTAssertFalse(model.followingFailed)
    }

    /// **A→B→A と戻った A の一覧を捨てない。** 戻った A は `use` まで「離れた人」に
    /// 入ったままで、その間に引き下げで取れた A の一覧を捨てていた（画面は
    /// `.task` の頭で `expect` を呼ぶ）
    func testFollowingForAViewerWhoCameBackIsKept() async {
        let model = GalleryViewModel()
        model.use(viewerId: "a", following: ["a1"])
        model.expect(viewerId: "b")
        model.use(viewerId: "b", following: ["b1"])
        model.expect(viewerId: "a")
        model.refreshFollowing(["a2"], viewerId: "a")
        XCTAssertEqual(model.followingIds, ["a2"], "戻ってきた人の一覧を捨てている")
        model.use(viewerId: "a", following: nil)
        XCTAssertEqual(model.followingIds, ["a2"])
        XCTAssertFalse(model.followingFailed, "取れていたのに「読み込めませんでした」を出す")
        // 離れた b の遅れた一覧は、引き続き捨てる
        model.refreshFollowing(["b1"], viewerId: "b")
        XCTAssertEqual(model.followingIds, ["a2"], "離れた人の一覧を今の人に書いた")
    }

    /// **人が替わってフィードを押した回に、前の人の「読めた／読めなかった」を持ち越さない。**
    /// 前の人が読めていたら、空の集合で「まだありません」と嘘を出していた
    func testSelectingAFeedAsAnotherViewerDoesNotCarryTheFailureFlag() async {
        let model = GalleryViewModel()
        model.use(viewerId: "a", following: ["x"])
        XCTAssertFalse(model.followingFailed)
        model.select(feed: .following, viewerId: "b")
        XCTAssertEqual(model.followingIds, [])
        XCTAssertTrue(model.followingFailed, "今の人の一覧はまだ無いのに「まだありません」になる")
    }
}
