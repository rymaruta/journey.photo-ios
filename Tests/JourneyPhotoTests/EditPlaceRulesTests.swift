import XCTest
@testable import JourneyPhoto

/// 写真の編集で座標を消す／差し替えで書く決まり（位置の漏れと、触っていないピンの消失）
final class EditPlaceRulesTests: XCTestCase {

    /// 撮影地を消して保存したら座標も消す
    func testClearingThePlaceClearsCoords() {
        XCTAssertTrue(EditPlaceRules.clearsCoords(openedLocation: "パリ", currentLocation: " ", pickedCoords: false))
    }

    /// 🔴 開いたときから撮影地が空（圏外で投稿した等）の写真は、題を直しただけで座標を消さない
    func testUntouchedEmptyPlaceKeepsCoords() {
        XCTAssertFalse(EditPlaceRules.clearsCoords(openedLocation: nil, currentLocation: "", pickedCoords: false))
        XCTAssertFalse(EditPlaceRules.clearsCoords(openedLocation: "", currentLocation: "", pickedCoords: false))
    }

    /// 候補を選んだなら消さない（選んだ座標を送る）
    func testPickedCoordsAreNotCleared() {
        XCTAssertFalse(EditPlaceRules.clearsCoords(openedLocation: "パリ", currentLocation: "", pickedCoords: true))
    }

    /// ピンのある写真は、差し替えでピンを新しい写真の位置へ動かす
    func testReplaceMovesAnExistingPin() {
        XCTAssertTrue(EditPlaceRules.keepsCoordsOnReplace(openedLocation: "パリ", openedHasCoords: true, currentLocation: "パリ"))
        XCTAssertTrue(EditPlaceRules.keepsCoordsOnReplace(openedLocation: nil, openedHasCoords: true, currentLocation: ""))
    }

    /// 🔴 ピンを外した写真（撮影地あり・座標なし）に、差し替えで位置を戻さない
    func testReplaceDoesNotRestoreARemovedPin() {
        XCTAssertFalse(EditPlaceRules.keepsCoordsOnReplace(openedLocation: "パリ", openedHasCoords: false, currentLocation: "パリ"))
        XCTAssertFalse(EditPlaceRules.keepsCoordsOnReplace(openedLocation: nil, openedHasCoords: false, currentLocation: ""))
    }

    /// この画面で撮影地を消してから差し替えたら、位置を書かない
    func testReplaceAfterClearingDoesNotWriteCoords() {
        XCTAssertFalse(EditPlaceRules.keepsCoordsOnReplace(openedLocation: "パリ", openedHasCoords: true, currentLocation: ""))
    }
}
