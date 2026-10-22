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
    /// 写真を飾る場面: 天井を隠す・選んだ額を光らせる・まだ保存していない見本の写真
    private var photosMode = false
    private var focusFrameUid: String?
    private var previewPhotoId: String?
    private let focusNode = SCNNode()
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
    /// 額に**保存した中身**（`it.photos` の1枚目）の印画があるもの（額の uid → 写真 id）と、選んだだけでまだ保存していない
    /// 見本の写真（`previewPhotoId`）が載っている額。UI テストが「飾った写真が額に入ったか」を読む（`CriticalFlowTests`・2026-10-22）。
    /// 🔴 2つを分ける（確かめ役の指摘）: 見本は選んだ瞬間に額へ載るので、まとめると「この額に飾る」を押さなくても緑になる
    private(set) var framedPhotos: [String: String] = [:]
    private(set) var previewedPhotos: [String: String] = [:]
    var onFramed: ((_ framed: [String: String], _ previewed: [String: String]) -> Void)?
    /// 家具を見せるだけの所（図鑑の寄り）。手前の壁を切らない向きでも、天井の灯りを強めに
    var studio = false
    /// 最初のコマの見張り（SCNView の delegate は弱い参照なので、ここで持つ）
    var firstFrame: AnyObject?
    /// 材質を替えたあとに再描画させる（`rendersContinuously = false` だと取りこぼすことがある）
    private weak var scnView: SCNView?

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
        focusNode.name = "photo.focus"
        focusNode.isHidden = true
        overlayNode.addChildNode(focusNode)
    }

    /// SCNView を覚える（写真の材質を替えたあと、止まっている描画を起こす）
    func attach(_ view: SCNView) { scnView = view }

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
            // 組み直しのあいだに届いた印画を載せる（setPhotoImages が空の itemNodes に当たって取りこぼす）
            self.reapplyAllPhotos()
            self.applyPhotosModeVisibility()
            self.applyCutaway()
            self.updateFocusRing()
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
        reapplyAllPhotos()
        applyCutaway()
    }

    /// 見本用: 組んだ部屋（`installNow`）のまま、家具だけを入れ替える（家具の接写の一覧・2026-10-21。部屋の殻は組み直さない）
    func replaceItemsNow(_ doc: CamperRoomDocument) {
        guard let layout else { return }
        self.doc = doc
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
        let placed = doc.all.compactMap { CamperRoomBuilder.place($0, ceiling: layout.ceilingHeight) }
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
        if let d = dragItem, d.u == it.uid, var lifted = CamperRoomBuilder.place(d, ceiling: layout?.ceilingHeight ?? CamperRoomLayout.ceiling) {
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
        // 写真の材質は額ごとに専用にする（共有だと片方の印画がもう片方にも乗る／差し替えが効かない）
        if geometry.materials.count == mesh.groups.count {
            geometry.materials = zip(geometry.materials, mesh.groups).map { mat, group in
                guard case .room(.photo) = group.material else { return mat }
                let fresh = SCNMaterial()
                palette.configure(fresh, CamperMaterials.spec(group.material, paint: paint, mood: mood))
                return fresh
            }
        }
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
        for (_, entry) in itemNodes { applyPhotos(entry.node, entry.item) }
        kickRender()
    }

    /// 写真を飾る場面の見せ方（天井の換気窓などを隠し、選んだ額の前に縁を出す・見本の写真を載せる）
    func setPhotosMode(_ on: Bool, focus: String?, preview: String?) {
        let changed = on != photosMode || focus != focusFrameUid || preview != previewPhotoId
        photosMode = on
        focusFrameUid = focus
        previewPhotoId = preview
        guard changed || !itemNodes.isEmpty else { return }
        applyPhotosModeVisibility()
        // 選んだ額を切った壁の規則から外す（写真を飾る場面に入った直後）
        applyCutaway()
        for (_, entry) in itemNodes where !entry.item.photos.isEmpty || entry.item.uid == focus {
            applyPhotos(entry.node, entry.item)
        }
        updateFocusRing()
        kickRender()
    }

    private func applyPhotosModeVisibility() {
        for (_, entry) in itemNodes where entry.item.placement == .ceiling {
            // 換気窓が額のように見えて「変な写真枠」に見えた（2026-10-20 #326）
            entry.node.isHidden = photosMode
        }
    }

    /// 持っている印画を全部の額に載せ直す（組み直し直後・画像が後から届いたとき）
    private func reapplyAllPhotos() {
        for (_, entry) in itemNodes { applyPhotos(entry.node, entry.item) }
        kickRender()
    }

    private func updateFocusRing() {
        focusNode.childNodes.forEach { $0.removeFromParentNode() }
        guard photosMode, let uid = focusFrameUid, let entry = itemNodes[uid] else {
            focusNode.isHidden = true
            return
        }
        let it = entry.item
        let w = max(it.footprint.x, 12) * Self.unit
        let h = max(it.footprint.y, 12) * Self.unit
        // 真鍮の縁だけ（選んでいる額の合図）。全面の板に透明の穴を重ねても奥は透けないので、
        // 四辺の細い板で枠だけ描く——全面だと飾った写真が真鍮に隠れて見えなかった（2026-10-20 owner）
        let brass = SCNMaterial()
        brass.lightingModel = .constant
        brass.diffuse.contents = CamperScene.color(0xC9A66B, alpha: 0.95)
        brass.isDoubleSided = true
        brass.writesToDepthBuffer = false
        let rimW = 1.4 * Self.unit
        let outerW = w + 2 * rimW
        func strip(width: CGFloat, height: CGFloat, x: Float, y: Float) {
            let plane = SCNPlane(width: width, height: height)
            plane.materials = [brass]
            let n = SCNNode(geometry: plane)
            n.position = SCNVector3(x, y, 0)
            focusNode.addChildNode(n)
        }
        strip(width: CGFloat(outerW), height: CGFloat(rimW), x: 0, y: Float(h / 2 + rimW / 2))
        strip(width: CGFloat(outerW), height: CGFloat(rimW), x: 0, y: Float(-(h / 2 + rimW / 2)))
        strip(width: CGFloat(rimW), height: CGFloat(h), x: Float(w / 2 + rimW / 2), y: 0)
        strip(width: CGFloat(rimW), height: CGFloat(h), x: Float(-(w / 2 + rimW / 2)), y: 0)
        var pos = it.position * Self.unit
        pos.y += (it.footprint.y / 2) * Self.unit
        let lift = 2.2 * Self.unit
        if it.yaw == 0 {
            pos.z += lift
            focusNode.eulerAngles = SCNVector3(0, 0, 0)
        } else {
            pos.x += lift
            focusNode.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
        }
        focusNode.position = CamperScene.vector(pos)
        focusNode.renderingOrder = 30
        focusNode.isHidden = false
    }

    private func applyPhotos(_ holder: SCNNode, _ it: CamperRoomPlacedItem) {
        guard let body = holder.childNodes.first(where: { $0.name == "body" }), let g = body.geometry,
              let mesh = furniture[it.furnitureId] else { return }
        let photos: [String]
        if photosMode, it.uid == focusFrameUid, let preview = previewPhotoId {
            photos = [preview]
        } else {
            photos = it.photos
        }
        var mats = g.materials
        var shown: String?
        let previewing = photos != it.photos
        for (i, group) in mesh.groups.enumerated() where i < mats.count {
            guard case .room(.photo(let slot)) = group.material else { continue }
            let index = Int(slot.dropFirst(4)) ?? 0
            let m = mats[i]
            palette.configure(m, CamperMaterials.spec(group.material, paint: paint, mood: mood))
            if index < photos.count, let image = photoImages[photos[index]] {
                if index == 0 { shown = photos[0] }
                // 印画は光を受けない。夜の壁は暗く、窓と同じ硝子だと白い板になって、飾った写真が消える
                m.lightingModel = .constant
                // UIImage のまま渡すと端末によって黒い面になることがあるので CGImage にする
                m.diffuse.contents = image.cgImage ?? image
                m.diffuse.wrapS = .clamp
                m.diffuse.wrapT = .clamp
                m.diffuse.mipFilter = .linear
                // パネル全面に伸ばさず中央で切る（縦長の写真を横長の額に載せても潰れない）
                let imgW = max(1, image.size.width), imgH = max(1, image.size.height)
                let panelA = CamperRoomPhotoFit.panelAspect(flatPositions: mesh.positions, indices: group.indices)
                let fit = CamperRoomPhotoFit.uvFit(imageAspect: imgW / imgH, panelAspect: panelA)
                let scale = SCNMatrix4MakeScale(Float(fit.scaleX), Float(fit.scaleY), 1)
                let shift = SCNMatrix4MakeTranslation(Float(fit.offsetX), Float(fit.offsetY), 0)
                m.diffuse.contentsTransform = SCNMatrix4Mult(scale, shift)
                // configure が付けた clearCoat / metalness が残ると印画が白い膜に見える
                m.clearCoat.contents = 0.0
                m.clearCoatRoughness.contents = 0.0
                m.metalness.contents = 0.0
                m.roughness.contents = 1.0
                m.emission.contents = CamperScene.color(0x000000)
                m.emission.intensity = 0
                m.transparency = 1
                m.writesToDepthBuffer = true
            }
            mats[i] = m
        }
        g.materials = mats
        let saved = it.photos.first.flatMap { photoImages[$0] != nil ? $0 : nil }
        let previewed = previewing ? shown : nil
        if framedPhotos[it.uid] != saved || previewedPhotos[it.uid] != previewed {
            framedPhotos[it.uid] = saved
            previewedPhotos[it.uid] = previewed
            onFramed?(framedPhotos, previewedPhotos)
        }
    }

    /// 部屋を組み上げ、SCNView が画面に大きさを持って載っているか（外から入る時の覆いを消してよいか・2026-10-21）
    var isShowingRoom: Bool {
        guard builtKey != nil, let view = scnView, view.window != nil else { return false }
        return view.bounds.width > 1 && view.bounds.height > 1
    }

    /// 止まっている SCNView に次のコマを描かせる
    func requestRender() { kickRender() }

    private func kickRender() {
        // 止まっている SCNView（rendersContinuously = false）に、材質の差し替えを気づかせる
        guard let view = scnView else { return }
        view.rendersContinuously = true
        view.scene = scene
        DispatchQueue.main.async { [weak self] in self?.scnView?.rendersContinuously = false }
    }

    // MARK: 灯り

    private func rebuildLamps(_ items: [CamperRoomPlacedItem], layout: CamperRoomLayout, style: CamperRoomStyle) {
        var specs = CamperRoomBuilder.lights(items, style: style, layout: layout)
        defer { lampSpecs = specs }
        if studio {
            // 図鑑の寄り: 灯りの無い家具も夜に見えるよう、近くに暖色の灯りを 1 つ
            // 家具の斜め前上に置いた電球ほどの灯り（届く距離 50・まわりは暗い）
            specs.append(CamperLightSpec(name: "interior.studio", kind: .omni, pattern: .roomLamp,
                                         position: CV3(layout.size.x * 0.5 + 14, 44, 30),
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
            // 型どおり（部屋の家具灯はなだらか・`CamperLightPattern.roomLamp`）
            spec.applyAttenuation(to: l, unit: Self.unit)
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
        // 夜は灯りの溜まりの外が真っ黒に潰れないよう、ごく弱い暖色の環境光（木の色がわずかに残る）
        ambientNode.light?.intensity = CGFloat(night ? 38 : 90)
        ambientNode.light?.color = night ? CamperScene.color(0x2E261C) : CamperScene.color(0xFFF6EA)
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
            // 写真を飾る場面の選んだ額は、切った壁の向きでも消さない（飾ったのに額ごと消えて「載らない」に見える）
            if photosMode, entry.item.uid == focusFrameUid {
                entry.node.isHidden = false
                continue
            }
            // 後ろの壁（x = 0）が手前に来て切られた時は、その壁の物も見せない
            entry.node.isHidden = entry.item.yaw != 0 && !c.cutsFrontEnd
        }
        // 写真を飾る場面では天井の換気窓を隠す（切ったあとも戻さない）
        applyPhotosModeVisibility()
        if photosMode { updateFocusRing() }
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
        guard let item, let placed = CamperRoomBuilder.place(item, ceiling: layout?.ceilingHeight ?? CamperRoomLayout.ceiling) else {
            SCNTransaction.commit()
            return
        }
        // 持ち上げ: 7 浮かせ、接地の影を広げて薄く（板の付箋「長押しで 7 浮かせ、影を広げる」）。
        // 棚から押して置く途中の家具（まだ部屋に無い）は、マスの白と赤だけを出す（2026-10-21）
        if let entry = itemNodes[item.u] {
            transform(entry.node, displayed(entry.item))
            if let contact = entry.node.childNodes.first(where: { $0.name == "contact" }) {
                contact.scale = SCNVector3(1.35, 1.35, 1.35)
                if placed.placement == .floor { contact.position = SCNVector3(0, Float(-7 * Self.unit + 0.0015), 0) }
            }
        }
        SCNTransaction.commit()
        // 白（置ける）と赤（ぶつかる #F0565A）のマス
        let ok = check?.ok ?? true
        let blocked = check?.blocked ?? []
        let cell = CamperRoomLayout.cell
        if let r = item.rect {
            for c in r.cells {
                let red = !ok && (blocked.isEmpty || blocked.contains(c))
                overlayNode.addChildNode(cellNode(center: CV3((Double(c.x) + 0.5) * cell, placed.placement == .floor ? 0.3 : (layout?.ceilingHeight ?? CamperRoomLayout.ceiling) - 0.3,
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

    /// 押して置くときの「置ける所」（薄い白のマス・2026-10-21）。nil で消す
    func setHints(_ area: CamperRoomFitArea?) {
        guard area != hintArea else { return }
        hintArea = area
        overlayNode.childNodes.filter { $0.name == "hint" }.forEach { $0.removeFromParentNode() }
        guard let area, let layout else { return }
        let cell = CamperRoomLayout.cell
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = CamperScene.color(0xFFFFFF, alpha: 0.16)
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        let holder = SCNNode()
        holder.name = "hint"
        holder.renderingOrder = 19
        holder.castsShadow = false
        for c in area.cells {
            let y = area.ceiling ? layout.ceilingHeight - 0.4 : 0.25
            let plane = SCNPlane(width: CGFloat(8.6 * Self.unit), height: CGFloat(8.6 * Self.unit))
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            n.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            n.position = CamperScene.vector(CV3((Double(c.x) + 0.5) * cell, y, (Double(c.z) + 0.5) * cell) * Self.unit)
            holder.addChildNode(n)
        }
        for w in area.wall {
            let lo = CamperRoomLayout.rowBottoms[w.row]
            let along = (Double(w.column) + 0.5) * cell
            let center = w.wall == .back ? CV3(along, lo + CamperRoomLayout.rowHeight / 2, 0.35) : CV3(0.35, lo + CamperRoomLayout.rowHeight / 2, along)
            let plane = SCNPlane(width: CGFloat((cell - 1.4) * Self.unit), height: CGFloat((CamperRoomLayout.rowHeight - 1.4) * Self.unit))
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            if w.wall == .left { n.eulerAngles = SCNVector3(0, Float.pi / 2, 0) }
            n.position = CamperScene.vector(center * Self.unit)
            holder.addChildNode(n)
        }
        let flat = holder.flattenedClone()
        flat.name = "hint"
        flat.renderingOrder = 19
        flat.castsShadow = false
        overlayNode.addChildNode(flat)
        kickRender()
    }

    private var hintArea: CamperRoomFitArea?

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
