import Foundation

/// 図鑑の寄り（2026-10-19・owner「家具の寄りを昼と夜で撮って、ホンモノに見えるか確かめる」）。
/// 家具を 1 つだけ、窓のある小さな部屋（8×6 マス・奥の壁の前）に置き、部屋と同じ素材と光で描く。
/// 灯りの無い家具も夜に見えるよう、場面の側が暖色の灯りを 1 つ足す（`CamperRoomScene.studio`）
enum CamperRoomStudio {

    static let layout = CamperRoomLayout(kind: .car, width: 8, depth: 6, door: 0...0, kitchen: CamperRoomRect(x: 0, z: 0, w: 0, d: 0),
                                         windows: [CamperRoomWindow(wall: .left, from: 1, to: 3)],
                                         floorLimit: 4, wallLimit: 4, ceilingLimit: 4, photoLimit: 4, isStudio: true)

    static func make(_ f: CamperRoomFurniture) -> (layout: CamperRoomLayout, doc: CamperRoomDocument) {
        var doc = CamperRoomDocument(room: .car)
        doc.upsert(item(f))
        return (layout, doc)
    }

    static func item(_ f: CamperRoomFurniture) -> CamperRoomItem {
        switch f.placement {
        case .floor: return .floor("studio", f.id, x: max(0, (layout.width - f.width) / 2), z: max(0, min(1, layout.depth - f.depth)))
        case .wall: return .wall("studio", f.id, .back, c: max(0, (layout.width - f.width) / 2), row: f.depth >= 2 ? 0 : 1)
        case .ceiling: return .ceiling("studio", f.id, x: max(0, (layout.width - f.width) / 2), z: 2)
        }
    }

    /// 寄りのカメラ（家具の真ん中を狙い、家具の大きさに合わせた距離）
    static func camera(_ f: CamperRoomFurniture) -> CamperRoomCamera {
        let it = item(f)
        guard let b = CamperRoomPick.bounds(it) else { return CamperRoomCamera.overview(layout) }
        var center = (b.min + b.max) * 0.5
        let size = b.max - b.min
        let span = max(size.x, size.y, size.z, 18)
        if f.placement == .wall { center = center + CV3(0, 0, 6) }
        return CamperRoomCamera(yaw: 28, pitch: f.placement == .ceiling ? 12 : 22, zoom: 1, target: center, baseDistanceOverride: span * 2.3 + 24)
    }
}
