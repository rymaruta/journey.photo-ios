import Foundation

/// 地図の初期表示をどこに合わせるか。
///
/// **世界全体を出さない**（指示書 9-2）。既定のままだと日本とヨーロッパの
/// ピンを同時に収めようとして地球儀の縮尺になり、**1枚ずつの写真が
/// 探せない**。
///
/// **いちばん写真の多い塊に寄せる。** 全部を収める枠は「全部見える」が
/// 「何も見えない」のと同じ。旅の写真は地理的に固まるので、
/// **塊ごとに分けてから、いちばん大きい塊に合わせる**。
///
/// 画面を持たない層に置いてある（`MapKit` を読まない）ので、
/// Linux 上の `swift test` で検証できる。
enum MapFraming {

    /// 同じ塊と見なす距離（度）。**約 300km**
    /// （緯度1度 ≒ 111km。旅1回ぶんの移動はだいたいこの中に収まる）
    static let clusterDegrees = 2.7

    /// 表示する枠。中心と、緯度経度それぞれの幅（度）。
    struct Frame: Equatable {
        let latitude: Double
        let longitude: Double
        let latitudeSpan: Double
        let longitudeSpan: Double
    }

    /// 余白。**枠ぴったりだと端のピンが画面の縁に貼り付く**
    static let padding = 1.4
    /// いちばん狭いときの幅（度）。1点しか無いときに地面まで寄りすぎない
    static let minimumSpan = 0.08

    /// 点が無ければ nil（呼ぶ側は地図の既定に任せる）。
    ///
    /// - Parameter weights: 点ごとの重み（ピンに載っている写真の枚数）。省けば1点1つ。
    ///   **ピンは座標を丸めた1地点ごとなので、数えるのは写真の枚数**——東京の1地点に40枚、
    ///   パリの2地点に1枚ずつなら東京に寄る（ピンの数で数えるとパリに寄っていた）
    static func frame(for points: [(latitude: Double, longitude: Double)],
                      weights: [Int]? = nil) -> Frame? {
        guard !points.isEmpty else { return nil }
        let cluster = largestCluster(points, weights: weights)
        let latitudes = cluster.map(\.latitude)
        let longitudes = cluster.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return nil }
        return Frame(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2,
            latitudeSpan: max(minimumSpan, (maxLat - minLat) * padding),
            longitudeSpan: max(minimumSpan, (maxLon - minLon) * padding)
        )
    }

    /// いちばん重い（写真の多い）塊。**同じ重さなら北にある方**（毎回同じ結果にする）。
    ///
    /// 写真を約 30km の小さな升にまとめ、その升（の重みの中心）を中心の候補にして、**そこから
    /// `clusterDegrees`（約 300km）以内の写真の重さがいちばん大きい所**を選び、その範囲の点を
    /// 塊とする。塊の広さは中心から ±300km に収まる。
    /// - 🔴 北から順に「最初に近い塊」へ足す形は、一続きの点が割れて小さい塊が選ばれた
    /// - つながりをたどる形は、点が密だと大陸ごと1つになり、点の数の2乗の時間がかかった
    /// - 升目の 3×3 をそのまま囲む形は、離れた1枚が枠を決めた。重みの中心で切る形は、中心が
    ///   2つの群の間に落ちると、間にある1枚だけに寄った
    /// - 写真の1地点ずつを候補にする形は、1つの升に写真が集まると2乗の時間になった
    ///   （同じ升に 20000 枚で約 100 秒）。小さな升にまとめれば、候補も見る先も升の数で抑えられる
    ///   （1つの 300km の升の中の小さな升は多くて 100）
    static func largestCluster(
        _ points: [(latitude: Double, longitude: Double)],
        weights: [Int]? = nil
    ) -> [(latitude: Double, longitude: Double)] {
        struct Cell: Hashable { let lat: Int; let lon: Int }
        struct Bin { var weight = 0; var latSum = 0.0; var lonSum = 0.0; var members: [Int] = []
            var latitude: Double { latSum / Double(weight) }
            var longitude: Double { lonSum / Double(weight) }
        }
        let fine = clusterDegrees / 10
        func fineCell(_ p: (latitude: Double, longitude: Double)) -> Cell {
            Cell(lat: Int((p.latitude / fine).rounded(.down)), lon: Int((p.longitude / fine).rounded(.down)))
        }
        func coarse(_ c: Cell) -> Cell {
            Cell(lat: Int((Double(c.lat) / 10).rounded(.down)), lon: Int((Double(c.lon) / 10).rounded(.down)))
        }
        func weight(_ index: Int) -> Int {
            (weights?.indices.contains(index) ?? false) ? max(1, weights![index]) : 1
        }
        var bins: [Cell: Bin] = [:]
        for index in points.indices {
            let w = weight(index)
            let key = fineCell(points[index])
            bins[key, default: Bin()].weight += w
            bins[key]!.latSum += points[index].latitude * Double(w)
            bins[key]!.lonSum += points[index].longitude * Double(w)
            bins[key]!.members.append(index)
        }
        var byCoarse: [Cell: [Cell]] = [:]
        for key in bins.keys { byCoarse[coarse(key), default: []].append(key) }
        func nearby(_ center: (latitude: Double, longitude: Double), home: Cell) -> [Cell] {
            let c = coarse(home)
            return (-1...1).flatMap { dLat in (-1...1).flatMap { dLon in
                byCoarse[Cell(lat: c.lat + dLat, lon: c.lon + dLon)] ?? []
            } }.filter {
                abs(bins[$0]!.latitude - center.latitude) <= clusterDegrees
                    && abs(bins[$0]!.longitude - center.longitude) <= clusterDegrees
            }
        }
        var best: (key: Cell, center: (latitude: Double, longitude: Double), weight: Int)?
        for (key, bin) in bins {
            let center = (latitude: bin.latitude, longitude: bin.longitude)
            let total = nearby(center, home: key).reduce(0) { $0 + bins[$1]!.weight }
            guard let current = best else { best = (key, center, total); continue }
            // 重い方。同じなら北、それも同じなら西（辞書の並びに依らず毎回同じ結果にする）
            if total > current.weight
                || (total == current.weight && (center.latitude > current.center.latitude
                    || (center.latitude == current.center.latitude && center.longitude < current.center.longitude))) {
                best = (key, center, total)
            }
        }
        guard let best else { return [] }
        return nearby(best.center, home: best.key)
            .flatMap { bins[$0]!.members }
            .sorted { points[$0].latitude > points[$1].latitude }
            .map { points[$0] }
    }
}

