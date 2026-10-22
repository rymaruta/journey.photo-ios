import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// UI テストの見本の通信（`PreviewBackend`・2026-10-22）。答えが**本物の読み手（Service の型）で読める**こと、
/// 押した状態が次の読みに出ること、知らない口を 401 にしないこと、ふだん（鍵が無い）は何も差し替えないこと
final class PreviewBackendTests: XCTestCase {

    private let uid = "user-1"

    private func reply(_ method: String, _ route: [String], body: Any? = nil,
                       store: PreviewBackend.Store, publicLikes: Int? = 5) async -> PreviewBackend.Reply {
        let data = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return await PreviewBackend.reply(method: method, route: route, body: data, userId: uid,
                                          store: store, publicLikes: { _ in publicLikes })
    }

    func testOffByDefaultSoNothingIsReplaced() {
        // 鍵（`-JPPreviewUserId`・`-JPPreviewLocalBackend`）が無ければ本物の口のまま
        XCTAssertFalse(PreviewBackend.isOn)
        XCTAssertNil(PreviewBackend.tokenProvider)
        XCTAssertNil(PreviewBackend.session)
        XCTAssertNil(PreviewBackend.authGateway)
    }

    /// 見本の通信は**見本の利用者で入っているときだけ**（`PreviewSession.localBackend` の `guard userId != nil`）。
    /// 引数だけが残った起動で、本物のログインの人の鍵の要る口を端末の中の答え手に向けない
    func testLocalBackendNeedsThePreviewUser() {
        let d = UserDefaults.standard
        let user = d.object(forKey: PreviewSession.defaultsKey)
        let flag = d.object(forKey: PreviewSession.localBackendKey)
        defer {
            d.set(user, forKey: PreviewSession.defaultsKey)
            d.set(flag, forKey: PreviewSession.localBackendKey)
        }
        d.set(true, forKey: PreviewSession.localBackendKey)
        d.removeObject(forKey: PreviewSession.defaultsKey)
        XCTAssertFalse(PreviewSession.localBackend, "見本の利用者が居ないのに見本の通信になる")
        XCTAssertNil(PreviewBackend.tokenProvider)
        XCTAssertNil(PreviewBackend.authGateway)
        XCTAssertNil(PreviewBackend.transfer)
        d.set("preview-user", forKey: PreviewSession.defaultsKey)
        XCTAssertTrue(PreviewSession.localBackend)
        XCTAssertNotNil(PreviewBackend.tokenProvider)
        XCTAssertNotNil(PreviewBackend.authGateway)
        d.set(false, forKey: PreviewSession.localBackendKey)
        XCTAssertFalse(PreviewSession.localBackend, "引数が無ければ見本の利用者でも本物の口")
    }

    /// 投稿の本体は答え手へ直に渡る。**空の本体は断る**（写真の中身が届いていないのに投稿が通ったように見せない）
    func testTransferRefusesAnEmptyBodyAndKeepsTheRest() async throws {
        let transfer = PreviewBackend.PreviewTransfer()
        let key = "uploads/u/\(UUID().uuidString).jpg"
        var request = URLRequest(url: URL(string: "https://\(PreviewBackend.host)/put/\(key)")!)
        request.httpMethod = "PUT"
        let empty = try await transfer.upload(request, body: Data(), key: key)
        XCTAssertEqual((empty as? HTTPURLResponse)?.statusCode, 400)
        let ok = try await transfer.upload(request, body: Data([9, 8, 7]), key: key)
        XCTAssertEqual((ok as? HTTPURLResponse)?.statusCode, 200)
        let img = await PreviewBackend.reply(method: "GET", route: [PreviewBackend.host, "img"] + key.split(separator: "/").map(String.init),
                                             body: nil, userId: uid, publicLikes: { _ in nil })
        XCTAssertEqual(img.body, Data([9, 8, 7]))
    }

    func testHandlesOnlyThePreviewTokenAndHost() {
        var signed = URLRequest(url: URL(string: "https://api.example.com/photos/p1/like")!)
        signed.setValue("Bearer \(PreviewBackend.token)", forHTTPHeaderField: "Authorization")
        XCTAssertTrue(PreviewBackend.handles(signed))
        var real = signed
        real.setValue("Bearer eyJ.real.jwt", forHTTPHeaderField: "Authorization")
        XCTAssertFalse(PreviewBackend.handles(real), "本物の鍵の要求は引き受けない")
        XCTAssertFalse(PreviewBackend.handles(URLRequest(url: URL(string: "https://api.example.com/photos/p1/like")!)),
                       "鍵なしの公開の口は本物を読む")
        XCTAssertTrue(PreviewBackend.handles(URLRequest(url: URL(string: "https://\(PreviewBackend.host)/img/a.jpg")!)))
    }

    func testRouteStripsTheApiBasePath() {
        let url = URL(string: "https://api.example.com/prod/user/likes/p1")!
        XCTAssertEqual(PreviewBackend.route(url, basePath: "/prod"), ["user", "likes", "p1"])
        XCTAssertEqual(PreviewBackend.route(URL(string: "https://api.example.com/photos/p1/like")!, basePath: ""),
                       ["photos", "p1", "like"])
        XCTAssertEqual(PreviewBackend.route(URL(string: "https://\(PreviewBackend.host)/put/uploads/u/a.jpg")!, basePath: "/prod"),
                       [PreviewBackend.host, "put", "uploads", "u", "a.jpg"])
    }

