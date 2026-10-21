import Foundation

// とおまわり号の中の下ごしらえ（2026-10-19・外の車の `CamperScenePlan` と同じ考え）。部屋の網・家具の網（種類ごとに 1 つ）・
// 貼り絵を画面の処理の外で作り、画面の側（`CamperRoomScene`）は SceneKit の形にしてまとめるだけ。
// 家具は種類ごとに 1 つの形を作り、置いた数だけ写し（clone）を置く（動かす・回すは位置と向きだけ変える）。

struct CamperRoomScenePlan: Sendable {
    var blueprint: CamperRoomBlueprint
    /// 部屋の網（名前つき）
    var shell: [(name: String, mesh: CamperPreparedMesh)]
    /// 家具の網（図鑑の id ごと）
    var furniture: [String: CamperPreparedMesh]
    var bitmaps: [String: CamperBitmap]

    static let unit = 0.01

    /// 組む（重い。画面の処理の外で呼ぶ）。昼と夜の両方の貼り絵を作るので、時刻を替えても組み直さない
    static func make(_ layout: CamperRoomLayout, doc: CamperRoomDocument, paint: UInt32, extra: [String] = []) -> CamperRoomScenePlan {
        let bp = CamperRoomBuilder.build(layout, doc: doc, paint: paint)
        var used = Set<CamperMaterial>()
        var shell: [(String, CamperPreparedMesh)] = []
        for n in bp.shell {
            guard case .mesh(let m) = n.shape, !m.isEmpty else { continue }
            let p = CamperPreparedMesh(m, unit: unit)
            p.groups.forEach { used.insert($0.material) }
            shell.append((n.name, p))
        }
        var furniture: [String: CamperPreparedMesh] = [:]
        for id in Set(bp.items.map(\.furnitureId) + extra) {
            guard let m = CamperRoomFurnitureModels.mesh(id) else { continue }
            let p = CamperPreparedMesh(m, unit: unit)
            p.groups.forEach { used.insert($0.material) }
            furniture[id] = p
        }
        var bitmaps: [String: CamperBitmap] = [:]
        for mood in [CamperMood.day, .night] {
            for m in used {
                let spec = CamperMaterials.spec(m, paint: paint, mood: mood)
                if let kind = spec.texture {
                    let key = CamperScenePlan.textureKey(kind, spec.color)
                    if bitmaps[key] == nil { bitmaps[key] = CamperTextures.make(kind).tinted(spec.color) }
                }
                if let kind = spec.emissionTexture, let e = spec.emission {
                    let key = "emit." + CamperScenePlan.textureKey(kind, e)
                    if bitmaps[key] == nil { bitmaps[key] = CamperTextures.make(kind).tinted(e) }
                }
            }
            bitmaps["env.\(mood.rawValue)"] = CamperTextures.environment(mood)
        }
        bitmaps["contact"] = CamperTextures.contactShadow().premultiplied()
        bitmaps["room.grid"] = gridBitmap()
        return CamperRoomScenePlan(blueprint: bp, shell: shell, furniture: furniture, bitmaps: bitmaps)
    }

    /// 向きによって見せる壁（手前の端の壁は低い方、奥の端の壁は高い方。窓もその壁と一緒）
    static func visible(_ name: String, camera: CamperRoomCamera) -> Bool {
        let front = camera.cutsFrontEnd
        if name.hasPrefix("room.end.front.full") { return !front }
        if name.hasPrefix("room.end.front.low") { return front }
        if name.hasPrefix("room.end.rear.full") { return front }
        if name.hasPrefix("room.end.rear.low") { return !front }
        return true
    }

    /// 置くときの床のマス目（白い細い線・1 マスの絵。白の 35%）
    static func gridBitmap() -> CamperBitmap {
        var b = CamperBitmap(width: 32, height: 32)
        for y in 0..<32 {
            for x in 0..<32 {
                let line = x == 0 || y == 0
                b.set(x, y, (1, 1, 1), line ? 0.35 : 0)
            }
        }
        return b.premultiplied()
    }
}
