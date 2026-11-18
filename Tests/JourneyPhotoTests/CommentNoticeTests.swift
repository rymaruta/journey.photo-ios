import XCTest
@testable import JourneyPhoto

/// 案 B4（2026-11-18 owner 採用）: 写真へのコメントの知らせに本文の1行を出し、押すとそのコメントの位置で
/// **返信を書ける状態**（「〇〇さんに返信中 ×」とキーボード）で開く。光らせる（2秒白くする）のはやめた。
/// サーバーは `api-user/src/comments.ts` の `postComment` が `commentId` と本文の抜粋 `text` を足す
@MainActor
final class CommentNoticeTests: XCTestCase {

    private func notice(_ json: String) throws -> AppNotification {
        try JSONDecoder.api.decode(AppNotification.self, from: Data(json.utf8))
    }

    private func line(_ n: AppNotification) -> NotificationText.Line? {
        NotificationText.line(for: .init(lead: n, others: 0, unread: false))
    }

    // MARK: - お知らせの行（板 Notifications「霧の人 がコメントしました：「稜線の色がきれいですね」」）

    func testCommentLineShowsTheExcerpt() async throws {
        let n = try notice(#"{"type":"comment","photoId":"p1","byName":"霧の人","commentId":"c5","text":"稜線の色がきれいですね"}"#)
        XCTAssertEqual(n.commentText, "稜線の色がきれいですね")
        let l = try XCTUnwrap(line(n))
        XCTAssertEqual(l.who, "霧の人")
        XCTAssertEqual(l.plain, "霧の人 がコメントしました：「稜線の色がきれいですね」")
        XCTAssertEqual(l.lineLimit, 3, "本文を出す行は 3 段で切る")
    }

    /// 本文の無い古い行・消されたコメント（サーバーが抜粋を消す）・空白だけは、今までどおりの文
    func testCommentLineWithoutExcerptStaysAsBefore() async throws {
        for json in [#"{"type":"comment","photoId":"p1","byName":"朝凪"}"#,
                     #"{"type":"comment","photoId":"p1","byName":"朝凪","commentId":"c1","text":"  \n "}"#,
                     #"{"type":"comment","photoId":"p1","byName":"朝凪","text":42}"#] {
            let n = try notice(json)
            XCTAssertNil(n.commentText, json)
            let l = try XCTUnwrap(line(n))
            XCTAssertEqual(l.plain, "朝凪 がコメントしました", json)
            XCTAssertNil(l.lineLimit, json)
        }
    }

    /// 本文の欄はコメントの知らせのものだけ（ほかの種類の行の文は変えない）
    func testOtherKindsIgnoreText() async throws {
        let like = try notice(#"{"type":"like","photoId":"p1","byName":"A","text":"x"}"#)
        XCTAssertEqual(line(like)?.plain, "A があなたの写真にいいねしました")
        let reply = try notice(#"{"type":"commentreply","photoId":"p1","byName":"A","commentId":"c1","text":"x"}"#)
        XCTAssertEqual(line(reply)?.plain, "A があなたのコメントに返信しました")
    }

    // MARK: - 行き先（押す回数: 今 4＋下へ送る → 案 3）

    func testCommentNoticeGoesToTheComment() async throws {
        let model = NotificationsViewModel()
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"p2","src":"https://x/p2.jpg"}"#.utf8))
        model.setFeedForTesting([photo])
        let n = try notice(#"{"type":"comment","photoId":"p2","commentId":"c9","text":"すてき"}"#)
        guard case .comment(let opened, _, let commentId) = model.destination(for: n) else {
            return XCTFail("コメントの知らせがコメントの位置へ行かない")
        }
        XCTAssertEqual(opened.id, "p2")
        XCTAssertEqual(commentId, "c9")
        // プッシュから来ても同じ（`deliverPush` は commentId を載せる・本文は載せない）
        let pushed = try XCTUnwrap(AppNotification.fromPush(["type": "comment", "photoId": "p2", "commentId": "c9"]))
        guard case .comment(_, _, "c9") = model.destination(for: pushed) else {
            return XCTFail("コメントのプッシュがコメントの位置へ行かない")
        }
        // 形の崩れた id は捨てて、写真の頭で開く
        let bad = try notice(#"{"type":"comment","photoId":"p2","commentId":"../x"}"#)
        guard case .photo = model.destination(for: bad) else { return XCTFail("崩れた id で写真が開かない") }
    }

    // MARK: - 着いたら返信の欄を開く

    private func comment(_ id: String, uid: String = "u2", deleted: Bool? = nil) -> PhotoComment {
        PhotoComment(id: id, uid: uid, name: "霧の人", text: "本文", t: nil, deleted: deleted)
    }

    func testArrivalOpensReplyOnlyWhereReplyWorks() async {
        typealias R = PhotoDetailRules
        let list = [comment("c1"), comment("c5"), comment("gone-user", deleted: true)]
        XCTAssertEqual(R.replyTargetOnArrival("c5", comments: list, viewerId: "me", acceptsComments: true)?.id, "c5")
        XCTAssertNil(R.replyTargetOnArrival("c5", comments: list, viewerId: nil, acceptsComments: true),
                     "ログアウト中に返信の欄を開いている")
        XCTAssertNil(R.replyTargetOnArrival("c5", comments: list, viewerId: "me", acceptsComments: false),
                     "コメントを受け付けない写真で返信の欄を開いている")
        XCTAssertNil(R.replyTargetOnArrival("gone-user", comments: list, viewerId: "me", acceptsComments: true),
                     "退会した人のコメントに返信の欄を開いている")
        XCTAssertNil(R.replyTargetOnArrival("missing", comments: list, viewerId: "me", acceptsComments: true),
                     "無いコメントに返信の欄を開いている")
    }

    /// キーボードが出終わったら1回だけ送り直す。やめた後・2回目の合図では動かない（回 1462・1466 の数）
    func testKeyboardShowWaitRunsOnce() async {
        let center = NotificationCenter()
        var runs = 0
        let wait = KeyboardShowWait()
        wait.start(center: center) { runs += 1 }
        center.post(name: KeyboardShowWait.didShow, object: nil)
        center.post(name: KeyboardShowWait.didShow, object: nil)
        XCTAssertEqual(runs, 1, "キーボードの合図で1回だけ送り直す")

        let cancelled = KeyboardShowWait()
        cancelled.start(center: center) { runs += 1 }
        cancelled.cancel(center: center)
        center.post(name: KeyboardShowWait.didShow, object: nil)
        XCTAssertEqual(runs, 1, "待つのをやめた後に送り直している")
    }

    // MARK: - 見本の通信（UI テスト `testCommentNoticeOpensReply` が使う）

    func testPreviewBackendReturnsCommentNotices() async throws {
        let store = PreviewBackend.Store()
        let body = try JSONSerialization.data(withJSONObject: ["text": "稜線の色がきれいですね"])
        let posted = await PreviewBackend.reply(method: "POST", route: ["photos", "p1", "comments"], body: body,
                                                userId: "me", store: store, publicLikes: { _ in nil })
        let commentId = try XCTUnwrap(
            ((try JSONSerialization.jsonObject(with: posted.body) as? [String: Any])?["comment"] as? [String: Any])?["id"] as? String)
        // 印が無ければ今までどおり断る（ほかの UI テストのお知らせを変えない）
        let off = await PreviewBackend.reply(method: "GET", route: ["user", "notifications"], body: nil,
                                             userId: "me", store: store, publicLikes: { _ in nil })
        XCTAssertEqual(off.status, 503)
        let on = await PreviewBackend.reply(method: "GET", route: ["user", "notifications"], body: nil,
                                            userId: "me", store: store, commentNotice: true, publicLikes: { _ in nil })
        XCTAssertEqual(on.status, 200)
        // 本物の読み手で読める
        let page = try JSONDecoder.api.decode(NotificationService.Page.self, from: on.body)
        let row = try XCTUnwrap(page.items.first)
        XCTAssertEqual(row.kind, .comment)
        XCTAssertEqual(row.photoId, "p1")
        XCTAssertEqual(row.commentId, commentId)
        XCTAssertEqual(row.commentText, "稜線の色がきれいですね")
        XCTAssertEqual(page.unread, 1)
        let read = await PreviewBackend.reply(method: "PUT", route: ["user", "notifications"], body: nil,
                                              userId: "me", store: store, commentNotice: true, publicLikes: { _ in nil })
        XCTAssertEqual(read.status, 200)
    }
}
