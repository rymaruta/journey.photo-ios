import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 札 #541（2026-11-11 owner 承認）の ①「写真をストーリーで紹介」と ②「コメントに返信」。
/// サーバー（`api-user/src/storyPhotoShare.ts`・`comments.ts`・`notify.ts`）と同じ形を読み書きするか、
/// 並べ方・送るシートの行動・札の寸法の決まりを見る
@MainActor
final class SNSShareReplyTests: XCTestCase {

    private var session: URLSession!

    private func prepare() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
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
        StubProtocol.reset()
        super.tearDown()
    }

    private func api() -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!,
                  tokenProvider: StubTokenProvider(token: "t"), session: session)
    }

    private func comment(_ id: String, uid: String = "u", name: String = "名", replyTo: String? = nil,
                         replyName: String = "相手") -> PhotoComment {
        PhotoComment(id: id, uid: uid, name: name, text: "本文\(id)", t: nil, deleted: nil,
                     replyTo: replyTo.map { .init(id: $0, uid: "r-\($0)", name: replyName, deleted: nil) })
    }

    private func bodyJSON() throws -> [String: Any] {
        let body = try XCTUnwrap(StubProtocol.lastBody)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - ② コメントに返信: 並べ方（Web の `threadComments` と同じ）

    /// 返信は相手のすぐ下に古い順で1段下げて並ぶ。返信への返信も同じ親の下（段は1つ）
    func testRepliesSitUnderTheirParentOldestFirst() async {
        // 一覧は新しい順: r2（r1 への返信）, b, r1（a への返信）, a
        let out = CommentThreads.thread([comment("r2", replyTo: "r1"), comment("b"), comment("r1", replyTo: "a"), comment("a")])
        XCTAssertEqual(out.map(\.comment.id), ["b", "a", "r1", "r2"])
        XCTAssertEqual(out.map(\.isReply), [false, false, true, true])
    }

    /// 相手が一覧に無い返信（消された・ブロックで落とした）は、その場に下げずに残す。輪になっても止まる
    func testOrphanRepliesStayAndCyclesStop() async {
        XCTAssertEqual(CommentThreads.thread([comment("r", replyTo: "gone"), comment("a")]).map(\.isReply), [false, false])
        XCTAssertEqual(CommentThreads.thread([comment("x", replyTo: "y"), comment("y", replyTo: "x")]).count, 2)
    }

    func testMentionAndReplyingLabel() async {
        XCTAssertEqual(CommentThreads.mention(comment("r", replyTo: "a", replyName: "けんじ")), "@けんじ")
        XCTAssertNil(CommentThreads.mention(comment("a")))
        XCTAssertEqual(CommentThreads.replyingLabel(comment("a", name: "けんじ")),
                       L("けんじさんに返信中", "Replying to けんじ"))
    }

    /// 「返信」はログイン中・コメントを受ける写真・退会していない人のコメントだけ
    func testReplyButtonShowsOnlyWhereItWorks() async {
        let alive = comment("a")
        let gone = PhotoComment(id: "g", uid: "g", name: "退会", text: "x", t: nil, deleted: true)
        XCTAssertTrue(CommentThreads.canReply(to: alive, viewerId: "me", acceptsComments: true))
        XCTAssertFalse(CommentThreads.canReply(to: alive, viewerId: nil, acceptsComments: true))
        XCTAssertFalse(CommentThreads.canReply(to: alive, viewerId: "me", acceptsComments: false))
        XCTAssertFalse(CommentThreads.canReply(to: gone, viewerId: "me", acceptsComments: true))
    }

    // MARK: - ② コメントに返信: サーバーの形

    /// 返信の相手を読む。**壊れた相手でも1件ごと落とさない**（ふつうのコメントとして出す）
    func testCommentDecodesReplyToAndToleratesBrokenOnes() async throws {
        let json = #"{"items":[{"id":"c2","uid":"m","name":"みか","text":"坂の上","replyTo":{"id":"c1","uid":"k","name":"退会したユーザー","deleted":true}},{"id":"c3","uid":"m","name":"みか","text":"x","replyTo":42}],"count":2}"#
        let page = try JSONDecoder.api.decode(SocialService.CommentPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.items[0].replyTo, .init(id: "c1", uid: "k", name: "退会したユーザー", deleted: true))
        XCTAssertNil(page.items[1].replyTo)
    }

    /// 「返信」を押してから送ると `replyTo` を付けて送り、送れたら返信中を外す
    func testPostingAReplySendsReplyToAndClearsIt() async throws {
        prepare()
        StubProtocol.respond(path: "/photos/p1/comments", status: 200,
                             body: #"{"comment":{"id":"c9","uid":"me","name":"me","text":"坂の上","replyTo":{"id":"c1","uid":"k","name":"けんじ"}}}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        model.replyingTo = comment("c1", uid: "k", name: "けんじ")
        model.draftComment = "坂の上"
        await model.postComment()
        let body = try bodyJSON()
        XCTAssertEqual(body["text"] as? String, "坂の上")
        XCTAssertEqual(body["replyTo"] as? String, "c1", "返信の相手を送っていない（相手に知らせが届かない）")
        XCTAssertNil(model.replyingTo, "送れたのに返信中のまま")
        XCTAssertEqual(model.comments.first?.replyTo?.name, "けんじ")
    }

    /// ふつうのコメントは `replyTo` を送らない（古いサーバーにも今までどおり）
    func testPlainCommentDoesNotSendReplyTo() async throws {
        prepare()
        StubProtocol.respond(path: "/photos/p1/comments", status: 200,
                             body: #"{"comment":{"id":"c9","uid":"me","name":"me","text":"x"}}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        model.draftComment = "x"
        await model.postComment()
        XCTAssertNil(try bodyJSON()["replyTo"])
    }

    /// 隣の写真へ送ったら返信中を外す（前の写真の人に「返信中」を出さない）
    func testMovingToAnotherPhotoClearsReplying() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.replyingTo = comment("c1")
        model.show(photoId: "p2", initialLikes: nil, liked: false)
        XCTAssertNil(model.replyingTo)
    }

    // MARK: - 知らせ（`storyshare`・`commentreply`）

    func testNewNotificationKindsDecodeAndHaveLines() async throws {
        let share = try JSONDecoder.api.decode(AppNotification.self, from: Data(
            #"{"type":"storyshare","photoId":"mine","photoSrc":"https://x/mine.jpg","byId":"u7","byName":"そら"}"#.utf8))
        XCTAssertEqual(share.kind, .storyshare, "種類を足し忘れると nil になり、行が出ない")
        XCTAssertEqual(NotificationText.line(for: .init(lead: share, others: 0, unread: false))?.plain,
                       L("そら があなたの写真をストーリーで紹介しました", "そら shared your photo in a story"))
        XCTAssertEqual(NotificationText.thumbnailURL(share)?.absoluteString, "https://x/mine.jpg")

        let reply = try JSONDecoder.api.decode(AppNotification.self, from: Data(
            #"{"type":"commentreply","photoId":"p2","photoSrc":"https://x/p2.jpg","byId":"u8","byName":"みか","commentId":"c9"}"#.utf8))
        XCTAssertEqual(reply.kind, .commentreply)
        XCTAssertEqual(NotificationText.line(for: .init(lead: reply, others: 0, unread: false))?.plain,
                       L("みか があなたのコメントに返信しました", "みか replied to your comment"))
    }

    /// 返信は「コメント」の札、紹介は「すべて」だけ（Web の `inTab` と同じ）
    func testFiltersMatchTheWeb() async {
        XCTAssertTrue(NotificationFilter.comment.matches(.commentreply))
        XCTAssertFalse(NotificationFilter.comment.matches(.storyshare))
        XCTAssertTrue(NotificationFilter.all.matches(.storyshare))
        XCTAssertFalse(NotificationFilter.like.matches(.storyshare))
    }

    /// 押すと写真へ（紹介は自分の写真・返信はコメントの付いた写真）
    func testNotificationsOpenThePhoto() async throws {
        let model = NotificationsViewModel()
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"p2","src":"https://x/p2.jpg"}"#.utf8))
        model.setFeedForTesting([photo])
        for type in ["storyshare", "commentreply"] {
            let n = try JSONDecoder.api.decode(AppNotification.self, from: Data(#"{"type":"\#(type)","photoId":"p2"}"#.utf8))
            guard case .photo(let opened, _) = model.destination(for: n) else { return XCTFail("\(type) を押しても写真が開かない") }
            XCTAssertEqual(opened.id, "p2")
        }
    }

    // MARK: - ① 写真をストーリーで紹介: サーバーの形

    /// 紹介した写真の id を読む。形の崩れた値は捨てる（行き先に入れるため）
    func testStoryDecodesSharedPhotoId() async throws {
        let ok = try JSONDecoder.api.decode(Story.self, from: Data(#"{"id":"story-1","src":"https://x/s.jpg","sharedPhotoId":"p1"}"#.utf8))
        XCTAssertEqual(ok.sharedPhotoId, "p1")
        let bad = try JSONDecoder.api.decode(Story.self, from: Data(#"{"id":"story-1","src":"https://x/s.jpg","sharedPhotoId":"../x"}"#.utf8))
        XCTAssertNil(bad.sharedPhotoId)
        let none = try JSONDecoder.api.decode(Story.self, from: Data(#"{"id":"story-1","src":"https://x/s.jpg"}"#.utf8))
        XCTAssertNil(none.sharedPhotoId)
    }

    /// 紹介のときだけ `sharedPhotoId` を送る
    func testCreateRecordSendsSharedPhotoIdOnlyWhenSharing() async throws {
        prepare()
        StubProtocol.respond(path: "/stories", status: 201, body: #"{"success":true}"#)
        let service = StoryService(api: api())
        let media = StoryService.UploadedMedia(key: "uploads/me/a.jpg", publicUrl: "https://cdn/uploads/me/a.jpg")
        _ = try await service.createRecord(media, caption: nil, location: nil, coords: nil, sharedPhotoId: "p1")
        XCTAssertEqual(try bodyJSON()["sharedPhotoId"] as? String, "p1")
        _ = try await service.createRecord(media, caption: nil, location: nil, coords: nil)
        XCTAssertNil(try bodyJSON()["sharedPhotoId"], "紹介でないのに送っている")
    }

    /// 送っている途中で落ちても、紹介の印は戻る（戻したあとに「写真を見る」の無い1本にしない）
    func testSharedPhotoIdSurvivesARelaunch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("story-uploads-\(UUID().uuidString)")
        let center = StoryUploadCenter(directory: dir)
        var release = false
        center.start([StoryUploadCenter.Job(imageData: Data([7]), caption: "", location: "", coords: nil,
                                            song: nil, durationSec: 5, archive: false, sharedPhotoId: "p1"),
                      StoryUploadCenter.Job(imageData: Data([8]), caption: "", location: "", coords: nil,
                                            song: nil, durationSec: 5, archive: false)],
                     ownerId: "me", currentUserId: { "me" },
                     send: { _, _ in
            while !release { await Task.yield() }
            throw URLError(.notConnectedToInternet)
        })
        for _ in 0..<200 { await Task.yield() }

        let relaunched = StoryUploadCenter(directory: dir)
        var sent: [String?] = []
        relaunched.configure(currentUserId: { "me" }, send: { j, _ in sent.append(j.sharedPhotoId) },
                             discardUpload: { _ in })
        relaunched.retry()
        for _ in 0..<200 {
            if case .sending = relaunched.phase { await Task.yield(); continue }
            break
        }
        XCTAssertEqual(sent, ["p1", nil], "戻した並びで紹介の印が落ちた")
        release = true
        center.userChanged(to: nil)
    }

    // MARK: - ① 送るシートと札

    /// ストーリーはログイン中の公開写真だけ。リンクは個別のページがある写真だけ
    func testSendSheetActions() async {
        let url = URL(string: "https://site.example.test/photo/p1")!
        XCTAssertEqual(SendSheetLayout.photoActions(url: url, canShareToStory: true, story: {}).map(\.id),
                       ["story", "copy", "other"])
        XCTAssertEqual(SendSheetLayout.photoActions(url: url, canShareToStory: false, story: {}).map(\.id),
                       ["copy", "other"])
        XCTAssertEqual(SendSheetLayout.photoActions(url: nil, canShareToStory: true, story: {}).map(\.id), ["story"])
        XCTAssertGreaterThan(SendSheetLayout.height(hasPeople: true), SendSheetLayout.height(hasPeople: false))
    }

    /// 送る相手の顔（③）は送れる写真のときだけ・12 人まで
    func testSendSheetFaces() async {
        let people = (0..<20).map { FollowUser(id: "u\($0)", name: "人\($0)", deleted: nil) }
        XCTAssertEqual(SendSheetLayout.faces(people, canSend: true).count, 12)
        XCTAssertTrue(SendSheetLayout.faces(people, canSend: false).isEmpty, "送れない写真に顔の段を出している")
        XCTAssertEqual(SendSheetLayout.sentLabel("けんじ"), L("けんじさんに送りました", "Sent to けんじ"))
    }

    /// 札は地の中に収まり、横は真ん中。細長い写真でも札の縦は決まった幅に収まる。
    /// 「写真を見る」はいちばん縦長の札の下より下（札に重ならない）
    func testCardLayoutStaysInsideAndAboveTheButton() async {
        let canvas = SharedPhotoStoryCard.canvas
        for size in [CGSize(width: 4000, height: 1000), CGSize(width: 3000, height: 4000), CGSize(width: 1000, height: 5000)] {
            let card = SharedPhotoStoryCard.cardRect(imageSize: size)
            XCTAssertGreaterThanOrEqual(card.minY, 0)
            XCTAssertLessThanOrEqual(card.maxY, canvas.height)
            XCTAssertEqual(card.midX, canvas.width / 2, accuracy: 0.5)
            XCTAssertLessThan(card.maxY / canvas.height, SharedPhotoStoryCard.buttonCenterY - 0.03,
                              "「写真を見る」が札に重なる")
            let photo = SharedPhotoStoryCard.photoRect(imageSize: size)
            let aspect = photo.width / photo.height
            XCTAssertGreaterThanOrEqual(aspect, SharedPhotoStoryCard.minPhotoAspect - 0.01)
            XCTAssertLessThanOrEqual(aspect, SharedPhotoStoryCard.maxPhotoAspect + 0.01)
        }
    }

    func testCardLines() async {
        XCTAssertEqual(SharedPhotoStoryCard.handleLine(username: "mika_trip", displayName: "みか"), "@mika_trip")
        XCTAssertEqual(SharedPhotoStoryCard.handleLine(username: nil, displayName: "みか"), "みか")
        XCTAssertEqual(SharedPhotoStoryCard.titleLine(title: " 金沢の夕暮れ ", location: "金沢"), "金沢の夕暮れ")
        XCTAssertEqual(SharedPhotoStoryCard.titleLine(title: "", location: "金沢"), "金沢")
    }

    /// 「写真を見る」は公開の一覧から引き当てる。無ければ開かない（空の詳細を開かない）
    func testSharedPhotoLookup() async throws {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"p1","src":"https://x/p1.jpg"}"#.utf8))
        XCTAssertEqual(StorySharedPhoto.find("p1", in: [photo])?.id, "p1")
        XCTAssertNil(StorySharedPhoto.find("p2", in: [photo]))
        XCTAssertNil(StorySharedPhoto.find("p1", in: nil))
    }

    // MARK: - 確かめ役の直し（2026-11-11）

    private struct Refused: Error {}

    /// 「写真を見る」は確かめてから開く。一覧に無い・持ち主をブロック・サーバーが断った（読めなかった）なら開かない
    func testSharedPhotoOpensOnlyAfterTheServerSaysYes() async throws {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"p1","src":"https://x/p1.jpg","userId":"mika"}"#.utf8))
        var checked: [String] = []
        let ok = await StorySharedPhoto.verified("p1", in: [photo], blocked: []) { checked.append($0) }
        XCTAssertEqual(ok?.id, "p1")
        XCTAssertEqual(checked, ["p1"], "サーバーに確かめずに開いている")
        let refused = await StorySharedPhoto.verified("p1", in: [photo], blocked: []) { _ in throw Refused() }
        XCTAssertNil(refused, "サーバーが断った（非公開・削除・読めない）写真を開いている")
        let blocked = await StorySharedPhoto.verified("p1", in: [photo], blocked: ["mika"]) { _ in }
        XCTAssertNil(blocked, "ブロックした人の写真を開いている")
        let missing = await StorySharedPhoto.verified("p2", in: [photo], blocked: []) { _ in XCTFail("一覧に無いのに確かめに行った") }
        XCTAssertNil(missing)
    }

    /// 「24時間後も自分用に残す」は紹介の写真だけで出さない。混ぜたときは出して、紹介の写真は残らないと添える
    func testKeepToggleSkipsOnlySharedPhotos() async {
        XCTAssertEqual(StorySharedPhoto.keepToggle(sharedFlags: [true]), .hidden)
        XCTAssertEqual(StorySharedPhoto.keepToggle(sharedFlags: [true, true]), .hidden)
        XCTAssertEqual(StorySharedPhoto.keepToggle(sharedFlags: [true, false]),
                       .shown(note: StorySharedPhoto.keepSkipsSharedNote), "混ぜると他の写真の切り替えまで消えている")
        XCTAssertEqual(StorySharedPhoto.keepToggle(sharedFlags: [false]), .shown(note: nil))
        XCTAssertEqual(StorySharedPhoto.keepToggle(sharedFlags: []), .shown(note: nil))
    }

    /// 送るシートはすぐ開き、顔を読んでいる間は段の場所を取っておく。読めて顔が無ければ段ごと出さない
    func testSendSheetOpensBeforeFacesLoad() async {
        let people = (0..<3).map { FollowUser(id: "u\($0)", name: "人\($0)", deleted: nil) }
        XCTAssertEqual(SendSheetLayout.peopleRow(loaded: false, people: [], canSend: true), .placeholder)
        XCTAssertEqual(SendSheetLayout.peopleRow(loaded: true, people: people, canSend: true), .faces(people))
        XCTAssertEqual(SendSheetLayout.peopleRow(loaded: true, people: [], canSend: true), .none)
        XCTAssertEqual(SendSheetLayout.peopleRow(loaded: false, people: people, canSend: false), .none,
                       "送れない写真に段（取り置き）を出している")
    }

    /// 返信の知らせはコメントの id を読み、押すとそのコメントの位置へ。手元に無い写真も押せる（取り直して引き当てる）
    func testCommentReplyNotificationGoesToTheComment() async throws {
        let n = try JSONDecoder.api.decode(AppNotification.self,
                                           from: Data(#"{"type":"commentreply","photoId":"p2","commentId":"c9"}"#.utf8))
        XCTAssertEqual(n.commentId, "c9")
        let bad = try JSONDecoder.api.decode(AppNotification.self,
                                             from: Data(#"{"type":"commentreply","photoId":"p2","commentId":"../x"}"#.utf8))
        XCTAssertNil(bad.commentId)
        XCTAssertEqual(AppNotification.fromPush(["type": "commentreply", "photoId": "p2", "commentId": "c9"])?.commentId, "c9")

        let model = NotificationsViewModel()
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"p2","src":"https://x/p2.jpg"}"#.utf8))
        model.setFeedForTesting([photo])
        guard case .comment(let opened, _, let commentId) = model.destination(for: n) else {
            return XCTFail("返信の知らせがコメントの位置へ行かない")
        }
        XCTAssertEqual(opened.id, "p2")
        XCTAssertEqual(commentId, "c9")
        // ふつうのコメントの知らせは今までどおり写真へ
        let plain = try JSONDecoder.api.decode(AppNotification.self,
                                               from: Data(#"{"type":"comment","photoId":"p2","commentId":"c9"}"#.utf8))
        guard case .photo = model.destination(for: plain) else { return XCTFail("コメントの知らせの行き先が変わった") }

        // 手元に無い（範囲を絞った人の写真）→ 押せる。押したら取り直して引き当てる
        model.setFeedForTesting([])
        guard case .findPhoto(let id, let cid) = model.destination(for: n) else {
            return XCTFail("手元に無い写真への返信の知らせが押せない")
        }
        XCTAssertEqual(id, "p2")
        XCTAssertEqual(cid, "c9")
        XCTAssertNotNil(model.route(for: n))
    }

    /// 知らせから来たコメントへは、読み終えてから1回だけ。消えたコメントには送らない。束を送った先では送らない
    func testCommentFocusDecision() async {
        typealias R = PhotoDetailRules
        XCTAssertNil(R.commentToFocus(nil, done: false, showingFirstPhoto: true, loaded: ["c1"], finishedLoading: true))
        XCTAssertNil(R.commentToFocus("c1", done: false, showingFirstPhoto: true, loaded: [], finishedLoading: false),
                     "読み終える前に決めている")
        XCTAssertEqual(R.commentToFocus("c1", done: false, showingFirstPhoto: true, loaded: ["c0", "c1"], finishedLoading: true), .some("c1"))
        XCTAssertEqual(R.commentToFocus("gone", done: false, showingFirstPhoto: true, loaded: ["c1"], finishedLoading: true), .some(nil))
        XCTAssertNil(R.commentToFocus("c1", done: true, showingFirstPhoto: true, loaded: ["c1"], finishedLoading: true), "2回送っている")
        XCTAssertNil(R.commentToFocus("c1", done: false, showingFirstPhoto: false, loaded: ["c1"], finishedLoading: true),
                     "束を送った先の写真で送っている")
    }
}
