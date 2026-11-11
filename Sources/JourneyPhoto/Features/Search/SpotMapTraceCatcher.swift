#if os(iOS)
import UIKit
#endif
import SwiftUI

/// 地図をなぞる長押しを受ける見えない部品（探すの撮影スポットの段の地図・`SpotMapTrace`）。
///
/// 指は受けない——枠の大きさと位置を測るためだけに置き、長押しの認識は**いちばん近い縦の送り（`UIScrollView`）**に付ける
/// （プロフィールの横の払い `ProfileSwipeCatcher` と同じ作り）。長押しは 0.25 秒・動き 10pt まで。それより前に動いた指は
/// 失敗し、画面のスクロールへ渡る（run 1022 の数・`SpotMapTrace` の注記）。始まったあとは同じ見えない部品の座標で点を渡す。
/// UIKit の部分は iOS だけ。Linux の型検査では何も置かない
struct SpotMapTraceCatcher: View {

    /// 長押しの長さ（秒）
    var delay: Double
    /// 長押しに届いた・動いた（地図の枠の座標）
    var onChange: (CGPoint, _ began: Bool) -> Void
    /// 離した（地図の枠の座標）
    var onEnd: (CGPoint) -> Void
    /// 取り消された（スクロール・電話・画面を離れた）
    var onCancel: () -> Void

    var body: some View {
        #if os(iOS)
        SpotMapTraceHost(handlers: self)
        #else
        Color.clear
        #endif
    }
}

#if os(iOS)
/// `SpotMapTraceCatcher` の UIKit の部分（`isUserInteractionEnabled = false` の見えない UIView）
struct SpotMapTraceHost: UIViewRepresentable {

    let handlers: SpotMapTraceCatcher

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

        var handlers: SpotMapTraceCatcher?
        private weak var probe: UIView?
        private weak var host: UIScrollView?
        private lazy var press: UILongPressGestureRecognizer = {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            press.allowableMovement = 10
            press.delegate = self
            return press
        }()

        /// いちばん近い祖先の `UIScrollView`（縦の送り）に長押しを付ける
        func attach(to probe: UIView) {
            self.probe = probe
            press.minimumPressDuration = handlers?.delay ?? 0.25
            guard probe.window != nil else { detach(); return }
            var view = probe.superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            guard let scroll = view as? UIScrollView else { detach(); return }
            guard scroll !== host || press.view !== scroll else { return }
            detach()
            scroll.addGestureRecognizer(press)
            host = scroll
        }

        /// 外す。**なぞっている途中なら取り消しとして終える**（画面を離れたときに塗りを残さない）
        func detach() {
            if press.state == .began || press.state == .changed { handlers?.onCancel() }
            press.view?.removeGestureRecognizer(press)
            host = nil
        }

        @objc private func handle(_ press: UILongPressGestureRecognizer) {
            guard let probe, let handlers else { return }
            let point = press.location(in: probe)
            switch press.state {
            case .began: handlers.onChange(point, true)
            case .changed: handlers.onChange(point, false)
            case .ended: handlers.onEnd(point)
            case .cancelled, .failed: handlers.onCancel()
            default: break
            }
        }

        /// この部品（地図）の枠の中で始まった指だけ
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === press, let probe, probe.window != nil else { return false }
            return probe.bounds.contains(touch.location(in: probe))
        }
    }
}
#endif
