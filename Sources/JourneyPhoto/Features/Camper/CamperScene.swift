import UIKit
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
// Linux で型検査するための SceneKit の模型（Package.swift だけが読む。実機のビルドには入らない）
import ImageIO
import SceneKitShim
#endif

// 写真で作るキャンピングカーを SceneKit で描く（2026-10-18・札 #307）。
//
// 旅のトランク・メダルを回す画面（`MedalViewerView`）と同じく、SwiftUI に `SCNView` を置く。形は素の Swift の
// 組み立て図（`CamperBuilder`）が作り、ここはそれを `SCNNode` に写すだけ。素材は physicallyBased
// （塗装は clearCoat・クロームは metalness 1）、周りの空を映り込みの元に、床は `SCNFloor` の映り込みと太陽の落ち影、
// 車体の下に接地の暗がり。夜は室内の灯り（omni）・前照灯（spot）・尾灯、窓とレンズは emission。iOS 標準だけで無料。
//
// 性能（2026-10-18 判断）: 組み立て図は画面の処理の外で作る。止まっている部品は材質ごとに1つの形へまとめ
// （`flattenedClone`）、描く回数を材質の数（70 前後）に抑える。貼り絵は 256 px まで。画面は動いた時だけ描き直す。

#if canImport(SceneKit) || canImport(SceneKitShim)

/// SceneKit の場面（車・床・光・カメラ）
@MainActor
final class CamperScene {

    /// 板の単位 → SceneKit の単位（車体の長さ 242 → 2.42）
    static let unit = 0.01
    /// 灯りの組: 外（太陽・前照灯・焚き火が照らす）と室内（室内の灯りだけが照らす。太陽と周りの光はどちらも照らす）
    static let outsideMask = 1
    static let insideMask = 2

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let cameraRig = SCNNode()
    private let turntable = SCNNode()
    private let floorNode = SCNNode()
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private var carNode: SCNNode?
    private var doorPivot: SCNNode?
    private var doorGlowNode: SCNNode?
    private var buildTask: Task<Void, Never>?
    private var textureCache: [String: CGImage] = [:]
    /// 下ごしらえの貼り絵（`CamperScenePlan.bitmaps`）
    private var planBitmaps: [String: CamperBitmap] = [:]
    /// 材質（同じ材質は 1 つ。時刻を替えたら値を入れ直す）
    private var materials: [CamperMaterial: SCNMaterial] = [:]
    private var paint: UInt32 = 0x5B6168
    private(set) var currentMood: CamperMood = .day
    /// その時刻だけ見せる部品の組と灯り
    private var moodNodes: [(SCNNode, Set<CamperMood>)] = []
    private var moodLights: [(SCNNode, Set<CamperMood>?)] = []
    /// いま組んである形の鍵（時刻を除いた設定）
    private var builtKey: CamperConfig?

    private(set) var config: CamperConfig?
    private(set) var blueprint: CamperBlueprint?
    private var angle: CamperAngle?
    private var doorOpen = false
    /// 組み終えたら呼ぶ（読み上げの値・画面写真の試験が待つ）
    var onReady: ((String) -> Void)?

    init() {
        buildStage()
    }

