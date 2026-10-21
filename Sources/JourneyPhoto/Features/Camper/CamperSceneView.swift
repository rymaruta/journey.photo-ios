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
    /// 動きの長さの倍率（見本の起動で「中に入る」をゆっくり撮るときだけ 1 より大きい）
    var timeScale = 1.0
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
