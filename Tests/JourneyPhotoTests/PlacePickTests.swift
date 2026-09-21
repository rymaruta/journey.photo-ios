import XCTest
@testable import JourneyPhoto

/// 撮影地の座標を持ち続けてよいか。
///
/// **間違った場所に確定で刺さるのがいちばん困る。** サーバーは明示的に
/// 送られた座標を「正確」と見て `geoApprox` を外すので、直しようがない。
final class PlacePickTests: XCTestCase {

    func testKeepsCoordsWhileTheTextMatchesWhatWasPicked() {
        XCTAssertTrue(PlacePick.keepsCoords(typed: "パリ", pickedLabel: "パリ"))
    }

    /// **1文字でも直されたら手放す。**
    func testDropsCoordsOnceTheTextIsEdited() {
        XCTAssertFalse(PlacePick.keepsCoords(typed: "ロンドン", pickedLabel: "パリ"))
        XCTAssertFalse(PlacePick.keepsCoords(typed: "パリ ", pickedLabel: "パリ"))
        XCTAssertFalse(PlacePick.keepsCoords(typed: "パ", pickedLabel: "パリ"))
    }

    /// 選んでいないなら、そもそも持っていない。
    func testNothingPickedMeansNoCoords() {
        XCTAssertFalse(PlacePick.keepsCoords(typed: "パリ", pickedLabel: nil))
    }
}
