import Foundation

// 家具を組む形の道具（2026-10-19）。owner「アーティファクトの家具はホンモノ感が足りない」: 箱を並べただけにしない。
// - 角を丸めた箱（面取りの丸みを本当の曲面で。向きもなめらか）
// - ふくらんだ箱（クッション・布団・枕。面の真ん中がふくらみ、縁は縫い目で締まる）
// - 管（金具・脚・腕・紐。道筋に沿って丸い断面を流す）
// - 旋盤（`CamperMeshKit.lathe`）・板の押し出し（`CamperMeshKit.extrude`）は外まわりのものを使う
// どれも素の Swift の網（`CamperMesh`）なので、Linux で形と三角形の数を試験できる。

enum CamperRoomMeshKit {

    // MARK: 写す

    /// 回して（Y の軸）動かす
    static func placed(_ m: CamperMesh, at t: CV3, yaw: Double = 0) -> CamperMesh {
        let q = CQuat.axisAngle(CV3(0, 1, 0), yaw)
        return m.mapped({ q.rotate($0) + t }, normal: { q.rotate($0) })
    }

    /// 向きを変えて動かす
    static func placed(_ m: CamperMesh, at t: CV3, rotation q: CQuat) -> CamperMesh {
        m.mapped({ q.rotate($0) + t }, normal: { q.rotate($0) })
    }

    /// 大きさを変える（向きは逆の比で直す）
    static func scaled(_ m: CamperMesh, _ s: CV3) -> CamperMesh {
        let mirror = s.x * s.y * s.z < 0
        return m.mapped({ CV3($0.x * s.x, $0.y * s.y, $0.z * s.z) }, normal: { CV3($0.x / s.x, $0.y / s.y, $0.z / s.z).normalized },
                        mirror: mirror)
    }

    /// 貼り絵の位置を付け直す（面の向きで軸の平面に投げ、`scale` 単位で 1 回）
    static func reUV(_ m: CamperMesh, scale: Double) -> CamperMesh {
        var out = m
        out.uvs = zip(m.positions, m.normals).map { CamperMesh.uv($0, $1, scale: scale) }
        return out
    }

    /// 裏返す（向きを逆に・巻きも逆に）。旋盤の内側の面（器の内・笠の内）に使う
    static func inverted(_ m: CamperMesh) -> CamperMesh {
        var out = m
        out.normals = m.normals.map { -$0 }
        out.groups = m.groups.map { g in
            var idx = g.indices
            var k = 0
            while k + 2 < idx.count {
                idx.swapAt(k + 1, k + 2)
                k += 3
            }
            return (g.material, idx)
        }
        return out
    }

    /// 器（外の面は `outer`、内の面は `inner` の断面。どちらも下から上へ。内は内向き）。縁は外と内をつなぐ
    static func vessel(outer: [CV2], inner: [CV2], segments: Int = 24, _ m: CamperMaterial, innerMaterial: CamperMaterial? = nil) -> CamperMesh {
        var parts = [lathe(outer, segments: segments, m, capStart: true, capEnd: false)]
        parts.append(inverted(lathe(inner, segments: segments, innerMaterial ?? m, capStart: true, capEnd: false)))
        // 縁（外の上の端から内の上の端へ・上向き）。高さは外の端にそろえる
        if let a = outer.last, let b = inner.last {
            parts.append(lathe([a, CV2(b.x, a.y)], segments: segments, m, capStart: false, capEnd: false))
        }
        return merge(parts)
    }

