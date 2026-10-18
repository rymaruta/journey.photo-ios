import SwiftUI
import UIKit
#if canImport(SceneKit)
import SceneKit
#endif

/// メダルを手に取って回す（板 Badge3D・2026-10-09）。全画面。
///
/// SceneKit の円柱で硬貨を作る: 表＝メダルの絵、裏＝金属ごとの絞り羽根に**持ち主の名前と
/// 受け取った日を重ねた絵**、縁＝金属ごとの細いギザの帯を円周に巻く。
/// 表・裏は面を少しふくらませ（`MedalRelief`）、絵の大きな形をほんの少し浮き彫りにし、縁の内側に細い面取りを付け、
/// 控えめな映り込みを付けて、回すと光と陰が流れる（2026-10-14）。指で横に払うと回り、
/// 離すと惰性で少し回って止まる（止まりきったらゆっくり回り続ける）。
///
/// **「視差効果を減らす」の人には勝手に回さない**（惰性も短くする・浮き彫りと映り込みも半分）。読み上げでは
/// 「裏返す」の操作で表と裏を替えられる。
///
/// 初期ユーザー章の後光は硬貨に貼らない（硬貨は内側の円だけ）。代わりに後ろに真鍮の淡い光を敷く。
struct MedalViewerView: View {

    let badge: EarnedBadge
    /// 裏に刻む名前（バッジの持ち主の表示名）
    let ownerName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textures: MedalTextures.Faces?
    /// 読み上げの「裏返す」を押した回数（数の変化で裏返す）
    @State private var flips = 0
    /// 画面写真のために止める向き（Debug の起動の鍵だけ・`PreviewSession.medalPoses`）
    private let previewPoses = PreviewSession.medalPoses
    /// 画面写真の向きの準備の具合（読み上げの値に出し、UI テストが待つ。止めていないときは空）
    @State private var poseMarker = ""

