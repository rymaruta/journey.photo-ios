import XCTest
@testable import JourneyPhoto

/// マイページの「行きたい」は、**他人の写真のスポット画面から入れた場所も出す**。
final class MyPageWishlistTests: XCTestCase {

    private func photo(_ id: String, location: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"likes\":0,\"createdAt\":\"2026-01-01T00:00:00Z\",\"location\":\"\(location)\"}".utf8))
    }

    /// 他人の写真（公開一覧にだけ在る）の撮影地も地点になる
    func testPlacesFromOthersPhotosAppear() throws {
        let own = [try photo("mine", location: "パリ")]
        let feed = [try photo("theirs", location: "高屋神社")]
        let slugs = DerivedSpot.all(in: MyPageView.wishlistPool(own: own, feed: feed)).map(\.slug)
        XCTAssertTrue(slugs.contains(DerivedSpot.all(in: feed)[0].slug))
        XCTAssertTrue(slugs.contains(DerivedSpot.all(in: own)[0].slug))
    }

    /// 両方に載る自分の公開写真は1枚に数える（枚数が倍にならない）
    func testSamePhotoCountedOnce() throws {
        let mine = try photo("mine", location: "パリ")
        let pool = MyPageView.wishlistPool(own: [mine], feed: [mine])
        XCTAssertEqual(pool.map(\.id), ["mine"])
        XCTAssertEqual(DerivedSpot.all(in: pool).first?.count, 1)
    }
}
