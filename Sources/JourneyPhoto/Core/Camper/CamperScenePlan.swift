import Foundation

// 場面に写す前の下ごしらえ（2026-10-18・#312 の見直し「主スレッドの重さ」）。
//
// 組み立て図を作り、室内の灯りの組に分け（`splitForInteriorLight`）、網の点を SceneKit が読む Float の並びに写し、
// 貼り絵（木目・織り目・周りの光・接地の暗がり）を全部の時刻の分だけ作る——ここまでを画面の処理の外でやる。
// 画面の側（`CamperScene`）は並びから `SCNGeometry` を作ってまとめる（`flattenedClone`）だけ。
// 昼・夜・雪は全部を一度に組む（`CamperBuilder.build(_:allMoods:)`）ので、時刻を替えても組み直さない。
// 素の Swift なので Linux でも試験できる。

/// SceneKit の網の束に渡す並び（点 3・向き 3・貼り絵の位置 2 の Float）
struct CamperPreparedMesh: Sendable {
    var positions: [Float]
    var normals: [Float]
    var uvs: [Float]
    var groups: [(material: CamperMaterial, indices: [Int32])]
    var vertexCount: Int { positions.count / 3 }

    /// 網を写す（点は 1/100 にする）
    init(_ m: CamperMesh, unit: Double) {
        positions = m.positions.flatMap { [Float($0.x * unit), Float($0.y * unit), Float($0.z * unit)] }
        normals = m.normals.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        uvs = m.uvs.flatMap { [Float($0.x), Float($0.y)] }
        groups = m.groups.filter { !$0.indices.isEmpty }
    }
}

/// 部品 1 つの下ごしらえ（室内の灯りの組か・網の並び）
struct CamperPreparedNode: Sendable {
    var spec: CamperNodeSpec
    /// 室内の灯りが照らす組
    var inside: Bool
    /// 網の部品だけ（箱・円柱・文字は画面の側で SceneKit の形を作る）
    var mesh: CamperPreparedMesh?
}

struct CamperScenePlan: Sendable {
    var blueprint: CamperBlueprint
    var nodes: [CamperPreparedNode]
    /// 貼り絵（鍵 → 画素）。素材の貼り絵は全部の時刻の色の分（`textureKey`）、周りの光は "env.<時刻>"、接地の暗がりは "contact"
    var bitmaps: [String: CamperBitmap]
    /// 夜の外の遠景の網（林・山の稜線。2026-10-21・画面の処理の外で作る）
    var nightScenery: (trees: CamperPreparedMesh, ridge: CamperPreparedMesh)

    static let unit = 0.01

    /// 夜の外の遠景の網（林・山の稜線）。材質は場面の側で光を受けない霞の材質に替える
    static func nightScenery() -> (trees: CamperPreparedMesh, ridge: CamperPreparedMesh) {
        let st = CamperMaterials.NightStage.self
        return (CamperPreparedMesh(CamperNightScenery.treeMesh(CamperNightScenery.trees(), material: .tint(st.treeColor)), unit: unit),
                CamperPreparedMesh(CamperNightScenery.ridgeMesh(material: .tint(st.ridgeColor)), unit: unit))
    }

    static func textureKey(_ kind: CamperTextureKind, _ color: UInt32) -> String { "\(kind.rawValue).\(color)" }

    /// 下ごしらえを作る（重い。画面の処理の外で呼ぶ）
    static func make(_ config: CamperConfig) -> CamperScenePlan {
        let bp = CamperBuilder.build(config, allMoods: true)
        var nodes: [CamperPreparedNode] = []
        var used = Set<CamperMaterial>()
        for whole in bp.nodes {
            let split = whole.splitForInteriorLight()
            for (part, inside) in [(split.inside, true), (split.outside, false)] {
                guard let spec = part else { continue }
                var mesh: CamperPreparedMesh?
                if case .mesh(let m) = spec.shape {
                    guard !m.isEmpty else { continue }
                    let prepared = CamperPreparedMesh(m, unit: unit)
                    prepared.groups.forEach { used.insert($0.material) }
                    mesh = prepared
                } else {
                    used.insert(spec.material)
                }
                nodes.append(CamperPreparedNode(spec: spec, inside: inside, mesh: mesh))
            }
        }
        var bitmaps: [String: CamperBitmap] = [:]
        let paint = config.loadout.paint
        for mood in CamperMood.allCases {
            for m in used {
                let spec = CamperMaterials.spec(m, paint: paint, mood: mood)
                guard let kind = spec.texture else { continue }
                let key = textureKey(kind, spec.color)
                if bitmaps[key] == nil { bitmaps[key] = CamperTextures.make(kind).tinted(spec.color) }
            }
            bitmaps["env.\(mood.rawValue)"] = CamperTextures.environment(mood)
        }
        bitmaps["contact"] = CamperTextures.contactShadow().premultiplied()
        // 夜の外の空・空の光・地面（2026-10-21）。夜に替えた時に画面の処理の中で作らない
        bitmaps["sky.night"] = CamperTextures.nightSky()
        bitmaps["env.night.outdoor"] = CamperTextures.nightEnvironment()
        bitmaps["ground.night"] = CamperTextures.groundNight().tinted(CamperMaterials.NightStage.ground)
        return CamperScenePlan(blueprint: bp, nodes: nodes, bitmaps: bitmaps, nightScenery: nightScenery())
    }
}

extension CamperConfig {
    /// 組み直しが要るかを決める値（時刻・天気は入れない。昼・夜・雪は組み直さずに切り替える）
    var buildKey: CamperConfig {
        var k = self
        k.mood = .day
        return k
    }
}

extension CamperBitmap {
    /// 透け具合を色に掛けておく（CGImage の premultipliedLast に合わせる）
    func premultiplied() -> CamperBitmap {
        var out = self
        var i = 0
        while i + 3 < out.rgba.count {
            let a = Double(out.rgba[i + 3]) / 255
            for c in 0..<3 { out.rgba[i + c] = UInt8((Double(out.rgba[i + c]) * a).rounded()) }
            i += 4
        }
        return out
    }

    /// 白〜灰の貼り絵に色を掛ける
    func tinted(_ hex: UInt32) -> CamperBitmap {
        var out = self
        let rgb = [Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255]
        var i = 0
        while i + 3 < out.rgba.count {
            for c in 0..<3 { out.rgba[i + c] = UInt8(max(0, min(255, (Double(out.rgba[i + c]) * rgb[c]).rounded()))) }
            i += 4
        }
        return out
    }
}
