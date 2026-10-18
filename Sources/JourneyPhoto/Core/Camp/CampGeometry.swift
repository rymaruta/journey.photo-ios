import Foundation

// キャンプ場の島を組む形の計算（板 Camp の `mkR3` の積み木を Swift に移したもの）。
//
// - **座標は板のまま**: x 右・y 下（芝の面が y=0、下が正）・z 手前。単位も板の単位
// - 面の向きは「外から見て、三角の (b−a)×(c−a) が外を向く」に揃える。SceneKit へ渡すとき
//   y を返すと裏返るので、渡す側（`CampSceneRenderer`）が三角の順を入れ替える
// - ここは画面を持たない計算だけ（Linux でテストできる）。SceneKit の型は使わない

/// 3 次元の点・向き（板の座標）
struct CampVec3: Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static let zero = CampVec3(0, 0, 0)

    static func + (a: CampVec3, b: CampVec3) -> CampVec3 { CampVec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: CampVec3, b: CampVec3) -> CampVec3 { CampVec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: CampVec3, k: Double) -> CampVec3 { CampVec3(a.x * k, a.y * k, a.z * k) }
    static prefix func - (a: CampVec3) -> CampVec3 { CampVec3(-a.x, -a.y, -a.z) }

    func dot(_ b: CampVec3) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: CampVec3) -> CampVec3 { CampVec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var length: Double { (x * x + y * y + z * z).squareRoot() }
    var normalized: CampVec3 {
        let l = length
        return l > 0 ? self * (1 / l) : self
    }

    /// 縦の軸（y）まわりに回す（板の `rY`。度）
    func rotatedY(_ degrees: Double) -> CampVec3 {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a)
        return CampVec3(x * c + z * s, y, -x * s + z * c)
    }

    /// 横の軸（x）まわりに回す（板の `rX`。度）
    func rotatedX(_ degrees: Double) -> CampVec3 {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a)
        return CampVec3(x, y * c - z * s, y * s + z * c)
    }

    /// 奥の軸（z）まわりに回す（板の `rZ`。度）
    func rotatedZ(_ degrees: Double) -> CampVec3 {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a)
        return CampVec3(x * c - y * s, x * s + y * c, z)
    }

    static func mix(_ a: CampVec3, _ b: CampVec3, _ t: Double) -> CampVec3 { a + (b - a) * t }
}

/// 平らな 2 次元の点（島の外形・切り絵の輪郭）
struct CampVec2: Equatable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// 三角の網（位置・法線・貼り絵の座標・頂点の色）
struct CampMesh: Equatable, Sendable {
    var positions: [CampVec3] = []
    var normals: [CampVec3] = []
    var uvs: [CampVec2] = []
    /// 頂点ごとの色（草むら・花のように 1 つの網で色を変えるもの）。無ければ空
    var colors: [CampVec3] = []
    /// 三角（3 つずつ）。外から見て (b−a)×(c−a) が外を向く
    var indices: [Int32] = []

    var triangleCount: Int { indices.count / 3 }
    var isEmpty: Bool { indices.isEmpty }

    /// 頂点を 1 つ足して番号を返す
    @discardableResult
    mutating func vertex(_ p: CampVec3, _ n: CampVec3, _ uv: CampVec2 = CampVec2(0, 0), color: CampVec3? = nil) -> Int32 {
        positions.append(p)
        normals.append(n.normalized)
        uvs.append(uv)
        if let color { colors.append(color) }
        return Int32(positions.count - 1)
    }

    mutating func triangle(_ a: Int32, _ b: Int32, _ c: Int32) {
        indices += [a, b, c]
    }

    /// 平らな三角（法線は面の向き。`outward` があれば、その向きに揃える）
    mutating func flatTriangle(_ a: CampVec3, _ b: CampVec3, _ c: CampVec3, outward: CampVec3? = nil,
                               uv: [CampVec2]? = nil, color: CampVec3? = nil) {
        var n = (b - a).cross(c - a).normalized
        var (p, q, r) = (a, b, c)
        var (ua, ub, uc) = (uv?[0] ?? CampVec2(0, 0), uv?[1] ?? CampVec2(1, 0), uv?[2] ?? CampVec2(0, 1))
        if let outward, n.dot(outward) < 0 {
            n = -n
            swap(&q, &r)
            swap(&ub, &uc)
        }
        let i = vertex(p, n, ua, color: color), j = vertex(q, n, ub, color: color), k = vertex(r, n, uc, color: color)
        triangle(i, j, k)
    }

