import SwiftUI
import UIKit
#if canImport(SceneKit)
import SceneKit
#endif

/// メダルを手に取って回す（板 Badge3D・2026-10-09）。全画面。
///
/// SceneKit の円柱で硬貨を作る: 表＝メダルの絵、裏＝金属ごとの絞り羽根に**持ち主の名前と
/// 受け取った日を重ねた絵**、縁＝金属ごとの細いギザの帯を円周に巻く。
/// 表・裏は面を少しふくらませ（`MedalRelief`）、控えめな映り込みを付けて、回すと光が流れる（凹凸は縁のギザだけ）。指で横に払うと回り、
/// 離すと惰性で少し回って止まる（止まりきったらゆっくり回り続ける）。
///
/// **「視差効果を減らす」の人には勝手に回さない**（惰性も短くする）。読み上げでは
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

    var body: some View {
        GeometryReader { geo in
            let coin = MedalTextureLayout.coinSide(screenWidth: Double(geo.size.width))
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 20) {
                    Spacer(minLength: 0)
                    coinStage(coin)
                    captions
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                closeButton
            }
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

    @ViewBuilder
    private func coinStage(_ coin: Double) -> some View {
        ZStack {
            if badge.key == "earlyUser" {
                // 後光の代わりの淡い真鍮の光（硬貨の外側だけに出る）
                Circle()
                    .fill(RadialGradient(colors: [WebTheme.accent.opacity(0.30), Color.clear],
                                         center: .center, startRadius: coin * 0.30, endRadius: coin * 0.62))
                    .frame(width: coin * 1.3, height: coin * 1.3)
                    .accessibilityHidden(true)
            }
            MedalCoinView(textures: textures, fallbackImage: BadgeCatalog.largeImage(badge.key, tier: badge.tier),
                          reduceMotion: reduceMotion, flips: flips)
                .frame(width: coin, height: coin)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("\(BadgeCatalog.fullName(badge.key, tier: badge.tier)) のメダル",
                                      "\(BadgeCatalog.fullName(badge.key, tier: badge.tier)) medal"))
                .accessibilityAddTraits(.isImage)
                .accessibilityAction(named: L("裏返す", "Turn over")) { flips += 1 }
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
    }
}

// MARK: - 硬貨

/// 硬貨。iOS では SceneKit（`MedalSceneView`）、SceneKit の無い Linux の模型では絵を置くだけ
private struct MedalCoinView: View {
    let textures: MedalTextures.Faces?
    let fallbackImage: String
    let reduceMotion: Bool
    let flips: Int

    var body: some View { coin }

