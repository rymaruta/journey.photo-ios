import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// S3 への PUT に `Cache-Control` を付ける（2026-11-25 判断・`UploadCacheControl`）。
///
/// iOS から上げた写真だけ、ブラウザと CDN が覚えておく時間の指定が無かった。Web と同じ値を、
/// **写真を上げるすべての道**（投稿の本体・サムネ・差し替え・ストーリーの画像と動画。前面でも背景の転送でも）に付ける
final class UploadCacheControlTests: XCTestCase {

    /// 運ばれた要求を控えるだけの転送（背景の転送 `BackgroundTransfer` と前面の `SessionTransfer` が受け取るのと同じ要求）
    private final class RecordingTransfer: PhotoTransfer, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URLRequest] = []
        var requests: [URLRequest] { lock.withLock { stored } }

        func upload(_ request: URLRequest, body: Data, key: String) async throws -> URLResponse {
            lock.withLock { stored.append(request) }
            return HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        }
    }

    private let presigned = UploadService.PresignResponse(
        presignedUrl: "https://s3.example.test/put?X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost",
        key: "uploads/u1/abc.jpg",
        publicUrl: "https://cdn.example.test/uploads/u1/abc.jpg",
        photoId: "p1",
        contentType: "image/jpeg"
    )

    /// Web（`lib/utils/uploadToS3.ts`）と同じ値。変えるなら Web と一緒に
    func testValuesMatchTheWeb() {
        XCTAssertEqual(UploadCacheControl.photo, "max-age=31536000")
        XCTAssertEqual(UploadCacheControl.profileImage, "no-store")
    }

    /// 転送（前面・背景のどちらも）に渡す要求に、署名した種別と `Cache-Control` が載る
    func testPutHandsTheTransferARequestWithCacheControl() async throws {
        let transfer = RecordingTransfer()
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"))
        try await UploadService(api: api, transfer: transfer).put(data: Data([0xFF, 0xD8]), to: presigned)

        let request = try XCTUnwrap(transfer.requests.first)
        XCTAssertEqual(transfer.requests.count, 1)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "max-age=31536000",
                       "iOS から上げた写真に覚えておく時間の指定が無い")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg",
                       "署名した種別と違う（S3 が 403 にする）")
    }

    /// 投稿の本体とサムネ（`stagePhoto`）を実際の URLSession で通し、**S3 に届いた PUT** を見る。
    /// 差し替え（`PhotoService.replace`）とストーリー（`StoryService.upload`）も同じ `put` を通る
    func testPostedPhotoAndThumbnailPutsCarryCacheControl() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeaderRecordingProtocol.self]
        let session = URLSession(configuration: config)
        HeaderRecordingProtocol.reset()
        defer { HeaderRecordingProtocol.reset() }
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let service = UploadService(api: api, session: session)

        let staged = try await service.stagePhoto(ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil, thumbnail: Data(repeating: 0xEE, count: 8)))
        XCTAssertNotNil(staged.thumb, "サムネが置けていない（試験の前提）")

        let puts = HeaderRecordingProtocol.puts
        XCTAssertEqual(puts.count, 2, "本体とサムネの2回")
        for put in puts {
            XCTAssertEqual(put.cacheControl, "max-age=31536000")
            XCTAssertEqual(put.contentType, "image/jpeg")
        }
    }

    /// アイコンとカバーは鍵が固定なので `no-store`（Web の `app/user/profile/page.tsx` と同じ）
    func testProfileImagePutSaysNoStore() throws {
        let request = ProfileService.imagePutRequest(url: URL(string: "https://s3.example.test/profiles/u1")!,
                                                     contentType: "image/jpeg")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
    }

    /// **写真の PUT を作る所は2つだけ**（投稿の `UploadService.putRequest`・アイコンの `ProfileService.imagePutRequest`）。
    /// 新しい道が自分で PUT を組むと、`Cache-Control` を付け忘れる。意見の写真（`FeedbackService`）は
    /// 運営だけが見る非公開の置き場で、Web も付けていないので外す
    func testOnlyTheTwoBuildersMakeS3Puts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
        let allowed: Set<String> = [
            "Services/UploadService.swift", "Services/ProfileService.swift", "Services/FeedbackService.swift",
        ]
        var found: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("httpMethod = \"PUT\"") else { continue }
            found.append(String(url.path.dropFirst(root.path.count + 1)))
        }
        XCTAssertEqual(Set(found).subtracting(allowed), [], "PUT を自分で組む所が増えた（`UploadService.putRequest` を通す）")

        let upload = try String(contentsOf: root.appendingPathComponent("Services/UploadService.swift"), encoding: .utf8)
        XCTAssertEqual(upload.components(separatedBy: "httpMethod = \"PUT\"").count - 1, 1,
                       "UploadService の PUT は putRequest の1か所だけ")
        let profile = try String(contentsOf: root.appendingPathComponent("Services/ProfileService.swift"), encoding: .utf8)
        XCTAssertEqual(profile.components(separatedBy: "httpMethod = \"PUT\"").count - 1, 1,
                       "ProfileService の PUT は imagePutRequest の1か所だけ")
    }
}

/// presign には決まった答えを返し、PUT の見出しを控える `URLProtocol`
final class HeaderRecordingProtocol: URLProtocol {
    struct Put {
        let contentType: String?
        let cacheControl: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: [Put] = []
    nonisolated(unsafe) private static var counter = 0

    static var puts: [Put] { lock.withLock { stored } }
    static func reset() { lock.withLock { stored = []; counter = 0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body: String
        if request.httpMethod == "PUT" {
            Self.lock.withLock {
                Self.stored.append(Put(contentType: request.value(forHTTPHeaderField: "Content-Type"),
                                       cacheControl: request.value(forHTTPHeaderField: "Cache-Control")))
            }
            body = ""
        } else {
            let n = Self.lock.withLock { () -> Int in Self.counter += 1; return Self.counter }
            body = """
            {"presignedUrl":"https://s3.example.test/put\(n)","key":"uploads/u1/k\(n).jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/k\(n).jpg","photoId":"p\(n)","contentType":"image/jpeg"}
            """
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
