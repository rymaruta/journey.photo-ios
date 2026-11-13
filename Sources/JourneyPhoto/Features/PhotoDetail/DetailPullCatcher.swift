import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 写真を下に引いている量の箱（札 #592・`PhotoDetailPull`）。
///
/// **画面の `@State` の値に置かない**（`ProfileTabDrag` と同じ形）。指が動くたびに写真の詳細の `body` ぜんぶ
/// （題・撮影情報・コメント…）が作り直される（2026-11-12 確かめ役がつまむ値で見つけたのと同じ）。
/// 画面は箱の参照だけを持ち、描き直すのは見張る小さな子（`DetailPullFollow`）だけ
final class PhotoDetailPullDrag: ObservableObject {
    /// 指の動いた量（pt）。引いていないときは 0
    @Published var translation: CGSize = .zero
    /// 戻ると決めて閉じている最中（閉じる動きの間に、もう一度つかませない）
    var closing = false
}

/// 引いている量に合わせて動く小さな子。**中身は親が作った値で受け取る**（作り方の関数で受けると、
/// ここが描き直すたびに説明・コメントの段を作り直す・`ProfileTabDragOffset` と同じ）
struct DetailPullFollow<Content: View>: View {

    enum Part {
        /// 写真: 指に付いて動き、縮み、角が丸まる
        case photo
        /// 写真の下（説明・コメント・入力欄）: 薄れて消える
        case rest
    }

    @ObservedObject var drag: PhotoDetailPullDrag
    let part: Part
    let reduceMotion: Bool
    let content: Content

    var body: some View {
        let dx = Double(drag.translation.width), dy = Double(drag.translation.height)
        switch part {
        case .photo:
            let shift = PhotoDetailPull.offset(dx: dx, dy: dy)
            content
                .clipShape(RoundedRectangle(cornerRadius: PhotoDetailPull.rounds(dy: dy) ? JPRadius.l : 0))
                .scaleEffect(PhotoDetailPull.scale(dy: dy, reduceMotion: reduceMotion))
                .offset(x: shift.x, y: shift.y)
        case .rest:
            content.opacity(PhotoDetailPull.restOpacity(dy: dy))
        }
    }
}

/// 写真の詳細の縦の送り（`UIScrollView`）に、**下へ引くパンを1本足す**見えない部品（札 #592）。
/// 指は受けない——枠（写真）の大きさと位置を測るためだけに置く。
///
/// **2026-11-13 判断（作り方）: SwiftUI の `DragGesture` ではなく UIKit のパンを縦の送りに付ける。**
/// 2026-10-28 にマイページの払い（`ProfileTabSwipe` の注記）で、縦の `ScrollView` の中で `simultaneousGesture` の
/// `DragGesture` を使うと、実機では送りのパン（UIKit）が先に始まった指で SwiftUI の払いが取り消され、`onEnded` が
/// 呼ばれずに終わったと確かめてある。`gesture` に替えると今度は縦の送りと写真を押す操作を奪う。同じ作りにして:
/// - 写真の枠の中で始まった1本の指だけを見る（2本指のつまむと地図 `PinchToMapHero` には関わらない）
/// - 縦の送りは**こちらが「始めない」と決まってから動く**（`shouldBeRequiredToFailBy`）。上に居ない・上へ払う・
///   横に払う（束の写真の送り・端からの戻る）指は、こちらが始めずに今までどおり下の部品へ渡る
/// - 始まったら写真を押す操作は取り消される（引いて離した指で大きく見る画面が開かない）。送りも動かない
///   （上の端で伸びて戻る動きが写真の動きと二重にならない）
///
/// `ProfileSwipeCatcher` を使い回さないのは、あちらが横の量だけを渡し・横に流れる列の上を除く作りだから
/// （ここは縦の量と速さ・送りの上端が要り、束の写真＝横に流れる列の上でも引けないといけない）。
/// マイページの払いに手を入れずに済むよう、別の部品にした
struct DetailPullCatcher: View {

