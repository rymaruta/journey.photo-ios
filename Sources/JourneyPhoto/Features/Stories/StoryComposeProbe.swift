import SwiftUI

/// ストーリー作成の札の動きの記録（UI テストのときだけ有効・`-JPPreviewStoryProbe YES`・Debug のみ）。
///
/// 札 #499「場所などを入力した後、自由に場所（位置）を動かせない」を、推定でなく数で調べるための仕組み
/// （2026-11-08・CLAUDE.md「推定で直さない」）。`StoryCanvas` の動かす操作（札・写真）の始まり・終わり・打ち切り・
/// 押した、を数えて時刻と一緒に覚え、作る画面が各札の位置・打っている最中か・動かしている最中か、を足して
/// 見えない要素 `story.probe` の値に出す。UI テストは `StoryPlaceMoveTests` で読む。
///
/// 無効のとき（本番・ふつうの起動）は何も覚えない・要素も出ない。
@MainActor
final class StoryComposeProbe {
    static let shared = StoryComposeProbe()
    static let identifier = "story.probe"

    static var isEnabled: Bool { PreviewSession.storyProbe }

    private let startedAt = Date()
    /// 数（名前 → 回数）。`ov.changed` は札の動かす操作の途中の呼び出し、`ov.ended` は指を離した回
    private var counts: [String: Int] = [:]
    /// 出来事の並び（古い順・最大 14 件）。形は `+経過ms 名前 詳細`
    private var events: [String] = []

    func note(_ name: String, _ detail: String = "", countOnly: Bool = false) {
        guard Self.isEnabled else { return }
        counts[name, default: 0] += 1
        guard !countOnly else { return }
        let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
        events.append("+\(ms)ms \(name)\(detail.isEmpty ? "" : " " + detail)")
        if events.count > 14 { events.removeFirst(events.count - 14) }
    }

    /// 値の文字列。`snapshot` は作る画面が足す、いまの状態（札の位置・打っているか・動かしているか）。
    /// 形: `<snapshot> | n=[名前:回数,…] | ev=[…;…]`
    func summary(snapshot: String) -> String {
        let n = counts.keys.sorted().map { "\($0):\(counts[$0] ?? 0)" }.joined(separator: ",")
        return "\(snapshot) | n=[\(n)] | ev=[\(events.joined(separator: ";"))]"
    }
}

/// `story.probe` の見えない要素（1pt・押せない）。0.3 秒ごとに自分の中だけ描き直す
struct StoryComposeProbeView: View {
    let snapshot: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3)) { _ in
            Text(" ")
                .font(.system(size: 1))
                .accessibilityLabel("story probe")
                .accessibilityValue(StoryComposeProbe.shared.summary(snapshot: snapshot))
                .accessibilityIdentifier(StoryComposeProbe.identifier)
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }
}
