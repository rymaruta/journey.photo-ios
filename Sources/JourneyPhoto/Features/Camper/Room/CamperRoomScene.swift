import UIKit
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import ImageIO
import SceneKitShim
#endif

// とおまわり号の中を SceneKit で描く（2026-10-19）。外の車（`CamperScene`）と同じ素材と貼り絵（`CamperScenePalette`）。
//
// 光（owner「室内のランプ・窓からの光を家具に正しく当てる」）:
// - 昼: 太陽は奥の壁の窓の側から差し込む（影あり）。天井と壁が光をさえぎるので、床と家具には窓の形の光が落ちる。
//   部屋全体は周りの光（空の絵）で柔らかく。隅と家具の足元は画面の陰（SSAO）と、家具ごとの接地の影で締める
// - 夜: 指向の月は消す（残すと窓から昼の光が差し込み、白い板と硬い影になる・2026-10-19 owner）。
//   灯りの家具（床の灯り・壁の灯り・電球の紐・ストーブの火）の暖色 omni だけで、まわりの溜まりにする。
//   窓の硝子は暗い色にし、外の景色は光を受けない夜の絵（windowNight）
// - 夜の光の決まり（docs/CAMPER.md）: にじみ（bloom）は使わない・光る面の emission は 1 まで・室内の灯りは室内の組
//   （categoryBitMask = 2）だけを照らす。天井の広い spot は置かない（Mac run 575）

#if canImport(SceneKit) || canImport(SceneKitShim)

@MainActor
final class CamperRoomScene {

    static let unit = CamperRoomScenePlan.unit

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let roomNode = SCNNode()
    private let itemsNode = SCNNode()
    private let overlayNode = SCNNode()
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private let gridNode = SCNNode()
    private let palette = CamperScenePalette()
    private var shellGroups: [(SCNNode, String)] = []
    private var lampNodes: [SCNNode] = []
    private var itemNodes: [String: (node: SCNNode, item: CamperRoomPlacedItem)] = [:]
    private var furniture: [String: CamperPreparedMesh] = [:]
    private var photoImages: [String: UIImage] = [:]
    private var buildTask: Task<Void, Never>?
    /// 選んでいる家具（3 浮かせる）・持ち上げて動かしている家具（動かした先）と置けるか
    private var selectedUid: String?
    private var dragItem: CamperRoomItem?
    private var dragCheck: CamperRoomCheck?
    /// いま点けている灯りの並び（同じなら作り直さない）
    private var lampSpecs: [CamperLightSpec] = []
    private(set) var layout: CamperRoomLayout?
    private(set) var doc: CamperRoomDocument?
    private var builtKey: String?
    private(set) var mood: CamperMood = .day
    private(set) var camera: CamperRoomCamera?
    private var paint: UInt32 = 0x5B6168
    /// 組み終えたら呼ぶ（読み上げの値・画面写真の試験が待つ）
    var onReady: ((String) -> Void)?
    /// 家具を見せるだけの所（図鑑の寄り）。手前の壁を切らない向きでも、天井の灯りを強めに
    var studio = false

    init() {
        let cam = SCNCamera()
        cam.fieldOfView = CGFloat(CamperRoomCamera.fieldOfView)
        cam.zNear = 0.02
        cam.zFar = 40
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        // 夜の光の決まり: にじみは使わない（昼も使わない・窓の白が広がらない）
        cam.bloomIntensity = 0
        cam.bloomThreshold = 1.3
        // 隅と家具の足元の陰
        cam.screenSpaceAmbientOcclusionIntensity = 0.9
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(roomNode)
        scene.rootNode.addChildNode(itemsNode)
        scene.rootNode.addChildNode(overlayNode)
        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        // forward（その光だけを減らす）。deferred は影の所の画面の色そのものを暗くするので、天井の下の部屋全部が
        // 影の色で塗られる（外の車の run 538 と同じ）。天井と壁にさえぎられ、窓の形の光だけが床に落ちる
        sun.shadowMode = .forward
        sun.shadowRadius = 6
        sun.shadowSampleCount = 16
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.automaticallyAdjustsShadowProjection = true
        sun.categoryBitMask = CamperScene.insideMask | CamperScene.outsideMask
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.categoryBitMask = CamperScene.insideMask | CamperScene.outsideMask
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
        gridNode.isHidden = true
        overlayNode.addChildNode(gridNode)
    }

