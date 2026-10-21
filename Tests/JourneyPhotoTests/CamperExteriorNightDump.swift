import XCTest
@testable import JourneyPhoto

/// 外観の夜を Linux で網から描いて目で確かめる（`CAMPER_EXTERIOR_DUMP=<dir>` のときだけ）
final class CamperExteriorNightDump: XCTestCase {

    func testDumpExteriorNightViews() throws {
        guard let dir = ProcessInfo.processInfo.environment["CAMPER_EXTERIOR_DUMP"], !dir.isEmpty else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var load = CamperLoadout.standard
        // 実機の苦情に近い見え: ランタン・焚き火・梯子あり
        load.picks[CamperCategory.outdoorLight.rawValue] = "brass_lantern"
        load.picks[CamperCategory.firePit.rawValue] = "steel_bowl"
        let paint = load.paint
        let bp = CamperBuilder.build(CamperConfig(stage: .camper, mood: .night, loadout: load))
        let mesh = Self.worldMesh(bp)
        // カメラは center + yaw 回転の (0,0,1)。後ろ（−X）は yaw ≈ −90。
        // 実機の苦情: 後ろ斜めに梯子・スペアが見える寄り／全景は前照灯側
        let shots: [(String, Double, Double)] = [
            ("night-rear", -58, 16),       // 後ろ斜め・手前側
            ("night-rear-far", -110, 14),  // 後ろ斜め・向こう側
            ("night-side", -32, 14),       // 初めの向き（前照灯側）
            ("night-front", -8, 12),
        ]
        for (name, yaw, pitch) in shots {
            var o = CamperRoomRaster.Options()
            o.width = 720
            o.height = 540
            o.yaw = yaw
            o.pitch = pitch
            o.mood = .night
            o.background = 0x06080E
            // 塗色を渡すため、一時的に paint を差し込んだ描きは下の専用関数へ
            let b = Self.render(mesh, paint: paint, o)
            try Self.writeRGBA(b, to: "\(dir)/\(name).rgba")
        }
        // 直し前の巻き（mirror あり）だけの後壁を重ねて比較
        let broken = Self.brokenRearWallMesh()
        // 後壁だけを外（−X）から見る: yaw −90
        var o = CamperRoomRaster.Options()
        o.width = 640
        o.height = 480
        o.yaw = -90
        o.pitch = 8
        o.mood = .night
        o.background = 0x06080E
        try Self.writeRGBA(Self.render(broken, paint: paint, o), to: "\(dir)/night-rear-BROKEN-winding.rgba")
        try Self.writeRGBA(Self.render(Self.fixedRearWallMesh(), paint: paint, o), to: "\(dir)/night-rear-FIXED-winding.rgba")
    }

    /// 組み立て図の部品を世界座標の網にまとめる（地面の溜まり・炎・外装・窓）。足す光は最後に描く
    private static func worldMesh(_ bp: CamperBlueprint) -> CamperMesh {
        var solid: [CamperMesh] = []
        var glow: [CamperMesh] = []
        for n in bp.nodes {
            // 室内の細かい家具は外観の確認では重いので、殻・灯り・溜まり・外の置き物に絞る
            let keep = n.name.hasPrefix("body.")
                || n.name.hasPrefix("rear.")
                || n.name.hasPrefix("light.")
                || n.name.hasPrefix("glow.")
                || n.name.hasPrefix("fire.")
                || n.name.hasPrefix("window")
                || n.name.hasPrefix("door.")
                || n.name.hasPrefix("ext.")
                || n.name.hasPrefix("awning.")
                || n.name.hasPrefix("cargo.")
                || n.name.hasPrefix("wheel.")
                || n.name.hasPrefix("interior.windowGlow")
                || n.name.hasPrefix("interior.curtain")
                || n.name.hasPrefix("cabDoor")
                || n.group == .glow || n.group == .flame || n.group == .doorGlow
            guard keep else { continue }
            guard case .mesh(let m) = n.shape, !m.isEmpty else { continue }
            let placed: CamperMesh
            if n.scale != CV3(1, 1, 1) {
                placed = CamperRoomMeshKit.placed(CamperRoomMeshKit.scaled(m, n.scale), at: n.position, rotation: n.orientation)
            } else {
                placed = CamperRoomMeshKit.placed(m, at: n.position, rotation: n.orientation)
            }
            let isGlow = n.group == .glow || n.group == .doorGlow || n.name.hasPrefix("glow.")
                || n.name.hasPrefix("interior.windowGlow")
            if isGlow { glow.append(placed) } else { solid.append(placed) }
        }
        return CamperRoomMeshKit.merge(solid + glow)
    }

    private static func fixedRearWallMesh() -> CamperMesh {
        let bp = CamperBuilder.build(CamperConfig(stage: .camper, mood: .night, loadout: .standard))
        var parts: [CamperMesh] = []
        for n in bp.nodes where n.name == "body.rearWall" || n.name.hasPrefix("rear.") {
            guard case .mesh(let m) = n.shape else { continue }
            parts.append(CamperRoomMeshKit.placed(m, at: n.position, rotation: n.orientation))
        }
        return CamperRoomMeshKit.merge(parts)
    }

    /// 旧バグ再現: 後壁だけ mirror で巻きを逆にする
    private static func brokenRearWallMesh() -> CamperMesh {
        let bp = CamperBuilder.build(CamperConfig(stage: .camper, mood: .night, loadout: .standard))
        var parts: [CamperMesh] = []
        for n in bp.nodes where n.name == "body.rearWall" || n.name.hasPrefix("rear.") {
            guard case .mesh(var m) = n.shape else { continue }
            if n.name == "body.rearWall" {
                // 巻きだけ逆（旧 mirror: true と同じ）
                m.groups = m.groups.map { g in
                    var idx = g.indices
                    var i = 0
                    while i + 2 < idx.count {
                        idx.swapAt(i + 1, i + 2)
                        i += 3
                    }
                    return (g.material, idx)
                }
            }
            parts.append(CamperRoomMeshKit.placed(m, at: n.position, rotation: n.orientation))
        }
        return CamperRoomMeshKit.merge(parts)
    }

    /// 塗色つきで描く（CamperRoomRaster は既定塗色固定なので、ここで差し替え）
    private static func render(_ mesh: CamperMesh, paint: UInt32, _ o: CamperRoomRaster.Options) -> CamperBitmap {
        // 一時的に材質の色を差し替えた網は作れないので、raster を paint=0x5B6168 のまま使い、
        // 塗色は loadout の標準に近い灰色のまま（白飛びの有無の確認が主目的）
        _ = paint
        return CamperRoomRaster.render(mesh, o)
    }

    private static func writeRGBA(_ b: CamperBitmap, to path: String) throws {
        var data = Data()
        withUnsafeBytes(of: UInt32(b.width).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(b.height).littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: b.rgba)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
