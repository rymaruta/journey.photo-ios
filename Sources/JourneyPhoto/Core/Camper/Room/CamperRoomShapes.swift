import Foundation

// 家具に添える小さな形（2026-10-19）: 額・鉢植え・つる・木の鳥・マグ・弧の蓋。`CamperRoomFurnitureModels` が使う。

private typealias K = CamperRoomMeshKit
private func R(_ m: CamperRoomMaterial) -> CamperMaterial { .room(m) }

enum CamperRoomShapes {

    /// 向きを、同じ点を共にする面どうしでなめらかにする（角の立つ所 60° より急な所は分けたまま）
    static func smoothNormals(_ mesh: CamperMesh, crease: Double = 60) -> CamperMesh {
        struct Key: Hashable { var x: Int, y: Int, z: Int }
        func key(_ p: CV3) -> Key { Key(x: Int((p.x * 200).rounded()), y: Int((p.y * 200).rounded()), z: Int((p.z * 200).rounded())) }
        var faceNormals = [CV3](repeating: .zero, count: mesh.positions.count)
        var sums: [Key: [CV3]] = [:]
        for g in mesh.groups {
            for k in stride(from: 0, to: g.indices.count - 2, by: 3) {
                let ia = Int(g.indices[k]), ib = Int(g.indices[k + 1]), ic = Int(g.indices[k + 2])
                var n = (mesh.positions[ib] - mesh.positions[ia]).cross(mesh.positions[ic] - mesh.positions[ia])
                if n.length < 1e-12 { continue }
                n = n.normalized
                for i in [ia, ib, ic] {
                    faceNormals[i] = n
                    sums[key(mesh.positions[i]), default: []].append(n)
                }
            }
        }
        var out = mesh
        let limit = cos(crease * .pi / 180)
        for i in mesh.positions.indices {
            let f = faceNormals[i]
            guard f.length > 0.5, let list = sums[key(mesh.positions[i])] else { continue }
            var acc = CV3.zero
            for n in list where n.dot(f) >= limit { acc = acc + n }
            out.normals[i] = acc.normalized
        }
        return out
    }

    /// 弧の蓋の断面（横 z・高さ y。下の辺から `base` だけ立ち上がり、真ん中が `rise` だけ盛り上がる）
    static func archOutline(width: Double, base: Double, rise: Double, steps: Int = 16) -> [CV2] {
        var pts = [CV2(-width / 2, 0), CV2(width / 2, 0), CV2(width / 2, base)]
        for k in 1..<steps {
            let t = Double(k) / Double(steps)
            let z = width / 2 - width * t
            pts.append(CV2(z, base + rise * sqrt(max(0, 1 - pow(z / (width / 2), 2)))))
        }
        pts.append(CV2(-width / 2, base))
        return pts
    }

    /// 断面（横 z・高さ y）を x の向きへ `length` だけ押し出す（真ん中が原点）
    static func extrudeAlongX(_ outline: [CV2], length: Double, inset: Double, _ m: CamperMaterial) -> CamperMesh {
        let flipped = outline.map { CV2(-$0.x, $0.y) }
        let mesh = CamperMeshKit.extrude(flipped, depth: length, front: m, side: m, bevel: inset)
        return K.placed(mesh, at: CV3(length / 2, 0, 0), yaw: .pi / 2)
    }

    /// 額（枠・白いマットと内の切り口・写真・表の硝子）。`at` は額の真ん中（壁の面の上）。表は +Z
    static func frame(outer: CV2, photo: CV2, depth: Double, rim: Double, at c: CV3, frame m: CamperMaterial) -> CamperMesh {
        var parts: [CamperMesh] = []
        let inner = CV2(outer.x - rim * 2, outer.y - rim * 2)
        let ring = K.roundedRect(outer.x, outer.y, r: 0.5, steps: 2)
        let hole = CamperPolygon.cw(K.roundedRect(inner.x, inner.y, r: 0.3, steps: 2))
        parts.append(K.placed(CamperMeshKit.extrude(ring, holes: [hole], depth: depth, front: m, side: m, bevel: 0.35), at: c + CV3(0, 0, depth)))
        // 枠の内の段（写真を押さえる細い縁）
        parts.append(K.placed(K.panel(width: inner.x + 0.2, height: inner.y + 0.2, R(.mat)), at: c + CV3(0, 0, depth - 0.7)))
        let matHole = CamperPolygon.cw(K.roundedRect(photo.x, photo.y, r: 0.2, steps: 2))
        parts.append(K.placed(CamperMeshKit.extrude(K.roundedRect(photo.x + 1.2, photo.y + 1.2, r: 0.3, steps: 2), holes: [matHole], depth: 0.25,
                                                    front: R(.mat), side: R(.mat), bevel: 0.2), at: c + CV3(0, 0, depth - 0.45)))
        parts.append(K.placed(K.panel(width: photo.x, height: photo.y, CamperRoomFurnitureModels.photoMaterial(0)), at: c + CV3(0, 0, depth - 0.66)))
        parts.append(K.placed(K.panel(width: inner.x + 0.1, height: inner.y + 0.1, R(.glass)), at: c + CV3(0, 0, depth - 0.25)))
        // 壁に付く背板（隙間から壁が透けない）
        parts.append(K.placed(K.panel(width: outer.x - 0.4, height: outer.y - 0.4, R(.painted(0x3A3430))), at: c + CV3(0, 0, 0.05)))
        return K.merge(parts)
    }