    // MARK: 組み立て

    /// 部屋を見せる（広さ・模様替え・塗装が変われば組み直す。家具の場所だけなら、組み直さずに動かす）
    func show(layout: CamperRoomLayout, doc: CamperRoomDocument, paint: UInt32) {
        let key = "\(layout.kind.rawValue) \(layout.width)x\(layout.depth) \(doc.style.wall) \(doc.style.floor) \(doc.style.curtain) \(doc.style.light) \(paint) \(studio)"
        self.doc = doc
        self.layout = layout
        self.paint = paint
        if key == builtKey {
            syncItems(layout: layout, doc: doc)
            return
        }
        buildTask?.cancel()
        let started = Date()
        let extra = doc.all.map(\.k)
        buildTask = Task { [weak self] in
            let plan = await Task.detached(priority: .userInitiated) {
                CamperRoomScenePlan.make(layout, doc: doc, paint: paint, extra: extra)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.install(plan, key: key)
            if let now = self.doc { self.syncItems(layout: layout, doc: now) }
            self.reapplyDrag()
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            self.onReady?(self.marker(ms: ms))
        }
    }

    /// 試験用: いまの処理の中で組む
    func installNow(layout: CamperRoomLayout, doc: CamperRoomDocument, paint: UInt32) {
        self.layout = layout
        self.doc = doc
        install(CamperRoomScenePlan.make(layout, doc: doc, paint: paint), key: "now")
        syncItems(layout: layout, doc: doc)
    }

    /// 組み終えた合図（画面写真の試験が待つ）
    func marker(ms: Int = 0) -> String {
        "camper-room-ready \(layout?.kind.rawValue ?? "") \(mood.rawValue) items=\(itemNodes.count) ms=\(ms)"
    }

    private func install(_ plan: CamperRoomScenePlan, key: String) {
        builtKey = key
        palette.reset(bitmaps: plan.bitmaps, paint: paint, mood: mood)
        furniture = plan.furniture
        roomNode.childNodes.forEach { $0.removeFromParentNode() }
        itemsNode.childNodes.forEach { $0.removeFromParentNode() }
        itemNodes = [:]
        shellGroups = []
        // 灯りは部屋の節の子なので一緒に外れる。並びの控えも消す（作り直させる）
        lampNodes = []
        lampSpecs = []
        // 部屋は見せ方の組（いつも・手前の端の壁の高い／低い）ごとにまとめる（描く回数を抑える）
        var groups: [String: SCNNode] = [:]
        for (name, mesh) in plan.shell {
            guard let g = palette.geometry(mesh) else { continue }
            let n = SCNNode(geometry: g)
            n.name = name
            if name == "room.ceiling" { n.castsShadow = true }
            let key = Self.visibilityKey(name)
            let holder = groups[key] ?? SCNNode()
            holder.addChildNode(n)
            groups[key] = holder
        }
        for (key, holder) in groups.sorted(by: { $0.key < $1.key }) {
            let flat = holder.flattenedClone()
            flat.name = key
            CamperScene.mask(flat, CamperScene.insideMask)
            roomNode.addChildNode(flat)
            shellGroups.append((flat, key))
        }
        installGrid(plan.blueprint.layout)
        applyMood(mood)
        applyCutaway()
    }

    /// 見せ方の組の名前（`CamperRoomScenePlan.visible` に渡す代表の名前）
    static func visibilityKey(_ name: String) -> String {
        for p in ["room.end.front.full", "room.end.front.low", "room.end.rear.full", "room.end.rear.low"] where name.hasPrefix(p) { return p }
        return "room.always"
    }

    /// 家具を文書に合わせる（増えた物は作り、消えた物は外し、動いた物は場所だけ替える）
    private func syncItems(layout: CamperRoomLayout, doc: CamperRoomDocument) {
        let placed = doc.all.compactMap(CamperRoomBuilder.place)
        let keep = Set(placed.map(\.uid))
        for (uid, entry) in itemNodes where !keep.contains(uid) {
            entry.node.removeFromParentNode()
            itemNodes[uid] = nil
        }
        for it in placed {
            if let entry = itemNodes[it.uid], entry.item.furnitureId == it.furnitureId {
                if entry.item != it {
                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = 0.12
                    transform(entry.node, displayed(it))
                    SCNTransaction.commit()
                    if entry.item.photos != it.photos { applyPhotos(entry.node, it) }
                    itemNodes[it.uid] = (entry.node, it)
                }
                continue
            }
            itemNodes[it.uid]?.node.removeFromParentNode()
            guard let node = makeItemNode(it) else { continue }
            itemsNode.addChildNode(node)
            itemNodes[it.uid] = (node, it)
            transform(node, displayed(it))
        }
        rebuildLamps(placed, layout: layout, style: doc.style)
    }

    /// 組み直した後に、持ち上げている家具とマス目の色を描き直す
    private func reapplyDrag() {
        let d = dragItem, c = dragCheck
        dragItem = nil
        dragCheck = nil
        setDrag(d, check: c)
    }

    /// 見せる場所（持ち上げている家具は動かした先で 7 浮かせ、選んでいる床の家具は 3 浮かせる）
    private func displayed(_ it: CamperRoomPlacedItem) -> CamperRoomPlacedItem {
        if let d = dragItem, d.u == it.uid, var lifted = CamperRoomBuilder.place(d) {
            if lifted.placement == .floor { lifted.position = lifted.position + CV3(0, 7, 0) }
            if lifted.placement == .wall { lifted.position = lifted.position + (lifted.yaw == 0 ? CV3(0, 0, 3) : CV3(3, 0, 0)) }
            return lifted
        }
        var out = it
        if it.uid == selectedUid, it.placement == .floor, !(CamperRoomCatalog.furniture(it.furnitureId)?.isRug ?? false) {
            out.position = out.position + CV3(0, 3, 0)
        }
        return out
    }

    private func transform(_ node: SCNNode, _ it: CamperRoomPlacedItem) {
        node.position = CamperScene.vector(it.position * Self.unit)
        node.eulerAngles = SCNVector3(0, Float(it.yaw), 0)
    }

    private func makeItemNode(_ it: CamperRoomPlacedItem) -> SCNNode? {
        if furniture[it.furnitureId] == nil, let m = CamperRoomFurnitureModels.mesh(it.furnitureId) {
            furniture[it.furnitureId] = CamperPreparedMesh(m, unit: Self.unit)
        }
        guard let mesh = furniture[it.furnitureId], let geometry = palette.geometry(mesh) else { return nil }
        let holder = SCNNode()
        holder.name = "item.\(it.uid)"
        let body = SCNNode(geometry: geometry)
        body.name = "body"
        holder.addChildNode(body)
        // 接地の影（床の物は足元に、壁の物は壁に。敷物には付けない）
        let f = CamperRoomCatalog.furniture(it.furnitureId)
        if f?.isRug == false, it.placement != .ceiling {
            let pad = it.placement == .floor ? 5.0 : 3.0
            let plane = SCNPlane(width: CGFloat((it.footprint.x + pad) * Self.unit), height: CGFloat((it.footprint.y + pad) * Self.unit))
            let shade = SCNMaterial()
            shade.lightingModel = .constant
            shade.diffuse.contents = palette.image(key: "contact") { CamperTextures.contactShadow().premultiplied() }
            shade.transparencyMode = .aOne
            shade.blendMode = .alpha
            shade.writesToDepthBuffer = false
            shade.transparency = it.placement == .floor ? 0.85 : 0.45
            plane.materials = [shade]
            let contact = SCNNode(geometry: plane)
            contact.name = "contact"
            contact.castsShadow = false
            contact.renderingOrder = 5
            if it.placement == .floor {
                contact.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
                contact.position = SCNVector3(0, 0.0015, 0)
            } else {
                contact.position = SCNVector3(0, Float((it.footprint.y / 2 - 1.5) * Self.unit), 0.0012)
            }
            holder.addChildNode(contact)
        }
        transform(holder, it)
        CamperScene.mask(holder, CamperScene.insideMask)
        applyPhotos(holder, it)
        return holder
    }

    // MARK: 写真

    /// 額に入れる写真（投稿の写真の id → 絵）。読めたものから入れる
    func setPhotoImages(_ images: [String: UIImage]) {
        photoImages = images
        for (_, entry) in itemNodes where !entry.item.photos.isEmpty { applyPhotos(entry.node, entry.item) }
    }

    private func applyPhotos(_ holder: SCNNode, _ it: CamperRoomPlacedItem) {
        guard let body = holder.childNodes.first(where: { $0.name == "body" }), let g = body.geometry,
              let mesh = furniture[it.furnitureId] else { return }
        var mats = g.materials
        for (i, group) in mesh.groups.enumerated() where i < mats.count {
            guard case .room(.photo(let slot)) = group.material else { continue }
            let index = Int(slot.dropFirst(4)) ?? 0
            let m = SCNMaterial()
            palette.configure(m, CamperMaterials.spec(group.material, paint: paint, mood: mood))
            if index < it.photos.count, let image = photoImages[it.photos[index]] {
                m.diffuse.contents = image
                m.diffuse.wrapS = .clamp
                m.diffuse.wrapT = .clamp
            }
            mats[i] = m
        }
        g.materials = mats
    }

    // MARK: 灯り

    private func rebuildLamps(_ items: [CamperRoomPlacedItem], layout: CamperRoomLayout, style: CamperRoomStyle) {
        var specs = CamperRoomBuilder.lights(items, style: style, layout: layout)
        defer { lampSpecs = specs }
        if studio {
            // 図鑑の寄り: 灯りの無い家具も夜に見えるよう、近くに暖色の灯りを 1 つ
            // 家具の斜め前上に置いた電球ほどの灯り（届く距離 50・まわりは暗い）
            specs.append(CamperLightSpec(name: "interior.studio", kind: .omni, position: CV3(layout.size.x * 0.5 + 14, 44, 30),
                                         color: CamperRoomMaterials.lightColor(style.light), intensity: 0.5, range: 90, moods: [.night]))
        }
        // 灯りの並びが同じなら作り直さない（指で動かしている間に毎回作り直さない）
        guard specs != lampSpecs || lampNodes.isEmpty && !specs.isEmpty else { return }
        lampNodes.forEach { $0.removeFromParentNode() }
        lampNodes = []
        for spec in specs {
            let l = SCNLight()
            l.type = spec.kind == .spot ? .spot : .omni
            l.color = CamperScene.color(spec.color)
            l.intensity = CGFloat(spec.intensity)
            l.attenuationStartDistance = 0
            l.attenuationEndDistance = CGFloat(spec.range * Self.unit)
            // 距離の二乗に近い落ち方（白い芯を避け、木と布になだらかに回る）
            l.attenuationFalloffExponent = 1.0
            // 室内の灯りは室内の組だけ
            l.categoryBitMask = CamperScene.insideMask
            if spec.kind == .spot {
                l.spotInnerAngle = CGFloat(spec.spotInner)
                l.spotOuterAngle = CGFloat(spec.spotOuter)
            }
            if spec.castsShadow {
                // 影はその灯りの光だけを減らす forward で（外の車の run 538 と同じ）
                l.castsShadow = true
                l.shadowMode = .forward
                l.shadowSampleCount = 8
                l.shadowRadius = 4
                l.shadowMapSize = CGSize(width: 1024, height: 1024)
                l.shadowColor = CamperScene.color(0x000000, alpha: 1)
            }
            let n = SCNNode()
            n.name = "light.\(spec.name)"
            n.light = l
            n.position = CamperScene.vector(spec.position * Self.unit)
            if spec.kind == .spot {
                let q = CQuat.rotation(from: CV3(0, 0, -1), to: spec.direction)
                n.orientation = SCNQuaternion(Float(q.x), Float(q.y), Float(q.z), Float(q.w))
            }
            n.isHidden = mood != .night
            roomNode.addChildNode(n)
            lampNodes.append(n)
        }
    }

    // MARK: 昼と夜

    func setMood(_ next: CamperMood) {
        let m: CamperMood = next == .night ? .night : .day
        guard m != mood else { return }
        mood = m
        applyMood(m)
        for (_, entry) in itemNodes where !entry.item.photos.isEmpty { applyPhotos(entry.node, entry.item) }
        onReady?(marker())
    }

    /// 試験用: いまの光の値
    var lightingSnapshot: (sun: Double, environment: Double, ambient: Double, lamps: Int, lampsShown: Int, bloom: Double) {
        (Double(sunNode.light?.intensity ?? 0), Double(scene.lightingEnvironment.intensity), Double(ambientNode.light?.intensity ?? 0),
         lampNodes.count, lampNodes.filter { !$0.isHidden }.count, Double(cameraNode.camera?.bloomIntensity ?? 0))
    }

    private func applyMood(_ m: CamperMood) {
        let night = m == .night
        palette.setMood(m)
        scene.lightingEnvironment.contents = palette.image(key: "env.\(m.rawValue)") { CamperTextures.environment(m) }
        // 夜の値は外の車の夜にそろえる（周りの光・露出）。環境光はごく弱く
        scene.lightingEnvironment.intensity = CGFloat(night ? 0.06 : (studio ? 1.25 : 1.1))
        // 昼の太陽は奥の壁の窓の側（z の負）から、少し後ろから差し込む。
        // 夜の指向光は消す（強度を残すと窓から昼の光が差し込み、硝子が白い板・硬い影になる・2026-10-19 owner）
        let from = CV3(-0.25, 0.62, -0.75)
        let q = CQuat.rotation(from: CV3(0, 0, -1), to: -from)
        sunNode.orientation = SCNQuaternion(Float(q.x), Float(q.y), Float(q.z), Float(q.w))
        sunNode.light?.intensity = CGFloat(night ? 0 : 1500)
        sunNode.light?.color = CamperScene.color(0xFFF1DC)
        sunNode.light?.castsShadow = !night
        sunNode.light?.shadowColor = CamperScene.color(0x000000, alpha: 1)
        // 夜は灯りの溜まりの外が完全な黒にならないよう、ごく弱い暖色の環境光（木の色がわずかに残る）
        ambientNode.light?.intensity = CGFloat(night ? 24 : 90)
        ambientNode.light?.color = night ? CamperScene.color(0x3A2E22) : CamperScene.color(0xFFF6EA)
        cameraNode.camera?.exposureOffset = CGFloat(night ? -0.15 : 0.15)
        cameraNode.camera?.bloomIntensity = 0
        for n in lampNodes { n.isHidden = !night }
    }

    // MARK: カメラと手前の壁

    func setCamera(_ c: CamperRoomCamera, animated: Bool) {
        guard c != camera, let layout else {
            camera = c
            return
        }
        let cutChanged = camera?.cutsFrontEnd != c.cutsFrontEnd
        camera = c
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.6 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.75, 0.25, 1)
        cameraNode.position = CamperScene.vector(c.eye(layout) * Self.unit)
        let q = c.orientation
        cameraNode.orientation = SCNQuaternion(Float(q.x), Float(q.y), Float(q.z), Float(q.w))
        SCNTransaction.commit()
        if cutChanged { applyCutaway() }
    }

