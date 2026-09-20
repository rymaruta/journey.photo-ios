import XCTest
@testable import JourneyPhoto
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
        let photo = try await service().upload(
            data: Data(repeating: 0xFF, count: 16),
            fileName: "photo.jpg", fileType: "image/jpeg", draft: PhotoDraft()
        )
        XCTAssertEqual(photo?.id, "p1")
        XCTAssertEqual(ScriptedProtocol.calls.map(\.path),
                       ["/upload/presigned-url", "/put", "/upload/save"])
        let put = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path == "/put" })
        XCTAssertEqual(put.contentType, "image/jpeg")
        XCTAssertEqual(put.method, "PUT")
    }

    /// **保存で落ちたら、S3 の迷子を片付ける。**
    func testDiscardsUploadWhenSaveFails() async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"保存に失敗しました"}"#),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        do {
            _ = try await service().upload(
                data: Data(repeating: 0xFF, count: 16),
                fileName: "photo.jpg", fileType: "image/jpeg", draft: PhotoDraft()
            )
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual((error as? APIError)?.errorDescription, "保存に失敗しました")
        }
        XCTAssertTrue(ScriptedProtocol.calls.contains { $0.path == "/upload/discard" },
                      "S3 に迷子が残ったまま")
    }

    /// 上限と形は**手前で弾く**（50MB 上げてから 400 を食わない）。
    func testRejectsTooLargeFileWithoutCallingServer() async {
        do {
            _ = try await service().upload(
                data: Data(count: UploadService.maxFileSize + 1),
                fileName: "big.jpg", fileType: "image/jpeg", draft: PhotoDraft()
            )
            XCTFail("投げるはず")
        } catch {
            XCTAssertTrue((error as? APIError)?.errorDescription?.contains("大きすぎ") == true)
        }
        XCTAssertTrue(ScriptedProtocol.calls.isEmpty, "手前で弾かずに投げている")
    }

    /// **SVG は通さない。** スクリプトを書ける文書で、同じオリジンから返る。
    func testRejectsSVG() async {
        do {
            _ = try await service().upload(
                data: Data("<svg/>".utf8),
                fileName: "a.svg", fileType: "image/svg+xml", draft: PhotoDraft()
            )
            XCTFail("投げるはず")
        } catch {
            XCTAssertTrue((error as? APIError)?.errorDescription?.contains("対応していない") == true)
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
