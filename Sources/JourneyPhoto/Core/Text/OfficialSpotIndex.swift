import Foundation

/// 撮影スポットの索引（`OfficialSpot`）を**手元で引く**。通信しない。
///
/// 名前で探す（地図の検索窓）と、近くのスポット（画面の末尾）の2つ。
/// どちらも画面を持たない層に置いて、Linux の `swift test` で動かす。
enum OfficialSpotIndex {

    /// 名前・読み・英語名・都道府県・市区町村のどれかに当たるもの。
    /// **空の語は何も当てない**（「絞っていない」）。全角半角・大小は区別しない。
    ///
    /// **名前で当たったものが先**、地域だけで当たったものはその後ろ。
    /// 同じ段の中は slug 順（毎回同じ並びにする）
    static func matches(_ spots: [OfficialSpot], query: String, limit: Int = 60) -> [OfficialSpot] {
        let needle = MapSearch.fold(query)
        guard !needle.isEmpty else { return [] }
        return spots
            .compactMap { spot -> (OfficialSpot, Int)? in
                if nameMatches(spot, needle: needle) { return (spot, 0) }
                if regionMatches(spot, needle: needle) { return (spot, 1) }
                return nil
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.slug < $1.0.slug }
            .prefix(limit)
            .map(\.0)
    }

    private static func nameMatches(_ spot: OfficialSpot, needle: String) -> Bool {
        [spot.name, spot.reading, spot.nameEn]
            .compactMap { $0 }
            .contains { MapSearch.fold($0).contains(needle) }
    }

    private static func regionMatches(_ spot: OfficialSpot, needle: String) -> Bool {
        [spot.region?.prefecture, spot.region?.city]
            .compactMap { $0 }
            .contains { MapSearch.fold($0).contains(needle) }
    }

    /// 近くの撮影スポット。**座標を持っているものだけ**、自分を除いて近い順。
    /// 距離は写真と同じ式（`TravelDistance.kilometers`）。同じ距離は slug 順
    static func nearby(_ spot: OfficialSpot, in spots: [OfficialSpot],
                       limit: Int = 6) -> [(spot: OfficialSpot, km: Double)] {
        guard let here = spot.coords else { return [] }
        return spots
            .filter { $0.spotId != spot.spotId }
            .compactMap { other -> (spot: OfficialSpot, km: Double)? in
                guard let there = other.coords else { return nil }
                return (other, TravelDistance.kilometers(from: here, to: there))
            }
            .sorted { $0.km != $1.km ? $0.km < $1.km : $0.spot.slug < $1.spot.slug }
            .prefix(limit)
            .map { $0 }
    }
}
