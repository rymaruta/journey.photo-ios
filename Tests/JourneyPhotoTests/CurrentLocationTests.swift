import XCTest
import CoreLocation
@testable import JourneyPhoto

/// 現在地は**1回だけ**取り、拒否・失敗を黙って飲み込まない。
@MainActor
final class CurrentLocationTests: XCTestCase {

    /// 本物の `CLLocationManager` の代わり。呼ばれた回数を数える
    private final class FakeRequester: LocationRequesting {
        var status: CLAuthorizationStatus
        /// 許可の状態を何回読まれたか（本物はメインスレッドで読むと待つ・札 #594）
        var statusReads = 0
        var authorizationStatus: CLAuthorizationStatus {
            statusReads += 1
            return status
        }
        var authorizationRequests = 0
        var locationRequests = 0
        init(status: CLAuthorizationStatus) { self.status = status }
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

    /// `locateIfAllowed` は**尋ねない**: 未決・拒否では何もしない。許されていれば1回だけ取る（札 #524）
    func testLocateIfAllowedNeverAsks() async {
        for status in [CLAuthorizationStatus.notDetermined, .denied, .restricted] {
            let fake = FakeRequester(status: status)
            let location = CurrentLocation(manager: fake)
            location.locateIfAllowed()
            XCTAssertEqual(location.state, .idle)
            XCTAssertEqual(fake.authorizationRequests, 0)
            XCTAssertEqual(fake.locationRequests, 0)
        }
        let fake = FakeRequester(status: .authorizedWhenInUse)
        let location = CurrentLocation(manager: fake)
        location.locateIfAllowed()
        location.locateIfAllowed()
        XCTAssertEqual(location.state, .locating)
        XCTAssertEqual(fake.locationRequests, 1)
        XCTAssertEqual(fake.authorizationRequests, 0)
        XCTAssertFalse(location.requestedByUser)
        // 取れたあと（一覧に戻ってきた）・失敗したあとも取り直さない（並びが目の前で動かない）
        location.handle(latitude: 35, longitude: 139)
        location.locateIfAllowed()
        XCTAssertEqual(fake.locationRequests, 1)
        XCTAssertEqual(location.state, .located(latitude: 35, longitude: 139))
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

    /// 地図を開いたときの自動の回は「押していない」と分かる。
    /// 断られても画面が黙れるように（開くたびに「許可されていません」を出さない）
    func testAutomaticLocateIsMarkedAsNotRequestedByUser() async {
        let fake = FakeRequester(status: .denied)
        let location = CurrentLocation(manager: fake)
        location.locate(requestedByUser: false)
        XCTAssertEqual(location.state, .denied)
        XCTAssertFalse(location.requestedByUser)
        XCTAssertEqual(fake.authorizationRequests, 0)
    }

    /// 自動の回のあとにボタンを押したら、その回は「押した」になる（拒否を言葉にする）
    func testButtonAfterAutomaticIsRequestedByUser() async {
        let fake = FakeRequester(status: .denied)
        let location = CurrentLocation(manager: fake)
        location.locate(requestedByUser: false)
        location.locate()
        XCTAssertEqual(location.state, .denied)
        XCTAssertTrue(location.requestedByUser)
    }

    /// 自動の回でも、許可があれば位置は1回だけ取りにいく
    func testAutomaticLocateRequestsOnceWhenAuthorized() async {
        let fake = FakeRequester(status: .authorizedWhenInUse)
        let location = CurrentLocation(manager: fake)
        location.locate(requestedByUser: false)
        XCTAssertEqual(location.state, .locating)
        XCTAssertEqual(fake.locationRequests, 1)
        location.handle(latitude: 35.68, longitude: 139.76)
        XCTAssertEqual(location.state, .located(latitude: 35.68, longitude: 139.76))
    }
    // MARK: - 許可の状態をメインスレッドで聞かない（2026-11-25 札 #594・run 1786 の地図の止まり 2,296ms）

    /// 本物は、管理者を作った直後の知らせ（`locationManagerDidChangeAuthorization`）より前に状態を読まない。
    /// 地図を開いた時の自動の回は控えておき、知らせが来たら1回だけ取る
    func testWaitsForStatusNoticeInsteadOfReadingStatus() async {
        let fake = FakeRequester(status: .authorizedWhenInUse)
        let location = CurrentLocation(manager: fake, waitsForStatusNotice: true)
        location.locate(requestedByUser: false)
        XCTAssertEqual(location.state, .idle, "知らせの前は動かない（状態を聞きに行かない）")
        XCTAssertEqual(fake.statusReads, 0, "メインスレッドで許可の状態を読まない")
        XCTAssertEqual(fake.locationRequests, 0)

        location.handle(status: .authorizedWhenInUse)
        XCTAssertEqual(location.state, .locating)
        XCTAssertEqual(fake.locationRequests, 1)
        XCTAssertFalse(location.requestedByUser)
        // 同じ知らせがもう一度来ても取り直さない
        location.handle(status: .authorizedWhenInUse)
        XCTAssertEqual(fake.locationRequests, 1)
        XCTAssertEqual(fake.statusReads, 0)
    }

    /// 知らせのあとは控えた状態で動く（ボタンを押すたびに管理者へ聞きに行かない）
    func testUsesStatusFromNoticeAfterward() async {
        let fake = FakeRequester(status: .denied)
        let location = CurrentLocation(manager: fake, waitsForStatusNotice: true)
        location.handle(status: .denied)
        XCTAssertEqual(location.state, .idle, "押していない知らせでは何もしない")
        location.locate()
        XCTAssertEqual(location.state, .denied)
        XCTAssertTrue(location.requestedByUser)
        XCTAssertEqual(fake.statusReads, 0)
        XCTAssertEqual(fake.authorizationRequests, 0)
    }

    /// 知らせの前に押したボタン（まだ決めていない人）は、知らせが来たら尋ねる
    func testPendingLocateAsksOnceStatusIsKnown() async {
        let fake = FakeRequester(status: .notDetermined)
        let location = CurrentLocation(manager: fake, waitsForStatusNotice: true)
        location.locate()
        XCTAssertEqual(fake.authorizationRequests, 0)
        location.handle(status: .notDetermined)
        XCTAssertEqual(location.state, .asking)
        XCTAssertEqual(fake.authorizationRequests, 1)
        location.handle(status: .authorizedWhenInUse)
        XCTAssertEqual(location.state, .locating)
        XCTAssertEqual(fake.locationRequests, 1)
    }

    /// 尋ねない回（`locateIfAllowed`）は、知らせのあとも尋ねない。ボタンが重なれば尋ねる方が勝つ
    func testPendingLocateIfAllowedNeverAsks() async {
        let fake = FakeRequester(status: .notDetermined)
        let location = CurrentLocation(manager: fake, waitsForStatusNotice: true)
        location.locateIfAllowed()
        location.handle(status: .notDetermined)
        XCTAssertEqual(location.state, .idle)
        XCTAssertEqual(fake.authorizationRequests, 0)

        let other = CurrentLocation(manager: FakeRequester(status: .notDetermined), waitsForStatusNotice: true)
        other.locate()
        other.locateIfAllowed()
        other.handle(status: .notDetermined)
        XCTAssertEqual(other.state, .asking, "先に押したボタンを、尋ねない回で上書きしない")
    }

    /// 本物（管理者を渡さない）は知らせを待つ。知らせが来ない間は尋ねも取りもしない
    func testRealManagerWaitsForNotice() async {
        let location = CurrentLocation()
        location.locate(requestedByUser: false)
        XCTAssertEqual(location.state, .idle)
        // 控えた回をここで済ませる（Mac の試験で本物の知らせが後から来ても、許可のダイアログを出さない）
        location.handle(status: .denied)
        XCTAssertEqual(location.state, .denied)
    }
}
