import Foundation

/// 地図の「スポット」の札（板 04c 案A）: 撮影スポットを近い順に並べた一覧。
///
/// - **公開済みの行だけ**（`isDraft` でない）。下書きは地図のピンと同じく一覧にも出さない
/// - **座標の無い行は出さない**（距離が測れない・地図にも置けない）
/// - 近さは**現在地から**。取れていなければ**地図の中心から**測る
///   （どちらも無ければ名前の順・距離は出さない）
/// - **検索窓で絞っているときは、当たりの強さが先**（2026-11-09・`ranks`）: 名前の完全一致 → 前方一致 →
///   部分一致 → 地域の順に並べ、同じ強さの中だけ近い順。語を打った人は「近い所」より「名前が合う所」を探している
/// - 写真の数は、その撮影スポットの写真（本人が選んだ `Photo.spotId`、無ければ自動の結び・
///   `SpotPhotoLinks`・2026-10-31 #425）。スポットの画面（`OfficialSpotView`）が並べるものと同じ数え方
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
enum OfficialSpotList {

    struct Row: Identifiable, Equatable {
        let spot: OfficialSpot
        /// 起点からの距離。起点が無ければ nil
        let km: Double?
        let photoCount: Int

        var id: String { spot.spotId }
    }

    /// - Parameter ranks: `spotId` → 当たりの強さ（`SpotSearchIndex.Hit.rank`）。**検索窓に語があるときだけ**渡す。
    ///   無い行（渡していない `spotId`）は最後。nil なら近い順のまま
    static func rows(_ spots: [OfficialSpot], photos: [Photo], from center: Photo.Coords?,
                     links: SpotPhotoLinks = .empty, ranks: [String: Int]? = nil) -> [Row] {
        var counts: [String: Int] = [:]
        for photo in photos {
            if let id = links.spotId(for: photo) { counts[id, default: 0] += 1 }
        }
        let rows = spots
            .filter { !$0.isDraft && $0.coords != nil }
            .map { spot in
                Row(spot: spot,
                    km: center.flatMap { c in spot.coords.map { TravelDistance.kilometers(from: c, to: $0) } },
                    photoCount: counts[spot.spotId] ?? 0)
            }
        return rows.sorted { a, b in
            if let ranks {
                let ra = ranks[a.spot.spotId] ?? Int.max, rb = ranks[b.spot.spotId] ?? Int.max
                if ra != rb { return ra < rb }
            }
            switch (a.km, b.km) {
            case let (x?, y?) where x != y: return x < y
            default: return a.spot.name < b.spot.name
            }
        }
    }
}
