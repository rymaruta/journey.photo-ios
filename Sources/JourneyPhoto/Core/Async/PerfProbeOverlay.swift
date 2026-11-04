import SwiftUI
#if os(iOS)
import UIKit
#endif

/// `PerfRecorder.summary()` を読み上げの値に出す見えない要素（UI テストのときだけ置く・`-JPPreviewPerfProbe YES`）。
///
/// `CamperRenderProbe` と同じ作り: 0.5 秒ごとに**自分の中だけ**描き直す（親の画面は動かさない）。
/// 見えない 1pt・押せない。識別子は `perf.probe`（UI テストは `PerfProbeSupport` で読む）
struct PerfProbeOverlay: View {
    static let identifier = "perf.probe"

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { _ in
            Text(" ")
                .font(.system(size: 1))
                .accessibilityLabel("perf probe")
                .accessibilityValue(PerfRecorder.shared.summary())
                .accessibilityIdentifier(Self.identifier)
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .onAppear { PerfStallWatcher.shared.start() }
    }
}

/// 画面の表示の刻み（`CADisplayLink`）の間隔を `PerfRecorder` に渡す。メインスレッドが止まると刻みが遅れるので、
/// 間隔が 100ms を超えた回数と最大の間隔が、メインスレッドの停止の数になる（`StallMeter`）。
/// 無効のとき（本番・ふつうの起動）は始めない。iOS 以外（Linux の型検査）では何もしない
final class PerfStallWatcher: NSObject {
    static let shared = PerfStallWatcher()

    #if os(iOS)
    private var link: CADisplayLink?

    func start() {
        guard link == nil, PerfRecorder.shared.isEnabled else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        // 裏に入る間は刻みが止まる。戻った直後の長い空きを停止に数えない
        NotificationCenter.default.addObserver(self, selector: #selector(resetFrames),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    @objc private func tick(_ link: CADisplayLink) {
        PerfRecorder.shared.recordFrame(at: link.timestamp)
    }

    @objc private func resetFrames() {
        PerfRecorder.shared.resetFrames()
    }
    #else
    func start() {}
    #endif
}
