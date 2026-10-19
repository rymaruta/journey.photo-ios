import Foundation

/// 立体の持ち手の網（2026-10-19）。
///
/// 前は `SCNShape` に、下の辺を共有した外と内の角丸を even-odd で穴にして押し出していた。
/// その割れ目の三角が蓋の革の粒を持ち手の前後の面に乗せ、穴の中にトゲを出し、縫い目が内側の縁だけに伸びていた。
/// ここは中心線に帯を沿わせて自分で組む。前後の面だけが持ち手の絵（0〜1）、壁は1色、縫い目は外側の破線。
struct TrunkHandleMesh: Equatable {

    struct Vertex: Equatable {
        var x, y, z: Double
        var nx, ny, nz: Double
        var u, v: Double
    }

    /// 前後の面（持ち手の絵を貼る）
    var caps: [Vertex]
    var capIndices: [Int]
    /// 外側・内側・足の底（1色。蓋の絵は貼らない）
    var walls: [Vertex]
    var wallIndices: [Int]
    /// 上から見える縫い目（外側の面の真ん中）。縫わない型は空
    var stitch: [Vertex]
    var stitchIndices: [Int]

    /// 2D の持ち手と同じ外形（幅 100・高さ 36・帯 10・上の角 22）。`depth` は前後の厚み（点）
    static func make(depth: Double, stitched: Bool, band: Double = 10) -> TrunkHandleMesh {
        let halfZ = max(0.5, depth) / 2
        let halfBand = band / 2
        let line = centerline(band: band)
        var caps = MeshBuilder()
        var walls = MeshBuilder()

        func corner(_ s: LinePoint, _ outward: Double, _ z: Double) -> (Double, Double, Double) {
            (s.x + s.ox * halfBand * outward, s.y + s.oy * halfBand * outward, z)
        }

        for i in 0..<(line.count - 1) {
            let a = line[i], b = line[i + 1]
            let facing = ((a.ox + b.ox) / 2, (a.oy + b.oy) / 2, 0.0)
            // 外側
            let o0 = walls.add(corner(a, 1, halfZ), normal: (a.ox, a.oy, 0))
            let o1 = walls.add(corner(a, 1, -halfZ), normal: (a.ox, a.oy, 0))
            let o2 = walls.add(corner(b, 1, halfZ), normal: (b.ox, b.oy, 0))
            let o3 = walls.add(corner(b, 1, -halfZ), normal: (b.ox, b.oy, 0))
            walls.quad(o0, o2, o3, o1, facing: facing)
            // 内側
            let i0 = walls.add(corner(a, -1, halfZ), normal: (-a.ox, -a.oy, 0))
            let i1 = walls.add(corner(a, -1, -halfZ), normal: (-a.ox, -a.oy, 0))
            let i2 = walls.add(corner(b, -1, halfZ), normal: (-b.ox, -b.oy, 0))
            let i3 = walls.add(corner(b, -1, -halfZ), normal: (-b.ox, -b.oy, 0))
            walls.quad(i0, i1, i3, i2, facing: (-facing.0, -facing.1, 0))
            // 正面（+z）と背面（-z）。絵は持ち手の枠（幅 100・高さ 36）に合わせる
            func capUV(_ p: (Double, Double, Double)) -> (Double, Double) {
                ((p.0 + 50) / 100, p.1 / 36)
            }
            let f0 = corner(a, 1, halfZ), f1 = corner(b, 1, halfZ)
            let f2 = corner(b, -1, halfZ), f3 = corner(a, -1, halfZ)
            let c0 = caps.add(f0, normal: (0, 0, 1), uv: capUV(f0))
            let c1 = caps.add(f1, normal: (0, 0, 1), uv: capUV(f1))
            let c2 = caps.add(f2, normal: (0, 0, 1), uv: capUV(f2))
            let c3 = caps.add(f3, normal: (0, 0, 1), uv: capUV(f3))
            caps.quad(c0, c1, c2, c3, facing: (0, 0, 1))
            let b0 = corner(a, 1, -halfZ), b1 = corner(b, 1, -halfZ)
            let b2 = corner(b, -1, -halfZ), b3 = corner(a, -1, -halfZ)
            let d0 = caps.add(b0, normal: (0, 0, -1), uv: capUV(b0))
            let d1 = caps.add(b1, normal: (0, 0, -1), uv: capUV(b1))
            let d2 = caps.add(b2, normal: (0, 0, -1), uv: capUV(b2))
            let d3 = caps.add(b3, normal: (0, 0, -1), uv: capUV(b3))
            caps.quad(d0, d3, d2, d1, facing: (0, 0, -1))
        }

        // 足の底（胴に 6pt 埋まる側）。開いたままにしない
        for (index, sign) in [(0, -1.0), (line.count - 1, 1.0)] {
            let s = line[index]
            let n = (s.tx * sign, s.ty * sign, 0.0)
            let p0 = walls.add(corner(s, 1, halfZ), normal: n)
            let p1 = walls.add(corner(s, 1, -halfZ), normal: n)
            let p2 = walls.add(corner(s, -1, -halfZ), normal: n)
            let p3 = walls.add(corner(s, -1, halfZ), normal: n)
            walls.quad(p0, p3, p2, p1, facing: n)
        }

        let stitchMesh = stitched ? stitchDashes(along: line, halfBand: halfBand) : MeshBuilder()
        return TrunkHandleMesh(caps: caps.vertices, capIndices: caps.indices,
                               walls: walls.vertices, wallIndices: walls.indices,
                               stitch: stitchMesh.vertices, stitchIndices: stitchMesh.indices)
    }

