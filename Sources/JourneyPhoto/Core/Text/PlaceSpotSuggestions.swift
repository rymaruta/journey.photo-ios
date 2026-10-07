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

    /// `aliases` は slug → 別名（`OfficialSpotService.fetchAliases`・無ければ空）。別名にも当てる
    static func suggestions(query: String, near: Photo.Coords?, index: [OfficialSpot],
                            aliases: [String: [String]] = [:]) -> [OfficialSpot] {
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
        // **名前・読みで当たったものが先、別名だけで当たったものは後。** 別名は「町」「公園」の
        // ような一般の語を含むので、混ぜて3つで切ると、近い別名の当たりが名前の当たりを
        // 押し出した（47b7180 のレビュー・Web の searchSpotRows も名前が先）。段の中は近い順
        let byName = usable.filter { spot in
            [spot.name, spot.reading, spot.nameEn]
                .compactMap { $0 }
                .contains { MapSearch.fold($0).contains(needle) }
        }
        let named = Set(byName.map(\.spotId))
        let byAlias = usable.filter {
            !named.contains($0.spotId) && OfficialSpotIndex.aliasMatches(aliases[$0.slug], needle: needle)
        }
        func ordered(_ spots: [OfficialSpot]) -> [OfficialSpot] {
            guard let near else { return spots.sorted { ($0.name, $0.slug) < ($1.name, $1.slug) } }
            return byDistance(spots, from: near).map(\.spot)
        }
        return Array((ordered(byName) + ordered(byAlias)).prefix(limit))
    }

    /// スポットを選んだときに欄へ入れる座標。
    ///
    /// 🔴 **近くで撮った写真は写真の座標のまま。** スポットの座標（約1kmに丸めた値・3km 先の
    /// こともある）で撮った位置を置き換えて「正確」として送っていた。前に選んだ地名の座標も
    /// 残さない（残すと名前はスポット、座標は前の地名になった）
    ///
    /// 2026-10-07 判断（`PlaceCoordsRule`）: 書き換えた撮影地には写真の座標を付けないので、nil（写真の
    /// 座標のまま）ではなく、**写真から `PlaceCoordsRule.photoKm`（5km）以内のスポットなら写真の座標そのもの**
    /// （撮った位置を置き換えない決まりは守る）、遠いスポットはスポットの座標（写真の撮った位置を
    /// スポットの名前に付けない）。スポットに座標が無ければ nil
    static func coordsAfterPicking(_ spot: OfficialSpot, photoPosition: Photo.Coords?) -> Photo.Coords? {
        PlaceCoordsRule.coordsForPickedSpot(spot.coords, photo: photoPosition)
    }

    /// 近い順（同じ距離は slug 順・毎回同じ並び）
    private static func byDistance(_ spots: [OfficialSpot], from here: Photo.Coords) -> [(spot: OfficialSpot, km: Double)] {
        spots
            .compactMap { spot in spot.coords.map { (spot, TravelDistance.kilometers(from: here, to: $0)) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.slug < $1.0.slug }
            .map { (spot: $0.0, km: $0.1) }
    }
}
