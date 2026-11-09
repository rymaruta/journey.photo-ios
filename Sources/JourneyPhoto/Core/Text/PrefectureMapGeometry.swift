import Foundation

/// 行った県マップの**地図の形と当たり判定**（札 #503）。既存の `japan-prefectures.json`
/// （`ShareCardMap.Shape`・Natural Earth 由来・出典は `Tools/generate-japan-prefectures.py`）をそのまま使い、
/// 新しいデータは足さない。画面（SwiftUI）を持たない層なので、Linux の `swift test` で確かめられる。
///
/// 2026-11-08 判断:
/// - 座標は「本州側の幅を 1000」とする**単位の空間**に投影する（等緯度経度に cos(緯度) を掛けた図法）。
///   画面は幅に合わせて拡大するだけ。向きは北が上
/// - **沖縄は挿入図**: 沖縄県の輪を実際と同じ縮尺（1.0 倍）で、日本海の空いた左上へ置く。外枠（`inset`）は
///   描く側が細い線で囲む。実際の位置に置くと地図が南へ大きく伸び、本州〜九州が小さくなる。
///   左上に置いても本州・北海道の線に重ならないことは試験で縛る
/// - **北緯30度より南の他県の島は描かない**（小笠原・南鳥島・奄美・トカラ。東京都・鹿児島県の一部）。
///   描くと地図の南が4度ぶん伸びて本土が縮む。県の札・一覧からは今までどおり選べる（差の一覧に入れる）
/// - 当たり判定: ①線の内側 ②外側でも近い県（`tolerance` 以内）③挿入図の枠の中は沖縄県。
///   小さな県を指で押しやすくするため、②で最も近い県を採る
struct PrefectureMapGeometry {

    struct Piece {
        let prefecture: String
        /// 輪（単位の空間の点）。島ごとに1つ
        let polygons: [[CGPoint]]
        let bounds: CGRect
        /// 文字・数字を置く点（いちばん大きい輪の重心）
        let anchor: CGPoint
        /// 挿入図の中か（沖縄県）
        let inInset: Bool
    }

    /// 県の並びは `RegionList.prefectures`（北から・JIS の順）。読み込めなかった県は含まない
    let pieces: [Piece]
    /// 単位の空間の大きさ（幅 1000）
    let size: CGSize
    /// 沖縄の挿入図の枠。無ければ nil
    let inset: CGRect?
    /// 本州側の投影（緯度経度 → 単位の空間）。ピンや試験で使う。**挿入図の中の沖縄には使えない**
    let projection: Projection

    struct Projection: Equatable {
        let west: Double
        let north: Double
        let cosMid: Double
        let scale: Double

        func point(latitude: Double, longitude: Double) -> CGPoint {
            CGPoint(x: (longitude - west) * cosMid * scale, y: (north - latitude) * scale)
        }
    }

    nonisolated static let width: CGFloat = 1000
    /// この緯度より南の輪は、沖縄県以外は描かない
    nonisolated static let mainLatitudeFloor = 30.0
    nonisolated static let insetPadding: CGFloat = 16
    nonisolated static let insetPrefecture = "沖縄県"

    func piece(_ prefecture: String) -> Piece? { pieces.first { $0.prefecture == prefecture } }

    // MARK: - 作る

