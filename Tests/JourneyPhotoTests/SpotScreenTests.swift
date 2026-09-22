import XCTest
@testable import JourneyPhoto

/// 撮影スポット詳細（モック5）の決まりごと。
///
/// 🔴 **この画面は実機の絵で確かめられない**（台帳が0件で、出す地点が
/// 1つも無い）。せめて中身の決まりはここで動かして確かめる。
final class SpotScreenTests: XCTestCase {

    // MARK: - 代表画像のページャ（モック5-2）

    /// 「1/10」は**数えた数**
    func testPagerCountsWhatIsThere() {
        XCTAssertEqual(SpotScreen.pagerLabel(page: 0, count: 10), "1/10")
        XCTAssertEqual(SpotScreen.pagerLabel(page: 2, count: 10), "3/10")
    }

    /// **並びの外を指さない。** 絞り込みで写真が減った回に「5/3」と出さない
    func testPagerNeverPointsOutsideTheList() {
        XCTAssertEqual(SpotScreen.pagerLabel(page: 4, count: 3), "3/3")
        XCTAssertEqual(SpotScreen.pagerLabel(page: -2, count: 3), "1/3")
    }

    /// 1枚も無ければ札を出さない（「0/0」と書かない）
    func testPagerIsHiddenWhenThereIsNothing() {
        XCTAssertNil(SpotScreen.pagerLabel(page: 0, count: 0))
    }

    // MARK: - シェア（モック5-6）

    /// 🔴 **開けないリンクを配らない。** スポットのページ（`/spots/<スラッグ>`）は
    /// まだ無いので、journey-photo.com は入れない
    func testShareTextHasNoSiteLink() {
        let url = SpotScreen.mapURL(name: "イアの夕景", coords: Photo.Coords(lat: 36.46, lng: 25.37))
        let text = SpotScreen.shareText(name: "イアの夕景", region: "ギリシャ サントリーニ島", mapURL: url)
        XCTAssertFalse(text.contains("journey-photo.com"), "開けないリンクを配っている")
        XCTAssertTrue(text.contains("イアの夕景"))
        XCTAssertTrue(text.contains("ギリシャ サントリーニ島"))
        XCTAssertTrue(text.contains("maps.apple.com"))
    }

    /// **無い行に空行を作らない**（地域も地図も無い地点）
    func testShareTextSkipsWhatIsMissing() {
        XCTAssertEqual(SpotScreen.shareText(name: "名前だけ", region: nil, mapURL: nil), "名前だけ")
        XCTAssertEqual(SpotScreen.shareText(name: "名前だけ", region: "  ", mapURL: nil), "名前だけ")
        XCTAssertFalse(SpotScreen.shareText(name: "名前だけ", region: nil, mapURL: nil).contains("\n"))
    }

    // MARK: - 地図で見る（モック5-6）

    /// **座標があるときだけ。** 無い地点に「地図で見る」を出さない
    func testMapLinkNeedsCoordinates() {
        XCTAssertNil(SpotScreen.mapURL(name: "座標なし", coords: nil))
        XCTAssertNotNil(SpotScreen.mapURL(name: "あり", coords: Photo.Coords(lat: 35.0, lng: 135.0)))
    }

    /// 名前は**そのまま渡さない**（空白や記号が入るので URL の形にする）
    func testMapLinkEscapesTheName() throws {
        let url = try XCTUnwrap(SpotScreen.mapURL(name: "高屋神社 天空の鳥居",
                                                  coords: Photo.Coords(lat: 34.1, lng: 133.6)))
        XCTAssertFalse(url.absoluteString.contains(" "), "URL に生の空白が入っている")
        XCTAssertTrue(url.absoluteString.contains("ll=34.1,133.6"))
    }
}
