import Foundation
import SwiftUI
#if canImport(SceneKit)
import SceneKit
#endif
#if os(iOS)
import UIKit
#endif

// 旅のトランクの重さを測る（2026-11-11・owner「旅のトランク重すぎるな」「重いのはトランクを回したり、Pro で使える
// トランクの一覧を見たとき」）。**見た目も動きも変えない・測るだけ。**
//
// 見本の起動の `-JPPreviewTrunkPerf YES`（Debug・入っている見本の利用者のときだけ・`PreviewSession.trunkPerf`）でだけ数え、
// 見えない 1pt の要素 `trunk.perf`（`TrunkPerfProbe`）の読み上げの値に出す。UI テスト
// （`ScreenshotTests.testMeasuresTrunk…`）が操作の前後の差を取り、ログの `TRUNKPERF:` の行に残す。
//
// 数えるもの:
// - 名前ごとの回数と時間（`measure`）: Canvas の描く手順（粒・縞・絵）・回す箱の貼り絵を描いた時間・SceneKit の 1 コマ
// - 回数だけ（`hit`）: `TrunkBoxView` の body を評価した回数など
// - 生きている数（`live`）: いま画面に作られているトランクの絵（`TrunkBoxView`）の数
// - 1 コマの間隔（`gap`）: 主スレッドの表示の刻み（`Main`）と、回す箱の SceneKit の刻み（`Spin`）。
//   25ms を越えた（60 コマ/秒で 1 コマ以上落ちた）回数・50・100ms を越えた回数・最長・落ちたコマの数
// - 場面の中身（`note`）: 回す箱の三角・貼り絵の数と大きさ、貼り絵 1 枚ずつの画素
// - 途中のメモリ（`mark`）: phys_footprint と user_tag 別（`CamperRenderMeter.vmTagSummary` を読むだけ使う）
final class TrunkPerfMeter: @unchecked Sendable {

    static let shared = TrunkPerfMeter(enabled: PreviewSession.trunkPerf)

    struct Tally: Equatable, Sendable {
        var count = 0
        var nanos: UInt64 = 0
        var maxNanos: UInt64 = 0
        /// 16.7ms を越えた回数
        var slow = 0
    }

    /// 1 コマの間隔の数え（ms）
    struct Gaps: Equatable, Sendable {
        var frames = 0
        var over25 = 0
        var over50 = 0
        var over100 = 0
        var maxMs = 0.0
        /// 落ちたコマの数（間隔 ÷ 本来の間隔 − 1 の合計・丸め）
        var dropped = 0
        /// 本来の間隔を越えた分の合計（ms）
        var excessMs = 0.0
        var sumMs = 0.0
    }

    static let budgetNanos: UInt64 = 16_666_667

    let enabled: Bool
    private let lock = NSLock()
    private var tallies: [String: Tally] = [:]
    private var gaps: [String: Gaps] = [:]
    private var lives: [String: Int] = [:]
    private var livePeaks: [String: Int] = [:]
    private var notes: [String: String] = [:]

    init(enabled: Bool) { self.enabled = enabled }

    func add(_ name: String, nanos: UInt64) {
        guard enabled else { return }
        lock.lock()
        var t = tallies[name] ?? Tally()
        t.count += 1
        t.nanos += nanos
        t.maxNanos = max(t.maxNanos, nanos)
        if nanos > Self.budgetNanos { t.slow += 1 }
        tallies[name] = t
        lock.unlock()
    }

    /// 回数だけ数える
    func hit(_ name: String) {
        guard enabled else { return }
        add(name, nanos: 0)
    }

    /// 生きている数を足し引きする（いちばん多かった数も残す）
    func live(_ name: String, _ delta: Int) {
        guard enabled else { return }
        lock.lock()
        let now = (lives[name] ?? 0) + delta
        lives[name] = now
        livePeaks[name] = max(livePeaks[name] ?? 0, now)
        lock.unlock()
    }

    /// 1 コマの間隔を足す（`expectedMs` は本来の間隔）
    func gap(_ name: String, ms: Double, expectedMs: Double) {
        guard enabled, ms > 0 else { return }
        lock.lock()
        var g = gaps[name] ?? Gaps()
        g.frames += 1
        g.sumMs += ms
        if ms > 25 { g.over25 += 1 }
        if ms > 50 { g.over50 += 1 }
        if ms > 100 { g.over100 += 1 }
        g.maxMs = max(g.maxMs, ms)
        let expected = max(1, expectedMs)
        g.dropped += max(0, Int((ms / expected).rounded()) - 1)
        g.excessMs += max(0, ms - expected * 1.5)
        gaps[name] = g
        lock.unlock()
    }

    func note(_ name: String, _ fields: String) {
        guard enabled else { return }
        lock.lock()
        notes[name] = fields
        lock.unlock()
    }

    /// 途中のメモリを残す（`Mem<段>` に「mb= int= cmp= dev=」、`VM<段>` に user_tag 別）
    func mark(_ stage: String) {
        guard enabled, let p = CamperRenderMeter.processUsage() else { return }
        note("Mem" + stage, String(format: "mb=%.1f int=%.1f cmp=%.1f dev=%.1f", p.memMB, p.internalMB, p.compressedMB, p.deviceMB))
        #if canImport(Darwin)
        note("VM" + stage, CamperRenderMeter.vmTagSummary())
        #endif
    }

