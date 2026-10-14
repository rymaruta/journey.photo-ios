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
        TravelDistance.webOldestFirst(photos.filter { TripBook.day(of: $0, in: utc) != nil })
            .compactMap(\.coords)
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
        let fitted = points.map { point in
            CGPoint(x: (point.lng - minLng) / spanLng, y: 1 - (point.lat - minLat) / spanLat)
        }
        let meridians = stride(from: (minLng / meridianStep).rounded(.up) * meridianStep,
                               through: maxLng, by: meridianStep).map { ($0 - minLng) / spanLng }
        let parallels = stride(from: (minLat / parallelStep).rounded(.up) * parallelStep,
                               through: maxLat, by: parallelStep).map { 1 - ($0 - minLat) / spanLat }
        return Shape(points: fitted, meridians: meridians, parallels: parallels)
    }

    private static func padded(_ low: Double, _ high: Double) -> (Double, Double) {
        guard high - low < minimumSpanDegrees else { return (low, high) }
        let middle = (low + high) / 2
        return (middle - minimumSpanDegrees / 2, middle + minimumSpanDegrees / 2)
    }

    /// 一番古い写真の年（「2024 年から」）。読めなければ nil
    static func firstYear(of photos: [Photo]) -> Int? {
        guard let first = TravelDistance.webOldestFirst(photos.filter { TripBook.day(of: $0, in: utc) != nil }).first,
              let day = TripBook.day(of: first, in: utc) else { return nil }
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
    static func countriesLine(_ names: [String], limit: Int = 3) -> String {
        guard names.count > limit else { return names.joined(separator: L("・", ", ")) }
        let shown = names.prefix(limit).joined(separator: L("・", ", "))
        return shown + L(" ほか\(names.count - limit)", " +\(names.count - limit)")
    }

    private static let utc = TimeZone(identifier: "UTC")!
}
