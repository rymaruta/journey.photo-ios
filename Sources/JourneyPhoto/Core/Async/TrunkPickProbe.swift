import Foundation

/// 札 #424「旅のトランクの中身を押しても持ち上がらない回がある」の**原因を数で取る記録**（2026-11-07 判断）。
///
/// **UI テストのときだけ有効**（`-JPPreviewPerfProbe YES`・Debug のみ・`PreviewSession.perfProbe`）。
/// 無効のときは何も記録せず、画面の見た目と動きは変えない。直すためではなく、直す前に値を取るための仕組み。
///
/// 候補は3つ（`TrunkOpenView`）:
/// - A: 舞台の祖先の引く指（`LidDragPriority` の `DragGesture`）が、中のボタンの押しを奪う
/// - B: `dragStart` が残る・`lidSettled` が false のまま（引く指が取り消され `onEnded` が来ない）→ 押せない姿のまま
/// - C: `held` が取り残される（`allowsHitTesting(held == nil)`）
///
/// 見えない要素 `trunk.open.debug` の `accessibilityValue` に `summary(_:)` を出し、UI テストが読む。
/// 記録するもの（時刻は最初に触れた時点からの ms）:
/// - 引く指: `onChanged` の回数・`onEnded` の回数・最後の `onChanged` の時刻と座標
/// - 押し: `pick`（`Button` の押しの入口）の回数・最後の時刻
/// - 出来事の履歴（`ev`・新しい12件）: `+時刻 種類`
final class TrunkPickProbe: @unchecked Sendable {

    static let shared = TrunkPickProbe(enabled: PreviewSession.perfProbe)

    /// 画面の今の状態（`TrunkOpenView` の `body` が評価のたびに渡す）
    struct Snapshot: Equatable, Sendable {
        var flat: Bool
        var lidSettled: Bool
        var dragStartSet: Bool
        var held: String
        var p: Double
        var overflows: Bool
        var k: Double
    }

    static let eventCap = 12

    let isEnabled: Bool
    private let clock: () -> TimeInterval
    private let origin: TimeInterval
    private let lock = NSLock()
    private var dragChanged = 0
    private var dragEnded = 0
    private var dragIgnoredHeld = 0
    private var pickCount = 0
    private var lastChangedMs: Int?
    private var lastEndedMs: Int?
    private var lastPickMs: Int?
    private var lastX = 0.0
    private var lastY = 0.0
    private var events: [String] = []

    init(enabled: Bool, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.isEnabled = enabled
        self.clock = clock
        self.origin = clock()
    }

    private func elapsedMs() -> Int {
        Int(((clock() - origin) * 1000).rounded())
    }

    private func push(_ text: String, at ms: Int) {
        events.append("+\(ms) \(text)")
        if events.count > Self.eventCap { events.removeFirst(events.count - Self.eventCap) }
    }

    /// ふたを引く指の `onChanged`（座標は指の位置）
    func recordDragChanged(x: Double, y: Double) {
        guard isEnabled else { return }
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        dragChanged += 1
        lastChangedMs = now
        lastX = x
        lastY = y
        // 動き続ける間の履歴を埋め尽くさない（続けて来た2回目からは残さない）
        if events.last?.hasSuffix(" changed") != true { push("changed", at: now) }
    }

    /// `onChanged` に来たが `held` があるので無視した
    func recordDragIgnoredByHeld() {
        guard isEnabled else { return }
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        dragIgnoredHeld += 1
        push("ignoredHeld", at: now)
    }

    func recordDragEnded() {
        guard isEnabled else { return }
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        dragEnded += 1
        lastEndedMs = now
        push("ended", at: now)
    }

    /// 中身のボタンの押しが `pick` に届いた
    func recordPick(_ label: String) {
        guard isEnabled else { return }
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        pickCount += 1
        lastPickMs = now
        push("pick:\(label)", at: now)
    }

    /// 開き具合などの節目（ふたの動きの終わり・平らなふたへの差し替え）
    func recordEvent(_ text: String) {
        guard isEnabled else { return }
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        push(text, at: now)
    }

    /// 見えない要素の値。**形を変えるときは `TrunkPickProbeTests` と UI テストの読み方も合わせる**:
    ///
    ///     flat=1 settled=1 dragStart=0 held=none p=1.000 overflows=0 k=1.000 | drag=0/0/0 | pick=1@5230ms | lastDrag=-@-,-  endedAt=- | ev=[+5230 pick:card] | t=9000ms
    func summary(_ s: Snapshot) -> String {
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        func ms(_ value: Int?) -> String { value.map { "\($0)" } ?? "-" }
        let point = lastChangedMs == nil ? "-,-" : "\(Int(lastX.rounded())),\(Int(lastY.rounded()))"
        return "flat=\(s.flat ? 1 : 0) settled=\(s.lidSettled ? 1 : 0) dragStart=\(s.dragStartSet ? 1 : 0)"
            + " held=\(s.held) p=\(String(format: "%.3f", s.p)) overflows=\(s.overflows ? 1 : 0) k=\(String(format: "%.3f", s.k))"
            + " | drag=\(dragChanged)/\(dragEnded)/\(dragIgnoredHeld)"
            + " | pick=\(pickCount)@\(ms(lastPickMs))ms"
            + " | lastDrag=\(ms(lastChangedMs))ms@\(point) endedAt=\(ms(lastEndedMs))ms"
            + " | ev=[\(events.joined(separator: ";"))]"
            + " | t=\(now)ms"
    }

    /// `TrunkHeld` の短い名前（メダルの名前は載せない）
    static func label(_ item: TrunkHeld?) -> String {
        switch item {
        case .none: return "none"
        case .some(.medal): return "medal"
        case .some(.more): return "more"
        case .some(.card): return "card"
        case .some(.tickets): return "tickets"
        }
    }
}
