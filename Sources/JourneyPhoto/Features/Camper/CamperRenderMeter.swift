import Foundation
import SwiftUI
#if canImport(os)
import os
#endif
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif

// とおまわり号の描画を測る（2026-10-31・#430「キャンピングカーの描画を軽くする」）。見た目は変えない。
//
// - 印（`OSSignposter`・subsystem `com.journeyphoto.camper`・category `CamperRender`）: 1 コマ（SceneKit の描く糸で
//   `updateAtTime` → `didRenderScene`）と、SwiftUI から SCNView へ値を渡す処理（`updateUIView` とその中の段）。
//   Instruments と UI テストの `XCTOSSignpostMetric` が読む。名前はキャンピングカーだけのもの（`Camper…`）にして、
//   アプリ全体の計測（別の枝）とぶつけない
// - 数（`CamperRenderMeter`）: 同じ名前ごとに回数・合計の時間・最長・16.7 ms を越えた回数。見本の起動で
//   `-JPPreviewCamperPerf YES` のときだけ数え、画面の隅の読み上げの値（`CamperRenderProbe`・見えない 1pt）に出す。
//   UI テスト（`ScreenshotTests.testMeasuresCamperRender…`）が前後の差を取り、ログと注記に残す

/// 名前ごとの回数と時間（スレッドをまたいで足す。描く糸と画面の糸の両方から呼ばれる）
final class CamperRenderMeter: @unchecked Sendable {

    static let shared = CamperRenderMeter(enabled: PreviewSession.camperPerf)

    /// 印の置き場（UI テストの `XCTOSSignpostMetric` も同じ字で読む）
    static let subsystem = "com.journeyphoto.camper"
    static let category = "CamperRender"
    /// 1 コマの目安（60 コマ/秒）。これを越えたコマを「遅いコマ」に数える
    static let frameBudgetNanos: UInt64 = 16_666_667

    struct Tally: Equatable, Sendable {
        var count = 0
        var nanos: UInt64 = 0
        var maxNanos: UInt64 = 0
        /// 1 コマの目安（16.7 ms）を越えた回数
        var slow = 0
    }

    /// 数えるか（見本の起動の計測のときだけ。印はいつも付ける）
    let enabled: Bool
    private let lock = NSLock()
    private var tallies: [String: Tally] = [:]

    init(enabled: Bool) { self.enabled = enabled }

    func add(_ name: String, nanos: UInt64) {
        guard enabled else { return }
        lock.lock()
        var t = tallies[name] ?? Tally()
        t.count += 1
        t.nanos += nanos
        t.maxNanos = max(t.maxNanos, nanos)
        if nanos > Self.frameBudgetNanos { t.slow += 1 }
        tallies[name] = t
        lock.unlock()
    }

    func tally(_ name: String) -> Tally {
        lock.lock()
        defer { lock.unlock() }
        return tallies[name] ?? Tally()
    }

    /// 「名前 n=回数 ms=合計 max=最長 slow=遅いコマ;」を名前の順に（UI テストが読む）
    func summary() -> String {
        lock.lock()
        let all = tallies
        lock.unlock()
        return all.keys.sorted().map { key in
            let t = all[key]!
            return "\(key) n=\(t.count) ms=\(Self.ms(t.nanos)) max=\(Self.ms(t.maxNanos)) slow=\(t.slow);"
        }.joined(separator: " ")
    }

    static func ms(_ nanos: UInt64) -> String { String(format: "%.2f", Double(nanos) / 1_000_000) }

    /// 試験用
    func reset() {
        lock.lock()
        tallies = [:]
        lock.unlock()
    }
}

/// 印を付けて測る（画面の糸の処理）
enum CamperRenderMark {
    #if canImport(os)
    static let signposter = OSSignposter(subsystem: CamperRenderMeter.subsystem, category: CamperRenderMeter.category)
    #endif

    @discardableResult
    static func measure<T>(_ name: StaticString, meter: CamperRenderMeter = .shared, _ body: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        #if canImport(os)
        let state = signposter.beginInterval(name)
        #endif
        let out = try body()
        #if canImport(os)
        signposter.endInterval(name, state)
        #endif
        if meter.enabled { meter.add(name.description, nanos: DispatchTime.now().uptimeNanoseconds &- start) }
        return out
    }

    /// 回数だけ数える（止まっている SCNView を起こした回数など）
    static func count(_ name: StaticString, meter: CamperRenderMeter = .shared) {
        #if canImport(os)
        signposter.emitEvent(name)
        #endif
        if meter.enabled { meter.add(name.description, nanos: 0) }
    }
}

#if canImport(SceneKit) || canImport(SceneKitShim)
/// SCNView の 1 コマを測る（描く糸で `updateAtTime` から `didRenderScene` まで）。
/// SCNView の delegate は 1 つなので、もとの delegate（部屋の「最初のコマ」の見張り）へは描いた後を渡す
final class CamperFrameMeter: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    let name: StaticString
    let meter: CamperRenderMeter
    /// もとの delegate（持つのは呼ぶ側。ここは弱く）
    weak var next: (any SCNSceneRendererDelegate)?
    private let lock = NSLock()
    private var started: UInt64?
    #if canImport(os)
    private var state: OSSignpostIntervalState?
    #endif

    init(_ name: StaticString, meter: CamperRenderMeter = .shared, next: (any SCNSceneRendererDelegate)? = nil) {
        self.name = name
        self.meter = meter
        self.next = next
    }

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        begin()
    }

    func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        end()
        next?.renderer(renderer, didRenderScene: scene, atTime: time)
    }

    /// 1 コマの始まり（試験からも呼ぶ）
    func begin() {
        lock.lock()
        started = DispatchTime.now().uptimeNanoseconds
        #if canImport(os)
        state = CamperRenderMark.signposter.beginInterval(name)
        #endif
        lock.unlock()
    }

    /// 1 コマの終わり（始まりの無い終わりは数えない）
    func end() {
        lock.lock()
        let from = started
        started = nil
        #if canImport(os)
        if let s = state { CamperRenderMark.signposter.endInterval(name, s) }
        state = nil
        #endif
        lock.unlock()
        guard let from else { return }
        meter.add(name.description, nanos: DispatchTime.now().uptimeNanoseconds &- from)
    }
}
#endif

/// 計測の数を読み上げの値に出す（見えない 1pt・見本の起動の `-JPPreviewCamperPerf YES` のときだけ置く）。
/// 0.5 秒ごとに読み直す。自分の中だけ描き直すので、親の画面（SCNView への値渡し）は動かさない
struct CamperRenderProbe: View {
    let id: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { _ in
            Text(" ")
                .font(.system(size: 1))
                .accessibilityLabel("camper render meter")
                .accessibilityValue(CamperRenderMeter.shared.summary())
                .accessibilityIdentifier(id)
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }
}
