import Foundation
import MapKit

/// 撮影スポットへの経路を Apple のマップで開く（地図の札・旅行プランの地図で共通）。
///
/// 🔴 **索引の座標は約1kmに丸めてある**ので、そのまま渡すと山や滝では入口と違う道に案内する。
/// 名前で探し直して、丸めた座標から `OfficialSpotIndex.directionsMatchKm` 以内でいちばん近い
/// 地点を使う。見つからない・`directionsTimeout` 秒で返らなければ、丸めた座標に名前を付けて渡す。
/// 地図の札（`PhotoMapView.openDirections`）にあった作りを、旅行プランの地図でも使うために寄せた
@MainActor
enum SpotDirections {

    /// 行き先の地点。探し直せれば Apple の地点、だめなら丸めた座標に名前を付けたもの
    static func item(name: String, coords: Photo.Coords) async -> MKMapItem {
        let found = await AsyncTimeout.firstWithin(seconds: OfficialSpotIndex.directionsTimeout) {
            await search(name: name, coords: coords)
        }
        return found ?? rounded(name: name, coords: coords)
    }

    /// 丸めた座標に名前を付けた地点（探し直さない）
    static func rounded(name: String, coords: Photo.Coords) -> MKMapItem {
        let coordinate = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }

    private static func search(name: String, coords: Photo.Coords) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return nil }
        let candidates = items.map {
            Photo.Coords(lat: $0.placemark.coordinate.latitude, lng: $0.placemark.coordinate.longitude)
        }
        return OfficialSpotIndex.directionsTargetIndex(of: candidates, near: coords).map { items[$0] }
    }
}
