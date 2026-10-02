import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 🔴 **保存の応答が失われたあと、公開範囲を変えてやり直すと 409 が続いた。**
///
/// やり直しは前回の鍵で保存する（`UploadService.stage` の注記）。前回の保存が実は通っていて、
/// 今回は公開範囲が違うと、サーバーは画像の置き場（`uploads/` と `private/`）が食い違うので
/// 「この写真は保存済みです。公開範囲は、写真の編集から変えられます」の 409 で断る
/// （`api-user/src/upload.ts` の `ConditionalCheckFailedException` の枝）。写真は待ち行列に残り、
/// 押し直しても同じ鍵・同じ 409 で、いつまでも抜けられなかった
final class UploadRetryVisibilityTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        session = URLSession(configuration: config)
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private let presignBody = """
    {"presignedUrl":"https://s3.example.test/put?sig=1",
     "key":"uploads/u1/abc.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg",
     "photoId":"p1","contentType":"image/jpeg"}
    """

    /// サーバーの本文そのまま（`upload.ts` の「保存済み」の 409）
    private let savedAlready = #"{"error":"この写真は保存済みです。公開範囲は、写真の編集から変えられます"}"#

    @MainActor
    private func makeModel() -> UploadViewModel {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        return UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                               photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
    }

    private func photo() -> PendingPhoto {
        PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))
    }

    /// 1回目の保存の応答が切れた（API Gateway の 504。保存そのものは通っている）
    @MainActor
    private func submitWithLostSaveResponse(_ model: UploadViewModel) async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 504, body: #"{"message":"Endpoint request timed out"}"#),
        ]
        await model.submit()
    }

    /// 「保存済み」の 409 を受けたら、その写真は**上がった**として待ち行列から外し、
    /// 前に選んだ公開範囲で投稿済みであることを知らせる（閉じずに知らせを見せる）
    @MainActor
    func testSavedAlready409MovesThePhotoOutOfTheQueue() async throws {
        let model = makeModel()
        model.items = [photo()]
        model.published = true
        model.audience = .followers
        await submitWithLostSaveResponse(model)
        XCTAssertEqual(model.items.count, 1, "前提: 応答が切れた写真は残る")

        // 鍵を控えたまま（ここでは画面の錠を通らずに）公開範囲が変わった回。
        // 別の画面（写真の編集）で公開範囲を変えた回もサーバーは同じ 409 を返す
        model.audience = .everyone
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [.init(match: "/upload/save", status: 409, body: savedAlready)]
        await model.submit()

        XCTAssertTrue(model.items.isEmpty, "保存済みの写真が待ち行列に残り、押し直しても 409 が続く")
        XCTAssertFalse(ScriptedProtocol.calls.contains { $0.path == "/upload/presigned-url" },
                       "新しい鍵で上げ直した（同じ写真が2枚になる）")
        let message = try XCTUnwrap(model.errorMessage, "投稿済みであることを知らせていない")
        XCTAssertTrue(message.contains("投稿済み") || message.contains("already posted"), message)
        XCTAssertFalse(model.didPostAll, "知らせを見せずに画面を閉じる")
        XCTAssertFalse(model.visibilityLocked, "上がったのに公開範囲が変えられないまま")
    }

    /// **同じ 409 でも別の理由（他人の写真とぶつかった）は上がったとみなさない**
    @MainActor
    func testOther409StaysAFailure() async throws {
        let model = makeModel()
        model.items = [photo()]
        await submitWithLostSaveResponse(model)
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [.init(match: "/upload/save", status: 409,
                                         body: #"{"error":"この画像はすでに登録されています"}"#)]
        await model.submit()
        XCTAssertEqual(model.items.count, 1)
        XCTAssertFalse(model.didPostAll)
    }

    /// 🔴 **鍵を控えている写真が1枚でもある間は、公開範囲を変えさせない**（理由を一言で出す）。
    /// 外せば（`remove`）鍵も片付くので、また変えられる
    @MainActor
    func testVisibilityIsLockedWhileAKeyIsKept() async throws {
        let model = makeModel()
        model.items = [photo()]
        model.published = true
        model.audience = .followers
        XCTAssertFalse(model.visibilityLocked)
        XCTAssertNil(model.visibilityLockReason)

        await submitWithLostSaveResponse(model)
        XCTAssertTrue(model.visibilityLocked, "鍵を控えたまま公開範囲を変えられる")
        XCTAssertNotNil(model.visibilityLockReason, "変えられない理由を出していない")

        model.chooseVisibility(published: true, audience: .everyone)
        XCTAssertEqual(model.audience, .followers, "錠が掛かっているのに公開範囲が変わった")
        model.chooseVisibility(published: false, audience: nil)
        XCTAssertTrue(model.published, "錠が掛かっているのに非公開に変わった")

        model.remove(model.items[0].id)
        XCTAssertFalse(model.visibilityLocked, "写真を外しても錠が外れない")
        model.chooseVisibility(published: true, audience: .everyone)
        XCTAssertEqual(model.audience, .everyone)
    }

    /// 「保存済み」の判定は**前方一致**。別の断りの文中に「保存済み」が出ただけでは上がったことにしない
    func testSavedAlreadyMatchesOnlyTheServerSentence() {
        XCTAssertTrue(UploadSummary.isSavedAlready("この写真は保存済みです。公開範囲は、写真の編集から変えられます"))
        XCTAssertFalse(UploadSummary.isSavedAlready("この画像はすでに登録されています"))
        XCTAssertFalse(UploadSummary.isSavedAlready("下書きは保存済みですが、画像を移せませんでした"),
                       "文中の「保存済み」で上がったことにした")
        XCTAssertFalse(UploadSummary.isSavedAlready(""))
    }

    /// 「保存済み」の 409 で写真の ID が分からない（presign が `photoId` を返さなかった）ときは、
    /// 曲を付けられない——**付いたことにせず知らせる**
    @MainActor
    func testSavedAlreadyWithoutPhotoIdReportsTheSongAsNotAttached() async throws {
        let model = makeModel()
        model.song = Photo.Song(title: "曲", artist: nil, artwork: nil,
                                previewUrl: "https://example.test/p.m4a", trackUrl: nil)
        model.items = [photo()]
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","contentType":"image/jpeg"}
            """),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 504, body: "{}"),
        ]
        await model.submit()
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [.init(match: "/upload/save", status: 409, body: savedAlready)]
        await model.submit()

        XCTAssertTrue(model.items.isEmpty)
        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(message.contains("曲") || message.contains("song"), "曲が付かなかったことを言っていない: \(message)")
        XCTAssertFalse(ScriptedProtocol.calls.contains { $0.path.hasPrefix("/photos/") }, "ID の無い写真に曲を付けにいった")
    }

    /// 🔴 **送っている間は公開範囲を変えない**（`chooseVisibility`）。送信は1枚ごとにその時点の値を読む
    @MainActor
    func testVisibilityDoesNotChangeWhileSending() async throws {
        let gate = Gate(holds: 1)
        let gates = PathGates(["/upload/presigned-url": gate])
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session,
                            beforeRequest: { await gates.wait(for: $0) })
        let model = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        model.items = [photo()]
        model.chooseVisibility(published: true, audience: .followers)
        let sending = Task { await model.submit() }
        await gate.untilWaiting()
        XCTAssertTrue(model.isWorking, "前提: 送っている途中")
        XCTAssertFalse(model.visibilityLocked, "前提: 鍵はまだ控えていない（錠ではなく送信中で止める）")

        model.chooseVisibility(published: false, audience: nil)
        model.chooseVisibility(published: true, audience: .everyone)
        XCTAssertTrue(model.published, "送っている間に非公開に変わった")
        XCTAssertEqual(model.audience, .followers, "送っている間に公開範囲が変わった")

        await gate.open()
        await sending.value
        let save = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path == "/upload/save" })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(save.body)) as? [String: Any])
        XCTAssertEqual(json["audience"] as? String, "followers")
    }
}
