import XCTest
@testable import JourneyPhoto

/// journey-photo.com のリンクでアプリが開いたときの行き先（Universal Links・2026-11-20 札 #661 / #664）。
/// 受ける道はサイトの apple-app-site-association の applinks と同じ（Web は `appSiteAssociation.test.ts`）
@MainActor
final class AppLinkTests: XCTestCase {

    private let base = URL(string: "https://journey-photo.com")!

    private func link(_ text: String) -> AppLink? { AppLink.parse(URL(string: text)!, base: base) }

    /// 🔴 **人の QR の URL（`ProfileQR` が作る形）を iPhone のカメラで読んだら、アプリの人の頁へ**（札 #664）。
    /// アプリの中の QR の読み取りと同じ所（`ProfileQRLink.parse`）を通る
    func testProfileQRURLsOpenThePerson() async throws {
        let personURL = try XCTUnwrap(ProfileQR.url(userId: "u-1", base: base))
        XCTAssertEqual(AppLink.parse(personURL, base: base), .person("u-1"))
        let passURL = try XCTUnwrap(ProfileQR.passURL(token: "tok_1", base: base))
        XCTAssertEqual(AppLink.parse(passURL, base: base), .pass("tok_1"))
        XCTAssertEqual(link("https://www.journey-photo.com/users/u-2"), .person("u-2"))
        XCTAssertEqual(link("https://journey-photo.com/users/u-2/"), .person("u-2"))
    }

    func testPhotoAndSpotPages() async {
        XCTAssertEqual(link("https://journey-photo.com/photo/abc123"), .photo("abc123"))
        XCTAssertEqual(link("https://www.journey-photo.com/photo/abc123/"), .photo("abc123"))
        XCTAssertEqual(link("https://journey-photo.com/spots/abukumado"), .spot("abukumado"))
        // 観光スポットの頁の「アプリで保存」（`?app=save`）もその頁へ
        XCTAssertEqual(link("https://journey-photo.com/spots/abukumado?app=save"), .spot("abukumado"))
    }

    /// AASA で外している道・アプリに受ける口が無い道・外のサイトは受けない（アプリが開いて何も出ない、を作らない）
    func testIgnoresPagesTheAppDoesNotHave() async {
        for text in [
            "https://journey-photo.com/", "https://journey-photo.com/spots", "https://journey-photo.com/spots/sakura",
            "https://journey-photo.com/spots/momiji", "https://journey-photo.com/spots/snow",
            "https://journey-photo.com/spots/area/kanto", "https://journey-photo.com/spots/sakura/tokyo",
            "https://journey-photo.com/photo", "https://journey-photo.com/photo/a/b",
            "https://journey-photo.com/users/search", "https://journey-photo.com/users/trip", "https://journey-photo.com/users",
            "https://journey-photo.com/trips", "https://journey-photo.com/t?t=tok", "https://journey-photo.com/j?t=tok",
            "https://journey-photo.com/login", "https://journey-photo.com/photo/..%2Fx",
            "https://example.com/photo/abc123", "https://example.com/users?id=u-1",
            "journeyphoto://photo/abc123",
        ] {
            XCTAssertNil(link(text), text)
        }
    }

    /// 受けたリンクは、見頃のお知らせと同じ道でホームに積む（`TabRouter.openOnHome`）
    func testRouterStacksTheScreenOnHome() async throws {
        let router = TabRouter()
        XCTAssertTrue(router.openLink(try XCTUnwrap(ProfileQR.url(userId: "u-1", base: base)), base: base))
        XCTAssertEqual(router.homeRequests, 1)
        XCTAssertEqual(router.homeScreenRequests, 1)
        XCTAssertEqual(router.takePendingHomeScreen(), .person(userId: "u-1"))

        XCTAssertTrue(router.openLink(URL(string: "https://journey-photo.com/qr?t=tok")!, base: base))
        XCTAssertEqual(router.takePendingHomeScreen(), .profilePass("tok"))
        XCTAssertTrue(router.openLink(URL(string: "https://journey-photo.com/photo/p1")!, base: base))
        XCTAssertEqual(router.takePendingHomeScreen(), .photo(id: "p1"))
        XCTAssertTrue(router.openLink(URL(string: "https://journey-photo.com/spots/abukumado")!, base: base))
        XCTAssertEqual(router.takePendingHomeScreen(), .officialSpot(slug: "abukumado"))

        // 受けない URL は何もしない（ホームへも移らない）
        XCTAssertFalse(router.openLink(URL(string: "https://journey-photo.com/trips")!, base: base))
        XCTAssertEqual(router.homeScreenRequests, 4)
        XCTAssertNil(router.takePendingHomeScreen())
    }

    private func photo(_ id: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data("{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"}".utf8))
    }

    private struct Offline: Error {}

    /// 写真の頁: 公開一覧の控え → 自分の写真 → 取り直し の順に探す。圏外では「見つからない」と言わない
    func testFindsTheLinkedPhoto() async throws {
        let shown = try photo("p1"), mine = try photo("m1")
        var forced: [Bool] = []

        let inFeed = await AppLinkPhoto.find("p1", mine: [mine]) { force in forced.append(force); return [shown] }
        XCTAssertEqual(inFeed, .found(shown, fromPublicFeed: true))
        XCTAssertEqual(forced, [false])

        forced = []
        let own = await AppLinkPhoto.find("m1", mine: [mine]) { force in forced.append(force); return [shown] }
        XCTAssertEqual(own, .found(mine, fromPublicFeed: false))
        XCTAssertEqual(forced, [false], "自分の写真なら取り直さない")

        // 控えに無い新しい写真は、取り直した一覧で見つかる
        let fresh = try photo("p2")
        let refetched = await AppLinkPhoto.find("p2", mine: []) { force in force ? [shown, fresh] : [shown] }
        XCTAssertEqual(refetched, .found(fresh, fromPublicFeed: true))

        let missing = await AppLinkPhoto.find("gone", mine: [mine]) { _ in [shown] }
        XCTAssertEqual(missing, .missing)

        let offline = await AppLinkPhoto.find("p1", mine: []) { _ in throw Offline() }
        XCTAssertEqual(offline, .failed)
    }
}
