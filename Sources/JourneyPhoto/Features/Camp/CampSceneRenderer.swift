#if canImport(SceneKit)
import SceneKit
import SwiftUI
import UIKit
import simd

/// キャンプ場の島を SceneKit で描く（板の付箋: SwiftUI に SCNView・島は押し出し・太陽は directional で影・
/// 炎と火の粉は SCNParticleSystem。iOS 標準だけ）。
///
/// - 形は `CampSceneBuilder` が板の座標で組んだ一覧。ここは y を返して SceneKit の節にするだけ
/// - 向きは板と同じく**島の側を回す**（カメラは正面に止めたまま。太陽も島と一緒に回る＝板の `world: true`）
/// - 指で回す: 横 0.6°・縦 0.4° / pt、縦は −75°〜0°。回している間は細い線（草・縫い目の筒・苔）を隠す
/// - 時刻を変えると、空・芝・葉の色と太陽の向きを 0.8 秒で移す（付箋「動き」の案）
struct CampSceneView: UIViewRepresentable {
    let options: CampSceneOptions
    let angle: CampAngle
    var zoom: Double = 1
    var interactive = true
    var reduceMotion = false
    /// いま立てた切り絵（奥から 0.12 秒ずつ遅れて台に差さる）
    var justPlaced: String? = nil
    let images: CampCutoutImages
    var onAngle: ((CampAngle) -> Void)? = nil

    func makeCoordinator() -> CampSceneCoordinator { CampSceneCoordinator() }

    func makeUIView(context: Context) -> CampSCNView {
        let view = CampSCNView(frame: .zero, options: nil)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.isPlaying = true
        view.loops = true
        let coordinator = context.coordinator
        coordinator.view = view
        view.onLayout = { [weak coordinator] size in coordinator?.resize(size) }
        if interactive {
            let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(CampSceneCoordinator.handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)
            let reset = UITapGestureRecognizer(target: coordinator, action: #selector(CampSceneCoordinator.handleReset(_:)))
            reset.numberOfTapsRequired = 2
            view.addGestureRecognizer(reset)
        }
        coordinator.apply(self, animated: false)
        return view
    }

    func updateUIView(_ view: CampSCNView, context: Context) {
        context.coordinator.apply(self, animated: !reduceMotion)
    }

    static func dismantleUIView(_ view: CampSCNView, coordinator: CampSceneCoordinator) {
        view.isPlaying = false
    }
}

/// 大きさが決まったら知らせる SCNView（画角は高さで決まる・板の `persp`）
final class CampSCNView: SCNView {
    var onLayout: ((CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.size)
    }
}

@MainActor
final class CampSceneCoordinator: NSObject {

    let scene = SCNScene()
    let cameraNode = SCNNode()
    /// 島を回す節と、寄る先へずらす節
    private let pivot = SCNNode()
    private let world = SCNNode()
    private var content = SCNNode()
    private var effects = SCNNode()
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private var detailNodes: [SCNNode] = []
    private var materials: [CampMaterialKey: SCNMaterial] = [:]
    private var builtGeometry: CampSceneOptions?
    private var builtTime: CampTime?
    private var lookTime: CampTime?
    private var lookSeason: CampSeason?
    private var size: CGSize = .zero
    private var zoom = 1.0
    private(set) var angle = CampAngle.resting
    private var requestedAngle: CampAngle?
    private var dragStart: CampAngle?
    private var images: CampCutoutImages = { _, _ in nil }
    private var onAngle: ((CampAngle) -> Void)?
    private var animatedPlacements: Set<String> = []
    private var options = CampSceneOptions()
    weak var view: SCNView?

