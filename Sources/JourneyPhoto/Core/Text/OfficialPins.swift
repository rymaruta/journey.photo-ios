import Foundation

/// 地図に置く撮影スポットのピン（モック4 の小さな丸い印）。
///
/// 🔴 **1,417件を常時 `Annotation` で置かない。** 日本全体の倍率では
/// 重なって塊になるだけで、描く負担ばかり増える。置くのは:
///
///   - **寄せたとき**（緯度幅 `maxLatitudeSpan` 未満 ≈ 55km）、枠の中を
///     中心に近い順に最大 `limit` 本
///   - **名前で絞っているとき**は倍率に関係なく、当たったものを最大 `limit` 本
///     （owner が名前でスポットを探す入口——検索の画面には節を足さない）。
///     **枠は捨てない**——枠の中の候補を近い順に先、そのあと枠の外を中心から
///     近い順。京都に寄せて「寺」なら京都の寺が先頭に来る
///
/// 画面を持たない層（`MapKit` を読まない）に置いてあるので、
/// Linux の `swift test` で確かめられる。
enum OfficialPins {

    struct Pin: Identifiable, Equatable {
        let spotId: String
        let slug: String
        let name: String
        /// 「[都道府県] · [市区町村]」。無ければ nil
        let regionLabel: String?
        let coords: Photo.Coords
        /// 札に「下書き」と書くため（`published` 以外は全部 true）
        let isDraft: Bool

        var id: String { spotId }
    }

    /// これより引いているときは置かない（度）。**線の上は「引いている」側**
    static let maxLatitudeSpan = 0.5
    /// 一度に置く上限
    static let limit = 60

    /// - Parameters:
    ///   - frame: いま見えている枠（「このエリアを検索」中はその枠）。nil なら置かない
    ///   - query: 検索窓の文字。空でなければ倍率を見ずに当たったものを出す
    static func visible(_ spots: [OfficialSpot], frame: MapFraming.Frame?, query: String = "") -> [Pin] {
        if !MapSearch.fold(query).isEmpty {
            // 索引の側で名前の一致順（名前 → 地域）に並んでいる。座標の無い行は置けない
            let matched = OfficialSpotIndex.matches(spots, query: query).compactMap(pin)
            // 枠が無ければその並びのまま。あれば**枠の中を先に・近い順**
            guard let frame else { return Array(matched.prefix(limit)) }
            let center = Photo.Coords(lat: frame.latitude, lng: frame.longitude)
            return matched
                .map { pin -> (Pin, Bool, Double) in
                    (pin,
                     MapSearch.contains(frame, latitude: pin.coords.lat, longitude: pin.coords.lng),
                     TravelDistance.kilometers(from: center, to: pin.coords))
                }
                .sorted {
                    if $0.1 != $1.1 { return $0.1 }
                    if $0.2 != $1.2 { return $0.2 < $1.2 }
                    return $0.0.slug < $1.0.slug
                }
                .prefix(limit)
                .map(\.0)
        }
        guard let frame, frame.latitudeSpan < maxLatitudeSpan else { return [] }
        let center = Photo.Coords(lat: frame.latitude, lng: frame.longitude)
        return spots
            .compactMap { spot -> (Pin, Double)? in
                guard let pin = pin(spot),
                      MapSearch.contains(frame, latitude: pin.coords.lat, longitude: pin.coords.lng)
                else { return nil }
                return (pin, TravelDistance.kilometers(from: center, to: pin.coords))
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.slug < $1.0.slug }
            .prefix(limit)
            .map(\.0)
    }

    /// **id の集まりで比べる。** 並びが違うだけなら「変わっていない」
    /// ——入れ替えるたびに描き直し → カメラの知らせ → … と回る種になる
    static func changed(_ before: [Pin], _ after: [Pin]) -> Bool {
        Set(before.map(\.id)) != Set(after.map(\.id))
    }

    private static func pin(_ spot: OfficialSpot) -> Pin? {
        guard let coords = spot.coords else { return nil }
        return Pin(spotId: spot.spotId, slug: spot.slug, name: spot.name,
                   regionLabel: spot.regionLabel, coords: coords, isDraft: spot.isDraft)
    }
}