    static func build(shapes: [ShareCardMap.Shape]) -> PrefectureMapGeometry? {
        let known = Set(RegionList.prefectures)
        func meanLatitude(_ ring: [[Double]]) -> Double {
            let lats = ring.filter { $0.count == 2 }.map { $0[1] }
            return lats.isEmpty ? 0 : lats.reduce(0, +) / Double(lats.count)
        }
        // 本州側の輪（沖縄県以外・北緯30度以北）と、沖縄県の輪
        var main: [(name: String, rings: [[[Double]]])] = []
        var okinawa: [[[Double]]] = []
        for shape in shapes where known.contains(shape.n) {
            if shape.n == insetPrefecture {
                okinawa = shape.r.filter { $0.count >= 3 }
                continue
            }
            let kept = shape.r.filter { $0.count >= 3 && meanLatitude($0) >= mainLatitudeFloor }
            if !kept.isEmpty { main.append((shape.n, kept)) }
        }
        guard let mainBounds = ShareCardMap.Bounds(main.flatMap { $0.rings }) else { return nil }

        let cosMid = max(0.2, cos(((mainBounds.south + mainBounds.north) / 2) * .pi / 180))
        let k = Double(width) / max((mainBounds.east - mainBounds.west) * cosMid, 0.01)
        func mainPoint(_ p: [Double]) -> CGPoint {
            CGPoint(x: (p[0] - mainBounds.west) * cosMid * k, y: (mainBounds.north - p[1]) * k)
        }
        let height = CGFloat((mainBounds.north - mainBounds.south) * k)

        var built: [String: Piece] = [:]
        for entry in main {
            let polygons = entry.rings.map { ring in ring.filter { $0.count == 2 }.map(mainPoint) }
            if let piece = makePiece(entry.name, polygons, inInset: false) { built[entry.name] = piece }
        }

        var insetFrame: CGRect?
        if let okBounds = ShareCardMap.Bounds(okinawa) {
            let okCos = max(0.2, cos(((okBounds.south + okBounds.north) / 2) * .pi / 180))
            let pad = Double(insetPadding)
            func insetPoint(_ p: [Double]) -> CGPoint {
                CGPoint(x: pad + (p[0] - okBounds.west) * okCos * k, y: pad + (okBounds.north - p[1]) * k)
            }
            let polygons = okinawa.map { ring in ring.filter { $0.count == 2 }.map(insetPoint) }
            if let piece = makePiece(insetPrefecture, polygons, inInset: true) {
                built[insetPrefecture] = piece
                insetFrame = CGRect(x: 0, y: 0,
                                    width: (okBounds.east - okBounds.west) * okCos * k + pad * 2,
                                    height: (okBounds.north - okBounds.south) * k + pad * 2)
            }
        }
        let pieces = RegionList.prefectures.compactMap { built[$0] }
        guard !pieces.isEmpty else { return nil }
        return PrefectureMapGeometry(
            pieces: pieces, size: CGSize(width: width, height: height), inset: insetFrame,
            projection: Projection(west: mainBounds.west, north: mainBounds.north, cosMid: cosMid, scale: k))
    }

    private static func makePiece(_ name: String, _ polygons: [[CGPoint]], inInset: Bool) -> Piece? {
        let polygons = polygons.filter { $0.count >= 3 }
        guard !polygons.isEmpty else { return nil }
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for polygon in polygons {
            for p in polygon {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        let largest = polygons.max { abs(signedArea($0)) < abs(signedArea($1)) } ?? polygons[0]
        return Piece(prefecture: name, polygons: polygons,
                     bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                     anchor: centroid(largest), inInset: inInset)
    }

    // MARK: - 図形の計算

    static func signedArea(_ polygon: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    static func centroid(_ polygon: [CGPoint]) -> CGPoint {
        let area = signedArea(polygon)
        if abs(area) < 0.0001 {
            let n = CGFloat(max(polygon.count, 1))
            return CGPoint(x: polygon.map(\.x).reduce(0, +) / n, y: polygon.map(\.y).reduce(0, +) / n)
        }
        var cx: CGFloat = 0, cy: CGFloat = 0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let cross = a.x * b.y - b.x * a.y
            cx += (a.x + b.x) * cross
            cy += (a.y + b.y) * cross
        }
        return CGPoint(x: cx / (6 * area), y: cy / (6 * area))
    }

    /// 線の内側か（偶奇の規則）
    static func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        var t: CGFloat = 0
        if lengthSquared > 0 { t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared)) }
        let nx = a.x + t * dx, ny = a.y + t * dy
        let ex = p.x - nx, ey = p.y - ny
        return (ex * ex + ey * ey).squareRoot()
    }

    /// 県の形までの距離（内側なら 0）
    func distance(from p: CGPoint, to piece: Piece) -> CGFloat {
        var best = CGFloat.infinity
        for polygon in piece.polygons {
            if Self.contains(polygon, p) { return 0 }
            for i in polygon.indices {
                best = min(best, Self.distance(from: p, toSegment: polygon[i], polygon[(i + 1) % polygon.count]))
            }
        }
        return best
    }

    // MARK: - 当たり判定

    /// 押した点（単位の空間）にある県。①内側 ②`tolerance` 以内でいちばん近い県 ③挿入図の枠の中なら沖縄県
    func prefecture(at p: CGPoint, tolerance: CGFloat) -> String? {
        for piece in pieces where piece.bounds.contains(p) {
            if piece.polygons.contains(where: { Self.contains($0, p) }) { return piece.prefecture }
        }
        var best: (distance: CGFloat, name: String)?
        for piece in pieces where piece.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p) {
            let d = distance(from: p, to: piece)
            if d <= tolerance, best == nil || d < best!.distance { best = (d, piece.prefecture) }
        }
        if let best { return best.name }
        if let inset, inset.contains(p), piece(Self.insetPrefecture) != nil { return Self.insetPrefecture }
        return nil
    }

    /// 押した点に近い県（押した県を除く・近い順・`count` 件）。**押し間違えた隣を直すための札**に使う。
    /// 挿入図の沖縄県は本土と位置が比べられないので、どちら側でも入れない（沖縄県を押したときは空）
    func nearby(to p: CGPoint, excluding prefecture: String?, count: Int = 3) -> [String] {
        if let prefecture, piece(prefecture)?.inInset == true { return [] }
        let ranked = pieces
            .filter { !$0.inInset && $0.prefecture != prefecture }
            .map { (name: $0.prefecture, distance: distance(from: p, to: $0)) }
            .sorted { $0.distance != $1.distance ? $0.distance < $1.distance : indexOf($0.name) < indexOf($1.name) }
        return ranked.prefix(count).map(\.name)
    }

    private func indexOf(_ name: String) -> Int { RegionList.prefectures.firstIndex(of: name) ?? Int.max }
}