    /// 平らな四角（a→b→c→d の順の輪）
    mutating func flatQuad(_ a: CampVec3, _ b: CampVec3, _ c: CampVec3, _ d: CampVec3, outward: CampVec3? = nil,
                           uv: [CampVec2]? = nil, color: CampVec3? = nil) {
        flatPolygon([a, b, c, d], outward: outward, uv: uv, color: color)
    }

    /// 平らな多角形（凹んでいてもよい・耳を切って三角に分ける）。`uv` は頂点ごと
    mutating func flatPolygon(_ points: [CampVec3], outward: CampVec3? = nil, uv: [CampVec2]? = nil,
                              color: CampVec3? = nil) {
        guard points.count >= 3 else { return }
        var n = CampGeometry.newell(points)
        if let outward, n.dot(outward) < 0 { n = -n }
        let tris = CampGeometry.triangulate(points, normal: n)
        let base = Int32(positions.count)
        for (i, p) in points.enumerated() {
            vertex(p, n, uv?[i] ?? CampVec2(0, 0), color: color)
        }
        for t in tris {
            // 三角の向きを法線に合わせる
            let a = points[t.0], b = points[t.1], c = points[t.2]
            if (b - a).cross(c - a).dot(n) >= 0 {
                triangle(base + Int32(t.0), base + Int32(t.1), base + Int32(t.2))
            } else {
                triangle(base + Int32(t.0), base + Int32(t.2), base + Int32(t.1))
            }
        }
    }

    /// なめらかな四角（頂点ごとの法線）。三角の向きは法線の平均に合わせる
    mutating func smoothQuad(_ p: [CampVec3], _ n: [CampVec3], uv: [CampVec2]? = nil, color: CampVec3? = nil) {
        let avg = (n[0] + n[1] + n[2] + n[3]).normalized
        let base = Int32(positions.count)
        for i in 0..<4 { vertex(p[i], n[i], uv?[i] ?? CampVec2(0, 0), color: color) }
        let face = (p[1] - p[0]).cross(p[2] - p[0])
        if face.dot(avg) >= 0 {
            triangle(base, base + 1, base + 2)
            triangle(base, base + 2, base + 3)
        } else {
            triangle(base, base + 2, base + 1)
            triangle(base, base + 3, base + 2)
        }
    }

    /// なめらかな三角（頂点ごとの法線）
    mutating func smoothTriangle(_ p: [CampVec3], _ n: [CampVec3], uv: [CampVec2]? = nil, color: CampVec3? = nil) {
        let avg = (n[0] + n[1] + n[2]).normalized
        let base = Int32(positions.count)
        for i in 0..<3 { vertex(p[i], n[i], uv?[i] ?? CampVec2(0, 0), color: color) }
        if (p[1] - p[0]).cross(p[2] - p[0]).dot(avg) >= 0 {
            triangle(base, base + 1, base + 2)
        } else {
            triangle(base, base + 2, base + 1)
        }
    }

    mutating func append(_ other: CampMesh) {
        let base = Int32(positions.count)
        positions += other.positions
        normals += other.normals
        uvs += other.uvs
        colors += other.colors
        indices += other.indices.map { $0 + base }
    }

    /// 全部の点を動かす（板の座標のまま）
    func transformed(_ f: (CampVec3) -> CampVec3, normal g: (CampVec3) -> CampVec3) -> CampMesh {
        var m = self
        m.positions = positions.map(f)
        m.normals = normals.map { g($0).normalized }
        return m
    }

    /// 囲む箱（最小・最大）
    var bounds: (min: CampVec3, max: CampVec3) {
        guard let first = positions.first else { return (.zero, .zero) }
        var lo = first, hi = first
        for p in positions {
            lo = CampVec3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = CampVec3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        return (lo, hi)
    }
}

/// 形の積み木（板の `extrude`・`loft`・`lathe`・`rounded`・`offset2`）
enum CampGeometry {