    /// 向きに合わせて、手前の端の壁を低い方に替える（窓と壁の物もその壁と一緒に）
    private func applyCutaway() {
        guard let c = camera else { return }
        if let layout { setCamera(c, animated: false, layout: layout) }
        for (node, key) in shellGroups { node.isHidden = !CamperRoomScenePlan.visible(key, camera: c) }
        for (_, entry) in itemNodes where entry.item.placement == .wall {
            // 後ろの壁が手前に来て切られた時は、その壁の物も見せない
            entry.node.isHidden = entry.item.yaw != 0 && !c.cutsFrontEnd
        }
    }

    private func setCamera(_ c: CamperRoomCamera, animated: Bool, layout: CamperRoomLayout) {
        cameraNode.position = CamperScene.vector(c.eye(layout) * Self.unit)
        let q = c.orientation
        cameraNode.orientation = SCNQuaternion(Float(q.x), Float(q.y), Float(q.z), Float(q.w))
    }

    // MARK: 置く時の見た目（マス目・持ち上げ・白と赤のマス）

    private func installGrid(_ layout: CamperRoomLayout) {
        let s = layout.size
        let plane = SCNPlane(width: CGFloat(s.x * Self.unit), height: CGFloat(s.z * Self.unit))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = palette.image(key: "room.grid") { CamperRoomScenePlan.gridBitmap() }
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(layout.width), Float(layout.depth), 1)
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        plane.materials = [m]
        gridNode.geometry = plane
        gridNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        gridNode.position = SCNVector3(Float(s.x / 2 * Self.unit), 0.002, Float(s.z / 2 * Self.unit))
        gridNode.renderingOrder = 6
        gridNode.castsShadow = false
    }

    /// 置く場面（マス目を出す）
    func setEditing(_ on: Bool) { gridNode.isHidden = !on }

    /// 持ち上げて動かしている家具（`item` は動かした先・`check` は置けるか）。nil で終わり
    func setDrag(_ item: CamperRoomItem?, check: CamperRoomCheck?) {
        guard item != dragItem || check != dragCheck else { return }
        let previous = dragItem
        dragItem = item
        dragCheck = check
        overlayNode.childNodes.filter { $0.name == "drag" }.forEach { $0.removeFromParentNode() }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.12
        // 前に持ち上げていた家具を元の場所へ・接地の影を元に
        if let prev = previous?.u, prev != item?.u, let entry = itemNodes[prev] {
            transform(entry.node, displayed(entry.item))
            if let contact = entry.node.childNodes.first(where: { $0.name == "contact" }) {
                contact.scale = SCNVector3(1, 1, 1)
                if entry.item.placement == .floor { contact.position = SCNVector3(0, 0.0015, 0) }
            }
        }
        guard let item, let placed = CamperRoomBuilder.place(item), let entry = itemNodes[item.u] else {
            SCNTransaction.commit()
            return
        }
        // 持ち上げ: 7 浮かせ、接地の影を広げて薄く（板の付箋「長押しで 7 浮かせ、影を広げる」）
        transform(entry.node, displayed(entry.item))
        if let contact = entry.node.childNodes.first(where: { $0.name == "contact" }) {
            contact.scale = SCNVector3(1.35, 1.35, 1.35)
            if placed.placement == .floor { contact.position = SCNVector3(0, Float(-7 * Self.unit + 0.0015), 0) }
        }
        SCNTransaction.commit()
        // 白（置ける）と赤（ぶつかる #F0565A）のマス
        let ok = check?.ok ?? true
        let blocked = check?.blocked ?? []
        let cell = CamperRoomLayout.cell
        if let r = item.rect {
            for c in r.cells {
                let red = !ok && (blocked.isEmpty || blocked.contains(c))
                overlayNode.addChildNode(cellNode(center: CV3((Double(c.x) + 0.5) * cell, placed.placement == .floor ? 0.3 : CamperRoomLayout.ceiling - 0.3,
                                                              (Double(c.z) + 0.5) * cell), red: red, horizontal: true))
            }
        } else if let s = item.wallSpan {
            let lo = CamperRoomLayout.rowBottoms[s.rows.lowerBound], h = CamperRoomLayout.rowHeight * Double(s.rows.count)
            let along = (Double(s.columns.lowerBound) + Double(s.columns.count) / 2) * cell
            let center = s.wall == .back ? CV3(along, lo + h / 2, 0.4) : CV3(0.4, lo + h / 2, along)
            let n = cellNode(center: center, red: !ok, horizontal: false, size: CV2(Double(s.columns.count) * cell - 1, h - 1))
            if s.wall == .left { n.eulerAngles = SCNVector3(0, Float.pi / 2, 0) }
            overlayNode.addChildNode(n)
        }
    }

    private func cellNode(center: CV3, red: Bool, horizontal: Bool, size: CV2 = CV2(9, 9)) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(size.x * Self.unit), height: CGFloat(size.y * Self.unit))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = red ? CamperScene.color(0xF0565A, alpha: 0.55) : CamperScene.color(0xFFFFFF, alpha: 0.32)
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.isDoubleSided = true
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.name = "drag"
        n.renderingOrder = 20
        n.castsShadow = false
        if horizontal { n.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0) }
        n.position = CamperScene.vector(center * Self.unit)
        return n
    }

    /// 選んでいる家具（少し浮かせて見せる: 板の付箋「軽く押す: 選ぶ（3 浮いて…）」）
    func setSelected(_ uid: String?) {
        guard uid != selectedUid else { return }
        let previous = selectedUid
        selectedUid = uid
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.12
        for id in [previous, uid].compactMap({ $0 }) {
            if let entry = itemNodes[id] { transform(entry.node, displayed(entry.item)) }
        }
        SCNTransaction.commit()
    }

    func cancel() {
        buildTask?.cancel()
        buildTask = nil
    }
}

#endif