    var body: some View {
        // 🔴 **組みは画面の大きさに固定し、× は画面の右上に重ねる**（2026-10-09 owner「メダル回す画面で
        // 戻れない」）。初期ユーザーの後光（硬貨の 1.3 倍）が組みの幅に効いていて、組みが画面より広くなり、
        // × が画面の外へ押し出されていた（説明の文も折り返さず右端で切れていた）。後光は硬貨の背景に置く
        GeometryReader { geo in
            let coin = MedalTextureLayout.coinSide(screenWidth: Double(geo.size.width))
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                coinStage(coin)
                captions
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .topTrailing) { closeButton }
        }
        .background { background }
        .statusBarHidden(true)
        .task {
            guard textures == nil else { return }
            textures = MedalTextures.make(badge: badge, ownerName: ownerName)
        }
    }

    /// 地（板: 左寄りに少し明るい丸いグラデーション）
    private var background: some View {
        RadialGradient(colors: [ProMarkColors.color(0x17181B), ProMarkColors.color(0x050505), Color.black],
                       center: UnitPoint(x: 0.3, y: 0.45), startRadius: 0, endRadius: 520)
            .ignoresSafeArea()
    }

    private func coinStage(_ coin: Double) -> some View {
        MedalCoinView(textures: textures, fallbackImage: BadgeCatalog.largeImage(badge.key, tier: badge.tier),
                      reduceMotion: reduceMotion, flips: flips, shape: .coin, poses: previewPoses,
                      onPoseReady: previewPoses == nil ? nil : { poseMarker = $0 })
        .frame(width: coin, height: coin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(BadgeCatalog.fullName(badge.key, tier: badge.tier)) のメダル",
                              "\(BadgeCatalog.fullName(badge.key, tier: badge.tier)) medal"))
        .accessibilityAddTraits(.isImage)
        .accessibilityValue(poseMarker)
        .accessibilityAction(named: L("裏返す", "Turn over")) { flips += 1 }
        .accessibilityIdentifier("medalViewer.coin")
        // 後光は**背景に置く**（組みの大きさに効かせない・画面の幅を超えても × を押し出さない）。
        // 指の払いも硬貨へ通す
        .background {
            if badge.key == "earlyUser" {
                // 後光の代わりの淡い真鍮の光（硬貨の外側だけに出る）
                Circle()
                    .fill(RadialGradient(colors: [WebTheme.accent.opacity(0.30), Color.clear],
                                         center: .center, startRadius: coin * 0.30, endRadius: coin * 0.62))
                    .frame(width: MedalTextureLayout.haloSide(coin: coin),
                           height: MedalTextureLayout.haloSide(coin: coin))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var captions: some View {
        VStack(spacing: 8) {
            Text(L("手に取って回す", "Turn it over"))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            Text(BadgeCatalog.fullName(badge.key, tier: badge.tier))
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.foreground)
                .multilineTextAlignment(.center)
            if let date = BadgeCatalog.awardDate(badge.at) {
                Text(L("\(date) に受け取りました", "Received \(date)"))
                    .font(JPFont.mono(12))
                    .foregroundStyle(WebTheme.muted2)
            }
            Text(L("指で横に払うと裏返ります。裏には名前と日付が入っています。",
                   "Swipe sideways to turn it over. Your name and the date are on the back."))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .jpGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .accessibilityLabel(Labels.Common.close)
        .accessibilityIdentifier("medalViewer.close")
    }
}

// MARK: - 硬貨

/// 手に取って回すものの形。硬貨（メダル）か、角の丸いカード（サポーター証・板 Badge3D）か、
/// 旅のトランク（2026-10-17・角の丸い箱に持ち手）
enum SpinShape: Equatable {
    case coin
    /// 横 ÷ 縦（サポーター証は 342:216）
    case card(aspect: Double)
    /// 旅のトランク。横 ÷ 縦（胴は 360:268）・厚み ÷ 横・角の丸み ÷ 横・持ち手の色（0〜1 の RGB）
    case box(aspect: Double, depth: Double, corner: Double, handle: SpinRGB)
}

/// 3D の部品の色（SwiftUI・UIKit を読まない形で渡す）
struct SpinRGB: Equatable {
    let r: Double
    let g: Double
    let b: Double
}

/// 決まった向きへ回す合図（旅のトランクの「正面・側面・上と背面・底」・板 TrunkSpin）。
/// `id` を替えるたびに、その向きへなめらかに回す（ラジアン。横の回りと縦の傾き）
struct SpinAim: Equatable {
    let id: Int
    let yaw: Double
    let pitch: Double
}

/// 旅のトランクの箱の、表と裏のほかの面の絵（板「旅のトランク」の TrunkFaces・2026-10-18）。
/// 左右の側面（86×268）・上の面と底（360×86）・持ち手の面と付け根の金具。`TrunkTextures.box` が作る
struct SpinBoxFaces {
    /// 背面（後から描いて貼る。表を先に出すため・2026-10-18）
    let back: UIImage?
    let left: UIImage?
    let right: UIImage?
    let top: UIImage?
    let bottom: UIImage?
    /// 持ち手の面（正面の持ち手と同じ塗り・縫い目）
    let handle: UIImage?
    /// 持ち手の付け根の金具（錠前と同じ金属）
    let clip: UIImage?
}

/// 硬貨・カード。iOS では SceneKit（`MedalSceneView`）、SceneKit の無い Linux の模型では絵を置くだけ
struct MedalCoinView: View {
    let textures: MedalTextures.Faces?
    let fallbackImage: String
    let reduceMotion: Bool
    let flips: Int
    var shape: SpinShape = .coin
    /// 画面写真のために止める向き（Debug の起動の鍵だけ）。nil ならふだんどおり回る
    var poses: [MedalPose]? = nil
    /// 画面写真の向きの準備の具合（「pose-<番号>-ready」など）を受け取る
    var onPoseReady: ((String) -> Void)? = nil
    /// 旅のトランクの箱の、表と裏のほかの面（`.box` のときだけ）
    var box: SpinBoxFaces? = nil
    /// 決まった向きへ回す合図（旅のトランクの向きのボタン）
    var aim: SpinAim? = nil

    var body: some View { coin }

    #if canImport(SceneKit)
    private var coin: some View {
        MedalSceneView(textures: textures, reduceMotion: reduceMotion, flips: flips, shape: shape, poses: poses,
                       onPoseReady: onPoseReady, box: box, aim: aim)
    }
    #else
    /// Linux の模型のための代わり。**実機では使わない**
    private var coin: some View {
        Image(fallbackImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
    #endif
}

#if canImport(SceneKit)

/// SceneKit で描く硬貨・カード。指で回す・惰性・自動で回る（「視差効果を減らす」では回さない）
private struct MedalSceneView: UIViewRepresentable {
    let textures: MedalTextures.Faces?
    let reduceMotion: Bool
    let flips: Int
    let shape: SpinShape
    let poses: [MedalPose]?
    let onPoseReady: ((String) -> Void)?
    let box: SpinBoxFaces?
    let aim: SpinAim?

    func makeCoordinator() -> MedalCoinCoordinator { MedalCoinCoordinator(shape: shape) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        // 角度は自前の表示の刻み（CADisplayLink）で書き換える。描き直しは毎回させる
        view.rendersContinuously = true
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(MedalCoinCoordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)
        if let poses, !poses.isEmpty {
            // 画面写真: 止めた向きで見せ、押すと次の向きへ（Debug の起動の鍵だけ）
            context.coordinator.poseReady = onPoseReady
            context.coordinator.pose(poses)
            let tap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(MedalCoinCoordinator.handlePoseTap(_:)))
            view.addGestureRecognizer(tap)
        }
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.lastFlips = flips
        if let textures { context.coordinator.apply(textures) }
        if let box { context.coordinator.applyBox(box) }
        context.coordinator.lastAimId = aim?.id
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.reduceMotion = reduceMotion
        if let textures, !coordinator.hasTextures { coordinator.apply(textures) }
        if let box, !coordinator.hasBoxFaces { coordinator.applyBox(box) }
        if let aim, aim.id != coordinator.lastAimId {
            coordinator.lastAimId = aim.id
            coordinator.aim(yaw: aim.yaw, pitch: aim.pitch)
        }
        if flips != coordinator.lastFlips {
            coordinator.lastFlips = flips
            coordinator.flip()
        }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: MedalCoinCoordinator) {
        coordinator.stop()
    }
}

/// 硬貨の場面と、指の動き・惰性
@MainActor
final class MedalCoinCoordinator: NSObject {

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let coin = SCNNode()
    private let front = SCNMaterial()
    private let back = SCNMaterial()
    private let edge = SCNMaterial()
    private let cap = SCNMaterial()
    /// 旅のトランクの箱の面（左・右・上・底）と持ち手（2026-10-18・面ごとに絵を貼る）
    private let left = SCNMaterial()
    private let right = SCNMaterial()
    private let top = SCNMaterial()
    private let bottom = SCNMaterial()
    private let handleCap = SCNMaterial()
    private let handleSide = SCNMaterial()
    private let clipMaterial = SCNMaterial()
    private(set) var hasBoxFaces = false
    /// 最後に受けた向きの合図
    var lastAimId: Int?
    /// 向きのボタンで向かう角度（横・縦）
    private var aimTarget: (yaw: Float, pitch: Float)?
    /// 向きのボタンで着いた向きに止めている（指で払うまで動かさない・板 TrunkSpin どおり）
    private var aimHeld = false

    private(set) var hasTextures = false
    /// 「視差効果を減らす」。変わったら浮き彫りと映り込みの強さを作り直す
    var reduceMotion = false {
        didSet { if oldValue != reduceMotion { reliefSettingsChanged() } }
    }
    var lastFlips = 0
    /// 貼った絵（浮き彫りを作り直すときに使う）
    private var faces: MedalTextures.Faces?
    /// 浮き彫り（法線の絵）を作る仕事。画面の処理の外で作る
    private var reliefTask: Task<Void, Never>?
    /// 画面写真のために止める向き（Debug の起動の鍵だけ）と、いま見せている番号
    private var poses: [MedalPose] = []
    private var poseIndex = 0
    /// いま貼ってある浮き彫りの強さ（作り終えて貼ったもの）
    private var appliedAmount: Double?
    /// 画面写真の向きの準備ができたか（「pose-<番号>-ready」）を知らせる先。UI テストがこれを待ってから撮る
    var poseReady: ((String) -> Void)?

    /// 横の回り（ラジアン）と、少しだけ傾ける縦の回り
    private var yaw: Float = -0.35
    private var pitch: Float = MedalCoinCoordinator.restingPitch
    /// 横の回りの速さ（ラジアン/秒）
    private var velocity: Float = 0
    private var dragging = false
    /// 読み上げの「裏返す」で向かう角度
    private var flipTarget: Float?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    /// 置いたときの傾き（板: rotateX(-8deg)）
    private static let restingPitch: Float = -0.14
    /// 箱を置いたときの傾き（板 TrunkSpin: rotateX(-16deg)。SceneKit では上の面が手前へ傾く向きが正）
    private static let boxRestingPitch: Float = 0.28
    /// 箱を置いたときの横の向き（板 TrunkSpin: rotateY(-34deg)。正面から始めず、少し斜めから側面が見える）
    private static let boxRestingYaw: Float = -34 * .pi / 180
    /// 止まりきったあと、ゆっくり回る速さ（板: 9秒で1周 ≈ 0.7rad/s。それより控えめに）
    private static let idleSpin: Float = 0.45

    /// 止まりきったあとに回る速さ。**トランクは勝手に回さず、-20° の斜めで止めて置く**
    /// （2026-10-17・run 466: 回り続けると、開いて数秒で横を向き正面の絵が見えなかった）。払えば惰性で回る
    private var restingSpin: Float {
        if case .box = shape { return 0 }
        return Self.idleSpin
    }

    private let shape: SpinShape

    private var isBox: Bool {
        if case .box = shape { return true }
        return false
    }

    /// 決まった向きへ回す（旅のトランクの向きのボタン）。いまの横の回りから近い周に寄せる
    func aim(yaw target: Double, pitch targetPitch: Double) {
        let turn = 2 * Double.pi
        let current = Double(yaw)
        let nearest = target + (((current - target) / turn).rounded()) * turn
        aimTarget = (Float(nearest), Float(targetPitch))
        aimHeld = false
        flipTarget = nil
        velocity = 0
    }

    init(shape: SpinShape = .coin) {
        self.shape = shape
        super.init()
        // 箱は少し上から見下ろして置く（板 TrunkSpin の rotateX(-16deg)＝上の面と持ち手が見える）
        if isBox {
            pitch = Self.boxRestingPitch
            yaw = Self.boxRestingYaw
        }
        buildScene()
    }

    private func buildScene() {
        switch shape {
        case .coin: buildCoin()
        case .card(let aspect): buildCard(aspect: aspect)
        case let .box(aspect, depth, corner, handle):
            // 旅のトランク: 6つの面に絵を貼った箱（表＝胴の絵・裏＝背面・左右・上・底＝板 TrunkFaces）に、上の持ち手
            buildBox(aspect: aspect, depthRatio: depth, cornerRatio: corner)
            addHandle(aspect: aspect, depth: depth, color: handle)
        }
        addLightsAndCamera()
        if case .box = shape { brightenForBox() }
        applyAngles()
    }

    /// サポーター証（板 Badge3D: 342×216・角 16・厚み 4・縁は角の丸みまで金の小口）。
    /// 縁は角丸の四角を押し出した形（`SCNShape`）に金の帯を貼り、表と裏は角を丸めた平面
    private func buildCard(aspect: Double,
                           cornerRatio: Double = SupporterCardLayout.cornerRadius / SupporterCardLayout.width,
                           thicknessRatio: Double = SupporterCardLayout.thickness / SupporterCardLayout.width,
                           glossyEdge: Bool = true) {
        // 舞台は硬貨と同じ正方形（視野 30° で、5.2 離れて見える高さは約 2.79）。カードは
        // 横幅が舞台の 9 割ほどになる 2.56 にする（硬貨の直径 2 のままだと板より小さく見える）
        // トランクは厚みがあるので、斜めから見ても舞台に収まるよう少し小さく（2.2）
        let width: CGFloat = glossyEdge ? 2.56 : 2.2
        let height = width / CGFloat(max(0.1, aspect))
        let corner = width * CGFloat(cornerRatio)
        let thickness = width * CGFloat(thicknessRatio)

        let outline = UIBezierPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                   cornerRadius: corner)
        // 既定の細かさ（0.6）では角の丸みが直線の面取りになる（この場面は 1 が約 140pt）
        outline.flatness = 0.002
        let slab = SCNShape(path: outline, extrusionDepth: thickness)
        setUpMetal(edge)
        // 金の小口は光らせる（回すと光が縁を滑る）。トランクの側面（革・布・木）は光らせない
        edge.specular.contents = UIColor(white: glossyEdge ? 0.9 : 0.12, alpha: 1)
        edge.shininess = glossyEdge ? 0.6 : 0.2
        edge.diffuse.wrapS = .clamp
        edge.diffuse.wrapT = .clamp
        slab.materials = [edge, edge, edge]
        coin.addChildNode(SCNNode(geometry: slab))

        for (material, z, turned) in [(front, Float(thickness) / 2 + 0.001, false),
                                      (back, -Float(thickness) / 2 - 0.001, true)] {
            setUpMetal(material)
            material.diffuse.mipFilter = .linear
            let plane = SCNPlane(width: width, height: height)
            plane.cornerRadius = corner
            plane.cornerSegmentCount = 16
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(0, 0, z)
            if turned { node.eulerAngles = SCNVector3(0, Float.pi, 0) }
            coin.addChildNode(node)
        }
        scene.rootNode.addChildNode(coin)
    }

    /// 旅のトランクの箱（板「旅のトランク」の TrunkSpin・TrunkFaces・2026-10-18）。
    ///
    /// 板と同じく**6枚の面を角の丸い平面で組む**（表と裏は角 16・ほかの面は角 10。寸法は胴 360×268・
    /// 厚み 86）。押し出しの形（`SCNShape`）では側面が1つの材質で、面ごとの絵が貼れなかった。
    /// 面の角の丸みで空く隅は、少し小さい暗い芯の箱で埋める（縁の陰に見える）。
    /// 向きは展開図のまま: 上の面は正面の辺が下、底は正面の辺が上、側面は正面の辺が内側
    private func buildBox(aspect: Double, depthRatio: Double, cornerRatio: Double) {
        let width: CGFloat = 2.2
        let unit = width / 360
        let height = width / CGFloat(max(0.1, aspect))
        let depth = width * CGFloat(depthRatio)
        let faceCorner = 10 * unit

        // 芯（面の角の丸みで空く隅を埋める）
        let core = SCNBox(width: width - 4 * unit, height: height - 4 * unit, length: depth - 4 * unit, chamferRadius: 6 * unit)
        core.materials = [edge]
        edge.lightingModel = .lambert
        edge.specular.contents = UIColor(white: 0, alpha: 1)
        coin.addChildNode(SCNNode(geometry: core))

        func face(_ material: SCNMaterial, w: CGFloat, h: CGFloat, corner: CGFloat,
                  position: SCNVector3, euler: SCNVector3) {
            material.lightingModel = .lambert
            material.specular.contents = UIColor(white: 0, alpha: 1)
            material.locksAmbientWithDiffuse = true
            material.diffuse.mipFilter = .linear
            let plane = SCNPlane(width: w, height: h)
            plane.cornerRadius = corner
            plane.cornerSegmentCount = 12
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.position = position
            node.eulerAngles = euler
            coin.addChildNode(node)
        }
        let half = Float.pi / 2
        let lift: Float = 0.001
        face(front, w: width, h: height, corner: width * CGFloat(cornerRatio),
             position: SCNVector3(0, 0, Float(depth / 2) + lift), euler: SCNVector3(0, 0, 0))
        face(back, w: width, h: height, corner: width * CGFloat(cornerRatio),
             position: SCNVector3(0, 0, -Float(depth / 2) - lift), euler: SCNVector3(0, Float.pi, 0))
        // 左の側面は -x を向き、絵の右（正面の辺）が手前へ
        face(left, w: depth, h: height, corner: faceCorner,
             position: SCNVector3(-Float(width / 2) - lift, 0, 0), euler: SCNVector3(0, -half, 0))
        // 右の側面は +x を向き、絵の左（正面の辺）が手前へ
        face(right, w: depth, h: height, corner: faceCorner,
             position: SCNVector3(Float(width / 2) + lift, 0, 0), euler: SCNVector3(0, half, 0))
        // 上の面は +y を向き、絵の下（正面の辺）が手前へ
        face(top, w: width, h: depth, corner: faceCorner,
             position: SCNVector3(0, Float(height / 2) + lift, 0), euler: SCNVector3(-half, 0, 0))
        // 底は -y を向き、絵の上（正面の辺）が手前へ
        face(bottom, w: width, h: depth, corner: faceCorner,
             position: SCNVector3(0, -Float(height / 2) - lift, 0), euler: SCNVector3(half, 0, 0))
        scene.rootNode.addChildNode(coin)
    }

    /// 箱の左右・上・底と持ち手の絵を貼る（表と裏は `apply`）
    func applyBox(_ faces: SpinBoxFaces) {
        for (material, image) in [(back, faces.back), (left, faces.left), (right, faces.right), (top, faces.top),
                                  (bottom, faces.bottom)] {
            material.diffuse.contents = image
            // 表と裏と同じく、光の当たらない向きでも絵が沈まないよう少し自ら光らせる
            material.emission.contents = image
            material.emission.intensity = 0.45
        }
        if let handle = faces.handle {
            handleCap.diffuse.contents = handle
            handleCap.diffuse.wrapS = .clamp
            handleCap.diffuse.wrapT = .clamp
        }
        if let clip = faces.clip { clipMaterial.diffuse.contents = clip }
        hasBoxFaces = faces.left != nil
    }

    /// トランクの光（2026-10-17・run 466 の見比べ）: 正面の絵がトランクの画面（板 Main）と同じ明るさに見えるよう、
    /// 正面の少し左上にキーライトを足し、環境光は弱いまま。表と裏は光らせず（金属の映り込みは付けない）、
    /// 絵そのものを少し自ら光らせて暗く沈まないようにする
    private func brightenForBox() {
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 1100
        key.position = SCNVector3(-1.2, 1.4, 5)
        scene.rootNode.addChildNode(key)
        for material in [front, back] {
            material.lightingModel = .lambert
            material.specular.contents = UIColor(white: 0, alpha: 1)
        }
    }

    /// トランクの持ち手（上の角が丸い U の字を、胴の上に立てる・2026-10-17）
    private func addHandle(aspect: Double, depth: Double, color: SpinRGB) {
        let width: CGFloat = 2.2
        let height = width / CGFloat(max(0.1, aspect))
        // 胴の 360pt に対して 幅 100・高さ 36・太さ 10（2D の絵と同じ割合）
        let unit = width / 360
        let outer = UIBezierPath(roundedRect: CGRect(x: -50 * unit, y: 0, width: 100 * unit, height: 36 * unit),
                                 byRoundingCorners: [.bottomLeft, .bottomRight],
                                 cornerRadii: CGSize(width: 22 * unit, height: 22 * unit))
        let inner = UIBezierPath(roundedRect: CGRect(x: -40 * unit, y: 0, width: 80 * unit, height: 26 * unit),
                                 byRoundingCorners: [.bottomLeft, .bottomRight],
                                 cornerRadii: CGSize(width: 12 * unit, height: 12 * unit))
        outer.append(inner.reversing())
        outer.usesEvenOddFillRule = true
        outer.flatness = 0.002
        let thickness = width * CGFloat(depth) * 0.25
        let shape = SCNShape(path: outer, extrusionDepth: thickness)
        // 持ち手は正面と同じ塗りの立体（2026-10-18）: 前と後ろの面に持ち手の絵（塗り・縫い目）、
        // 押し出しの側面は同じ色の暗い方。絵が届く前は1色
        let base = UIColor(red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 1)
        for material in [handleCap, handleSide] {
            material.lightingModel = .blinn
            material.specular.contents = UIColor(white: 0.2, alpha: 1)
            material.diffuse.contents = base
        }
        handleSide.multiply.contents = UIColor(white: 0.72, alpha: 1)
        shape.materials = [handleCap, handleCap, handleSide]
        let node = SCNNode(geometry: shape)
        // SceneKit の形は上が +y（UIKit の「下」の角＝maxY が上になる）。U の字の開いた側（y=0）を
        // 胴の上の縁に合わせ、2D の絵と同じく 6pt ぶん埋める。前後は上の面の持ち手の場所（正面から 56・
        // 真ん中から奥へ 13）に立てる（板 TrunkSpin の `translateZ(-13px)`）
        let behind = -13 * Float(unit)
        node.position = SCNVector3(0, Float(height / 2 - 6 * unit), behind)
        coin.addChildNode(node)
        // 付け根の金具（錠前と同じ金属・20×14 を持ち手より少し厚く）
        clipMaterial.lightingModel = .blinn
        clipMaterial.specular.contents = UIColor(white: 0.5, alpha: 1)
        clipMaterial.diffuse.contents = UIColor(red: 0.79, green: 0.65, blue: 0.42, alpha: 1)
        // 付け根は正面の絵・上の面の絵と同じ真ん中（`TrunkFaces.handleClipCenters`・胴の真ん中から ±50）
        for x in TrunkFaces.handleClipCenters.map({ $0 - TrunkLooks.bodyWidth / 2 }) {
            let clip = SCNBox(width: 20 * unit, height: 14 * unit, length: thickness + 4 * unit, chamferRadius: 2 * unit)
            clip.materials = [clipMaterial]
            let clipNode = SCNNode(geometry: clip)
            clipNode.position = SCNVector3(Float(x * Double(unit)), Float(height / 2 - 1 * unit), behind)
            coin.addChildNode(clipNode)
        }
    }

    private func buildCoin() {
        let thickness = CGFloat(MedalTextureLayout.thicknessPerRadius)

        // 縁（円柱の側面）。上下の蓋は表・裏の円で隠れる
        let cylinder = SCNCylinder(radius: 1, height: thickness)
        cylinder.radialSegmentCount = 120
        for material in [edge, cap] { setUpMetal(material) }
        edge.diffuse.wrapS = .repeat
        edge.diffuse.wrapT = .clamp
        edge.diffuse.mipFilter = .linear
        cap.diffuse.contents = UIColor(white: 0.18, alpha: 1)
        cylinder.materials = [edge, cap, cap]
        let rim = SCNNode(geometry: cylinder)
        // 円柱の軸（Y）を手前向き（Z）へ
        rim.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        coin.addChildNode(rim)

        // 表と裏。四角い面の角を半径いっぱいに丸めて円にする（絵の向きが素直に決まる）
        for (material, z, turned) in [(front, Float(thickness) / 2 + 0.001, false),
                                      (back, -Float(thickness) / 2 - 0.001, true)] {
            setUpMetal(material)
            material.diffuse.mipFilter = .linear
            let plane = SCNPlane(width: 2, height: 2)
            plane.cornerRadius = 1
            plane.cornerSegmentCount = 48
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(0, 0, z)
            if turned { node.eulerAngles = SCNVector3(0, Float.pi, 0) }
            coin.addChildNode(node)
        }
        scene.rootNode.addChildNode(coin)
    }

    private func addLightsAndCamera() {
        // 光（2026-10-09 立体感の見直し）: 環境光は控えめにし（強いと凹凸の陰が消えてのっぺりする）、
        // 左上手前の主な光・右の弱い補いの光・後ろ右の縁取りの光の3つで、回すと光と陰が面と縁を滑る
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        scene.rootNode.addChildNode(ambient)
        let key = MedalRelief.keyLight
        for (position, intensity) in [(SCNVector3(Float(key.x), Float(key.y), Float(key.z)), CGFloat(800)),
                                      (SCNVector3(3.5, 0.5, 3), CGFloat(240)),
                                      (SCNVector3(2.5, 1.5, -4), CGFloat(360))] {
            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = .omni
            light.light?.intensity = intensity
            light.position = position
            scene.rootNode.addChildNode(light)
        }

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.1
        camera.zFar = 50
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 5.2)
        scene.rootNode.addChildNode(cameraNode)
    }

    /// 金属の面。**光り過ぎない**（絵の明るさを保つ。光の点は小さく弱く・owner「光反射しすぎて少し嫌だ」）
    private func setUpMetal(_ material: SCNMaterial) {
        material.lightingModel = .blinn
        material.specular.contents = UIColor(white: 0.3, alpha: 1)
        material.shininess = 0.75
        material.locksAmbientWithDiffuse = true
    }

    func apply(_ textures: MedalTextures.Faces) {
        front.diffuse.contents = textures.front
        back.diffuse.contents = textures.back
        edge.diffuse.contents = textures.edge
        if case .coin = shape {
            edge.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(textures.edgeRepeat), 1, 1)
        }
        hasTextures = textures.front != nil
        faces = textures
        if case .box = shape {
            // 箱の表と裏は絵を少し自ら光らせる（光の当たらない向きでも絵が沈まない・`brightenForBox`）
            front.emission.contents = textures.front
            front.emission.intensity = 0.45
            back.emission.contents = textures.back
            back.emission.intensity = 0.45
        }
        // 面のふくらみ・浮き彫り・面取り・縁のギザは硬貨の形に合わせた凹凸。サポーター証（カード）には貼らない
        if case .coin = shape { applyRelief(textures) }
    }

    /// いまの浮き彫りの強さ。画面写真で止めているときはその向きの強さ、ふだんは既定
    /// （「視差効果を減らす」なら半分）
    private var reliefAmount: Double {
        if poses.indices.contains(poseIndex) { return poses[poseIndex].amount }
        return MedalRelief.effectiveAmount(reduceMotion: reduceMotion)
    }

    /// 「視差効果を減らす」・見本の強さが変わった。浮き彫りを作り直す
    private func reliefSettingsChanged() {
        guard case .coin = shape, let faces, hasTextures else { return }
        applyRelief(faces)
    }

    /// 面のふくらみ・浮き彫り・面取り・縁のギザの凹凸（法線の絵・`MedalRelief`）と、周りの映り込み。
    ///
    /// **法線の絵は開いたときに1度だけ作る**（512px を2枚と縁の帯・ぼかしを含めて数十 ms）。画面の処理を
    /// 止めないよう外で作り、できたら貼る（それまでは平らなまま見える）。回している間の毎コマの負担は
    /// SceneKit が元から行う光の計算（法線の絵を読むだけ）で、前の作りから増えない
    private func applyRelief(_ textures: MedalTextures.Faces) {
        reliefTask?.cancel()
        let amount = reliefAmount
        let face = MedalRelief.face(amount: amount)
        // 縁の帯は強さに依らない。作り直しのときは前のを使う（待ちを短く）
        let needsEdge = edge.normal.contents == nil
        let frontImage = textures.front, backImage = textures.back
        let edgeImage = needsEdge ? textures.edge : nil
        reliefTask = Task { [weak self] in
            let maps = await Task.detached(priority: .userInitiated) { () -> [UIImage?] in
                let side = MedalRelief.side
                let faceMaps = [frontImage, backImage].map { image -> UIImage? in
                    guard let image else { return nil }
                    return MedalReliefImage.normalMap(of: image, width: side, height: side,
                                                      strength: MedalRelief.strength,
                                                      dome: MedalRelief.dome,
                                                      relief: face.relief,
                                                      blurRadius: MedalRelief.faceBlurRadius,
                                                      maxReliefSlope: face.maxSlope,
                                                      reliefFloor: face.floor,
                                                      bevelWidth: face.bevelWidth,
                                                      bevelDepth: face.bevelDepth)
                }
                var edgeMap: UIImage?
                if let image = edgeImage, let cg = image.cgImage {
                    // 縁の帯は左右がつながる。高さはギザが潰れない程度に半分へ
                    let width = max(3, cg.width / 2), height = max(3, cg.height / 2)
                    edgeMap = MedalReliefImage.normalMap(of: image, width: width, height: height,
                                                         strength: MedalRelief.edgeStrength, dome: 0, wrapsX: true)
                }
                return faceMaps + [edgeMap]
            }.value
            guard !Task.isCancelled, let self else { return }
            self.setRelief(front: maps[0], back: maps[1], edge: maps[2], metal: textures.metal)
            self.appliedAmount = amount
            self.reportPose()
        }
    }

    private func setRelief(front frontMap: UIImage?, back backMap: UIImage?, edge edgeMap: UIImage?,
                           metal: BadgeCatalog.Metal) {
        for (material, normal) in [(front, frontMap), (back, backMap)] {
            guard let normal else { continue }
            material.normal.contents = normal
            material.normal.mipFilter = .linear
        }
        if let edgeMap {
            edge.normal.contents = edgeMap
            edge.normal.wrapS = .repeat
            edge.normal.wrapT = .clamp
            edge.normal.contentsTransform = edge.diffuse.contentsTransform
        }
        let reflection = MedalReliefImage.studio(tint: MedalReliefImage.tint(metal))
        // 映り込み（回すと面をなでる光）も、「視差効果を減らす」の人には半分
        let scale = CGFloat(MedalRelief.effectiveAmount(reduceMotion: reduceMotion, base: 1))
        let intensity = MedalReliefImage.reflectionIntensity * scale
        for material in [front, back, edge] {
            material.reflective.contents = reflection
            material.reflective.intensity = intensity
        }
    }

    /// 画面写真のために止める（Debug の起動の鍵だけ）。最初の向きで止め、勝手に回さない
    func pose(_ list: [MedalPose]) {
        poses = list
        poseIndex = 0
        showPose()
    }

    /// 硬貨を押すと次の向きへ（画面写真のため）
    @objc func handlePoseTap(_ gesture: UITapGestureRecognizer) {
        guard !poses.isEmpty else { return }
        let previous = reliefAmount
        poseIndex = (poseIndex + 1) % poses.count
        showPose()
        if reliefAmount != previous { reliefSettingsChanged() }
        reportPose()
    }

    /// 画面写真の向きの準備の具合を知らせる。浮き彫りを作り直している間は「loading」、貼り終えたら「ready」
    private func reportPose() {
        guard poses.indices.contains(poseIndex) else { return }
        let ready = appliedAmount == poses[poseIndex].amount
        let marker = "pose-\(poseIndex)-\(ready ? "ready" : "loading")"
        let report = poseReady
        // SwiftUI の描き直しの最中に状態を変えない
        DispatchQueue.main.async { report?(marker) }
    }

    private func showPose() {
        guard poses.indices.contains(poseIndex) else { return }
        velocity = 0
        flipTarget = nil
        yaw = Float(poses[poseIndex].yaw)
        pitch = Self.restingPitch
        applyAngles()
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        velocity = reduceMotion || !poses.isEmpty ? 0 : restingSpin
    }

    func stop() {
        link?.invalidate()
        link = nil
        reliefTask?.cancel()
        reliefTask = nil
    }

    /// 裏返す（読み上げの操作）。いまの向きから半周先の、表か裏の正面へ
    func flip() {
        // 決め方はきっぷと同じ1つ（`SpinMotion`・2026-10-16）
        flipTarget = Float(SpinMotion.flipTarget(from: Double(yaw)))
        // 向きのボタンの寄せ・止めと取り合わない（裏返すが勝つ）
        aimTarget = nil
        aimHeld = false
        velocity = 0
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        // 画面写真で止めているときは払っても回さない（角度を決まったままにする）
        guard poses.isEmpty, let view = gesture.view else { return }
        let width = Float(max(1, view.bounds.width))
        let move = gesture.translation(in: view)
        gesture.setTranslation(.zero, in: view)
        switch gesture.state {
        case .began:
            dragging = true
            flipTarget = nil
            aimTarget = nil
            aimHeld = false
            velocity = 0
        case .changed:
            // 幅いっぱい払うと約 1.2 周の 4 割（指に付いてくる量・`SpinMotion.turnPerWidth`）
            yaw += Float(SpinMotion.yawDelta(dx: Double(move.x), width: Double(width)))
            // 箱は底と上まで見られるよう大きく傾ける（板 TrunkSpin の ±85°）。硬貨・カードは少しだけ
            let limit: Float = isBox ? 1.48 : 0.6
            pitch = min(limit, max(-limit, pitch + Float(move.y) / width * 1.2))
        case .ended, .cancelled, .failed:
            dragging = false
            // 惰性は付けるが、速すぎる払いは抑える。「視差効果を減らす」では弱く（`SpinMotion.releaseVelocity`）
            velocity = Float(SpinMotion.releaseVelocity(vx: Double(gesture.velocity(in: view).x), width: Double(width),
                                                        reduceMotion: reduceMotion))
        default:
            break
        }
        applyAngles()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = Float(lastTimestamp == 0 ? 0 : now - lastTimestamp)
        lastTimestamp = now
        guard dt > 0, dt < 0.1, !dragging, poses.isEmpty else { return }

        if let target = aimTarget {
            // 向きのボタン: 横と縦をなめらかに寄せる（「視差効果を減らす」では一息に）
            let step = Float(SpinMotion.approachStep(dt: Double(dt), reduceMotion: reduceMotion))
            yaw += (target.yaw - yaw) * step
            pitch += (target.pitch - pitch) * step
            if abs(target.yaw - yaw) < 0.002, abs(target.pitch - pitch) < 0.002 {
                yaw = target.yaw
                pitch = target.pitch
                aimTarget = nil
                // 着いたら止める（惰性・ゆっくり回りに戻さない）
                aimHeld = true
                velocity = 0
            }
            applyAngles()
            return
        } else if aimHeld {
            return
        } else if let target = flipTarget {
            // なめらかに寄せる（「視差効果を減らす」では一息に）
            let step = Float(SpinMotion.approachStep(dt: Double(dt), reduceMotion: reduceMotion))
            yaw += (target - yaw) * step
            if abs(target - yaw) < 0.002 { yaw = target; flipTarget = nil }
        } else {
            yaw += velocity * dt
            // 速さは、ゆっくり回る速さ（減らす設定では 0）へ戻っていく
            let resting: Float = reduceMotion ? 0 : (velocity < 0 ? -restingSpin : restingSpin)
            let damping: Float = reduceMotion ? 6 : 1.6
            velocity += (resting - velocity) * min(1, dt * damping)
        }
        // 傾きは置いたときの角度へゆっくり戻す。**箱は戻さない**（傾けて底や上を見ている途中で起き上がらない）
        if !isBox { pitch += (Self.restingPitch - pitch) * min(1, dt * 2.5) }
        applyAngles()
    }

    private func applyAngles() {
        coin.eulerAngles = SCNVector3(pitch, yaw, 0)
    }
}

