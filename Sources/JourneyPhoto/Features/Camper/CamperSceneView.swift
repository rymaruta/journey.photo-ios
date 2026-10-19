import SwiftUI
import UIKit
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif

/// 車を描く SCNView（指の動きは SwiftUI の側が受けて、向きの値で渡す）
struct CamperSceneView: UIViewRepresentable {
    let config: CamperConfig
    let angle: CamperAngle
    let animateAngle: Bool
    let doorOpen: Bool
    let reduceMotion: Bool
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
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        // 炎が揺れている間だけ描き続ける（毎秒 30 で足りる。止まっている間は動いた時だけ描く）
        context.coordinator.onFlickerChange = { [weak view] on in
            view?.rendersContinuously = on
            view?.preferredFramesPerSecond = on ? 30 : 60
        }
        context.coordinator.onReady = { marker in
            // 画面の更新の外で知らせる
            DispatchQueue.main.async { onReady(marker) }
        }
        context.coordinator.setAngle(angle, animated: false)
        context.coordinator.setDoor(open: doorOpen, animated: false)
        context.coordinator.setFlicker(allowed: !reduceMotion)
        context.coordinator.show(config)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        c.show(config)
        c.setAngle(angle, animated: animateAngle && !reduceMotion)
        c.setDoor(open: doorOpen, animated: !reduceMotion)
        c.setFlicker(allowed: !reduceMotion)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: CamperScene) {
        coordinator.cancel()
    }
}
