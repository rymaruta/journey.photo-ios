import XCTest
@testable import JourneyPhoto

/// 地図のリストが空のときの言い分け（`PhotoMapView.listEmpty`）。
/// **読めなかった回は失敗（警告と「もう一度試す」）、読めて0件は空の状態（三角なし）**
final class MapListEmptyTests: XCTestCase {

    func testFailureIsNotCalledEmpty() {
        XCTAssertEqual(PhotoMapView.listEmpty(loadFailed: true, photosEmpty: true, filtering: false), .failed,
                       "読めなかったのを「撮影地の分かる写真がありません」と言っている")
        XCTAssertEqual(PhotoMapView.listEmpty(loadFailed: true, photosEmpty: true, filtering: true), .failed,
                       "読めなかったのを「見つかりませんでした」と言っている")
    }

    func testEmptyIsNotAFailure() {
        XCTAssertEqual(PhotoMapView.listEmpty(loadFailed: false, photosEmpty: true, filtering: false), .noPlaces)
        XCTAssertEqual(PhotoMapView.listEmpty(loadFailed: false, photosEmpty: false, filtering: true), .noResults)
        // 前に読めた写真が残っている回は数が本物（帯の知らせと同じ）
        XCTAssertEqual(PhotoMapView.listEmpty(loadFailed: true, photosEmpty: false, filtering: false), .noPlaces)
    }

    /// 🔴 2026-10-09: カテゴリを選んだままスポットの名前を打つと、地図の帯は理由なしの
    /// 「見つかりませんでした」だった。帯で理由を言う。
    /// **帯は短い字**（全文 `categoryHidesSpotsNote` は約3行に折れて右の操作列に重なった・レビュー）。
    /// 全文はリストの上の1行にだけ出す
    func testBannerSaysCategoryHidesMatchingSpots() {
        XCTAssertEqual(PhotoMapView.emptyBanner(loadFailed: false, photosEmpty: false, filtering: true,
                                                categoryHidesSpots: true), .categoryHidesSpots)
        XCTAssertEqual(PhotoMapView.categoryHidesSpotsBannerText, "カテゴリで絞っている間はスポットを出しません")
        XCTAssertLessThan(PhotoMapView.categoryHidesSpotsBannerText.count, RegionList.categoryHidesSpotsNote.count / 2,
                          "地図の帯にリストの全文を出している（折り返して右の操作列に重なる）")
        // 当たるスポットが無ければ今までどおり
        XCTAssertEqual(PhotoMapView.emptyBanner(loadFailed: false, photosEmpty: false, filtering: true,
                                                categoryHidesSpots: false), .noResults)
        XCTAssertEqual(PhotoMapView.emptyBanner(loadFailed: false, photosEmpty: true, filtering: false,
                                                categoryHidesSpots: false), .noPlaces)
        // 読めなかった回は読めなかったと言う（理由より先）
        XCTAssertEqual(PhotoMapView.emptyBanner(loadFailed: true, photosEmpty: true, filtering: true,
                                                categoryHidesSpots: true), .failed)
    }
}
