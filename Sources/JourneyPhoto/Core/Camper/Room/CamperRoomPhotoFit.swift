import Foundation

/// 額の印画の縦横比合わせ（2026-10-21）。パネル全面に伸ばさず、中央で切り取る（aspect-fill）。
enum CamperRoomPhotoFit {

    /// UV の scale / offset（SceneKit の `contentsTransform` 用）。`imageAspect`・`panelAspect` は 幅/高さ。
    static func uvFit(imageAspect: Double, panelAspect: Double) -> (scaleX: Double, scaleY: Double, offsetX: Double, offsetY: Double) {
        let ia = max(1e-6, imageAspect), pa = max(1e-6, panelAspect)
        if ia > pa {
            // 画像の方が横長 → 高さいっぱいに合わせ、左右を切る
            let sx = ia / pa
            return (sx, 1, (1 - 1 / sx) / 2, 0)
        }
        if ia < pa {
            // 画像の方が縦長 → 幅いっぱいに合わせ、上下を切る
            let sy = pa / ia
            return (1, sy, 0, (1 - 1 / sy) / 2)
        }
        return (1, 1, 0, 0)
    }

    /// 印画パネルの縦横比（壁の額は XY、向き付きは外接箱の長い2辺）
    static func panelAspect(positions: [CV3], indices: [Int32]) -> Double {
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude, maxZ = -Double.greatestFiniteMagnitude
        for i in indices {
            let idx = Int(i)
            guard idx < positions.count else { continue }
            let p = positions[idx]
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }
        return aspectFromExtents(dx: maxX - minX, dy: maxY - minY, dz: maxZ - minZ)
    }

    /// `CamperPreparedMesh`（点は xyz の Float 並び）向け
    static func panelAspect(flatPositions: [Float], indices: [Int32]) -> Double {
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude, maxZ = -Double.greatestFiniteMagnitude
        for i in indices {
            let vi = Int(i) * 3
            guard vi + 2 < flatPositions.count else { continue }
            let x = Double(flatPositions[vi]), y = Double(flatPositions[vi + 1]), z = Double(flatPositions[vi + 2])
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            minZ = min(minZ, z); maxZ = max(maxZ, z)
        }
        return aspectFromExtents(dx: maxX - minX, dy: maxY - minY, dz: maxZ - minZ)
    }

    private static func aspectFromExtents(dx: Double, dy: Double, dz: Double) -> Double {
        // 薄い軸を厚みとみなし、残る2辺をパネルの縦横に
        if dx <= dy, dx <= dz { return max(1e-6, dz) / max(1e-6, dy) }
        if dz <= dx, dz <= dy { return max(1e-6, dx) / max(1e-6, dy) }
        return max(1e-6, dx) / max(1e-6, dz)
    }
}
