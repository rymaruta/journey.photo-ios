import SwiftUI

/// 報告する AI の答え（`AIAnswerReportFlow` に渡す）
struct AIAnswerReportTarget: Identifiable, Equatable {
    /// 隠すときの印（`AIAnswerReports`）
    let id: String
    let source: AIAnswerReport.Source
    /// 利用者自身が頼んだ文（無ければ nil）
    let question: String?
    /// AI の答え
    let answer: String
}

/// 「この答えを報告」を押したあとの流れ（2026-11-26 判断・審査 1.2 と 4.7）。
///
/// 理由を1つ選ぶ（系統の確かめのダイアログ。取り消せる）→ その場で答えを隠す → 「意見を送る」の口で送る
/// （`FeedbackOutbox`: 圏外なら残して、つながったら送る）。送るのは頼んだ文と AI の答えだけ（`AIAnswerReport.text`）
struct AIAnswerReportFlow: ViewModifier {

    @Binding var target: AIAnswerReportTarget?

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var toasts: ToastCenter
    @ObservedObject private var reports = AIAnswerReports.shared

    func body(content: Content) -> some View {
        content
            .confirmationDialog(AIAnswerReport.dialogTitle, isPresented: shown, titleVisibility: .visible) {
                ForEach(AIAnswerReport.Reason.allCases, id: \.rawValue) { reason in
                    Button(reason.label) { report(reason) }
                }
                Button(Labels.Common.cancel, role: .cancel) { target = nil }
            } message: {
                Text(AIAnswerReport.dialogMessage)
            }
    }

    private var shown: Binding<Bool> {
        Binding(get: { target != nil }, set: { if !$0 { target = nil } })
    }

    private func report(_ reason: AIAnswerReport.Reason) {
        guard let target else { return }
        self.target = nil
        // その場で隠す（送れたかどうかを待たない）
        reports.hide(target.id)
        let draft = AIAnswerReport.draft(source: target.source, reason: reason, question: target.question,
                                         answer: target.answer, userId: auth.userId)
        let outbox = FeedbackOutbox()
        try? outbox.save(draft, photo: nil)
        let service = environment.feedback
        let userId = auth.userId
        Task {
            let outcome = await outbox.deliver(draft, currentUserId: userId) { draft, photo, signedIn in
                try await service.send(draft, photo: photo, signedIn: signedIn)
            }
            toasts.show(outcome.isDelivered ? AIAnswerReport.thanks : AIAnswerReport.later)
        }
    }
}

extension View {
    /// AI の答えの報告の流れを付ける（`AIAnswerReportFlow`）
    func aiAnswerReport(_ target: Binding<AIAnswerReportTarget?>) -> some View {
        modifier(AIAnswerReportFlow(target: target))
    }
}

/// 答えの下の「この答えを報告」（字のボタン。text-3 の小さな字、当たりは 44）
struct AIAnswerReportButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "flag")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(AIAnswerReport.action)
                    .font(JPFont.caption)
            }
            .foregroundStyle(WebTheme.text3)
            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AIAnswerReport.action)
        .accessibilityIdentifier("ai.report")
    }
}

/// 報告して隠した答えの代わりの1行
struct AIAnswerHiddenLine: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.slash")
                .font(JPFont.footnote)
                .accessibilityHidden(true)
            Text(AIAnswerReport.hiddenLine)
                .font(JPFont.footnote)
        }
        .foregroundStyle(WebTheme.text3)
        .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ai.report.hidden")
    }
}
