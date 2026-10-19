import Foundation

// 家具の小さな絵（2026-10-19）。下の棚と図鑑の枠に出す、家具の形そのものの静止画を、端末の中で網から描く
// （板の「部品の絵は 3D で 1 個ずつ撮った静止画」）。SceneKit を待たずに描け、素の Swift なので Linux でも試験できる。
// 奥行きの順（z の値）を守り、向きのなめらかな陰・貼り絵の色・艶の強い面の光を乗せる。影絵（まだ持っていない家具）も描く。

enum CamperRoomRaster {

    struct Options: Sendable {
        var width = 128
        var height = 128
        /// 見る向き（横の回り・見下ろし。度）
        var yaw = 34.0
        var pitch = 26.0
        var mood: CamperMood = .day
        /// 影絵（黒に細い灰の縁）
        var silhouette = false
        /// 地の色（nil は透明）
        var background: UInt32?
    }

    /// 網を描く（網の外接の箱に合わせて寄る）
    static func render(_ mesh: CamperMesh, _ o: Options = Options()) -> CamperBitmap {
        var out = CamperBitmap(width: o.width, height: o.height)
        guard !mesh.positions.isEmpty else { return out }
        let xs = mesh.positions.map(\.x), ys = mesh.positions.map(\.y), zs = mesh.positions.map(\.z)
        let lo = CV3(xs.min()!, ys.min()!, zs.min()!), hi = CV3(xs.max()!, ys.max()!, zs.max()!)
        let center = (lo + hi) * 0.5
        let radius = max(1, (hi - lo).length / 2)
        let q = CQuat.axisAngle(CV3(0, 1, 0), o.yaw * .pi / 180) * CQuat.axisAngle(CV3(1, 0, 0), -o.pitch * .pi / 180)
        let inv = CQuat(x: -q.x, y: -q.y, z: -q.z, w: q.w)
        let fov = 30.0 * .pi / 180
        let dist = radius / sin(fov / 2) * 1.02
        let eye = center + q.rotate(CV3(0, 0, 1)) * dist
        let w = Double(o.width), h = Double(o.height)
        let t = tan(fov / 2)
        let light = CV3(-0.45, 0.8, 0.55).normalized
        let viewLight = inv.rotate(light)
        var depth = [Double](repeating: .greatestFiniteMagnitude, count: o.width * o.height)
        var rgba = [Double](repeating: 0, count: o.width * o.height * 4)
        if let bg = o.background {
            let c = CamperTextures.rgb(bg)
            for i in 0..<(o.width * o.height) { rgba[i * 4] = c.0; rgba[i * 4 + 1] = c.1; rgba[i * 4 + 2] = c.2; rgba[i * 4 + 3] = 1 }
        }
        var textures: [String: CamperBitmap] = [:]
        // 画面の点へ
        let viewPositions = mesh.positions.map { inv.rotate($0 - eye) }
        let projected: [(x: Double, y: Double, z: Double)] = viewPositions.map { v in
            let z = -v.z
            let nx = v.x / max(z, 1e-6) / (t * w / h), ny = v.y / max(z, 1e-6) / t
            return ((nx + 1) / 2 * w, (1 - ny) / 2 * h, z)
        }
        let viewNormals = mesh.normals.map { inv.rotate($0) }
        for g in mesh.groups {
            let spec = CamperMaterials.spec(g.material, paint: 0x5B6168, mood: o.mood)
            let base = CamperTextures.rgb(spec.color)
            var tex: CamperBitmap?
            if !o.silhouette, let kind = spec.texture {
                let key = "\(kind.rawValue)"
                if textures[key] == nil { textures[key] = CamperTextures.make(kind) }
                tex = textures[key]
            }
            let emit = spec.emission.map(CamperTextures.rgb)
            for k in stride(from: 0, to: g.indices.count - 2, by: 3) {
                let ia = Int(g.indices[k]), ib = Int(g.indices[k + 1]), ic = Int(g.indices[k + 2])
                let a = projected[ia], b = projected[ib], c = projected[ic]
                guard a.z > 0, b.z > 0, c.z > 0 else { continue }
                // 裏の面は描かない（SceneKit と同じ。向きを書き違えた面は、ここでも消えて見える）
                let va = viewPositions[ia]
                let face = (viewPositions[ib] - va).cross(viewPositions[ic] - va)
                if !spec.doubleSided, !o.silhouette, face.dot(-va) <= 0 { continue }
                let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
                guard abs(area) > 1e-9 else { continue }
                let minX = max(0, Int(floor(min(a.x, b.x, c.x)))), maxX = min(o.width - 1, Int(ceil(max(a.x, b.x, c.x))))
                let minY = max(0, Int(floor(min(a.y, b.y, c.y)))), maxY = min(o.height - 1, Int(ceil(max(a.y, b.y, c.y))))
                guard minX <= maxX, minY <= maxY else { continue }
                for py in minY...maxY {
                    for px in minX...maxX {
                        let sx = Double(px) + 0.5, sy = Double(py) + 0.5
                        let w0 = ((b.x - sx) * (c.y - sy) - (b.y - sy) * (c.x - sx)) / area
                        let w1 = ((c.x - sx) * (a.y - sy) - (c.y - sy) * (a.x - sx)) / area
                        let w2 = 1 - w0 - w1
                        guard w0 >= -1e-6, w1 >= -1e-6, w2 >= -1e-6 else { continue }
                        let z = w0 * a.z + w1 * b.z + w2 * c.z
                        let i = py * o.width + px
                        guard z < depth[i] else { continue }
                        depth[i] = z
                        if o.silhouette {
                            rgba[i * 4] = 0.02; rgba[i * 4 + 1] = 0.02; rgba[i * 4 + 2] = 0.02; rgba[i * 4 + 3] = 1
                            continue
                        }
                        var n = (viewNormals[ia] * w0 + viewNormals[ib] * w1 + viewNormals[ic] * w2).normalized
                        if n.z < 0, spec.doubleSided { n = -n }
                        let diffuse = max(0, n.dot(viewLight))
                        var col = base
                        if let tex {
                            let uv = mesh.uvs[ia] * w0 + mesh.uvs[ib] * w1 + mesh.uvs[ic] * w2
                            let tx = ((Int(floor(uv.x * Double(tex.width))) % tex.width) + tex.width) % tex.width
                            let ty = ((Int(floor(uv.y * Double(tex.height))) % tex.height) + tex.height) % tex.height
                            let p = tex.pixel(tx, ty)
                            col = (col.0 * Double(p.r) / 255, col.1 * Double(p.g) / 255, col.2 * Double(p.b) / 255)
                        }
                        let metal = spec.metalness
                        let ambient = 0.32 + 0.12 * max(0, n.y)
                        var lit = ambient + 0.75 * diffuse * (1 - metal * 0.5)
                        // 艶（粗さが低いほど鋭く強い光）
                        let half = (viewLight + CV3(0, 0, 1)).normalized
                        let shine = pow(max(0, n.dot(half)), 8 + (1 - spec.roughness) * 90) * (1 - spec.roughness) * (0.4 + metal * 0.8)
                        if spec.unlit { lit = 1 }
                        var r = col.0 * lit + shine, gg = col.1 * lit + shine, bb = col.2 * lit + shine
                        if let e = emit, spec.emissionIntensity > 0 {
                            r += e.0 * spec.emissionIntensity * 0.8; gg += e.1 * spec.emissionIntensity * 0.8; bb += e.2 * spec.emissionIntensity * 0.8
                        }
                        let alpha = spec.opacity < 1 ? max(0.35, spec.opacity) : 1
                        rgba[i * 4] = rgba[i * 4] * (1 - alpha) + min(1, r) * alpha
                        rgba[i * 4 + 1] = rgba[i * 4 + 1] * (1 - alpha) + min(1, gg) * alpha
                        rgba[i * 4 + 2] = rgba[i * 4 + 2] * (1 - alpha) + min(1, bb) * alpha
                        rgba[i * 4 + 3] = max(rgba[i * 4 + 3], alpha)
                    }
                }
            }
        }
        // 影絵は縁を細い灰に
        if o.silhouette {
            for y in 0..<o.height {
                for x in 0..<o.width {
                    let i = y * o.width + x
                    guard rgba[i * 4 + 3] > 0 else { continue }
                    let edge = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < o.width, ny < o.height else { return true }
                        return rgba[(ny * o.width + nx) * 4 + 3] == 0
                    }
                    if edge { rgba[i * 4] = 0.42; rgba[i * 4 + 1] = 0.42; rgba[i * 4 + 2] = 0.42 }
                }
            }
        }
        for i in 0..<(o.width * o.height) {
            let a = rgba[i * 4 + 3]
            out.set(i % o.width, i / o.width, (rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]), a)
        }
        return out
    }
}
