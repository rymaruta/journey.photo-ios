import Foundation
import Combine
import CoreLocation

/// 位置を要求する口。本物は `CLLocationManager`。**テストで偽物に差し替える**
/// ためだけの約束（Linux には CoreLocation が無く、実機でも権限のダイアログは
/// テストから押せない）
protocol LocationRequesting: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func requestLocation()
}

extension CLLocationManager: LocationRequesting {}

/// 現在地を**1回だけ**取る（モック3 の現在地ボタン）。
///
/// 使い道は「地図をそこへ寄せる」と「近くの写真」の中心。**このクラスは
/// 追跡しない・保存しない・送らない**——取った座標はカメラに渡して終わり。
/// （地図の青い点と自分を追う表示は MapKit が端末の中で描くもので、
/// こことは別。そちらも保存・送信はしない）。精度は km 級
/// （`kCLLocationAccuracyKilometer`）で、`docs/APP_REVIEW.md` の
/// 「精細な位置は『いいえ』」と食い違わせない。
///
/// **黙って何も起きない状態を作らない。** 拒否・失敗は `state` に載せて
/// 画面が言葉にする。取れる前に既定の座標へ寄せることもしない
/// （取れていないものを取れたふりで描かない）。
@MainActor
final class CurrentLocation: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        /// 権限を尋ねている（ダイアログが出ている）
        case asking
        /// 権限はあり、位置を待っている
        case locating
        case located(latitude: Double, longitude: Double)
        case denied
        case failed
    }

    @Published private(set) var state: State = .idle

    private let manager: LocationRequesting

    /// - Parameter manager: 省略すると本物。テストは偽物を渡す
    init(manager: LocationRequesting? = nil) {
        if let manager {
            self.manager = manager
            super.init()
        } else {
            let real = CLLocationManager()
            real.desiredAccuracy = kCLLocationAccuracyKilometer
            self.manager = real
            super.init()
            real.delegate = self
        }
    }

    /// ボタンを押したとき。権限が無ければ尋ね、あれば1回だけ位置を取る
    func locate() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .asking
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .denied
        case .authorizedAlways, .authorizedWhenInUse:
            state = .locating
            manager.requestLocation()
        }
    }

    // MARK: - 委譲から届くもの（テストは直接呼ぶ）

    /// 権限が変わった。**尋ねている最中にだけ動く**——iOS は管理者を作った
    /// 直後にも同じ知らせを送るので、そこで位置を要求すると押していないのに
    /// 取りにいく。取り終えたあとに再び届いても再要求しない（1回だけ）
    func handle(status: CLAuthorizationStatus) {
        guard state == .asking else { return }
        switch status {
        case .notDetermined:
            break
        case .denied, .restricted:
            state = .denied
        case .authorizedAlways, .authorizedWhenInUse:
            state = .locating
            manager.requestLocation()
        }
    }

    func handle(latitude: Double, longitude: Double) {
        guard state == .locating else { return }
        state = .located(latitude: latitude, longitude: longitude)
    }

    func handle(error: Error) {
        guard state == .locating else { return }
        state = .failed
    }
}

/// 委譲はメインアクタの外から呼ばれ得るので、値だけ取り出してから戻る
/// （`CLLocation` そのものは Sendable ではない）
extension CurrentLocation: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.handle(status: status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        Task { @MainActor in self.handle(latitude: latitude, longitude: longitude) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.handle(error: LocationError(message: message)) }
    }

    private struct LocationError: Error { let message: String }
}