    /// 面積ゼロ（辺の外積が `epsilon` 未満）の三角形を落とす。点は残す（番号を付け直さない）
    static func droppingDegenerate(_ m: CamperMesh) -> CamperMesh {
        let epsilon = 1e-9
        var out = m
        out.groups = m.groups.map { g in
            var kept: [Int32] = []
            kept.reserveCapacity(g.indices.count)
            var i = 0
            while i + 2 < g.indices.count {
                let a = m.positions[Int(g.indices[i])], b = m.positions[Int(g.indices[i + 1])], c = m.positions[Int(g.indices[i + 2])]
                if (b - a).cross(c - a).length >= epsilon {
                    kept.append(g.indices[i])
                    kept.append(g.indices[i + 1])
                    kept.append(g.indices[i + 2])
                }
                i += 3
            }
            return (g.material, kept)
        }.filter { !$0.indices.isEmpty }
        return out
    }

    /// 網をまとめる
    static func merge(_ parts: [CamperMesh]) -> CamperMesh {
        var out = CamperMesh()
        for p in parts { out.append(p) }
        return out
    }

    /// 材質を替える
    static func recolored(_ m: CamperMesh, _ f: (CamperMaterial) -> CamperMaterial) -> CamperMesh {
        var out = CamperMesh()
        out.positions = m.positions
        out.normals = m.normals
        out.uvs = m.uvs
        var groups: [(material: CamperMaterial, indices: [Int32])] = []
        for g in m.groups {
            let mm = f(g.material)
            if let i = groups.firstIndex(where: { $0.material == mm }) { groups[i].indices += g.indices } else { groups.append((mm, g.indices)) }
        }
        out.groups = groups
        return out
    }

    // MARK: 角を丸めた箱・ふくらんだ箱

    /// 角を丸めた箱（真ん中が原点・幅 X・高さ Y・奥行き Z）。`radius` は角の丸み、`segments` は丸みの段数。
    /// `puff` は上下の面の真ん中のふくらみ（クッション・布団）、`sidePuff` は横の面のふくらみ。
    /// `material` は面の向き（外向きの軸）ごとの材質
    static func roundedBox(_ size: CV3, radius r0: Double, segments: Int = 3, puff: Double = 0, sidePuff: Double = 0,
                           material: (CV3) -> CamperMaterial) -> CamperMesh {
        let h = CV3(size.x / 2, size.y / 2, size.z / 2)
        let r = max(0.001, min(r0, min(h.x, min(h.y, h.z)) * 0.999))
        let n = max(1, segments)
        /// 1 つの軸の座標の並び（端の丸み n 段・真ん中は `mid` 段）
        func axis(_ half: Double, mid: Int) -> [Double] {
            var out: [Double] = []
            for k in 0...n { out.append(-(half - r) - r * cos(Double(k) / Double(n) * .pi / 2)) }
            for k in 1..<mid { out.append(-(half - r) + 2 * (half - r) * Double(k) / Double(mid)) }
            for k in 0...n { out.append((half - r) + r * sin(Double(k) / Double(n) * .pi / 2)) }
            return out
        }
        let midX = puff > 0 || sidePuff > 0 ? 6 : 1, midY = sidePuff > 0 ? 4 : 1, midZ = puff > 0 || sidePuff > 0 ? 6 : 1
        let ax = axis(h.x, mid: midX), ay = axis(h.y, mid: midY), az = axis(h.z, mid: midZ)
        func surface(_ p: CV3) -> CV3 {
            let inner = CV3(max(-(h.x - r), min(h.x - r, p.x)), max(-(h.y - r), min(h.y - r, p.y)), max(-(h.z - r), min(h.z - r, p.z)))
            var d = p - inner
            if d.length < 1e-9 { d = CV3(0, 1, 0) }
            var q = inner + d.normalized * r
            // ふくらみ: 面の真ん中ほど外へ（縁 0・真ん中 1）
            if puff > 0 {
                let u = max(0, 1 - pow(q.x / h.x, 2)), w = max(0, 1 - pow(q.z / h.z, 2))
                // 下の面は載っている物に押されて、上の 3 分の 1 ほどしかふくらまない
                q.y += (q.y > 0 ? 1 : -0.35) * puff * u * w * min(1, abs(q.y) / h.y)
            }
            if sidePuff > 0 {
                let v = max(0, 1 - pow(q.y / h.y, 2))
                let ux = max(0, 1 - pow(q.z / h.z, 2)), uz = max(0, 1 - pow(q.x / h.x, 2))
                q.x += (q.x > 0 ? 1 : -1) * sidePuff * v * ux * min(1, abs(q.x) / h.x)
                q.z += (q.z > 0 ? 1 : -1) * sidePuff * v * uz * min(1, abs(q.z) / h.z)
            }
            return q
        }
        var mesh = CamperMesh()
        // 6 面: (外向き, 面の u 軸の並び, v 軸の並び, 点を作る)
        let faces: [(CV3, [Double], [Double], (Double, Double) -> CV3)] = [
            (CV3(0, 1, 0), ax, az, { CV3($0, h.y, $1) }), (CV3(0, -1, 0), ax, az, { CV3($0, -h.y, $1) }),
            (CV3(1, 0, 0), az, ay, { CV3(h.x, $1, $0) }), (CV3(-1, 0, 0), az, ay, { CV3(-h.x, $1, $0) }),
            (CV3(0, 0, 1), ax, ay, { CV3($0, $1, h.z) }), (CV3(0, 0, -1), ax, ay, { CV3($0, $1, -h.z) }),
        ]
        for (out, us, vs, point) in faces {
            let m = material(out)
            let grid = vs.map { v in us.map { u in surface(point(u, v)) } }
            func normal(_ i: Int, _ j: Int) -> CV3 {
                let a = grid[j][min(i + 1, us.count - 1)] - grid[j][max(i - 1, 0)]
                let b = grid[min(j + 1, vs.count - 1)][i] - grid[max(j - 1, 0)][i]
                var nn = a.cross(b)
                if nn.dot(out) < 0 { nn = -nn }
                if nn.length < 1e-9 {
                    // 角の点（四隅が縮んだ所）は、真ん中からの向き
                    nn = grid[j][i]
                }
                return nn.normalized
            }
            for j in 0..<(vs.count - 1) {
                for i in 0..<(us.count - 1) {
                    let p00 = grid[j][i], p10 = grid[j][i + 1], p11 = grid[j + 1][i + 1], p01 = grid[j + 1][i]
                    mesh.quad(p00, p10, p11, p01, normal(i, j), normal(i + 1, j), normal(i + 1, j + 1), normal(i, j + 1), m)
                }
            }
        }
        return mesh
    }