    func testLikeAddsOneToThePublicCountAndUnlikeRestoresIt() async throws {
        let store = PreviewBackend.Store()
        let like = await reply("POST", ["photos", "p1", "like"], store: store)
        let liked = try JSONDecoder.api.decode(SocialService.LikeResult.self, from: like.body)
        XCTAssertEqual(liked.liked, true)
        XCTAssertEqual(liked.likes, 6)

        let mine = await reply("GET", ["user", "likes", "p1"], store: store)
        let answer = try JSONDecoder.api.decode(SocialService.MyLike.self, from: mine.body)
        XCTAssertEqual(answer.liked, true)
        XCTAssertEqual(answer.count, 6)

        // 2回目以降は本物を読み直さない（押した後の数で基準がずれない）
        let unlike = await reply("DELETE", ["photos", "p1", "like"], store: store, publicLikes: 99)
        let unliked = try JSONDecoder.api.decode(SocialService.LikeResult.self, from: unlike.body)
        XCTAssertEqual(unliked.liked, false)
        XCTAssertEqual(unliked.likes, 5)
    }

    func testLikeWithoutAPublicCountSendsNoCount() async throws {
        let store = PreviewBackend.Store()
        let like = await reply("POST", ["photos", "p2", "like"], store: store, publicLikes: nil)
        let liked = try JSONDecoder.api.decode(SocialService.LikeResult.self, from: like.body)
        XCTAssertNil(liked.likes, "読めない数は 0 や 1 にしない")
    }

    func testSaveAndUnsave() async throws {
        struct Saved: Decodable { let saved: Bool }
        struct Ids: Decodable { let photoIds: [String] }
        let store = PreviewBackend.Store()
        _ = await reply("POST", ["photos", "p1", "save"], store: store)
        var list = try JSONDecoder().decode(Ids.self, from: await reply("GET", ["user", "saves"], store: store).body)
        XCTAssertEqual(list.photoIds, ["p1"])
        let one = await reply("GET", ["user", "saves", "p1"], store: store)
        XCTAssertTrue(try JSONDecoder().decode(Saved.self, from: one.body).saved)
        _ = await reply("DELETE", ["photos", "p1", "save"], store: store)
        list = try JSONDecoder().decode(Ids.self, from: await reply("GET", ["user", "saves"], store: store).body)
        XCTAssertEqual(list.photoIds, [])
    }

    func testPostedCommentIsReadBackNewestFirst() async throws {
        struct Posted: Decodable { let comment: PhotoComment }
        let store = PreviewBackend.Store()
        let first = try JSONDecoder.api.decode(Posted.self, from: await reply(
            "POST", ["photos", "p1", "comments"], body: ["text": "一つ目"], store: store).body)
        XCTAssertEqual(first.comment.text, "一つ目")
        XCTAssertEqual(first.comment.uid, uid)
        _ = await reply("POST", ["photos", "p1", "comments"], body: ["text": "二つ目"], store: store)
        let page = try JSONDecoder.api.decode(SocialService.CommentPage.self, from: await reply(
            "GET", ["user", "comments", "p1"], store: store).body)
        XCTAssertEqual(page.items.map(\.text), ["二つ目", "一つ目"])
        XCTAssertEqual(page.count, 2)
        // 空の文は断る
        let empty = await reply("POST", ["photos", "p1", "comments"], body: ["text": ""], store: store)
        XCTAssertEqual(empty.status, 400)
    }

    func testUploadRoundTripReturnsAPhotoWithTheTypedTitleAndPlace() async throws {
        let store = PreviewBackend.Store()
        let presign = try JSONDecoder.api.decode(UploadService.PresignResponse.self, from: await reply(
            "POST", ["upload", "presigned-url"], body: ["fileName": "a.jpg", "fileType": "image/jpeg", "fileSize": 3],
            store: store).body)
        XCTAssertEqual(presign.contentType, "image/jpeg")
        let put = URL(string: presign.presignedUrl)!
        XCTAssertEqual(put.host, PreviewBackend.host, "本体は見本の置き場へ（外へ出ない）")
        let putReply = await PreviewBackend.reply(method: "PUT", route: PreviewBackend.route(put, basePath: ""),
                                                  body: Data([1, 2, 3]), userId: uid, store: store, publicLikes: { _ in nil })
        XCTAssertEqual(putReply.status, 200)
        let img = await PreviewBackend.reply(method: "GET", route: PreviewBackend.route(URL(string: presign.publicUrl)!, basePath: ""),
                                             body: nil, userId: uid, store: store, publicLikes: { _ in nil })
        XCTAssertEqual(img.body, Data([1, 2, 3]))

        var draft = PhotoDraft()
        draft.title = "見本の題"
        draft.location = "高屋神社"
        let body = draft.saveBody(key: presign.key, publicUrl: presign.publicUrl)
        let encoded = try JSONEncoder.api.encode(body)
        let saved = await PreviewBackend.reply(method: "POST", route: ["upload", "save"], body: encoded, userId: uid,
                                               store: store, publicLikes: { _ in nil })
        let response = try JSONDecoder.api.decode(UploadService.SaveResponse.self, from: saved.body)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.photo?.displayTitle, "見本の題")
        XCTAssertEqual(response.photo?.location, "高屋神社")
        XCTAssertEqual(response.photo?.userId, uid)
        XCTAssertEqual(response.photo?.published, true)
    }

    func testUnknownRouteIsRefusedWithoutLookingLikeAnExpiredSession() async {
        let store = PreviewBackend.Store()
        let r = await reply("GET", ["user", "notifications"], store: store)
        XCTAssertEqual(r.status, 503, "401 にすると取り直し → ログアウトに倒れる")
    }
}
