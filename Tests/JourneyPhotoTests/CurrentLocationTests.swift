import XCTest
import CoreLocation
@testable import JourneyPhoto

/// 現在地は**1回だけ**取り、拒否・失敗を黙って飲み込まない。
@MainActor
final class CurrentLocationTests: XCTestCase {

    /// 本物の `CLLocationManager` の代わり。呼ばれた回数を数える
    private final class FakeRequester: LocationRequesting {
        var authorizationStatus: CLAuthorizationStatus
        var authorizationRequests = 0
        var locationRequests = 0
        init(status: CLAuthorizationStatus) { authorizationStatus = status }
        func requestWhenInUseAuthorization() { authorizationRequests += 1 }
        func requestLocation() { locationRequests += 1 }
    }

    /// 尋ねて断られたら「拒否」を返し、位置は要求しない
    func testDeniedEndsWithoutRequestingLocation() async {
        let fake = FakeRequester(status: .notDetermined)
        let location = CurrentLocation(manager: fake)
        location.locate()
        XCTAssertEqual(location.state, .asking)
        XCTAssertEqual(fake.authorizationRequests, 1)

        location.handle(status: .denied)
        XCTAssertEqual(location.state, .denied)
        XCTAssertEqual(fake.locationRequests, 0)
    }

    /// 既に断られているなら、尋ね直さずに「拒否」を返す
    func testAlreadyDeniedReportsWithoutAsking() async {
        let fake = FakeRequester(status: .denied)
        let location = CurrentLocation(manager: fake)
        location.locate()
        XCTAssertEqual(location.state, .denied)
        XCTAssertEqual(fake.authorizationRequests, 0)
        XCTAssertEqual(fake.locationRequests, 0)
    }

    /// 許可されたら位置を1回だけ要求し、取れたら止まる（追跡しない）
    func testAuthorizedRequestsExactlyOnceAndStops() async {
        let fake = FakeRequester(status: .notDetermined)
        let location = CurrentLocation(manager: fake)
        location.locate()
        location.handle(status: .authorizedWhenInUse)
        XCTAssertEqual(location.state, .locating)
        XCTAssertEqual(fake.locationRequests, 1)

        location.handle(latitude: 35.68, longitude: 139.76)
        XCTAssertEqual(location.state, .located(latitude: 35.68, longitude: 139.76))

        // iOS は権限の知らせを何度も送る。**押していないのに再要求しない**
        location.handle(status: .authorizedWhenInUse)
        location.handle(status: .authorizedWhenInUse)
        XCTAssertEqual(fake.locationRequests, 1)
        XCTAssertEqual(location.state, .located(latitude: 35.68, longitude: 139.76))
    }

    /// 管理者を作った直後の知らせ（押していない）では位置を取りにいかない
    func testAuthorizationNoticeWithoutTapDoesNothing() async {
        let fake = FakeRequester(status: .authorizedWhenInUse)
        let location = CurrentLocation(manager: fake)
        location.handle(status: .authorizedWhenInUse)
        XCTAssertEqual(location.state, .idle)
        XCTAssertEqual(fake.locationRequests, 0)
    }

    /// 取れなかったら「失敗」を返す（既定の座標に寄せない）
    func testFailureIsReported() async {
        let fake = FakeRequester(status: .authorizedWhenInUse)
        let location = CurrentLocation(manager: fake)
        location.locate()
        XCTAssertEqual(location.state, .locating)
        XCTAssertEqual(fake.locationRequests, 1)

        location.handle(error: URLError(.unknown))
        XCTAssertEqual(location.state, .failed)
    }
}
