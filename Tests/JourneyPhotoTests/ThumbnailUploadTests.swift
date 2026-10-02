import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 一覧用の 512px（`thumbSrc`）を本体と一緒に上げる（2026-10-02）。
///
/// アプリで上げた写真には `thumbSrc` が無く、一覧の格子が元画像（〜1920px）を読んでいた。
/// Web は前から 512px を併せて上げ、保存に `thumbUrl` を送っている（`app/user/upload/page.tsx`）。
/// ここは**送る中身**を模型の通信で見る（JPEG を本当に作るところは Linux の ImageIO 模型では試せない）
final class ThumbnailUploadTests: XCTestCase {

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

    private func api() -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!,
                  tokenProvider: StubTokenProvider(token: "t"), session: session)
    }

    private func service() -> UploadService { UploadService(api: api(), session: session) }

    /// presign が返す形は本物と同じ: `uploads/<sub>/<uuid>.jpg` と CDN の https
    /// （サーバーの `isOwnUploadUrl` が見るのはこの接頭辞・https・CDN の host）
    private let presignBody = """
    {"presignedUrl":"https://s3.example.test/put?sig=1",
     "key":"uploads/u1/abc.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg",
     "photoId":"p1","contentType":"image/jpeg"}
    """

    /// 2回目の presign（サムネイル）は**別の鍵**を返す。同じ答えだと、本体とサムネイルの URL を
    /// 取り違えても緑のまま（2026-10-02 のレビュー）
    private let thumbPresignBody = """
    {"presignedUrl":"https://s3.example.test/put?sig=2",
     "key":"uploads/u1/thumb.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/thumb.jpg",
     "photoId":"p2","contentType":"image/jpeg"}
    """

    /// 本体 → サムネイルの順に別の鍵を返す presign
    private var twoPresigns: [ScriptedProtocol.Step] {
        [.init(match: "/upload/presigned-url", status: 200, body: presignBody, once: true),
         .init(match: "/upload/presigned-url", status: 200, body: thumbPresignBody, once: true)]
    }

    /// 片付け（`/upload/discard`）に送った鍵
    private var discardedKeys: [String] {
        ScriptedProtocol.calls.filter { $0.path == "/upload/discard" }.compactMap {
            (try? JSONSerialization.jsonObject(with: $0.body ?? Data())) as? [String: Any]
        }.compactMap { $0["key"] as? String }
    }

    private func prepared(thumbnail: Data?) -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg",
                               contentType: "image/jpeg", exif: nil, coords: nil, takenOn: nil,
                               thumbnail: thumbnail)
    }

    private func json(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }

    // MARK: - Web と同じ大きさ・品質

    func testThumbnailMatchesTheWebSizeAndQuality() {
        // Web の `createThumbnail(file, maxPx = 512, quality = 0.75)`
        XCTAssertEqual(ImagePreparer.thumbnailMaxPixelSize, 512)
        XCTAssertEqual(ImagePreparer.thumbnailQuality, 0.75)
        // Web の `thumbFileName`（`<名前>_thumb.<拡張子>`）
        XCTAssertEqual(prepared(thumbnail: nil).thumbnailFileName, "photo_thumb.jpg")
    }

    /// 🔴 **サムネイルを作るのは写真の投稿・差し替えだけ。** ストーリー・アイコン・カバーは
    /// `thumbSrc` を持たないので、作ると縮小と読み直しが1回ずつ無駄になる（2026-10-02 のレビュー）
    func testThumbnailIsMadeOnlyForPhotoPostsAndReplacements() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        }
        for path in ["Features/Upload/UploadViewModel.swift", "Features/Profile/EditPhotoView.swift"] {
            XCTAssertTrue(try source(path).contains("withThumbnail: true"), "\(path) がサムネイルを作っていない")
        }
        for path in ["Features/Stories/StoryComposerView.swift", "Features/Profile/ProfileEditView.swift"] {
            XCTAssertFalse(try source(path).contains("withThumbnail: true"), "\(path) がサムネイルを作っている")
        }
        XCTAssertTrue(try source("Services/ImagePreparer.swift").contains("withThumbnail: Bool = false"),
                      "既定は作らない")
    }

    // MARK: - 投稿

    /// 本体 → サムネの順に presign と PUT。サムネの presign は `image/jpeg`・自分の大きさで、
    /// 保存の本文に `thumbUrl`（presign が返した `publicUrl`）が入る
    @MainActor
    func testPostSendsThumbUrlInTheSaveBody() async throws {
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api()),
                                    photos: PhotoService(api: api()), discovery: DiscoveryService(api: api()))
        let thumb = Data(repeating: 0xAB, count: 7)
        model.items = [PendingPhoto(prepared: prepared(thumbnail: thumb))]

        await model.submit()

        XCTAssertEqual(ScriptedProtocol.calls.map(\.path),
                       ["/upload/presigned-url", "/put", "/upload/presigned-url", "/put", "/upload/save"])
        let presigns = ScriptedProtocol.calls.filter { $0.path == "/upload/presigned-url" }
        let thumbPresign = try json(presigns[1].body)
        XCTAssertEqual(thumbPresign["fileName"] as? String, "photo_thumb.jpg")
        XCTAssertEqual(thumbPresign["fileType"] as? String, "image/jpeg",
                       "サーバーの許可リストにある種別（署名に焼き付く）")
        XCTAssertEqual(thumbPresign["fileSize"] as? Int, thumb.count, "サムネ自身の大きさで署名する")
        let puts = ScriptedProtocol.calls.filter { $0.path == "/put" }
        XCTAssertEqual(puts[1].contentType, "image/jpeg", "presign が返した種別で PUT する")
        // PUT の中身は URLProtocol に届かない（`upload(for:from:)`）ので、大きさは presign の署名で見る

        let save = try json(ScriptedProtocol.calls.last?.body)
        XCTAssertEqual(save["thumbUrl"] as? String, "https://cdn.example.test/uploads/u1/thumb.jpg",
                       "サムネイルの presign の URL")
        XCTAssertEqual(save["publicUrl"] as? String, "https://cdn.example.test/uploads/u1/abc.jpg")
        XCTAssertEqual(save["key"] as? String, "uploads/u1/abc.jpg", "保存の鍵は本体（写真の ID の素）")
    }

    /// サムネが無ければ（作れなかった・復元した下書き）、**前と同じ3手**で `thumbUrl` を送らない
    @MainActor
    func testWithoutThumbnailNothingExtraIsSent() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api()),
                                    photos: PhotoService(api: api()), discovery: DiscoveryService(api: api()))
        model.items = [PendingPhoto(prepared: prepared(thumbnail: nil))]

        await model.submit()

        XCTAssertEqual(ScriptedProtocol.calls.map(\.path), ["/upload/presigned-url", "/put", "/upload/save"])
        XCTAssertNil(try json(ScriptedProtocol.calls.last?.body)["thumbUrl"], "無いのにキーを送った")
    }

    /// サムネの PUT が落ちても**本体の投稿は止めない**（Web と同じ）。置けなかったサムネは片付ける
    func testThumbnailFailureDoesNotStopTheUpload() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 500, body: ""),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        let thumb = await service().stageThumbnail(data: Data([1, 2, 3]), fileName: "photo_thumb.jpg")
        XCTAssertNil(thumb, "投げずに nil")
        XCTAssertEqual(ScriptedProtocol.calls.map(\.path), ["/upload/presigned-url", "/put", "/upload/discard"],
                       "置けなかった実体を片付ける")
    }

    /// 🔴 **保存のやり直しは同じ2つの鍵で。** サムネも置き直さない（置き直すと迷子が増える）
    @MainActor
    func testRetryReusesTheThumbnailToo() async throws {
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"保存に失敗しました"}"#),
        ]
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api()),
                                    photos: PhotoService(api: api()), discovery: DiscoveryService(api: api()))
        model.items = [PendingPhoto(prepared: prepared(thumbnail: Data([9, 9])))]
        await model.submit()

        ScriptedProtocol.script = [
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        await model.submit()

        let paths = ScriptedProtocol.calls.map(\.path)
        XCTAssertEqual(paths.filter { $0 == "/upload/presigned-url" }.count, 2, "本体とサムネの1回ずつだけ")
        XCTAssertEqual(paths.filter { $0 == "/put" }.count, 2)
        XCTAssertEqual(try json(ScriptedProtocol.calls.last?.body)["thumbUrl"] as? String,
                       "https://cdn.example.test/uploads/u1/thumb.jpg", "やり直しでもサムネを送る")
    }

    /// 片付けの鍵は本体とサムネの両方
    func testStagedKeysIncludeTheThumbnail() throws {
        let presign = try JSONDecoder().decode(UploadService.PresignResponse.self, from: Data(presignBody.utf8))
        XCTAssertEqual(UploadService.Staged(main: presign, thumb: nil).keys, ["uploads/u1/abc.jpg"])
        XCTAssertEqual(UploadService.Staged(main: presign, thumb: presign).keys.count, 2)
    }

    // MARK: - 差し替え

    /// 差し替えも `replace.thumbUrl` を送る（`photoReplace.ts` の `buildReplace` が `thumbSrc` に書く）
    func testReplaceSendsThumbUrl() async throws {
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/photos/p1", status: 200, body: #"{"success":true}"#),
        ]
        try await PhotoService(api: api()).replace(photoId: "p1", prepared: prepared(thumbnail: Data([1])),
                                                   uploads: service())
        XCTAssertEqual(ScriptedProtocol.calls.map(\.path),
                       ["/upload/presigned-url", "/put", "/upload/presigned-url", "/put", "/photos/p1"])
        let replace = try XCTUnwrap(try json(ScriptedProtocol.calls.last?.body)["replace"] as? [String: Any])
        XCTAssertEqual(replace["thumbUrl"] as? String, "https://cdn.example.test/uploads/u1/thumb.jpg")
        XCTAssertEqual(replace["publicUrl"] as? String, "https://cdn.example.test/uploads/u1/abc.jpg")
        XCTAssertEqual(replace["key"] as? String, "uploads/u1/abc.jpg")
    }

    /// 差し替えの保存が断られたら、**本体とサムネイルの両方**を片付ける
    func testFailedReplaceDiscardsTheThumbnailToo() async throws {
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/photos/p1", status: 500, body: #"{"error":"x"}"#),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        do {
            try await PhotoService(api: api()).replace(photoId: "p1", prepared: prepared(thumbnail: Data([1])),
                                                       uploads: service())
            XCTFail("投げるはず")
        } catch {}
        XCTAssertEqual(Set(discardedKeys), ["uploads/u1/abc.jpg", "uploads/u1/thumb.jpg"])
    }

    // MARK: - 取り消し・片付け

    /// 取り消された回（画面を閉じた）は、サムネイルの presign も PUT も送らない
    func testCancelledThumbnailSendsNothing() async throws {
        ScriptedProtocol.script = twoPresigns + [.init(match: "/put", status: 200, body: "")]
        let uploads = service()
        let task = Task { () -> UploadService.PresignResponse? in
            withUnsafeCurrentTask { $0?.cancel() }
            return await uploads.stageThumbnail(data: Data([1, 2]), fileName: "photo_thumb.jpg")
        }
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertTrue(ScriptedProtocol.calls.isEmpty, "取り消したのに送った: \(ScriptedProtocol.calls.map(\.path))")
    }

    /// 保存が落ちた写真を**外したら**、本体とサムネイルの両方の鍵を片付けに行く
    @MainActor
    func testRemovingAPhotoDiscardsItsThumbnailToo() async throws {
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"x"}"#),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api()),
                                    photos: PhotoService(api: api()), discovery: DiscoveryService(api: api()))
        model.items = [PendingPhoto(prepared: prepared(thumbnail: Data([9])))]
        await model.submit()
        XCTAssertTrue(discardedKeys.isEmpty, "保存の失敗では片付けない（やり直しで使う）")

        model.remove(model.items[0].id)
        try await waitUntil { self.discardedKeys.count >= 2 }
        XCTAssertEqual(Set(discardedKeys), ["uploads/u1/abc.jpg", "uploads/u1/thumb.jpg"])
    }

    /// 保存が落ちたまま画面を閉じた（view model が消えた）ら、両方の鍵を片付けに行く
    @MainActor
    func testClosingDiscardsTheThumbnailToo() async throws {
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"x"}"#),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        var model: UploadViewModel? = UploadViewModel(
            uploads: service(), albums: AlbumService(api: api()),
            photos: PhotoService(api: api()), discovery: DiscoveryService(api: api()))
        model?.items = [PendingPhoto(prepared: prepared(thumbnail: Data([9])))]
        await model?.submit()
        weak var gone = model
        model = nil
        XCTAssertNil(gone, "画面の頭が残っている（deinit が走らない）")
        try await waitUntil { self.discardedKeys.count >= 2 }
        XCTAssertEqual(Set(discardedKeys), ["uploads/u1/abc.jpg", "uploads/u1/thumb.jpg"])
    }

    /// 条件が立つまで待つ（最長5秒）
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// サムネが無い差し替えは `thumbUrl` を送らない（サーバーは `thumbSrc` を消してビルドに作らせる）
    func testReplaceWithoutThumbnailOmitsThumbUrl() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/photos/p1", status: 200, body: #"{"success":true}"#),
        ]
        try await PhotoService(api: api()).replace(photoId: "p1", prepared: prepared(thumbnail: nil),
                                                   uploads: service())
        let replace = try XCTUnwrap(try json(ScriptedProtocol.calls.last?.body)["replace"] as? [String: Any])
        XCTAssertNil(replace["thumbUrl"])
    }
}
