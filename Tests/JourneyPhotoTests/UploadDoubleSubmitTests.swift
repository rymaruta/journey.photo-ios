import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 🔴 **投稿の二度押しで二重に出さない**（`submit()` の頭の `canSubmit`）。
/// ボタンの `.disabled` は次の描画まで効かず、素早い2回押しで `submit()` が2本走ると、
/// 同じ写真に鍵を2つ取り（presign が2回）、同じ写真が2枚上がる
final class UploadDoubleSubmitTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    @MainActor
    func testRapidDoubleSubmitPresignsOnce() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: config)
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
            """),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]

        // 同じ描画の間の2回押し（どちらも1本目が送り始める前に着く）
        async let first: Void = model.submit()
        async let second: Void = model.submit()
        _ = await (first, second)

        let presigns = ScriptedProtocol.calls.filter { $0.path == "/upload/presigned-url" }
        XCTAssertEqual(presigns.count, 1, "二度押しで鍵を2回取った（同じ写真が2枚上がる）")
        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.count, 1)
        XCTAssertTrue(model.didPostAll)
    }
}
