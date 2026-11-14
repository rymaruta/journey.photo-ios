import SwiftUI
#if os(iOS)
import UIKit
import ObjectiveC
#endif

/// シートを**下へ払って閉じようとしたとき**の扱い（2026-11-14 判断・札 #188・点検「直すべき 1」）。
///
/// 🔴 **払って閉じるのを止めるのは、必ずこの部品（`sheetSwipeGuard`）を通す。** 前は 14 か所が
/// `interactiveDismissDisabled` を直に書き、書きかけの投稿・写真の編集を下へ払っても**跳ね返るだけで
/// 何も言わなかった**（左上の「閉じる」まで手を伸ばすしかなかった）。払われたことは SwiftUI だけでは
/// 知れないので、UIKit のシートの知らせ（`presentationControllerDidAttemptToDismiss`）を
/// `SheetSwipeRelay` で受け、**左上の「閉じる」を押したときと同じ確かめ**をそのまま出す。
/// 確かめの中身は今のもの（`unsavedCloseGuard`・投稿の閉じる確認など）——2つ目の確かめは作らない。
///
/// - `.close`: 書きかけが無い。今までどおり払えば閉じる
/// - `.ask`: 書きかけがある。払うと止まり、`onAttempt`（＝左上の「閉じる」と同じ手）を呼ぶ
/// - `.hold`: 送っている最中。払っても閉じない（左上の「閉じる」も押せない間なので、出す確かめが無い）
///
/// **`@MainActor` の型に置かない**（テストから呼べなくなる・`UnsavedLeave` と同じ）。
enum SheetSwipe: Equatable {
    case close
    case ask
    case hold

    /// 送っていない変更があるときの判断（`UnsavedLeave`）から。✕・戻ると同じ判断を使う
    static func from(_ leave: UnsavedLeave) -> SheetSwipe {
        switch leave {
        case .now: return .close
        case .confirm: return .ask
        case .wait: return .hold
        }
    }

    /// 送っている最中だけ止める画面（通報・意見・退会・旅行プランを作るなど。書きかけの確かめが無い）
    static func busy(_ isBusy: Bool) -> SheetSwipe {
        isBusy ? .hold : .close
    }

    /// 払って閉じるのを止めるか（`interactiveDismissDisabled` に渡す値）
    var blocksSwipe: Bool { self != .close }

    /// 1つのシートに部品が重なったとき（シートの中で積んだ画面にも付いている）、払われたらどれが答えるか。
    /// `stack` は窓に載った順（後ろほど手前の画面）。**手前から見て、最初の `.ask` が答える。**
    /// 手前が `.hold`（送っている最中）なら、奥の確かめは出さない（送り終える前に閉じさせない）。
    /// 答える部品が無ければ nil（今までどおり跳ね返るだけ）
    static func responder(in stack: [SheetSwipe]) -> Int? {
        for index in stack.indices.reversed() {
            switch stack[index] {
            case .ask: return index
            case .hold: return nil
            case .close: continue
            }
        }
        return nil
    }
}

extension View {
    /// 下へ払って閉じるのを止め、止めたときは `onAttempt` を呼ぶ（`SheetSwipe` の注記）。
    ///
    /// - `onAttempt`: **左上の「閉じる」（✕・戻る）を押したときと同じ手**を渡す。`.ask` のときだけ呼ぶ
    ///
    /// `ViewModifier` にしないのは `Shims/` の模型が持っていないため（`unsavedCloseGuard` と同じ）。
    func sheetSwipeGuard(_ swipe: SheetSwipe, onAttempt: @escaping () -> Void = {}) -> some View {
        self
            .interactiveDismissDisabled(swipe.blocksSwipe)
            .background { SheetSwipeProbe(swipe: swipe, onAttempt: onAttempt) }
    }
}

/// 払われたことを UIKit から受ける見えない部品（指は奪わない・読み上げない）
struct SheetSwipeProbe: View {
    let swipe: SheetSwipe
    let onAttempt: () -> Void

    var body: some View {
        #if os(iOS)
        SheetSwipeHost(swipe: swipe, onAttempt: onAttempt)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #else
        Color.clear
        #endif
    }
}

#if os(iOS)
/// `SheetSwipeProbe` の UIKit の部分。窓に載ったら、いちばん外の出している画面（シート）の
/// 知らせの受け手に `SheetSwipeRelay` を挟む
struct SheetSwipeHost: UIViewRepresentable {