    override init() {
        super.init()
        let camera = SCNCamera()
        camera.zNear = 1
        camera.zFar = 4000
        camera.wantsHDR = false
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(pivot)
        pivot.addChildNode(world)
        world.addChildNode(content)
        world.addChildNode(effects)

        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMode = .forward
        sun.shadowSampleCount = 16
        sun.shadowRadius = 3
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.automaticallyAdjustsShadowProjection = true
        sunNode.light = sun
        world.addChildNode(sunNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambientNode.light = ambient
        world.addChildNode(ambientNode)
        scene.background.contents = UIColor.clear
    }

    // MARK: - 受け取る

    func apply(_ v: CampSceneView, animated: Bool) {
        images = v.images
        onAngle = v.onAngle
        zoom = v.zoom
        let o = v.options
        let geometryChanged = builtGeometry.map { !Self.sameGeometry($0, o) } ?? true
        let timeChanged = builtTime != o.time
        options = o
        let built = CampSceneBuilder.build(o)
        if geometryChanged {
            buildGeometry(built, justPlaced: v.justPlaced)
            builtGeometry = o
        }
        if geometryChanged || timeChanged {
            buildEffects(built, o)
            builtTime = o.time
        }
        if lookTime != o.time || lookSeason != o.season || geometryChanged {
            applyLook(o, animated: animated && !geometryChanged)
            lookTime = o.time
            lookSeason = o.season
        }
        if dragStart == nil, requestedAngle != v.angle {
            requestedAngle = v.angle
            setAngle(v.angle, animated: animated && builtGeometry != nil && !geometryChanged)
        }
        updateCamera()
    }

    /// 形が変わる注文か（時刻は光と炎だけを組み直す）
    private static func sameGeometry(_ a: CampSceneOptions, _ b: CampSceneOptions) -> Bool {
        a.stage == b.stage && a.season == b.season && a.focus == b.focus && a.cutouts == b.cutouts && a.placing == b.placing
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        updateCamera()
    }

    /// 板の投影と同じカメラ（目の距離 = 900 / 倍率・画角 = 2 atan(H / 1800)・寄る先が画面の真ん中）
    private func updateCamera() {
        guard size.width > 0, let camera = cameraNode.camera else { return }
        let scale = CampOrbit.scale(focus: options.focus, stage: options.stage, zoom: zoom,
                                    width: Double(size.width), height: Double(size.height))
        camera.fieldOfView = CGFloat(CampOrbit.fieldOfView(height: Double(size.height)))
        camera.projectionDirection = .vertical
        let distance = CampOrbit.cameraDistance(scale: scale)
        cameraNode.position = SCNVector3(0, 0, Float(distance))
        camera.zNear = max(1, distance - 600)
        camera.zFar = distance + 600
        let t = CampOrbit.toScene(options.focus.preset.target)
        world.position = SCNVector3(Float(-t.x), Float(-t.y), Float(-t.z))
    }

    private func setAngle(_ a: CampAngle, animated: Bool) {
        angle = a
        let e = CampOrbit.sceneEuler(a)
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.6
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        pivot.eulerAngles = SCNVector3(Float(e.pitch), Float(e.yaw), 0)
        if animated { SCNTransaction.commit() }
    }

    // MARK: - 指

    @objc func handlePan(_ g: UIPanGestureRecognizer) {
        guard let view = g.view else { return }
        let t = g.translation(in: view)
        switch g.state {
        case .began:
            dragStart = angle
            setDetail(hidden: true)
        case .changed:
            guard let start = dragStart else { return }
            setAngle(CampOrbit.dragged(from: start, dx: Double(t.x), dy: Double(t.y)), animated: false)
        case .ended, .cancelled, .failed:
            // 払った勢いで少しだけ回り続けて止まる（横だけ・0.5 秒）
            let v = g.velocity(in: view)
            let coast = CampOrbit.dragged(from: angle, dx: Double(v.x) * 0.12, dy: 0)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            setAngle(coast, animated: false)
            SCNTransaction.completionBlock = { [weak self] in
                Task { @MainActor in self?.setDetail(hidden: false) }
            }
            SCNTransaction.commit()
            dragStart = nil
            requestedAngle = coast
            onAngle?(coast)
        default:
            break
        }
    }

    /// 2 回叩くと初めの向きへ戻る
    @objc func handleReset(_ g: UITapGestureRecognizer) {
        setAngle(.resting, animated: true)
        requestedAngle = .resting
        onAngle?(.resting)
    }

    private func setDetail(hidden: Bool) {
        for n in detailNodes { n.isHidden = hidden }
    }

    // MARK: - 形

    private func buildGeometry(_ built: CampScene, justPlaced: String?) {
        content.removeFromParentNode()
        content = SCNNode()
        world.insertChildNode(content, at: 0)
        detailNodes = []
        var cutoutGroups: [String: SCNNode] = [:]
        for piece in built.pieces {
            guard let node = makeNode(piece) else { continue }
            node.castsShadow = piece.castsShadow
            if piece.detail { detailNodes.append(node) }
            if let id = piece.cutout {
                // 切り絵は層ごとにまとめる（立てる動き）
                // 層の無いもの（台・溝）は「base」
                let key = id + "#" + (piece.layer.map(String.init) ?? "base")
                let group: SCNNode
                if let existing = cutoutGroups[key] {
                    group = existing
                } else {
                    group = SCNNode()
                    group.name = key
                    content.addChildNode(group)
                    cutoutGroups[key] = group
                }
                group.addChildNode(node)
            } else {
                content.addChildNode(node)
            }
        }
        // いま立てた切り絵: 奥から 0.12 秒ずつ遅れて台に差さり、最後に 2% 沈んで戻る（付箋「動き」の案）
        if let id = justPlaced, !animatedPlacements.contains(id) {
            animatedPlacements.insert(id)
            for (key, group) in cutoutGroups where key.hasPrefix(id + "#") {
                let layer = Int(key.split(separator: "#").last ?? "") ?? -1
                let delay = Double(max(0, layer)) * 0.12
                group.position.y += 9
                group.opacity = layer < 0 ? 1 : 0.0
                let drop = SCNAction.move(by: SCNVector3(0, -9.6, 0), duration: 0.34)
                drop.timingMode = .easeIn
                let settle = SCNAction.move(by: SCNVector3(0, 0.6, 0), duration: 0.16)
                settle.timingMode = .easeOut
                group.runAction(.sequence([.wait(duration: delay), .group([drop, .fadeIn(duration: 0.12)]), settle]))
            }
        }
    }

    private func material(_ key: CampMaterialKey) -> SCNMaterial {
        if let m = materials[key] { return m }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        materials[key] = m
        return m
    }

    private func makeNode(_ piece: CampPiece) -> SCNNode? {
        let m = material(piece.material)
        switch piece.shape {
        case .mesh(let mesh):
            guard let geometry = Self.geometry(mesh) else { return nil }
            geometry.materials = [m]
            return SCNNode(geometry: geometry)
        case let .box(center, size, chamfer, yaw, roll, top):
            let r = max(0, min(chamfer, min(size.x, size.y, size.z) / 2 - 0.01))
            let box = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: CGFloat(r))
            if let top {
                // 面の並びは 前・右・後ろ・左・上・下
                box.materials = [m, m, m, m, material(top), m]
            } else {
                box.materials = [m]
            }
            let node = SCNNode(geometry: box)
            node.position = Self.vector(CampOrbit.toScene(center))
            node.eulerAngles = SCNVector3(0, Float(yaw * .pi / 180), Float(-roll * .pi / 180))
            return node
        case let .tube(from, to, radius, caps):
            let a = CampOrbit.toScene(from), b = CampOrbit.toScene(to)
            let length = (b - a).length
            guard length > 0.001 else { return nil }
            let cylinder = SCNCylinder(radius: CGFloat(radius), height: CGFloat(length))
            cylinder.radialSegmentCount = radius < 1 ? 8 : 16
            if let caps, caps.count == 2 {
                // 筒の面の並びは 胴・上（終わり）・下（始まり）
                cylinder.materials = [m, material(caps[1]), material(caps[0])]
            } else {
                cylinder.materials = [m]
            }
            return Self.oriented(SCNNode(geometry: cylinder), from: a, to: b)
        case let .taper(from, to, r0, r1):
            let a = CampOrbit.toScene(from), b = CampOrbit.toScene(to)
            let length = (b - a).length
            guard length > 0.001 else { return nil }
            let cone = SCNCone(topRadius: CGFloat(r1), bottomRadius: CGFloat(r0), height: CGFloat(length))
            cone.radialSegmentCount = 12
            cone.materials = [m]
            return Self.oriented(SCNNode(geometry: cone), from: a, to: b)
        case let .ring(center, radius, pipe):
            let torus = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: CGFloat(pipe))
            torus.materials = [m]
            let node = SCNNode(geometry: torus)
            node.position = Self.vector(CampOrbit.toScene(center))
            return node
        }
    }

