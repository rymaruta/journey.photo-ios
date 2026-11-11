import Foundation

/// 地図の「スポット」の札（板 04c 案A）: 撮影スポットを近い順に並べた一覧。
///
/// - **公開済みの行だけ**（`isDraft` でない）。下書きは地図のピンと同じく一覧にも出さない
/// - **座標の無い行は出さない**（距離が測れない・地図にも置けない）
/// - 近さは**現在地から**。取れていなければ**地図の中心から**測る
///   （どちらも無ければ名前の順・距離は出さない）
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

    /// 撮影スポット id → 写真の枚数（本人が選んだ `spotId`、無ければ自動の結び）。
    /// 探すの撮影スポットの一覧は、これを写真か結びが変わったときだけ数えて持つ（札 #524）
    static func photoCounts(_ photos: [Photo], links: SpotPhotoLinks = .empty) -> [String: Int] {
        var counts: [String: Int] = [:]
        for photo in photos {
            if let id = links.spotId(for: photo) { counts[id, default: 0] += 1 }
        }
        return counts
    }

    static func rows(_ spots: [OfficialSpot], photos: [Photo], from center: Photo.Coords?,
                     links: SpotPhotoLinks = .empty) -> [Row] {
        rows(spots, counts: photoCounts(photos, links: links), from: center)
    }

    /// 数えておいた枚数で行を作る（`photoCounts`）
    static func rows(_ spots: [OfficialSpot], counts: [String: Int], from center: Photo.Coords?) -> [Row] {
        let rows = spots
            .filter { !$0.isDraft && $0.coords != nil }
            .map { spot in
                Row(spot: spot,
                    km: center.flatMap { c in spot.coords.map { TravelDistance.kilometers(from: c, to: $0) } },
                    photoCount: counts[spot.spotId] ?? 0)
            }
        return rows.sorted { a, b in
            switch (a.km, b.km) {
            case let (x?, y?) where x != y: return x < y
            default: return a.spot.name < b.spot.name
            }
        }
    }
}
