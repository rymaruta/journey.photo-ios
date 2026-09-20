import XCTest
@testable import JourneyPhoto

final class ProfileAssetURLTests: XCTestCase {

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
