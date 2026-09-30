import Foundation

/// 撮影地の欄に出す、撮影スポットの候補（2026-09-30・強化案「撮影地の候補に台帳を先に出す」）。
///
/// 今の候補は地名検索（Nominatim）の5件だけで、選ぶと長い住所がそのまま入り、
/// 同じ場所が別々の名前に散っていた。撮影スポットの索引（`OfficialSpot`）は名前・読み・
/// 座標を持つので、**地名検索より先に**出す。索引は端末の中で引く（通信は増えない）。
///
/// - 欄が空: **写真の位置の近く**（`nearKm` 以内）の場所を近い順に
/// - 打った語: 名前・読み・英語名に当たる場所。写真の位置があれば近い順、無ければ名前順
/// - **公開済みの場所だけ**（運営の下書きの名前を撮影地に入れさせない）。座標の無い場所は出さない
///
/// 選んでも**写真とスポットの紐付けはしない**（紐付けは人が確かめてから・サーバーも断る）。
/// 入るのはスポットの名前と座標（どちらも約1kmに丸めた公開の値）だけ。
enum PlaceSpotSuggestions {

    /// 近くと呼ぶ距離（km）。座標は約1kmに丸めてあるので、狭くしすぎない
    static let nearKm: Double = 3
    /// 出す数。**地名検索の候補を押し出さない**よう少なめに
    static let limit = 3

    static func suggestions(query: String, near: Photo.Coords?, index: [OfficialSpot]) -> [OfficialSpot] {
        var seen = Set<String>()
        let usable = index.filter { !$0.isDraft && $0.coords != nil && seen.insert($0.spotId).inserted }
        let needle = MapSearch.fold(query)
        if needle.isEmpty {
            guard let near else { return [] }
            return Array(byDistance(usable, from: near)
                .filter { $0.km <= nearKm }
                .map(\.spot)
                .prefix(limit))
        }
        let matched = usable.filter { spot in
            [spot.name, spot.reading, spot.nameEn]
                .compactMap { $0 }
                .contains { MapSearch.fold($0).contains(needle) }
        }
        guard let near else {
            return Array(matched.sorted { ($0.name, $0.slug) < ($1.name, $1.slug) }.prefix(limit))
        }
        return Array(byDistance(matched, from: near).map(\.spot).prefix(limit))
    }

    /// 近い順（同じ距離は slug 順・毎回同じ並び）
    private static func byDistance(_ spots: [OfficialSpot], from here: Photo.Coords) -> [(spot: OfficialSpot, km: Double)] {
        spots
            .compactMap { spot in spot.coords.map { (spot, TravelDistance.kilometers(from: here, to: $0)) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.slug < $1.0.slug }
            .map { (spot: $0.0, km: $0.1) }
    }
}
