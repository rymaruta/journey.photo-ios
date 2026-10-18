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
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        context.coordinator.onReady = { marker in
            // 画面の更新の外で知らせる
            DispatchQueue.main.async { onReady(marker) }
        }
        context.coordinator.setAngle(angle, animated: false)
        context.coordinator.setDoor(open: doorOpen, animated: false)
        context.coordinator.show(config)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        c.show(config)
        c.setAngle(angle, animated: animateAngle && !reduceMotion)
        c.setDoor(open: doorOpen, animated: !reduceMotion)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: CamperScene) {
        coordinator.cancel()
    }
}
