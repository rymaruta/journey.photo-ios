import XCTest
@testable import JourneyPhoto

/// この場所の、最初の1枚をお願いする（札 #710 の案7）
final class FirstPhotoTests: XCTestCase {

    private func photo(_ id: String, spotId: String?) throws -> Photo {
        var obj: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg"]
        if let spotId { obj["spotId"] = spotId }
        return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    /// 言葉は案の頁のとおり。急かす言葉・競わせる言葉は使わない
    func testWords() {
        XCTAssertEqual(FirstPhoto.emptyTitle, L("まだ写真がありません", "No photos yet"))
        XCTAssertEqual(FirstPhoto.emptyMessage, L("あなたの1枚が、この観光スポットの最初の写真になります", "Your photo will be the first one here"))
        XCTAssertEqual(FirstPhoto.postLabel, L("最初の1枚を投稿する", "Post the first photo"))
        XCTAssertEqual(FirstPhoto.postedTitle("宝厳院"), L("宝厳院の最初の1枚になりました", "You posted the first photo of 宝厳院"))
        XCTAssertTrue(FirstPhoto.postedDetail.hasPrefix(L("ありがとうございます", "Thank you")))
        for text in [FirstPhoto.emptyTitle, FirstPhoto.emptyMessage, FirstPhoto.postLabel, FirstPhoto.postedDetail] {
            for word in ["急いで", "今だけ", "誰より先に", "一番乗り"] { XCTAssertFalse(text.contains(word)) }
        }
        XCTAssertEqual(OfficialSpotView.postLabel(hasLinked: false), FirstPhoto.postLabel)
    }

    /// 「最初の1枚」は、数を読めていて0のときだけ言う
    func testAnnouncesOnlyWhenZeroIsKnown() throws {
        XCTAssertTrue(FirstPhoto.announces(photosKnown: true, count: 0))
        XCTAssertFalse(FirstPhoto.announces(photosKnown: false, count: 0), "読めていないのに「最初の1枚」と言った")
        XCTAssertFalse(FirstPhoto.announces(photosKnown: true, count: 1))
        let photos = [try photo("a", spotId: "sp_1"), try photo("b", spotId: "sp_2")]
        XCTAssertEqual(FirstPhoto.count(spotId: "sp_1", in: photos, links: .empty), 1)
        XCTAssertEqual(FirstPhoto.count(spotId: "sp_3", in: photos, links: .empty), 0)
    }

    /// 投稿の知らせ: 0枚と読めていた観光スポットに上がったときだけ「最初の1枚になりました」。並ばなかった回（0枚）は言わない
    func testPostedNotice() throws {
        var target = UploadSpotTarget(spotId: "sp_1", name: "宝厳院", coords: nil)
        target.announcesFirst = true
        let posted = [try photo("p", spotId: "sp_1")]
        let made = PostedPlaceNotice.make(posted: posted, wishKeys: [], spots: [], announced: [], spot: target, postedToSpot: 1)
        XCTAssertEqual(made?.notice, PostedPlaceNotice(title: FirstPhoto.postedTitle("宝厳院"), detail: FirstPhoto.postedDetail))
        XCTAssertNil(PostedPlaceNotice.make(posted: posted, wishKeys: [], spots: [], announced: [], spot: target, postedToSpot: 0))
        target.announcesFirst = false
        XCTAssertNil(PostedPlaceNotice.make(posted: posted, wishKeys: [], spots: [], announced: [], spot: target, postedToSpot: 1),
                     "0枚と読めていなかったのに「最初の1枚」と言った")
    }
}
