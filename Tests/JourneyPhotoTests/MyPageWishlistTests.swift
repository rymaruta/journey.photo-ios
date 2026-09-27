import XCTest
@testable import JourneyPhoto

/// マイページの「行きたい」は、**他人の写真のスポット画面から入れた場所も出す**。
final class MyPageWishlistTests: XCTestCase {

    private func photo(_ id: String, location: String, owner: String = "me", likes: Int = 0) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"likes\":\(likes),\"createdAt\":\"2026-01-01T00:00:00Z\",\"location\":\"\(location)\",\"userId\":\"\(owner)\"}".utf8))
    }

    /// 他人の写真（公開一覧にだけ在る）の撮影地も地点になる
    func testPlacesFromOthersPhotosAppear() throws {
        let own = [try photo("mine", location: "パリ")]
        let feed = [try photo("theirs", location: "高屋神社")]
        let slugs = DerivedSpot.all(in: MyPageView.wishlistPool(own: own, feed: feed, hidden: ModerationSnapshot())).map(\.slug)
        XCTAssertTrue(slugs.contains(DerivedSpot.all(in: feed)[0].slug))
        XCTAssertTrue(slugs.contains(DerivedSpot.all(in: own)[0].slug))
    }

    /// 両方に載る自分の公開写真は1枚に数える（枚数が倍にならない）
    func testSamePhotoCountedOnce() throws {
        let mine = try photo("mine", location: "パリ")
        let pool = MyPageView.wishlistPool(own: [mine], feed: [mine], hidden: ModerationSnapshot())
        XCTAssertEqual(pool.map(\.id), ["mine"])
        XCTAssertEqual(DerivedSpot.all(in: pool).first?.count, 1)
    }

    /// ブロックした人・非表示にした写真は、公開一覧から入っても地点の代表（表紙）にならない
    func testBlockedAndReportedPhotosDoNotBecomeTheCover() throws {
        let own = [try photo("mine", location: "パリ", owner: "me", likes: 1)]
        let feed = [try photo("blocked", location: "パリ", owner: "bad", likes: 99),
                    try photo("reported", location: "パリ", owner: "x", likes: 50)]
        let hidden = ModerationSnapshot(blocked: ["bad"], reported: ["reported"])
        let pool = MyPageView.wishlistPool(own: own, feed: feed, hidden: hidden)
        XCTAssertEqual(pool.map(\.id), ["mine"])
        XCTAssertEqual(DerivedSpot.all(in: pool).first?.cover?.id, "mine")
    }

    /// 自分の写真は落とさない（自分の ID がブロック側に紛れていても）
    func testOwnPhotosAreNotFiltered() throws {
        let own = [try photo("mine", location: "パリ", owner: "me")]
        let pool = MyPageView.wishlistPool(own: own, feed: [],
                                           hidden: ModerationSnapshot(blocked: ["me"], reported: ["mine"]))
        XCTAssertEqual(pool.map(\.id), ["mine"])
    }
}
