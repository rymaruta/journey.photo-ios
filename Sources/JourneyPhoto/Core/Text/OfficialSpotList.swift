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

    static func rows(_ spots: [OfficialSpot], photos: [Photo], from center: Photo.Coords?,
                     links: SpotPhotoLinks = .empty) -> [Row] {
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
            switch (a.km, b.km) {
            case let (x?, y?) where x != y: return x < y
            default: return a.spot.name < b.spot.name
            }
        }
    }

    /// 「スポット」の札に出す行。上の欄で打った語があれば名前で絞り（地図のピンと同じ当て方）、近い順に並べる。
    /// 画面の body から外に出した計算の本体（2026-11-04）。`SpotListCache` が入力の変わった回だけ呼ぶ
    static func visibleRows(spots: [OfficialSpot], query: String, aliases: [String: [String]],
                            photos: [Photo], links: SpotPhotoLinks, from center: Photo.Coords?) -> [Row] {
        let matched = MapSearch.fold(query).isEmpty
            ? spots
            : OfficialSpotIndex.matches(spots, query: query, aliases: aliases)
        return rows(matched, photos: photos, from: center, links: links)
    }
}

/// 「スポット」の札の行の控え（2026-11-04 判断）。
///
/// 以前は `spotsArea` の body の中で毎回 `OfficialSpotList.rows` を呼んでいた（写真の全件の走査＋
/// スポット約2,850件の距離計算と並べ替え）。モデルの `@Published` のどれが変わっても走るので、
/// **入力が変わった回だけ**計算する。入力は「モデルが持つ値の改訂番号（`revision`）」と「起点」。
/// 改訂番号は `PhotoMapViewModel` が query・photos・officialSpots・photoLinks・spotAliases の
/// `didSet` で上げる（配列の中身を比べ直さない）。結果は1つの値で持つ。
struct SpotListCache {
    struct Key: Equatable {
        let revision: Int
        let center: Photo.Coords?
    }

    private var key: Key?
    private var rows: [OfficialSpotList.Row] = []
    /// 計算した回数（試験で「2回呼んでも1回」を数えるためだけ）
    private(set) var computeCount = 0

    mutating func rows(for key: Key, compute: () -> [OfficialSpotList.Row]) -> [OfficialSpotList.Row] {
        if self.key == key { return rows }
        rows = compute()
        self.key = key
        computeCount += 1
        return rows
    }
}
