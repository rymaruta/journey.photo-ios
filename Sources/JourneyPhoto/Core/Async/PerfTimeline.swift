import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// 札 #594「アプリ全体を軽くする」の**下調べの記録**（2026-11-13 判断）。どの画面のどの操作が重いかを、
/// UI テスト（`PerformanceTests.testUsageSurveyProbe`）が段ごとに数で並べられるようにする。**測るだけで動作は変えない**。
///
/// `PerfRecorder` の値（`perf.probe`）は起動の切り分け用で、停止は長い順の 12 件・積みの見本は**最初の** 16 件しか残らない。
/// 起動の後に流す操作（ホームを送る・写真を開く・マイページ・地図・DM・投稿）の分は枠が尽きて取れない。
/// そこで別の見えない要素 `perf.timeline`（`PerfProbeOverlay`）に、**時刻つきの通しの記録**を出す。
/// UI テストは段の始めと終わりに `t=` を読み、その間の分だけを数える（段の考えはアプリに持たせない）:
///
/// - `st=`: 100ms を超えた停止の**全部**（`始め:長さ`・ms）。始めは `CADisplayLink.timestamp`（前の刻み）から取る。
///   `PerfRecorder` の `stalls=` は「刻みが届いた時刻 − 長さ」なので、届くのが遅れた分だけ後ろにずれる（2026-11-13・
///   perf1219 の探すの回で、停止どうしが重なって見えた）。こちらは刻みの時刻どうしなので重ならない
/// - `mem=`: アプリの使うメモリ（`phys_footprint`・MB）を 1 秒ごと（`時刻:MB`）
/// - `cnt=`: 画面ごとの `body` の評価回数（通しの累計・`名前:回数`）。`PerfRecorder.bodyHit`・`hit` の分も入る
/// - `rs=`: 止まっている最中の主スレッドの積みの見本の**新しい方から** 12 件（`PerfMainSampler` が撮った分）
///
/// **UI テストのときだけ有効**（`PerfRecorder.shared.isEnabled`＝ `-JPPreviewPerfProbe YES`・Debug のみ）。無効なら全部の口が何もしない
final class PerfTimeline: @unchecked Sendable {

    static let shared = PerfTimeline(enabled: PerfRecorder.shared.isEnabled, origin: PerfRecorder.shared.origin)

    /// 停止の一覧の上限（5 分の試験で溢れない数。溢れた数は `+Ndropped`）
    static let stallCap = 600
    /// メモリの記録の上限と間隔（秒）
    static let memoryCap = 600
    static let memoryInterval: TimeInterval = 1
    /// 積みの見本（新しい方から残す）の数と、1 件の段の数・1 段の字数
    static let sampleCap = 12
    static let sampleFrameCap = 6
    static let frameCharCap = 100
    /// `body` を数える名前の上限
    static let countKeyCap = 48

    struct Stall: Equatable {
        let startMs: Int
        let gapMs: Int
    }

    struct MemoryPoint: Equatable {
        let ms: Int
        let mb: Int
    }

    let isEnabled: Bool
    private let clock: () -> TimeInterval
    /// 0ms の時刻（`PerfRecorder` と同じ起点にして、`ev=` と突き合わせられるようにする）
    private let origin: TimeInterval
    /// メモリを読む口（試験で差し替える）。読めなければ nil
    private let footprint: () -> Int?
    private let lock = NSLock()
    private var meter = StallMeter()
    private var stalls: [Stall] = []
    private var droppedStalls = 0
    private var memory: [MemoryPoint] = []
    private var lastMemoryAt: TimeInterval?
    private var counts: [String: Int] = [:]
    private var recentSamples: [PerfSample] = []

    /// - Parameters:
    ///   - origin: 0ms とする時刻（`clock` と同じ時計・秒）
    ///   - clock: 秒を返す時計。`CADisplayLink.timestamp` と同じ時計（起動からの秒）
    ///   - footprint: アプリの使うメモリ（byte）
    init(enabled: Bool, origin: TimeInterval,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         footprint: @escaping () -> Int? = PerfTimeline.physFootprint) {
        self.isEnabled = enabled
        self.origin = origin
        self.clock = clock
        self.footprint = footprint
    }

    private func ms(_ time: TimeInterval) -> Int {
        Int(((time - origin) * 1000).rounded())
    }

    // MARK: - 刻み