    let swipe: SheetSwipe
    let onAttempt: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.backgroundColor = .clear
        probe.isUserInteractionEnabled = false
        probe.coordinator = context.coordinator
        context.coordinator.swipe = swipe
        context.coordinator.onAttempt = onAttempt
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        // 書きかけの有無・閉じる手は描き直しのたびに替わる。最新を持つ
        context.coordinator.swipe = swipe
        context.coordinator.onAttempt = onAttempt
        context.coordinator.attach(to: probe)
    }

    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// 窓に載った・外れた（積んだ画面の奥に回った）ときに付け替える
    final class Probe: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: self)
        }
    }

    @MainActor final class Coordinator {
        var swipe: SheetSwipe = .close
        var onAttempt: () -> Void = {}
        private weak var relay: SheetSwipeRelay?

        func attach(to probe: UIView) {
            guard probe.window != nil, let presented = Self.presentedRoot(of: probe),
                  let controller = presented.presentationController else { detach(); return }
            let next = SheetSwipeRelay.install(on: controller)
            if next !== relay { detach() }
            relay = next
            next.add(self)
        }

        func detach() {
            relay?.remove(self)
            relay = nil
        }

        /// 部品の画面から上へたどり、**出している画面（シート）のいちばん外**を返す。シートの中で無ければ nil
        /// （戻るの確かめ `unsavedLeaveGuard` はシートの外でも使う。そのときは何もしない）
        private static func presentedRoot(of view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            while let current = responder, !(current is UIViewController) { responder = current.next }
            guard var controller = responder as? UIViewController else { return nil }
            while let parent = controller.parent { controller = parent }
            return controller.presentingViewController == nil ? nil : controller
        }
    }
}

/// シートの知らせの受け手に挟む中継ぎ。**SwiftUI がもともと持つ受け手（`original`）に全部渡したうえで、**
/// 払って止められた知らせ（`presentationControllerDidAttemptToDismiss`）だけ、手前の部品の `onAttempt` を呼ぶ。
///
/// SwiftUI の受け手を差し替えるだけだと、閉じたときに `isPresented` が戻らない・`interactiveDismissDisabled`
/// が効かなくなるおそれがある。だから知らない口（閉じてよいか・閉じた後など）は `forwardingTarget` で元へ回す。
/// SwiftUI が受け手を付け直したときは、次に部品が窓に載る・描き直すときに挟み直す（`install`）。
/// 挟めなかった回は、今までどおり跳ね返るだけ（悪くはならない）
@MainActor final class SheetSwipeRelay: NSObject, UIAdaptivePresentationControllerDelegate {

    /// SwiftUI がもともと持つ受け手。下の `responds`・`forwardingTarget`（NSObject の口で、主の役者の外の扱い）
    /// からも読むので `nonisolated(unsafe)`。書くのも読むのも UIKit の主スレッドだけ
    nonisolated(unsafe) private weak var original: UIAdaptivePresentationControllerDelegate?
    /// 窓に載った順の部品（弱く持つ）
    private var members: [WeakCoordinator] = []
    /// シートの知らせ口に中継ぎを紐づける鍵（中身は使わない。番地だけ）
    private static let key = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))

    private struct WeakCoordinator {
        weak var value: SheetSwipeHost.Coordinator?
    }

    /// シートに中継ぎを挟む（もう挟んであれば同じものを返す）。中継ぎはシートの知らせ口に紐づけて持つ
    static func install(on controller: UIPresentationController) -> SheetSwipeRelay {
        let relay = (objc_getAssociatedObject(controller, key) as? SheetSwipeRelay) ?? {
            let made = SheetSwipeRelay()
            objc_setAssociatedObject(controller, key, made, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return made
        }()
        if controller.delegate !== relay {
            relay.original = controller.delegate
            controller.delegate = relay
        }
        return relay
    }

    func add(_ coordinator: SheetSwipeHost.Coordinator) {
        members.removeAll { $0.value == nil || $0.value === coordinator }
        members.append(WeakCoordinator(value: coordinator))
    }

    func remove(_ coordinator: SheetSwipeHost.Coordinator) {
        members.removeAll { $0.value == nil || $0.value === coordinator }
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        let alive = members.compactMap(\.value)
        if let index = SheetSwipe.responder(in: alive.map(\.swipe)) {
            alive[index].onAttempt()
        }
        original?.presentationControllerDidAttemptToDismiss?(presentationController)
    }

    // 上で書いていない口（閉じてよいか・閉じる前後・出し方の切り替え）は、元の受け手に回す

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return original?.responds(to: aSelector) ?? false
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) { return original }
        return super.forwardingTarget(for: aSelector)
    }
}
#endif
