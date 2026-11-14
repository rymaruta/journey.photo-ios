import SwiftUI

/// **UI テストの事実取りだけ**: 札の行・中身の横の払いを「どの指の操作が受けたか」を記録し、見えない要素
/// `mypage.tabs.probe` の値に出す（`-JPPreviewTabSwipeProbe YES`・Debug のみ・`PreviewSession.tabSwipeProbe`）。
///
/// 2026-11-13（#187 案 B の確かめ役の指摘・Mac run 1227）: とても大きい字（AX3）で札の行が横に送る並びに替わると、
/// 流れている元の札の行の上を右へ払っても札が替わらなかった（`testPinsMyPageTabsAtLargeTextAX3` の after-right）。
/// 受けたのが UIKit のパン（`ProfileSwipePanHost`）か、留まった札の SwiftUI の払い（`ProfileTabOverlaySwipe`）か、
/// 横に送る `ScrollView` か、どれも受けなかったのかを、**推定でなく記録で**分ける。Release では何も記録しない
final class ProfileTabSwipeLog: ObservableObject {

    static let shared = ProfileTabSwipeLog()

    /// 残す件数（古いものから捨てる。番号 `#n` は通しなので、前後の値の差で増えた分が分かる）
    static let keep = 14

    /// 記録するか（起動の引数で決まる。途中で変わらない）
    let enabled = PreviewSession.tabSwipeProbe

    @Published private(set) var entries: [String] = []
    /// 横に送る札の行（`ProfileTabColumnRow` の `ScrollView(.horizontal)`）の送りの位置（contentOffset.x）と、その範囲
    @Published private(set) var horizontalOffset: Double?
    private var horizontalRange: (min: Double, max: Double)?
    private var count = 0

    /// 1件足す（無効なら何もしない）
    func note(_ text: String) {
        guard enabled else { return }
        count += 1
        entries.append("#\(count) \(text)")
        if entries.count > Self.keep { entries.removeFirst(entries.count - Self.keep) }
    }

    /// 横に送る札の行の送りの位置。動いた範囲（最小〜最大）も控える——離した後に元へ戻っても、動いたことが分かる
    func horizontal(_ offset: Double) {
        guard enabled else { return }
        let rounded = (offset * 10).rounded() / 10
        guard rounded != horizontalOffset else { return }
        horizontalOffset = rounded
        let range = horizontalRange ?? (rounded, rounded)
        horizontalRange = (min(range.min, rounded), max(range.max, rounded))
    }

    /// 見えない要素に出す値
    var text: String {
        let hx = horizontalOffset.map { Self.n($0) } ?? "-"
        let range = horizontalRange.map { "\(Self.n($0.min))..\(Self.n($0.max))" } ?? "-"
        return "hx=\(hx) hxRange=\(range) | " + entries.joined(separator: " ; ")
    }

    static func n(_ value: Double) -> String { String(format: "%.1f", value) }
}

/// `mypage.tabs.probe` の見えない要素。選んでいる札が替わったことも記録する（払いの結果）
struct ProfileTabSwipeProbeView: View {
    let selection: String
    @ObservedObject var log = ProfileTabSwipeLog.shared

    var body: some View {
        if log.enabled {
            Text(".")
                .font(.caption2)
                .foregroundStyle(Color.clear)
                .allowsHitTesting(false)
                .accessibilityIdentifier("mypage.tabs.probe")
                .accessibilityValue(log.text)
                .onChange(of: selection) { previous, next in
                    log.note("sel \(previous)->\(next)")
                }
        }
    }
}
