import UIKit
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import ImageIO
import SceneKitShim
#endif

// 素材と形を SceneKit に写す所（2026-10-19・`CamperScene` から切り出した）。外の車（`CamperScene`）と、とおまわり号の中
// （`CamperRoomScene`）が同じものを使う——素材の値・貼り絵・光る面の決まり（emission は 1 まで）を 2 か所に持たない。
// 同じ材質は 1 つの SCNMaterial を使い回し、時刻を替えたら値だけ入れ直す。

#if canImport(SceneKit) || canImport(SceneKitShim)

@MainActor
final class CamperScenePalette {

    private var textureCache: [String: CGImage] = [:]
    /// 下ごしらえの貼り絵（`CamperScenePlan.bitmaps` など）
    private var bitmaps: [String: CamperBitmap] = [:]
    private(set) var materials: [CamperMaterial: SCNMaterial] = [:]
    /// 殻の中（室内の組）の材質。外と同じ値に、空の光の遮り（`CamperMaterials.interiorSkyOcclusion`）を足した別の 1 つ
    private(set) var insideMaterials: [CamperMaterial: SCNMaterial] = [:]
    private(set) var paint: UInt32 = 0x5B6168
    private(set) var mood: CamperMood = .day

    /// 組み直す時（材質を作り直す。貼り絵の控えは残す）
    func reset(bitmaps: [String: CamperBitmap], paint: UInt32, mood: CamperMood) {
        self.bitmaps.merge(bitmaps) { _, new in new }
        self.paint = paint
        self.mood = mood
        materials = [:]
        insideMaterials = [:]
    }

    /// 時刻を替える（作った材質の値を全部入れ直す）
    func setMood(_ mood: CamperMood) {
        self.mood = mood
        for (m, scn) in materials { configure(scn, CamperMaterials.spec(m, paint: paint, mood: mood)) }
        for (m, scn) in insideMaterials { configureInside(scn, m) }
    }

    /// 材質（同じ材質は 1 つ）。`inside` は外の車の殻の中（室内の組）——空の光を遮る別の 1 つ
    func material(_ m: CamperMaterial, inside: Bool = false) -> SCNMaterial {
        if inside {
            if let hit = insideMaterials[m] { return hit }
            let made = SCNMaterial()
            configureInside(made, m)
            insideMaterials[m] = made
            return made
        }
        if let hit = materials[m] { return hit }
        let made = SCNMaterial()
        configure(made, CamperMaterials.spec(m, paint: paint, mood: mood))
        materials[m] = made
        return made
    }

    /// 殻の中の材質（2026-10-21 判断・owner「中の光で眩しすぎる」）。SceneKit の周りの光（`lightingEnvironment`）と環境光は
    /// 壁と屋根で遮られず、殻の中まで外と同じ明るさで照らす——昼に扉を開けると、奥の内張りが外の塗装より明るく見えた。
    /// 物理ベースの材質の `ambientOcclusion`（周りの光と環境光だけに掛かる。灯りには掛からない）で、口から入る空の光の分まで落とす
    private func configureInside(_ scn: SCNMaterial, _ m: CamperMaterial) {
        configure(scn, CamperMaterials.spec(m, paint: paint, mood: mood))
        let k = CamperMaterials.interiorSkyOcclusion(mood)
        scn.ambientOcclusion.contents = UIColor(white: CGFloat(k), alpha: 1)
    }

    /// 網の並びから形を作る（材質は束ごと）
    func geometry(_ m: CamperPreparedMesh, inside: Bool = false) -> SCNGeometry? {
        guard m.vertexCount > 0, !m.groups.isEmpty else { return nil }
        func source(_ values: [Float], _ semantic: SCNGeometrySource.Semantic, _ components: Int) -> SCNGeometrySource {
            let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
            return SCNGeometrySource(data: data, semantic: semantic, vectorCount: values.count / components,
                                     usesFloatComponents: true, componentsPerVector: components,
                                     bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                     dataStride: MemoryLayout<Float>.size * components)
        }
        let sources = [source(m.positions, .vertex, 3), source(m.normals, .normal, 3), source(m.uvs, .texcoord, 2)]
        let elements = m.groups.map { SCNGeometryElement(indices: $0.indices, primitiveType: .triangles) }
        let g = SCNGeometry(sources: sources, elements: elements)
        g.materials = m.groups.map { material($0.material, inside: inside) }
        return g
    }

    /// 箱・円柱・輪・球・文字の形（`unit` は板の単位 → SceneKit の単位）
    func geometry(_ shape: CamperShape, material key: CamperMaterial, unit s: Double, inside: Bool = false) -> SCNGeometry? {
        let m = material(key, inside: inside)
        return geometry(shape, scnMaterial: m, unit: s)
    }

