import Foundation

// 写真で作るキャンピングカーの「形」を計算する層（2026-10-18・札 #307・板「写真で作るキャンピングカー」）。
//
// **SceneKit を読まない素の Swift。** 点・多角形・三角形の網（メッシュ）をここで作り、Linux でも型検査と
// 試験が走る（面の数・閉じているか・穴の扱い）。SceneKit の側（`CamperSceneView`）はこの網をそのまま
// `SCNGeometry` に写すだけ。
//
// 単位は板の単位（車体の長さ 242）。**上が +Y・地面が 0**（板は下が +y なので `Y = 62 - y` で写す）。
// 手前（板の近い側）が +Z、車の前が +X。

/// 3次元の点・向き
struct CV3: Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static let zero = CV3(0, 0, 0)
    static let up = CV3(0, 1, 0)

    static func + (a: CV3, b: CV3) -> CV3 { CV3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: CV3, b: CV3) -> CV3 { CV3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: CV3, k: Double) -> CV3 { CV3(a.x * k, a.y * k, a.z * k) }
    static prefix func - (a: CV3) -> CV3 { CV3(-a.x, -a.y, -a.z) }

    func dot(_ b: CV3) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: CV3) -> CV3 { CV3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var length: Double { (x * x + y * y + z * z).squareRoot() }
    var normalized: CV3 {
        let l = length
        return l > 1e-12 ? self * (1 / l) : CV3(0, 1, 0)
    }
}

/// 平面の点（輪郭）
struct CV2: Equatable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static func + (a: CV2, b: CV2) -> CV2 { CV2(a.x + b.x, a.y + b.y) }
    static func - (a: CV2, b: CV2) -> CV2 { CV2(a.x - b.x, a.y - b.y) }
    static func * (a: CV2, k: Double) -> CV2 { CV2(a.x * k, a.y * k) }
    func cross(_ b: CV2) -> Double { x * b.y - y * b.x }
    var length: Double { (x * x + y * y).squareRoot() }
}

/// 向き（四元数）。部品を回して置くのに使う（SceneKit の `orientation` にそのまま渡す）
struct CQuat: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double
    var w: Double

    static let identity = CQuat(x: 0, y: 0, z: 0, w: 1)

    /// 軸のまわりに角度（ラジアン）だけ回す
    static func axisAngle(_ axis: CV3, _ angle: Double) -> CQuat {
        let a = axis.normalized
        let s = sin(angle / 2)
        return CQuat(x: a.x * s, y: a.y * s, z: a.z * s, w: cos(angle / 2))
    }

    /// +Y を `dir` へ向ける回転（旋盤で作った部品の軸を向ける）
    static func yTo(_ dir: CV3) -> CQuat {
        let d = dir.normalized
        let c = CV3.up.dot(d)
        if c > 0.999_999 { return .identity }
        if c < -0.999_999 { return axisAngle(CV3(1, 0, 0), .pi) }
        return axisAngle(CV3.up.cross(d), acos(max(-1, min(1, c))))
    }

    /// 向き `a` を向き `b` へ回す
    static func rotation(from a: CV3, to b: CV3) -> CQuat {
        let u = a.normalized, v = b.normalized
        let c = u.dot(v)
        if c > 0.999_999 { return .identity }
        if c < -0.999_999 {
            let side = abs(u.x) < 0.9 ? CV3(1, 0, 0) : CV3(0, 1, 0)
            return axisAngle(u.cross(side), .pi)
        }
        return axisAngle(u.cross(v), acos(max(-1, min(1, c))))
    }

    /// 先に `b`、次に `self` を回す
    static func * (a: CQuat, b: CQuat) -> CQuat {
        CQuat(x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
              y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
              z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
              w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
    }

    func rotate(_ v: CV3) -> CV3 {
        let u = CV3(x, y, z)
        let t = u.cross(v) * 2
        return v + t * w + u.cross(t)
    }
}

// MARK: - 多角形

enum CamperPolygon {