    static func roundedBox(_ size: CV3, radius: Double, segments: Int = 3, puff: Double = 0, sidePuff: Double = 0,
                           _ m: CamperMaterial) -> CamperMesh {
        roundedBox(size, radius: radius, segments: segments, puff: puff, sidePuff: sidePuff, material: { _ in m })
    }

    /// 角を丸めた箱を、下の面の真ん中が `at` に来るように置く
    static func block(_ size: CV3, at p: CV3, radius: Double, segments: Int = 2, _ m: CamperMaterial) -> CamperMesh {
        placed(roundedBox(size, radius: radius, segments: segments, m), at: p + CV3(0, size.y / 2, 0))
    }

    // MARK: 管・旋盤

    /// 管（道筋 `path` に沿って半径 `radius` の丸い断面を流す）。`closed` なら輪。端は蓋をする
    static func tube(_ path: [CV3], radius: Double, sides: Int = 10, closed: Bool = false, cap: Bool = true,
                     _ m: CamperMaterial) -> CamperMesh {
        var mesh = CamperMesh()
        guard path.count >= 2 else { return mesh }
        let count = path.count
        func tangent(_ i: Int) -> CV3 {
            if closed {
                return (path[(i + 1) % count] - path[(i - 1 + count) % count]).normalized
            }
            let a = path[max(0, i - 1)], b = path[min(count - 1, i + 1)]
            return (b - a).normalized
        }
        // 平行に運ぶ枠（ねじれない）
        var normals: [CV3] = []
        var t0 = tangent(0)
        var n0 = abs(t0.y) < 0.9 ? t0.cross(CV3(0, 1, 0)).normalized : t0.cross(CV3(1, 0, 0)).normalized
        normals.append(n0)
        for i in 1..<count {
            let t1 = tangent(i)
            let q = CQuat.rotation(from: t0, to: t1)
            n0 = q.rotate(n0).normalized
            normals.append(n0)
            t0 = t1
        }
        let rings: [[(CV3, CV3)]] = (0..<count).map { i in
            let t = tangent(i), nn = normals[i], b = t.cross(nn).normalized
            return (0..<sides).map { k in
                let a = Double(k) / Double(sides) * 2 * .pi
                let dir = nn * cos(a) + b * sin(a)
                return (path[i] + dir * radius, dir)
            }
        }
        let segs = closed ? count : count - 1
        for i in 0..<segs {
            let r0 = rings[i], r1 = rings[(i + 1) % count]
            for k in 0..<sides {
                let k1 = (k + 1) % sides
                mesh.quad(r0[k].0, r0[k1].0, r1[k1].0, r1[k].0, r0[k].1, r0[k1].1, r1[k1].1, r1[k].1, m)
            }
        }
        if cap, !closed {
            for (i, sign) in [(0, -1.0), (count - 1, 1.0)] {
                let nn = tangent(i) * sign
                for k in 0..<sides { mesh.tri(path[i], rings[i][k].0, rings[i][(k + 1) % sides].0, normal: nn, m) }
            }
        }
        return mesh
    }

