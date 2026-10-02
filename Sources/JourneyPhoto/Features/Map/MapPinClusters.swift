import Foundation

/// 写真のピンを**多すぎるときだけ**近いものでまとめる（2026-10-02）。
///
/// ピンは撮影地（約1km に丸めた座標）ごとに1つで、上限が無かった。写真が増えると
/// 日本全体の倍率で数百の `Annotation` が並び、それぞれが画像を読む。撮影スポットの
/// ピン（`OfficialPins` の「最大60本」）に倣って、**見えている範囲で `limit` を超えたら**
/// 近いピンを束にする:
///
///   - 全部で `limit` 本以下なら**今までどおり**（枠を見ない——地図を動かしても描き直さない）
///   - 超えたら、見えている枠（周りに `margin` ぶん足す）の中だけを置く。それでも超えたら
///     **世界に固定した格子**（2 の冪の度）で同じ升のピンを1つの束にし、`limit` 以下に
///     なるまで升を倍にする。格子を枠ではなく世界に固定するのは、少し動かしただけで
///     束の組み方（と id）が変わり、全部の印が作り直されないようにするため
///
/// 束を押すと、その束が収まる枠まで寄る（Web の `mapClusters.ts` と同じふるまい）。
/// 束はピンを選ばない——札（`MapPin`）の仕組みには触らない。
///
/// 画面を持たない計算なので、Linux の `swift test` で確かめられる。
enum MapPinClusters {

    /// 一度に置く印の上限（撮影スポットの `OfficialPins.limit` と同じ）
    static let limit = 60
    /// 枠のまわりに足す幅（枠の幅に対する割合・片側）。少し動かしたときに縁が空かない
    static let margin = 0.5
    /// 枠の長い辺を何升に割るところから始めるか
    static let gridDivisions = 8.0

    struct Cluster: Identifiable, Equatable {
        let id: String
        let latitude: Double
        let longitude: Double
        /// 束ねた撮影地（写真の多い順）
        let pins: [MapPin]

        var photoCount: Int { pins.reduce(0) { $0 + $1.photos.count } }
        /// 印に出す1枚（いちばん写真の多い撮影地の先頭）
        var cover: Photo? { pins.first?.photos.first }

        /// 押したときに寄る枠。束の全部が入る矩形に余白（`MapFraming.padding`）を足す
        var frame: MapFraming.Frame {
            let lats = pins.map(\.coordinate.latitude)
            let lngs = pins.map(\.coordinate.longitude)
            let (south, north) = (lats.min() ?? latitude, lats.max() ?? latitude)
            let (west, east) = (lngs.min() ?? longitude, lngs.max() ?? longitude)
            return MapFraming.Frame(
                latitude: (south + north) / 2, longitude: (west + east) / 2,
                latitudeSpan: max((north - south) * MapFraming.padding, MapFraming.minimumSpan),
                longitudeSpan: max((east - west) * MapFraming.padding, MapFraming.minimumSpan))
        }

        /// **id と中の撮影地で比べる**（`MapPin ==` は id しか見ない）
        static func == (lhs: Cluster, rhs: Cluster) -> Bool {
            lhs.id == rhs.id && lhs.pins.map(\.id) == rhs.pins.map(\.id)
        }
    }

    /// 地図に置くもの。`pins` はそのまま置く撮影地、`clusters` は束
    struct Layout: Equatable {
        var pins: [MapPin] = []
        var clusters: [Cluster] = []

        /// 置く印の数
        var markerCount: Int { pins.count + clusters.count }

        /// 選んでいるピンが**結果には居るのに地図に置かれていない**（束に吸われた・枠の外）か。
        /// true なら選びを外す。結果から外れたピン（絞り込み）は false——選びを持ち続ける決まり
        func hides(_ selected: MapPin?, among results: [MapPin]) -> Bool {
            guard let selected, results.contains(where: { $0.id == selected.id }) else { return false }
            return !pins.contains { $0.id == selected.id }
        }

