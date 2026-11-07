import Foundation
#if canImport(MetricKit) && canImport(os)
import MetricKit
import os
#endif

/// OS が集めた診断（前回までのクラッシュ・ハング・CPU/ディスクの上限超え）と、起動時間の分布を
/// 受け取って `os.Logger`（category `MetricKit`）に出す（2026-11-07 判断）。
///
/// - **サーバーには送らない。** 端末のログに残すだけ（新しい口は承認が要る）。
/// - **プライバシーマニフェストは変えない**: 受け取りは端末内で完結し、アプリは何も外へ出さない
///   （`NSPrivacyCollectedDataTypes` に足すのは「開発者が自分のサーバーなどへ集める」データ。
///   MetricKit の受信は必須理由 API（`NSPrivacyAccessedAPITypes`）にも当たらない）。
///   将来サーバーへ送るときは、マニフェスト（クラッシュデータ・性能データ）と App Store Connect の
///   「App のプライバシー」を同時に直す。
/// - OS は診断を最大1日1回、起動の直後などにまとめて届ける。受け取るには、起動の早い時期に
///   購読者を登録しておく必要がある（`AppDelegate.didFinishLaunching` から `start()`）。
final class MetricKitReceiver: NSObject, @unchecked Sendable {

    static let shared = MetricKitReceiver()

    private var started = false
    private let lock = NSLock()

    /// 購読を始める（何度呼んでも1回）。MetricKit の無い環境（Linux の模型）では何もしない
    func start() {
        lock.lock()
        let first = !started
        started = true
        lock.unlock()
        guard first else { return }
        #if canImport(MetricKit) && canImport(os)
        MXMetricManager.shared.add(self)
        #endif
    }
}

#if canImport(MetricKit) && canImport(os)
extension MetricKitReceiver: MXMetricManagerSubscriber {

    private static let log = Logger(subsystem: PerfSignpost.subsystem, category: "MetricKit")

    // MARK: - 受け取り

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let version = payload.latestApplicationVersion
            guard let histogram = payload.applicationLaunchMetrics?.histogrammedTimeToFirstDraw else { continue }
            let buckets = histogram.bucketEnumerator.allObjects
                .compactMap { $0 as? MXHistogramBucket<UnitDuration> }
                .map { (startMs: $0.bucketStart.converted(to: .milliseconds).value,
                        endMs: $0.bucketEnd.converted(to: .milliseconds).value,
                        count: $0.bucketCount) }
            Self.log.notice("\(DiagnosticsSummary.launch(buckets: buckets, appVersion: version), privacy: .public)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let line = DiagnosticsSummary.crash(
                    signal: crash.signal?.intValue,
                    exceptionType: crash.exceptionType?.intValue,
                    exceptionCode: crash.exceptionCode?.intValue,
                    terminationReason: crash.terminationReason,
                    appVersion: crash.applicationVersion)
                Self.log.error("\(line, privacy: .public)")
                emitCallStack(crash.callStackTree)
            }
            for hang in payload.hangDiagnostics ?? [] {
                let line = DiagnosticsSummary.hang(
                    milliseconds: hang.hangDuration.converted(to: .milliseconds).value,
                    appVersion: hang.applicationVersion)
                Self.log.error("\(line, privacy: .public)")
                emitCallStack(hang.callStackTree)
            }
            for item in payload.cpuExceptionDiagnostics ?? [] {
                let line = DiagnosticsSummary.exception(kind: "cpu", appVersion: item.applicationVersion)
                Self.log.error("\(line, privacy: .public)")
            }
            for item in payload.diskWriteExceptionDiagnostics ?? [] {
                let line = DiagnosticsSummary.exception(kind: "diskWrite", appVersion: item.applicationVersion)
                Self.log.error("\(line, privacy: .public)")
            }
        }
    }

    /// 呼び出し履歴（JSON）を、ログの長さの限りに分けて出す
    private func emitCallStack(_ tree: MXCallStackTree) {
        let json = String(decoding: tree.jsonRepresentation(), as: UTF8.self)
        for (index, piece) in DiagnosticsSummary.chunks(json).enumerated() {
            Self.log.error("callStack[\(index, privacy: .public)] \(piece, privacy: .public)")
        }
    }
}
#endif
