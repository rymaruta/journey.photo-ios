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
        // 背の高い物（煙突・床の灯り）は、全体より手の届く高さの本体に寄る（Mac run 572: ストーブが遠く小さかった）
        var span = max(size.x, size.y, size.z, 18)
        if f.placement == .floor, size.y > 45 {
            span = max(size.x, size.z, 40)
            center = CV3(center.x, min(center.y, 24), center.z)
        }
        // 床の灯りは笠と腕が主役（2026-10-21・Mac run 596: 弧の灯りの腕と笠が枠の上に切れて、柱と台だけに見えた）
        if f.category == .floorLamp {
            span = max(size.x, size.z, size.y * 0.72)
            center = CV3(center.x, size.y * 0.55, center.z)
        }
        if f.placement == .wall { center = center + CV3(0, 0, 6) }
        // 天井の物は下から少し見上げる（上から見下ろすと天井の板が裏向きで消え、換気窓が宙に浮いた板に見えた・run 596）
        // 天窓は真下寄りから（浅いと縁の厚みしか見えず、硝子と空が見えない・run 605）
        let pitch = f.category == .roofHatch ? -42.0 : (f.placement == .ceiling ? -10.0 : 22)
        return CamperRoomCamera(yaw: 28, pitch: pitch, zoom: 1, target: center, baseDistanceOverride: span * 2.3 + 24)
    }
}
