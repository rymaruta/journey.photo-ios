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
// 車体の下に接地の暗がり。夜は室内の灯り（下向きの spot）・入口の灯り（spot）・外の火、窓と電球は emission。
// 停めている車なので前照灯・尾灯は点けない（2026-10-19。レンズは透ける硝子で、周りの灯りを映すだけ）。iOS 標準だけで無料。
//
// 性能（2026-10-18 判断）: 組み立て図は画面の処理の外で作る。止まっている部品は材質ごとに1つの形へまとめ
// （`flattenedClone`）、描く回数を材質の数（70 前後）に抑える。貼り絵は 256 px まで。画面は動いた時だけ描き直す。

#if canImport(SceneKit) || canImport(SceneKitShim)

/// SceneKit の場面（車・床・光・カメラ）
@MainActor
final class CamperScene {

    /// 板の単位 → SceneKit の単位（車体の長さ 242 → 2.42）
    static let unit = 0.01
    /// 灯りの組: 外（月・入口の灯り・焚き火・ランタンが照らす）と室内（室内の灯りだけが照らす。太陽・月と周りの光はどちらも照らす）
    static let outsideMask = 1
    static let insideMask = 2
    /// 外の置き物（椅子・机・焚き火・外の灯り・敷物）と地面。焚き火・ランタン・電球の列はこの組だけを照らす
    /// （2026-10-21 判断・確かめ役: 艶の強い塗装に火の照り返しが小さな橙の点で映り、宙に浮いた灯りに見えた。
    /// 車体は月と空の光と入口の灯りで読ませ、火は地面と小物になだらかに落とす）
    static let propsMask = 4
    /// 外の置き物の分類
    static let propCategories: Set<CamperCategory> = [.chair, .table, .firePit, .outdoorLight, .rug]

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let cameraRig = SCNNode()
    private let turntable = SCNNode()
    private let floorNode = SCNNode()
    /// 夜の外の地面と遠景（2026-10-21・`CamperMaterials.NightStage`）。夜にはじめて替えた時に作る
    private let nightStageNode = SCNNode()
    private var nightStageBuilt = false
    /// 下ごしらえで作った夜の遠景の網（`CamperScenePlan.nightScenery`）
    private var nightScenery: (trees: CamperPreparedMesh, ridge: CamperPreparedMesh)?
    /// いまの見下ろしの角度（下から見る向きでは地面と遠景を隠す）
    private var elevation = 14.0
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private var carNode: SCNNode?
    private var doorPivot: SCNNode?
    private var doorGlowNode: SCNNode?
    private var buildTask: Task<Void, Never>?
    /// 材質と貼り絵（同じ材質は 1 つ。時刻を替えたら値を入れ直す・とおまわり号の中と共に使う）
    private let palette = CamperScenePalette()
    private(set) var currentMood: CamperMood = .day
    /// その時刻だけ見せる部品の組と灯り
    private var moodNodes: [(SCNNode, Set<CamperMood>)] = []
    private var moodLights: [(SCNNode, Set<CamperMood>?)] = []
    /// いま組んである形の鍵（時刻を除いた設定）
    private var builtKey: CamperConfig?
    /// 炎の舌と、揺らす灯り（焚き火・ランタン）。夜だけ、ゆっくり小さく揺らす（「視差効果を減らす」では止める）
    private var flameNodes: [SCNNode] = []
    private var flickerLights: [(SCNNode, Double)] = []
    /// 揺らしてよいか（`CamperSceneView` が「視差効果を減らす」を渡す）
    private(set) var flickerAllowed = true
    /// いま揺らしているか（揺らしている間だけ SCNView を回し続ける）
    private(set) var isFlickering = false
    /// 揺らし始めた・止めた（SCNView の描き続けるかを切り替える）
    var onFlickerChange: ((Bool) -> Void)?