    /// 付け根の金具。面取りの箱は絵の座標が潰れて単色の塊になったので、6面を自分で貼る
    static func clip(width: Double = 20, height: Double = 14, depth: Double) -> (vertices: [Vertex], indices: [Int]) {
        let w = width / 2, h = height / 2, d = depth / 2
        var mesh = MeshBuilder()
        func face(_ corners: [(Double, Double, Double)], _ normal: (Double, Double, Double)) {
            let uv = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
            let ids = zip(corners, uv).map { mesh.add($0.0, normal: normal, uv: $0.1) }
            mesh.quad(ids[0], ids[1], ids[2], ids[3], facing: normal)
        }
        face([(-w, -h, d), (w, -h, d), (w, h, d), (-w, h, d)], (0, 0, 1))
        face([(w, -h, -d), (-w, -h, -d), (-w, h, -d), (w, h, -d)], (0, 0, -1))
        face([(-w, h, d), (w, h, d), (w, h, -d), (-w, h, -d)], (0, 1, 0))
        face([(-w, -h, -d), (w, -h, -d), (w, -h, d), (-w, -h, d)], (0, -1, 0))
        face([(w, -h, d), (w, -h, -d), (w, h, -d), (w, h, d)], (1, 0, 0))
        face([(-w, -h, -d), (-w, -h, d), (-w, h, d), (-w, h, -d)], (-1, 0, 0))
        return (mesh.vertices, mesh.indices)
    }

    /// 帯の中心（左の足から右の足へ）。`ox, oy` は穴の反対（外）
    static func centerline(band: Double = 10) -> [LinePoint] {
        let radius = 22.0
        let height = 36.0
        let halfSpan = 50.0
        let inset = band / 2
        let curve = radius - inset
        let cornerX = halfSpan - radius
        let cornerY = height - radius
        let sideX = halfSpan - inset
        var raw: [(Double, Double, Double, Double, Double, Double)] = []

        let legSteps = 4
        for i in 0...legSteps {
            let y = cornerY * Double(i) / Double(legSteps)
            raw.append((-sideX, y, 0, 1, -1, 0))
        }
        let arcSteps = 16
        for i in 1...arcSteps {
            let t = Double.pi - (Double.pi / 2) * Double(i) / Double(arcSteps)
            raw.append(arc(centerX: -cornerX, centerY: cornerY, radius: curve, angle: t, decreasing: true))
        }
        let topSteps = 8
        for i in 1...topSteps {
            let x = -cornerX + (cornerX * 2) * Double(i) / Double(topSteps)
            raw.append((x, cornerY + curve, 1, 0, 0, 1))
        }
        for i in 1...arcSteps {
            let t = (Double.pi / 2) * (1 - Double(i) / Double(arcSteps))
            raw.append(arc(centerX: cornerX, centerY: cornerY, radius: curve, angle: t, decreasing: true))
        }
        for i in 1...legSteps {
            let y = cornerY * (1 - Double(i) / Double(legSteps))
            raw.append((sideX, y, 0, -1, 1, 0))
        }

        var out: [LinePoint] = []
        var distance = 0.0
        for (i, p) in raw.enumerated() {
            if i > 0 {
                let q = raw[i - 1]
                distance += hypot(p.0 - q.0, p.1 - q.1)
            }
            out.append(LinePoint(x: p.0, y: p.1, tx: p.2, ty: p.3, ox: p.4, oy: p.5, distance: distance))
        }
        return out
    }

    struct LinePoint: Equatable {
        var x, y: Double
        var tx, ty: Double
        var ox, oy: Double
        var distance: Double
    }

    // MARK: - 縫い目