    /// 画面の表示の刻み（`CADisplayLink.timestamp`・秒）。停止と、1 秒ごとのメモリを残す
    func recordFrame(at timestamp: TimeInterval) {
        guard isEnabled else { return }
        let now = clock()
        lock.lock()
        let previous = meter.lastTimestamp
        if let gapMs = meter.ingest(timestamp), let previous {
            if stalls.count < Self.stallCap {
                stalls.append(Stall(startMs: ms(previous), gapMs: gapMs))
            } else {
                droppedStalls += 1
            }
        }
        let due = lastMemoryAt.map { now - $0 >= Self.memoryInterval } ?? true
        if due { lastMemoryAt = now }
        lock.unlock()
        // メモリを読むのは鍵の外（読む口は系統を呼ぶ）
        guard due, let bytes = footprint() else { return }
        let point = MemoryPoint(ms: ms(now), mb: Int((Double(bytes) / 1_048_576).rounded()))
        lock.lock()
        if memory.count < Self.memoryCap { memory.append(point) }
        lock.unlock()
    }

    /// 裏に入った・戻った。その間の空きを停止に数えない
    func resetFrames() {
        guard isEnabled else { return }
        lock.lock()
        meter.reset()
        lock.unlock()
    }

    // MARK: - body の回数

    /// `body` を 1 回評価した（`let _ = PerfTimeline.shared.count("body.map")`）。名前は `PerfRecorder` の `hit` と同じ形
    func count(_ name: @autoclosure () -> String) {
        guard isEnabled else { return }
        let key = name()
        lock.lock()
        defer { lock.unlock() }
        guard counts[key] != nil || counts.count < Self.countKeyCap else { return }
        counts[key, default: 0] += 1
    }

    // MARK: - 積みの見本

    /// 止まっている最中の積み（浅い方から）。新しい方から `sampleCap` 件だけ残す。段は浅い方の 2 段と、このアプリの段
    func recordSample(frames: [String]) {
        guard isEnabled else { return }
        let now = clock()
        let head = frames.prefix(2)
        let app = frames.dropFirst(2).filter { $0.hasPrefix("JourneyPhoto") }
        let kept = Array((Array(head) + app).prefix(Self.sampleFrameCap)).map { String($0.prefix(Self.frameCharCap)) }
        lock.lock()
        defer { lock.unlock() }
        recentSamples.append(PerfSample(ms: ms(now), frames: kept))
        if recentSamples.count > Self.sampleCap { recentSamples.removeFirst(recentSamples.count - Self.sampleCap) }
    }

    // MARK: - 出力

    /// 見えない要素 `perf.timeline` の値。**形を変えるときは `PerfTimelineTests` と UI テストの `PerfTimelineReading` も合わせる**:
    ///
    ///     t=12345 | st=[2604:424,5434:227] | mem=[1000:85,2000:120] | cnt=[body.home:14,body.map:3] | rs=[+18322 A`a^B`b;+19022 …]
    func summary() -> String {
        let now = ms(clock())
        lock.lock()
        defer { lock.unlock() }
        var st = stalls.map { "\($0.startMs):\($0.gapMs)" }
        if droppedStalls > 0 { st.append("+\(droppedStalls)dropped") }
        let mem = memory.map { "\($0.ms):\($0.mb)" }
        let cnt = counts.keys.sorted().map { "\($0):\(counts[$0] ?? 0)" }
        let rs = recentSamples.map { sample in
            "+\(sample.ms) " + sample.frames.map(Self.clean).joined(separator: "^")
        }
        return "t=\(now)"
            + " | st=[\(st.joined(separator: ","))]"
            + " | mem=[\(mem.joined(separator: ","))]"
            + " | cnt=[\(cnt.joined(separator: ","))]"
            + " | rs=[\(rs.joined(separator: ";"))]"
    }

    /// 区切りの字（`;` `^` `|` `[` `]`）を値に入れない
    private static func clean(_ frame: String) -> String {
        String(frame.map { ";^|[]".contains($0) ? "_" : $0 })
    }

    // MARK: - メモリ

    /// アプリの使うメモリ（`task_vm_info.phys_footprint`・Xcode のメモリの数と同じもの）。iOS 以外は nil
    static func physFootprint() -> Int? {
        #if os(iOS)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint)
        #else
        return nil
        #endif
    }
}
