import XCTest
@testable import JourneyPhoto

/// 地図を開いたまま「マップ」をもう一度押したときの動き（`MapTabReselect`）
final class MapTabReselectTests: XCTestCase {

    private func action(onScreen: Bool = true, isMapMode: Bool = true,
                        followsLocation: Bool = false, followsHeading: Bool = false) -> MapTabReselect.Action {
        MapTabReselect.action(onScreen: onScreen, isMapMode: isMapMode,
                              followsLocation: followsLocation, followsHeading: followsHeading)
    }

    /// 目的地までスクロールした（追っていない）→ 現在地を取り直して寄せる
    func testLocatesWhenScrolledAway() {
        XCTAssertEqual(action(), .locate)
    }

    /// 🔴 **詳細を開いている間は動かさない。** iOS が地図まで戻すのが1回目、
    /// 現在地へ寄せるのは戻ったあとの2回目
    func testIgnoresWhileDetailIsPushed() {
        XCTAssertEqual(action(onScreen: false), .ignore)
    }

    /// スポット・リストの間は地図が見えていないので動かさない
    func testIgnoresOutsideMapMode() {
        XCTAssertEqual(action(isMapMode: false), .ignore)
    }

    /// 🔴 **ボタンと違い、段を進めない。** 追っている最中にもう一度押しても
    /// 向きに合わせる段へ進まない
    func testDoesNotAdvanceToHeadingWhileFollowing() {
        XCTAssertEqual(action(followsLocation: true), .ignore)
    }

    /// 向きに合わせている最中は、回すのをやめて現在地を追うだけに戻す
    func testStopsHeadingRotation() {
        XCTAssertEqual(action(followsLocation: true, followsHeading: true), .stopHeading)
    }
}
