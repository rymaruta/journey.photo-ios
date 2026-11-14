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
    /// 積みの見本（新しい方から残す）の数と、1 件の段の数・1 段の字数。
    /// 2026-11-14（run 1231）: 12 件では地図の段（54 回止まる）の前半の見本が残らなかったので 30 件にした。
    /// 段は浅い方の 3 段・その下の**別の画像の最初の段**（MapKit・VectorKit など、誰が呼んだか）4 つ・このアプリの段 3 つ
    static let sampleCap = 30
    static let sampleFrameCap = 10
    static let frameCharCap = 90
    /// `body` を数える名前の上限（`chg.<画面>.<理由>` も数えるので多め・2026-11-14）
    static let countKeyCap = 200
    /// 時間を測る名前の上限
    static let durationKeyCap = 32

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
    /// 名前ごとの 回数・合計・最大（`measure`・2026-11-14）
    private var durations: [String: DurationStat] = [:]
    /// いまの値（`gauge`・2026-11-14。画像の控えの大きさなど）
    private var gauges: [String: Int] = [:]

    /// 回数・合計・最大（ms）
    struct DurationStat: Equatable {
        var count = 0
        var total = 0.0
        var max = 0.0
    }

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
        guard due else { return }
        // 画像の控え（`URLCache.shared`・メモリの分）の大きさも 1 秒ごとに（2026-11-14）
        #if canImport(Darwin)
        let urlCacheKB = URLCache.shared.currentMemoryUsage / 1024
        lock.lock()
        gauges["urlcache.memKB"] = urlCacheKB
        lock.unlock()
        #endif
        guard let bytes = footprint() else { return }
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

    /// 止まっている最中の積み（浅い方から）。新しい方から `sampleCap` 件だけ残す（段の選び方は `pickFrames`）
    func recordSample(frames: [String]) {
        guard isEnabled else { return }
        let now = clock()
        let kept = Self.pickFrames(frames).map { String($0.prefix(Self.frameCharCap)) }
        lock.lock()
        defer { lock.unlock() }
        recentSamples.append(PerfSample(ms: ms(now), frames: kept))
        if recentSamples.count > Self.sampleCap { recentSamples.removeFirst(recentSamples.count - Self.sampleCap) }
    }

    /// 残す段: 浅い方の 3 段・その下で**初めて出てくる画像**の段（下回りの画像は除く）を 4 つ・このアプリの段を 3 つ。
    /// 2026-11-14（run 1231）: 浅い 2 段とアプリの段だけでは、`_os_log_impl_mirror_to_stderr` を誰が呼んだか分からなかった
    static func pickFrames(_ frames: [String]) -> [String] {
        let head = Array(frames.prefix(3))
        let rest = frames.dropFirst(3)
        let plumbing = ["libsystem", "libswiftCore", "libdispatch", "libobjc", "CoreFoundation", "libc++", "dyld",
                        "JourneyPhoto", "AttributeGraph", "SwiftUICore", "SwiftUI`", "UIKitCore", "GraphicsServices"]
        var seen = Set(head.map(image))
        var callers: [String] = []
        for frame in rest where callers.count < 4 {
            let name = image(frame)
            guard !seen.contains(name), !plumbing.contains(where: { frame.hasPrefix($0) }) else { continue }
            seen.insert(name)
            callers.append(frame)
        }
        let app = rest.filter { $0.hasPrefix("JourneyPhoto") && !$0.contains("$main") && !$0.contains("entry_point") }
        return Array((head + callers + app.prefix(3)).prefix(sampleFrameCap))
    }

    /// 段の画像の名前（「画像`名前」の前）
    private static func image(_ frame: String) -> String {
        frame.split(separator: "`", maxSplits: 1).first.map(String.init) ?? frame
    }

    // MARK: - 時間と、いまの値（2026-11-14 札 #594）

    /// 処理の時間を測って名前ごとに足す（`dur=`）。**無効のときは測らずにそのまま返す**
    func measure<T>(_ name: @autoclosure () -> String, _ body: () -> T) -> T {
        guard isEnabled else { return body() }
        let start = clock()
        let result = body()
        let ms = (clock() - start) * 1000
        let key = name()
        lock.lock()
        defer { lock.unlock() }
        guard durations[key] != nil || durations.count < Self.durationKeyCap else { return result }
        var d = durations[key, default: DurationStat()]
        d.count += 1
        d.total += ms
        d.max = Swift.max(d.max, ms)
        durations[key] = d
        return result
    }

    /// いまの値に足す（引くときは負の数・`gauge=`）。無効なら何もしない
    func gauge(_ name: @autoclosure () -> String, add delta: Int) {
        guard isEnabled else { return }
        let key = name()
        lock.lock()
        defer { lock.unlock() }
        gauges[key, default: 0] += delta
    }

    /// いまの値を置き換える
    func gauge(_ name: @autoclosure () -> String, set value: Int) {
        guard isEnabled else { return }
        let key = name()
        lock.lock()
        defer { lock.unlock() }
        gauges[key] = value
    }

    // MARK: - 出力

    /// 見えない要素 `perf.timeline` の値。**形を変えるときは `PerfTimelineTests` と UI テストの `PerfTimelineReading` も合わせる**:
    ///
    ///     t=12345 | st=[2604:424,5434:227] | mem=[1000:85,2000:120] | cnt=[body.home:14,body.map:3] | rs=[+18322 A`a^B`b;+19022 …] | dur=[home.choices:12/340/80] | gauge=[img.decodedKB:51200]
    ///
    /// `dur=` は 名前:回数/合計 ms/最大 ms（整数に丸める）。`gauge=` は名前:いまの値。どちらも名前の順
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
        let dur = durations.keys.sorted().map { key -> String in
            let d = durations[key] ?? DurationStat()
            return "\(key):\(d.count)/\(Int(d.total.rounded()))/\(Int(d.max.rounded()))"
        }
        let gauge = gauges.keys.sorted().map { "\($0):\(gauges[$0] ?? 0)" }
        return "t=\(now)"
            + " | st=[\(st.joined(separator: ","))]"
            + " | mem=[\(mem.joined(separator: ","))]"
            + " | cnt=[\(cnt.joined(separator: ","))]"
            + " | rs=[\(rs.joined(separator: ";"))]"
            + " | dur=[\(dur.joined(separator: ","))]"
            + " | gauge=[\(gauge.joined(separator: ","))]"
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