    /// 外側の面の真ん中に、3pt の線と 2pt の空き（正面の持ち手の破線と同じ刻み）
    private static func stitchDashes(along line: [LinePoint], halfBand: Double) -> MeshBuilder {
        guard let last = line.last else { return MeshBuilder() }
        let dash = 3.0, gap = 2.0, lift = 0.8, halfWidth = 0.5
        var mesh = MeshBuilder()
        var s = 1.0
        while s + dash < last.distance - 1 {
            guard let a = sample(line, s), let b = sample(line, s + dash) else { break }
            func point(_ p: LinePoint, _ z: Double) -> (Double, Double, Double) {
                (p.x + p.ox * (halfBand + lift), p.y + p.oy * (halfBand + lift), z)
            }
            let n = ((a.ox + b.ox) / 2, (a.oy + b.oy) / 2, 0.0)
            let p0 = mesh.add(point(a, -halfWidth), normal: (a.ox, a.oy, 0))
            let p1 = mesh.add(point(b, -halfWidth), normal: (b.ox, b.oy, 0))
            let p2 = mesh.add(point(b, halfWidth), normal: (b.ox, b.oy, 0))
            let p3 = mesh.add(point(a, halfWidth), normal: (a.ox, a.oy, 0))
            mesh.quad(p0, p1, p2, p3, facing: n)
            s += dash + gap
        }
        return mesh
    }

    private static func sample(_ line: [LinePoint], _ distance: Double) -> LinePoint? {
        guard let first = line.first, let last = line.last else { return nil }
        if distance <= first.distance { return first }
        if distance >= last.distance { return last }
        var lo = 0, hi = line.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if line[mid].distance < distance { lo = mid } else { hi = mid }
        }
        let a = line[lo], b = line[hi]
        let span = b.distance - a.distance
        let t = span > 1e-6 ? (distance - a.distance) / span : 0
        func mix(_ p: Double, _ q: Double) -> Double { p + (q - p) * t }
        var ox = mix(a.ox, b.ox), oy = mix(a.oy, b.oy)
        let ol = hypot(ox, oy)
        if ol > 1e-6 { ox /= ol; oy /= ol }
        var tx = mix(a.tx, b.tx), ty = mix(a.ty, b.ty)
        let tl = hypot(tx, ty)
        if tl > 1e-6 { tx /= tl; ty /= tl }
        return LinePoint(x: mix(a.x, b.x), y: mix(a.y, b.y), tx: tx, ty: ty, ox: ox, oy: oy, distance: distance)
    }

    /// 円弧の1点。`decreasing` は角度が減る向き（左の足から右の足へ進む）
    private static func arc(centerX: Double, centerY: Double, radius: Double, angle: Double,
                            decreasing: Bool) -> (Double, Double, Double, Double, Double, Double) {
        let c = cos(angle), s = sin(angle)
        let x = centerX + c * radius, y = centerY + s * radius
        // 進む向きは -d/dθ（角度が減る）= (sin θ, -cos θ)
        let tx = decreasing ? s : -s
        let ty = decreasing ? -c : c
        let len = hypot(tx, ty)
        return (x, y, tx / len, ty / len, c, s)
    }
}

/// 三角を足す。向きは外を向く法線に合わせ、潰れた三角は捨てる
private struct MeshBuilder {
    var vertices: [TrunkHandleMesh.Vertex] = []
    var indices: [Int] = []

    mutating func add(_ p: (Double, Double, Double), normal: (Double, Double, Double),
                      uv: (Double, Double) = (0, 0)) -> Int {
        let len = (normal.0 * normal.0 + normal.1 * normal.1 + normal.2 * normal.2).squareRoot()
        let n = len > 1e-8 ? (normal.0 / len, normal.1 / len, normal.2 / len) : (0.0, 1.0, 0.0)
        vertices.append(TrunkHandleMesh.Vertex(x: p.0, y: p.1, z: p.2, nx: n.0, ny: n.1, nz: n.2, u: uv.0, v: uv.1))
        return vertices.count - 1
    }

    mutating func quad(_ a: Int, _ b: Int, _ c: Int, _ d: Int, facing: (Double, Double, Double)) {
        triangle(a, b, c, facing: facing)
        triangle(a, c, d, facing: facing)
    }

    private mutating func triangle(_ a: Int, _ b: Int, _ c: Int, facing: (Double, Double, Double)) {
        let n = cross(a, b, c)
        let area = (n.0 * n.0 + n.1 * n.1 + n.2 * n.2).squareRoot()
        if area < 1e-4 { return }
        let dot = n.0 * facing.0 + n.1 * facing.1 + n.2 * facing.2
        if dot < 0 {
            indices += [a, c, b]
        } else {
            indices += [a, b, c]
        }
    }

    private func cross(_ a: Int, _ b: Int, _ c: Int) -> (Double, Double, Double) {
        let p = vertices[a], q = vertices[b], r = vertices[c]
        let ux = q.x - p.x, uy = q.y - p.y, uz = q.z - p.z
        let vx = r.x - p.x, vy = r.y - p.y, vz = r.z - p.z
        return (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
    }
}
