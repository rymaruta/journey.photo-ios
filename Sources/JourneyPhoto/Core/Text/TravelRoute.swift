import Foundation

/// マイページの「旅の記録」に描く、**写真をつないだ線**の形（2026-10-14 owner「妥協なしでこだわりたい」・
/// 案 H1「星図」https://claude.ai/artifact/YR7SiY5op4gmCeQ8gxFhXZ）。
///
/// **距離（`TravelDistance.total`）と同じ写真・同じ順**でつなぐ。線の形と数字が食い違わないように、
/// 並べ方と選び方は `TravelDistance` のものをそのまま使う。地図は描かず、正距円筒（経度＝横・緯度＝縦）で
/// 線の通る範囲だけを枠いっぱいに広げる。
///
/// 画面の部品から切り離してあるのは、形をテストで見張るため（Linux では絵を描けない）
enum TravelRoute {

    /// 線を描くのに足りる点の数。これより少なければ線は出さない（距離も 0 になる）
    static let minimumPoints = 2
    /// 点が多いときに間引く上限。数百枚でも描く手間を増やさない（形はほとんど変わらない）
    static let maximumPoints = 240

    /// 距離と同じ写真を、同じ古い順に並べた撮影地（緯度・経度）
    static func coordinates(of photos: [Photo]) -> [Photo.Coords] {
        datedOldestFirst(photos).compactMap(\.coords)
    }

    /// 日時の読める写真を、Web と同じ古い順に（距離・線・最初の年が使う並び）
    static func datedOldestFirst(_ photos: [Photo]) -> [Photo] {
        TravelDistance.webOldestFirst(photos.filter { TripBook.day(of: $0, in: utc) != nil })
    }

    /// 経度を前の点から続くように直す（日付変更線をまたぐと 359° 飛んで見えるのを防ぐ）。
    /// 東京→ハワイは 139.7 → -157.8 ではなく 139.7 → 202.2 として描く
    static func unwrapped(_ points: [Photo.Coords]) -> [(lng: Double, lat: Double)] {
        var out: [(lng: Double, lat: Double)] = []
        out.reserveCapacity(points.count)
        for point in points {
            guard let previous = out.last else {
                out.append((point.lng, point.lat))
                continue
            }
            var lng = point.lng
            while lng - previous.lng > 180 { lng -= 360 }
            while lng - previous.lng < -180 { lng += 360 }
            out.append((lng, point.lat))
        }
        return out
    }

    /// 均等に間引く。**最初と最後の点は必ず残す**（一番古い・一番新しい写真）
    static func thinned<T>(_ points: [T], limit: Int = maximumPoints) -> [T] {
        guard points.count > limit, limit >= 2 else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { points[Int((Double($0) * step).rounded())] }
    }

    /// 枠の中に収めた線の形
    struct Shape: Equatable {
        /// 0〜1 に収めた点（x: 左→右、y: 上→下）。古い順
        let points: [CGPoint]
        /// 経度の格子（0〜1 の x）。30° ごと
        let meridians: [Double]
        /// 緯度の格子（0〜1 の y）。10° ごと
        let parallels: [Double]
    }

    /// 経度 30°・緯度 10° ごとに格子を引く
    static let meridianStep = 30.0
    static let parallelStep = 10.0
    /// 範囲がこれより狭いときは、この幅があるものとして真ん中に置く（同じ町の中だけの線が
    /// 枠いっぱいに引き伸ばされて、大旅行に見えないように）
    static let minimumSpanDegrees = 2.0

    /// 撮影地を枠に収める。点が足りなければ nil
    static func shape(of coordinates: [Photo.Coords]) -> Shape? {
        let points = thinned(unwrapped(coordinates))
        guard points.count >= minimumPoints else { return nil }
        let lngs = points.map(\.lng), lats = points.map(\.lat)
        let (minLng, maxLng) = padded(lngs.min()!, lngs.max()!)
        let (minLat, maxLat) = padded(lats.min()!, lats.max()!)
        let spanLng = maxLng - minLng, spanLat = maxLat - minLat
        let fitted = deduplicated(points.map { point in
            CGPoint(x: (point.lng - minLng) / spanLng, y: 1 - (point.lat - minLat) / spanLat)
        })
        // まとめた結果1点になる（同じ町の中だけ）なら、線は描かない
        guard fitted.count >= minimumPoints else { return nil }
        let meridians = stride(from: (minLng / meridianStep).rounded(.up) * meridianStep,
                               through: maxLng, by: meridianStep).map { ($0 - minLng) / spanLng }
        let parallels = stride(from: (minLat / parallelStep).rounded(.up) * parallelStep,
                               through: maxLat, by: parallelStep).map { 1 - ($0 - minLat) / spanLat }
        return Shape(points: fitted, meridians: meridians, parallels: parallels)
    }

    /// 枠の中でほとんど同じ所に続く点は1つにまとめる（同じ町で何枚も撮ると、点と線が重なって潰れる）。
    /// 一番新しい点は必ず残す
    static let mergeDistance = 0.012

    static func deduplicated(_ points: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for (index, point) in points.enumerated() {
            if let previous = out.last, hypot(point.x - previous.x, point.y - previous.y) < mergeDistance {
                if index == points.count - 1 { out[out.count - 1] = point }
                continue
            }
            out.append(point)
        }
        return out
    }