    /// 円柱・円錐（縦の軸が y）を a → b に向けて置く
    private static func oriented(_ node: SCNNode, from a: CampVec3, to b: CampVec3) -> SCNNode {
        let mid = CampVec3.mix(a, b, 0.5)
        node.position = vector(mid)
        let dir = (b - a).normalized
        let q = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(Float(dir.x), Float(dir.y), Float(dir.z)))
        node.simdOrientation = q
        return node
    }

    private static func vector(_ v: CampVec3) -> SCNVector3 { SCNVector3(Float(v.x), Float(v.y), Float(v.z)) }

    /// 板の座標の網を SceneKit の形に（y を返し、三角の向きを入れ替える）
    static func geometry(_ mesh: CampMesh) -> SCNGeometry? {
        guard !mesh.isEmpty else { return nil }
        let vertices = mesh.positions.map { SCNVector3(Float($0.x), Float(-$0.y), Float($0.z)) }
        let normals = mesh.normals.map { SCNVector3(Float($0.x), Float(-$0.y), Float($0.z)) }
        let uvs = mesh.uvs.map { CGPoint(x: $0.x, y: $0.y) }
        var sources = [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                       SCNGeometrySource(textureCoordinates: uvs)]
        if mesh.colors.count == mesh.positions.count {
            var floats: [Float] = []
            floats.reserveCapacity(mesh.colors.count * 3)
            for c in mesh.colors { floats += [Float(c.x), Float(c.y), Float(c.z)] }
            let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
            sources.append(SCNGeometrySource(data: data, semantic: .color, vectorCount: mesh.colors.count,
                                             usesFloatComponents: true, componentsPerVector: 3,
                                             bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                             dataStride: MemoryLayout<Float>.size * 3))
        }
        var indices: [Int32] = []
        indices.reserveCapacity(mesh.indices.count)
        var i = 0
        while i + 2 < mesh.indices.count {
            indices += [mesh.indices[i], mesh.indices[i + 2], mesh.indices[i + 1]]
            i += 3
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: sources, elements: [element])
    }

    // MARK: - 素材と光

    private func applyLook(_ o: CampSceneOptions, animated: Bool) {
        let light = CampLighting.of(time: o.time, season: o.season)
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.8
        }
        for (key, m) in materials {
            let spec = CampMaterials.spec(key, season: o.season, time: o.time)
            Self.configure(m, spec, images: images)
        }
        // 太陽（夜は月）: 板の L は「光の来る向き」。SceneKit の光は節の −z へ進む
        let l = CampOrbit.toScene(light.sun)
        sunNode.position = SCNVector3(Float(l.x * 300), Float(l.y * 300), Float(l.z * 300))
        sunNode.look(at: SCNVector3(0, 0, 0))
        let night = o.time == .night
        if let sun = sunNode.light {
            sun.intensity = CGFloat(light.diffuse * 1500)
            if night {
                // 青白い月（縁にだけ乗る）。白の拡散だと島全体が灰になる
                sun.color = UIColor(red: 0.55, green: 0.62, blue: 0.88, alpha: 1)
            } else {
                let tint = light.sunTint
                sun.color = UIColor(red: min(1, 1 + CGFloat(tint[0]) / 400), green: min(1, 0.97 + CGFloat(tint[1]) / 400),
                                    blue: min(1, 0.92 + CGFloat(tint[2]) / 400), alpha: 1)
            }
            sun.castsShadow = light.shadowOpacity > 0
            sun.shadowColor = CampTexturePainter.color(light.shadow, CGFloat(light.shadowOpacity))
        }
        if let ambient = ambientNode.light {
            // 夜の環境光は冷たい青灰（焚き火の暖色と対比）。白だと影が消える
            ambient.intensity = CGFloat(light.ambient * (night ? 720 : 900))
            ambient.color = night ? UIColor(red: 0.32, green: 0.38, blue: 0.52, alpha: 1) : UIColor.white
        }
        scene.lightingEnvironment.contents = CampTexturePainter.environment(o.time, season: o.season)
        // 夜の周りの光はごく弱く。強いと色温度の対比が消える
        scene.lightingEnvironment.intensity = night ? 0.08 : 0.7
        if animated { SCNTransaction.commit() }
    }

    static func configure(_ m: SCNMaterial, _ spec: CampMaterialSpec, images: CampCutoutImages) {
        let base = CampTexturePainter.color(spec.color)
        if let texture = spec.texture, let image = CampTexturePainter.image(texture, color: spec.color, images: images) {
            m.diffuse.contents = image
            if case .cutout = texture {
                m.diffuse.wrapS = .clamp
                m.diffuse.wrapT = .clamp
            } else {
                m.diffuse.wrapS = .repeat
                m.diffuse.wrapT = .repeat
            }
            m.diffuse.mipFilter = .linear
        } else {
            m.diffuse.contents = base
        }
        if spec.unlit {
            m.lightingModel = .constant
        } else {
            m.lightingModel = .physicallyBased
            m.roughness.contents = NSNumber(value: spec.roughness)
            m.metalness.contents = NSNumber(value: spec.metalness)
            m.clearCoat.contents = NSNumber(value: spec.clearCoat)
        }
        if let e = spec.emission {
            // 光る面は emissionTexture（夜のテントの透光図）があればそれ、無ければ texture
            let emitKind = spec.emissionTexture ?? spec.texture
            if let texture = emitKind, case .cutout = texture {
                m.emission.contents = CampTexturePainter.color(e)
            } else if let texture = emitKind,
                      let image = CampTexturePainter.image(texture, color: e, images: images) {
                m.emission.contents = image
                m.emission.wrapS = .clamp
                m.emission.wrapT = .clamp
            } else {
                m.emission.contents = CampTexturePainter.color(e)
            }
            m.emission.intensity = spec.unlit ? 0 : CGFloat(min(1, max(0, spec.emissionIntensity)))
        } else {
            m.emission.contents = UIColor.black
            m.emission.intensity = 0
        }
        m.isDoubleSided = spec.doubleSided
        m.transparency = CGFloat(spec.opacity)
        m.blendMode = .alpha
    }

    // MARK: - 炎・火の粉・煙・灯り・置く輪

    private func buildEffects(_ built: CampScene, _ o: CampSceneOptions) {
        effects.removeFromParentNode()
        effects = SCNNode()
        world.addChildNode(effects)
        for l in built.lights {
            let light = SCNLight()
            light.type = .omni
            light.color = CampTexturePainter.color(l.color)
            light.intensity = CGFloat(l.intensity * 700)
            light.attenuationStartDistance = 0
            light.attenuationEndDistance = CGFloat(l.range * 2.2)
            // 1.0 で距離の二乗に近い落ち方（白い芯を避け、芝へなだらかに）
            light.attenuationFalloffExponent = 1.0
            // 夜の焚き火の広がりは影を落とさない（芯だけが形を読む）
            light.castsShadow = false
            let node = SCNNode()
            node.light = light
            node.position = Self.vector(CampOrbit.toScene(l.position))
            effects.addChildNode(node)
        }
        if let flame = built.flame { effects.addChildNode(Self.flameNode(flame.position, height: flame.height, opacity: flame.opacity)) }
        if let p = built.sparks { effects.addChildNode(Self.sparks(at: p)) }
        if let smoke = built.smoke {
            effects.addChildNode(Self.smoke(at: smoke.position, opacity: smoke.opacity, dusk: o.time == .evening))
        }
        for g in built.glows {
            effects.addChildNode(Self.glow(at: g.position, radius: g.radius, opacity: g.opacity))
        }
        // 芝の上の焚き火の明かりの輪（夜 80 × 70・夕 46 × 40）。島の上の面の形で切る
        let light = CampLighting.of(time: o.time, season: o.season)
        if let ring = light.fireGlow, built.flame != nil,
           let node = Self.groundDecal(built.topOutline, center: CampLighting.firePosition, rx: ring.0, rz: ring.1,
                                       image: CampTexturePainter.warmGlow(), additive: true,
                                       opacity: o.time == .night ? 0.5 : 0.4) {
            effects.addChildNode(node)
        }
        if let s = built.placeShadow,
           let node = Self.groundDecal(built.topOutline, center: s.center, rx: s.rx, rz: s.rz,
                                       image: CampTexturePainter.softShadow(), additive: false, opacity: 1) {
            effects.addChildNode(node)
        }
        if let r = built.placeRing,
           let node = Self.groundDecal(built.topOutline, center: r.center, rx: r.rx + 1, rz: r.rz + 1,
                                       image: CampTexturePainter.placeRing(rx: r.rx, rz: r.rz), additive: false, opacity: 1,
                                       lift: 0.5) {
            node.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.9), .fadeOpacity(to: 1, duration: 0.9)])))
            effects.addChildNode(node)
        }
    }

    /// 島の上の面に貼る薄い絵（芝の上だけに出る＝板の `topClip`）
    private static func groundDecal(_ outline: [CampVec2], center: CampVec3, rx: Double, rz: Double, image: UIImage,
                                    additive: Bool, opacity: Double, lift: Double = 0.2) -> SCNNode? {
        guard !outline.isEmpty else { return nil }
        var mesh = CampMesh()
        let pts = outline.map { CampVec3($0.x, -lift, $0.y) }
        mesh.flatPolygon(pts, outward: CampVec3(0, -1, 0),
                         uv: outline.map { CampVec2(($0.x - center.x) / (2 * rx) + 0.5, ($0.y - center.z) / (2 * rz) + 0.5) })
        guard let geometry = geometry(mesh) else { return nil }
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        // 絵の縁は透明に描いてある（はみ出した所は何も出ない）
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.blendMode = additive ? .add : .alpha
        m.writesToDepthBuffer = false
        m.transparency = CGFloat(opacity)
        geometry.materials = [m]
        let node = SCNNode(geometry: geometry)
        node.castsShadow = false
        node.renderingOrder = 5
        return node
    }

    /// 揺れる 3 層の炎（0.9 秒・縦 0.94〜1.08 倍・傾き ±3°・行って戻る）
    private static func flameNode(_ base: CampVec3, height: Double, opacity: Double) -> SCNNode {
        let holder = SCNNode()
        holder.position = vector(CampOrbit.toScene(base))
        let face = SCNBillboardConstraint()
        face.freeAxes = .Y
        holder.constraints = [face]
        let flicker = SCNNode()
        holder.addChildNode(flicker)
        let w = height * 0.68
        for layer in 0..<3 {
            let plane = SCNPlane(width: CGFloat(w), height: CGFloat(height))
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = CampTexturePainter.flame(layer: layer)
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            m.transparency = CGFloat(opacity)
            plane.materials = [m]
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(0, Float(height / 2), Float(layer) * 0.05)
            node.castsShadow = false
            node.renderingOrder = 10 + layer
            flicker.addChildNode(node)
        }
        let keys: [(t: Double, sx: Double, sy: Double, rot: Double)] = [(0, 1, 1, 0), (0.35, 0.96, 1.08, -3), (0.7, 1.03, 0.94, 2),
                                                                          (1, 0.98, 1.04, -1)]
        let action = SCNAction.customAction(duration: 1.8) { node, elapsed in
            let t = Double(elapsed)
            var p = t < 0.9 ? t / 0.9 : 2 - t / 0.9
            p = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
            var k = 0
            while k < keys.count - 2 && p > keys[k + 1].t { k += 1 }
            let a = keys[k], b = keys[k + 1]
            let f = max(0, min(1, (p - a.t) / (b.t - a.t)))
            let sx = a.sx + (b.sx - a.sx) * f, sy = a.sy + (b.sy - a.sy) * f, rot = a.rot + (b.rot - a.rot) * f
            node.scale = SCNVector3(Float(sx), Float(sy), 1)
            node.eulerAngles = SCNVector3(0, 0, Float(rot * .pi / 180))
        }
        flicker.runAction(.repeatForever(action))
        return holder
    }

    /// 火の粉（2.2 秒で 60 上がって消える）
    private static func sparks(at p: CampVec3) -> SCNNode {
        let ps = SCNParticleSystem()
        ps.particleImage = CampTexturePainter.softDot()
        ps.birthRate = 3
        ps.particleLifeSpan = 2.2
        ps.particleLifeSpanVariation = 0.4
        ps.particleSize = 1.1
        ps.particleSizeVariation = 0.4
        ps.particleColor = CampTexturePainter.color(0xFFD27A)
        ps.particleColorVariation = SCNVector4(0.04, 0.1, 0.1, 0)
        ps.blendMode = .additive
        ps.emitterShape = SCNSphere(radius: 3)
        ps.birthLocation = .volume
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.spreadingAngle = 14
        ps.particleVelocity = 27
        ps.particleVelocityVariation = 6
        ps.isLocal = true
        ps.isAffectedByGravity = false
        let fade = CAKeyframeAnimation()
        fade.values = [0, 0.9, 0]
        fade.keyTimes = [0, 0.2, 1]
        ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        let node = SCNNode()
        node.position = vector(CampOrbit.toScene(p))
        node.addParticleSystem(ps)
        return node
    }

    /// 煙（4 秒で上がりながら広がって消える）
    private static func smoke(at p: CampVec3, opacity: Double, dusk: Bool) -> SCNNode {
        let ps = SCNParticleSystem()
        ps.particleImage = CampTexturePainter.softDot()
        // 板の煙は太さ 7・60% に縮めた細い筋（4 秒で 90 上がる）。粒は小さく、薄く重ねて筋に見せる
        ps.birthRate = 6
        ps.particleLifeSpan = 4
        ps.particleSize = 1.6
        ps.particleColor = CampTexturePainter.color(dusk ? 0xC9A48A : 0xE8E6E0, CGFloat(0.3 * opacity))
        ps.blendMode = .alpha
        ps.emitterShape = SCNSphere(radius: 2)
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.spreadingAngle = 4
        ps.particleVelocity = 22
        ps.acceleration = SCNVector3(1.2, 0, 0)
        ps.isLocal = true
        let grow = CAKeyframeAnimation()
        grow.values = [1.6, 2.6, 3.6]
        grow.keyTimes = [0, 0.5, 1]
        let fade = CAKeyframeAnimation()
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.2, 1]
        ps.propertyControllers = [.size: SCNParticlePropertyController(animation: grow),
                                  .opacity: SCNParticlePropertyController(animation: fade)]
        let node = SCNNode()
        node.position = vector(CampOrbit.toScene(p))
        node.addParticleSystem(ps)
        return node
    }

    /// 柔らかく光る輪（カメラの方を向く板）
    private static func glow(at p: CampVec3, radius: Double, opacity: Double) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(radius * 2), height: CGFloat(radius * 2))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = CampTexturePainter.warmGlow()
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        m.transparency = CGFloat(opacity)
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.position = vector(CampOrbit.toScene(p))
        node.constraints = [SCNBillboardConstraint()]
        node.castsShadow = false
        node.renderingOrder = 20
        return node
    }
}
#endif
