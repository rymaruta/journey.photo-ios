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

    /// カードの寸法。数は `SignatureShareCardRenderer.render` の描き方そのもの
    /// （描画とテストが同じ数を使う）。
    ///
    /// 2026-11-04 owner「地図8（整え版）を採用して、妥協なしでブラッシュアップ」。見本は Artifact
    /// 「SNS 共有カード 1.1.62」の `project/Map8.dc.html`（4:5・1080×1350）。決まり:
    /// - 外の余白 60・帯の中身は端から 48・額縁は 12 内側に 3px
    /// - 段の間隔（撮影者の段 → 区切り線 → 撮影情報）は 32 にそろえる。帯の下の余白は 38
    /// - 区切り線・縦線は 2px・真鍮 45% の1種類
    /// - 黒へ溶ける帯は、なだらかな曲線（smoothstep）で帯の開始位置にちょうど黒 100% になる
    ///   （以前は 15 下まで伸ばし、帯の開始位置で段が出ていた）
    /// - 撮影情報の3列の左端は、上の段（アバター・縦線の右・地図）の縦の線にそろえる
    struct Layout {
        static let width: CGFloat = 1080
        /// 写真と黒い帯の左右の余白（外の余白）
        static let margin: CGFloat = 60
        /// 帯の端から中身（アバター・区切り線・地図）まで
        static let contentInset: CGFloat = 48
        static var contentLeft: CGFloat { margin + contentInset }
        static var contentRight: CGFloat { width - margin - contentInset }
        /// 上の帯（ロゴと一文）の高さ。写真はこの下から始まる
        static let header: CGFloat = 100
        /// ロゴのマーク（45 角）の上端。字の中心はこのマークの中心にそろえる
        static let headerMarkY: CGFloat = 27
        static let headerMarkSize: CGFloat = 45
        /// 額縁（画像の端から内側へ）
        static let frameInset: CGFloat = 12
        static let frameWidth: CGFloat = 3
        /// 区切り線・縦線（1種類）
        static let lineWidth: CGFloat = 2
        static let lineAlpha: CGFloat = 0.45

        /// 写真の裾を黒へ溶かす帯の高さ。帯の開始位置（写真の下端）で黒 100%
        static let fadeHeight: CGFloat = 369
        /// 地図の上端は、帯がこの濃さになる所（見本の「黒 70%」）
        static let mapTopAlpha: CGFloat = 0.70
        /// なだらかな曲線（smoothstep）。始まりと終わりがゆるやかで、継ぎ目に線が出ない
        static func smoothstep(_ t: CGFloat) -> CGFloat {
            let c = min(1, max(0, t))
            return c * c * (3 - 2 * c)
        }
        static let fadeStops: [(location: CGFloat, alpha: CGFloat)] =
            (0...10).map { CGFloat($0) / 10 }.map { ($0, smoothstep($0)) }

        /// 黒い帯の上の余白（帯の開始 → 撮影者の段）。上は黒へ溶けているので近くてよい
        static let bandTopPad: CGFloat = 16
        static let avatarSize: CGFloat = 88
        /// 段の間隔（撮影者の段 → 区切り線 → 撮影情報）
        static let rowGap: CGFloat = 32
        static let infoHeight: CGFloat = 60

        /// 撮影者の名前の列（アバターの 24 右）。区切りの縦線はその 195 幅の 20 右
        static var nameX: CGFloat { contentLeft + avatarSize + 24 }
        static let nameColumnWidth: CGFloat = 195
        static var rowDividerX: CGFloat { nameX + nameColumnWidth + 20 }
        /// 撮影地の印（pin）と字
        static var pinX: CGFloat { rowDividerX + 24 }
        static var placeX: CGFloat { pinX + 50 }
        /// 地図の枠の幅。右端は本文の右端にそろえる
        static let mapWidth: CGFloat = 264
        static let mapGapToPlace: CGFloat = 8
        /// 地図の下端と撮影情報の上端の間（区切り線は地図の手前で止める）
        static let mapBottomGap: CGFloat = 8
        static let mapLineGap: CGFloat = 16
        static var mapX: CGFloat { contentRight - mapWidth }
        static var placeWidthWithMap: CGFloat { mapX - mapGapToPlace - placeX }
        static var placeWidthWithoutMap: CGFloat { contentRight - placeX }
        /// 撮影地の2行を描く枠の高さ（25pt × 1.35 × 2 行）
        static let placeFontSize: CGFloat = 25
        static let placeHeight: CGFloat = 25 * 1.35 * 2

        let height: CGFloat
        /// 写真の下端から画像の下端まで。9:16 だけ高い（下は Instagram の返信欄に隠れる）
        let footer: CGFloat

        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Layout.width / CGFloat(ratio.rawValue)
            footer = ratio == .story ? 403 : 328
        }

        var photoBottom: CGFloat { height - footer }
        var photoRect: CGRect {
            CGRect(x: Layout.margin, y: Layout.header,
                   width: Layout.width - Layout.margin * 2, height: photoBottom - Layout.header)
        }
        var bandRect: CGRect {
            CGRect(x: Layout.margin, y: photoBottom,
                   width: Layout.width - Layout.margin * 2, height: height - Layout.margin - photoBottom)
        }
        var fadeRect: CGRect {
            CGRect(x: Layout.margin, y: photoBottom - Layout.fadeHeight,
                   width: Layout.width - Layout.margin * 2, height: Layout.fadeHeight)
        }
        /// 撮影者の段の上端
        var rowTop: CGFloat { photoBottom + Layout.bandTopPad }
        var rowCenterY: CGFloat { rowTop + Layout.avatarSize / 2 }
        /// 区切り線の上端（線は 2px）
        var separatorY: CGFloat { rowTop + Layout.avatarSize + Layout.rowGap }
        /// 撮影情報の上端。区切り線（2px）の下も同じ 32
        var infoTop: CGFloat { separatorY + Layout.lineWidth + Layout.rowGap }
        var infoCenterY: CGFloat { infoTop + Layout.infoHeight / 2 }
        /// 区切り線の右端。地図があるときは地図の手前で止める
        func separatorEndX(hasMap: Bool) -> CGFloat {
            hasMap ? Layout.mapX - Layout.mapLineGap : Layout.contentRight
        }

        /// 帯の黒（`surface`）の濃さ。帯より上は 0、帯の開始位置で 1
        func fadeAlpha(atY y: CGFloat) -> CGFloat {
            Layout.smoothstep((y - fadeRect.minY) / fadeRect.height)
        }

        /// 帯がその濃さになる最初の y（smoothstep の逆を二分法で）
        func fadeY(reaching alpha: CGFloat) -> CGFloat {
            var low: CGFloat = 0, high: CGFloat = 1
            for _ in 0..<40 {
                let mid = (low + high) / 2
                if Layout.smoothstep(mid) < alpha { low = mid } else { high = mid }
            }
            return fadeRect.minY + high * fadeRect.height
        }

        /// 地図の枠。上は帯が 70% になる所（整数に切り上げ）、下は撮影情報の 8 上。
        /// 右端は本文の右端（972）にそろえる
        var mapRect: CGRect {
            let top = fadeY(reaching: Layout.mapTopAlpha).rounded(.up)
            let bottom = infoTop - Layout.mapBottomGap
            return CGRect(x: Layout.mapX, y: top, width: Layout.mapWidth, height: bottom - top)
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
