import Foundation
import MapKit

/// AI が並べた日程の**移動が無理な日**を、Apple の地図の目安（`MKDirections.calculateETA`・車）で測って直す（札 #621）。
///
/// 1日の移動の合計が `TripAILimits.maxTravelMinutesPerDay`（4時間）を超えたら、その日の中で
/// **ほかの場所からいちばん遠い所**から外し、外した場所は「外しました　戻す」で残す（案「AI が間違えそうなとき」）。
/// 測れなかった区間（圏外・地図が答えない）は 0 分として数える——測れないのに外さない（行き止まりにしない）
enum TripAIRouteCheck {

    struct Removed: Equatable {
        let spot: OfficialSpot
        /// 外した日（0 から）
        let day: Int
        /// 外す前のその日の移動（分）
        let minutes: Int

        static func == (a: Removed, b: Removed) -> Bool { a.spot.spotId == b.spot.spotId && a.day == b.day }
    }

    /// 区間の移動の分。測れなければ nil
    typealias ETA = (Photo.Coords, Photo.Coords) async -> Int?

    static func trim(_ days: [[OfficialSpot]], limit: Int = TripAILimits.maxTravelMinutesPerDay,
                     eta: ETA = mapsETA) async -> (days: [[OfficialSpot]], removed: [Removed]) {
        var cache: [String: Int?] = [:]
        func leg(_ a: OfficialSpot, _ b: OfficialSpot) async -> Int {
            guard let ca = a.coords, let cb = b.coords else { return 0 }
            let key = "\(a.spotId)>\(b.spotId)"
            if let hit = cache[key] { return hit ?? 0 }
            let m = await eta(ca, cb)
            cache[key] = m
            return m ?? 0
        }
        func total(_ day: [OfficialSpot]) async -> Int {
            var sum = 0
            for i in day.indices.dropFirst() { sum += await leg(day[i - 1], day[i]) }
            return sum
        }
        var out = days
        var removed: [Removed] = []
        for d in out.indices {
            var minutes = await total(out[d])
            while minutes > limit, out[d].count > 1 {
                let i = farthest(out[d])
                removed.append(Removed(spot: out[d][i], day: d, minutes: minutes))
                out[d].remove(at: i)
                minutes = await total(out[d])
            }
        }
        return (out.filter { !$0.isEmpty }, removed)
    }

    /// その日の中で、ほかの場所の真ん中からいちばん遠い所（座標の無い所は外さない）
    static func farthest(_ day: [OfficialSpot]) -> Int {
        var best = day.count - 1
        var bestKm = -1.0
        for (i, s) in day.enumerated() {
            guard let c = s.coords else { continue }
            let others = day.enumerated().filter { $0.offset != i }.compactMap(\.element.coords)
            guard !others.isEmpty else { continue }
            let mid = Photo.Coords(lat: others.map(\.lat).reduce(0, +) / Double(others.count),
                                   lng: others.map(\.lng).reduce(0, +) / Double(others.count))
            let km = TripAICandidates.km(c, mid)
            if km > bestKm { bestKm = km; best = i }
        }
        return best
    }

    /// Apple の地図の目安（車）。測れなければ nil
    static let mapsETA: ETA = { from, to in
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: from.lat, longitude: from.lng)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: to.lat, longitude: to.lng)))
        request.transportType = .automobile
        guard let eta = try? await MKDirections(request: request).calculateETA(), eta.expectedTravelTime > 0 else { return nil }
        return Int((eta.expectedTravelTime / 60).rounded())
    }
}