/// 凹凸と映り込みの絵を作る（iOS だけ。数の計算は `MedalRelief`）
enum MedalReliefImage {
    /// 映り込みの強さ。**控えめ**（owner「光反射しすぎて少し嫌だ」で 0.32 から半分に）
    static let reflectionIntensity: CGFloat = 0.16

    /// 絵の明るさ（灰色・上の行から）を読み、法線の絵にする
    static func normalMap(of image: UIImage, width: Int, height: Int,
                          strength: Double, dome: Double, relief: Double = 1,
                          wrapsX: Bool = false, blurRadius: Int = MedalRelief.blurRadius,
                          maxReliefSlope: Double? = nil, reliefFloor: Double = 0,
                          bevelWidth: Double = 0, bevelDepth: Double = 0) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        var gray = [UInt8](repeating: 0, count: width * height)
        let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let rgba = MedalRelief.normalMap(luminance: gray, width: width, height: height,
                                         strength: strength, dome: dome, relief: relief, wrapsX: wrapsX,
                                         blurRadius: blurRadius, maxReliefSlope: maxReliefSlope,
                                         reliefFloor: reliefFloor,
                                         bevelWidth: bevelWidth, bevelDepth: bevelDepth)
        guard !rgba.isEmpty, let provider = CGDataProvider(data: Data(rgba) as CFData),
              let normal = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true,
                                   intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: normal)
    }

    /// 金属ごとの映り込みの色（真鍮・銅は温かく、銀・白金は白に近く）
    static func tint(_ metal: BadgeCatalog.Metal) -> UIColor {
        switch metal {
        case .brass: return UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1)
        case .bronze: return UIColor(red: 1.0, green: 0.80, blue: 0.64, alpha: 1)
        case .silver: return UIColor(red: 0.94, green: 0.96, blue: 1.0, alpha: 1)
        case .platinum: return UIColor(white: 1.0, alpha: 1)
        }
    }

    /// 写真の撮影所のような周り（360°を横長に広げた絵）: 下は暗い床、上は明るめ、
    /// 左上に大きな柔らかい光の箱、右に縦長の細い光。回すとこの光が面を横切る
    static func studio(tint: UIColor) -> UIImage {
        let size = CGSize(width: 512, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let sky = [UIColor(white: 0.42, alpha: 1).cgColor, UIColor(white: 0.10, alpha: 1).cgColor,
                       UIColor(white: 0.02, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: sky, locations: [0, 0.5, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            let glow = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: glow, locations: [0, 1]) {
                // 左上の光の箱
                cg.drawRadialGradient(gradient, startCenter: CGPoint(x: size.width * 0.36, y: size.height * 0.24),
                                      startRadius: 0, endCenter: CGPoint(x: size.width * 0.36, y: size.height * 0.24),
                                      endRadius: size.height * 0.30, options: [])
                // 右の縦長の光
                cg.saveGState()
                cg.translateBy(x: size.width * 0.66, y: size.height * 0.38)
                cg.scaleBy(x: 0.22, y: 1)
                cg.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero,
                                      endRadius: size.height * 0.30, options: [])
                cg.restoreGState()
            }
            // 金属の色をかける
            cg.setBlendMode(.multiply)
            cg.setFillColor(tint.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
        }
    }
}

#endif