    /// 円弧の点（中心・半径・始めと終わりの角度。XY の面）
    static func arc(center: CV3, radius: Double, from a0: Double, to a1: Double, steps: Int = 12) -> [CV3] {
        (0...steps).map { k in
            let a = a0 + (a1 - a0) * Double(k) / Double(steps)
            return center + CV3(cos(a) * radius, sin(a) * radius, 0)
        }
    }

    /// 水平の輪の点（中心 `center` のまわり・XZ の面・高さは `center.y`）。笠の縁・帽子の帯・硝子球の帯に。
    ///
    /// 2026-10-21 判断（owner「家具ぶっ壊れてる」）: `arc(center:)` は XY の面の点なので、`.map { CV3($0.x, y, $0.y) }` で
    /// 寝かせると中心の**高さ**が奥行き（Z）に移り、輪が家具から何十も離れて宙に浮いた（弧の灯り・コート掛け・硝子球の吊り鉢）。
    /// 寝かせた輪はこれで作る
    static func ringXZ(center: CV3, radius: Double, steps: Int = 24) -> [CV3] {
        arc(center: .zero, radius: radius, from: 0, to: 2 * .pi, steps: steps).map { CV3(center.x + $0.x, center.y, center.z + $0.y) }
    }

    /// 旋盤（断面は 半径, 高さ）。外まわりの `CamperMeshKit.lathe` に材質を 1 つで
    static func lathe(_ profile: [CV2], segments: Int = 24, _ m: CamperMaterial, capStart: Bool = true, capEnd: Bool = true) -> CamperMesh {
        CamperMeshKit.lathe(profile, segments: segments, material: { _ in m }, capStart: capStart ? m : nil, capEnd: capEnd ? m : nil)
    }

    /// 縁を丸めた円柱（下の面が y = 0）
    static func disc(radius: Double, height: Double, bevel: Double, segments: Int = 28, _ m: CamperMaterial) -> CamperMesh {
        let b = min(bevel, height / 2, radius / 2)
        var profile = [CV2(0, 0), CV2(radius - b, 0)]
        for k in 1...3 {
            let a = Double(k) / 3 * .pi / 2
            profile.append(CV2(radius - b + sin(a) * b, b - cos(a) * b))
        }
        profile.append(CV2(radius, height - b))
        for k in 1...3 {
            let a = Double(k) / 3 * .pi / 2
            profile.append(CV2(radius - b + cos(a) * b, height - b + sin(a) * b))
        }
        profile.append(CV2(0, height))
        return lathe(profile, segments: segments, m, capStart: false, capEnd: false)
    }

