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

    /// 少し後に段のメモリを残す
    func markLater(_ stage: String, after seconds: Double) {
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in mark(stage) }
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

/// 回す箱の絵を塗る時間の内訳を測る（2026-11-11・1 回目に開く間の止まり 3〜4 秒の中身・**測るだけ**）。
///
/// 見本の起動の `-JPPreviewTrunkDiag rastercost`（Debug のみ）でトランクの画面を開いたときだけ、回す箱の正面・背面と同じ絵を
/// 部品を 1 つずつ外して描き、組む時間（`ImageRenderer`）と塗る時間（画素に写す）を `RasterCost…` に残す。
/// `skip` はふだんは空（外さない）
enum TrunkRasterProbe {
    /// いま外している部品（`grain` 粒・`stripes` 縞・`spots` しみと光・`art` 絵・`nodg` 胴の drawingGroup・`noshadow` 胴の影）
    static var skip: Set<String> = []

    @MainActor
    static func run(model: TrunkModel, posts: Int, stuck: [TrunkLabel], ownerName: String?, parts: TrunkEquipped,
                    wrinkles: [String: Double], tagPicks: [TrunkTagPick]) async {
        guard TrunkPerfMeter.shared.enabled else { return }
        struct Variant { let name: String; let skip: Set<String>; let labels: Bool; let parts: Bool; let scale: CGFloat; let back: Bool }
        let variants: [Variant] = [
            Variant(name: "full", skip: [], labels: true, parts: true, scale: 3, back: false),
            Variant(name: "full2", skip: [], labels: true, parts: true, scale: 3, back: false),
            Variant(name: "nograin", skip: ["grain"], labels: true, parts: true, scale: 3, back: false),
            Variant(name: "nostripes", skip: ["stripes"], labels: true, parts: true, scale: 3, back: false),
            Variant(name: "nospots", skip: ["spots"], labels: true, parts: true, scale: 3, back: false),
            Variant(name: "noart", skip: ["art"], labels: true, parts: true, scale: 3, back: false),
            Variant(name: "nodg", skip: ["nodg"], labels: true, parts: true, scale: 3, back: false),
            Variant(name: "noshadow", skip: ["noshadow"], labels: true, parts: true, scale: 3, back: false),
            Variant(name: "nolabels", skip: [], labels: false, parts: true, scale: 3, back: false),
            Variant(name: "noparts", skip: [], labels: true, parts: false, scale: 3, back: false),
            Variant(name: "scale2", skip: [], labels: true, parts: true, scale: 2, back: false),
            Variant(name: "back", skip: [], labels: true, parts: true, scale: 3, back: true),
            Variant(name: "backnograin", skip: ["grain"], labels: true, parts: true, scale: 3, back: true),
            Variant(name: "full3", skip: [], labels: true, parts: true, scale: 3, back: false),
        ]
        for (index, v) in variants.enumerated() {
            skip = v.skip
            let start = DispatchTime.now().uptimeNanoseconds
            let image: UIImage?
            if v.back {
                let r = ImageRenderer(content: TrunkFaceView(model: model, posts: posts, side: .back, parts: v.parts ? parts : .none))
                r.scale = v.scale
                image = r.uiImage
            } else {
                let r = ImageRenderer(content: TrunkBoxView(model: model, posts: posts, stuck: v.labels ? stuck : [], ownerName: ownerName,
                                                           bodyOnly: true, hangsOnFront: true, parts: v.parts ? parts : .none,
                                                           wrinkles: wrinkles, tagPicks: tagPicks))
                r.scale = v.scale
                image = r.uiImage
            }
            let built = DispatchTime.now().uptimeNanoseconds
            let px = paint(image)
            let painted = DispatchTime.now().uptimeNanoseconds
            skip = []
            TrunkPerfMeter.shared.note(String(format: "RasterCost%02d", index),
                                       String(format: "variant=%@ build_ms=%.1f paint_ms=%.1f px=%@", v.name,
                                              Double(built - start) / 1e6, Double(painted - built) / 1e6, px))
            // 画面の糸を続けて止めない
            try? await Task.sleep(for: .milliseconds(200))
        }
        TrunkPerfMeter.shared.hit("RasterCostDone")
    }

    /// 後で塗る絵を、その場で画素に写す（測るだけ・主スレッドで待つ）
    private static func paint(_ image: UIImage?) -> String {
        #if os(iOS)
        guard let cg = image?.cgImage else { return "none" }
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "noctx" }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return "\(cg.width)x\(cg.height)"
        #else
        return "-"
        #endif
    }
}

/// 文字を太くする設定（アクセシビリティの「文字を太くする」）が、回す箱の正面の絵に効くかを測る（2026-11-11・**測るだけ**）。
/// `-JPPreviewTrunkDiag boldcheck` でトランクの画面を開いたときだけ、正面と同じ絵を `legibilityWeight` なし・regular・bold で
/// 描いて画素を比べ、`BoldCheck` に残す（違いのある画素の割合）
enum TrunkBoldProbe {
    @MainActor
    static func run(model: TrunkModel, posts: Int, stuck: [TrunkLabel], ownerName: String?, parts: TrunkEquipped,
                    wrinkles: [String: Double], tagPicks: [TrunkTagPick]) {
        guard TrunkPerfMeter.shared.enabled else { return }
        #if os(iOS)
        func front(_ weight: LegibilityWeight?) -> [UInt8]? {
            let view = TrunkBoxView(model: model, posts: posts, stuck: stuck, ownerName: ownerName, bodyOnly: true,
                                    hangsOnFront: true, parts: parts, wrinkles: wrinkles, tagPicks: tagPicks)
            let renderer: ImageRenderer<AnyView>
            if let weight {
                renderer = ImageRenderer(content: AnyView(view.environment(\.legibilityWeight, weight)))
            } else {
                renderer = ImageRenderer(content: AnyView(view))
            }
            renderer.scale = 3
            return pixels(renderer.uiImage)
        }
        let plain = front(nil), regular = front(.regular), bold = front(.bold)
        TrunkPerfMeter.shared.note("BoldCheck", String(format: "system_bold=%d plain_vs_regular_pct=%.4f regular_vs_bold_pct=%.4f plain_vs_bold_pct=%.4f",
                                                       TrunkSpinDiskCache.boldText ? 1 : 0, differ(plain, regular),
                                                       differ(regular, bold), differ(plain, bold)))
        #endif
        TrunkPerfMeter.shared.hit("BoldCheckDone")
    }

    private static func pixels(_ image: UIImage?) -> [UInt8]? {
        #if os(iOS)
        guard let cg = image?.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                      bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        return ok ? data : nil
        #else
        return nil
        #endif
    }

    /// 違いのある画素の割合（%・どれかの色が 2 より大きく違う）。比べられなければ -1
    private static func differ(_ a: [UInt8]?, _ b: [UInt8]?) -> Double {
        guard let a, let b, a.count == b.count, !a.isEmpty else { return -1 }
        var count = 0
        var i = 0
        while i < a.count {
            if abs(Int(a[i]) - Int(b[i])) > 2 || abs(Int(a[i + 1]) - Int(b[i + 1])) > 2 || abs(Int(a[i + 2]) - Int(b[i + 2])) > 2 {
                count += 1
            }
            i += 4
        }
        return Double(count) / Double(a.count / 4) * 100
    }
}