        /// **id の並びで比べる。** 中身（写真）の入れ替わりは `refresh` が必ず入れ直すので、
        /// 地図を動かしたときに見るのは組み方が変わったかだけ
        static func == (lhs: Layout, rhs: Layout) -> Bool {
            lhs.pins.map(\.id) == rhs.pins.map(\.id) && lhs.clusters == rhs.clusters
        }
    }

    /// - Parameters:
    ///   - pins: 絞り込んだあとのピン（`MapPin.group`）
    ///   - frame: いま見えている枠。まだ届いていなければ nil（全部のピンを囲む枠で数える）
    static func layout(_ pins: [MapPin], frame: MapFraming.Frame?, limit: Int = limit) -> Layout {
        guard pins.count > limit, limit > 0 else { return Layout(pins: pins) }
        let area: MapFraming.Frame
        let inArea: [MapPin]
        if let frame {
            area = MapFraming.Frame(latitude: frame.latitude, longitude: frame.longitude,
                                    latitudeSpan: frame.latitudeSpan * (1 + 2 * margin),
                                    longitudeSpan: frame.longitudeSpan * (1 + 2 * margin))
            inArea = pins.filter {
                MapSearch.contains(area, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            }
        } else {
            area = bounds(of: pins)
            inArea = pins
        }
        guard inArea.count > limit else { return Layout(pins: inArea) }

        let longest = max(area.latitudeSpan, area.longitudeSpan, 1e-6)
        var cell = pow(2, (log2(longest / gridDivisions)).rounded(.down))
        var cells = group(inArea, cell: cell)
        // 升を倍にしていけば、いつかは `limit` 以下になる（世界が1升＝1つ）。念のため回数で止める
        var rounds = 0
        while cells.count > limit, rounds < 32 {
            cell *= 2
            cells = group(inArea, cell: cell)
            rounds += 1
        }

        var layout = Layout()
        for (key, members) in cells {
            if members.count == 1 {
                layout.pins.append(members[0])
                continue
            }
            let ordered = members.sorted {
                $0.photos.count != $1.photos.count ? $0.photos.count > $1.photos.count : $0.id < $1.id
            }
            // 束の位置は写真の枚数で重みを付けた中心（写真の多い撮影地に寄る）
            let weights = ordered.map { Double(max($0.photos.count, 1)) }
            let total = weights.reduce(0, +)
            let lat = zip(ordered, weights).reduce(0) { $0 + $1.0.coordinate.latitude * $1.1 } / total
            let lng = zip(ordered, weights).reduce(0) { $0 + $1.0.coordinate.longitude * $1.1 } / total
            layout.clusters.append(Cluster(id: "cluster:\(cell):\(key.0):\(key.1)",
                                           latitude: lat, longitude: lng, pins: ordered))
        }
        layout.pins.sort { $0.id < $1.id }
        layout.clusters.sort { $0.id < $1.id }
        return layout
    }

    /// 世界に固定した `cell` 度の升で分ける
    private static func group(_ pins: [MapPin], cell: Double) -> [(key: (Int, Int), members: [MapPin])] {
        var buckets: [String: (key: (Int, Int), members: [MapPin])] = [:]
        for pin in pins {
            let i = Int((pin.coordinate.latitude / cell).rounded(.down))
            let j = Int((pin.coordinate.longitude / cell).rounded(.down))
            buckets["\(i):\(j)", default: ((i, j), [])].members.append(pin)
        }
        return Array(buckets.values)
    }

    /// 全部のピンを囲む枠（まだ地図の枠が届いていないとき）
    private static func bounds(of pins: [MapPin]) -> MapFraming.Frame {
        let lats = pins.map(\.coordinate.latitude)
        let lngs = pins.map(\.coordinate.longitude)
        let (south, north) = (lats.min() ?? 0, lats.max() ?? 0)
        let (west, east) = (lngs.min() ?? 0, lngs.max() ?? 0)
        return MapFraming.Frame(latitude: (south + north) / 2, longitude: (west + east) / 2,
                                latitudeSpan: north - south, longitudeSpan: east - west)
    }
}
