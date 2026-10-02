import SwiftUI

/// エラーを出す共通の見た目。**技術的な文言をそのまま出さない**。
struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let retry {
                Button(Labels.Common.retry, action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// **空の状態**（「まだありません」）の見た目。`ErrorBanner` と同じ置き方・同じ文字色で、
/// **警告の三角を出さない**——0件は失敗ではない（2026-10-02 の調査: 「まだありません」にも
/// 三角が出ていて、何か壊れたように読めた）。読めなかった回は `ErrorBanner` を使う
struct EmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(24)
            .frame(maxWidth: .infinity)
    }
}