    /// 「名前 n= ms= max= slow=;」「Gap名前 frames= …;」「Live名前 now= peak=;」「注記;」「Process …;」
    func summary() -> String {
        lock.lock()
        let t = tallies, g = gaps, l = lives, peaks = livePeaks, n = notes
        lock.unlock()
        var parts = t.keys.sorted().map { key -> String in
            let v = t[key]!
            return "\(key) n=\(v.count) ms=\(Self.ms(v.nanos)) max=\(Self.ms(v.maxNanos)) slow=\(v.slow);"
        }
        parts += g.keys.sorted().map { key -> String in
            let v = g[key]!
            return String(format: "Gap%@ frames=%d over25=%d over50=%d over100=%d max=%.1f dropped=%d excess=%.1f sum=%.1f;",
                          key, v.frames, v.over25, v.over50, v.over100, v.maxMs, v.dropped, v.excessMs, v.sumMs)
        }
        parts += l.keys.sorted().map { "Live\($0) now=\(l[$0]!) peak=\(peaks[$0] ?? 0);" }
        parts += n.keys.sorted().map { "\($0) \(n[$0]!);" }
        if enabled, let p = CamperRenderMeter.processUsage() {
            parts.append(String(format: "Process cpu_ms=%.1f mem_mb=%.1f int_mb=%.1f cmp_mb=%.1f dev_mb=%.1f;",
                                p.cpuMs, p.memMB, p.internalMB, p.compressedMB, p.deviceMB))
        }
        return parts.joined(separator: " ")
    }

    static func ms(_ nanos: UInt64) -> String { String(format: "%.2f", Double(nanos) / 1_000_000) }

    /// 測る（数えない起動では `body` だけ）
    @inline(__always)
    static func measure<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        guard shared.enabled else { return try body() }
        let start = DispatchTime.now().uptimeNanoseconds
        let out = try body()
        shared.add(name, nanos: DispatchTime.now().uptimeNanoseconds &- start)
        return out
    }
}

/// 主スレッドの表示の刻みの間隔を `TrunkPerfMeter` の `Main` に渡す（数える起動のときだけ始める）
final class TrunkFrameWatcher: NSObject {
    static let shared = TrunkFrameWatcher()

    #if os(iOS)
    private var link: CADisplayLink?
    private var last: CFTimeInterval?

    func start() {
        guard link == nil, TrunkPerfMeter.shared.enabled else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        NotificationCenter.default.addObserver(self, selector: #selector(reset),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard let last else { return }
        TrunkPerfMeter.shared.gap("Main", ms: (link.timestamp - last) * 1000, expectedMs: link.duration * 1000)
    }

    @objc private func reset() { last = nil }
    #else
    func start() {}
    #endif
}

/// 数を読み上げの値に出す見えない 1pt（数える起動のときだけ置く）。0.5 秒ごとに自分の中だけ描き直す
struct TrunkPerfProbe: View {
    static let identifier = "trunk.perf"

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { _ in
            Text(" ")
                .font(.system(size: 1))
                .accessibilityLabel("trunk perf")
                .accessibilityValue(TrunkPerfMeter.shared.summary())
                .accessibilityIdentifier(Self.identifier)
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .onAppear { TrunkFrameWatcher.shared.start() }
    }
}

/// 画面に作られているトランクの絵の数を数える（`onAppear`・`onDisappear`）。数えない起動では何もしない
struct TrunkLiveCount: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        if TrunkPerfMeter.shared.enabled {
            content
                .onAppear { TrunkPerfMeter.shared.live(name, 1) }
                .onDisappear { TrunkPerfMeter.shared.live(name, -1) }
        } else {
            content
        }
    }
}

#if canImport(SceneKit)
/// 回す箱（`MedalCoinView` の SCNView）の 1 コマ: 描く糸で `updateAtTime` から `didRenderScene` まで（`SpinFrame`）と、
/// コマの刻みの間隔（`Spin`）。数える起動で、箱のときだけ付ける
final class TrunkSpinFrameMeter: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    /// 箱の節（描いた向きを読む）
    weak var node: SCNNode?
    private let lock = NSLock()
    private var started: UInt64?
    private var lastTime: TimeInterval?

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        started = DispatchTime.now().uptimeNanoseconds
        let previous = lastTime
        lastTime = time
        lock.unlock()
        if let previous { TrunkPerfMeter.shared.gap("Spin", ms: (time - previous) * 1000, expectedMs: 1000.0 / 60) }
    }

    func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lock.lock()
        let from = started
        started = nil
        lock.unlock()
        guard let from else { return }
        TrunkPerfMeter.shared.add("SpinFrame", nanos: DispatchTime.now().uptimeNanoseconds &- from)
        // 描いた向き（書いた向き `SpinApplied` と同じなら、止まり際まで描いている）
        if let node { TrunkPerfMeter.shared.note("SpinDrawn", Self.text(node.presentation.orientation)) }
    }

    static func text(_ q: SCNQuaternion) -> String {
        String(format: "x=%.5f y=%.5f z=%.5f w=%.5f", Double(q.x), Double(q.y), Double(q.z), Double(q.w))
    }
}
#endif
