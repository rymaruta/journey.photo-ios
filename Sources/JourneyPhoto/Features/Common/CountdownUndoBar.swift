import SwiftUI

/// **大きな「取り消す」と、減っていく細い棒**（2026-11-12・札 #543・資料第6章「ひとつ戻す」）。
///
/// 第6章の決まり: 確かめのダイアログは出さず、先に動かして数秒だけ戻せるようにする。
/// ①現像の「投稿する」（5秒）と、手に取って運んだあと（3秒）が同じ形を使う。
///
/// 形（章の模型 `.toast.big`）: 高さ 60 以上・角 14・黒 72%＋ぼかし（ガラス）・左に一言、右に白の塗りの
/// 「取り消す」（幅 104・高さ 44・墨の字）、下の縁に残りの時間の棒（高さ 3）。
/// 2026-11-12 判断: 棒は**白**（章の模型は真鍮）。この札は写真の上にも出る（ガラスの地）ので、
/// 真鍮は黒地の上だけの決まり（CLAUDE.md）に合わせた
struct CountdownUndoBar: View {

    let message: String
    /// 残りを数える秒数（棒が 1 → 0 になる長さ）
    let seconds: Double
    let onUndo: () -> Void
    /// 試験・読み上げの目印
    var identifier = "undo.countdown"

    @State private var remaining: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: JPSpace.s) {
            Text(message)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUndo) {
                Text(L("取り消す", "Undo"))
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.accentText)
                    .frame(minWidth: Self.undoWidth, minHeight: WebTheme.minTapTarget)
                    .background(WebTheme.accentBackground, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
        }
        .padding(.leading, JPSpace.m)
        .padding(.trailing, JPSpace.xs)
        .padding(.vertical, JPSpace.xs)
        .frame(minHeight: Self.height)
        .overlay(alignment: .bottomLeading) {
            // 残りの時間（減っていく）。読み上げには出さない（「取り消す」と一言で足りる）
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: geometry.size.width * remaining, height: Self.barHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .accessibilityHidden(true)
        }
        .jpGlass(in: RoundedRectangle(cornerRadius: JPRadius.m))
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
        .padding(.horizontal, JPSpace.s)
        .accessibilityElement(children: .contain)
        .onAppear {
            remaining = 1
            withAnimation(.linear(duration: seconds)) { remaining = 0 }
        }
    }

    /// 札の背（章の 60）
    nonisolated static let height: CGFloat = 60
    /// 「取り消す」の幅（章の 104）
    nonisolated static let undoWidth: CGFloat = 104
    /// 残りの棒の高さ（章の 3）
    nonisolated static let barHeight: CGFloat = 3
}

/// 数秒待ってから実行する1件（取り消せる間は何も起こさない）。①現像の投稿と、手に取って運んだ行き先が使う。
///
/// **取り消せる間は外へ出さない**（章「送るは3秒たってから送り出す」）。`schedule` で始め、
/// `undo` で止める。時間が来たら `commit` を1回だけ呼ぶ
@MainActor
final class CountdownUndo: ObservableObject {

    /// 待っている1件の一言（無ければ nil・札を出さない）
    @Published private(set) var message: String?
    /// 何回目の待ちか（札を出し直すときの目印）
    @Published private(set) var token = 0

    private var task: Task<Void, Never>?
    private var pendingCommit: (() -> Void)?

    /// 始める。前の待ちがあれば**先に済ませる**（積まない・下書きの削除と同じ）
    func schedule(_ message: String, seconds: Double, commit: @escaping () -> Void) {
        finishNow()
        self.message = message
        token += 1
        pendingCommit = commit
        let mine = token
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self, self.token == mine else { return }
            self.fire()
        }
    }

    /// 取り消す（何も起こさない）
    func undo() {
        task?.cancel()
        task = nil
        pendingCommit = nil
        message = nil
    }

    /// 待たずにいま済ませる（次の待ちを始めた・画面を閉じた）
    func finishNow() {
        guard pendingCommit != nil else { return }
        task?.cancel()
        task = nil
        fire()
    }

    private func fire() {
        let commit = pendingCommit
        pendingCommit = nil
        message = nil
        commit?()
    }
}
