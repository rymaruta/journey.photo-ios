import SwiftUI
#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass
#endif

/// **UI テストの事実取りだけ**: 指が触れている間、その指を受けている UIKit の指の操作（スクロールのパン・SwiftUI の身振り・
/// 横の払いのパンなど）の状態を記録し、見えない要素 `gesture.spy` に出す（`-JPPreviewGestureSpy YES`・Debug のみ）。
///
/// 2026-11-12 判断: run 1182 で、ホームの写真の札に「手に取って運ぶ」の身振りがあると、写真の上から縦に送っても一覧が
/// まったく動かなかった（切り替えの y=406 のまま。身振りを外すと 406 → 168）。推定で直さず、**どの指の操作が始まり、
/// スクロールのパンがどうなったか**を数で取る。窓に「何もしない」指の操作を1つ足し、触れた指の `gestureRecognizers` を読む。
/// 足す操作は触れを取り消さず・遅らせず・ほかと同時に受け、指を離したら自分は失敗で終わる（画面の動きを変えない）
enum GestureSpy {

    static let identifier = "gesture.spy"

    /// 記録（最後の数回の指）。主スレッドだけで読み書きする
    @MainActor static var lines: [String] = []

    @MainActor static func append(_ line: String) {
        lines.append(line)
        if lines.count > 60 { lines.removeFirst(lines.count - 60) }
    }

    /// 状態を1文字で（P=待ち・B=始まった・C=変わった・E=終わった・X=取り消し・F=失敗）
    static func letter(_ raw: Int) -> String {
        switch raw {
        case 0: return "P"
        case 1: return "B"
        case 2: return "C"
        case 3: return "E"
        case 4: return "X"
        case 5: return "F"
        default: return "?"
        }
    }
}

/// `gesture.spy` を出す見えない部品（RootView に重ねる）。0.3 秒ごとに読み直す
struct GestureSpyOverlay: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3)) { _ in
            Text(" ")
                .font(.system(size: 1))
                .accessibilityLabel("gesture spy")
                .accessibilityValue(GestureSpy.lines.joined(separator: " | "))
                .accessibilityIdentifier(GestureSpy.identifier)
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .background {
            #if os(iOS)
            GestureSpyHost()
            #endif
        }
    }
}

#if os(iOS)
/// 窓に記録の指の操作を足す（見えない UIView・指は受けない）
struct GestureSpyHost: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        private let spy = GestureSpyRecognizer()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            spy.view?.removeGestureRecognizer(spy)
            window?.addGestureRecognizer(spy)
        }
    }
}

/// 触れた指を受けている指の操作の状態を記録する（自分は何も認めない）
final class GestureSpyRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {

    private var start: CGPoint = .zero
    private var startTime: TimeInterval = 0
    private var lastSignature = ""

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        start = touch.location(in: nil)
        startTime = touch.timestamp
        lastSignature = ""
        record("began", touch, full: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        record("moved", touch, full: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { record("ended", touch, full: false) }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { record("cancelled", touch, full: false) }
        state = .failed
    }

    /// 状態が変わったときだけ1行（`full` は始まりの1行で、指の操作の名前を全部書く）
    private func record(_ phase: String, _ touch: UITouch, full: Bool) {
        let others = (touch.gestureRecognizers ?? []).filter { $0 !== self }
        let signature = others.enumerated().map { "\($0.offset)\(GestureSpy.letter($0.element.state.rawValue))" }
            .joined(separator: ",")
        guard full || signature != lastSignature || phase != "moved" else { return }
        lastSignature = signature
        let point = touch.location(in: nil)
        let head = String(format: "%@ t=%.2f dy=%.0f dx=%.0f y=%.0f", phase, touch.timestamp - startTime,
                          point.y - start.y, point.x - start.x, start.y)
        let body: String
        if full {
            body = others.enumerated().map { index, recognizer in
                "\(index):\(Self.name(recognizer))=\(GestureSpy.letter(recognizer.state.rawValue))"
                    + (recognizer.isEnabled ? "" : "(off)")
            }.joined(separator: " ")
        } else {
            body = signature
        }
        let line = "[\(head)] \(body)"
        MainActor.assumeIsolated { GestureSpy.append(line) }
    }

    /// 指の操作の名前。縦の送りのパンは `scrollPan`（どの UIScrollView か・送れるか）と書く
    static func name(_ recognizer: UIGestureRecognizer) -> String {
        if let scroll = recognizer.view as? UIScrollView, recognizer === scroll.panGestureRecognizer {
            let size = scroll.contentSize
            return "scrollPan<\(type(of: scroll)) \(Int(size.width))x\(Int(size.height)) "
                + "on=\(scroll.isScrollEnabled)>"
        }
        let kind = String(describing: type(of: recognizer))
        let view = recognizer.view.map { String(describing: type(of: $0)) } ?? "-"
        let label = recognizer.name.map { "#\($0)" } ?? ""
        return "\(kind)\(label)@\(view.prefix(40))"
    }
}
#endif
