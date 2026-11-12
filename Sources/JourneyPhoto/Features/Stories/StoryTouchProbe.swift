#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass
#endif
import SwiftUI

/// ストーリー作成で、**指（合成された指を含む）がどの窓・どの部品に届いたか**を記録する見えない部品
/// （UI テストのときだけ・`-JPPreviewStoryProbe YES`・`StoryComposeProbe` の出来事に足す）。
///
/// 2026-11-12 判断: 1.1.82 の統合の枝の Mac（run 1124）で `StoryPlaceMoveTests` の運びが 6 回に 1 回だけ空振りし、
/// その回は `ov.begin` も `photo.begin` も記録に無かった（札にも写真にも指が届いていない）。どこで指が止まったかを
/// 推定でなく数で見るため、場面のすべての窓に「認識しない（見るだけ）」の認識器を付け、指の始まり・終わりの
/// 座標・届いた窓・当たった部品の型を `touch.began` / `touch.ended` として残す。
/// ふつうの起動（記録が無効）では何も置かない。指の配り方は変えない（取り消さない・遅らせない・同時に認める）
struct StoryTouchProbe: View {
    var body: some View {
        #if os(iOS)
        StoryTouchProbeHost()
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        #else
        Color.clear.frame(width: 1, height: 1)
        #endif
    }
}

#if os(iOS)
private struct StoryTouchProbeHost: UIViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.isUserInteractionEnabled = false
        anchor.backgroundColor = .clear
        anchor.coordinator = context.coordinator
        return anchor
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        context.coordinator.attach(near: anchor)
    }

    static func dismantleUIView(_ anchor: Anchor, coordinator: Coordinator) {
        coordinator.detachAll()
    }

    final class Anchor: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(near: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var watchers: [Watcher] = []
        private var timer: Timer?

        /// 同じ場面のすべての窓に付ける。キーボード・アラートの窓は後から出るので 0.5 秒ごとに付け直す
        func attach(near anchor: UIView) {
            guard let scene = anchor.window?.windowScene else { return }
            attachAll(in: scene)
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak scene] _ in
                    MainActor.assumeIsolated {
                        guard let self, let scene else { return }
                        self.attachAll(in: scene)
                    }
                }
            }
        }

        private func attachAll(in scene: UIWindowScene) {
            watchers.removeAll { $0.view == nil }
            for window in scene.windows where !watchers.contains(where: { $0.view === window }) {
                let watcher = Watcher(target: nil, action: nil)
                watcher.cancelsTouchesInView = false
                watcher.delaysTouchesBegan = false
                watcher.delaysTouchesEnded = false
                watcher.delegate = self
                window.addGestureRecognizer(watcher)
                watchers.append(watcher)
            }
        }

        func detachAll() {
            timer?.invalidate()
            timer = nil
            for watcher in watchers { watcher.view?.removeGestureRecognizer(watcher) }
            watchers.removeAll()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    /// 認識しない（見るだけ）の認識器。始まり・終わりの座標と、届いた窓・当たった部品の型を記録に足す
    final class Watcher: UIGestureRecognizer {
        private var start: CGPoint = .zero

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            guard let touch = touches.first, let window = view as? UIWindow else { return }
            start = touch.location(in: nil)
            let hit = window.hitTest(touch.location(in: window), with: event)
            let chain = Self.chain(hit)
            let touched = touch.view.map { String(describing: type(of: $0)) } ?? "nil"
            MainActor.assumeIsolated {
                StoryComposeProbe.shared.note("touch.began",
                                              "x=\(Int(start.x)) y=\(Int(start.y)) win=\(String(describing: type(of: window)))"
                                              + " lvl=\(Int(window.windowLevel.rawValue)) touchView=\(touched) hit=\(chain)")
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesEnded(touches, with: event)
            note("touch.ended", touches)
            state = .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesCancelled(touches, with: event)
            note("touch.cancelled", touches)
            state = .failed
        }

        private func note(_ name: String, _ touches: Set<UITouch>) {
            guard let touch = touches.first else { return }
            let end = touch.location(in: nil)
            MainActor.assumeIsolated {
                StoryComposeProbe.shared.note(name, "x=\(Int(end.x)) y=\(Int(end.y)) dx=\(Int(end.x - start.x)) dy=\(Int(end.y - start.y))")
            }
        }

        /// 当たった部品から上へ 4 段の型（SwiftUI の中は型の名前が長いので頭 28 字まで）
        private static func chain(_ view: UIView?) -> String {
            var names: [String] = []
            var current = view
            while let v = current, names.count < 4 {
                names.append(String(String(describing: type(of: v)).prefix(28)))
                current = v.superview
            }
            return names.isEmpty ? "nil" : names.joined(separator: "<")
        }
    }
}
#endif
