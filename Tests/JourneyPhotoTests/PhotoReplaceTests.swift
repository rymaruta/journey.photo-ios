import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 写真そのものの差し替え（`PUT /photos/{id}`）。
///
/// **送る形を縛る。** サーバーは `body.replace` しか見ない
/// （`api-user/src/photoUpdate.ts` の `hasReplace`）。包み忘れると、
/// 包まれていない項目だけが「中身の更新」として通り——**200 が返って
/// 「差し替えました」と出るのに、画像は古いまま撮影日と座標だけ書き換わる**。
/// 口（ルート）を見る検査では素通りするので、ここで body を見る。
@MainActor
final class PhotoReplaceTests: XCTestCase {

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

    private func api() -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!,
                  tokenProvider: StubTokenProvider(token: "t"),
                  session: session)
    }

    private func prepared() -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: Data([0xff, 0xd8]), fileName: "photo.jpg",
                               contentType: "image/jpeg", exif: nil,
                               coords: Photo.Coords(lat: 34.2812, lng: 133.8034),
                               takenOn: "2026-09-20")
    }

    func testReplaceBodyIsWrappedInReplace() async throws {
        prepare()
        StubProtocol.respond(status: 200, body: #"{"presignedUrl":"https://s3.example.test/put","key":"uploads/u/1.jpg","publicUrl":"https://site.example.test/uploads/u/1.jpg","contentType":"image/jpeg"}"#)

        try await PhotoService(api: api()).replace(
            photoId: "p1", prepared: prepared(),
            uploads: UploadService(api: api(), session: session))

        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let replace = try XCTUnwrap(json["replace"] as? [String: Any],
                                    "replace で包んでいない（サーバーは body.replace しか見ない）")
        XCTAssertEqual(replace["key"] as? String, "uploads/u/1.jpg")
        XCTAssertEqual(replace["publicUrl"] as? String, "https://site.example.test/uploads/u/1.jpg")
        XCTAssertNil(json["key"], "包みの外に出さない（中身の更新として通ってしまう）")
    }

    /// **座標は端末でも丸めてから送る**（投稿と同じ。約1km＝小数第2位）。
    func testCoordinatesAreRoundedBeforeSending() async throws {
        prepare()
        StubProtocol.respond(status: 200, body: #"{"presignedUrl":"https://s3.example.test/put","key":"uploads/u/1.jpg","publicUrl":"https://site.example.test/uploads/u/1.jpg","contentType":"image/jpeg"}"#)

        try await PhotoService(api: api()).replace(
            photoId: "p1", prepared: prepared(),
            uploads: UploadService(api: api(), session: session))

        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let coords = try XCTUnwrap((json["replace"] as? [String: Any])?["coords"] as? [String: Any])
        XCTAssertEqual(coords["lat"] as? Double, 34.28)
        XCTAssertEqual(coords["lng"] as? Double, 133.8)
    }

    /// **大きすぎる写真は、上げる前に断る**（投稿と同じ関所を通す）。
    func testTooLargeIsRefusedBeforeUploading() async throws {
        prepare()
        let huge = ImagePreparer.Prepared(
            data: Data(count: UploadService.maxFileSize + 1), fileName: "photo.jpg",
            contentType: "image/jpeg", exif: nil, coords: nil, takenOn: nil)

        do {
            try await PhotoService(api: api()).replace(
                photoId: "p1", prepared: huge,
                uploads: UploadService(api: api(), session: session))
            XCTFail("断られるはず")
        } catch {
            XCTAssertNil(StubProtocol.lastRequest, "サーバーを叩く前に断る")
        }
    }
}