    private func buildStage() {
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(CamperFraming.fieldOfView)
        camera.zNear = 0.02
        camera.zFar = 80
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomThreshold = 0.85
        camera.bloomBlurRadius = 10
        // 車体の下と室内の隅の陰（接地の影を強める）
        camera.screenSpaceAmbientOcclusionIntensity = 0.6
        cameraNode.camera = camera
        cameraRig.addChildNode(cameraNode)
        scene.rootNode.addChildNode(cameraRig)
        scene.rootNode.addChildNode(turntable)

        // 床（映り込みと落ち影を受ける。果ては無く、車から離れるほど透けて画面の黒い地に溶ける）
        let floor = SCNFloor()
        floor.reflectionFalloffEnd = 0.8
        floor.reflectionResolutionScaleFactor = 0.5
        floorNode.geometry = floor
        scene.rootNode.addChildNode(floorNode)

        // 太陽（影を落とす）と、ほんの少しの環境光
        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowRadius = 4
        sun.shadowSampleCount = 16
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.automaticallyAdjustsShadowProjection = true
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    // MARK: 時刻・天気

    private func applyMood(_ mood: CamperMood) {
        let env = image(key: "env.\(mood.rawValue)") { CamperTextures.environment(mood) }
        scene.lightingEnvironment.contents = env
        // 周りの光を強め、太陽を少し弱める（塗装の clearCoat に空と光の箱が映る。run 529 では映り込みが弱かった）
        scene.lightingEnvironment.intensity = CGFloat(mood == .night ? 0.14 : (mood == .snow ? 1.45 : 1.35))
        // 板の光の向き（画面基準）: 昼 (−0.18, −0.72, 0.62)・夜の月 (0.45, −0.6, 0.55)。板は下が +y
        let from = mood == .night ? CV3(0.45, 0.6, 0.55) : CV3(-0.18, 0.72, 0.62)
        let q = CQuat.rotation(from: CV3(0, 0, -1), to: -from)
        sunNode.orientation = SCNQuaternion(Float(q.x), Float(q.y), Float(q.z), Float(q.w))
        // 夜の月は車体の形が読める強さ（縁に青白いリムが乗る程度・run 538 で車が影絵になった）
        sunNode.light?.intensity = CGFloat(mood == .night ? 260 : (mood == .snow ? 1000 : 1200))
        sunNode.light?.color = mood == .night ? Self.color(0x9FB4DC) : Self.color(0xFFF4E2)
        // 板: 影の色 #1a2230 0.5・雪は #3a5270 0.35・夜は出さない
        sunNode.light?.shadowColor = mood == .snow ? Self.color(0x3A5270, alpha: 0.35)
            : Self.color(0x000000, alpha: mood == .night ? 0.15 : 0.5)
        ambientNode.light?.intensity = CGFloat(mood == .night ? 60 : 0)
        // 夜はにじみ（bloom）を使わない（2026-10-18 Mac の絵 run 533）。艶の強い面に近くの灯りが当たると HDR の値が
        // 半精度の上限を超え、にじみの縮小の段で黒い四角に広がった（見立て）。昼はにじむほどの光が無いので残す
        cameraNode.camera?.bloomIntensity = CGFloat(mood == .night ? 0 : 0.2)
        // 夜は露出を少し下げる（口の中・窓の灯りを白く飛ばさない）
        cameraNode.camera?.exposureOffset = CGFloat(mood == .night ? -0.15 : 0)
        cameraNode.camera?.bloomThreshold = CGFloat(mood == .night ? 1.3 : 0.85)

        // 床: 暗い一色。透け具合は車からの距離で（絵は貼らない・`CamperFloor`）
        let f = CamperMaterials.floor(mood)
        let floorMaterial = SCNMaterial()
        floorMaterial.lightingModel = .physicallyBased
        floorMaterial.diffuse.contents = Self.color(f.color)
        floorMaterial.roughness.contents = f.roughness
        floorMaterial.metalness.contents = 0.0
        floorMaterial.blendMode = .alpha
        floorMaterial.shaderModifiers = [.fragment: f.shaderModifier]
        floorNode.geometry?.materials = [floorMaterial]
        (floorNode.geometry as? SCNFloor)?.reflectivity = CGFloat(f.reflectivity)
    }

    /// 昼・夜・雪を切り替える（組み直さない。光・材質の値・その時刻だけの部品と灯りの見せる／隠すだけ）
    func setMood(_ mood: CamperMood) {
        currentMood = mood
        applyMood(mood)
        for (m, scn) in materials { configure(scn, CamperMaterials.spec(m, paint: paint, mood: mood)) }
        for (node, moods) in moodNodes { node.isHidden = !moods.contains(mood) }
        // その時刻でない灯りはノードごと隠す（強さ 0 で残すと、影ありの spot が昼にも影の絵を描き、光の数にも数えられる）
        for (node, moods) in moodLights { node.isHidden = !(moods.map { $0.contains(mood) } ?? true) }
    }

    // MARK: 組み立て

    /// 飾り・段が変わったら組み直す（下ごしらえは画面の処理の外で作る）。時刻・天気だけなら組み直さない
    func show(_ next: CamperConfig) {
        guard next != config else { return }
        config = next
        if builtKey == next.buildKey, blueprint != nil {
            buildTask?.cancel()
            setMood(next.mood)
            onReady?(Self.marker(next, blueprint: blueprint, ms: 0))
            return
        }
        buildTask?.cancel()
        let started = Date()
        buildTask = Task { [weak self] in
            let plan = await Task.detached(priority: .userInitiated) { CamperScenePlan.make(next) }.value
            guard !Task.isCancelled, let self, let now = self.config, now.buildKey == next.buildKey else { return }
            self.install(plan, config: now)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            self.onReady?(Self.marker(now, blueprint: plan.blueprint, ms: ms))
        }
    }

    /// 組み終えた合図（画面写真の試験が待つ）
    static func marker(_ c: CamperConfig, blueprint: CamperBlueprint?, ms: Int) -> String {
        "camper-ready \(c.stage.rawValue) \(c.mood.rawValue) tris=\(blueprint?.triangleEstimate ?? 0) ms=\(ms)"
    }

    /// 試験用: 下ごしらえから組むまでを、いまの処理の中で（Linux の試験で組み上げた場面を確かめる）
    func installNow(_ next: CamperConfig) {
        config = next
        install(CamperScenePlan.make(next), config: next)
    }

    private func install(_ plan: CamperScenePlan, config: CamperConfig) {
        let bp = plan.blueprint
        planBitmaps = plan.bitmaps
        paint = config.loadout.paint
        currentMood = config.mood
        materials = [:]
        moodNodes = []
        moodLights = []
        builtKey = config.buildKey
        let s = Self.unit
        let body = SCNNode()
        let inside = SCNNode()
        let door = SCNNode()
        // その時刻だけの部品（雪・夜の電球など）。時刻と灯りの組ごとに別にまとめ、見せる・隠すで切り替える
        var moodGroups: [String: (node: SCNNode, moods: Set<CamperMood>, inside: Bool)] = [:]
        // 地面の灯りの溜まり（まとめず・影を落とさない）。扉の口の溜まりは扉を開けた時だけ見せる
        let glow = SCNNode()
        let doorGlow = SCNNode()
        for prepared in plan.nodes {
            let spec = prepared.spec
            guard let geometry = makeGeometry(prepared) else { continue }
            let node = SCNNode(geometry: geometry)
            node.name = spec.name
            node.orientation = SCNQuaternion(Float(spec.orientation.x), Float(spec.orientation.y), Float(spec.orientation.z),
                                             Float(spec.orientation.w))
            if case .text = spec.shape {
                // 字の高さを合わせ、真ん中を置き場所に（SCNText は字の大きさで形が決まる）
                let (lo, hi) = geometry.boundingBox
                let h = max(0.001, Double(hi.y - lo.y))
                let k = spec.shape.textHeight / h * s
                node.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z)
                node.scale = SCNVector3(Float(k), Float(k), Float(k))
            } else {
                node.scale = SCNVector3(Float(spec.scale.x), Float(spec.scale.y), Float(spec.scale.z))
            }
            if spec.group == .door {
                node.position = Self.vector((spec.position - bp.doorHinge) * s)
                door.addChildNode(node)
            } else if spec.group == .glow || spec.group == .doorGlow {
                node.position = Self.vector(spec.position * s)
                node.castsShadow = false
                // 床（不透明の組）を描いた後に足す
                node.renderingOrder = 10
                (spec.group == .glow ? glow : doorGlow).addChildNode(node)
            } else if let moods = spec.moods {
                node.position = Self.vector(spec.position * s)
                let key = "\(moods.map(\.rawValue).sorted()) \(prepared.inside)"
                let holder = moodGroups[key]?.node ?? SCNNode()
                holder.addChildNode(node)
                moodGroups[key] = (holder, moods, prepared.inside)
            } else {
                node.position = Self.vector(spec.position * s)
                (prepared.inside ? inside : body).addChildNode(node)
            }
        }
        let car = SCNNode()
        // 止まっている部品は材質ごとにまとめる（描く回数を減らす）。室内と外は灯りの組が違うので別々に
        let bodyFlat = body.flattenedClone()
        bodyFlat.name = "camper.outside"
        Self.mask(bodyFlat, Self.outsideMask)
        car.addChildNode(bodyFlat)
        let insideFlat = inside.flattenedClone()
        insideFlat.name = "camper.inside"
        Self.mask(insideFlat, Self.insideMask)
        car.addChildNode(insideFlat)
        for (key, group) in moodGroups.sorted(by: { $0.key < $1.key }) {
            let flat = group.node.flattenedClone()
            flat.name = "camper.mood \(key)"
            Self.mask(flat, group.inside ? Self.insideMask : Self.outsideMask)
            car.addChildNode(flat)
            moodNodes.append((flat, group.moods))
        }
        let pivot = SCNNode()
        pivot.position = Self.vector(bp.doorHinge * s)
        let doorFlat = door.flattenedClone()
        doorFlat.name = "camper.door"
        Self.mask(doorFlat, Self.outsideMask)
        pivot.addChildNode(doorFlat)
        pivot.eulerAngles = SCNVector3(0, Float(doorOpen ? bp.doorOpenAngle : 0), 0)
        car.addChildNode(pivot)
        glow.castsShadow = false
        doorGlow.castsShadow = false
        doorGlow.opacity = doorOpen ? 1 : 0
        car.addChildNode(glow)
        car.addChildNode(doorGlow)
        // 地面の灯りの溜まりは夜だけ
        moodNodes.append((glow, [.night]))
        moodNodes.append((doorGlow, [.night]))
        // 灯り（夜）
        for light in bp.lights {
            let l = SCNLight()
            l.type = light.kind == .spot ? .spot : .omni
            l.color = Self.color(light.color)
            l.intensity = CGFloat(light.intensity)
            l.attenuationStartDistance = 0
            l.attenuationEndDistance = CGFloat(light.range * s)
            l.attenuationFalloffExponent = 2
            // 室内の灯りは室内だけ、外の灯りは外だけ（影を落とさない omni が壁を抜けないように）
            l.categoryBitMask = light.inside ? Self.insideMask : Self.outsideMask
            if light.kind == .spot {
                l.spotInnerAngle = CGFloat(light.spotInner)
                l.spotOuterAngle = CGFloat(light.spotOuter)
            }
            if light.castsShadow {
                // 影はその灯りの光だけを減らす forward で（2026-10-18 Mac の絵 run 538）。deferred は画面の色そのものに
                // 影の色を掛けるので、円錐の外の全部（車体・窓・前照灯）が 0.9 の黒で塗られ、夜が影絵になった
                l.castsShadow = true
                l.shadowMode = .forward
                l.shadowSampleCount = 8
                l.shadowRadius = 3
                l.shadowMapSize = CGSize(width: 1024, height: 1024)
                l.shadowColor = Self.color(0x000000, alpha: 1)
            }
            let n = SCNNode()
            n.name = "light.\(light.name)"
            n.light = l
            n.position = Self.vector(light.position * s)
            if light.kind == .spot {
                let q = CQuat.rotation(from: CV3(0, 0, -1), to: light.direction)
                n.orientation = SCNQuaternion(Float(q.x), Float(q.y), Float(q.z), Float(q.w))
            }
            car.addChildNode(n)
            moodLights.append((n, light.moods))
        }
        // 車体の下の暗がり（板: 楕円・ぼかし・0.75）。床から少し浮かせる
        let len = (bp.length.upperBound - bp.length.lowerBound + 8) * s
        let plane = SCNPlane(width: CGFloat(len), height: CGFloat((bp.halfWidth * 2 + 12) * s))
        let shade = SCNMaterial()
        shade.lightingModel = .constant
        shade.diffuse.contents = image(key: "contact") { CamperTextures.contactShadow().premultiplied() }
        shade.transparencyMode = .aOne
        shade.blendMode = .alpha
        shade.writesToDepthBuffer = false
        plane.materials = [shade]
        let contact = SCNNode(geometry: plane)
        contact.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        contact.position = SCNVector3(Float((bp.length.lowerBound + bp.length.upperBound) / 2 * s), 0.002, 0)
        contact.castsShadow = false
        car.addChildNode(contact)

        carNode?.removeFromParentNode()
        turntable.addChildNode(car)
        carNode = car
        doorPivot = pivot
        doorGlowNode = doorGlow
        blueprint = bp
        setMood(config.mood)
    }

