import XCTest
@testable import JourneyPhoto

/// 「投稿する」のシートの札に敷く写真
final class PostSheetThumbsTests: XCTestCase {

    private func photo(_ id: String, at: String? = nil, published: Bool? = nil) throws -> Photo {
        let c = at.map { ",\"createdAt\":\"\($0)\"" } ?? ""
        let p = published.map { ",\"published\":\($0)" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"https://journey-photo.com/uploads/\(id).jpg\"\(c)\(p)}".utf8))
    }

    /// 自分の写真の新しい順に2枚
    func testNewestTwoOfMine() throws {
        let urls = PostSheetThumbs.pick(fromMine: [
            try photo("old", at: "2026-09-01T00:00:00Z"),
            try photo("new", at: "2026-09-20T00:00:00Z"),
            try photo("mid", at: "2026-09-10T00:00:00Z"),
        ])
        XCTAssertEqual(urls.map(\.lastPathComponent), ["new.jpg", "mid.jpg"])
    }

    /// 下書き（まだ見せていない写真）は敷かない
    func testSkipsDrafts() throws {
        let urls = PostSheetThumbs.pick(fromMine: [
            try photo("draft", at: "2026-09-20T00:00:00Z", published: false),
            try photo("shown", at: "2026-09-10T00:00:00Z"),
        ])
        XCTAssertEqual(urls.map(\.lastPathComponent), ["shown.jpg"])
    }

    /// **足りなければ足りないまま**（他人の写真で埋めない）
    func testNoPhotosMeansPlainCards() throws {
        XCTAssertEqual(PostSheetThumbs.pick(fromMine: []), [])
    }

    /// 日時の無い行は後ろ（落とさない）
    func testUndatedGoesLast() throws {
        let urls = PostSheetThumbs.pick(fromMine: [
            try photo("undated"),
            try photo("dated", at: "2026-09-10T00:00:00Z"),
        ])
        XCTAssertEqual(urls.map(\.lastPathComponent), ["dated.jpg", "undated.jpg"])
    }

    // MARK: - 控え

    private let a = URL(string: "https://journey-photo.com/uploads/a.jpg")!

    /// 同じ人なら5分は前の答えを使う
    func testCacheServesSameUserWithinMaxAge() {
        var cache = PostSheetThumbs.Cache()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        cache.store([a], for: "u1", now: t0)
        XCTAssertEqual(cache.urls(for: "u1", now: t0.addingTimeInterval(60)), [a])
        XCTAssertNil(cache.urls(for: "u1", now: t0.addingTimeInterval(PostSheetThumbs.Cache.maxAge)))
    }

    /// **人が替わったら使わない**（前の人の写真を次の人に見せない）
    func testCacheIsPerUser() {
        var cache = PostSheetThumbs.Cache()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        cache.store([a], for: "u1", now: t0)
        XCTAssertNil(cache.urls(for: "u2", now: t0))
    }

    /// まだ無い写真も「無い」と控える（0枚の人に毎回取りに行かない）
    func testCacheKeepsEmptyAnswer() {
        var cache = PostSheetThumbs.Cache()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        cache.store([], for: "u1", now: t0)
        XCTAssertEqual(cache.urls(for: "u1", now: t0), [])
    }
}
