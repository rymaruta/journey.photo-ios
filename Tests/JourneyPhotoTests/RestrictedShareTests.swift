import XCTest
@testable import JourneyPhoto

/// 公開範囲を絞った写真は、共有で個別ページを配らない（バグ探し 2026-09-27）。
/// 一覧には `/feed/restricted` の写真も混ざる（`published: true`）が、`photos.json` に
/// 載らず個別ページが建たない——配ると受け取った人が開けない 404 になっていた
final class RestrictedShareTests: XCTestCase {

    override func setUp() {
        super.setUp()
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
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    private func photo(_ id: String, audience: String?) throws -> Photo {
        let aud = audience.map { #","audience":"\#($0)""# } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"\#(id)","src":"/uploads/\#(id).jpg","published":true\#(aud)}"#.utf8))
    }

    func testRestrictedLeadPhotoIsNotShared() throws {
        let restricted = try photo("p1", audience: "followers")
        let text = CollectionScreen.shareText(title: "パリ", count: 1, kind: nil, lead: restricted)
        // `/photo/` も `?photo=`（ホームへの振り替え）も、Web では開けない
        XCTAssertFalse(text.contains("http"), "開けないリンクを配っている: \(text)")

        let everyone = try photo("p2", audience: nil)
        let shared = CollectionScreen.shareText(title: "パリ", count: 1, kind: nil, lead: everyone)
        XCTAssertTrue(shared.contains("p2"), "全体に公開の写真まで配らなくなった: \(shared)")
    }
}
