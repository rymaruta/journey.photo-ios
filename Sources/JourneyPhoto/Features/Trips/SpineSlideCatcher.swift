import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 浮いている背（`SpineSlideCatcher` が書き、背の枠 `BookSpineSlot` だけが見張る）。
/// **棚の `@State` に置かない**——ずらすたびに棚ぜんぶを作り直さない（`BookSpineHider` と同じ考え・2026-11-24 の軽くした開閉）
@MainActor
final class SpineLifter: ObservableObject {
    @Published private(set) var liftedId: String?
    /// ずらして別の背に替わった回数（軽い振動の合図・`SpineSlideFeedback`）
    @Published private(set) var switches = 0

    func lift(_ id: String?) {
        if liftedId != id { liftedId = id }
    }

    func switched() { switches &+= 1 }
}

/// ずらして替わった時の軽い振動（2026-11-25 判断・案 3）。見張るのはこの小さな子だけ
struct SpineSlideFeedback: View {
    @ObservedObject var lifter: SpineLifter

    var body: some View {
        Color.clear
            .sensoryFeedback(.selection, trigger: lifter.switches)
            .accessibilityHidden(true)
    }
}

/// 1段の背の上の指を受ける見えない部品（2026-11-25 判断・人間工学の案 3・決まりは `TripBookshelf` の「押して・ずらして・離して」）。
///
/// 縦の送り（`UIScrollView`）に UIKit の指を2本足す（`DetailPullCatcher`・`ProfileSwipeCatcher` と同じ形。枠の中で始まった指だけ）:
/// - **押さえる**（`UILongPressGestureRecognizer`・`holdSeconds`・動いてよいのは `holdSlop`）: 背が浮き、ずらすと替わり、離すと開く。
///   押さえている間は縦の送りと札の横の払いを止める（同じ縦の送りに付いたパンは、こちらが「始めない」と決まってから動く）
/// - **すぐ押して離す**（`UITapGestureRecognizer`・押さえるが始まらなかった時だけ）: 押した背が開く
///
/// 長押しのメニュー（表紙だけ見る）は SwiftUI の `contextMenu` のまま。メニューが出ると指が取り消されるので、何も開かない
struct SpineSlideCatcher: View {
    /// 段の背ごとの押せる幅（左から・`TripBookshelf.hitWidth`）
    var slots: [Double]
    /// 押さえていられるか（本が開く・閉じる動きの最中は受けない）
    var isEnabled: Bool
    /// 浮いている背が替わった（nil は外した・離した）
    var onLift: (Int?) -> Void
    /// ずらして別の背に替わった（軽い振動）
    var onSwitch: () -> Void
    /// 開く（すぐ押して離した・押さえて離した）
    var onOpen: (Int) -> Void

    var body: some View {
        #if os(iOS)
        SpineSlideHost(handlers: self)
        #else
        Color.clear
        #endif
    }
}

#if os(iOS)
struct SpineSlideHost: UIViewRepresentable {

    let handlers: SpineSlideCatcher

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

    final class Probe: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var handlers: SpineSlideCatcher?
        private weak var probe: UIView?
        private weak var host: UIScrollView?
        private var slide = TripBookshelf.Slide(start: nil)
        /// 押さえ始めた所（縦にどれだけ動いたかを見る）
        private var holdStart: CGPoint = .zero

        private lazy var hold: UILongPressGestureRecognizer = {
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
            hold.minimumPressDuration = TripBookshelf.holdSeconds
            hold.allowableMovement = CGFloat(TripBookshelf.holdSlop)
            // SwiftUI の中身（長押しのメニュー）への指は止めない
            hold.cancelsTouchesInView = false
            hold.delegate = self
            return hold
        }()

        private lazy var tap: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            // 押さえるが始まらなかった時だけ（押さえて離した指を、もう1回の「押した」に数えない）
            tap.require(toFail: hold)
            return tap
        }()

        /// いちばん近い祖先の `UIScrollView`（マイページ・人のページの縦の送り）に付ける
        func attach(to probe: UIView) {
            self.probe = probe
            guard probe.window != nil else { detach(); return }
            var view = probe.superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            guard let scroll = view as? UIScrollView else { detach(); return }
            guard scroll !== host || hold.view !== scroll else { return }
            detach()
            scroll.addGestureRecognizer(hold)
            scroll.addGestureRecognizer(tap)
            host = scroll
        }

        func detach() {
            if hold.state == .began || hold.state == .changed { handlers?.onLift(nil) }
            hold.view?.removeGestureRecognizer(hold)
            tap.view?.removeGestureRecognizer(tap)
            host = nil
        }

        private func target(_ recognizer: UIGestureRecognizer) -> Int? {
            guard let probe, let handlers else { return nil }
            let point = recognizer.location(in: probe)
            return TripBookshelf.slideTarget(x: Double(point.x), y: Double(point.y),
                                             height: Double(probe.bounds.height), slots: handlers.slots)
        }

        @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
            guard let handlers else { return }
            switch recognizer.state {
            case .began:
                holdStart = recognizer.location(in: nil)
                slide = TripBookshelf.Slide(start: target(recognizer))
                handlers.onLift(slide.lifted)
            case .changed:
                // 縦に大きく動いた: ずらすのをやめて縦の送りに渡す（取り消すと `.cancelled` が来る）
                if TripBookshelf.handsToScroll(dy: Double(recognizer.location(in: nil).y - holdStart.y)) {
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                    return
                }
                if slide.move(to: target(recognizer)) { handlers.onSwitch() }
                handlers.onLift(slide.lifted)
            case .ended:
                let opens = slide.opens
                slide = TripBookshelf.Slide(start: nil)
                handlers.onLift(nil)
                if let opens { handlers.onOpen(opens) }
            case .cancelled, .failed:
                // 長押しのメニューが出た・電話が来た: 何も開かない
                slide = TripBookshelf.Slide(start: nil)
                handlers.onLift(nil)
            default:
                break
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let handlers, let index = target(recognizer) else { return }
            handlers.onOpen(index)
        }

        /// この段の枠の中で始まった指だけ（ほかの段・年の見出し・札の行には関わらない）
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === hold || gestureRecognizer === tap,
                  let probe, probe.window != nil, handlers?.isEnabled == true else { return false }
            // 流れている送りの上の一押しは、送りを止めるだけ（本を開かない）
            guard TripBookshelf.receivesTouch(scrollDecelerating: host?.isDecelerating == true) else { return false }
            return probe.bounds.contains(touch.location(in: probe))
        }

        /// 長押しのメニュー（SwiftUI）とは同時に動いてよい。メニューが出たら、こちらは取り消される
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === hold || gestureRecognizer === tap else { return false }
            // 縦の送りとは同時に動く（押さえたあと縦に大きく動かせば送れる・`handsToScroll`）。
            // 札の横の払い（同じ縦の送りに付いたほかのパン）とは同時に動かない
            if other === host?.panGestureRecognizer { return true }
            return !(other is UIPanGestureRecognizer && other.view === host)
        }

        /// 札の横の払いは、押さえるが「始まらない」と決まってから（ずらしている指で札が替わらない。押してすぐ払った指は 10pt 動いた所で渡す）。
        /// 縦の送りは待たせない（2026-11-25 確かめ役の指摘: 背の上に指を置いてから縦に送れなかった）
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            gestureRecognizer === hold && other is UIPanGestureRecognizer && other.view === host
                && other !== host?.panGestureRecognizer
        }
    }
}
#endif
