// CoreLocation の模型。
//
// **足してあるのは、アプリが使う口だけ。** どれも本物の CoreLocation に
// 実在する名前・形で、模型は素通し（位置は取れず、権限も変わらない）。
// 実在しない口をここに置くと、手元では通って実機で落ちる。
import Foundation

public typealias CLLocationDegrees = Double
public typealias CLLocationAccuracy = Double

/// 精度の指定。**精細な位置は求めない**（`docs/APP_REVIEW.md` の
/// 「精細な位置は『いいえ』」と揃える）ので、km 級だけを写している
public let kCLLocationAccuracyKilometer: CLLocationAccuracy = 1000

/// 本物では CoreLocation の型。MapKit を読むと透けて見えるので、
/// MapKit の模型は `@_exported import CoreLocation` でこれを見せる
public struct CLLocationCoordinate2D {
    public var latitude: CLLocationDegrees
    public var longitude: CLLocationDegrees
    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum CLAuthorizationStatus {
    case notDetermined, restricted, denied, authorizedAlways, authorizedWhenInUse
}

open class CLLocation: NSObject {
    public let coordinate: CLLocationCoordinate2D
    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 本物は `@objc optional`。模型では空の既定実装を置いて任意扱いにする
public protocol CLLocationManagerDelegate: NSObjectProtocol {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
}
public extension CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

open class CLLocationManager: NSObject {
    public weak var delegate: CLLocationManagerDelegate?
    public var desiredAccuracy: CLLocationAccuracy = 0
    /// iOS 14 からのインスタンス属性（クラス属性の方は非推奨）
    public var authorizationStatus: CLAuthorizationStatus { .notDetermined }
    public override init() {}
    public func requestWhenInUseAuthorization() {}
    /// 1回だけ取る口。`startUpdatingLocation`（追跡）は使わないので写していない
    public func requestLocation() {}
}
