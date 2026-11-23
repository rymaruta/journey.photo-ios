import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 開いた一冊の日のページを左右でめくる（札 #714・決まりは `TripBookPageFlip`）。
/// 投稿した一冊（`TripBookView`）と端末の一冊（`DeviceTripBookView`）で同じ動き。
///
/// **2026-11-23 判断（確かめ役の指摘）: 指は UIKit のパンで受ける（`TripDayFlipCatcher`）。**
/// SwiftUI の `DragGesture` を `simultaneousGesture` で縦の `ScrollView` に付ける形は、2026-10-28 に実機で
/// 「指を離しても `onEnded` が呼ばれない」と確かめて捨てた形（`ProfileTabSwipe`・`DetailPullCatcher` の注記）。
/// さらに iOS 26 では画面のどこから右へ払っても「戻る」になる。同じ作りにして:
/// - 縦の送りは、こちらが「始めない」と決まってから動く（縦に読む指は今までどおり）
/// - 「戻る」の払い（端からの払い・iOS 26 の画面のどこからでもの払い）も、こちらが「始めない」と決まってから動く。
///   **右へ払って前の日があるときだけ**こちらが受け、1日目と表紙では「戻る」に譲る。左の端から始めた指は必ず「戻る」へ
///
/// めくる見た目は、ページが背（左の辺）を軸に少し回って替わる（`DayTurnFollow`）。`UIPageViewController` の `.pageCurl` は
/// 使わない: 一冊は下へ流れる1本の読み物（表紙・数字・足取り・日の段）で、日ごとの頁に割っていない。`.pageCurl` は頁ごとに
/// 別の画面を要り、一冊を作り直すことになる（札 #714 の「大きく作り直さない」）
struct TripDayFlip: ViewModifier {
    /// 日の見出しの行の id（並びの順。`ForEach` の id と同じもの）
    let dayIDs: [String]

    @StateObject private var model = DayFlipModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            DayTurnFollow(model: model, content: content)
                .environment(\.tripDayFlip, model)
                // UI テストのときだけ: 日めくりの指の記録（`trips.flip.probe`・`DayFlipProbeLog`）
                .overlay(alignment: .topLeading) { DayFlipProbeView(log: model.log) }
                .onAppear {
                    model.dayIDs = dayIDs
                    model.log.note("appear days=\(dayIDs.count) first=\(dayIDs.first ?? "-")")
                    model.reduceMotion = reduceMotion
                    model.scroll = { id in proxy.scrollTo(id, anchor: .top) }
                }
                .onChange(of: dayIDs) { _, ids in model.dayIDs = ids }
                .onChange(of: reduceMotion) { _, reduce in model.reduceMotion = reduce }
        }
    }
}

/// めくる量に合わせて回る小さな子（一冊の `body` は作り直さない・`DetailPullFollow` と同じ形）
struct DayTurnFollow<Content: View>: View {
    @ObservedObject var model: DayFlipModel
    let content: Content

    var body: some View {
        content
            .rotation3DEffect(.degrees(model.turn), axis: (x: 0, y: 1, z: 0),
                              anchor: .leading, perspective: TripBookPageFlip.perspective)
            .opacity(model.fade)
    }
}

/// めくる段取り（指の量・離したとき・読み上げの「次の日」「前の日」）
@MainActor
final class DayFlipModel: ObservableObject {
    /// ページの向き（度・背を軸に）と濃さ
    @Published private(set) var turn: Double = 0
    @Published private(set) var fade: Double = 1

    var dayIDs: [String] = []
    /// 読む線を過ぎた見出し（`tripDayHeader`）。**知らせない**（送るたびに描き直さない）
    var passed: Set<String> = []
    var reduceMotion = false
    var scroll: ((String) -> Void)?
    private var turning = false
    /// UI テストのときだけの記録（`trips.flip.probe`）
    let log = DayFlipProbeLog()

    /// 見出しが読む線を過ぎたか
    func mark(_ id: String, passed isPast: Bool) {
        if isPast { passed.insert(id) } else { passed.remove(id) }
    }

    /// 指を受けるか（動き始めの横・縦の量と、指の始まりの x）
    func begins(dx: Double, dy: Double, startX: Double) -> Bool {
        let direction = turning ? nil
            : TripBookPageFlip.beginDirection(dx: dx, dy: dy, startX: startX, dayIDs: dayIDs, passed: passed)
        log.note("begin dx=\(DayFlipProbeLog.n(dx)) dy=\(DayFlipProbeLog.n(dy)) x0=\(DayFlipProbeLog.n(startX)) "
                 + "now=\(TripBookPageFlip.current(dayIDs: dayIDs, passed: passed)) days=\(dayIDs.count) turning=\(turning) "
                 + "-> \(direction.map { "\($0)" } ?? "no")")
        return direction != nil
    }

    /// 指に付いて少しだけ回る
    func follow(dx: Double, width: Double) {
        guard !turning, !reduceMotion else { return }
        turn = TripBookPageFlip.followAngle(dx: dx, width: width)
    }

