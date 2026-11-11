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
            // 読み上げと UI テストの木から外す（run 1049: 外さないと行ごとに同じ識別子の「Other」が1つずつ増え、
            // `tripPlan.dragHandle` が 5 行で 10 個になって、3 番目に別の行を拾っていた）
            .background(TripRowDragHost(events: events, preview: AnyView(preview())).accessibilityHidden(true))
            .accessibilityDragPoint(.center, description: Text(label))
        #else
        self
        #endif
    }
}

#if os(iOS)
/// 行の後ろに置く見えない部品。いちばん近い祖先の `UIScrollView` に付いた**1つの** `UIDragInteraction`
/// （`TripRowDragHub`）に自分の行を登録し、**この行の枠の中で始まった指だけ**持ち上げる
/// （行の上の SwiftUI の押す・送るはそのまま届く。`.draggable` も祖先の部品に付けて同じことをしている）
struct TripRowDragHost: UIViewRepresentable {
    let events: TripRowDragEvents
    let preview: AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.backgroundColor = .clear
        probe.isUserInteractionEnabled = false
        probe.isAccessibilityElement = false
        probe.accessibilityElementsHidden = true
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

    /// 窓に載った・外れたときに、登録し直す
    final class Probe: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: self)
        }
    }

    /// 1 行分の受け手（中身・絵・始まりと終わりの知らせ）。運ぶ働きそのものは `TripRowDragHub` が持つ
    @MainActor
    final class Coordinator {
        var events: TripRowDragEvents?
        var preview: AnyView?
        private(set) weak var probe: UIView?
        private weak var hub: TripRowDragHub?

        /// いちばん近い祖先の `UIScrollView`（無ければ窓）の運ぶ働きに登録する
        func attach(to probe: UIView) {
            self.probe = probe
            guard let window = probe.window else { detach(); return }
            var view = probe.superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            let next = TripRowDragHub.hub(for: view ?? window)
            guard next !== hub else { return }
            detach()
            next.add(self)
            hub = next
        }

        func detach() {
            hub?.remove(self)
            hub = nil
        }

        /// 指がこの行の枠の中か
        func contains(_ session: UIDragSession) -> Bool {
            guard let probe, probe.window != nil else { return false }
            return probe.bounds.contains(session.location(in: probe))
        }

        func items() -> [UIDragItem] {
            guard let events else { return [] }
            let item = UIDragItem(itemProvider: NSItemProvider(object: events.payload as NSString))
            item.localObject = events.payload
            return [item]
        }

        /// 持ち上げ・運ぶ間の絵は、`.draggable` の preview と同じ SwiftUI の絵（名前の札）
        func liftPreview() -> UITargetedDragPreview? {
            guard let probe, probe.window != nil, let preview else { return nil }
            let renderer = ImageRenderer(content: preview)
            renderer.scale = probe.window?.screen.scale ?? 3
            guard let image = renderer.uiImage else { TripRowDragHub.note("P:nil"); return nil }
            TripRowDragHub.note("P:ok")
            let view = UIImageView(image: image)
            view.frame = CGRect(origin: .zero, size: image.size)
            let parameters = UIDragPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(roundedRect: view.bounds, cornerRadius: JPRadius.field)
            let target = UIDragPreviewTarget(container: probe, center: CGPoint(x: probe.bounds.midX, y: probe.bounds.midY))
            return UITargetedDragPreview(view: view, parameters: parameters, target: target)
        }
    }
}

/// 1 つの `UIScrollView` に**1 つだけ**付ける運ぶ働き。行（`TripRowDragHost.Coordinator`）はここに登録する。
///
/// 2026-11-11 判断（run 1053 の数）: 行ごとに `UIDragInteraction` を同じ `UIScrollView` に付けると、自分の行の
/// `itemsForBeginning`（I:in）・絵（P:ok）・持ち上げの始まり（W）までは来るが、そのあとほかの行の働きにも
/// `itemsForBeginning` が呼ばれ（空を返す）、`sessionWillBegin` も取り消し（C）も終わり（X）も来ないまま、
/// 9 起動 + Days の 2 回すべてで運べなかった。働きを 1 つにして、指の下の行を自分で選ぶ
@MainActor
final class TripRowDragHub: NSObject, UIDragInteractionDelegate {
    private static let key = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    /// その部品の働き（無ければ作って付ける）
    static func hub(for view: UIView) -> TripRowDragHub {
        if let hub = objc_getAssociatedObject(view, key) as? TripRowDragHub { return hub }
        let hub = TripRowDragHub(view: view)
        objc_setAssociatedObject(view, key, hub, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return hub
    }

    private weak var view: UIView?
    private var rows: [ObjectIdentifier: Row] = [:]
    /// いま運んでいる行
    private weak var active: TripRowDragHost.Coordinator?
    private var running = false
    private lazy var interaction: UIDragInteraction = {
        let interaction = UIDragInteraction(delegate: self)
        // iPhone の既定は「切」（`isEnabledByDefault` が false）。`.draggable` と同じく入れる
        interaction.isEnabled = true
        return interaction
    }()

    private struct Row { weak var coordinator: TripRowDragHost.Coordinator? }

    private init(view: UIView) {
        self.view = view
        super.init()
        view.addInteraction(interaction)
        Self.note("A:\(String(describing: type(of: view)))")
    }

    func add(_ row: TripRowDragHost.Coordinator) {
        rows[ObjectIdentifier(row)] = Row(coordinator: row)
    }

    /// 外す。**運んでいる途中の行なら、終わったとして知らせる**（落とす先の印を残さない）
    func remove(_ row: TripRowDragHost.Coordinator) {
        rows[ObjectIdentifier(row)] = nil
        if active === row {
            if running { row.events?.ended() }
            active = nil
            running = false
        }
    }

    /// 見本のときだけ、運ぶ元の出来事を並びに残す（札 #521）
    static func note(_ event: String) {
        #if DEBUG
        if TripPlanFixture.isOn { TripPlanFixtureCounter.shared.mark(event) }
        #endif
    }

    /// 指の下の行だけ運ぶ
    func dragInteraction(_ interaction: UIDragInteraction,
                         itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        let row = rows.values.compactMap(\.coordinator).first { $0.contains(session) }
        guard let row else { Self.note("I:out"); return [] }
        Self.note("I:in")
        active = row
        return row.items()
    }

    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem,
                         session: UIDragSession) -> UITargetedDragPreview? {
        active?.liftPreview()
    }

    func dragInteraction(_ interaction: UIDragInteraction, willAnimateLiftWith animator: UIDragAnimating,
                         session: UIDragSession) {
        Self.note("W")
    }

    func dragInteraction(_ interaction: UIDragInteraction, item: UIDragItem,
                         willAnimateCancelWith animator: UIDragAnimating) {
        Self.note("C")
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
        running = true
        active?.events?.began()
    }

    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession,
                         willEndWith operation: UIDropOperation) {
        Self.note("Y\(operation.rawValue)")
    }

    /// **運ぶ操作が終わった。落とした・落とさなかったに関わらず必ず来る**（2026-11-11 判断・落とす先の印を空に戻す）
    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession,
                         didEndWith operation: UIDropOperation) {
        running = false
        active?.events?.ended()
        active = nil
    }
}
#endif