    // MARK: 向き・扉

    /// 見る向き（横の回りは車を回す。見下ろしと寄りはカメラを回す）
    func setAngle(_ a: CamperAngle, animated: Bool) {
        guard a != angle else { return }
        angle = a
        let s = Self.unit
        let yaw = a.yaw * .pi / 180
        // 狙う点も車と一緒に回る
        let t = a.target * s
        let rotated = CV3(t.x * cos(yaw) + t.z * sin(yaw), t.y, -t.x * sin(yaw) + t.z * cos(yaw))
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.6 : 0
        // 板の注記: 指を離すと 0.6 秒 cubic-bezier(.2,.75,.25,1) で止まる
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.75, 0.25, 1)
        turntable.eulerAngles = SCNVector3(0, Float(yaw), 0)
        cameraRig.position = Self.vector(rotated)
        cameraRig.eulerAngles = SCNVector3(Float(-a.elevation * .pi / 180), 0, 0)
        cameraNode.position = SCNVector3(0, 0, Float(CamperFraming.distance(zoom: a.zoom)))
        SCNTransaction.commit()
    }

    /// 扉を開け閉めする（板の注記: 開くは 0.6 秒 ease-out で 100°、閉じるは 0.4 秒）
    func setDoor(open: Bool, animated: Bool) {
        guard open != doorOpen else { return }
        doorOpen = open
        guard let pivot = doorPivot, let bp = blueprint else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? (open ? 0.6 : 0.4) : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1)
        pivot.eulerAngles = SCNVector3(0, Float(open ? bp.doorOpenAngle : 0), 0)
        doorGlowNode?.opacity = open ? 1 : 0
        SCNTransaction.commit()
    }

    func cancel() {
        buildTask?.cancel()
        buildTask = nil
    }

    // MARK: 形と素材

    /// 材質（同じ材質は 1 つを使い回す。時刻を替えたら値だけ入れ直す・`setMood`）
    private func material(_ m: CamperMaterial) -> SCNMaterial {
        if let hit = materials[m] { return hit }
        let made = SCNMaterial()
        configure(made, CamperMaterials.spec(m, paint: paint, mood: currentMood))
        materials[m] = made
        return made
    }

    private func makeGeometry(_ prepared: CamperPreparedNode) -> SCNGeometry? {
        let s = Self.unit
        let spec = prepared.spec
        if let m = prepared.mesh {
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
            g.materials = m.groups.map { material($0.material) }
            return g
        }
        switch spec.shape {
        case .mesh:
            return nil
        case let .box(size, chamfer):
            let b = SCNBox(width: CGFloat(size.x * s), height: CGFloat(size.y * s), length: CGFloat(size.z * s),
                           chamferRadius: CGFloat(chamfer * s))
            b.chamferSegmentCount = chamfer > 0.8 ? 3 : 1
            b.materials = [material(spec.material)]
            return b
        case let .cylinder(radius, height, segments):
            let c = SCNCylinder(radius: CGFloat(radius * s), height: CGFloat(height * s))
            c.radialSegmentCount = max(3, segments)
            c.materials = [material(spec.material)]
            return c
        case let .torus(ring, pipe):
            let t = SCNTorus(ringRadius: CGFloat(ring * s), pipeRadius: CGFloat(pipe * s))
            t.ringSegmentCount = 32
            t.pipeSegmentCount = 10
            t.materials = [material(spec.material)]
            return t
        case .sphere(let radius):
            let sp = SCNSphere(radius: CGFloat(radius * s))
            sp.segmentCount = 18
            sp.materials = [material(spec.material)]
            return sp
        case let .text(string, _, depth):
            let t = SCNText(string: string, extrusionDepth: CGFloat(depth * 10))
            t.font = UIFont.systemFont(ofSize: 10, weight: .bold)
            t.flatness = 0.2
            t.materials = [material(spec.material)]
            return t
        }
    }

    /// 材質に値を入れる（作る時と、時刻を替えた時。前の時刻の値が残らないよう、全部入れ直す）
    private func configure(_ m: SCNMaterial, _ spec: CamperMaterialSpec) {
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
            m.lightingModel = .constant
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
            m.transparencyMode = .dualLayer
        }
        if let e = spec.emission, spec.emissionIntensity > 0 {
            m.emission.contents = Self.color(e)
            m.emission.intensity = CGFloat(spec.emissionIntensity)
        }
    }

    /// 貼り絵（下ごしらえで作った画素があればそれを、無ければその場で作る）
    private func image(key: String, make: () -> CamperBitmap) -> CGImage? {
        if let hit = textureCache[key] { return hit }
        let bitmap = planBitmaps[key] ?? make()
        guard let provider = CGDataProvider(data: Data(bitmap.rgba) as CFData),
              let made = CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        textureCache[key] = made
        return made
    }

    /// 灯りの組をまとめた形の下の全部に付ける（まとめた結果が子を持つ場合にも効くように）
    static func mask(_ node: SCNNode, _ bits: Int) {
        node.categoryBitMask = bits
        for child in node.childNodes { mask(child, bits) }
    }

    static func vector(_ v: CV3) -> SCNVector3 { SCNVector3(Float(v.x), Float(v.y), Float(v.z)) }

    static func color(_ hex: UInt32, alpha: Double = 1) -> UIColor {
        UIColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255,
                alpha: alpha)
    }
}

#endif

extension CamperShape {
    /// 字の高さ（文字のときだけ）
    var textHeight: Double {
        if case let .text(_, height, _) = self { return height }
        return 1
    }
}
