import SwiftUI
#if os(iOS)
import UIKit
#endif

/// ホームの写真の札を **0.35 秒押さえて手に取る** UIKit の長押し（2026-11-12・`PhotoLift.GestureStyle.pressCatcher`）。
///
/// 縦の送りの `UIScrollView` に `UILongPressGestureRecognizer` を1本足し、この部品の枠（札）の中で始まった指だけを見る
/// （横の払い `ProfileSwipeCatcher` と同じ付け方）。押さえている間に 10pt 以上動けば長押しは成り立たず、スクロールのパンが
/// そのまま送る。成り立ったら指を離すまで位置を知らせ続ける（UIKit の長押しは始まった後も `.changed` で動きを知らせる）。
/// 取り消し（着信・裏に回る・札が消える）は必ず `.cancelled` で来るので、手に取ったままにならない。
/// 見えない部品で、指は受けない（枠の大きさと位置を測るためだけに置く）。Linux の型検査では何も置かない
struct PhotoLiftPressCatcher: View {

    /// 手に取った（画面の座標の指の位置）
    var onBegan: (CGPoint) -> Void
    /// 手に取ったまま動いた（画面の座標）
    var onChanged: (CGPoint) -> Void
    /// 離した
    var onEnded: () -> Void
    /// 取り消された（手に取った後だけ）
    var onCancelled: () -> Void

    var body: some View {
        #if os(iOS)
        PhotoLiftPressHost(handlers: self)
        #else
        Color.clear
        #endif
    }
}

#if os(iOS)
/// `PhotoLiftPressCatcher` の UIKit の部分（`isUserInteractionEnabled = false` の見えない UIView）
struct PhotoLiftPressHost: UIViewRepresentable {

    let handlers: PhotoLiftPressCatcher

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.backgroundColor = .clear
        probe.isUserInteractionEnabled = false
        probe.coordinator = context.coordinator
        context.coordinator.handlers = handlers
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        context.coordinator.handlers = handlers
        context.coordinator.attach(to: probe)
    }

    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// 窓に載った・外れたときに、長押しを付け替える
    final class Probe: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var handlers: PhotoLiftPressCatcher?
        private weak var probe: UIView?
        private weak var host: UIScrollView?
        private lazy var press: UILongPressGestureRecognizer = {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            press.minimumPressDuration = PhotoLift.pressSeconds
            press.allowableMovement = CGFloat(PhotoLift.moveTolerance)
            press.numberOfTouchesRequired = 1
            press.name = "photoLift"
            press.delegate = self
            return press
        }()

        /// いちばん近い祖先の `UIScrollView`（縦の送り）に長押しを付ける
        func attach(to probe: UIView) {
            self.probe = probe
            guard probe.window != nil else { detach(); return }
            var view = probe.superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            guard let scroll = view as? UIScrollView else { detach(); return }
            guard scroll !== host || press.view !== scroll else { return }
            detach()
            scroll.addGestureRecognizer(press)
            host = scroll
        }

        /// 外す。**手に取っている途中なら取り消しとして終える**（札が一覧から消えたときに手に取ったままにしない）
        func detach() {
            if press.state == .began || press.state == .changed { handlers?.onCancelled() }
            press.view?.removeGestureRecognizer(press)
            host = nil
        }

        @objc private func handle(_ press: UILongPressGestureRecognizer) {
            guard let handlers else { return }
            // 窓の座標＝SwiftUI の `.global`（ホームは全画面の窓）
            let point = press.location(in: nil)
            switch press.state {
            case .began: handlers.onBegan(point)
            case .changed: handlers.onChanged(point)
            case .ended: handlers.onEnded()
            case .cancelled, .failed: handlers.onCancelled()
            default: break
            }
        }

        /// この部品の枠（札）の中で始まった指だけ
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === press, let probe, probe.window != nil else { return false }
            return probe.bounds.contains(touch.location(in: probe))
        }
    }
}
#endif
