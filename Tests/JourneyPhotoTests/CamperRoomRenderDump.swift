import XCTest
@testable import JourneyPhoto

/// 家具の形を手元で見るための書き出し（2026-10-19）。`CAMPER_ROOM_DUMP=<dir>` を渡した時だけ、作り込んだ家具を
/// 小さな絵（`CamperRoomRaster`）にして `<dir>/<id>.rgba`（幅・高さ 4 バイトずつの後に RGBA）に書く。渡さなければ何もしない
final class CamperRoomRenderDump: XCTestCase {

    /// 部屋全体（最初の並び・箱庭の向き）
    func testDumpRoomRender() throws {
        guard let dir = ProcessInfo.processInfo.environment["CAMPER_ROOM_DUMP"], !dir.isEmpty else { return }
        for (name, kind, stage) in [("room.camper", CamperRoomKind.car, CamperStage.camper), ("room.van", .car, .van), ("room.trailer", .trailer, .trailer)] {
            let layout = CamperRoomLayout.make(kind, stage: stage)
            let doc = CamperRoomRules.starterDocument(layout)
            let bp = CamperRoomBuilder.build(layout, doc: doc)
            let camera = CamperRoomCamera.overview(layout)
            var parts: [CamperMesh] = []
            for n in bp.shell where CamperRoomScenePlan.visible(n.name, camera: camera) {
                if case .mesh(let m) = n.shape { parts.append(m) }
            }
            for it in bp.items {
                guard let m = CamperRoomFurnitureModels.mesh(it.furnitureId) else { continue }
                parts.append(CamperRoomMeshKit.placed(m, at: it.position, yaw: it.yaw))
            }
            var o = CamperRoomRaster.Options()
            o.width = 640
            o.height = 480
            o.yaw = camera.yaw
            o.pitch = camera.pitch
            o.background = 0x101010
            let b = CamperRoomRaster.render(CamperRoomMeshKit.merge(parts), o)
            var data = Data()
            withUnsafeBytes(of: UInt32(b.width).littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(b.height).littleEndian) { data.append(contentsOf: $0) }
            data.append(contentsOf: b.rgba)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).rgba"))
        }
    }

    func testDumpFurnitureRenders() throws {
        guard let dir = ProcessInfo.processInfo.environment["CAMPER_ROOM_DUMP"], !dir.isEmpty else { return }
        let size = Int(ProcessInfo.processInfo.environment["CAMPER_ROOM_DUMP_SIZE"] ?? "") ?? 320
        let only = ProcessInfo.processInfo.environment["CAMPER_ROOM_DUMP_ONLY"]
        for f in CamperRoomCatalog.all where f.built {
            if let only, !only.isEmpty, !f.id.contains(only) { continue }
            guard let mesh = CamperRoomFurnitureModels.mesh(f.id) else { continue }
            for mood in [CamperMood.day, .night] {
                var o = CamperRoomRaster.Options()
                o.width = size
                o.height = size
                o.mood = mood
                o.background = 0x202020
                o.pitch = f.placement == .wall ? 8 : (f.placement == .ceiling ? 4 : 28)
                o.yaw = f.placement == .wall ? 20 : 34
                let b = CamperRoomRaster.render(mesh, o)
                var data = Data()
                withUnsafeBytes(of: UInt32(b.width).littleEndian) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: UInt32(b.height).littleEndian) { data.append(contentsOf: $0) }
                data.append(contentsOf: b.rgba)
                try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(f.id).\(mood.rawValue).rgba"))
            }
        }
    }

    /// 印画を朱色にして額を描く（飾った写真がマットに沈まず見えるかを手元で確かめる）
    func testDumpHungPhotoFrames() throws {
        guard let dir = ProcessInfo.processInfo.environment["CAMPER_ROOM_DUMP"], !dir.isEmpty else { return }
        let size = Int(ProcessInfo.processInfo.environment["CAMPER_ROOM_DUMP_SIZE"] ?? "") ?? 480
        let ids = ["photo_frame.landscape", "photo_frame.square", "photo_frame.oval", "photo_frame.triptych"]
        for id in ids {
            guard let raw = CamperRoomFurnitureModels.mesh(id) else { continue }
            // 硝子はソフトラスタだと奥行きを書いて印画を消すので外し、印画を朱色の無地にする
            var mesh = CamperMesh()
            mesh.positions = raw.positions
            mesh.normals = raw.normals
            mesh.uvs = raw.uvs
            mesh.groups = raw.groups.compactMap { g in
                if g.material == .room(.frameGlass) { return nil }
                if case .room(.photo) = g.material { return (.room(.painted(0xD94A3D)), g.indices) }
                return g
            }
            var o = CamperRoomRaster.Options()
            o.width = size
            o.height = size
            o.background = 0x181818
            o.pitch = 12
            o.yaw = 28
            let b = CamperRoomRaster.render(mesh, o)
            var data = Data()
            withUnsafeBytes(of: UInt32(b.width).littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(b.height).littleEndian) { data.append(contentsOf: $0) }
            data.append(contentsOf: b.rgba)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("hung.\(id).rgba"))
        }
    }
}
