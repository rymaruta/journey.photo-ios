import SwiftUI
import UIKit
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import ImageIO
import SceneKitShim
#endif

/// 車を描く SCNView（指の動きは SwiftUI の側が受けて、向きの値で渡す）
struct CamperSceneView: UIViewRepresentable {
    let config: CamperConfig
    let angle: CamperAngle
    let animateAngle: Bool
    let doorOpen: Bool
    let reduceMotion: Bool
    /// 動きの長さの倍率（見本の起動で「中に入る」をゆっくり撮るときだけ 1 より大きい）
    var timeScale = 1.0
    /// いまの絵を写し取る口（中に入る時、部屋が組み上がるまでの覆いに使う）
    var snapshot: CamperSceneSnapshot?
    var onReady: (String) -> Void = { _ in }

    func makeCoordinator() -> CamperScene { CamperScene() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        // 動いた時だけ描き直す（止まっている間は描かない）
        view.rendersContinuously = false
        #if canImport(SceneKit)
        // 実機の HDR の画面で、光る面が SDR の白より明るく出ないように（2026-10-19 owner「夜の発光の仕方ひどい」。
        // シミュレータより強く光って見えた見立て）。場面は HDR で描いてトーンマップで 0〜1 に収め、拡張の明るさは使わない
        if #available(iOS 16.0, *), let metal = view.layer as? CAMetalLayer {
            metal.wantsExtendedDynamicRangeContent = false
        }
        #endif
        snapshot?.view = view
        // 1 コマの時間を測る（2026-10-31・#430・`CamperFrameMeter`。delegate は弱い参照なので場面が持つ）
        let meter = CamperFrameMeter("CamperExteriorFrame")
        context.coordinator.frameMeter = meter
        view.delegate = meter
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        // 炎の揺らぎ（SCNAction）は「動いている」ので、rendersContinuously が false のままでも描き直される。
        // 2026-10-19（Mac run 547）: 揺らし始めた時に rendersContinuously と毎秒の枚数を切り替えていたら、夜に替えた直後の
        // 数枚が描き直されず、昼の絵のまま止まって見えた（画面写真 95b）。描き方の設定は切り替えない
        context.coordinator.onReady = { marker in
            // 画面の更新の外で知らせる
            DispatchQueue.main.async { onReady(marker) }
        }
        context.coordinator.timeScale = timeScale
        context.coordinator.setAngle(angle, animated: false)
        context.coordinator.setDoor(open: doorOpen, animated: false)
        context.coordinator.setFlicker(allowed: !reduceMotion)
        context.coordinator.show(config)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        CamperRenderMark.measure("CamperExteriorUpdate") {
            let c = context.coordinator
            c.show(config)
            c.setAngle(angle, animated: animateAngle && !reduceMotion)
            c.setDoor(open: doorOpen, animated: !reduceMotion)
            c.setFlicker(allowed: !reduceMotion)
        }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: CamperScene) {
        coordinator.cancel()
    }
}

/// 車の絵を写し取る（2026-10-21 確かめ役: 「中に入る」の最後に、部屋が組み上がるまで暗い画面が 1 秒ほど出た。
/// 寄った口の絵を部屋の画面の覆いに使い、組み上がったらなだらかに消す）
@MainActor
final class CamperSceneSnapshot {
    weak var view: SCNView?
    /// 最後に写した絵（部屋の画面が開いた時に読む。画面の状態を通さず、同じ入れ物を渡す——Mac run 642 で、
    /// 夜の 1 回目は状態を通した絵が部屋の画面に届かず、暗い画面が出た）
    private(set) var last: UIImage?

    @discardableResult
    func capture() -> UIImage? {
        guard let view, view.bounds.width > 0 else {
            last = nil
            return nil
        }
        // 2026-10-21（Mac run 642・644）: 夜は SCNView の snapshot() が空の絵を返し、部屋の画面に何も重ならなかった（昼は写った）。
        // 写った絵がほぼ透明か真っ黒なら、画面に出ている層をそのまま写す（drawHierarchy）
        let shot = view.snapshot()
        if Self.looksEmpty(shot) {
            let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
            let drawn = renderer.image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) }
            last = Self.looksEmpty(drawn) ? nil : drawn
        } else {
            last = shot
        }
        return last
    }

    /// 絵がほぼ透明・真っ黒、または入室時の覆いとして暗すぎる絵か（8×8 に縮めて不透明さと明るさの平均を見る）。
    /// 夜の SCNView snapshot は「空ではないが画面を覆うには暗い」絵を返すことがある。
    /// そのまま使うと部屋の最初のフレームが出るまで画面全体が黒く見えるため、暖色のフォールバックへ切り替える。
    static func looksEmpty(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        var px = [UInt8](repeating: 0, count: 8 * 8 * 4)
        guard let ctx = CGContext(data: &px, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        var alpha = 0.0, light = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            alpha += Double(px[i + 3])
            light += Double(px[i]) + Double(px[i + 1]) + Double(px[i + 2])
        }
        return alpha / 64 < 128 || light / (64 * 3) < 24
    }

    func clear() { last = nil }
}
