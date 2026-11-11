import MapKit
import XCTest

/// 移動の見込み（旅行プラン・札 #521）の前に、**事実を取る**ための小さな試験（2026-11-10 判断）。
///
/// `MKDirections.calculateETA` が日本の区間で、車・歩き・公共交通（`.transit`）の時間を返すかを、
/// Mac のシミュレーターから Apple のサーバーに聞いて確かめる。公式の文書では「公共交通は所要時間の
/// 見込みにだけ使える」までしか分からず、日本の区間で返るかは書いていない。
///
/// **合否は付けない。** 返った秒数・距離・失敗の種類を 1 行ずつ（`ETA route=… mode=… seconds=…`）
/// ログと活動の名前（`XCTContext.runActivity`）に残すだけ。成果物 `build-logs` の `xcodebuild-full.log` で読む。
/// **名指しした回だけ流れる**（`Tools/pick-ui-tests.py` の `ONLY_WHEN_NAMED`・`inputs[screens]=MapETAProbeTests`）。
/// 位置は今いる場所を取らない（決めた 2 区間の座標だけを送る）
final class MapETAProbeTests: XCTestCase {

    private struct Route {
        let name: String
        let from: CLLocationCoordinate2D
        let to: CLLocationCoordinate2D
    }

    /// 金沢駅 → 東尋坊（約 60km・車と電車なら返るはずの遠い区間）、金沢駅 → 兼六園（約 2km・歩ける区間）
    private let routes = [
        Route(name: "kanazawa-tojinbo",
              from: CLLocationCoordinate2D(latitude: 36.5781, longitude: 136.6479),
              to: CLLocationCoordinate2D(latitude: 36.2376, longitude: 136.1260)),
        Route(name: "kanazawa-kenrokuen",
              from: CLLocationCoordinate2D(latitude: 36.5781, longitude: 136.6479),
              to: CLLocationCoordinate2D(latitude: 36.5621, longitude: 136.6627)),
    ]

    private let modes: [(String, MKDirectionsTransportType)] = [
        ("automobile", .automobile), ("walking", .walking), ("transit", .transit),
    ]

    func testProbesJapanETA() async throws {
        for route in routes {
            for (modeName, mode) in modes {
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: route.from))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: route.to))
                request.transportType = mode
                var fields = "ETA route=\(route.name) mode=\(modeName)"
                do {
                    let eta = try await MKDirections(request: request).calculateETA()
                    fields += " seconds=\(Int(eta.expectedTravelTime)) meters=\(Int(eta.distance))"
                        + " returnedMode=\(eta.transportType.rawValue)"
                } catch {
                    let ns = error as NSError
                    fields += " error=\(ns.domain):\(ns.code)"
                    if let mk = error as? MKError { fields += " mkError=\(mk.code.rawValue)" }
                    fields += " message=\(ns.localizedDescription.replacingOccurrences(of: " ", with: "_"))"
                }
                print(fields)
                XCTContext.runActivity(named: fields) { _ in }
                // 短い間に多く聞くと loadingThrottled で断られる（Apple の文書）ので、間を空ける
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }
}