    /// 鉢植え（素焼きの鉢・縁・土・外へ広がる葉と茎）
    static func pottedPlant(at p: CV3, potRadius r: Double, height h: Double, leaves: Int, spread: Double) -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(r * 0.72, 0), CV2(r * 0.92, h * 0.82), CV2(r * 1.08, h * 0.84), CV2(r * 1.08, h),
                                       CV2(r * 0.9, h), CV2(r * 0.86, h * 0.86), CV2(0, h * 0.86)], segments: 20, R(.terracotta)), at: p))
        parts.append(K.placed(K.disc(radius: r * 0.86, height: 0.2, bevel: 0.05, segments: 16, R(.soil)), at: p + CV3(0, h * 0.8, 0)))
        for k in 0..<leaves {
            let a = Double(k) / Double(leaves) * 2 * .pi + 0.3
            let lift = 0.5 + 0.5 * Double(k % 3) / 2
            let tip = p + CV3(cos(a) * spread * 0.8, h + spread * lift, sin(a) * spread * 0.8)
            let base = p + CV3(0, h * 0.86, 0)
            parts.append(K.tube([base, base * 0.4 + tip * 0.6 + CV3(0, 0.4, 0), tip], radius: 0.08, sides: 4, R(.leaf)))
            parts.append(leaf(at: tip, toward: CV3(cos(a), 0.5, sin(a)), size: spread * 0.42))
        }
        return K.merge(parts)
    }

    /// 葉 1 枚（細長い楕円の薄い面を `toward` の向きへ、少し反らせて）
    static func leaf(at p: CV3, toward dir: CV3, size: Double) -> CamperMesh {
        let shape = K.scaled(K.sphere(radius: 1, segments: 10, R(.leaf)), CV3(size, size * 0.12, size * 0.5))
        let flat = CV3(dir.x, 0, dir.z).length > 1e-6 ? CV3(dir.x, 0, dir.z).normalized : CV3(1, 0, 0)
        let yaw = atan2(-flat.z, flat.x)
        let tilt = CQuat.axisAngle(CV3(0, 0, 1), atan2(dir.y, CV3(dir.x, 0, dir.z).length) * 0.6)
        return K.placed(shape, at: p + flat * (size * 0.6), rotation: CQuat.axisAngle(CV3(0, 1, 0), yaw) * tilt)
    }

    /// 鉢から垂れるつる（葉が左右に互い違い）
    static func trailingVines(at p: CV3, count: Int, length: Double) -> CamperMesh {
        var parts: [CamperMesh] = []
        for k in 0..<count {
            let a = Double(k) / Double(count) * 2 * .pi + 0.2
            let out = CV3(cos(a), 0, sin(a))
            let len = length * (0.55 + 0.45 * Double((k * 5) % 7) / 6)
            let path = (0...10).map { s -> CV3 in
                let t = Double(s) / 10
                let r = 3.4 + 2.4 * sin(t * .pi * 0.6)
                return p + out * r + CV3(0, 1.2 - t * len, 0) + CV3(-out.z, 0, out.x) * (sin(t * 6 + Double(k)) * 0.6)
            }
            parts.append(K.tube(path, radius: 0.1, sides: 4, R(.leaf)))
            for (i, q) in path.enumerated() where i % 2 == 1 {
                let side = CV3(-out.z, 0, out.x) * (i % 4 == 1 ? 1 : -1)
                parts.append(leaf(at: q, toward: side + out * 0.6 + CV3(0, -0.2, 0), size: 1.5))
            }
        }
        return K.merge(parts)
    }

    /// 木の鳥（胴・頭・くちばし・尾・羽 2・目）。くちばしは +X
    static func bird(_ m: CamperMaterial) -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.scaled(K.sphere(radius: 1, segments: 16, m), CV3(3.1, 1.5, 1.35)))
        parts.append(K.placed(K.sphere(radius: 1.05, segments: 12, m), at: CV3(2.5, 0.9, 0)))
        parts.append(K.placed(K.lathe([CV2(0.35, 0), CV2(0, 1.1)], segments: 8, R(.wood(.darkOak))), at: CV3(3.4, 0.95, 0),
                              rotation: CQuat.axisAngle(CV3(0, 0, 1), -.pi / 2)))
        parts.append(K.placed(K.roundedBox(CV3(2.6, 0.3, 1.6), radius: 0.14, segments: 1, m), at: CV3(-3.4, 0.6, 0),
                              rotation: CQuat.axisAngle(CV3(0, 0, 1), 0.45)))
        for s in [-1.0, 1.0] {
            parts.append(K.placed(K.roundedBox(CV3(2.6, 0.22, 3.0), radius: 0.11, segments: 1, m), at: CV3(-0.3, 0.9, s * 2.1),
                                  rotation: CQuat.axisAngle(CV3(1, 0, 0), s * 0.45)))
            parts.append(K.placed(K.sphere(radius: 0.17, segments: 6, R(.painted(0x141414))), at: CV3(3.05, 1.2, s * 0.62)))
        }
        return K.merge(parts)
    }

    /// 壁に貼った紙（真ん中が原点・+Z 向き・貼り絵は 0〜1）。わずかに波打ち、下の両角が `curl` だけ壁から浮く
    static func paperSheet(width: Double, height: Double, curl: Double, _ m: CamperMaterial) -> CamperMesh {
        let cols = 10, rows = 14
        func p(_ i: Int, _ j: Int) -> CV3 {
            let u = Double(i) / Double(cols), v = Double(j) / Double(rows)
            let wave = 0.12 * sin(u * .pi * 3 + v * 2) * sin(v * .pi)
            let corner = curl * pow(max(0, v - 0.7) / 0.3, 2) * pow(abs(u - 0.5) * 2, 3)
            return CV3((u - 0.5) * width, (0.5 - v) * height, wave + corner)
        }
        var mesh = CamperMesh()
        for j in 0...rows {
            for i in 0...cols {
                mesh.positions.append(p(i, j))
                mesh.uvs.append(CV2(Double(i) / Double(cols), Double(j) / Double(rows)))
                let a = p(min(cols, i + 1), j) - p(max(0, i - 1), j)
                let b = p(i, max(0, j - 1)) - p(i, min(rows, j + 1))
                mesh.normals.append(a.cross(b).normalized)
            }
        }
        var idx: [Int32] = []
        for j in 0..<rows {
            for i in 0..<cols {
                let a = Int32(j * (cols + 1) + i), b = a + 1, c = a + Int32(cols + 1), d = c + 1
                // 上の行が j、下が j+1（y が下がる）。表（+Z）から見て反時計回り
                idx += [a, c, d, a, d, b]
            }
        }
        mesh.groups = [(m, idx)]
        return mesh
    }

    /// 流し（上が開いた箱・面は内向き）。`center` は上の縁の真ん中
    static func basin(center c: CV3, width w: Double, depth d: Double, height h: Double, _ m: CamperMaterial) -> CamperMesh {
        var mesh = CamperMesh()
        let x0 = c.x - w / 2, x1 = c.x + w / 2, z0 = c.z - d / 2, z1 = c.z + d / 2, y0 = c.y - h, y1 = c.y
        mesh.quad(CV3(x0, y0, z0), CV3(x1, y0, z0), CV3(x1, y0, z1), CV3(x0, y0, z1), .up, .up, .up, .up, m)
        let walls: [(CV3, CV3, CV3)] = [(CV3(x0, 0, z0), CV3(x1, 0, z0), CV3(0, 0, 1)), (CV3(x1, 0, z1), CV3(x0, 0, z1), CV3(0, 0, -1)),
                                         (CV3(x0, 0, z1), CV3(x0, 0, z0), CV3(1, 0, 0)), (CV3(x1, 0, z0), CV3(x1, 0, z1), CV3(-1, 0, 0))]
        for (a, b, n) in walls {
            mesh.quad(CV3(a.x, y0, a.z), CV3(b.x, y0, b.z), CV3(b.x, y1, b.z), CV3(a.x, y1, a.z), n, n, n, n, m)
        }
        return mesh
    }

    /// マグ（胴・内側・縁・取っ手・中のコーヒー）
    static func mug(at p: CV3, body: CamperMaterial, rim: CamperMaterial, yaw: Double) -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.vessel(outer: [CV2(0, 0), CV2(1.5, 0), CV2(1.65, 0.2), CV2(1.65, 3.4)], inner: [CV2(0, 0.4), CV2(1.45, 0.4), CV2(1.45, 3.4)],
                              segments: 22, body))
        parts.append(K.tube(K.arc(center: .zero, radius: 1.55, from: 0, to: 2 * .pi, steps: 22).map { CV3($0.x, 3.4, $0.y) }, radius: 0.12,
                            sides: 5, closed: true, rim))
        parts.append(K.placed(K.disc(radius: 1.44, height: 0.1, bevel: 0.02, segments: 18, R(.painted(0x2A170C))), at: CV3(0, 2.6, 0)))
        parts.append(K.tube(K.arc(center: CV3(1.65, 1.8, 0), radius: 1, from: -.pi / 2, to: .pi / 2, steps: 10).map { CV3($0.x, $0.y, 0) },
                            radius: 0.22, sides: 6, body))
        return K.placed(K.merge(parts), at: p, yaw: yaw)
    }
}
