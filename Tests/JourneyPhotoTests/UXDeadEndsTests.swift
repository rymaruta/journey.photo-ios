import XCTest
@testable import JourneyPhoto

/// 体験の行き止まりの直し（2026-10-16・完成度レビュー）。
///
/// 目指す体験は「写真から、次の旅が始まる」——写真に出会う → 撮影場所と撮り方を知る → 行きたい →
/// 撮る → 投稿 → 旅の記録。その途中で、押しても何も起きない・次の一手が無い所を塞いだ。
/// 画面の部品は Linux で動かせないので、決まりは値で、配線は元のコードを読んで確かめる
@MainActor
final class UXDeadEndsTests: XCTestCase {

    // MARK: - 道具

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let head = text.range(of: start) else { return "" }
        let rest = text[head.lowerBound...]
        guard let tail = rest.range(of: end, range: rest.index(after: rest.startIndex)..<rest.endIndex) else {
            return String(rest)
        }
        return String(rest[..<tail.lowerBound])
    }

    private func spot(_ id: String, lat: Double?, lng: Double?, slug: String? = nil,
                      stage: String = "published") throws -> OfficialSpot {
        var fields = ["\"spotId\":\"\(id)\"", "\"slug\":\"\(slug ?? id)\"", "\"name\":\"[\(id)]\"", "\"stage\":\"\(stage)\""]
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func photo(_ id: String, spotId: String? = nil, lat: Double? = nil, lng: Double? = nil) throws -> Photo {
        var json = "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\""
        if let spotId { json += ",\"spotId\":\"\(spotId)\"" }
        if let lat, let lng { json += ",\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}" }
        return try JSONDecoder.api.decode(Photo.self, from: Data((json + "}").utf8))
    }

    // MARK: - 1. 未ログインのストーリー

    /// 開いた時点で決める: 未ログインはログイン画面、確認中は待つ、ログイン済みは作る
    func testStoryComposerAsksToSignInWhenOpened() async {
        XCTAssertEqual(StoryComposerView.stage(userId: nil, isResolving: false), .signIn)
        XCTAssertEqual(StoryComposerView.stage(userId: nil, isResolving: true), .resolving)
        XCTAssertEqual(StoryComposerView.stage(userId: "u1", isResolving: false), .compose)
        XCTAssertEqual(StoryComposerView.signInReason, "ストーリーを投稿するにはログインしてください")
    }

    /// 画面がこの見分けを通り、既存のログイン画面を出す。送る所でも黙って抜けない
    func testStoryComposerWiresSignInAndNeverSilentlyDrops() async throws {
        let view = try source("Features/Stories/StoryComposerView.swift")
        let body = slice(view, from: "    var body: some View {", to: "    private var composer: some View {")
        XCTAssertTrue(body.contains("switch Self.stage(userId: auth.userId, isResolving: auth.isResolving)"))
        XCTAssertTrue(body.contains("SignInView(reason: Self.signInReason)"), "未ログインでログイン画面を出していない")
        XCTAssertTrue(body.contains("case .compose:\n            composer"))
        XCTAssertFalse(view.contains("let ownerId = auth.userId else { return }"),
                       "送る所で未ログインのまま黙って抜ける道が残っている")
        let post = slice(view, from: "private func post(waitedSpots:", to: "guard waitedSpots != nil")
        XCTAssertTrue(post.contains("guard let ownerId = auth.userId else {\n            message = Self.signInReason"))
    }

    // MARK: - 2. この近くの撮影スポット

    /// 2km 以内でいちばん近い行。遠い・座標が無い・スラッグが空の行は出さない
    func testNearbySpotPicksClosestWithinLimit() async throws {
        let near = try spot("near", lat: 35.01, lng: 135.01)    // 約1.4km
        let nearer = try spot("nearer", lat: 35.00, lng: 135.01) // 約0.9km
        let far = try spot("far", lat: 35.05, lng: 135.00)       // 約5.6km
        let noCoords = try spot("nocoords", lat: nil, lng: nil)
        let blank = try spot("blank", lat: 35.00, lng: 135.00, slug: " ")
        let index = [far, near, noCoords, blank, nearer]
        let here = Photo.Coords(lat: 35.00, lng: 135.00)
        XCTAssertEqual(PhotoTrip.nearbySpot(to: here, in: index)?.spotId, "nearer")
        XCTAssertNil(PhotoTrip.nearbySpot(to: here, in: [far, noCoords, blank]), "2km より遠い・座標やスラッグの無い行を出した")
        XCTAssertNil(PhotoTrip.nearbySpot(to: nil, in: index))
        XCTAssertEqual(PhotoTrip.nearbySpotMaxKm, 2)
        // 運営の下書きの行は、いちばん近くても出さない
        let draft = try spot("draft", lat: 35.00, lng: 135.001, stage: "draft")
        XCTAssertTrue(draft.isDraft)
        XCTAssertEqual(PhotoTrip.nearbySpot(to: here, in: [draft, near])?.spotId, "near", "下書きの行を勧めた")
        XCTAssertNil(PhotoTrip.nearbySpot(to: here, in: [draft]))
    }

    /// 鍵は `spotId` の無い写真で、座標のあるときだけ。写真と座標で変わる
    func testNearbySpotKeyOnlyForPhotosWithoutSpotId() async throws {
        XCTAssertNil(PhotoTrip.nearbySpotKey(photo: try photo("p1", spotId: "SPOT-1", lat: 35, lng: 135)),
                     "spotId のある写真は「撮影スポット」の行が受け持つ")
        XCTAssertNil(PhotoTrip.nearbySpotKey(photo: try photo("p2")))
        let a = try XCTUnwrap(PhotoTrip.nearbySpotKey(photo: try photo("p3", lat: 35, lng: 135)))
        XCTAssertNotEqual(a, PhotoTrip.nearbySpotKey(photo: try photo("p4", lat: 35, lng: 135)))
        XCTAssertNotEqual(a, PhotoTrip.nearbySpotKey(photo: try photo("p3", lat: 35.01, lng: 135)))
        // 読み込みの段は、今の写真の鍵で読んだ結果だけを使う（前の写真の行を出さない）
        let loaded = PhotoTrip.Loaded(spotId: a, spot: nil, index: [], photos: nil)
        XCTAssertNotNil(PhotoTrip.stage(photoSpotId: a, loaded: loaded).loaded)
        XCTAssertNil(PhotoTrip.stage(photoSpotId: "other", loaded: loaded).loaded)
    }

    /// 写真の詳細と撮影地の頁が行を出し、台帳の撮影スポットの頁（`OfficialSpotView`）へ行く
    func testNearbySpotRowsAreWired() async throws {
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("placeRow\n            spotGuideRow\n            nearbySpotRow"), "写真の裾に行が無い")
        XCTAssertTrue(detail.contains(".task(id: PhotoTrip.nearbySpotKey(photo: shown) ?? \"\") { await loadNearbySpot() }"))
        XCTAssertTrue(detail.contains("PhotoTrip.nearbySpot(to: shown.coords, in: rows)"))
        let row = slice(detail, from: "private var nearbySpotRow: some View {", to: "private var inspiredRow")
        XCTAssertTrue(row.contains("OfficialSpotView(spot: spot"))
        XCTAssertTrue(row.contains(".foregroundStyle(WebTheme.foreground)"), "写真の上は白だけ")
        XCTAssertFalse(row.contains("WebTheme.accent"), "写真の上に真鍮を置いた")
        XCTAssertTrue(row.contains("WebTheme.minTapTarget"))

        let place = try source("Features/Spots/SpotDetailView.swift")
        XCTAssertTrue(place.contains("stats\n                nearbySpotRow"), "撮影地の頁に行が無い")
        XCTAssertTrue(place.contains("PhotoTrip.nearbySpot(to: coords, in: rows)"))
        XCTAssertTrue(place.contains("OfficialSpotView(spot: official"))
        XCTAssertTrue(place.contains("WebTheme.minTapTarget"))
        XCTAssertEqual(PhotoTrip.nearbySpotTitle, "この近くの撮影スポット")
    }

    // MARK: - 3. 空の画面の次の一手

    /// 空の画面から投稿の流れを開く口。受け取ったら消える
    func testOpenPostHandsOverOnce() async {
        let router = TabRouter()
        let before = router.postRequests
        router.openPost(.trip)
        XCTAssertEqual(router.postRequests, before + 1)
        XCTAssertEqual(router.takePendingPost(), .trip)
        XCTAssertNil(router.takePendingPost(), "2度目に同じ画面を開いた")
        XCTAssertTrue(PostRequestGate.opens(busy: [false, false]))
        XCTAssertFalse(PostRequestGate.opens(busy: [false, true]), "ほかの投稿の画面の上に重ねた")
    }

    func testEmptyStatesOfferOneNextStep() async throws {
        let mypage = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(mypage.contains("""
            EmptyState(message: L("まだ写真がありません", "No photos yet"),
                       actionTitle: MyPageEmpty.postTitle, actionIdentifier: "mypage.emptyPost") {
                tabRouter.openPost(.photo)
            }
"""), "投稿0枚に「写真を投稿」が無い")
        XCTAssertTrue(mypage.contains("actionTitle: MyPageEmpty.browseTitle, actionIdentifier: \"mypage.emptySaved\") {\n                    tabRouter.openHome()"))
        XCTAssertEqual(MyPageEmpty.postTitle, "写真を投稿")

        let shelf = try source("Features/Trips/TripShelf.swift")
        XCTAssertTrue(shelf.contains("actionTitle: isMine ? Self.startTripTitle : nil"), "人の棚にも出している／自分の棚に無い")
        XCTAssertTrue(shelf.contains("action: isMine ? { TabRouter.shared.openPost(.trip) } : nil"))
        XCTAssertEqual(TripShelfList.startTripTitle, "旅の写真からまとめて")

        let book = try source("Features/Pass/PassBookView.swift")
        XCTAssertTrue(book.contains("actionTitle: Self.settingsTitle, actionIdentifier: \"passBook.emptySettings\") {\n                            if fromSettings"))
        XCTAssertTrue(book.contains(".navigationDestination(isPresented: $showSettings) { PassSettingsView() }"))

        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains(".onChange(of: tabRouter.postRequests)"))
        XCTAssertTrue(root.contains("guard let kind = tabRouter.takePendingPost(),"))
        XCTAssertTrue(root.contains("                choosePost(kind)\n            }"), "下の「投稿」と別の道で開いている")
    }

    /// 「ほかの投稿の画面が出ていたら開かない」の並びに、投稿の画面の旗が全部入っている
    /// （1つ抜けると、その画面の上に別の投稿の画面が重なる）
    func testPostRequestGateCoversEveryPostScreen() async throws {
        let root = try source("App/RootView.swift")
        let gate = slice(root, from: "private var postScreensShown: [Bool] {", to: "]\n    }")
        let flags = ["showTripImport", "showPhotoUpload", "showStoryComposer", "showPostChoice", "showPostCamera"]
        for flag in flags {
            XCTAssertTrue(root.contains("@State private var \(flag) = false"), "\(flag) が RootView に無い")
            XCTAssertTrue(gate.contains(flag), "\(flag) が出ている間も空の画面の一手が投稿の画面を開く")
        }
        // 空の画面の一手と、端末の旅の一冊の「この旅の写真を投稿する」が、同じ並びを見る（別々に書くと抜ける）
        XCTAssertEqual(root.components(separatedBy: "PostRequestGate.opens(busy: postScreensShown)").count - 1, 2,
                       "投稿の画面を開く入口が、まとめた並びとは別の確かめをしている")
        XCTAssertFalse(root.contains("guard !showTripImport, !showPhotoUpload"), "手書きの確かめが残っている")
    }

    /// 設定から来たすれちがい帳では、「すれちがいの設定」で設定を積み直さず戻る
    func testPassBookFromSettingsGoesBack() async throws {
        let book = try source("Features/Pass/PassBookView.swift")
        XCTAssertTrue(book.contains("if fromSettings { dismiss() } else { showSettings = true }"))
        let settings = try source("Features/Pass/PassSettingsView.swift")
        XCTAssertTrue(settings.contains("PassBookView(fromSettings: true)"))
        XCTAssertFalse(settings.contains("PassBookView()"), "設定から開く帳が、設定を積み直す")
    }

    // MARK: - 4. アプリの一言

    func testOneTagline() async throws {
        XCTAssertEqual(Labels.Brand.tagline, "写真から、次の旅が始まる。")
        let gate = try source("Features/Legal/LegalGateView.swift")
        let signIn = try source("Features/Auth/SignInView.swift")
        XCTAssertTrue(gate.contains("Text(Labels.Brand.tagline)"))
        XCTAssertTrue(signIn.contains("Text(Labels.Brand.tagline)"))
        XCTAssertFalse(gate.contains("次に撮りたい場所が、見つかる。"))
        XCTAssertFalse(signIn.contains("旅の写真を、一冊の記録に。"))
    }

    // MARK: - 5. 「保存」の呼び名

    func testSavedIsCalledSaveEverywhere() async throws {
        XCTAssertEqual(ProfileTab.favorites.label, "保存")
        let menu = try source("Features/Common/SiteMenuView.swift")
        XCTAssertTrue(menu.contains("SiteMenuRow(title: ProfileTab.favorites.label, systemImage: \"bookmark\""))
        XCTAssertFalse(menu.contains("保存した写真\", \"Saved photos\""))
    }

    // MARK: - 6. カメラで撮る

    func testPostSheetOffersCameraThroughExistingFlow() async throws {
        let sheet = try source("Features/Upload/PostSheet.swift")
        XCTAssertTrue(sheet.contains("if CameraPicker.isAvailable {"), "カメラの無い端末にも出している")
        XCTAssertTrue(sheet.contains("kind: .camera"))
        XCTAssertEqual(PostSheet.cameraTitle, "カメラで撮る")
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("case .camera:\n            pendingCapture = nil\n            showPostCamera = true"))
        // 撮った1枚は構図を重ねて撮ったあとと同じ道（閉じきってから投稿画面へ・`UploadView.initialCapture`）
        XCTAssertTrue(root.contains(".fullScreenCover(isPresented: $showPostCamera, onDismiss: postCapturedPhotoIfAny) {\n                CameraPicker { capture in pendingCapture = capture }"))
    }

    // MARK: - 7. ストーリーへの返信の通知

    private func storyReply(_ storyId: String?) throws -> AppNotification {
        let id = storyId.map { ",\"photoId\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(AppNotification.self, from: Data(
            "{\"type\":\"storyreply\",\"byId\":\"x\",\"t\":\"2026-10-16T01:00:00Z\"\(id)}".utf8))
    }

    private func story(_ id: String, owner: String) throws -> Story {
        try JSONDecoder.api.decode(Story.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"userId\":\"\(owner)\"}".utf8))
    }

    /// まだ出ている自分のストーリーなら返信の一覧へ。消えた・分からない・id が無いなら押せないまま
    func testStoryReplyOpensRepliesWhileStoryIsLive() async throws {
        let model = NotificationsViewModel()
        let reply = try storyReply("S1")
        XCTAssertNil(model.route(for: reply), "分からない間に押せる行にした")
        model.setLiveStoryIdsForTesting(["S1"])
        XCTAssertEqual(model.route(for: reply), .storyReplies("S1"))
        XCTAssertNil(model.route(for: try storyReply("S2")), "消えたストーリーの空の一覧を開いた")
        XCTAssertNil(model.route(for: try storyReply(nil)))
        model.forget()
        XCTAssertNil(model.route(for: reply), "人が替わっても前の人のストーリーを覚えている")
    }

    func testLiveStoryIdsAreOnlyMine() async throws {
        let stories = [try story("S1", owner: "me"), try story("S2", owner: "other")]
        XCTAssertEqual(NotificationsViewModel.liveStoryIds(stories, viewerId: "me"), ["S1"])
    }

    func testStoryRepliesRouteOpensSheet() async throws {
        let view = try source("Features/Notifications/NotificationsView.swift")
        XCTAssertTrue(view.contains("if case .storyReplies(let storyId) = target {\n            repliesStory = StoryRepliesTarget(storyId: storyId)"))
        XCTAssertTrue(view.contains(".sheet(item: $repliesStory) { target in\n            StoryRepliesLoader(storyId: target.storyId)"))
        XCTAssertTrue(view.contains("open(destination)"), "通知を押して開いた回がシートを通らない")
        // 返信のシートが出たまま別の行き先へ行くときは閉じる（シートの下で積まれて見えない）
        let open = slice(view, from: "private func open(_ target:", to: "/// 行き先の画面")
        XCTAssertTrue(open.contains("repliesStory = nil\n            route = target"))
        // 積む道には返信の一覧を置かない（自分の NavigationStack を持つので入れ子になる）
        let destination = slice(view, from: "private func destinationView(", to: "private var emptyState")
        XCTAssertFalse(destination.contains("StoryRepliesLoader"))
        let loader = try source("Features/Stories/StoryRepliesSheet.swift")
        XCTAssertTrue(loader.contains("try await environment.stories.replies(id: storyId)"))
        XCTAssertTrue(loader.contains("BlockFilter.replies(fetched, blocked: hidden.blockedUserIds)"))
    }

    private func notifications(_ json: String) throws -> [AppNotification] {
        try JSONDecoder.api.decode([AppNotification].self, from: Data(json.utf8))
    }

    /// 🔴 **返信の一覧のシート・人のページでブロックして戻っても、お知らせにその人の行が残っていた**（2026-10-16）。
    /// ブロックで落としてから種類で絞る。送り手の無い行（メダル）は残す
    func testNotificationsDropBlockedSendersOnScreen() async throws {
        let rows = try notifications(#"[{"type":"storyreply","byId":"a","photoId":"S1","t":"4"},{"type":"like","byId":"a","photoId":"p1","t":"3"},{"type":"like","byId":"b","photoId":"p2","t":"2"},{"type":"badge","key":"first","tier":1,"t":"1"}]"#)
        XCTAssertEqual(NotificationsView.shown(rows, blocked: ["a"], filter: .all).map(\.byId), ["b", nil])
        XCTAssertEqual(NotificationsView.shown(rows, blocked: ["a"], filter: .like).map(\.byId), ["b"])
        XCTAssertEqual(NotificationsView.shown(rows, blocked: ["a"], filter: .comment).count, 0,
                       "ブロックした人の返信が「コメント」に残った")
        XCTAssertEqual(NotificationsView.shown(rows, blocked: [], filter: .comment).map(\.byId), ["a"])
        // 画面はこの関数を呼ぶだけ（自前で絞らない）
        let view = try source("Features/Notifications/NotificationsView.swift")
        XCTAssertTrue(view.contains("Self.shown(model.rows, blocked: hidden.blockedUserIds, filter: filter)"))
        XCTAssertTrue(view.contains("Self.emptyIsTotal(rows: model.rows, blocked: hidden.blockedUserIds)"))
    }

    /// 空の画面の文言: 全部ブロックした人の行なら、どの種類を選んでいても「まだお知らせはありません」側
    func testNotificationsEmptyIsTotalAfterBlocking() async throws {
        let rows = try notifications(#"[{"type":"like","byId":"a","photoId":"p1","t":"2"},{"type":"comment","byId":"a","photoId":"p1","t":"1"}]"#)
        XCTAssertTrue(NotificationsView.shown(rows, blocked: ["a"], filter: .like).isEmpty)
        XCTAssertTrue(NotificationsView.emptyIsTotal(rows: rows, blocked: ["a"]),
                      "全員ブロック済みなのに「この種類のお知らせはありません」と言う")
        XCTAssertFalse(NotificationsView.emptyIsTotal(rows: rows, blocked: []))
        XCTAssertTrue(NotificationsView.emptyIsTotal(rows: [], blocked: []))
        // 「フォロー」が空でもほかの人の行が残っていれば「この種類が無い」側
        XCTAssertFalse(NotificationsView.emptyIsTotal(rows: rows, blocked: ["b"]))
    }

    /// 🔴 **ブロックの前に届いたプッシュを後で押すと、その人の写真・人のページへ進んでいた**（2026-10-16）
    func testPushTargetFromBlockedSenderDoesNotOpen() async throws {
        let follow = try XCTUnwrap(AppNotification.fromPush(["type": "follow", "byId": "a", "targetUserId": "a"]))
        let like = try XCTUnwrap(AppNotification.fromPush(["type": "like", "byId": "a", "photoId": "p1"]))
        let badge = try XCTUnwrap(AppNotification.fromPush(["type": "badge", "key": "first", "tier": "1"]))
        XCTAssertFalse(NotificationsView.opensPushTarget(follow, blocked: ["a"]))
        XCTAssertFalse(NotificationsView.opensPushTarget(like, blocked: ["a"]))
        XCTAssertTrue(NotificationsView.opensPushTarget(like, blocked: ["b"]))
        XCTAssertTrue(NotificationsView.opensPushTarget(badge, blocked: ["a"]), "送り手の無い通知まで止めた")
        // 押した通知の行き先を受け取るのはお知らせ画面だけで、そこで止める
        let view = try source("Features/Notifications/NotificationsView.swift")
        let task = slice(view, from: ".task(id: router.openActivityRequests)", to: ".sheet(item: $repliesStory)")
        XCTAssertTrue(task.contains("Self.opensPushTarget(target, blocked: hidden.blockedUserIds),\n                  let destination = model.route(for: target)"))
    }

    // MARK: - 8. 文言

    func testWishlistEmptyDoesNotRepeatNothingYet() async throws {
        // いいねした写真の空の文は「いいね」と呼ぶ（「お気に入り」はもう使わない）
        let liked = try source("Features/Profile/FavoritesView.swift")
        XCTAssertTrue(liked.contains("まだいいねした写真がありません"))
        XCTAssertFalse(liked.contains("まだお気に入りがありません"))
        // 撮影地の頁の近くのスポットは、座標を `place` を作らずに取る
        let place = try source("Features/Spots/SpotDetailView.swift")
        XCTAssertTrue(place.contains("private var nearbyCoords: Photo.Coords? { linked.compactMap(\\.coords).first }"))
        XCTAssertTrue(place.contains("let coords = nearbyCoords"))
        XCTAssertFalse(place.contains("place.coords.map { \"near|"))
        XCTAssertFalse(MyPageEmpty.wishlistMessage.contains("まだありません"), "見出しと本文で「まだありません」を重ねた")
        let mypage = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(mypage.contains("message: MyPageEmpty.wishlistMessage)"))
        let search = try source("Features/Search/SearchView.swift")
        XCTAssertTrue(search.contains("\"Browse by color\""))
        XCTAssertFalse(search.contains("colour"))
    }
}
