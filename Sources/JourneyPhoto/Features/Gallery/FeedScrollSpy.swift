import SwiftUI
#if os(iOS)
import UIKit
#endif

/// UI テストのときだけ（`PreviewSession.feedProbe`）、ホームの縦の送り（`UIScrollView`）の送りの位置・内側の余白・
/// 中身の高さの変わり目を、ホームの事実取り（`FeedProbeTrail`）へ書く。
///
/// 2026-11-13 判断（run 1230・`testSwipesHomeFeedTabs`）: 留まった状態から「新着」を押して替えると、替えて 0.4〜0.8 秒後、
/// 中身の高さが変わらないまま、中身が 1 フレームで 13 下がった（頭へ送る `scrollTo` は呼んでいない・`scrollTo=no`）。
/// SwiftUI の枠からは「送りの位置が動いた」のか「内側の余白が変わった」のか分けられず、誰が動かしたかも分からない。
/// ここで `contentOffset`・`adjustedContentInset`・`contentSize` を直に見て、指で動かしていないのに 5 以上跳んだときは、
/// 動かした呼び出しの並び（`Thread.callStackSymbols` の先頭）も書く。推定で直さないための数（CLAUDE.md）
struct FeedScrollSpyModifier: ViewModifier {
    let record: (String) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        if PreviewSession.feedProbe {
            content.background(FeedScrollSpy(record: record).allowsHitTesting(false))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// 呼び出しの並びの1行（`Thread.callStackSymbols`）から、ライブラリと関数の名前だけを残す。区切りの「;」は「,」に替える
/// （`FeedProbeTrail` の区切りと紛れない）
enum FeedScrollSpyText {
    static func frame(_ symbol: String) -> String {
        // 例: "3   UIKitCore   0x00000001 -[UIScrollView setContentOffset:] + 120"
        let parts = symbol.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return symbol.replacingOccurrences(of: ";", with: ",") }
        let library = parts[1]
        let name = parts.dropFirst(3).joined(separator: " ")
        let trimmed = name.components(separatedBy: " + ").first ?? name
        return (library + ":" + String(trimmed.prefix(90))).replacingOccurrences(of: ";", with: ",")
    }

    /// 見張りの仕組み自身（KVO・この部品）の行を落とし、先頭の `count` 行
    static func stack(_ symbols: [String], count: Int = 8) -> String {
        symbols.dropFirst()
            .map(frame)
            .filter { !$0.contains("NSKeyValue") && !$0.contains("FeedScrollSpy") && !$0.contains("KVO") }
            .prefix(count)
            .joined(separator: " < ")
    }
}

#if os(iOS)
private struct FeedScrollSpy: UIViewRepresentable {
    let record: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.backgroundColor = .clear
        probe.coordinator = context.coordinator
        context.coordinator.record = record
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        context.coordinator.record = record
        context.coordinator.attach(to: probe)
    }

    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Probe: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: self)
        }
    }

    final class Coordinator {
        var record: ((String) -> Void)?
        private weak var host: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        private var lastOffset: CGFloat?

        /// いちばん近い祖先の `UIScrollView`（ホームの縦の送り）を見張る
        func attach(to probe: UIView) {
            guard probe.window != nil else { detach(); return }
            var view = probe.superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            guard let scroll = view as? UIScrollView, scroll !== host else { return }
            detach()
            host = scroll
            lastOffset = scroll.contentOffset.y
            observations = [
                scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                    MainActor.assumeIsolated { self?.offsetChanged(scroll) }
                },
                scroll.observe(\.contentSize, options: [.new]) { [weak self] scroll, _ in
                    MainActor.assumeIsolated { self?.write(scroll, "size") }
                },
                scroll.observe(\.contentInset, options: [.new]) { [weak self] scroll, _ in
                    MainActor.assumeIsolated { self?.write(scroll, "inset") }
                },
            ]
        }

        func detach() {
            observations.forEach { $0.invalidate() }
            observations = []
            host = nil
            lastOffset = nil
        }

        @MainActor private func offsetChanged(_ scroll: UIScrollView) {
            let y = scroll.contentOffset.y
            let delta = y - (lastOffset ?? y)
            guard abs(delta) >= 0.5 else { return }
            lastOffset = y
            var line = String(format: "off=%.2f d=%.2f", Double(y), Double(delta))
            line += summary(scroll)
            // 指で動かしていない（掴んでいない・惰性でもない）のに 5 以上跳んだら、動かした呼び出しの並びも書く
            if abs(delta) >= 5, !scroll.isTracking, !scroll.isDecelerating, !scroll.isDragging {
                line += " by=" + FeedScrollSpyText.stack(Thread.callStackSymbols)
            }
            record?(line)
        }

        @MainActor private func write(_ scroll: UIScrollView, _ what: String) {
            record?(what + String(format: " off=%.2f", Double(scroll.contentOffset.y)) + summary(scroll))
        }

        @MainActor private func summary(_ scroll: UIScrollView) -> String {
            String(format: " insTop=%.2f adjTop=%.2f adjBottom=%.2f size=%.2f track=%d decel=%d",
                   Double(scroll.contentInset.top), Double(scroll.adjustedContentInset.top),
                   Double(scroll.adjustedContentInset.bottom), Double(scroll.contentSize.height),
                   scroll.isTracking ? 1 : 0, scroll.isDecelerating ? 1 : 0)
        }
    }
}
#endif