    /// 離した。めくると決まればめくり、決まらなければ元へ戻す
    func release(dx: Double, velocityX: Double) {
        log.note("end dx=\(DayFlipProbeLog.n(dx)) vx=\(DayFlipProbeLog.n(velocityX)) "
                 + "commit=\(TripBookPageFlip.commitDirection(dx: dx, velocityX: velocityX).map { "\($0)" } ?? "no")")
        guard !turning else { return }
        if let direction = TripBookPageFlip.commitDirection(dx: dx, velocityX: velocityX), flip(direction) { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { turn = 0; fade = 1 }
    }

    /// 次の日（+1）・前の日（-1）へめくる。行き先が無ければ何もせず偽
    @discardableResult
    func flip(_ direction: Int) -> Bool {
        guard !turning, let id = TripBookPageFlip.targetID(dayIDs: dayIDs, passed: passed, direction: direction) else {
            log.note("flip \(direction) -> none")
            return false
        }
        log.note("flip \(direction) -> \(id) scroll=\(scroll != nil)")
        guard !reduceMotion else {
            scroll?(id)
            turn = 0
            return true
        }
        turning = true
        Task { [weak self] in
            guard let self else { return }
            if direction > 0 {
                // 次の日: 今のページが背を軸に左へめくれて薄れ、下から次の日のページが出る
                withAnimation(.easeIn(duration: TripBookPageFlip.turnOutDuration)) {
                    self.turn = -TripBookPageFlip.turnAngle
                    self.fade = TripBookPageFlip.turnFade
                }
                try? await Task.sleep(nanoseconds: Self.ns(TripBookPageFlip.turnOutDuration))
                self.jump(to: id, turn: 0, fade: TripBookPageFlip.turnFade)
            } else {
                // 前の日: 前の日のページが左から背を軸に戻ってくる
                self.jump(to: id, turn: -TripBookPageFlip.turnAngle, fade: TripBookPageFlip.turnFade)
            }
            withAnimation(.easeOut(duration: TripBookPageFlip.turnInDuration)) {
                self.turn = 0
                self.fade = 1
            }
            try? await Task.sleep(nanoseconds: Self.ns(TripBookPageFlip.turnInDuration))
            self.turning = false
        }
        return true
    }

    /// 動きを付けずにその日の見出しへ移り、向きと濃さを置き直す
    private func jump(to id: String, turn: Double, fade: Double) {
        log.note("jump \(id)")
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scroll?(id)
            self.turn = turn
            self.fade = fade
        }
    }

    private static func ns(_ seconds: Double) -> UInt64 { UInt64(max(0, seconds) * 1_000_000_000) }
}

private struct TripDayFlipKey: EnvironmentKey {
    static let defaultValue: DayFlipModel? = nil
}

extension EnvironmentValues {
    /// 開いた一冊の日めくり（`TripDayFlip` が置く）
    var tripDayFlip: DayFlipModel? {
        get { self[TripDayFlipKey.self] }
        set { self[TripDayFlipKey.self] = newValue }
    }
}

/// 日の見出しの印（`tripDayHeader`）
private struct TripDayHeader: ViewModifier {
    let id: String
    @Environment(\.tripDayFlip) private var flip

    func body(content: Content) -> some View {
        content
            // 見出しが読む線を過ぎたか（めくる起点の「いまの日」）。値は真偽だけなので、送るたびに描き直さない
            .onGeometryChange(for: Bool.self) {
                Double($0.frame(in: .scrollView).minY) <= TripBookPageFlip.readingLine
            } action: { isPast in
                flip?.mark(id, passed: isPast)
            }
            // 読み上げでも日を送れる（見出しは読み上げで止まる要素）
            .accessibilityAction(named: L("次の日", "Next day")) { flip?.flip(1) }
            .accessibilityAction(named: L("前の日", "Previous day")) { flip?.flip(-1) }
    }
}

extension View {
    /// 日の見出しに付ける（いまの日を数える・読み上げの「次の日」「前の日」）
    func tripDayHeader(id: String) -> some View {
        modifier(TripDayHeader(id: id))
    }

    /// 一冊の送りの中身（`ScrollView` の中）に付ける。横の払いを UIKit のパンで受ける（`TripDayFlipCatcher`）
    func tripDayFlipCatcher() -> some View {
        background { TripDayFlipCatcher() }
    }
}

/// 一冊の縦の送り（`UIScrollView`）に、**横に払うパンを1本足す**見えない部品。指は受けない——中身の枠を測るためだけに置く
struct TripDayFlipCatcher: View {
    @Environment(\.tripDayFlip) private var flip

    var body: some View {
        #if os(iOS)
        if let flip {
            TripDayFlipPanHost(model: flip)
        }
        #else
        Color.clear
        #endif
    }
}

#if os(iOS)
/// `TripDayFlipCatcher` の UIKit の部分（`isUserInteractionEnabled = false` の見えない UIView）。作りは `DetailPullPanHost` と同じ
struct TripDayFlipPanHost: UIViewRepresentable {