    /// 2点を結ぶ弧（2026-10-14 判断）。
    ///
    /// 🔴 run 437 は直線で、日本とヨーロッパの行き来が平行な線の束に潰れた。run 438 は上へだけ少し
    /// ふくらませたが、同じ2か所の行き来が同じ弧に重なり、まだ束だった。いま:
    /// - **行きは上へ・帰りは下へ**ふくらむ（東へ向かう区間は上、西へは下）。往復が目の形に開く
    /// - **同じ2か所を何度も行き来したら、回ごとに大きくふくらむ**（`occurrence`）
    /// - ふくらみは区間の長さに比例し、上下の余白に収める
    /// ふくらみが最大になる区間の長さ（枠の幅に対する割合）。これより短い区間は比例して低い
    static let arcFullLengthRatio = 0.6

    /// 曲げの点を、**画面の点の単位で**決める（枠は横長なので、0〜1 のままだとふくらみが縦に潰れる）。
    /// ふくらみの上限は上下の余白（`band`）の2倍（曲線の頂点は曲げの点の半分の高さに来るので、頂点が
    /// ちょうど余白に収まる）。同じ2か所の行き来は回ごとに 70% → 100% まで大きくする（run 440: 45% からでは往復が平らなまま）
    static func arcControl(from a: CGPoint, to b: CGPoint, occurrence: Int = 0,
                           size: CGSize, band: CGFloat) -> CGPoint {
        let w = Double(size.width), h = Double(size.height)
        guard w > 0, h > 0 else { return a }
        let ax = a.x * w, ay = a.y * h, bx = b.x * w, by = b.y * h
        let mx = (ax + bx) / 2, my = (ay + by) / 2
        let dx = bx - ax, dy = by - ay
        let length = hypot(dx, dy)
        guard length > 0 else { return CGPoint(x: mx / w, y: my / h) }
        // 区間に直角な2つの向きのうち、画面の上（y が小さい側）を指す方
        var upX = dy / length, upY = -dx / length
        if upY > 0 || (upY == 0 && upX > 0) { upX = -upX; upY = -upY }
        // 東へ進むなら上へ、西へなら下へ
        let sign: Double = dx >= 0 ? 1 : -1
        let base = min(1, length / (w * arcFullLengthRatio))
        let spread = 0.7 + 0.3 * Double(min(occurrence, 3)) / 3
        let lift = 2 * Double(band) * base * spread * sign
        return CGPoint(x: (mx + upX * lift) / w, y: (my + upY * lift) / h)
    }

    /// 区間ごとの曲げの点。同じ2か所（向きは問わない）を前に何回結んだかを数えて渡す
    static func arcControls(_ points: [CGPoint], size: CGSize, band: CGFloat) -> [CGPoint] {
        guard points.count >= 2 else { return [] }
        var seen: [(CGPoint, CGPoint)] = []
        var out: [CGPoint] = []
        let near = mergeDistance * 3
        func close(_ p: CGPoint, _ q: CGPoint) -> Bool { hypot(p.x - q.x, p.y - q.y) < near }
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            let occurrence = seen.filter { (close($0.0, a) && close($0.1, b)) || (close($0.0, b) && close($0.1, a)) }.count
            out.append(arcControl(from: a, to: b, occurrence: occurrence, size: size, band: band))
            seen.append((a, b))
        }
        return out
    }

    private static func padded(_ low: Double, _ high: Double) -> (Double, Double) {
        guard high - low < minimumSpanDegrees else { return (low, high) }
        let middle = (low + high) / 2
        return (middle - minimumSpanDegrees / 2, middle + minimumSpanDegrees / 2)
    }

    /// 一番古い写真の年（「2024 年から」）。読めなければ nil
    static func firstYear(of photos: [Photo]) -> Int? {
        firstYear(ofDatedOldestFirst: datedOldestFirst(photos))
    }

    /// `datedOldestFirst` で並べ済みの写真の、一番古い写真の年
    static func firstYear(ofDatedOldestFirst dated: [Photo]) -> Int? {
        guard let first = dated.first, let day = TripBook.day(of: first, in: utc) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.component(.year, from: day)
    }

    /// 訪れた国・地域の名前を**初めて訪れた順**に（数は `VisitedCountries.count` と同じ）
    static func countriesInOrder(_ photos: [Photo]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for photo in TravelDistance.webOldestFirst(photos) {
            guard let name = VisitedCountries.country(in: photo.location ?? ""), !seen.contains(name) else { continue }
            seen.insert(name)
            out.append(name)
        }
        return out
    }

    /// 名前の並びを1行に。3つまで、あとは「ほか N」
    ///
    /// **2026-10-24 判断（owner の要望）: 区切りは「/」**（「フランス/スペイン/イギリス」）。
    /// 「・」は「か国・地域」の「・」と並んで読みにくかった。英語も同じ「/」（「France/Spain/UK」）。
    /// 前後に空きを入れない（3つで1行に収まる幅を今と変えない・はみ出したら行の末尾を省く）。
    /// マイページと人のページは同じ部品（`TravelRecordSection` → `TravelRecordView`）なので、ここ1か所で両方が変わる
    static let countriesSeparator = "/"

    static func countriesLine(_ names: [String], limit: Int = 3) -> String {
        guard names.count > limit else { return names.joined(separator: countriesSeparator) }
        let shown = names.prefix(limit).joined(separator: countriesSeparator)
        return shown + L(" ほか\(names.count - limit)", " +\(names.count - limit)")
    }

    private static let utc = TimeZone(identifier: "UTC")!
}