    /// 符号つきの面積（反時計回りが正。上が +Y）
    static func signedArea(_ p: [CV2]) -> Double {
        guard p.count > 2 else { return 0 }
        var s = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    static func ccw(_ p: [CV2]) -> [CV2] { signedArea(p) < 0 ? p.reversed() : p }
    static func cw(_ p: [CV2]) -> [CV2] { signedArea(p) > 0 ? p.reversed() : p }

    /// 重なった点（続けて同じ位置）を落とす
    static func deduped(_ p: [CV2], epsilon: Double = 1e-6) -> [CV2] {
        var out: [CV2] = []
        for q in p where out.last.map({ ($0 - q).length > epsilon }) ?? true { out.append(q) }
        if out.count > 1, let first = out.first, let last = out.last, (first - last).length <= epsilon { out.removeLast() }
        return out
    }

    /// 重なった点と、一直線に並んだ点（まっすぐ続く点も、行って戻るとげも）を落とす
    static func cleaned(_ p: [CV2], epsilon: Double = 1e-7) -> [CV2] {
        var pts = deduped(p)
        var changed = true
        while changed, pts.count > 3 {
            changed = false
            for i in pts.indices {
                let a = pts[(i - 1 + pts.count) % pts.count], b = pts[i], c = pts[(i + 1) % pts.count]
                let e1 = b - a, e2 = c - b
                if abs(e1.cross(e2)) <= epsilon * max(1, e1.length * e2.length) {
                    pts.remove(at: i)
                    pts = deduped(pts)
                    changed = true
                    break
                }
            }
        }
        return pts
    }

    /// 角を丸める（板 r3.js の `rounded` と同じ二次曲線。角ごとに `seg + 1` 点）。
    /// `tags` は辺の名前（点 i から次の点への辺）。丸めた点の辺の名前は板と同じ決まりで割り振る
    static func rounded(_ corners: [(p: CV2, r: Double, tag: String)], seg: Int = 3) -> (points: [CV2], tags: [String]) {
        var points: [CV2] = []
        var tags: [String] = []
        let n = corners.count
        for i in 0..<n {
            let v = corners[i], prev = corners[(i - 1 + n) % n], next = corners[(i + 1) % n]
            if v.r <= 0 {
                points.append(v.p)
                tags.append(v.tag)
                continue
            }
            let d1 = (v.p - prev.p).length, d2 = (next.p - v.p).length
            let t1 = min(v.r, d1 / 2), t2 = min(v.r, d2 / 2)
            let a = v.p - (v.p - prev.p) * (t1 / max(d1, 1e-9))
            let b = v.p + (next.p - v.p) * (t2 / max(d2, 1e-9))
            for k in 0...seg {
                let t = Double(k) / Double(seg)
                let q = a * ((1 - t) * (1 - t)) + v.p * (2 * (1 - t) * t) + b * (t * t)
                points.append(q)
                // 板: 角の前半は前の辺の名前、後半はこの角から出る辺の名前
                tags.append(k < seg - 1 ? prev.tag : v.tag)
            }
        }
        return (points, tags)
    }

    /// 角の丸い四角（左下 x・y、幅・高さ、角の半径。上が +Y）
    static func roundedRect(x: Double, y: Double, w: Double, h: Double, r: Double, seg: Int = 2) -> [CV2] {
        rounded([(CV2(x, y), r, ""), (CV2(x + w, y), r, ""), (CV2(x + w, y + h), r, ""), (CV2(x, y + h), r, "")],
                seg: seg).points
    }

    /// 円（反時計回り）
    static func circle(_ c: CV2, _ r: Double, count: Int = 24, start: Double = 0) -> [CV2] {
        (0..<count).map { k in
            let t = start + Double(k) / Double(count) * 2 * .pi
            return CV2(c.x + cos(t) * r, c.y + sin(t) * r)
        }
    }

    /// 輪郭を外へ `d` だけ太らせる（負なら内へ痩せる）。向き（時計回りか）は問わない
    static func offset(_ p: [CV2], by d: Double) -> [CV2] {
        guard p.count > 2 else { return p }
        let s: Double = signedArea(p) >= 0 ? 1 : -1
        return p.indices.map { i in
            let a = p[(i - 1 + p.count) % p.count], q = p[i], b = p[(i + 1) % p.count]
            let e1 = q - a, e2 = b - q
            let l1 = max(e1.length, 1e-9), l2 = max(e2.length, 1e-9)
            let n1 = CV2(e1.y / l1, -e1.x / l1), n2 = CV2(e2.y / l2, -e2.x / l2)
            var m = n1 + n2
            let ml = max(m.length, 1e-9)
            m = m * (1 / ml)
            let cosh = max(0.35, m.x * n1.x + m.y * n1.y)
            return q + m * (s * d / cosh)
        }
    }

    /// 横線 `minY`〜`maxY` の間だけ残す（Sutherland–Hodgman）
    static func clipY(_ p: [CV2], min lo: Double, max hi: Double) -> [CV2] {
        func clip(_ pts: [CV2], _ y: Double, keepAbove: Bool) -> [CV2] {
            var out: [CV2] = []
            for i in pts.indices {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                let ia = keepAbove ? a.y >= y : a.y <= y
                let ib = keepAbove ? b.y >= y : b.y <= y
                if ia { out.append(a) }
                if ia != ib {
                    let t = (y - a.y) / (b.y - a.y)
                    out.append(CV2(a.x + (b.x - a.x) * t, y))
                }
            }
            return out
        }
        guard p.count > 2 else { return [] }
        return clip(clip(p, lo, keepAbove: true), hi, keepAbove: false)
    }

    /// 縦線 `minX`〜`maxX` の間だけ残す
    static func clipX(_ p: [CV2], min lo: Double, max hi: Double) -> [CV2] {
        clipY(p.map { CV2($0.y, $0.x) }, min: lo, max: hi).map { CV2($0.y, $0.x) }
    }

    /// 外周の向きを反時計回りにそろえる（辺の名前も同じ順に並べ直す。i の辺は i→i+1）
    static func ccwTagged(_ p: [CV2], _ tags: [String]) -> (points: [CV2], tags: [String]) {
        guard signedArea(p) < 0 else { return (p, tags) }
        let n = p.count
        return (Array(p.reversed()), (0..<n).map { i in tags[(n - 2 - i + n) % n] })
    }

    /// 点が多角形の中か（偶奇）
    static func contains(_ p: [CV2], _ q: CV2) -> Bool {
        var inside = false
        var j = p.count - 1
        for i in p.indices {
            let a = p[i], b = p[j]
            if (a.y > q.y) != (b.y > q.y), q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// 横線 y で辺を切って点を足す（帯の塗り分けの境目で面を分ける）。辺の名前は元の辺の名前
    static func split(_ p: [CV2], tags: [String], atY ys: [Double]) -> (points: [CV2], tags: [String]) {
        var points: [CV2] = []
        var outTags: [String] = []
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            points.append(a)
            outTags.append(tags[i])
            let cuts = ys.compactMap { y -> Double? in
                guard (a.y - y) * (b.y - y) < 0 else { return nil }
                return (y - a.y) / (b.y - a.y)
            }.sorted()
            for t in cuts {
                points.append(CV2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
                outTags.append(tags[i])
            }
        }
        return (points, outTags)
    }

    // MARK: 三角形に分ける（穴あり）

    /// 穴のある多角形を三角形に分ける（耳を切る方法。穴は一番右の点から橋を架けて外周につなぐ）。
    /// 返すのは反時計回りの三角形の頂点を3つずつ並べたもの
    static func triangulate(outer: [CV2], holes: [[CV2]] = []) -> [CV2] {
        var poly = ccw(cleaned(outer))
        guard poly.count >= 3 else { return [] }
        let hs = holes.map { cw(cleaned($0)) }.filter { $0.count >= 3 }
            .sorted { ($0.map(\.x).max() ?? 0) > ($1.map(\.x).max() ?? 0) }
        for (k, hole) in hs.enumerated() {
            poly = bridge(poly, hole, others: Array(hs[(k + 1)...]))
        }
        return earClip(poly)
    }

    private static func segmentsCross(_ p1: CV2, _ p2: CV2, _ q1: CV2, _ q2: CV2) -> Bool {
        let eps = 1e-9
        func same(_ a: CV2, _ b: CV2) -> Bool { (a - b).length < 1e-7 }
        if same(p1, q1) || same(p1, q2) || same(p2, q1) || same(p2, q2) { return false }
        let d1 = (q2 - q1).cross(p1 - q1), d2 = (q2 - q1).cross(p2 - q1)
        let d3 = (p2 - p1).cross(q1 - p1), d4 = (p2 - p1).cross(q2 - p1)
        return ((d1 > eps && d2 < -eps) || (d1 < -eps && d2 > eps)) && ((d3 > eps && d4 < -eps) || (d3 < -eps && d4 > eps))
    }

    /// 穴を外周へ橋でつなぐ（Eberly の方法: 穴の一番右の点から右へ光を飛ばし、当たった辺の右の端の点、
    /// その三角形の中に凹んだ点があれば一番まっすぐ見える点へ）
    private static func bridge(_ poly: [CV2], _ hole: [CV2], others: [[CV2]]) -> [CV2] {
        guard let m = hole.indices.max(by: { (hole[$0].x, -hole[$0].y) < (hole[$1].x, -hole[$1].y) }) else { return poly }
        let mp = hole[m]
        var bestT = Double.infinity
        var hit: Int?
        var hitPoint = mp
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            // 下から上へ（または上から下へ）M の高さを跨ぐ辺
            guard (a.y - mp.y) * (b.y - mp.y) <= 0, a.y != b.y else { continue }
            let t = (mp.y - a.y) / (b.y - a.y)
            let x = a.x + (b.x - a.x) * t
            guard x >= mp.x - 1e-9, x - mp.x < bestT else { continue }
            bestT = x - mp.x
            hit = a.x > b.x ? i : (i + 1) % poly.count
            hitPoint = CV2(x, mp.y)
        }
        guard var pick = hit else { return poly }
        // 当たった点が辺の端そのものでなければ、三角形 M・当たり・P の中の凹んだ点を探す
        if (poly[pick] - hitPoint).length > 1e-9 {
            let p = poly[pick]
            func inside(_ q: CV2) -> Bool {
                let d1 = (hitPoint - mp).cross(q - mp), d2 = (p - hitPoint).cross(q - hitPoint), d3 = (mp - p).cross(q - p)
                let neg = d1 < -1e-12 || d2 < -1e-12 || d3 < -1e-12
                let pos = d1 > 1e-12 || d2 > 1e-12 || d3 > 1e-12
                return !(neg && pos)
            }
            var bestAngle = Double.infinity
            var bestDist = Double.infinity
            for i in poly.indices where i != pick {
                let q = poly[i]
                let prev = poly[(i - 1 + poly.count) % poly.count], next = poly[(i + 1) % poly.count]
                let reflex = (q - prev).cross(next - q) <= 0
                guard reflex, q.x >= mp.x, inside(q) else { continue }
                let d = q - mp
                let angle = abs(atan2(d.y, d.x))
                if angle < bestAngle - 1e-12 || (abs(angle - bestAngle) < 1e-12 && d.length < bestDist) {
                    bestAngle = angle
                    bestDist = d.length
                    pick = i
                }
            }
        }
        _ = others
        // 同じ位置の点が2つある（前の穴の橋の行きと帰り）なら、橋の向きがその角の内側に入る方を選ぶ
        // （外側の角につなぐと三角形が重なる）
        let target = poly[pick]
        let twins = poly.indices.filter { (poly[$0] - target).length < 1e-9 }
        if twins.count > 1 {
            for j in twins {
                let v = poly[j], a = poly[(j - 1 + poly.count) % poly.count], b = poly[(j + 1) % poly.count]
                let e1 = a - v, e2 = b - v, d = mp - v
                let convex = (v - a).cross(b - v) > 0
                let inside = convex ? (e2.cross(d) > 0 && d.cross(e1) > 0) : !(e1.cross(d) > 0 && d.cross(e2) > 0)
                if inside {
                    pick = j
                    break
                }
            }
        }
        let i = pick
        var out = Array(poly[0...i])
        out += hole[m...] + hole[..<m]
        out.append(mp)
        out.append(poly[i])
        if i + 1 < poly.count { out += poly[(i + 1)...] }
        return out
    }

    private static func earClip(_ input: [CV2]) -> [CV2] {
        var idx = Array(input.indices)
        var out: [CV2] = []
        let p = input
        func inTri(_ q: CV2, _ a: CV2, _ b: CV2, _ c: CV2) -> Bool {
            let eps = 1e-9
            let d1 = (b - a).cross(q - a), d2 = (c - b).cross(q - b), d3 = (a - c).cross(q - c)
            return d1 > eps && d2 > eps && d3 > eps
        }
        var guardCount = 0
        while idx.count > 3, guardCount < 100_000 {
            guardCount += 1
            var clipped = false
            for k in idx.indices {
                let ia = idx[(k - 1 + idx.count) % idx.count], ib = idx[k], ic = idx[(k + 1) % idx.count]
                let a = p[ia], b = p[ib], c = p[ic]
                let turn = (b - a).cross(c - b)
                let flat = 1e-7 * max(1, (b - a).length * (c - b).length)
                if abs(turn) < flat {
                    // まっすぐ続く点は落とす（折り返し＝橋の行きと帰りは落とさない）
                    let e1 = b - a, e2 = c - b
                    if e1.x * e2.x + e1.y * e2.y > 0 || (b - a).length < 1e-9 || (c - b).length < 1e-9 {
                        idx.remove(at: k)
                        clipped = true
                        break
                    }
                    continue
                }
                guard turn > flat else { continue }
                var ear = true
                for j in idx where j != ia && j != ib && j != ic {
                    let q = p[j]
                    if (q - a).length < 1e-9 || (q - b).length < 1e-9 || (q - c).length < 1e-9 { continue }
                    if inTri(q, a, b, c) {
                        ear = false
                        break
                    }
                }
                if ear {
                    out += [a, b, c]
                    idx.remove(at: k)
                    clipped = true
                    break
                }
            }
            if !clipped {
                // 形が崩れている（自分と交わる）。残りを扇で閉じて抜ける（無限に回さない）
                for k in 1..<(idx.count - 1) {
                    let a = p[idx[0]], b = p[idx[k]], c = p[idx[k + 1]]
                    if (b - a).cross(c - a) > 0 { out += [a, b, c] }
                }
                return out
            }
        }
        if idx.count == 3 {
            let a = p[idx[0]], b = p[idx[1]], c = p[idx[2]]
            if (b - a).cross(c - a) > 1e-10 { out += [a, b, c] }
        }
        return out
    }

    /// 三角形を横線の帯で切る（塗り分けの帯ごとの三角形にする）
    static func clipTriangles(_ tris: [CV2], minY: Double, maxY: Double) -> [CV2] {
        var out: [CV2] = []
        var i = 0
        while i + 2 < tris.count {
            let poly = clipY([tris[i], tris[i + 1], tris[i + 2]], min: minY, max: maxY)
            if poly.count >= 3 {
                for k in 1..<(poly.count - 1) where (poly[k] - poly[0]).cross(poly[k + 1] - poly[0]) > 1e-10 {
                    out += [poly[0], poly[k], poly[k + 1]]
                }
            }
            i += 3
        }
        return out
    }
}

// MARK: - 網（メッシュ）

/// 材質ごとの三角形の束。SceneKit の `SCNGeometry`（材質ごとに1つの element）にそのまま写す
struct CamperMesh: Sendable {
    var positions: [CV3] = []
    var normals: [CV3] = []
    var uvs: [CV2] = []
    /// 材質と、その三角形の頂点の番号（3つずつ）。順番は足した順（決まった順で SceneKit に渡す）
    var groups: [(material: CamperMaterial, indices: [Int32])] = []

    var triangleCount: Int { groups.reduce(0) { $0 + $1.indices.count / 3 } }
    var isEmpty: Bool { groups.allSatisfy { $0.indices.isEmpty } }
    var materials: [CamperMaterial] { groups.map(\.material) }

    private mutating func groupIndex(_ m: CamperMaterial) -> Int {
        if let i = groups.firstIndex(where: { $0.material == m }) { return i }
        groups.append((m, []))
        return groups.count - 1
    }

    /// 貼り絵の位置（面の向きで、いちばん近い軸の平面に投げる・16 単位で1回）
    static func uv(_ p: CV3, _ n: CV3, scale: Double = 16) -> CV2 {
        let ax = abs(n.x), ay = abs(n.y), az = abs(n.z)
        if ax >= ay, ax >= az { return CV2(p.z / scale, p.y / scale) }
        if ay >= az { return CV2(p.x / scale, p.z / scale) }
        return CV2(p.x / scale, p.y / scale)
    }

    /// 三角形を1つ。**巻き方は向き（法線）から決める**（反時計回りが表。巻きの書き違いで裏返らない）
    mutating func tri(_ a: CV3, _ b: CV3, _ c: CV3, _ na: CV3, _ nb: CV3, _ nc: CV3, _ m: CamperMaterial) {
        let face = (b - a).cross(c - a)
        guard face.length > 1e-12 else { return }
        let base = Int32(positions.count)
        let flip = face.dot(na + nb + nc) < 0
        let vs = flip ? [a, c, b] : [a, b, c]
        let ns = flip ? [na, nc, nb] : [na, nb, nc]
        for (v, n) in zip(vs, ns) {
            positions.append(v)
            normals.append(n.normalized)
            uvs.append(Self.uv(v, n))
        }
        let g = groupIndex(m)
        groups[g].indices += [base, base + 1, base + 2]
    }

    mutating func tri(_ a: CV3, _ b: CV3, _ c: CV3, normal n: CV3, _ m: CamperMaterial) {
        tri(a, b, c, n, n, n, m)
    }

    /// 四角（a→b→c→d の輪）を2つの三角形で
    mutating func quad(_ a: CV3, _ b: CV3, _ c: CV3, _ d: CV3,
                       _ na: CV3, _ nb: CV3, _ nc: CV3, _ nd: CV3, _ m: CamperMaterial) {
        tri(a, b, c, na, nb, nc, m)
        tri(a, c, d, na, nc, nd, m)
    }

    mutating func append(_ other: CamperMesh) {
        let base = Int32(positions.count)
        positions += other.positions
        normals += other.normals
        uvs += other.uvs
        for g in other.groups {
            let i = groupIndex(g.material)
            groups[i].indices += g.indices.map { $0 + base }
        }
    }

    /// 材質で2つに分ける（`match` に当たる束と、残り）。点は両方にそのまま残す（使わない点は描かれない）
    func split(_ match: (CamperMaterial) -> Bool) -> (matched: CamperMesh, rest: CamperMesh) {
        var a = self, b = self
        a.groups = groups.filter { match($0.material) }
        b.groups = groups.filter { !match($0.material) }
        return (a, b)
    }

    /// 点と向きを写す。`mirror`（鏡に映す写し）なら巻きを逆にする
    func mapped(_ f: (CV3) -> CV3, normal nf: (CV3) -> CV3, mirror: Bool = false) -> CamperMesh {
        var out = self
        out.positions = positions.map(f)
        out.normals = normals.map { nf($0).normalized }
        if mirror {
            out.groups = groups.map { g in
                var idx = g.indices
                var i = 0
                while i + 2 < idx.count {
                    idx.swapAt(i + 1, i + 2)
                    i += 3
                }
                return (g.material, idx)
            }
        }
        return out
    }

    func translated(_ t: CV3) -> CamperMesh { mapped({ $0 + t }, normal: { $0 }) }

    /// 向こう側（-Z）へ鏡に映す
    func mirroredZ() -> CamperMesh {
        mapped({ CV3($0.x, $0.y, -$0.z) }, normal: { CV3($0.x, $0.y, -$0.z) }, mirror: true)
    }

    /// 囲む箱（試験と、置き場所の計算に使う）
    var bounds: (min: CV3, max: CV3) {
        guard let first = positions.first else { return (.zero, .zero) }
        var lo = first, hi = first
        for p in positions {
            lo = CV3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = CV3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        return (lo, hi)
    }

    /// 辺のうち、ちょうど1枚の三角形にしか使われていない辺の数（0 なら閉じた立体。試験で使う）。
    /// 塗り分けの帯で面を切った所の T 字（長い辺1本と、同じ線の上の短い辺2本）は閉じているとみなす
    var openEdgeCount: Int {
        struct Key: Hashable { let a: CV3, b: CV3 }
        func r(_ v: CV3) -> CV3 { CV3((v.x * 1000).rounded() / 1000, (v.y * 1000).rounded() / 1000, (v.z * 1000).rounded() / 1000) }
        var count: [Key: Int] = [:]
        for g in groups {
            var i = 0
            while i + 2 < g.indices.count {
                let v = [g.indices[i], g.indices[i + 1], g.indices[i + 2]].map { r(positions[Int($0)]) }
                for k in 0..<3 {
                    let a = v[k], b = v[(k + 1) % 3]
                    let key = (a.x, a.y, a.z) < (b.x, b.y, b.z) ? Key(a: a, b: b) : Key(a: b, b: a)
                    count[key, default: 0] += 1
                }
                i += 3
            }
        }
        let open = count.filter { $0.value == 1 }.map(\.key)
        func on(_ p: CV3, _ e: Key) -> Bool {
            let d = e.b - e.a, l = d.length
            guard l > 1e-9 else { return false }
            let t = (p - e.a).dot(d) / (l * l)
            return t > -1e-6 && t < 1 + 1e-6 && ((e.a + d * t) - p).length < 2e-3
        }
        var matched = Set<Int>()
        for (i, e) in open.enumerated() {
            let inside = open.indices.filter { $0 != i && on(open[$0].a, e) && on(open[$0].b, e) }
            // 同じ線の上の短い辺が、長い辺を端から端まで覆うか（重なりは1回に数える）
            let d = e.b - e.a, l2 = d.dot(d)
            let spans = inside.map { k -> (Double, Double) in
                let t0 = (open[k].a - e.a).dot(d) / l2, t1 = (open[k].b - e.a).dot(d) / l2
                return (min(t0, t1), max(t0, t1))
            }.sorted { $0.0 < $1.0 }
            var reach = 0.0
            for sp in spans where sp.0 <= reach + 1e-4 { reach = max(reach, sp.1) }
            if !inside.isEmpty, reach >= 1 - 1e-4 {
                matched.insert(i)
                inside.forEach { matched.insert($0) }
            }
        }
        return open.count - matched.count
    }
}

/// 塗り分けの帯（下の Y から上の Y まで・上が +Y）
/// 紙の反り（`center` から `direction` の向きへ測って `start` から先が浮き、`end` で `lift` まで）
struct CamperCurl: Sendable {
    var center: CV2
    var direction: CV2
    var start: Double
    var end: Double
    var lift: Double
    var slices = 6
}

struct CamperBand: Sendable {
    var minY: Double
    var maxY: Double
    var material: CamperMaterial
}

// MARK: - 網を作る道具

enum CamperMeshKit {

    /// なめらかにつなぐ曲がりの上限（これより急な角は角として立てる）
    static let smoothAngle = 35.0 * .pi / 180

    /// 輪の各点の、前の辺と次の辺の外向き（材質から離れる向き）の法線。急な角でなければ平均する
    static func loopNormals(_ loop: [CV2]) -> [(incoming: CV2, outgoing: CV2)] {
        let n = loop.count
        func edgeNormal(_ i: Int) -> CV2 {
            let a = loop[i], b = loop[(i + 1) % n]
            let d = b - a
            let l = max(d.length, 1e-9)
            return CV2(d.y / l, -d.x / l)
        }
        let edges = (0..<n).map(edgeNormal)
        return (0..<n).map { i in
            let inc = edges[(i - 1 + n) % n], out = edges[i]
            let cosA = inc.x * out.x + inc.y * out.y
            if cosA > cos(smoothAngle) {
                var m = inc + out
                let l = max(m.length, 1e-9)
                m = m * (1 / l)
                return (m, m)
            }
            return (inc, out)
        }
    }

    /// 2つの輪（同じ点の数）を帯でつなぐ。`za` の輪 `a` と `zb` の輪 `b`。向きは輪 `a` の辺の外向き＋`tilt`（Z の向き）
    static func strip(_ mesh: inout CamperMesh, a: [CV2], za: Double, b: [CV2], zb: Double, tiltA: Double, tiltB: Double,
                      skip: (Int) -> Bool = { _ in false }, material: (Int) -> CamperMaterial) {
        let n = a.count
        guard n > 1, b.count == n else { return }
        let ns = loopNormals(a)
        for i in 0..<n where !skip(i) {
            let j = (i + 1) % n
            let n0 = ns[i].outgoing, n1 = ns[j].incoming
            let a0 = CV3(a[i].x, a[i].y, za), a1 = CV3(a[j].x, a[j].y, za)
            let b0 = CV3(b[i].x, b[i].y, zb), b1 = CV3(b[j].x, b[j].y, zb)
            mesh.quad(a0, b0, b1, a1,
                      CV3(n0.x, n0.y, tiltA), CV3(n0.x, n0.y, tiltB), CV3(n1.x, n1.y, tiltB), CV3(n1.x, n1.y, tiltA),
                      material(i))
        }
    }

    /// 平らな面（穴あり）を Z=`z` に、向き `facing`（+1 で +Z）で。帯があれば帯ごとの材質で切る
    static func face(_ mesh: inout CamperMesh, outline: [CV2], holes: [[CV2]], z: Double, facing: Double,
                     bands: [CamperBand]) {
        let tris = CamperPolygon.triangulate(outer: outline, holes: holes)
        let n = CV3(0, 0, facing)
        for band in bands {
            let part = CamperPolygon.clipTriangles(tris, minY: band.minY, maxY: band.maxY)
            var i = 0
            while i + 2 < part.count {
                let a = part[i], b = part[i + 1], c = part[i + 2]
                mesh.tri(CV3(a.x, a.y, z), CV3(b.x, b.y, z), CV3(c.x, c.y, z), normal: n, band.material)
                i += 3
            }
        }
    }

    /// 帯の中で y の位置の材質（帯から外れたら最後の帯）
    static func material(at y: Double, in bands: [CamperBand]) -> CamperMaterial {
        bands.first { y >= $0.minY && y < $0.maxY }?.material ?? bands.last?.material ?? .black
    }

    /// 厚みのある板（穴あり・表の縁を面取り）。表は Z=0 で +Z を向き、裏は Z=-`thickness`。
    ///
    /// - outline: 外周（反時計回りに直して使う）。`tags` は外周の辺の名前（側面の材質を決める）
    /// - holes: 穴（窓・扉の口）。穴の壁（窓の厚み）は `reveal` の材質
    /// - bevel: 外周の面取り。holeBevel: 穴の縁の面取り
    /// - bands: 表の塗り分け（上が +Y）。coarse: 面取りと側面の材質（帯の細い線は入れない）
    static func slab(outline rawOutline: [CV2], tags rawTags: [String]? = nil, holes: [[CV2]] = [], thickness: Double,
                     bevel: Double, holeBevel: Double = 0.6, backBevel: Double = 0, bands: [CamperBand],
                     coarse: [CamperBand]? = nil,
                     side: ((String?, Double) -> CamperMaterial)? = nil,
                     back: CamperMaterial?, reveal: CamperMaterial) -> CamperMesh {
        var mesh = CamperMesh()
        let reversed = CamperPolygon.signedArea(rawOutline) < 0
        let outline = reversed ? Array(rawOutline.reversed()) : rawOutline
        // 外周を反時計回りに直したら、辺の名前も同じ順に（i の辺は i→i+1。逆順では i+1→i が元の辺）
        let tags: [String]? = rawTags.map { t in
            guard reversed else { return t }
            let n = t.count
            return (0..<n).map { i in t[(n - 2 - i + n) % n] }
        }
        let hs = holes.map { CamperPolygon.cw($0) }
        let coarseBands = coarse ?? bands
        func sideMaterial(_ i: Int, _ y: Double) -> CamperMaterial {
            if let side { return side(tags?[i], y) }
            return material(at: y, in: coarseBands)
        }
        let frontOuter = bevel > 0 ? CamperPolygon.offset(outline, by: -bevel) : outline
        let backOuter = backBevel > 0 ? CamperPolygon.offset(outline, by: -backBevel) : outline
        let frontHoles = hs.map { holeBevel > 0 ? CamperPolygon.offset($0, by: holeBevel) : $0 }
        // 表
        face(&mesh, outline: frontOuter, holes: frontHoles, z: 0, facing: 1, bands: bands)
        // 表の面取り（外周）
        let midY: (Int, [CV2]) -> Double = { i, l in (l[i].y + l[(i + 1) % l.count].y) / 2 }
        if bevel > 0 {
            strip(&mesh, a: frontOuter, za: 0, b: outline, zb: -bevel, tiltA: 1, tiltB: 1) { sideMaterial($0, midY($0, outline)) }
        }
        // 外周の側面
        strip(&mesh, a: outline, za: -bevel, b: outline, zb: -thickness + backBevel, tiltA: 0, tiltB: 0) {
            sideMaterial($0, midY($0, outline))
        }
        if backBevel > 0 {
            strip(&mesh, a: outline, za: -thickness + backBevel, b: backOuter, zb: -thickness, tiltA: -1, tiltB: -1) {
                sideMaterial($0, midY($0, outline))
            }
        }
        // 裏
        if let back {
            face(&mesh, outline: backOuter, holes: hs, z: -thickness, facing: -1,
                 bands: [CamperBand(minY: -.infinity, maxY: .infinity, material: back)])
        }
        // 穴の縁の面取りと、穴の壁（厚み）
        for (h, fh) in zip(hs, frontHoles) {
            if holeBevel > 0 {
                strip(&mesh, a: fh, za: 0, b: h, zb: -holeBevel, tiltA: 1, tiltB: 1) { material(at: midY($0, h), in: coarseBands) }
            }
            strip(&mesh, a: h, za: -holeBevel, b: h, zb: -thickness, tiltA: 0, tiltB: 0) { _ in reveal }
        }
        return mesh
    }

    /// 旋盤で回した形（+Y の軸のまわり）。`profile` は (半径, 高さ)。
    /// 曲がりの急な所は角を立て、ゆるい所はなめらかに。端の半径が 0 でなければ蓋をする
    static func lathe(_ profile: [CV2], segments: Int, faceted: Bool = false, start: Double = 0,
                      material: (Int) -> CamperMaterial, capStart: CamperMaterial? = nil,
                      capEnd: CamperMaterial? = nil) -> CamperMesh {
        var mesh = CamperMesh()
        let n = max(3, segments)
        guard profile.count >= 2 else { return mesh }
        func pt(_ p: CV2, _ t: Double) -> CV3 { CV3(cos(t) * p.x, p.y, sin(t) * p.x) }
        // 断面の各区間の外向き（半径と高さの面で）。高さが下がる区間でも、軸から外を向くよう
        // 法線は「外向き」を基準に決める（巻きは `tri` が向きから合わせる）
        let segNormals: [CV2] = (0..<(profile.count - 1)).map { k in
            let d = profile[k + 1] - profile[k]
            let l = max(d.length, 1e-9)
            var nn = CV2(d.y / l, -d.x / l)
            // 外向き＝半径が増える側。半径の変わらない平らな輪（皿）は高さの向きで決まる
            let mid = (profile[k] + profile[k + 1]) * 0.5
            if nn.x * 1 + 0 < 0, mid.x > 0.01, abs(d.y) > 1e-6 { nn = nn * -1 }
            return nn
        }
        let thetas = (0...n).map { start + Double($0) / Double(n) * 2 * .pi }
        for k in 0..<(profile.count - 1) {
            let a = profile[k], b = profile[k + 1]
            if a.x < 1e-4, b.x < 1e-4 { continue }
            var na = segNormals[k], nb = segNormals[k]
            if k > 0 {
                let prev = segNormals[k - 1]
                if prev.x * na.x + prev.y * na.y > cos(smoothAngle) { na = (prev + na) * 0.5 }
            }
            if k + 1 < segNormals.count {
                let next = segNormals[k + 1]
                if next.x * nb.x + next.y * nb.y > cos(smoothAngle) { nb = (next + nb) * 0.5 }
            }
            let m = material(k)
            for i in 0..<n {
                let t0 = thetas[i], t1 = thetas[i + 1]
                let tm = (t0 + t1) / 2
                func nrm(_ v: CV2, _ t: Double) -> CV3 {
                    let tt = faceted ? tm : t
                    return CV3(cos(tt) * v.x, v.y, sin(tt) * v.x)
                }
                let p00 = pt(a, t0), p01 = pt(a, t1), p10 = pt(b, t0), p11 = pt(b, t1)
                if a.x < 1e-4 {
                    mesh.tri(p00, p11, p10, nrm(na, tm), nrm(nb, t1), nrm(nb, t0), m)
                } else if b.x < 1e-4 {
                    mesh.tri(p00, p01, p10, nrm(na, t0), nrm(na, t1), nrm(nb, tm), m)
                } else {
                    mesh.quad(p00, p01, p11, p10, nrm(na, t0), nrm(na, t1), nrm(nb, t1), nrm(nb, t0), m)
                }
            }
        }
        // 蓋（端の輪を扇で閉じる）。向きは断面の外側（はじめは低い側、終わりは高い側）
        func cap(_ p: CV2, _ other: CV2, _ m: CamperMaterial) {
            guard p.x > 1e-4 else { return }
            let dir = p.y <= other.y ? -1.0 : 1.0
            let c = CV3(0, p.y, 0)
            let nn = CV3(0, dir, 0)
            for i in 0..<n { mesh.tri(c, pt(p, thetas[i]), pt(p, thetas[i + 1]), normal: nn, m) }
        }
        if let capStart { cap(profile[0], profile[profile.count - 1], capStart) }
        if let capEnd { cap(profile[profile.count - 1], profile[0], capEnd) }
        return mesh
    }

    /// タイヤの踏み面の山（ブロック）。軸は +Y、踏み面の半径 `r`、溝の深さ `depth`。
    /// 2列（`rows` の高さの範囲）を半ピッチずらして並べ、溝の底は旋盤の胴（半径 r - depth）が受け持つ
    static func treadBlocks(radius r: Double, depth: Double, rows: [(Double, Double)], pitches: Int,
                            land: Double = 0.72, material: CamperMaterial) -> CamperMesh {
        var mesh = CamperMesh()
        let inner = r - depth
        let pitch = 2 * Double.pi / Double(pitches)
        func p(_ rr: Double, _ t: Double, _ h: Double) -> CV3 { CV3(cos(t) * rr, h, sin(t) * rr) }
        func radial(_ t: Double) -> CV3 { CV3(cos(t), 0, sin(t)) }
        for (row, range) in rows.enumerated() {
            let (h0, h1) = range
            let offset = row % 2 == 0 ? 0 : pitch / 2
            for k in 0..<pitches {
                let t0 = Double(k) * pitch + offset
                let t1 = t0 + pitch * land
                let tm = (t0 + t1) / 2
                // 上の面（2つに分けて丸みを出す）
                for (a, b) in [(t0, tm), (tm, t1)] {
                    mesh.quad(p(r, a, h0), p(r, b, h0), p(r, b, h1), p(r, a, h1),
                              radial(a), radial(b), radial(b), radial(a), material)
                }
                // 回る向きの前と後ろの壁
                let back = CV3(sin(t0), 0, -cos(t0)), front = CV3(-sin(t1), 0, cos(t1))
                mesh.quad(p(inner, t0, h0), p(r, t0, h0), p(r, t0, h1), p(inner, t0, h1), back, back, back, back, material)
                mesh.quad(p(inner, t1, h0), p(inner, t1, h1), p(r, t1, h1), p(r, t1, h0), front, front, front, front, material)
                // 真ん中の溝に面する端（外側の端は肩に埋まる）
                let toCenter = row == 0 ? CV3(0, 1, 0) : CV3(0, -1, 0)
                let hEdge = row == 0 ? h1 : h0
                mesh.quad(p(inner, t0, hEdge), p(inner, t1, hEdge), p(r, t1, hEdge), p(r, t0, hEdge),
                          toCenter, toCenter, toCenter, toCenter, material)
            }
        }
        return mesh
    }

    /// 平らな形（穴なし）を厚み `depth` で押し出す（ステッカー・札など）。表は +Z
    /// 貼った紙（ステッカー）。表は Z=0 で +Z を向き、裏は Z=-`depth`。`curl` の向きの先の端が壁から浮いて反る。
    ///
    /// 平らな板のままだと反らせても面が曲がらないので、反る所は表も裏も `curl.slices` 本の帯に割る
    /// （輪郭にも帯の切れ目の点を入れ、側面と表の継ぎ目に隙間を作らない）
    static func paper(_ outline: [CV2], holes: [[CV2]] = [], depth: Double, front: CamperMaterial, side: CamperMaterial,
                      back: CamperMaterial, curl: CamperCurl) -> CamperMesh {
        let len = max(curl.direction.length, 1e-9)
        let d = CV2(curl.direction.x / len, curl.direction.y / len)
        let c = curl.center
        // 反りの向きを +Y にした平面（回すだけ・裏返さない）
        func local(_ p: CV2) -> CV2 {
            let q = p - c
            return CV2(q.x * d.y - q.y * d.x, q.x * d.x + q.y * d.y)
        }
        let n = max(1, curl.slices)
        let cuts = (0...n).map { curl.start + (curl.end - curl.start) * Double($0) / Double(n) }
        /// 輪の辺が帯の切れ目をまたぐ所に点を足す
        func densified(_ loop: [CV2]) -> [CV2] {
            var out: [CV2] = []
            for i in loop.indices {
                let a = loop[i], b = loop[(i + 1) % loop.count]
                out.append(a)
                guard abs(b.y - a.y) > 1e-9 else { continue }
                let crossing = cuts.filter { ($0 - a.y) * ($0 - b.y) < 0 }
                    .sorted { b.y > a.y ? $0 < $1 : $0 > $1 }
                for y in crossing { out.append(a + (b - a) * ((y - a.y) / (b.y - a.y))) }
            }
            return out
        }
        let outer = densified(CamperPolygon.ccw(CamperPolygon.cleaned(outline.map(local))))
        let hs = holes.map { densified(CamperPolygon.cw(CamperPolygon.cleaned($0.map(local)))) }
        let bounds = [-Double.infinity] + cuts + [Double.infinity]
        func bands(_ m: CamperMaterial) -> [CamperBand] {
            (0..<(bounds.count - 1)).map { CamperBand(minY: bounds[$0], maxY: bounds[$0 + 1], material: m) }
        }
        var mesh = CamperMesh()
        face(&mesh, outline: outer, holes: hs, z: 0, facing: 1, bands: bands(front))
        face(&mesh, outline: outer, holes: hs, z: -depth, facing: -1, bands: bands(back))
        strip(&mesh, a: outer, za: 0, b: outer, zb: -depth, tiltA: 0, tiltB: 0) { _ in side }
        for h in hs { strip(&mesh, a: h, za: 0, b: h, zb: -depth, tiltA: 0, tiltB: 0) { _ in side } }
        // 反らせる（帯の切れ目から先を、端で `lift` だけ浮かせる。向きも同じだけ起こす）。最後に元の向きへ戻す
        let span = max(curl.end - curl.start, 1e-9)
        for i in mesh.positions.indices {
            let p = mesh.positions[i]
            var nn = mesh.normals[i]
            var z = p.z
            if p.y > curl.start {
                let t = min(1, (p.y - curl.start) / span)
                z += curl.lift * t * t
                let tilt = atan(2 * curl.lift * t / span)
                nn = CV3(nn.x, nn.y * cos(tilt) - nn.z * sin(tilt), nn.y * sin(tilt) + nn.z * cos(tilt))
            }
            mesh.positions[i] = CV3(c.x + p.x * d.y + p.y * d.x, c.y - p.x * d.x + p.y * d.y, z)
            mesh.normals[i] = CV3(nn.x * d.y + nn.y * d.x, -nn.x * d.x + nn.y * d.y, nn.z).normalized
        }
        return mesh
    }

    static func extrude(_ outline: [CV2], holes: [[CV2]] = [], depth: Double, front: CamperMaterial,
                        side: CamperMaterial, back: CamperMaterial? = nil, bevel: Double = 0) -> CamperMesh {
        slab(outline: outline, holes: holes, thickness: depth, bevel: bevel, holeBevel: 0,
             bands: [CamperBand(minY: -.infinity, maxY: .infinity, material: front)],
             side: { _, _ in side }, back: back ?? side, reveal: side)
    }
}
