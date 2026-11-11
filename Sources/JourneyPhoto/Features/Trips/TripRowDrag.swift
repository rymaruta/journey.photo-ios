import SwiftUI
#if os(iOS)
import UIKit
#endif

// 旅行プランの日程で、行を押さえて運ぶ元（札 #521）。
//
// **2026-11-11 判断（運ぶ元を SwiftUI の `.draggable` から UIKit の `UIDragInteraction` に替えた）**:
// `.draggable` で運ぶと、運ぶ操作が落とさずに終わったとき（持ち上がったが落ちない (b)）に、落とす先の
// `isTargeted` が偽に戻らず、真鍮の落とす先の線が残った（Mac run 1036: 速く運んだ 8 回中 1 回、離して 5 秒後も
// `tripPlan.dropLine` が 1 本）。`.draggable` と `.dropDestination` には「運ぶ操作が終わった」知らせが無い
// （持ち上がった絵が消える時点は、23 回中 22 回で離す前に来ていて、終わりの合図に使えない）。
// `UIDragInteraction` の `dragInteraction(_:session:didEndWith:)` は、落とした・落とさなかったに関わらず
// 必ず来るので、そこで落とす先の印を空に戻す。(b) そのもの（OS の側で落とさずに終わる）は原因の行が言えないので直さない。
// 持ち上げの時間・振動・運ぶ間の絵・行き先（`.dropDestination` はそのまま）・置く・断るは今までと同じに動かす。

/// 落とす先の印（真鍮の 2pt の線）をどこに出すか。**運ぶ操作が終わったら必ず空**（2026-11-11 判断）
struct TripDropMark<Spot: Equatable>: Equatable {
    private(set) var spot: Spot?

    init() {}

    /// 落とす先の `isTargeted` の知らせ。外れた知らせは、その先を出しているときだけ消す
    /// （次の先に入った知らせが、前の先から出た知らせより先に来ることがある）
    mutating func targeted(_ on: Bool, _ target: Spot) {
        if on { spot = target } else if spot == target { spot = nil }
    }

    /// 落とした（`drop` が呼ばれた）
    mutating func dropped() { spot = nil }

    /// 運ぶ操作が終わった（`UIDragInteraction` の `didEndWith`）。落とさずに終わって外れた知らせが来なくても空に戻す
    mutating func dragEnded() { spot = nil }
}

/// 行を運ぶ元の知らせ。UIKit の受け手（`TripRowDragHost.Coordinator`）から呼ぶ。Linux でも単体テストで叩ける形に分けた
final class TripRowDragEvents {
    /// 運ぶ中身（`TripPlanEdit.dragPayload`）
    let payload: String
    private let onBegin: () -> Void
    private let onEnd: () -> Void

    init(payload: String, onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.payload = payload
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    /// 持ち上がった（`sessionWillBegin`）
    func began() { onBegin() }

    /// 運ぶ操作が終わった（`didEndWith`・落とした／落とさなかった／部品が外れた）
    func ended() { onEnd() }
}

extension View {
    /// 行を押さえて運ぶ元にする（2026-11-11 判断・上の注記）。押すと開く・押さえて運ぶは今までどおり。
    /// 読み上げの人には、運ぶ始まりの点（`accessibilityDragPoint`）を行の真ん中に置く
    @ViewBuilder
    func tripRowDragSource<Preview: View>(_ events: TripRowDragEvents, label: String,
                                          @ViewBuilder preview: () -> Preview) -> some View {
        #if os(iOS)
        self
            .background(TripRowDragHost(events: events, preview: AnyView(preview())))
            .accessibilityDragPoint(.center, description: Text(label))
        #else
        self
        #endif
    }
}

#if os(iOS)
/// 行の後ろに置く見えない部品。いちばん近い祖先の `UIScrollView` に `UIDragInteraction` を付け、
/// **この行の枠の中で始まった指だけ**持ち上げる（行の上の SwiftUI の押す・送るはそのまま届く。
/// `.draggable` も祖先の部品に付けて同じことをしている）
struct TripRowDragHost: UIViewRepresentable {
    let events: TripRowDragEvents
    let preview: AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.backgroundColor = .clear
        probe.isUserInteractionEnabled = false
        probe.coordinator = context.coordinator
        context.coordinator.events = events
        context.coordinator.preview = preview
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        context.coordinator.events = events
        context.coordinator.preview = preview
        context.coordinator.attach(to: probe)
    }

    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// 窓に載った・外れたときに、運ぶ働きを付け替える
    final class Probe: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIDragInteractionDelegate {
        var events: TripRowDragEvents?
        var preview: AnyView?
        private weak var probe: UIView?
        private weak var host: UIView?
        /// 運んでいる途中か（途中で部品が外れたら、終わったとして知らせる）
        private var active = false
        private lazy var interaction: UIDragInteraction = {
            let interaction = UIDragInteraction(delegate: self)
            // iPhone の既定は「切」（`isEnabledByDefault` が false）。`.draggable` と同じく入れる
            interaction.isEnabled = true
            return interaction
        }()

        /// いちばん近い祖先の `UIScrollView`（無ければ窓）に付ける
        func attach(to probe: UIView) {
            self.probe = probe
            guard let window = probe.window else { detach(); return }
            var view = probe.superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            let target: UIView = view ?? window
            guard target !== host || interaction.view !== target else { return }
            detach()
            target.addInteraction(interaction)
            host = target
        }

        func detach() {
            if active {
                active = false
                events?.ended()
            }
            interaction.view?.removeInteraction(interaction)
            host = nil
        }

        /// この行の枠の中で始まった指だけ運ぶ（ほかの行の働きも同じ祖先に付いている）
        func dragInteraction(_ interaction: UIDragInteraction,
                             itemsForBeginning session: UIDragSession) -> [UIDragItem] {
            guard let probe, probe.window != nil, let events else { return [] }
            guard probe.bounds.contains(session.location(in: probe)) else { return [] }
            let item = UIDragItem(itemProvider: NSItemProvider(object: events.payload as NSString))
            item.localObject = events.payload
            return [item]
        }

        /// 持ち上げ・運ぶ間の絵は、`.draggable` の preview と同じ SwiftUI の絵（名前の札）
        func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem,
                             session: UIDragSession) -> UITargetedDragPreview? {
            guard let probe, probe.window != nil else { return nil }
            let center = CGPoint(x: probe.bounds.midX, y: probe.bounds.midY)
            let target = UIDragPreviewTarget(container: probe, center: center)
            let parameters = UIDragPreviewParameters()
            parameters.backgroundColor = .clear
            guard let preview else { return nil }
            let renderer = ImageRenderer(content: preview)
            renderer.scale = probe.window?.screen.scale ?? 3
            guard let image = renderer.uiImage else { return nil }
            let view = UIImageView(image: image)
            view.frame = CGRect(origin: .zero, size: image.size)
            parameters.visiblePath = UIBezierPath(roundedRect: view.bounds, cornerRadius: JPRadius.field)
            return UITargetedDragPreview(view: view, parameters: parameters, target: target)
        }

        func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
            active = true
            events?.began()
        }

        /// **運ぶ操作が終わった。落とした・落とさなかったに関わらず必ず来る**（2026-11-11 判断・落とす先の印を空に戻す）
        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession,
                             didEndWith operation: UIDropOperation) {
            active = false
            events?.ended()
        }
    }
}
#endif
