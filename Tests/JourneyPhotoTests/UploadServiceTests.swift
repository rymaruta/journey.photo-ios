import XCTest
@testable import JourneyPhoto
// `PhotosPickerItem` は PhotosUI と SwiftUI の重なりにある。**両方要る**
// （片方だと Xcode でだけ落ちる・`Tools/check-cross-imports.py`）
import SwiftUI
import PhotosUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿の3手（presign → S3 に PUT → save）。
///
/// **2手目と3手目の間で落ちたら S3 に迷子が残る。** そこを実際に走らせて見る。
final class UploadServiceTests: XCTestCase {

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

    private func service() -> UploadService {
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        return UploadService(api: api, session: session)
    }

    private let presignBody = """
    {"presignedUrl":"https://s3.example.test/put?sig=1",
     "key":"uploads/u1/abc.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg",
     "photoId":"p1","contentType":"image/jpeg"}
    """

    /// 3手が順番どおり呼ばれ、**PUT の Content-Type は presign が返した値**。
    /// presigner が content-type を署名対象に入れているので、違う値で送ると
    /// 署名が合わない（`api-user/src/uploadPolicy.ts` の経緯）。
    func testHappyPathSendsSignedContentType() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        let presigned = try await service().stage(
            data: Data(repeating: 0xFF, count: 16),
            fileName: "photo.jpg", fileType: "image/jpeg"
        )
        let photo = try await service().save(PhotoDraft(), presigned: presigned)
        XCTAssertEqual(photo?.id, "p1")
        XCTAssertEqual(ScriptedProtocol.calls.map(\.path),
                       ["/upload/presigned-url", "/put", "/upload/save"])
        let put = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path == "/put" })
        XCTAssertEqual(put.contentType, "image/jpeg")
        XCTAssertEqual(put.method, "PUT")
    }

    /// **PUT で落ちたら、S3 の迷子を片付ける。** 行はまだ無いので消してよい
    func testDiscardsUploadWhenPutFails() async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 500, body: ""),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        do {
            _ = try await service().stage(
                data: Data(repeating: 0xFF, count: 16),
                fileName: "photo.jpg", fileType: "image/jpeg"
            )
            XCTFail("投げるはず")
        } catch {
            guard case .server(let status, _)? = error as? APIError else {
                return XCTFail("形が違う: \(error)")
            }
            XCTAssertEqual(status, 500)
        }
        XCTAssertTrue(ScriptedProtocol.calls.contains { $0.path == "/upload/discard" },
                      "S3 に迷子が残ったまま")
    }

    /// 🔴 **保存のやり直しは同じ鍵で送る。** 保存が「落ちた」ときも、サーバーには
    /// 行ができていることがある（応答だけ失われた）。やり直しで presign から
    /// 通すと新しい鍵になり、サーバーの「鍵から ID を導く」重複よけが効かず、
    /// 同じ写真が2枚になっていた。片付け（discard）もしない——やり直す鍵の本体が消える
    @MainActor
    func testRetryAfterFailedSaveReusesTheSameKey() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"保存に失敗しました"}"#),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]

        await model.submit()
        XCTAssertEqual(model.items.count, 1, "落ちた写真は残る")
        XCTAssertNotNil(model.errorMessage)

        ScriptedProtocol.script = [
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        await model.submit()
        XCTAssertTrue(model.items.isEmpty)

        let paths = ScriptedProtocol.calls.map(\.path)
        XCTAssertEqual(paths.filter { $0 == "/upload/presigned-url" }.count, 1, "やり直しで新しい鍵をもらっている")
        XCTAssertEqual(paths.filter { $0 == "/put" }.count, 1, "本体を置き直している")
        XCTAssertEqual(paths.filter { $0 == "/upload/save" }.count, 2)
        XCTAssertFalse(paths.contains("/upload/discard"), "やり直す鍵の本体を消している")
    }

    /// 保存が落ちた写真を**本人が外したら**、置いたままの本体を片付ける
    /// （保存の失敗では片付けないので、ここで消さないと S3 に残る）
    @MainActor
    func testRemovingAPhotoWhoseSaveFailedDiscardsItsUpload() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"保存に失敗しました"}"#),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]
        await model.submit()
        XCTAssertFalse(ScriptedProtocol.calls.contains { $0.path == "/upload/discard" })

        model.remove(model.items[0].id)
        try await waitUntil { ScriptedProtocol.calls.contains { $0.path == "/upload/discard" } }
        XCTAssertTrue(ScriptedProtocol.calls.contains { $0.path == "/upload/discard" },
                      "外した写真の本体が S3 に残ったまま")
    }

    /// カメラの1枚は**画面の処理の外で整える**。整えている間は投稿させない
    /// （押すと、その1枚が待ち行列に入る前に送信が始まる）。整えられなければ知らせる
    @MainActor
    func testCapturedPhotoIsPreparedInTheBackgroundAndBlocksSubmitMeanwhile() async throws {
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]
        XCTAssertTrue(model.canSubmit)

        // 模型の ImageIO は読めないので、整えるのは失敗で終わる
        model.accept(capturedJPEG: Data([0x00]))
        XCTAssertFalse(model.canSubmit, "整えている間に投稿できる")
        try await waitUntil { model.canSubmit }
        XCTAssertTrue(model.canSubmit)
        XCTAssertNotNil(model.errorMessage, "整えられなかったことを知らせていない")
        XCTAssertEqual(model.items.count, 1)
    }

    /// **カメラの写真だけの回でも、最後の1枚を外したら束の印を捨てる。**
    /// 残すと、次に撮った写真が前の（一部だけ上がった）投稿の束に入る
    @MainActor
    func testRemovingTheLastCameraPhotoDropsTheGroup() async throws {
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        // どちらも手前で弾かれる形（通信しない）。印は送り始めに作られる
        func camera() -> PendingPhoto {
            PendingPhoto(prepared: ImagePreparer.Prepared(
                data: Data([0xFF]), fileName: "photo.jpg", contentType: "image/svg+xml",
                exif: nil, coords: nil, takenOn: nil))
        }
        model.items = [camera(), camera()]
        model.groupsAsOnePost = true
        await model.submit()
        XCTAssertNotNil(model.groupId)

        model.remove(model.items[0].id)
        XCTAssertNotNil(model.groupId, "まだ1枚残っている")
        model.remove(model.items[0].id)
        XCTAssertNil(model.groupId, "前の投稿の束の印が残っている")
    }

    /// **選び足したときは、前に読めなかった写真も読み直す。** 読み直さないと、
    /// 一時的な失敗が直らないまま知らせが消え、1枚少ないまま投稿できる
    @MainActor
    func testAddingPhotosRetriesThoseThatCouldNotBeLoaded() async throws {
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        let a = PhotosPickerItem(itemIdentifier: "a")
        let c = PhotosPickerItem(itemIdentifier: "c")
        let d = PhotosPickerItem(itemIdentifier: "d")
        var photo = PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data([0xFF]), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))
        photo.pickerItem = a
        model.items = [photo]
        // 模型の PhotosUI は読めない（nil を返す）
        model.pickerItems = [a, c]
        try await waitUntil { !model.isLoadingPicked && model.errorMessage != nil }
        let once = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(once.contains("1"), once)

        model.pickerItems = [a, c, d]
        try await waitUntil { !model.isLoadingPicked && model.errorMessage != nil && model.errorMessage != once }
        let twice = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(twice.contains("2"), "読めなかった c を読み直していない: \(twice)")
    }

    /// 条件が立つまで待つ（既定は最長5秒）。切り離した仕事の終わりを時間で当てない
    @MainActor
    private func waitUntil(seconds: Double = 5, _ condition: () -> Bool) async throws {
        for _ in 0..<Int(seconds * 100) where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// 🔴 **一部だけ上がった回に、投稿済みの写真を選択から外す**——そして
    /// **その直しで読み直しを起こさない。**
    ///
    /// 外さないと、残った1枚を外す・「追加」で選び足すたびに、投稿済みの写真が
    /// 新しく選ばれた分として読み直され、もう一度上がる。外すときに読み直しを
    /// 起こすと、前に読めなかった写真を読み直して「残りは投稿できていません」を消す
    @MainActor
    func testPartialPostDropsPostedItemsFromTheSelectionAndKeepsTheError() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        let a = PhotosPickerItem(itemIdentifier: "a")
        let b = PhotosPickerItem(itemIdentifier: "b")
        // c は読めなかった写真（選択には残り、待ち行列には居ない）
        let c = PhotosPickerItem(itemIdentifier: "c")
        func pending(_ key: PhotosPickerItem, type: String) -> PendingPhoto {
            var photo = PendingPhoto(prepared: ImagePreparer.Prepared(
                data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: type,
                exif: nil, coords: nil, takenOn: nil))
            photo.pickerItem = key
            return photo
        }
        // b は手前で弾かれる形にして、a だけが上がる回を作る
        model.items = [pending(a, type: "image/jpeg"), pending(b, type: "image/svg+xml")]
        model.pickerItems = [a, b, c]
        // c の読み込み（読めずに終わる）を待つ。**時間で待たない**——本物の
        // PhotosUI では 100ms で返る保証が無い
        try await waitUntil { !model.isLoadingPicked && model.errorMessage != nil }

        await model.submit()
        let summary = model.errorMessage
        XCTAssertNotNil(summary)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.pickerItems, [b, c], "投稿済みの写真が選ばれたまま")
        XCTAssertEqual(model.errorMessage, summary, "送れなかった知らせが消えている")

        // 残った1枚を外しても、読めなかった c を読み直して知らせを上書きしない
        model.remove(model.items[0].id)
        // 読み直しが起きないことを見るので、短く待てば足りる
        try await waitUntil(seconds: 0.5) { model.isLoadingPicked || model.errorMessage != summary }
        XCTAssertEqual(model.pickerItems, [c])
        XCTAssertEqual(model.errorMessage, summary, "写真を外したら送れなかった知らせが消えた")
    }

    /// 上限と形は**手前で弾く**（50MB 上げてから 400 を食わない）。
    func testRejectsTooLargeFileWithoutCallingServer() async {
        do {
            _ = try await service().stage(
                data: Data(count: UploadService.maxFileSize + 1),
                fileName: "big.jpg", fileType: "image/jpeg"
            )
            XCTFail("投げるはず")
        } catch {
            // **文言で確かめない。** 表示は端末の言語で変わる。見るのは形
            guard case .server(let status, _)? = error as? APIError else {
                return XCTFail("形が違う: \(error)")
            }
            XCTAssertEqual(status, 400)
        }
        XCTAssertTrue(ScriptedProtocol.calls.isEmpty, "手前で弾かずに投げている")
    }

    /// **SVG は通さない。** スクリプトを書ける文書で、同じオリジンから返る。
    func testRejectsSVG() async {
        do {
            _ = try await service().stage(
                data: Data("<svg/>".utf8),
                fileName: "a.svg", fileType: "image/svg+xml"
            )
            XCTFail("投げるはず")
        } catch {
            guard case .server(let status, _)? = error as? APIError else {
                return XCTFail("形が違う: \(error)")
            }
            XCTAssertEqual(status, 400)
        }
        XCTAssertTrue(ScriptedProtocol.calls.isEmpty)
    }
}

/// 順番に応答を返す `URLProtocol`。パスの一部で引き当てる。
final class ScriptedProtocol: URLProtocol {

    struct Step {
        let match: String
        let status: Int
        let body: String
    }

    struct Call {
        let path: String
        let method: String
        let contentType: String?
    }

    nonisolated(unsafe) static var script: [Step] = []
    nonisolated(unsafe) static var calls: [Call] = []

    static func reset() {
        script = []
        calls = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        ScriptedProtocol.calls.append(.init(
            path: path,
            method: request.httpMethod ?? "",
            contentType: request.value(forHTTPHeaderField: "Content-Type")
        ))
        let step = ScriptedProtocol.script.first { path.contains($0.match) }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: step?.status ?? 404,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((step?.body ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