    let model: DayFlipModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.backgroundColor = .clear
        probe.isUserInteractionEnabled = false
        probe.coordinator = context.coordinator
        context.coordinator.model = model
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        context.coordinator.model = model
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

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        weak var model: DayFlipModel?
        private weak var probe: UIView?
        private weak var host: UIScrollView?
        private lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            return pan
        }()

        /// いちばん近い祖先の `UIScrollView`（一冊の縦の送り）にパンを付ける
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
            model?.log.note("attach \(type(of: scroll))")
        }

        /// 外す。払いの途中なら元へ戻して終える
        func detach() {
            if pan.state == .began || pan.state == .changed {
                model?.release(dx: 0, velocityX: 0)
            }
            pan.view?.removeGestureRecognizer(pan)
            host = nil
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            let move = pan.translation(in: nil)
            let width = Double(host?.bounds.width ?? 390)
            switch pan.state {
            case .began, .changed:
                model?.follow(dx: Double(move.x), width: width)
            case .ended:
                model?.release(dx: Double(move.x), velocityX: Double(pan.velocity(in: nil).x))
            case .cancelled, .failed:
                model?.log.note(pan.state == .cancelled ? "cancelled" : "failed")
                model?.release(dx: 0, velocityX: 0)
            default:
                break
            }
        }

        /// 一冊の中身の枠の中で始まった指だけ
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === pan, let probe, probe.window != nil, model != nil else { return false }
            return probe.bounds.contains(touch.location(in: probe))
        }

        /// 横に払い、その向きにめくる日があるときだけ始める（左の端から・1日目と表紙で右へ払う指は「戻る」へ）
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan else { return true }
            guard pan.numberOfTouches <= 1 else { return false }
            var move = pan.translation(in: nil)
            if move == .zero { move = pan.velocity(in: nil) }
            let startX = Double(pan.location(in: nil).x - pan.translation(in: nil).x)
            return model?.begins(dx: Double(move.x), dy: Double(move.y), startX: startX) ?? false
        }

        /// 縦の送りと「戻る」の払いは、こちらが「始めない」と決まってから
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan else { return false }
            if otherGestureRecognizer === host?.panGestureRecognizer { return true }
            return isNavigationPop(otherGestureRecognizer)
        }

        /// 一冊を閉じる払い。積む画面の「戻る」（端からの払いと、iOS 26 の画面のどこからでもの払い）に加えて、
        /// **本を開く拡大の移り変わり（`TripBookOpening`・`navigationTransition(.zoom)`）の閉じる払い**も含める。
        ///
        /// 2026-11-23 判断（1.2.0 の統合・Mac run 1765 の `testCapturesTripBookOpened`「左へ払っても1日目の見出しが出ない」）:
        /// 前は積む画面（`UINavigationController`）の view に付いた払いだけを待たせていた。一冊は棚から拡大で開くので、
        /// 拡大の閉じる払いは一冊の頁の外側の view（拡大の入れ物・積んだ画面の view）に付き、こちらを待たずに指を取りうる。
        /// **縦の送りの外側（祖先）の view に付いた払いは、どれもこちらが「始めない」と決まってから動かす**。
        /// こちらが始めるのは横に払い、その向きにめくる日があるときだけなので、下へ引いて閉じる・端から戻る指はそのまま届く
        private func isNavigationPop(_ other: UIGestureRecognizer) -> Bool {
            guard other is UIPanGestureRecognizer, let host, let view = other.view, view !== host else { return false }
            return host.isDescendant(of: view)
        }
    }
}
#endif

/// **UI テストの事実取りだけ**: 日めくりの指の始まり・離したとき・めくった先・受けたかを記録し、見えない要素
/// `trips.flip.probe` の値に出す（`-JPPreviewLayoutProbe YES`・Debug のみ・`PreviewSession.layoutProbe`）。
///
/// 2026-11-23（1.2.0 の統合）: `testCapturesTripBookOpened`「左へ払っても1日目の見出しが出ない」を推定で2回直して2回とも外した
/// （run 1765・1769）。決まり（CLAUDE.md「2回外れたら数字を取る」）どおり、次に落ちたら指が届いたか・めくったかを値で分ける。
/// 一冊の `body` を描き直さないよう、記録は日めくりの段取り（`DayFlipModel`）の外の小さな入れ物に持つ。Release では何も記録しない
@MainActor
final class DayFlipProbeLog: ObservableObject {
    /// 残す件数（番号 `#n` は通し）
    static let keep = 12

    let enabled = PreviewSession.layoutProbe
    @Published private(set) var entries: [String] = []
    private var count = 0

    func note(_ text: String) {
        guard enabled else { return }
        count += 1
        entries.append("#\(count) \(text)")
        if entries.count > Self.keep { entries.removeFirst(entries.count - Self.keep) }
    }

    var text: String { entries.joined(separator: " ; ") }

    static func n(_ value: Double) -> String { String(format: "%.1f", value) }
}

/// `trips.flip.probe` の見えない要素
struct DayFlipProbeView: View {
    @ObservedObject var log: DayFlipProbeLog

    var body: some View {
        if log.enabled {
            LayoutProbe(identifier: "trips.flip.probe", value: log.text)
        }
    }
}
