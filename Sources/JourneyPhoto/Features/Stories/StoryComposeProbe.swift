import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    /// キーボードの出入りの見張り（札 #522・下の `watchKeyboard`）
    private var keyboardObservers: [NSObjectProtocol] = []

    private init() {
        watchKeyboard()
    }

    /// **キーボードの出入りを出来事に足す**（札 #522・2026-11-14・UI テストのときだけ）。
    /// 「完了」を押してもキーボードが 6 秒で消えない回が Mac で出た（run 42886441355・1.1.82 の run 1091）。
    /// 押した指が届いたか（`touch.*`）・打ち終えたか（`typing.finish`）・欄のピントが外れたか（`typing.focus`）と、
    /// キーボードが閉じ始めた・閉じ終えた時刻（`kb.*`）を同じ時計で並べ、どこで止まったかを数で見る
    private func watchKeyboard() {
        #if os(iOS)
        guard Self.isEnabled else { return }
        let names: [(Notification.Name, String)] = [
            (UIResponder.keyboardWillShowNotification, "kb.willShow"), (UIResponder.keyboardDidShowNotification, "kb.didShow"),
            (UIResponder.keyboardWillHideNotification, "kb.willHide"), (UIResponder.keyboardDidHideNotification, "kb.didHide")
        ]
        for (name, label) in names {
            keyboardObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                MainActor.assumeIsolated {
                    StoryComposeProbe.shared.note(label, "y=\(Int(frame.minY)) h=\(Int(frame.height))")
                }
            })
        }
        #endif
    }
    /// 数（名前 → 回数）。`ov.changed` は札の動かす操作の途中の呼び出し、`ov.ended` は指を離した回
    private var counts: [String: Int] = [:]
    /// 出来事の並び（古い順・最大 40 件。2026-11-12 に指の届き先 `touch.*` を足したので 14 → 40）。形は `+経過ms 名前 詳細`
    private var events: [String] = []

    func note(_ name: String, _ detail: String = "", countOnly: Bool = false) {
        guard Self.isEnabled else { return }
        counts[name, default: 0] += 1
        guard !countOnly else { return }
        let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
        events.append("+\(ms)ms \(name)\(detail.isEmpty ? "" : " " + detail)")
        if events.count > 40 { events.removeFirst(events.count - 40) }
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
        ZStack {
            TimelineView(.animation(minimumInterval: 0.3)) { _ in
                Text(" ")
                    .font(.system(size: 1))
                    .accessibilityLabel("story probe")
                    .accessibilityValue(StoryComposeProbe.shared.summary(snapshot: snapshot))
                    .accessibilityIdentifier(StoryComposeProbe.identifier)
            }
            // 指の届き先（窓・部品）も記録に足す（`StoryTouchProbe`・2026-11-12）
            StoryTouchProbe()
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }
}