    /// 動きの長さの倍率（見本の起動で「中に入る」をゆっくり撮るとき・`PreviewSession.camperEnterSlow`）
    var timeScale = 1.0

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
        nightStageNode.name = "night.stage"
        nightStageNode.isHidden = true
        scene.rootNode.addChildNode(nightStageNode)

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
        let night = mood == .night
        // 周りの光（映り込みと空の光）。夜の外は長い露出の写真の空（`nightEnvironment`）、昼と雪は写真のスタジオの空。
        // とおまわり号の中の夜は前の暗い空（"env.night"）のまま——部屋の中の見た目を変えない
        let env = night ? palette.image(key: "env.night.outdoor") { CamperTextures.nightEnvironment() }
            : palette.image(key: "env.\(mood.rawValue)") { CamperTextures.environment(mood) }
        scene.lightingEnvironment.contents = env
        // 周りの光を強め、太陽を少し弱める（塗装の clearCoat に空と光の箱が映る。run 529 では映り込みが弱かった）
        scene.lightingEnvironment.intensity = CGFloat(CamperMaterials.fill(mood).environment)
        // 画面の後ろ: 夜は空（地平線の霞へ）。昼と雪は透明のまま（画面の地の丸いグラデーションが見える・前と同じ）。
        // 一度も夜にしていなければ触らない（昼の初めの絵を前と同じ道で描く）
        if night {
            scene.background.contents = palette.image(key: "sky.night") { CamperTextures.nightSky() }
        } else if scene.background.contents != nil {
            scene.background.contents = nil
        }
        // 太陽・月の向きと強さ（`CamperMaterials.sun`）。画面に対して決まっている（車は回る台の上）
        let sun = CamperMaterials.sun(mood)
        let q = CQuat.rotation(from: CV3(0, 0, -1), to: -sun.from)
        sunNode.orientation = SCNQuaternion(Float(q.x), Float(q.y), Float(q.z), Float(q.w))
        sunNode.light?.intensity = CGFloat(sun.intensity)
        sunNode.light?.color = Self.color(sun.color)
        // 板: 影の色 #1a2230 0.5・雪は #3a5270 0.35。夜は月のやわらかい影（2026-10-21: 前は 0.15 でほぼ無かった）
        let st = CamperMaterials.NightStage.self
        sunNode.light?.shadowColor = mood == .snow ? Self.color(0x3A5270, alpha: 0.35)
            : Self.color(0x000000, alpha: night ? st.shadowAlpha : 0.5)
        if night {
            // 影を作る範囲を車のまわり（±4.6 m）に絞る。夜は 140 m の地面と遠景があるので、自動の範囲だと影の絵の
            // 1 画素が粗くなる。光の向きの奥へ 12 m 下げた所から見る
            let from = sun.from.normalized
            sunNode.position = Self.vector(CV3(0, 0.6, 0) + from * 12)
            sunNode.light?.automaticallyAdjustsShadowProjection = false
            sunNode.light?.orthographicScale = CGFloat(st.shadowExtent)
            sunNode.light?.zNear = 1
            sunNode.light?.zFar = 30
            sunNode.light?.shadowRadius = CGFloat(st.shadowRadius)
        } else {
            sunNode.position = SCNVector3(0, 0, 0)
            sunNode.light?.automaticallyAdjustsShadowProjection = true
            sunNode.light?.shadowRadius = 4
        }
        ambientNode.light?.intensity = CGFloat(CamperMaterials.fill(mood).ambient)
        // 夜はにじみ（bloom）を使わない（2026-10-18 Mac の絵 run 533）。艶の強い面に近くの灯りが当たると HDR の値が
        // 半精度の上限を超え、にじみの縮小の段で黒い四角に広がった（見立て）。昼はにじむほどの光が無いので残す
        cameraNode.camera?.bloomIntensity = CGFloat(night ? 0 : 0.2)
        cameraNode.camera?.exposureOffset = CGFloat(night ? st.exposure : 0)
        cameraNode.camera?.bloomThreshold = CGFloat(night ? 1.3 : 0.85)
        // 2026-10-21（Mac run 627 の 95）: カメラの周辺の落ち・彩度（色の後処理の段）を入れたら、昼の初めの絵が灰色のむらで
        // 埋まった（見立て: 後処理の段の絵が描き直される前に写った）。後処理は使わず、周辺の落ちは画面の側（`CamperStageEdges`）で