    private func geometry(_ shape: CamperShape, scnMaterial: SCNMaterial, unit s: Double) -> SCNGeometry? {
        let m = scnMaterial
        switch shape {
        case .mesh:
            return nil
        case let .box(size, chamfer):
            let b = SCNBox(width: CGFloat(size.x * s), height: CGFloat(size.y * s), length: CGFloat(size.z * s),
                           chamferRadius: CGFloat(chamfer * s))
            b.chamferSegmentCount = chamfer > 0.8 ? 3 : 1
            b.materials = [m]
            return b
        case let .cylinder(radius, height, segments):
            let c = SCNCylinder(radius: CGFloat(radius * s), height: CGFloat(height * s))
            c.radialSegmentCount = max(3, segments)
            c.materials = [m]
            return c
        case let .torus(ring, pipe):
            let t = SCNTorus(ringRadius: CGFloat(ring * s), pipeRadius: CGFloat(pipe * s))
            t.ringSegmentCount = 32
            t.pipeSegmentCount = 10
            t.materials = [m]
            return t
        case .sphere(let radius):
            let sp = SCNSphere(radius: CGFloat(radius * s))
            sp.segmentCount = 18
            sp.materials = [m]
            return sp
        case let .text(string, _, depth):
            let t = SCNText(string: string, extrusionDepth: CGFloat(depth * 10))
            t.font = UIFont.systemFont(ofSize: 10, weight: .bold)
            t.flatness = 0.2
            t.materials = [m]
            return t
        }
    }

    /// 材質に値を入れる（作る時と、時刻を替えた時。前の時刻の値が残らないよう、全部入れ直す）
    func configure(_ m: SCNMaterial, _ spec: CamperMaterialSpec) {
        m.diffuse.contents = Self.color(spec.color)
        m.metalness.contents = 0.0
        m.roughness.contents = 1.0
        m.clearCoat.contents = 0.0
        m.clearCoatRoughness.contents = 0.0
        m.emission.contents = Self.color(0x000000)
        m.emission.intensity = 0
        m.transparency = 1
        m.transparencyMode = .aOne
        m.blendMode = .alpha
        m.writesToDepthBuffer = true
        m.isDoubleSided = spec.doubleSided
        func texture(_ kind: CamperTextureKind) -> CGImage? {
            image(key: CamperScenePlan.textureKey(kind, spec.color)) { CamperTextures.make(kind).tinted(spec.color) }
        }
        if spec.additive {
            // 下の色に光を足す（黒は何も足さない）。奥行きは書かず、灯りの溜まりどうしが重なっても欠けない
            m.lightingModel = .constant
            if let kind = spec.texture { m.diffuse.contents = texture(kind) }
            m.blendMode = .add
            m.writesToDepthBuffer = false
            m.isDoubleSided = true
            return
        }
        if spec.unlit {
            // 光を受けない一色（影絵）・絵（窓の外の景色）
            m.lightingModel = .constant
            if let kind = spec.texture { m.diffuse.contents = texture(kind) }
            return
        }
        m.lightingModel = .physicallyBased
        if let kind = spec.texture {
            m.diffuse.contents = texture(kind)
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.mipFilter = .linear
        }
        m.metalness.contents = spec.metalness
        m.roughness.contents = spec.roughness
        if spec.clearCoat > 0 {
            m.clearCoat.contents = spec.clearCoat
            m.clearCoatRoughness.contents = spec.clearCoatRoughness
        }
        if spec.opacity < 1 {
            m.transparency = CGFloat(spec.opacity)
            if spec.glassShell {
                m.transparencyMode = .dualLayer
            } else {
                // 額の表。両面の硝子にすると膜になって、奥の写真が見えない
                m.transparencyMode = .aOne
                m.writesToDepthBuffer = false
            }
        }
        if let e = spec.emission, spec.emissionIntensity > 0 {
            // 光る面に明暗の絵（反射板の輪・プリズムの筋・織り目）があれば、光の色を掛けて貼る（一色の平らな光にしない）
            if let kind = spec.emissionTexture {
                m.emission.contents = image(key: "emit." + CamperScenePlan.textureKey(kind, e)) { CamperTextures.make(kind).tinted(e) }
                m.emission.wrapS = .repeat
                m.emission.wrapT = .repeat
            } else {
                m.emission.contents = Self.color(e)
            }
            // 夜の光の決まり: 光る面は 1 まで（HDR で白く飛ばさない）
            m.emission.intensity = CGFloat(min(1, spec.emissionIntensity))
        }
    }

    /// 貼り絵（下ごしらえで作った画素があればそれを、無ければその場で作る）
    func image(key: String, make: () -> CamperBitmap) -> CGImage? {
        if let hit = textureCache[key] { return hit }
        let bitmap = bitmaps[key] ?? make()
        guard let made = Self.cgImage(bitmap) else { return nil }
        textureCache[key] = made
        return made
    }

    static func cgImage(_ bitmap: CamperBitmap) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bitmap.rgba) as CFData) else { return nil }
        return CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func color(_ hex: UInt32, alpha: Double = 1) -> UIColor {
        UIColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255,
                alpha: alpha)
    }
}

#endif