/// 地方ごとのまとまり（県の一覧・「関東 5/7」）。`RegionList.prefectures` の並びの区切り
enum PrefectureRegions {

    struct Region: Equatable {
        let name: String
        let range: Range<Int>

        var prefectures: [String] { Array(RegionList.prefectures[range]) }
    }

    static let all: [Region] = [
        Region(name: "北海道", range: 0..<1),
        Region(name: "東北", range: 1..<7),
        Region(name: "関東", range: 7..<14),
        Region(name: "中部", range: 14..<23),
        Region(name: "近畿", range: 23..<30),
        Region(name: "中国", range: 30..<35),
        Region(name: "四国", range: 35..<39),
        Region(name: "九州・沖縄", range: 39..<47),
    ]

    /// 地方の英語名（`L` の第2引数）
    static func englishName(_ region: Region) -> String {
        switch region.name {
        case "北海道": return "Hokkaido"
        case "東北": return "Tohoku"
        case "関東": return "Kanto"
        case "中部": return "Chubu"
        case "近畿": return "Kinki"
        case "中国": return "Chugoku"
        case "四国": return "Shikoku"
        default: return "Kyushu & Okinawa"
        }
    }

    /// 県の地方
    static func region(of prefecture: String) -> Region? {
        guard let index = RegionList.prefectures.firstIndex(of: prefecture) else { return nil }
        return all.first { $0.range.contains(index) }
    }
}

/// 色の段（提案書 第2版・板「黒塗りの真鍮」）。
/// **2026-11-09 owner 判断: 模様（点・線・格子）はやめ、色だけで分ける。** 0 回・1 回・2 回・3 回以上の4段（owner 判断 2026-11-09）。1〜3 回以上は真鍮の濃淡で、
/// 明るさの差を大きく取る（色覚が違っても明るさで分かる）。色だけに頼らない保険は、拡大時の数字と読み上げ
/// （「東京都、3 回」）。凡例の見本も地図の塗りも、この表（`fills`）だけを読む（写しを作らない）
enum VisitedMapStyle {

    /// 段（`VisitedPrefectures.level(forCount:)`）→ 塗りの色（0xRRGGBB）。0 は塗らない。
    /// 1 回 #7F6230・2 回 #B08C52・3 回以上 #F3DCA6（owner 承認 2026-11-08 の明るい端）。
    /// 黒地に対する相対輝度比は 3.69 / 6.72 / 15.60、隣り合う段の比は 1.82 / 2.32
    /// （`VisitedMapStyle.contrastOnBlack` `adjacentRatio`・テストが見張る）。板の使い道の外の色
    nonisolated static let fills: [UInt32?] = [nil, 0x7F6230, 0xB08C52, BrandPalette.accentHighlight]
    /// 未の県の地（板の surface-3）。無地
    nonisolated static let baseFill: UInt32 = BrandPalette.surface3

    /// 塗る段（1 以上）の色だけを段の順に。比のテストと、凡例・地図が同じ表を使う確かめに使う
    static var paintedFills: [UInt32] { fills.compactMap { $0 } }

    /// 黒地（地図の背景・県の縁）に対する比
    static func contrastOnBlack(_ hex: UInt32) -> Double {
        BrandPalette.contrast(hex, BrandPalette.background)
    }

    /// 隣り合う段（lower → higher）の相対輝度比。1 以上
    static func adjacentRatio(_ lower: UInt32, _ higher: UInt32) -> Double {
        BrandPalette.contrast(lower, higher)
    }

    /// 2つの色（0xRRGGBB）を割合 t（0〜1）で混ぜる。色の切り替え（0.15 秒）と祝いの明るさに使う
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        let t = min(max(t, 0), 1)
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded())
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    /// 段の塗り（未は地の色）
    static func fill(forLevel level: Int) -> UInt32 {
        let index = min(max(level, 0), fills.count - 1)
        return fills[index] ?? baseFill
    }
}