    /// 先の細る脚（下の半径・上の半径・高さ。下の面が y = 0）
    static func leg(bottom: Double, top: Double, height: Double, segments: Int = 14, _ m: CamperMaterial) -> CamperMesh {
        lathe([CV2(0, 0), CV2(bottom * 0.85, 0), CV2(bottom, bottom * 0.3), CV2(top, height - top * 0.3), CV2(top * 0.85, height), CV2(0, height)],
              segments: segments, m, capStart: false, capEnd: false)
    }

    /// 球
    static func sphere(radius: Double, segments: Int = 18, _ m: CamperMaterial) -> CamperMesh {
        let rows = max(4, segments / 2)
        let profile = (0...rows).map { k -> CV2 in
            let a = -Double.pi / 2 + Double(k) / Double(rows) * .pi
            return CV2(cos(a) * radius, sin(a) * radius)
        }
        return lathe(profile, segments: segments, m, capStart: false, capEnd: false)
    }

    // MARK: 布

    /// ひだのある布（幅 `width`・丈 `height`・ひだの数 `folds`・深さ `depth`）。上の辺が y = 0 で下へ垂れる。
    /// 裾は少し広がり、ひだは上で細かく下でゆるい（本物の布のたわみ）。表は +Z
    static func drape(width: Double, height: Double, folds: Int, depth: Double, flare: Double = 0.25, _ m: CamperMaterial) -> CamperMesh {
        var mesh = CamperMesh()
        let cols = max(8, folds * 6), rows = 10
        func p(_ i: Int, _ j: Int) -> CV3 {
            let u = Double(i) / Double(cols), v = Double(j) / Double(rows)
            let spread = 1 + flare * v
            let x = (u - 0.5) * width * spread
            let wave = sin(u * Double(folds) * 2 * .pi) * depth * (0.55 + 0.45 * v)
            let hemLift = v > 0.92 ? (v - 0.92) * 0.5 * height * abs(sin(u * Double(folds) * .pi)) * 0.15 : 0
            return CV3(x, -v * height + hemLift, wave)
        }
        let grid = (0...rows).map { j in (0...cols).map { i in p(i, j) } }
        func nrm(_ i: Int, _ j: Int) -> CV3 {
            let a = grid[j][min(cols, i + 1)] - grid[j][max(0, i - 1)]
            let b = grid[max(0, j - 1)][i] - grid[min(rows, j + 1)][i]
            return a.cross(b).normalized
        }
        for j in 0..<rows {
            for i in 0..<cols {
                mesh.quad(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i],
                          nrm(i, j), nrm(i + 1, j), nrm(i + 1, j + 1), nrm(i, j + 1), m)
            }
        }
        return mesh
    }

    // MARK: 平らな面（貼り絵の位置 0〜1 を付ける・写真・敷物・文字盤）

    /// 四角い面（真ん中が原点・+Z 向き）。貼り絵は 0〜1 で 1 回
    static func panel(width: Double, height: Double, _ m: CamperMaterial) -> CamperMesh {
        var mesh = CamperMesh()
        let w = width / 2, h = height / 2
        mesh.positions = [CV3(-w, -h, 0), CV3(w, -h, 0), CV3(w, h, 0), CV3(-w, h, 0)]
        mesh.normals = Array(repeating: CV3(0, 0, 1), count: 4)
        mesh.uvs = [CV2(0, 1), CV2(1, 1), CV2(1, 0), CV2(0, 0)]
        mesh.groups = [(m, [0, 1, 2, 0, 2, 3])]
        return mesh
    }

    /// 楕円・丸の面（真ん中が原点・+Z 向き・貼り絵は外接の四角で 0〜1）
    static func ellipsePanel(rx: Double, ry: Double, steps: Int = 40, _ m: CamperMaterial) -> CamperMesh {
        var mesh = CamperMesh()
        mesh.positions = [CV3(0, 0, 0)]
        mesh.uvs = [CV2(0.5, 0.5)]
        var idx: [Int32] = []
        for k in 0..<steps {
            let a = Double(k) / Double(steps) * 2 * .pi
            mesh.positions.append(CV3(cos(a) * rx, sin(a) * ry, 0))
            mesh.uvs.append(CV2(0.5 + cos(a) * 0.5, 0.5 - sin(a) * 0.5))
        }
        for k in 0..<steps { idx += [0, Int32(1 + k), Int32(1 + (k + 1) % steps)] }
        mesh.normals = Array(repeating: CV3(0, 0, 1), count: mesh.positions.count)
        mesh.groups = [(m, idx)]
        return mesh
    }

    /// 厚みのある敷物（輪郭 `outline` の板・縁は丸く落ちる・表の貼り絵は外接の四角で 0〜1）。床の上に寝かせる（+Y が表）
    static func rug(_ outline: [CV2], thickness: Double, top: CamperMaterial, edge: CamperMaterial) -> CamperMesh {
        let ccw = CamperPolygon.ccw(outline)
        let xs = ccw.map(\.x), ys = ccw.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1, minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let inset = CamperPolygon.offset(ccw, by: -thickness * 0.8)
        var mesh = CamperMesh()
        let tris = CamperPolygon.triangulate(outer: inset)
        var faceMesh = CamperMesh()
        for t in stride(from: 0, to: tris.count - 2, by: 3) {
            faceMesh.tri(CV3(tris[t].x, thickness, tris[t].y), CV3(tris[t + 1].x, thickness, tris[t + 1].y),
                         CV3(tris[t + 2].x, thickness, tris[t + 2].y), normal: CV3(0, 1, 0), top)
        }
        faceMesh.uvs = faceMesh.positions.map { CV2(($0.x - minX) / max(1e-6, maxX - minX), ($0.z - minY) / max(1e-6, maxY - minY)) }
        mesh.append(faceMesh)
        // 縁: 表の縁から床へ丸く落ちる帯
        let n = ccw.count
        for i in 0..<n {
            let a0 = inset[i], a1 = inset[(i + 1) % n], b0 = ccw[i], b1 = ccw[(i + 1) % n]
            let out0 = CV3(b0.x - a0.x, 0, b0.y - a0.y).normalized, out1 = CV3(b1.x - a1.x, 0, b1.y - a1.y).normalized
            let mid0 = CV3((a0.x + b0.x) / 2, thickness * 0.75, (a0.y + b0.y) / 2), mid1 = CV3((a1.x + b1.x) / 2, thickness * 0.75, (a1.y + b1.y) / 2)
            let up = CV3(0, 1, 0)
            mesh.quad(CV3(a0.x, thickness, a0.y), mid0, mid1, CV3(a1.x, thickness, a1.y),
                      (up + out0 * 0.5).normalized, (up + out0).normalized, (up + out1).normalized, (up + out1 * 0.5).normalized, edge)
            mesh.quad(mid0, CV3(b0.x, 0, b0.y), CV3(b1.x, 0, b1.y), mid1, (up + out0).normalized, out0, out1, (up + out1).normalized, edge)
        }
        return mesh
    }

    /// 角を丸めた四角の輪郭（真ん中が原点）
    static func roundedRect(_ w: Double, _ d: Double, r: Double, steps: Int = 4) -> [CV2] {
        CamperPolygon.roundedRect(x: -w / 2, y: -d / 2, w: w, h: d, r: min(r, w / 2, d / 2), seg: steps)
    }
}
