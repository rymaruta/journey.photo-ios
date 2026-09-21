import XCTest
@testable import JourneyPhoto

final class ProfileAssetURLTests: XCTestCase {

    /// **Info.plist を持たない環境でも動くようにする。**
    /// `AppConfig` は値が欠けていたら落とす作りなので（本番値の
    /// フォールバックを置かない方針）、テストでは明示的に入れる。
    override func setUp() {
        super.setUp()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "ap-northeast-1_TEST",
            "JPCognitoClientId": "testclient",
            "JPCognitoRegion": "ap-northeast-1",
        ]
    }

    override func tearDown() {
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    /// アイコンとカバーは**サイトのドメイン**で組み立てる。
    /// CloudFront の既定ドメインを直接指すと別オリジンになり、
    /// Web 側が 2026-09-13 に揃えた状態から逆戻りする。
    func testAvatarUsesSiteDomain() throws {
        let url = try XCTUnwrap(UserProfile.profileAssetURL(userId: "abc", suffix: nil, cacheBust: nil))
        XCTAssertEqual(url.host, AppConfig.siteBaseURL.host)
        XCTAssertEqual(url.path, "/profiles/abc")
    }

    func testCoverHasSuffix() throws {
        let url = try XCTUnwrap(UserProfile.profileAssetURL(userId: "abc", suffix: "cover", cacheBust: nil))
        XCTAssertEqual(url.path, "/profiles/abc/cover")
    }

    /// 固定キーで中身が差し替わるので、読み直すときは別の URL にする。
    func testCacheBustIsAppended() throws {
        let url = try XCTUnwrap(UserProfile.profileAssetURL(userId: "abc", suffix: nil, cacheBust: "12"))
        XCTAssertEqual(url.query, "v=12")
    }
}
