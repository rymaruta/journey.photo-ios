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
    static func frame(for points: [(latitude: Double, longitude: Double)]) -> Frame? {
        guard !points.isEmpty else { return nil }
        let cluster = largestCluster(points)
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

    /// いちばん点の多い塊。**同数なら北にある方**（毎回同じ結果にする）。
    static func largestCluster(
        _ points: [(latitude: Double, longitude: Double)]
    ) -> [(latitude: Double, longitude: Double)] {
        var clusters: [[(latitude: Double, longitude: Double)]] = []
        for point in points.sorted(by: { $0.latitude > $1.latitude }) {
            if let index = clusters.firstIndex(where: { cluster in
                cluster.contains { near($0, point) }
            }) {
                clusters[index].append(point)
            } else {
                clusters.append([point])
            }
        }
        return clusters.max { left, right in
            if left.count != right.count { return left.count < right.count }
            // 同数：北にある方を先に（`sorted` で北から入れているので後勝ちを避ける）
            return (left.first?.latitude ?? 0) < (right.first?.latitude ?? 0)
        } ?? []
    }

    private static func near(_ a: (latitude: Double, longitude: Double),
                             _ b: (latitude: Double, longitude: Double)) -> Bool {
        abs(a.latitude - b.latitude) <= clusterDegrees
            && abs(a.longitude - b.longitude) <= clusterDegrees
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
