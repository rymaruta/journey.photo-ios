import Foundation

/// SNS 共有カード（`SignatureShareCardRenderer`）の地図の計算。
///
/// 描く処理（CoreGraphics）から切り出し、Linux でも枠の寸法・残す島・塗る県を試せるようにした。
/// 2026-11-04 判断（案A-3・owner 了承。見本は Artifact の `project/MapA3.dc.html`）:
/// - 枠を広げる（4:5 で 250×185 → 290×250）。上端は写真の裾が黒へ溶ける帯の 86% の所、
///   下端は区切り線の 9px 上。どちらも撮影者の段（rowY）から測るので、3つの比で同じ大きさになる
/// - 国の全体ではなく「撮った場所の島」と「一番大きい陸」から 60km 以内でつながる島だけを収める
/// - 日本の写真は、撮影地の文字の県を真鍮 75% で塗る
enum ShareCardMap {
    /// Natural Earth 由来の輪郭（国: `country-outlines.json`、県: `japan-prefectures.json`）。
    /// `r` は輪の並び、輪は `[経度, 緯度]` の並び。
    struct Shape: Decodable {
        let n: String
        let r: [[[Double]]]
    }

    struct Bounds: Equatable {
        var west: Double
        var east: Double
        var south: Double
        var north: Double

        init(west: Double, east: Double, south: Double, north: Double) {
            self.west = west; self.east = east; self.south = south; self.north = north
        }

        init?(_ rings: [[[Double]]]) {
            var west = Double.infinity, east = -Double.infinity
            var south = Double.infinity, north = -Double.infinity
            for ring in rings {
                for point in ring where point.count == 2 {
                    west = min(west, point[0]); east = max(east, point[0])
                    south = min(south, point[1]); north = max(north, point[1])
                }
            }
            guard west.isFinite, south.isFinite else { return nil }
            self.init(west: west, east: east, south: south, north: north)
        }

        func contains(longitude: Double, latitude: Double, margin: Double = 0) -> Bool {
            (west - margin...east + margin).contains(longitude)
                && (south - margin...north + margin).contains(latitude)
        }
    }

    // MARK: - 枠の寸法

    /// カードの下の段の位置。数は `SignatureShareCardRenderer.render` の描き方そのもの
    /// （描画とテストが同じ数を使う）。
    struct Layout {
        static let width: CGFloat = 1080
        static let margin: CGFloat = 48
        static let header: CGFloat = 118
        /// 写真の裾を黒へ溶かす帯（写真の下端から 195 上〜15 下）。止めの位置と濃さ
        static let fadeRise: CGFloat = 195
        static let fadeHeight: CGFloat = 210
        static let fadeStops: [(location: CGFloat, alpha: CGFloat)] = [(0, 0), (0.66, 0.86), (1, 1)]
        /// 地図の上端は、帯が 86% になる所より下（デザインシステムの「黒 78% 以上なら真鍮を置ける」より濃い側）
        static let mapTopAlpha: CGFloat = 0.86
        /// 地図の下端と区切り線の間（板の 9px）
        static let mapSeparatorGap: CGFloat = 9
        /// 撮影地の字（570 から）と地図の間
        static let placeX: CGFloat = 570
        static let placeWidthWithMap: CGFloat = 140
        static let placeWidthWithoutMap: CGFloat = 385
        static let mapGap: CGFloat = 12
        static let mapWidth: CGFloat = 290
        /// 撮影地の字の上端（rowY から）と、2行を描く枠の高さ（26pt × 1.35 × 2 行）。
        /// 3行の撮影地は 2026-11-04 の2行の決まりで無くなった
        static let placeTopFromRow: CGFloat = 22
        static let placeHeight: CGFloat = 26 * 1.35 * 2

        let height: CGFloat
        let footer: CGFloat

        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Layout.width / CGFloat(ratio.rawValue)
            // 9:16 だけ下の段を高くする（写真が縦に伸びすぎない）
            footer = ratio == .story ? 430 : 355
        }

        var photoBottom: CGFloat { height - footer + 8 }
        var photoRect: CGRect {
            CGRect(x: Layout.margin, y: Layout.header,
                   width: Layout.width - Layout.margin * 2, height: photoBottom - Layout.header)
        }
        var fadeRect: CGRect {
            CGRect(x: Layout.margin, y: photoBottom - Layout.fadeRise,
                   width: Layout.width - Layout.margin * 2, height: Layout.fadeHeight)
        }
        var rowY: CGFloat { height - footer + 37 }
        var separatorY: CGFloat { rowY + 174 }