extension MapFraming {
    /// 拡大・縮小の1段（モック3-4 の `+` / `−`）。
    ///
    /// **倍率は2倍ずつ。** 細かく刻むと何度も押すことになり、
    /// 大きく刻むと行き過ぎる。
    ///
    /// **上限と下限で止める。** 止めないと、押し続けたときに
    /// 地球儀（span 180）や1点（span 0）になって**戻れなくなる**。
    static func zoomed(_ frame: Frame, by factor: Double) -> Frame {
        let lat = min(maxSpan, max(minSpan, frame.latitudeSpan * factor))
        let lng = min(maxSpan, max(minSpan, frame.longitudeSpan * factor))
        return Frame(latitude: frame.latitude, longitude: frame.longitude,
                     latitudeSpan: lat, longitudeSpan: lng)
    }

    /// いちばん寄れるところ。**約100m**——座標は約1kmに丸めてあるので、
    /// これ以上寄ってもピンは動かない
    static let minSpan = 0.001
    /// いちばん引けるところ（地球儀にしない）
    static let maxSpan = 90.0
    /// 1回ぶんの倍率
    static let zoomStep = 2.0

    /// 拡大・縮小を**続けて押したとき**の土台。
    ///
    /// 見えている枠は地図が落ち着いたとき（`onMapCameraChange(.onEnd)`）に
    /// しか届かない。届く前に次を押すと、**古い枠から計算し直す**ので:
    ///
    ///     ＋ ＋   → 2回押したのに1段しか寄らない
    ///     ＋ −   → 元の枠の2倍（押す前より引いた所）へ飛ぶ＝逆に見える
    ///
    /// だから**直前に押してから `window` 秒のあいだは、前に頼んだ枠を土台に
    /// する**。それを過ぎたら見えている枠に戻る（指で動かした地図に従う）。
    struct ZoomChain {
        static let window: TimeInterval = 1.0
        private var last: (frame: Frame, at: Date)?

        init() {}

        mutating func step(from visible: Frame?, by factor: Double,
                           now: Date = Date()) -> Frame? {
            let base: Frame?
            if let last, now.timeIntervalSince(last.at) < Self.window {
                base = last.frame
            } else {
                base = visible
            }
            guard let base else { return nil }
            let next = MapFraming.zoomed(base, by: factor)
            last = (next, now)
            return next
        }

        /// 地図が落ち着いたとき。**頼んだ枠から中心が離れていたら忘れる**
        /// ——指で払った・現在地へ寄せたなど、ボタン以外で動いた印。
        /// 忘れないと、1秒以内の次の＋−で払う前の場所へ引き戻す
        mutating func observe(_ visible: Frame) {
            guard let last else { return }
            let latDrift = abs(visible.latitude - last.frame.latitude)
            let lngDrift = abs(visible.longitude - last.frame.longitude)
            if latDrift > last.frame.latitudeSpan * Self.driftTolerance
                || lngDrift > last.frame.longitudeSpan * Self.driftTolerance {
                self.last = nil
            }
        }

        /// ボタン以外がカメラを動かしたとき（絞り込み・現在地）
        mutating func reset() { last = nil }

        /// 中心のずれをどこまで「同じ枠」と見なすか（幅に対する割合）
        static let driftTolerance = 0.25
    }
}