    /// 多角形の面の向き（Newell の方法・板の `newell`）
    static func newell(_ pts: [CampVec3]) -> CampVec3 {
        var n = CampVec3.zero
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        }
        return n.normalized
    }

    static func centroid(_ pts: [CampVec3]) -> CampVec3 {
        guard !pts.isEmpty else { return .zero }
        return pts.reduce(CampVec3.zero, +) * (1 / Double(pts.count))
    }

    /// 平らな 2 次元の多角形の符号つきの面積（左回りが正）
    static func area(_ p: [CampVec2]) -> Double {
        var s = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    /// 耳を切って三角に分ける（凹んだ多角形も・穴なし）。返すのは頂点の番号の組
    static func triangulate(_ pts: [CampVec3], normal: CampVec3) -> [(Int, Int, Int)] {
        // いちばん大きい成分の軸を捨てて 2 次元に写す
        let ax = abs(normal.x), ay = abs(normal.y), az = abs(normal.z)
        let flat: [CampVec2] = pts.map { p in
            if az >= ax && az >= ay { return CampVec2(p.x, p.y) }
            if ay >= ax { return CampVec2(p.x, p.z) }
            return CampVec2(p.y, p.z)
        }
        return triangulate2D(flat)
    }

    static func triangulate2D(_ flat: [CampVec2]) -> [(Int, Int, Int)] {
        guard flat.count >= 3 else { return [] }
        var idx = Array(flat.indices)
        if area(flat) < 0 { idx.reverse() }
        var out: [(Int, Int, Int)] = []
        func cross(_ o: CampVec2, _ a: CampVec2, _ b: CampVec2) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        func inside(_ p: CampVec2, _ a: CampVec2, _ b: CampVec2, _ c: CampVec2) -> Bool {
            cross(a, b, p) >= 0 && cross(b, c, p) >= 0 && cross(c, a, p) >= 0
        }
        var guardCount = 0
        while idx.count > 3 && guardCount < 10_000 {
            guardCount += 1
            var cut = false
            for i in idx.indices {
                let ip = idx[(i + idx.count - 1) % idx.count], ic = idx[i], inx = idx[(i + 1) % idx.count]
                let a = flat[ip], b = flat[ic], c = flat[inx]
                guard cross(a, b, c) > 1e-9 else { continue }
                var ear = true
                for j in idx where j != ip && j != ic && j != inx {
                    let p = flat[j]
                    if p == a || p == b || p == c { continue }
                    if inside(p, a, b, c) { ear = false; break }
                }
                if ear {
                    out.append((ip, ic, inx))
                    idx.remove(at: i)
                    cut = true
                    break
                }
            }
            if !cut {
                // 一直線に並んだ点などで耳が見つからないときは扇で閉じる
                for i in 1..<(idx.count - 1) { out.append((idx[0], idx[i], idx[i + 1])) }
                return out
            }
        }
        if idx.count == 3 { out.append((idx[0], idx[1], idx[2])) }
        return out
    }

    /// 外形を内（負）・外（正）へずらす（板の `offset2`。角は 0.35 で頭打ち）
    static func offset(_ pts: [CampVec2], _ d: Double) -> [CampVec2] {
        let n = pts.count
        return pts.indices.map { i in
            let p = pts[i], a = pts[(i - 1 + n) % n], b = pts[(i + 1) % n]
            let e1 = CampVec2(p.x - a.x, p.y - a.y), e2 = CampVec2(b.x - p.x, b.y - p.y)
            let l1 = max(1e-9, hypot(e1.x, e1.y)), l2 = max(1e-9, hypot(e2.x, e2.y))
            let n1 = CampVec2(e1.y / l1, -e1.x / l1), n2 = CampVec2(e2.y / l2, -e2.x / l2)
            var m = CampVec2(n1.x + n2.x, n1.y + n2.y)
            let ml = max(1e-9, hypot(m.x, m.y))
            m = CampVec2(m.x / ml, m.y / ml)
            let cosh = max(0.35, m.x * n1.x + m.y * n1.y)
            return CampVec2(p.x + m.x * d / cosh, p.y + m.y * d / cosh)
        }
    }

    /// 板の面取りの輪（板の `offset2(P2, ccw ? b : -b)` と同じ向き）。
    /// 🔴 **左回りの外形では外へ出る**——板の島は芝の面が壁より 3.4 張り出し、その下の帯（`lip`）が
    /// 内へ斜めに戻る形（縁が垂れた芝の唇に見える）。「面取り」の言葉どおり内へ削ると板の形と変わる
    static func bevelRing(_ pts: [CampVec2], by d: Double) -> [CampVec2] {
        offset(pts, area(pts) > 0 ? d : -d)
    }

    /// 外へずらす（大きくなる方を選ぶ・板の切り絵の紙のフチ）
    static func outset(_ pts: [CampVec2], by d: Double) -> [CampVec2] {
        let a = offset(pts, d), b = offset(pts, -d)
        return abs(area(a)) > abs(area(b)) ? a : b
    }

    /// 角を 2 次のベジェで丸める（板の `rounded`）。`radius` は点ごと。`smooth` は丸めた点の印
    static func rounded(_ pts: [(CampVec2, Double)], segments: Int = 3) -> [(point: CampVec2, smooth: Bool)] {
        var out: [(point: CampVec2, smooth: Bool)] = []
        let n = pts.count
        for i in 0..<n {
            let (v, r) = pts[i]
            let p = pts[(i - 1 + n) % n].0, q = pts[(i + 1) % n].0
            guard r > 0 else { out.append((v, false)); continue }
            let d1 = hypot(v.x - p.x, v.y - p.y), d2 = hypot(q.x - v.x, q.y - v.y)
            let t1 = min(r, d1 / 2), t2 = min(r, d2 / 2)
            let a = CampVec2(v.x - (v.x - p.x) / d1 * t1, v.y - (v.y - p.y) / d1 * t1)
            let b = CampVec2(v.x + (q.x - v.x) / d2 * t2, v.y + (q.y - v.y) / d2 * t2)
            for k in 0...segments {
                let t = Double(k) / Double(segments)
                let x = (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * v.x + t * t * b.x
                let y = (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * v.y + t * t * b.y
                out.append((CampVec2(x, y), true))
            }
        }
        return out
    }

    /// 輪を重ねて筒を作る（板の `loft`）。面の向きは `inside` から外へ。`smooth` なら輪の方向になめらか
    /// `material` は帯（k）と辺（i）ごとに分けたいとき（帯の番号を返す）。返すのは帯ごとの網
    static func loft(_ rings: [[CampVec3]], inside: CampVec3, smooth: Bool = false, open: Bool = false,
                     uv: ((Int, Int) -> [CampVec2])? = nil, band: (Int, Int) -> Int = { k, _ in k },
                     colors: ((Int, Int) -> CampVec3)? = nil) -> [Int: CampMesh] {
        var out: [Int: CampMesh] = [:]
        guard let first = rings.first else { return out }
        let n = first.count
        // 面の法線（外向き）を先に出しておく（なめらかにするとき隣と平均する）
        var faceN: [[CampVec3]] = []
        for k in 0..<(rings.count - 1) {
            var row: [CampVec3] = []
            for i in 0..<n {
                let j = (i + 1) % n
                let q = [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]]
                var nn = newell(q)
                if nn.dot(centroid(q) - inside) < 0 { nn = -nn }
                row.append(nn)
            }
            faceN.append(row)
        }
        for k in 0..<(rings.count - 1) {
            for i in 0..<n {
                if open && i == n - 1 { continue }
                let j = (i + 1) % n
                let q = [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]]
                let key = band(k, i)
                var mesh = out[key] ?? CampMesh()
                let uvs = uv?(k, i)
                let color = colors?(k, i)
                if smooth {
                    let prev = (open && i == 0) ? faceN[k][i] : faceN[k][(i - 1 + n) % n]
                    let next = (open && j == 0) ? faceN[k][i] : faceN[k][j]
                    let ni = (prev + faceN[k][i]).normalized
                    let nj = (faceN[k][i] + next).normalized
                    mesh.smoothQuad(q, [ni, nj, nj, ni], uv: uvs, color: color)
                } else {
                    mesh.flatQuad(q[0], q[1], q[2], q[3], outward: faceN[k][i], uv: uvs, color: color)
                }
                out[key] = mesh
            }
        }
        return out
    }

    /// 縦の外形を軸のまわりに回して作る（板の `lathe`）。`profile` は (半径, 軸に沿った長さ)
    static func lathe(origin: CampVec3, axis: CampVec3, profile: [(Double, Double)], segments: Int,
                      capStart: Bool = false, capEnd: Bool = false, smooth: Bool = true,
                      rotation: Double = 0) -> CampMesh {
        let k = axis.normalized
        let ref = abs(k.y) < 0.9 ? CampVec3(0, 1, 0) : CampVec3(1, 0, 0)
        let e1 = k.cross(ref).normalized, e2 = k.cross(e1)
        let rings: [[CampVec3]] = profile.map { r, h in
            (0..<segments).map { i in
                let t = Double(i) / Double(segments) * 2 * .pi + rotation
                return origin + k * h + e1 * (cos(t) * r) + e2 * (sin(t) * r)
            }
        }
        var mesh = CampMesh()
        for kk in 0..<(profile.count - 1) {
            let dr = profile[kk + 1].0 - profile[kk].0, dh = profile[kk + 1].1 - profile[kk].1
            for i in 0..<segments {
                let j = (i + 1) % segments
                func radial(_ s: Int) -> CampVec3 {
                    let t = Double(s) / Double(segments) * 2 * .pi + rotation
                    let dir = e1 * cos(t) + e2 * sin(t)
                    return (dir * dh + k * (-dr)).normalized
                }
                let na = radial(i), nb = radial(i + 1)
                let u0 = Double(i) / Double(segments), u1 = Double(i + 1) / Double(segments)
                let v0 = Double(kk) / Double(profile.count - 1), v1 = Double(kk + 1) / Double(profile.count - 1)
                if profile[kk].0 < 0.001 {
                    let tip = origin + k * profile[kk].1
                    if smooth {
                        mesh.smoothTriangle([tip, rings[kk + 1][j], rings[kk + 1][i]], [(na + nb).normalized, nb, na],
                                            uv: [CampVec2((u0 + u1) / 2, v0), CampVec2(u1, v1), CampVec2(u0, v1)])
                    } else {
                        mesh.flatTriangle(tip, rings[kk + 1][j], rings[kk + 1][i], outward: (na + nb))
                    }
                } else if profile[kk + 1].0 < 0.001 {
                    let tip = origin + k * profile[kk + 1].1
                    if smooth {
                        mesh.smoothTriangle([rings[kk][i], rings[kk][j], tip], [na, nb, (na + nb).normalized],
                                            uv: [CampVec2(u0, v0), CampVec2(u1, v0), CampVec2((u0 + u1) / 2, v1)])
                    } else {
                        mesh.flatTriangle(rings[kk][i], rings[kk][j], tip, outward: (na + nb))
                    }
                } else {
                    let q = [rings[kk][i], rings[kk][j], rings[kk + 1][j], rings[kk + 1][i]]
                    let uvs = [CampVec2(u0, v0), CampVec2(u1, v0), CampVec2(u1, v1), CampVec2(u0, v1)]
                    if smooth {
                        mesh.smoothQuad(q, [na, nb, nb, na], uv: uvs)
                    } else {
                        mesh.flatQuad(q[0], q[1], q[2], q[3], outward: (na + nb), uv: uvs)
                    }
                }
            }
        }
        if capStart, profile.first!.0 > 0.001 { mesh.flatPolygon(rings[0], outward: -k) }
        if capEnd, profile.last!.0 > 0.001 { mesh.flatPolygon(rings[rings.count - 1], outward: k) }
        return mesh
    }

    /// 島のように、平らな外形（x と z）を y の向きに押し出した塊（面取りつき）。
    /// 返すのは 帯 → 網: 0 = 下の面取り・1 = 壁・2 = 上の面取り・3 = 上の面・4 = 底の面
    ///
    /// 壁の貼り絵の座標は u = 周の長さ / `uvScale`、v = y / 厚み（地層の線を y 9・14・19 に描ける）
    static func extrudeY(_ outline: [CampVec2], top: Double, bottom: Double, bevel b: Double,
                         uvScale: Double = 40) -> [Int: CampMesh] {
        let inner = b > 0 ? bevelRing(outline, by: b) : outline
        let ring = { (pts: [CampVec2], y: Double) in pts.map { CampVec3($0.x, y, $0.y) } }
        let rings = b > 0
            ? [ring(inner, bottom), ring(outline, bottom - b), ring(outline, top + b), ring(inner, top)]
            : [ring(outline, bottom), ring(outline, top)]
        let center = CampVec3(0, (top + bottom) / 2, 0)
        // 周の長さ（壁の貼り絵の u）
        var acc: [Double] = [0]
        for i in 0..<outline.count {
            let a = outline[i], c = outline[(i + 1) % outline.count]
            acc.append(acc[i] + hypot(c.x - a.x, c.y - a.y))
        }
        let thick = bottom - top
        let uv: (Int, Int) -> [CampVec2] = { k, i in
            let u0 = acc[i] / uvScale, u1 = acc[i + 1] / uvScale
            let y0 = rings[k][0].y, y1 = rings[k + 1][0].y
            let v0 = (y0 - top) / thick, v1 = (y1 - top) / thick
            return [CampVec2(u0, v0), CampVec2(u1, v0), CampVec2(u1, v1), CampVec2(u0, v1)]
        }
        let bands = loft(rings, inside: center, smooth: true, uv: uv, band: { k, _ in b > 0 ? k : 1 })
        var out = bands
        var topMesh = CampMesh(), bottomMesh = CampMesh()
        let topRing = rings[rings.count - 1], bottomRing = rings[0]
        topMesh.flatPolygon(topRing, outward: CampVec3(0, -1, 0), uv: topRing.map { CampVec2($0.x / uvScale, $0.z / uvScale) })
        bottomMesh.flatPolygon(bottomRing, outward: CampVec3(0, 1, 0))
        out[3] = topMesh
        out[4] = bottomMesh
        // 帯の番号を「下の面取り 0・壁 1・上の面取り 2」に揃える（面取りの無い形は壁だけ）
        return out
    }

    /// 平らな外形（u, v）を厚み方向（d）に押し出した板。`map(u, v, d)` で置き場所へ写す。
    /// 返すのは 表（d が正の側）・裏・縁 の 3 つ。表の貼り絵の座標は (u / w, v / h)
    static func slab(_ outline: [CampVec2], thickness: Double, size: CampVec2,
                     map: (Double, Double, Double) -> CampVec3) -> (front: CampMesh, back: CampMesh, edge: CampMesh) {
        let half = thickness / 2
        let frontPts = outline.map { map($0.x, $0.y, half) }
        let backPts = outline.map { map($0.x, $0.y, -half) }
        let normalFront = (map(0, 0, 1) - map(0, 0, 0)).normalized
        var front = CampMesh(), back = CampMesh(), edge = CampMesh()
        front.flatPolygon(frontPts, outward: normalFront,
                          uv: outline.map { CampVec2($0.x / size.x, $0.y / size.y) })
        back.flatPolygon(backPts, outward: -normalFront,
                         uv: outline.map { CampVec2(1 - $0.x / size.x, $0.y / size.y) })
        let center = map(size.x / 2, size.y / 2, 0)
        for i in outline.indices {
            let j = (i + 1) % outline.count
            let q = [frontPts[i], frontPts[j], backPts[j], backPts[i]]
            let mid = centroid(q)
            // 縁の外向き（板の中心から離れる向き・板の面に沿う）
            var out = mid - center
            out = out - normalFront * out.dot(normalFront)
            edge.flatQuad(q[0], q[1], q[2], q[3], outward: out)
        }
        return (front, back, edge)
    }

    /// 凸包（板の `hull2`。落ち影の形を作る）
    static func hull(_ pts: [CampVec2]) -> [CampVec2] {
        let p = pts.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard p.count > 2 else { return p }
        func cross(_ o: CampVec2, _ a: CampVec2, _ b: CampVec2) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CampVec2] = [], upper: [CampVec2] = []
        for q in p {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}

/// 決まった並びの乱数（板の `rnd`: seed × 16807 mod 2³¹−1）。同じ島は何度描いても同じ形
struct CampRandom: Sendable {
    private var seed: Int

    init(_ seed: Int) { self.seed = seed }

    mutating func next() -> Double {
        seed = (seed * 16807) % 2_147_483_647
        return Double(seed - 1) / 2_147_483_646
    }
}
