import Foundation

/// 札 #435（起動直後に操作が効かない／ホームに戻される）と #429（アプリの重さ）の**原因を数で取る記録**
/// （2026-11-04 判断）。
///
/// **UI テストのときだけ有効**（`-JPPreviewPerfProbe YES`・Debug のみ・`PreviewSession.perfProbe`）。
/// 無効のときは何も記録せず、アプリの動作は変えない。直しではなく、直す前に値を取るための仕組み。
///
/// 記録するもの（すべて起動からの経過 ms。起動 = `JourneyPhotoApp.init` で `markLaunch` した時点）:
/// - `sel`: `RootView` の `selection`（下のタブ）を書いた全箇所の「どこで・何から何へ」
/// - `task`: 起動後の `.task(id: auth.state)` の始めと終わり
/// - `stall`: メインスレッドの停止（画面の表示の刻み `CADisplayLink` の間隔が 100ms を超えた回数・最大の間隔）
/// - `body`: ホーム・マイページ・写真詳細の `body` を評価した回数
///
/// 見えない要素 `perf.probe`（`PerfProbeOverlay`）の `accessibilityValue` に `summary()` を出し、
/// UI テストが読む（`UITests/.../PerfProbeSupport.swift`・失敗したときは添付に残す）
final class PerfRecorder: @unchecked Sendable {

    /// 本番（と UI テスト）で使う1つ。無効なら全部の口が何もしない
    static let shared = PerfRecorder(enabled: PreviewSession.perfProbe)

    /// body の評価を数える画面
    enum BodyScreen: String, CaseIterable, Sendable {
        case home
        case myPage
        case photoDetail
    }

    struct SelectionEntry: Equatable, Sendable {
        let ms: Int
        let site: String
        let from: String
        let to: String
    }

    struct TaskSpan: Equatable, Sendable {
        let name: String
        let startMs: Int
        var endMs: Int?
    }

    /// 履歴の上限（暴走しても見えない要素の値を膨らませない）
    static let selectionCap = 200
    static let taskCap = 50

    let isEnabled: Bool
    private let clock: () -> TimeInterval
    private let origin: TimeInterval
    private let lock = NSLock()
    private var selections: [SelectionEntry] = []
    private var droppedSelections = 0
    private var tasks: [TaskSpan] = []
    private var bodyCounts: [BodyScreen: Int] = [:]
    private var stall = StallMeter()

    /// - Parameter clock: 秒を返す時計（試験で差し替える）。作った時点を 0ms とする
    init(enabled: Bool, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.isEnabled = enabled
        self.clock = clock
        self.origin = clock()
    }

    /// 起動の0ms をここに合わせる（`JourneyPhotoApp.init`）。`shared` を作るだけ
    func markLaunch() {}

    private func elapsedMs() -> Int {
        Int(((clock() - origin) * 1000).rounded())
    }

    // MARK: - selection

    /// 下のタブを書いた。`site` は書いた場所の名前（`RootView.select(_:at:)` の呼び出し元）
    func recordSelection<T>(site: String, from: T, to: T) {
        guard isEnabled else { return }
        let now = elapsedMs()
        let entry = SelectionEntry(ms: now, site: site, from: "\(from)", to: "\(to)")
        lock.lock()
        defer { lock.unlock() }
        if selections.count < Self.selectionCap {
            selections.append(entry)
        } else {
            droppedSelections += 1
        }
    }

    // MARK: - task

    /// `.task` の始め。返す番号を `endTask` に渡す（無効のときは -1）
    @discardableResult
    func beginTask(_ name: String) -> Int {
        guard isEnabled else { return -1 }
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        guard tasks.count < Self.taskCap else { return -1 }
        tasks.append(TaskSpan(name: name, startMs: now, endMs: nil))
        return tasks.count - 1
    }

    func endTask(_ index: Int) {
        guard isEnabled, index >= 0 else { return }
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        guard tasks.indices.contains(index) else { return }
        tasks[index].endMs = now
    }

    // MARK: - stall

    /// 画面の表示の刻み（`CADisplayLink.timestamp`・秒）。前の刻みとの間隔を測る
    func recordFrame(at timestamp: TimeInterval) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        stall.ingest(timestamp)
    }

    /// 裏に入った・戻った。**その間の空きを停止に数えない**
    func resetFrames() {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        stall.reset()
    }

    // MARK: - body

    /// `body` を1回評価した。**評価ごとに1足す**（`let _ = PerfRecorder.shared.bodyHit(.home)`）
    func bodyHit(_ screen: BodyScreen) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        bodyCounts[screen, default: 0] += 1
    }

    func bodyCount(_ screen: BodyScreen) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return bodyCounts[screen] ?? 0
    }

    // MARK: - 出力

    /// 見えない要素の値。**形を変えるときは `PerfProbeTests` も合わせる**:
    ///
    ///     sel=[+120ms home>search@tabs.set;…] | task=[#0 auth.state 80-310ms;…] | stall=2/180ms/540f | body=home:12,myPage:3,photoDetail:0 | t=1234ms
    func summary() -> String {
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        var sel = selections.map { "+\($0.ms)ms \($0.from)>\($0.to)@\($0.site)" }
        if droppedSelections > 0 { sel.append("+\(droppedSelections)dropped") }
        var task: [String] = []
        for (index, span) in tasks.enumerated() {
            let end: String
            if let endMs = span.endMs { end = "\(endMs)ms" } else { end = "…" }
            task.append("#\(index) \(span.name) \(span.startMs)-\(end)")
        }
        let body = BodyScreen.allCases.map { "\($0.rawValue):\(bodyCounts[$0] ?? 0)" }
        return "sel=[\(sel.joined(separator: ";"))]"
            + " | task=[\(task.joined(separator: ";"))]"
            + " | stall=\(stall.count)/\(stall.maxMs)ms/\(stall.frames)f"
            + " | body=\(body.joined(separator: ","))"
            + " | t=\(now)ms"
    }
}

/// メインスレッドの停止の数え方（画面の表示の刻みの間隔が閾値を超えた回数・最大の間隔）。
/// 刻みを渡すだけの純粋な型にして、Linux の試験でも確かめる
struct StallMeter: Equatable {
    /// これを超える間隔を「停止」と数える（ミリ秒）。60Hz の1コマは約 16.7ms
    var thresholdMs: Double = 100
    private(set) var lastTimestamp: TimeInterval?
    /// 間隔が閾値を超えた回数
    private(set) var count = 0
    /// 最も長かった間隔（ミリ秒）
    private(set) var maxMs = 0
    /// 間隔を測った回数
    private(set) var frames = 0

    mutating func ingest(_ timestamp: TimeInterval) {
        defer { lastTimestamp = timestamp }
        guard let last = lastTimestamp else { return }
        let gapMs = (timestamp - last) * 1000
        frames += 1
        maxMs = max(maxMs, Int(gapMs.rounded()))
        if gapMs > thresholdMs { count += 1 }
    }

    /// 次の刻みを「最初の1回」にする（裏から戻った直後の長い空きを数えない）
    mutating func reset() {
        lastTimestamp = nil
    }
}
