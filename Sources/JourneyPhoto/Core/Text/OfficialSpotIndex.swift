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
    /// 同じ段の中は slug 順（毎回同じ並びにする）。`limit` が nil なら全部
    /// （地図は枠で並べ直してから切るので、ここでは切らない）
    static func matches(_ spots: [OfficialSpot], query: String, limit: Int? = nil) -> [OfficialSpot] {
        let needle = MapSearch.fold(query)
        guard !needle.isEmpty else { return [] }
        let ranked = spots
            .compactMap { spot -> (OfficialSpot, Int)? in
                if nameMatches(spot, needle: needle) { return (spot, 0) }
                if regionMatches(spot, needle: needle) { return (spot, 1) }
                return nil
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.slug < $1.0.slug }
            .map(\.0)
        guard let limit else { return ranked }
        return Array(ranked.prefix(limit))
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
    /// 距離は写真と同じ式（`TravelDistance.kilometers`）。同じ距離は slug 順。
    /// **同じ `spotId` は1つだけ（先勝ち）**——画面は `spotId` で並べるので、
    /// 重なると同じ札が2つ出る（索引を読む側 `LenientOfficialSpotList` でも落とす）
    static func nearby(_ spot: OfficialSpot, in spots: [OfficialSpot],
                       limit: Int = 6) -> [(spot: OfficialSpot, km: Double)] {
        guard let here = spot.coords else { return [] }
        var seen: Set<String> = [spot.spotId]
        return spots
            .filter { seen.insert($0.spotId).inserted }
            .compactMap { other -> (spot: OfficialSpot, km: Double)? in
                guard let there = other.coords else { return nil }
                return (other, TravelDistance.kilometers(from: here, to: there))
            }
            .sorted { $0.km != $1.km ? $0.km < $1.km : $0.spot.slug < $1.spot.slug }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 経路の行き先

    /// 経路の行き先を名前の検索結果から拾い直すときの距離（km）。
    ///
    /// 🔴 **索引の座標は約1km に丸めてある**（小数2桁。台帳 `content/spots.json`
    /// の時点で丸めてあり、丸める前の値はどこにも無い）。丸めのずれは最大で
    /// 緯度 0.005°≒0.56km・経度 0.005°≒0.45km、斜めで約0.7km。そのまま
    /// 経路に渡すと、山や滝では**入口と違う道の上**に案内する。
    /// 地図で押した地点の拾い直し（`PlaceLookup.sameSpotKm` = 0.3km）より
    /// 広く取るのはこのずれのぶん
    static let directionsMatchKm: Double = 1.5

    /// 名前で探した候補のうち、丸めた座標から `directionsMatchKm` 以内で
    /// いちばん近いものの位置。無ければ nil（丸めた座標に名前を付けて渡す）
    static func directionsTargetIndex(of candidates: [Photo.Coords], near rounded: Photo.Coords) -> Int? {
        PlaceLookup.nearestIndex(of: candidates, to: rounded, withinKm: directionsMatchKm)
    }
}
