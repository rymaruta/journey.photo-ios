import XCTest
@testable import JourneyPhoto

/// ホームの1本の並び（札 #595・2026-11-13 owner 決定・`HomeFeed`）。
///
/// 上から: 1. フォロー中の人の新しい写真 → 2. 選ばれた写真→いいね順 → 3. 新着（2 の間に4つめごとに混ぜる）。
/// **同じ写真は2回出さない。** 続きのページを読んでも、もう出ている所の順は動かない。
///
/// **指示書 5-2**: 推薦の口は無いので、2 は「owner が選んだ写真 → いいねの多い順」で作る。
final class HomeFeedTests: XCTestCase {

    private func photo(_ id: String, likes: Int? = nil, featured: Bool? = nil,
                       at date: String = "2026-01-01", user: String? = nil, group: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"createdAt\":\"\(date)\""]
        if let likes { fields.append("\"likes\":\(likes)") }
        if let featured { fields.append("\"featured\":\(featured)") }
        if let user { fields.append("\"userId\":\"\(user)\"") }
        if let group { fields.append("\"groupId\":\"\(group)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 番号の大きいほど新しい写真（新着の並び用）
    private func numbered(_ prefix: String, _ range: ClosedRange<Int>, user: String = "u") throws -> [Photo] {
        try range.map { try photo("\(prefix)\($0)", at: String(format: "2026-10-%02dT00:00:00Z", $0), user: user) }
    }

    private func ids(_ photos: [Photo]) -> [String] { photos.map(\.id) }

    // MARK: - 2. 選ばれた写真 → いいね順

    /// **選ばれた写真が先。** その後はいいねの多い順
    func testRecommendedPutsFeaturedFirst() throws {
        let photos = [
            try photo("popular", likes: 99),
            try photo("picked", likes: 1, featured: true),
            try photo("plain", likes: 5),
        ]
        XCTAssertEqual(ids(HomeFeed.recommended(photos)), ["picked", "popular", "plain"])
    }

    // MARK: - 混ぜ方

    /// 新着は **4つめごとに1つ**（選ばれた写真・いいね順 3 つに新着 1 つ）。新着が先に出ていたら飛ばす
    func testLatestIsMixedEveryFourthSlot() throws {
        let rec = try (1...9).map { try photo("r\($0)", likes: 100 - $0) }
        let latest = try numbered("n", 1...3).reversed().map { $0 }   // n3, n2, n1（新しい順）
        let arranged = HomeFeed.arrange(following: [], recommended: rec, latest: latest, latestHasMore: false)
        XCTAssertEqual(ids(arranged.main),
                       ["r1", "r2", "r3", "n3", "r4", "r5", "r6", "n2", "r7", "r8", "r9", "n1"])
        XCTAssertFalse(arranged.truncated)
        XCTAssertEqual(arranged.fromLatest, ["n3", "n2", "n1"])
        // UI テストが新着の1枚目を開く目印（上から 4 枚目・0 から 3）。1. の札も数える
        let rows = HomeFeedPageMemo.make(HomeFeedPageMemo.Input(following: [], recommended: rec, latest: latest,
                                                                latestHasMore: false, excluding: []),
                                         hidden: ModerationSnapshot())
        XCTAssertEqual(rows.firstLatestTile, 3)
        let friend = try photo("f1", at: "2026-11-01", user: "friend")
        let withFollowing = HomeFeedPageMemo.make(HomeFeedPageMemo.Input(following: [friend], recommended: rec, latest: latest,
                                                                         latestHasMore: false, excluding: []),
                                                  hidden: ModerationSnapshot())
        XCTAssertEqual(withFollowing.firstLatestTile, 4)
    }

    /// 🔴 **同じ写真は2回出さない。** 1.（フォロー中）・2.（いいね順）・3.（新着）・横並びのどれに居ても1回だけ
    func testNoPhotoIsShownTwice() throws {
        let shared = try photo("shared", likes: 50, at: "2026-10-30", user: "friend")
        let picked = try photo("picked", likes: 1, featured: true)
        let rec = [shared, picked, try photo("r1", likes: 40), try photo("r2", likes: 30), try photo("r3", likes: 20)]
        let latest = [shared, try photo("n1", at: "2026-10-29"), try photo("r1", likes: 40)]
        let arranged = HomeFeed.arrange(following: [shared], recommended: rec, latest: latest,
                                        latestHasMore: false, excluding: ["picked"])
        let all = ids(arranged.following) + ids(arranged.main)
        XCTAssertEqual(all.count, Set(all).count, "同じ写真が2回出た: \(all)")
        XCTAssertEqual(ids(arranged.following), ["shared"])
        XCTAssertFalse(all.contains("picked"), "横並びに出した写真を並びにも出した")
        XCTAssertEqual(Set(all), ["shared", "r1", "r2", "r3", "n1"])
    }

    /// 🔴 **フォロー中の人の新しい写真がいちばん上。** いいねの多い写真より先
    func testFollowingPhotosComeFirst() throws {
        let theirs = try photo("f1", likes: 0, at: "2026-11-01", user: "friend")
        let rec = [try photo("top", likes: 999), theirs]
        let fresh = HomeFeed.followingFresh(rec, viewerId: "me", followingIds: ["friend"], seen: nil)
        let arranged = HomeFeed.arrange(following: fresh, recommended: HomeFeed.recommended(rec), latest: [theirs],
                                        latestHasMore: false)
        XCTAssertEqual(ids(arranged.following), ["f1"])
        XCTAssertEqual(ids(arranged.main), ["top"], "上に出したフォロー中の写真を下にも出した")
    }

    /// 投稿の束は崩さない（同じ投稿の写真は一緒に出し、別の所に分けない）
    func testPostsStayTogether() throws {
        let a1 = try photo("a1", likes: 5, at: "2026-10-01", user: "u", group: "g")
        let a2 = try photo("a2", likes: 0, at: "2026-10-02", user: "u", group: "g")
        let rec = [a1, try photo("r1", likes: 4), try photo("r2", likes: 3), a2]
        let arranged = HomeFeed.arrange(following: [], recommended: rec, latest: [a2], latestHasMore: false)
        XCTAssertEqual(ids(arranged.main), ["a1", "a2", "r1", "r2"])
    }

    // MARK: - 続きのページ

    /// 🔴 **読めた新着を使い切ったら、続きがある間はそこで切る**（下の目印が次のページを読む）
    func testTruncatesWhereTheLoadedLatestRunsOut() throws {
        let rec = try (1...20).map { try photo("r\($0)", likes: 100 - $0) }
        let latest = try numbered("n", 1...2).reversed().map { $0 }
        let arranged = HomeFeed.arrange(following: [], recommended: rec, latest: latest, latestHasMore: true)
        XCTAssertTrue(arranged.truncated)
        XCTAssertEqual(ids(arranged.main), ["r1", "r2", "r3", "n2", "r4", "r5", "r6", "n1", "r7", "r8", "r9"],
                       "新着を使い切った後も、いいね順を全部並べた（続きを読むと上の順が動く）")
    }

    /// 🔴 **続きを読んでも、もう出ている所の順は崩れない**（足されるのは切った所より後ろだけ）
    func testLoadingTheNextPageKeepsTheShownOrder() throws {
        var rec = try (1...40).map { try photo("r\($0)", likes: 100 - $0) }
        // 2ページ目の新着の1つは、いいね順の後ろの方にも居る（重複を落とす）
        let page1 = try (21...30).reversed().map { try photo("n\($0)", at: String(format: "2026-10-%02d", $0)) }
        let page2 = try (11...20).reversed().map { try photo("n\($0)", at: String(format: "2026-10-%02d", $0)) }
        rec.append(page2[3])
        let before = HomeFeed.arrange(following: [], recommended: rec, latest: page1, latestHasMore: true)
        let after = HomeFeed.arrange(following: [], recommended: rec, latest: page1 + page2, latestHasMore: false)
        XCTAssertTrue(before.truncated)
        XCTAssertFalse(after.truncated)
        XCTAssertEqual(Array(ids(after.main).prefix(before.main.count)), ids(before.main),
                       "続きを読んだら、もう出ていた所の順が変わった")
        XCTAssertEqual(ids(after.main).count, Set(ids(after.main)).count, "続きで同じ写真が2回出た")
        XCTAssertEqual(Set(ids(after.main)), Set(ids(rec) + ids(page1) + ids(page2)), "出し損ねた写真がある")
    }

    /// 新着が読めていない（全件だけ）・いいね順が空（全件が読めない）でも並ぶ
    func testWorksWithOnlyOneSource() throws {
        let rec = try (1...3).map { try photo("r\($0)", likes: 10 - $0) }
        XCTAssertEqual(ids(HomeFeed.arrange(following: [], recommended: rec, latest: [], latestHasMore: false).main),
                       ["r1", "r2", "r3"])
        let latest = try numbered("n", 1...3).reversed().map { $0 }
        let onlyLatest = HomeFeed.arrange(following: [], recommended: [], latest: latest, latestHasMore: true)
        XCTAssertEqual(ids(onlyLatest.main), ["n3", "n2", "n1"])
        XCTAssertTrue(onlyLatest.truncated)
    }

    // MARK: - 1. フォロー中の人の新しい写真

    /// 未ログイン・フォロー 0 のときは何も上に出さない（2. から始まる）
    func testNoFollowingSectionWhenSignedOutOrFollowingNobody() throws {
        let photos = try numbered("f", 1...3, user: "friend")
        XCTAssertTrue(HomeFeed.followingFresh(photos, viewerId: nil, followingIds: ["friend"], seen: nil).isEmpty)
        XCTAssertTrue(HomeFeed.followingFresh(photos, viewerId: "me", followingIds: [], seen: nil).isEmpty)
        let arranged = HomeFeed.arrange(following: [], recommended: photos, latest: [], latestHasMore: false)
        XCTAssertTrue(arranged.following.isEmpty)
        XCTAssertEqual(arranged.main.count, 3)
    }

    /// **まだ上に出していない新しいものだけ**（`seen` より新しい投稿日）。自分の写真・フォローしていない人の写真は出さない
    func testFollowingFreshTakesOnlyUnseenPhotosOfFollowedPeople() throws {
        var photos = try numbered("f", 1...4, user: "friend")
        photos.append(try photo("mine", at: "2026-10-30", user: "me"))
        photos.append(try photo("stranger", at: "2026-10-30", user: "x"))
        let fresh = HomeFeed.followingFresh(photos, viewerId: "me", followingIds: ["friend", "me"],
                                            seen: "2026-10-02T00:00:00Z")
        XCTAssertEqual(ids(fresh), ["f4", "f3"])
        XCTAssertTrue(HomeFeed.followingFresh(photos, viewerId: "me", followingIds: ["friend"],
                                              seen: "2026-10-04T00:00:00Z").isEmpty, "見せたものをまた上に出した")
    }

    /// **数は多すぎないように**: 全体で `followingMax`（5 投稿）まで・1人 `followingPerPerson`（2 投稿）まで
    func testFollowingFreshIsCapped() throws {
        // a が新しい順に3つ続けて載せた日。b・c・d はその前
        let days: [(String, Int)] = [("a", 22), ("a", 21), ("a", 20), ("b", 11), ("b", 10), ("c", 9), ("d", 8)]
        let photos = try days.map { user, day in try photo("\(user)\(day)", at: String(format: "2026-10-%02dT00:00:00Z", day), user: user) }
        let fresh = HomeFeed.followingFresh(photos, viewerId: "me", followingIds: ["a", "b", "c", "d"], seen: nil)
        XCTAssertEqual(fresh.count, HomeFeed.followingMax)
        let perUser = Dictionary(grouping: fresh, by: { $0.userId ?? "" }).mapValues(\.count)
        XCTAssertTrue(perUser.values.allSatisfy { $0 <= HomeFeed.followingPerPerson }, "1人で上を埋めた: \(perUser)")
        XCTAssertEqual(ids(fresh), ["a22", "a21", "b11", "b10", "c9"], "新しい順・1人2つまで・5つまで、になっていない")
    }

    /// 🔴 確かめ役の指摘④: 「おすすめの人」で新しくフォローした人の写真は、**覚え（前に上に出した所）より古くても**上に出す。
    /// 出さないと、フォローして頭へ送っても上に何も出ない（押して何も起きない）
    func testNewlyFollowedPeopleShowRegardlessOfTheSeenMark() throws {
        let photos = [try photo("old", at: "2026-09-01T00:00:00Z", user: "newcomer"),
                      try photo("friendOld", at: "2026-09-02T00:00:00Z", user: "friend")]
        let seen = "2026-10-01T00:00:00Z"
        XCTAssertTrue(HomeFeed.followingFresh(photos, viewerId: "me", followingIds: ["newcomer", "friend"], seen: seen).isEmpty,
                      "前提: 覚えより古い写真は上に出ない")
        let fresh = HomeFeed.followingFresh(photos, viewerId: "me", followingIds: ["newcomer", "friend"], seen: seen,
                                            alwaysNew: ["newcomer"])
        XCTAssertEqual(ids(fresh), ["old"], "新しくフォローした人の写真が上に出ない（前からの人の古い写真は出さない）")
    }

    /// 🔴 確かめ役の指摘③: 見ている間（画面の頭にいない間）は、上の段に写真が**現れない・増えない**（下がずれない）。
    /// 頭にいるとき・引き下げ（`capture`）・新しくフォローしたとき（`addFollowees`）だけ足す
    func testFollowingSectionDoesNotGrowWhileScrolledAway() throws {
        let suite = "HomeFeedTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FollowingSeenStore(defaults: defaults)
        let a = try photo("a", at: "2026-10-01", user: "f")
        let b = try photo("b", at: "2026-10-02", user: "f")
        var baseline = FollowingBaseline()
        baseline.capture(viewer: "me", store: store)
        XCTAssertEqual(ids(baseline.visible([a])), ["a"], "まだ決めていないのに候補を出さない")

        // フォロー一覧が遅れて着いた（最初は空）・下へ送っている間に増えた → 出さない
        baseline.settle(candidates: [], atHead: false)
        baseline.settle(candidates: ["a"], atHead: false)
        XCTAssertTrue(baseline.visible([a]).isEmpty, "下へ送っている間に上の段が現れた（下がずれる）")
        // 頭に戻った → 出す
        baseline.settle(candidates: ["a"], atHead: true)
        XCTAssertEqual(ids(baseline.visible([a])), ["a"])
        // 送っている間に1枚増えた → 増やさない（減るのはよい: ブロックで落ちた分は出さない）
        baseline.settle(candidates: ["b", "a"], atHead: false)
        XCTAssertEqual(ids(baseline.visible([b, a])), ["a"], "下へ送っている間に上の段が増えた")
        XCTAssertTrue(baseline.visible([b]).isEmpty)
        // 引き下げ → 候補をそのまま
        baseline.capture(viewer: "me", store: store)
        XCTAssertEqual(ids(baseline.visible([b, a])), ["b", "a"])
        // 新しくフォローした → 決め直す（頭へ送る）
        baseline.settle(candidates: ["b", "a"], atHead: false)
        baseline.addFollowees(["n"])
        XCTAssertEqual(baseline.followees, ["n"])
        let n = try photo("n", at: "2026-09-01", user: "n")
        XCTAssertEqual(ids(baseline.visible([n, b, a])), ["n", "b", "a"], "フォローした人の写真が上に出ない")
        baseline.capture(viewer: "me", store: store)
        XCTAssertTrue(baseline.followees.isEmpty, "引き下げの後も、新しくフォローした扱いが残る")
    }

    /// 1. の上限で数えるのは投稿（束）。束の写真はまとめて返す
    func testFollowingFreshKeepsPostsWhole() throws {
        let photos = [try photo("p1", at: "2026-10-01", user: "friend", group: "g"),
                      try photo("p2", at: "2026-10-01", user: "friend", group: "g")]
        XCTAssertEqual(Set(ids(HomeFeed.followingFresh(photos, viewerId: "me", followingIds: ["friend"], seen: nil))),
                       ["p1", "p2"])
    }

    // MARK: - 季節の段・控え

    /// 季節の段の前はひと回り（大1→2→2＝5）
    func testSeasonShelfSplitsAfterOneCycle() {
        let split = HomeFeed.splitForSeasonShelf(Array(1...8))
        XCTAssertEqual(split.lead, [1, 2, 3, 4, 5])
        XCTAssertEqual(split.rest, [6, 7, 8])
        XCTAssertEqual(HomeFeed.splitForSeasonShelf([1, 2]).lead, [1, 2])
    }

    /// 並びの控え: 材料と「見せない」が同じなら計算し直さない。ブロックした人の写真は並びに出さない
    func testPageMemoReusesTheAnswerAndDropsBlockedPhotos() throws {
        let memo = HomeFeedPageMemo()
        let rec = [try photo("r1", likes: 2, user: "ok"), try photo("r2", likes: 1, user: "blocked")]
        let input = HomeFeedPageMemo.Input(following: [], recommended: rec, latest: [], latestHasMore: false, excluding: [])
        let shown = memo.rows(input, hidden: ModerationSnapshot())
        _ = memo.rows(input, hidden: ModerationSnapshot())
        XCTAssertEqual(memo.computeCount, 1, "同じ材料で計算し直した")
        XCTAssertEqual(shown.lead.map(\.cover.id), ["r1", "r2"])
        let hidden = ModerationSnapshot(blocked: ["blocked"])
        XCTAssertEqual(memo.rows(input, hidden: hidden).lead.map(\.cover.id), ["r1"], "ブロックした人の写真を並べた")
        XCTAssertEqual(memo.computeCount, 2)
    }
}

/// ホームのフォロー一覧の扱い（1本の並びの 1. を決める・札 #595 で切り替えは外した）。
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

    /// **ログイン状態の反映で範囲・並びを替えない**（ホームはいつも「すべて」の新着の並びを材料にする・#595）。
    /// 以前はここで範囲を「自分」へ倒していた穴があった
    func testSignedInUpdateKeepsTheScopeAndSort() async {
        let model = GalleryViewModel()
        model.use(viewerId: "me", following: ["a"])
        XCTAssertEqual(model.scope, .all)
        XCTAssertEqual(model.sort, .new)
        model.use(viewerId: nil, following: [])
        XCTAssertEqual(model.scope, .all)
        XCTAssertEqual(model.following(for: nil), [], "未ログインでフォロー先を使った")
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

    /// 🔴 **人が替わった回、前の人のフォロー一覧を持ち越さない。**
    /// 持ち越すと、次の人の一覧が取れなかったとき前の人の一覧で上の段（フォロー中の新しい写真）を作る
    func testAnotherViewerDropsThePreviousList() async {
        let model = GalleryViewModel()
        model.use(viewerId: "a", following: ["x"])
        model.expect(viewerId: "b")
        model.use(viewerId: "b", following: nil)
        XCTAssertEqual(model.followingIds, [], "前の人のフォロー一覧が次の人に残った")
        model.refreshFollowing(["x"], viewerId: "a")
        XCTAssertEqual(model.followingIds, [], "前の人に取りに行った一覧を次の人に書いた")
        XCTAssertEqual(model.following(for: "b"), [])
    }

    // MARK: - フォロー一覧を取れなかった回（バグ探し 2026-09-27 #7）

    /// **取れなかった回を「まだありません」にしない。** 以前は空の集合を
    /// 渡していたので、画面は「フォロー中の人の写真はまだありません」と出した
    func testFailedFollowingIsNotAnEmptyFollowing() async {
        let model = GalleryViewModel()
        model.use(viewerId: "me", following: nil)
        XCTAssertTrue(model.followingFailed, "取れなかったのに「まだありません」と区別できない")
        XCTAssertTrue(model.followingIds.isEmpty)
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

    /// 一度も取れていなければ、何度取れなくても失敗のまま
    func testFailureBeforeAnyFetchStaysAFailure() async {
        let model = GalleryViewModel()
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


}