        /// 帯の黒（`surface`）の濃さ。帯より上は 0、下は 1
        func fadeAlpha(atY y: CGFloat) -> CGFloat {
            let t = (y - fadeRect.minY) / fadeRect.height
            if t <= 0 { return 0 }
            if t >= 1 { return 1 }
            let stops = Layout.fadeStops
            for (a, b) in zip(stops, stops.dropFirst()) where t <= b.location {
                return a.alpha + (b.alpha - a.alpha) * (t - a.location) / (b.location - a.location)
            }
            return 1
        }

        /// 帯がその濃さになる最初の y
        func fadeY(reaching alpha: CGFloat) -> CGFloat {
            let stops = Layout.fadeStops
            for (a, b) in zip(stops, stops.dropFirst()) where alpha <= b.alpha {
                let t = a.location + (b.location - a.location) * (alpha - a.alpha) / (b.alpha - a.alpha)
                return fadeRect.minY + t * fadeRect.height
            }
            return fadeRect.maxY
        }

        /// 地図の枠。上は帯の 86% の所（整数に切り上げ）、下は区切り線の 9px 上。
        /// 横は撮影地の字（140 幅）の 12px 右から 290。
        var mapRect: CGRect {
            let top = fadeY(reaching: Layout.mapTopAlpha).rounded(.up)
            let bottom = separatorY - Layout.mapSeparatorGap
            return CGRect(x: Layout.placeX + Layout.placeWidthWithMap + Layout.mapGap, y: top,
                          width: Layout.mapWidth, height: bottom - top)
        }
    }

    // MARK: - 残す島

    /// 2つの島がこれより近ければ「つながっている」とみなす（owner 了承の 60km）
    static let islandGapKm: Double = 60

    /// 経度を撮った場所の側へそろえる。±180° をまたぐ国（ロシア・フィジー）が
    /// 360° 幅に伸びないよう、輪ごとに隣の頂点へつなげて開く。
    static func unwrap(_ rings: [[[Double]]], aroundLongitude pinLongitude: Double) -> [[[Double]]] {
        rings.map { ring -> [[Double]] in
            guard let first = ring.first, first.count == 2 else { return ring }
            var previous = first[0] + 360 * ((pinLongitude - first[0]) / 360).rounded()
            return ring.enumerated().map { index, point in
                guard point.count == 2 else { return point }
                if index == 0 { return [previous, point[1]] }
                let unwrapped = point[0] + 360 * ((previous - point[0]) / 360).rounded()
                previous = unwrapped
                return [unwrapped, point[1]]
            }
        }
    }

    /// 開いた輪の中に点があるか（偶奇の規則）
    static func ringContains(_ ring: [[Double]], longitude x: Double, latitude y: Double) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if a.count == 2, b.count == 2, (a[1] > y) != (b[1] > y),
               x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0] {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// 2点の距離（km）。60km を見分けるだけなので正距円筒の近似で足りる
    static func distanceKm(_ a: [Double], _ b: [Double]) -> Double {
        let latitude = (a[1] + b[1]) / 2 * .pi / 180
        let dx = (a[0] - b[0]) * cos(latitude) * 111.32
        let dy = (a[1] - b[1]) * 110.57
        return (dx * dx + dy * dy).squareRoot()
    }

    /// 面積（緯度で経度を縮めた平面の上で）
    private static func area(_ ring: [[Double]], longitudeScale: Double) -> Double {
        guard ring.count >= 3 else { return 0 }
        var sum = 0.0
        var j = ring.count - 1
        for i in ring.indices {
            sum += ring[j][0] * longitudeScale * ring[i][1] - ring[i][0] * longitudeScale * ring[j][1]
            j = i
        }
        return abs(sum) / 2
    }

    /// 地図に収める輪の番号。`rings` は `unwrap` 済み。
    ///
    /// 撮った場所を含む島（無ければいちばん近い島）と一番大きい陸から始め、
    /// 60km 以内の島を次々に足す。日本の本州で撮れば小笠原・沖ノ鳥島・南鳥島が外れ、
    /// 沖縄で撮れば沖縄が残る。フランスは海外県が、米国は（ハワイで撮らなければ）ハワイとアラスカが外れる。
    /// 重い総当たりはしない: 外接矩形を 60km 広げても重ならない輪は比べず、
    /// 比べるときも相手の矩形の近くの頂点だけを比べる。
    static func focusRingIndices(_ rings: [[[Double]]], latitude: Double, longitude: Double) -> [Int] {
        let usable = rings.indices.filter { rings[$0].count >= 3 }
        guard !usable.isEmpty else { return [] }
        let bounds = rings.map { Bounds([$0]) }
        var seeds = usable.filter { ringContains(rings[$0], longitude: longitude, latitude: latitude) }
        if seeds.isEmpty {
            let pin = [longitude, latitude]
            // 輪ごとに1回だけ測る（比べるたびに測り直さない・2026-11-04 確かめ役の指摘）
            var nearest: (index: Int, km: Double)?
            for index in usable {
                var best = Double.infinity
                for point in rings[index] where point.count == 2 {
                    best = min(best, distanceKm(point, pin))
                }
                if best < (nearest?.km ?? .infinity) { nearest = (index, best) }
            }
            if let nearest { seeds = [nearest.index] }
        }
        let longitudeScale = max(0.2, cos(latitude * .pi / 180))
        var largest: (index: Int, area: Double)?
        for index in usable {
            let size = area(rings[index], longitudeScale: longitudeScale)
            if size > (largest?.area ?? -1) { largest = (index, size) }
        }
        if let largest { seeds.append(largest.index) }
        var kept = Set(seeds)
        var queue = Array(kept)
        let latitudeMargin = islandGapKm / 110.57
        while let current = queue.popLast() {
            guard let a = bounds[current] else { continue }
            for index in usable where !kept.contains(index) {
                guard let b = bounds[index] else { continue }
                let widest = max(abs(a.south), abs(a.north), abs(b.south), abs(b.north))
                let longitudeMargin = islandGapKm / (111.32 * max(0.05, cos(widest * .pi / 180)))
                guard b.west <= a.east + longitudeMargin, b.east >= a.west - longitudeMargin,
                      b.south <= a.north + latitudeMargin, b.north >= a.south - latitudeMargin else { continue }
                if isNear(rings[current], rings[index], a, b,
                          longitudeMargin: longitudeMargin, latitudeMargin: latitudeMargin) {
                    kept.insert(index)
                    queue.append(index)
                }
            }
        }
        return kept.sorted()
    }

    private static func isNear(_ ringA: [[Double]], _ ringB: [[Double]], _ a: Bounds, _ b: Bounds,
                               longitudeMargin: Double, latitudeMargin: Double) -> Bool {
        // 湖や飛び地のような内側の輪は、外の輪から遠くても同じ陸として残す
        if let first = ringB.first, first.count == 2,
           ringContains(ringA, longitude: first[0], latitude: first[1]) { return true }
        if let first = ringA.first, first.count == 2,
           ringContains(ringB, longitude: first[0], latitude: first[1]) { return true }
        let nearA = ringA.filter { $0.count == 2
            && b.contains(longitude: $0[0], latitude: $0[1], margin: max(longitudeMargin, latitudeMargin)) }
        guard !nearA.isEmpty else { return false }
        let nearB = ringB.filter { $0.count == 2
            && a.contains(longitude: $0[0], latitude: $0[1], margin: max(longitudeMargin, latitudeMargin)) }
        for p in nearA {
            for q in nearB where distanceKm(p, q) < islandGapKm { return true }
        }
        return false
    }

    // MARK: - 収め方

    /// 収める範囲を枠に入れる縮尺と置き方（緯度で経度を縮めた正距円筒）
    struct Projection {
        let bounds: Bounds
        let rect: CGRect
        let longitudeScale: Double
        let scale: Double

        init(bounds: Bounds, rect: CGRect, inset: CGFloat = 8) {
            self.bounds = bounds
            self.rect = rect
            longitudeScale = max(0.2, cos(((bounds.south + bounds.north) / 2) * .pi / 180))
            let spanX = max((bounds.east - bounds.west) * longitudeScale, 0.01)
            let spanY = max(bounds.north - bounds.south, 0.01)
            scale = min(Double(rect.width - inset * 2) / spanX, Double(rect.height - inset * 2) / spanY)
        }

        func point(longitude: Double, latitude: Double) -> CGPoint {
            CGPoint(x: Double(rect.midX) + (longitude - (bounds.west + bounds.east) / 2) * longitudeScale * scale,
                    y: Double(rect.midY) - (latitude - (bounds.south + bounds.north) / 2) * scale)
        }
    }

    /// 国の輪郭を撮った場所に合わせて開き、収める輪と縮尺を決める
    static func focus(_ shape: Shape, latitude: Double, longitude: Double,
                      in rect: CGRect) -> (rings: [[[Double]]], projection: Projection)? {
        let rings = unwrap(shape.r, aroundLongitude: longitude)
        let kept = focusRingIndices(rings, latitude: latitude, longitude: longitude)
        guard let bounds = Bounds(kept.map { rings[$0] }) else { return nil }
        return (rings, Projection(bounds: bounds, rect: rect))
    }

    // MARK: - 塗る県

    /// 撮影地の文字（`LocationMatch.shareCardDisplay` の「千葉県（市原市）」など）から県を選ぶ。
    ///
    /// 2026-11-04 判断: 県は**カードに出す撮影地の文字**で決める。ピンは 0.5° に丸めた座標
    /// （`approximateShareCoordinate`）なので、県の境の近くでは隣の県に入る。丸める前の座標は
    /// SNS に出さない約束なので、描く側に渡さない。文字に 47 都道府県の名前がそのまま無ければ塗らない
    /// （「イヴリーヌ県」のような海外の県を拾わないよう、末尾の「県」では見ない）。
    static func prefectureName(in location: String?) -> String? {
        guard let location else { return nil }
        let separators = CharacterSet(charactersIn: "（）()、，,・ 　/")
        let parts = location.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let japanese = parts.first(where: { RegionList.prefectures.contains($0) }) { return japanese }
        // 英語の環境の撮影地（"Kyoto"・"Miyagi Prefecture"・"Hyōgo Prefecture"）。
        // 「,」で区切った欠片ごとに英語名の表で引く（2026-11-04 確かめ役の指摘）
        let pieces = location.components(separatedBy: CharacterSet(charactersIn: "（）()、，,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return pieces.lazy.compactMap { prefecture(english: $0) }.first
    }

    /// 英語の県名（JIS の順・RegionList.prefectures と同じ並び）
    static let englishPrefectures = [
        "Hokkaido", "Aomori", "Iwate", "Miyagi", "Akita", "Yamagata", "Fukushima",
        "Ibaraki", "Tochigi", "Gunma", "Saitama", "Chiba", "Tokyo", "Kanagawa",
        "Niigata", "Toyama", "Ishikawa", "Fukui", "Yamanashi", "Nagano", "Gifu",
        "Shizuoka", "Aichi", "Mie", "Shiga", "Kyoto", "Osaka", "Hyogo",
        "Nara", "Wakayama", "Tottori", "Shimane", "Okayama", "Hiroshima", "Yamaguchi",
        "Tokushima", "Kagawa", "Ehime", "Kochi", "Fukuoka", "Saga", "Nagasaki",
        "Kumamoto", "Oita", "Miyazaki", "Kagoshima", "Okinawa",
    ]

    /// 英語の県名 → 和文の県名。"Kyoto"・"Kyoto Prefecture"・"Hyōgo"・"Tokyo Metropolis" を受ける
    /// （長音の記号と大文字小文字は落として比べる）。それ以外は nil
    static func prefecture(english raw: String) -> String? {
        var name = raw.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespaces)
        for suffix in [" prefecture", " metropolis"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        guard let index = englishPrefectures.firstIndex(where: { $0.lowercased() == name }) else { return nil }
        return RegionList.prefectures[index]
    }

    /// 塗る県の形。文字と丸めた位置が食い違う（県の外接矩形から 1° 以上離れている）ときは塗らない
    static func prefectureShape(named name: String?, among prefectures: [Shape],
                                latitude: Double, longitude: Double) -> Shape? {
        guard let name, let shape = prefectures.first(where: { $0.n == name }),
              let bounds = Bounds(shape.r),
              bounds.contains(longitude: longitude, latitude: latitude, margin: 1) else { return nil }
        return shape
    }

    // MARK: - 同梱の輪郭

    static func loadShapes(resource: String, bundle: Bundle = .main) -> [Shape] {
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([Shape].self, from: data) else { return [] }
        return result
    }
}