    var isEnabled: Bool
    /// 動き始めの横・縦の量と、送りが上に居るか
    var shouldBegin: (Double, Double, Bool) -> Bool
    /// 動いている間（横・縦の量）
    var onChange: (Double, Double) -> Void
    /// 離した（縦の量・縦の速さ）。取り消し（2本目の指・電話・画面を離れた）は `onCancel`
    var onEnd: (Double, Double) -> Void
    var onCancel: () -> Void

    var body: some View {
        #if os(iOS)
        DetailPullPanHost(handlers: self)
        #else
        Color.clear
        #endif
    }
}

#if os(iOS)
/// `DetailPullCatcher` の UIKit の部分（`isUserInteractionEnabled = false` の見えない UIView）
struct DetailPullPanHost: UIViewRepresentable {

    let handlers: DetailPullCatcher

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

    /// 窓に載った・外れたときに、パンを付け替える
    final class Probe: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var handlers: DetailPullCatcher?
        private weak var probe: UIView?
        private weak var host: UIScrollView?
        private lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            // 2本目の指も数える（1 にすると2本目を数えず、引いている途中のつまみを見分けられない）。
            // 始めるのは1本のときだけ（`gestureRecognizerShouldBegin`）・途中で2本になったら取り消す（`handle`）
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            return pan
        }()

        /// いちばん近い祖先の `UIScrollView`（写真の詳細の縦の送り）にパンを付ける。
        /// 束の写真（`TabView` の横の送り）の中に置かないので、祖先の最初の送りが縦の送りになる
        func attach(to probe: UIView) {
            self.probe = probe
            guard probe.window != nil else { detach(); return }
            var view = probe.superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            guard let scroll = view as? UIScrollView else { detach(); return }
            guard scroll !== host || pan.view !== scroll else { return }
            detach()
            scroll.addGestureRecognizer(pan)
            host = scroll
        }

        /// 外す。**引いている途中なら取り消しとして終える**（画面を離れたときにずらしを残さない）
        func detach() {
            if pan.state == .began || pan.state == .changed { handlers?.onCancel() }
            pan.view?.removeGestureRecognizer(pan)
            host = nil
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            guard let handlers else { return }
            // 量と速さは窓の向きで取る（写真の枠は指に付いて動き・縮むので、枠の向きで取ると量が狂う）
            let move = pan.translation(in: nil)
            switch pan.state {
            case .began, .changed:
                // 引いている途中で2本目の指が来たら（つまみ始め）取り消す。止めて付け直すと `.cancelled` が来る
                guard pan.numberOfTouches <= 1 else {
                    pan.isEnabled = false
                    pan.isEnabled = true
                    return
                }
                handlers.onChange(Double(move.x), Double(move.y))
            case .ended:
                handlers.onEnd(Double(move.y), Double(pan.velocity(in: nil).y))
            case .cancelled, .failed:
                handlers.onCancel()
            default:
                break
            }
        }

        /// 写真の枠の中で始まった指だけ（説明・コメントの上の指には関わらない）
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === pan, let probe, probe.window != nil, handlers?.isEnabled == true else {
                return false
            }
            return probe.bounds.contains(touch.location(in: probe))
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan, let handlers, let host else { return true }
            guard handlers.isEnabled, pan.numberOfTouches <= 1 else { return false }
            var move = pan.translation(in: nil)
            if move == .zero { move = pan.velocity(in: nil) }
            let atTop = PhotoDetailPull.isAtTop(offsetY: Double(host.contentOffset.y),
                                                insetTop: Double(host.adjustedContentInset.top))
            return handlers.shouldBegin(Double(move.x), Double(move.y), atTop)
        }

        /// 縦の送りは、こちらが「始めない」と決まってから（上へ払う指は送りへ・下へ引く指はこちらへ）
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === pan && otherGestureRecognizer === host?.panGestureRecognizer
        }
    }
}
#endif