    #if canImport(SceneKit)
    private var coin: some View {
        MedalSceneView(textures: textures, reduceMotion: reduceMotion, flips: flips)
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

/// SceneKit で描く硬貨。指で回す・惰性・自動で回る（「視差効果を減らす」では回さない）
private struct MedalSceneView: UIViewRepresentable {
    let textures: MedalTextures.Faces?
    let reduceMotion: Bool
    let flips: Int

    func makeCoordinator() -> MedalCoinCoordinator { MedalCoinCoordinator() }

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
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.lastFlips = flips
        if let textures { context.coordinator.apply(textures) }
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.reduceMotion = reduceMotion
        if let textures, !coordinator.hasTextures { coordinator.apply(textures) }
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

    private(set) var hasTextures = false
    var reduceMotion = false
    var lastFlips = 0

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
    /// 止まりきったあと、ゆっくり回る速さ（板: 9秒で1周 ≈ 0.7rad/s。それより控えめに）
    private static let idleSpin: Float = 0.45

    override init() {
        super.init()
        buildScene()
    }

    private func buildScene() {
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

        // 光（2026-10-09 立体感の見直し）: 環境光は控えめにし（強いと凹凸の陰が消えてのっぺりする）、
        // 左上手前の主な光・右の弱い補いの光・後ろ右の縁取りの光の3つで、回すと光と陰が面と縁を滑る
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        scene.rootNode.addChildNode(ambient)
        for (position, intensity) in [(SCNVector3(-2.5, 3, 5), CGFloat(800)),
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

        applyAngles()
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
        edge.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(textures.edgeRepeat), 1, 1)
        hasTextures = textures.front != nil
        applyRelief(textures)
    }

    /// 面のふくらみ・縁のギザの凹凸（法線の絵・`MedalRelief`）と、周りの映り込み
    private func applyRelief(_ textures: MedalTextures.Faces) {
        let side = MedalRelief.side
        for (material, image) in [(front, textures.front), (back, textures.back)] {
            guard let image, let normal = MedalReliefImage.normalMap(of: image, width: side, height: side,
                                                                      strength: MedalRelief.strength,
                                                                      dome: MedalRelief.dome,
                                                                      relief: MedalRelief.faceRelief) else { continue }
            material.normal.contents = normal
            material.normal.mipFilter = .linear
        }
        if let image = textures.edge, let cg = image.cgImage {
            // 縁の帯は左右がつながる。高さはギザが潰れない程度に半分へ
            let width = max(3, cg.width / 2), height = max(3, cg.height / 2)
            if let normal = MedalReliefImage.normalMap(of: image, width: width, height: height,
                                                       strength: MedalRelief.edgeStrength, dome: 0, wrapsX: true) {
                edge.normal.contents = normal
                edge.normal.wrapS = .repeat
                edge.normal.wrapT = .clamp
                edge.normal.contentsTransform = edge.diffuse.contentsTransform
            }
        }
        let reflection = MedalReliefImage.studio(tint: MedalReliefImage.tint(textures.metal))
        for material in [front, back, edge] {
            material.reflective.contents = reflection
            material.reflective.intensity = MedalReliefImage.reflectionIntensity
        }
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        velocity = reduceMotion ? 0 : Self.idleSpin
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// 裏返す（読み上げの操作）。いまの向きから半周先の、表か裏の正面へ
    func flip() {
        let half = Float.pi
        flipTarget = (yaw / half).rounded() * half + half
        velocity = 0
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        let width = Float(max(1, view.bounds.width))
        let move = gesture.translation(in: view)
        gesture.setTranslation(.zero, in: view)
        switch gesture.state {
        case .began:
            dragging = true
            flipTarget = nil
            velocity = 0
        case .changed:
            // 幅いっぱい払うと約 1.2 周の 4 割（指に付いてくる量）
            yaw += Float(move.x) / width * .pi * 1.5
            pitch = min(0.6, max(-0.6, pitch + Float(move.y) / width * 1.2))
        case .ended, .cancelled, .failed:
            dragging = false
            let speed = Float(gesture.velocity(in: view).x) / width * .pi * 1.5
            // 惰性は付けるが、速すぎる払いは抑える。「視差効果を減らす」では弱く
            let limit: Float = reduceMotion ? 3 : 14
            velocity = min(limit, max(-limit, speed))
        default:
            break
        }
        applyAngles()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = Float(lastTimestamp == 0 ? 0 : now - lastTimestamp)
        lastTimestamp = now
        guard dt > 0, dt < 0.1, !dragging else { return }

        if let target = flipTarget {
            // なめらかに寄せる（「視差効果を減らす」では一息に）
            let step = reduceMotion ? 1 : min(1, dt * 7)
            yaw += (target - yaw) * step
            if abs(target - yaw) < 0.002 { yaw = target; flipTarget = nil }
        } else {
            yaw += velocity * dt
            // 速さは、ゆっくり回る速さ（減らす設定では 0）へ戻っていく
            let resting: Float = reduceMotion ? 0 : (velocity < 0 ? -Self.idleSpin : Self.idleSpin)
            let damping: Float = reduceMotion ? 6 : 1.6
            velocity += (resting - velocity) * min(1, dt * damping)
        }
        // 傾きは置いたときの角度へゆっくり戻す
        pitch += (Self.restingPitch - pitch) * min(1, dt * 2.5)
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
                          wrapsX: Bool = false) -> UIImage? {
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
                                         strength: strength, dome: dome, relief: relief, wrapsX: wrapsX)
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