        // 床: 昼と雪は暗い一色。透け具合は車からの距離で（絵は貼らない・`CamperFloor`）。夜は芝の地面に替える
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
        if night { buildNightStage() }
        updateStageVisibility()
    }

    /// 夜の地面と遠景（`CamperMaterials.NightStage`・`CamperNightScenery`）。夜にはじめて替えた時に一度だけ作る
    private func buildNightStage() {
        guard !nightStageBuilt else { return }
        nightStageBuilt = true
        let st = CamperMaterials.NightStage.self
        // 地面（芝と土・月の影と灯りの溜まりを受ける）。霞で果てが空の地平線の色に溶ける
        let size = CGFloat(st.groundSize)
        let plane = SCNPlane(width: size, height: size)
        let ground = SCNMaterial()
        ground.lightingModel = .physicallyBased
        ground.diffuse.contents = palette.image(key: "ground.night") { CamperTextures.groundNight().tinted(st.ground) }
        ground.diffuse.wrapS = .repeat
        ground.diffuse.wrapT = .repeat
        ground.diffuse.mipFilter = .linear
        let tiles = Float(st.groundSize / st.groundTile)
        ground.diffuse.contentsTransform = SCNMatrix4MakeScale(tiles, tiles, 1)
        ground.roughness.contents = 0.95
        ground.metalness.contents = 0.0
        ground.shaderModifiers = [.fragment: CamperNightHaze.shader(start: st.hazeStart, end: st.hazeEnd, mist: 0, floor: 0)]
        plane.materials = [ground]
        let groundNode = SCNNode(geometry: plane)
        groundNode.name = "night.ground"
        groundNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        groundNode.castsShadow = false
        groundNode.categoryBitMask = Self.outsideMask | Self.propsMask
        nightStageNode.addChildNode(groundNode)
        // 遠景: 林の影（霞は距離と根元の靄）と、遠い山の稜線（ほぼ霞の色・空との境だけ読める）
        // 網は下ごしらえ（画面の処理の外）で作ったもの。まだ無ければここで作る
        let scenery = nightScenery ?? CamperScenePlan.nightScenery()
        for (name, mesh, color, shader) in [
            ("night.trees", scenery.trees, st.treeColor, CamperNightHaze.shader(start: st.hazeStart, end: st.hazeEnd, mist: 0.38, floor: 0.12)),
            ("night.ridge", scenery.ridge, st.ridgeColor, CamperNightHaze.shader(start: 900, end: 1000, mist: 0, floor: 0.5)),
        ] {
            guard let g = palette.geometry(mesh) else { continue }
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = Self.color(color)
            m.isDoubleSided = true
            m.shaderModifiers = [.fragment: shader]
            g.materials = g.materials.map { _ in m }
            let node = SCNNode(geometry: g)
            node.name = name
            node.castsShadow = false
            nightStageNode.addChildNode(node)
        }
    }

    /// 夜の地面と遠景は夜だけ。下から見る向きでは隠す（地面の裏から林が浮いて見える）。昼と雪の床は夜に隠す
    private func updateStageVisibility() {
        let night = currentMood == .night
        // 値が替わる時だけ入れる（2026-10-21 Mac run 627・633 の 95: 組み上がる前の空の場面で描き直しが起き、昼の初めの絵が
        // 灰色のむら（車の無い場面の画面の陰 SSAO と見立てた）のまま残った。組む前は場面に触らない）
        let stageHidden = !night || elevation < 0
        if nightStageNode.isHidden != stageHidden { nightStageNode.isHidden = stageHidden }
        if floorNode.isHidden != night { floorNode.isHidden = night }
    }

    /// 試験用: 殻の中の材質に入れた空の光の割合と、ある材質（外の組）
    func paletteOcclusion(_ m: SCNMaterial) -> Double? { palette.insideOcclusion[ObjectIdentifier(m)] }
    func paletteMaterial(_ m: CamperMaterial) -> SCNMaterial? { palette.materials[m] }

    /// 試験用: 作った材質（殻の中の組・外の組）
    var paletteMaterials: (inside: [SCNMaterial], outside: [SCNMaterial]) {
        (Array(palette.insideMaterials.values), Array(palette.materials.values))
    }

    /// 昼・夜・雪を切り替える（組み直さない。光・材質の値・その時刻だけの部品と灯りの見せる／隠すだけ）
    /// 試験用: いまの太陽・周りの光・露出（夜に替えた後の値を確かめる）
    var lightingSnapshot: (sun: Double, environment: Double, exposure: Double, ambient: Double) {
        (Double(sunNode.light?.intensity ?? 0), Double(scene.lightingEnvironment.intensity),
         Double(cameraNode.camera?.exposureOffset ?? 0), Double(ambientNode.light?.intensity ?? 0))
    }

    func setMood(_ mood: CamperMood) {
        currentMood = mood
        applyMood(mood)
        palette.setMood(mood)
        palette.setDoorWindowLit(!doorOpen)
        for (node, moods) in moodNodes { node.isHidden = !moods.contains(mood) }
        // その時刻でない灯りはノードごと隠す（強さ 0 で残すと、影ありの spot が昼にも影の絵を描き、光の数にも数えられる）
        for (node, moods) in moodLights { node.isHidden = !(moods.map { $0.contains(mood) } ?? true) }
        updateFlicker()
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
        palette.reset(bitmaps: plan.bitmaps, paint: config.loadout.paint, mood: config.mood)
        if nightScenery == nil { nightScenery = plan.nightScenery }
        currentMood = config.mood
        moodNodes = []
        moodLights = []
        builtKey = config.buildKey
        let s = Self.unit
        let body = SCNNode()
        let props = SCNNode()
        let inside = SCNNode()
        let door = SCNNode()
        // その時刻だけの部品（雪・夜の電球など）。時刻と灯りの組ごとに別にまとめ、見せる・隠すで切り替える
        var moodGroups: [String: (node: SCNNode, moods: Set<CamperMood>, inside: Bool)] = [:]
        // 地面の灯りの溜まり（まとめず・影を落とさない）。扉の口の溜まりは扉を開けた時だけ見せる
        let glow = SCNNode()
        let doorGlow = SCNNode()
        let flames = SCNNode()
        flameNodes = []
        flickerLights = []
        isFlickering = false
        for prepared in plan.nodes {
            let spec = prepared.spec
            // 殻の中の部品は、空の光を遮る別の材質（`CamperScenePalette.material(_:inside:)`）
            let isInside = prepared.inside
            guard let geometry = prepared.mesh.flatMap({ palette.geometry($0, inside: isInside) })
                    ?? palette.geometry(spec.shape, material: spec.material, unit: s, inside: isInside) else {
                continue
            }
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
            } else if spec.group == .flame {
                // 炎はまとめず、1 つずつ揺らす。影は落とさず、床と硝子の後に足す
                node.position = Self.vector(spec.position * s)
                node.castsShadow = false
                node.renderingOrder = 11
                flames.addChildNode(node)
                flameNodes.append(node)
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
                if !prepared.inside, let c = spec.category, Self.propCategories.contains(c) {
                    props.addChildNode(node)
                } else {
                    (prepared.inside ? inside : body).addChildNode(node)
                }
            }
        }
        let car = SCNNode()
        // 止まっている部品は材質ごとにまとめる（描く回数を減らす）。室内と外は灯りの組が違うので別々に
        let bodyFlat = body.flattenedClone()
        bodyFlat.name = "camper.outside"
        Self.mask(bodyFlat, Self.outsideMask)
        car.addChildNode(bodyFlat)
        let propsFlat = props.flattenedClone()
        propsFlat.name = "camper.props"
        Self.mask(propsFlat, Self.outsideMask | Self.propsMask)
        car.addChildNode(propsFlat)
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
        flames.castsShadow = false
        car.addChildNode(flames)
        // 地面の灯りの溜まりは夜だけ
        moodNodes.append((glow, [.night]))
        moodNodes.append((doorGlow, [.night]))
        // 灯り（夜）
        for light in bp.lights {
            let l = SCNLight()
            l.type = light.kind == .spot ? .spot : .omni
            l.color = Self.color(light.color)
            l.intensity = CGFloat(light.intensity)
            // 型ごとに減衰を分ける（`CamperLightPattern`。天井・入口・ランタンは急に、部屋の家具と焚き火はなだらかに）
            light.applyAttenuation(to: l, unit: s)
            // 室内の灯りは室内だけ、外の灯りは外だけ（影を落とさない omni が壁を抜けないように）
            // 外の火（焚き火・ランタン・電球の列）は置き物と地面だけ（`propsMask`）
            l.categoryBitMask = light.inside ? Self.insideMask : (light.pattern.flickers || light.pattern == .lantern ? Self.propsMask : Self.outsideMask)
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
            if light.pattern.flickers { flickerLights.append((n, light.intensity)) }
        }
        // 車体の下の暗がり（板: 楕円・ぼかし・0.75）。床から少し浮かせる
        let len = (bp.length.upperBound - bp.length.lowerBound + 8) * s
        let plane = SCNPlane(width: CGFloat(len), height: CGFloat((bp.halfWidth * 2 + 12) * s))
        let shade = SCNMaterial()
        shade.lightingModel = .constant
        shade.diffuse.contents = palette.image(key: "contact") { CamperTextures.contactShadow().premultiplied() }
        shade.transparencyMode = .aOne
        shade.blendMode = .alpha
        shade.writesToDepthBuffer = false
        plane.materials = [shade]
        let contact = SCNNode(geometry: plane)
        contact.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        contact.position = SCNVector3(Float((bp.length.lowerBound + bp.length.upperBound) / 2 * s), 0.002, 0)
        contact.castsShadow = false
        car.addChildNode(contact)
        // 夜はもう一回り広い暗がりを重ねる（2026-10-21・Mac run 627: 芝の地面の上で車が少し浮いて見えた。月は上と奥から
        // なので、車の下の影はほとんど車に隠れる）。車の下と、まわりの地面がなだらかに暗い
        let wide = SCNNode(geometry: plane)
        wide.eulerAngles = contact.eulerAngles
        wide.position = SCNVector3(contact.position.x, 0.003, 0)
        wide.scale = SCNVector3(1.35, 1.7, 1)
        wide.castsShadow = false
        wide.name = "contact.night"
        car.addChildNode(wide)
        moodNodes.append((wide, [.night]))

        carNode?.removeFromParentNode()
        turntable.addChildNode(car)
        carNode = car
        doorPivot = pivot
        doorGlowNode = doorGlow
        blueprint = bp
        setMood(config.mood)
        // 組み上がった後の絵を必ず描き直させる（2026-10-21 Mac run 627・633・642 の 95: 昼の初めの絵が、組む前の灰色の
        // むらのまま残る回があった）。カメラの置き場所を入れ直すと、止まっている SCNView も次のコマを描く
        let p = cameraNode.position
        cameraNode.position = SCNVector3(p.x, p.y, p.z + 0.0001)
        cameraNode.position = p
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
        SCNTransaction.animationDuration = animated ? 0.6 * timeScale : 0
        // 板の注記: 指を離すと 0.6 秒 cubic-bezier(.2,.75,.25,1) で止まる
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.75, 0.25, 1)
        turntable.eulerAngles = SCNVector3(0, Float(yaw), 0)
        elevation = a.elevation
        cameraRig.position = Self.vector(rotated)
        cameraRig.eulerAngles = SCNVector3(Float(-a.elevation * .pi / 180), 0, 0)
        cameraNode.position = SCNVector3(0, 0, Float(CamperFraming.distance(zoom: a.zoom)))
        SCNTransaction.commit()
        updateStageVisibility()
    }

    /// 扉を開け閉めする（板の注記: 開くは 0.6 秒 ease-out で 100°、閉じるは 0.4 秒）
    func setDoor(open: Bool, animated: Bool) {
        guard open != doorOpen else { return }
        doorOpen = open
        guard let pivot = doorPivot, let bp = blueprint else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? (open ? 0.6 : 0.4) * timeScale : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1)
        pivot.eulerAngles = SCNVector3(0, Float(open ? bp.doorOpenAngle : 0), 0)
        doorGlowNode?.opacity = open ? 1 : 0
        palette.setDoorWindowLit(!open)
        SCNTransaction.commit()
    }

    func cancel() {
        buildTask?.cancel()
        buildTask = nil
    }

    // MARK: 炎のゆらぎ

    /// 揺らしてよいか（「視差効果を減らす」では止める）
    func setFlicker(allowed: Bool) {
        guard allowed != flickerAllowed else { return }
        flickerAllowed = allowed
        updateFlicker()
    }

    /// 夜だけ、炎の形と焚き火・ランタンの光をゆっくり小さく揺らす（2026-10-19 owner「発光の仕方ひどい」: 硬い円の光）
    private func updateFlicker() {
        let on = flickerAllowed && currentMood == .night && !(flameNodes.isEmpty && flickerLights.isEmpty)
        if on != isFlickering {
            isFlickering = on
            onFlickerChange?(on)
        }
        for (i, node) in flameNodes.enumerated() {
            node.removeAction(forKey: "flicker")
            if on { node.runAction(.repeatForever(Self.flameAction(phase: Double(i) * 1.3, base: node.scale)), forKey: "flicker") }
        }
        for (i, (node, intensity)) in flickerLights.enumerated() {
            node.removeAction(forKey: "flicker")
            node.light?.intensity = CGFloat(intensity)
            if on { node.runAction(.repeatForever(Self.lightAction(phase: Double(i) * 2.1, intensity: intensity)), forKey: "flicker") }
        }
    }

    /// 揺らぎの強さ（0.9〜1.1 ほど・周期 0.7〜1.9 秒の重ね合わせ。ゆっくり小さく）
    nonisolated static func flickerAmount(_ t: Double) -> Double {
        1 + 0.06 * sin(t * 2 * .pi / 1.9) + 0.03 * sin(t * 2 * .pi / 0.73 + 0.5) + 0.015 * sin(t * 2 * .pi / 0.31 + 1.7)
    }

    nonisolated private static func flameAction(phase: Double, base: SCNVector3) -> SCNAction {
        SCNAction.customAction(duration: 6) { node, elapsed in
            let k = flickerAmount(Double(elapsed) + phase)
            // 縦に伸び縮みし、横は少しだけ逆に（体積がおおよそ変わらない）
            node.scale = SCNVector3(base.x * Float(1 / k.squareRoot()), base.y * Float(k), base.z * Float(1 / k.squareRoot()))
        }
    }

    nonisolated private static func lightAction(phase: Double, intensity: Double) -> SCNAction {
        SCNAction.customAction(duration: 6) { node, elapsed in
            node.light?.intensity = CGFloat(intensity * flickerAmount(Double(elapsed) + phase))
        }
    }

    /// 灯りの組をまとめた形の下の全部に付ける（まとめた結果が子を持つ場合にも効くように）
    static func mask(_ node: SCNNode, _ bits: Int) {
        node.categoryBitMask = bits
        for child in node.childNodes { mask(child, bits) }
    }

    static func vector(_ v: CV3) -> SCNVector3 { SCNVector3(Float(v.x), Float(v.y), Float(v.z)) }

    static func color(_ hex: UInt32, alpha: Double = 1) -> UIColor { CamperScenePalette.color(hex, alpha: alpha) }
}

#endif

extension CamperShape {
    /// 字の高さ（文字のときだけ）
    var textHeight: Double {
        if case let .text(_, height, _) = self { return height }
        return 1
    }
}