/// 主スレッドの積みを 0.3 秒ごとにファイルへ書く 1 行（`PerfMainSampler` の `-JPMainSampleFile`）の形（2026-11-14・札 #594）。
///
/// 形: `ms=<書き手の起動からの ms> t=<PerfTimeline の時計の ms> wall=<UTC の HH:mm:ss.SSS> ping=<ms|pending> | 段 ; 段 ; …`
/// （`wall=` は書き手が渡したときだけ。UI テストのログの行頭の時刻と突き合わせる・札 #590）
///
/// 2026-11-14 判断（run 1244 の起動からホームの段の 5956ms の止まり）: 止まりの見張りは 1 回の止まりで 650ms までの
/// 3 枚しか撮らず、残りの 5.3 秒が XCUITest の画面読みかアプリの描画か分けられなかった。ファイルの行を止まりと
/// 突き合わせられるよう `t=`（止まりの `st=` と同じ時計）を足し、浅い 8 段で切れていた**画面読み・ログの段**も残す。
/// 読む側は UI テストの `PerfMainTraceLine`（変えるときは両方と `PerfTimelineTests`）
enum PerfMainTrace {
    /// 浅い方から残す段の数
    static let headFrames = 8
    /// 深い所から拾うこのアプリの段の数
    static let appFrames = 10
    /// 深い所から拾う、画面読み・ログの段の数
    static let markerFrames = 3
    /// 画面読み（XCUITest・読み上げの木）とログの写しの印（UI テストの `PerfSurveyStage.kind` と同じ）
    static let markers = ["UIAccessibility", "AXRuntime", "AXCoreUtilities", "XCTAutomationSupport",
                          "_os_log_impl_mirror_to_stderr", "_os_trace_writev"]

    /// 1 行（改行なし）。`frames` は浅い方から
    static func line(ms: Int, timelineMs: Int, wall: String? = nil, pingMs: Int?, frames: [String]) -> String {
        let head = Array(frames.prefix(headFrames))
        let deep = frames.dropFirst(headFrames)
        let marked = deep.filter { frame in markers.contains { frame.contains($0) } }.prefix(markerFrames)
        let app = deep.filter { $0.hasPrefix("JourneyPhoto") }.prefix(appFrames)
        let rest = Array(marked) + Array(app)
        let ping = pingMs.map(String.init) ?? "pending"
        let wallField = wall.map { " wall=\($0)" } ?? ""
        return "ms=\(ms) t=\(timelineMs)\(wallField) ping=\(ping) | " + (head + (rest.isEmpty ? [] : ["…"]) + rest).joined(separator: " ; ")
    }
}

