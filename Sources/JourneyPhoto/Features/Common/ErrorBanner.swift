import SwiftUI

/// エラーを出す共通の見た目。**技術的な文言をそのまま出さない**。
struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?
    /// 読み直している最中（「もう一度試す」を止める。続けて押すと古い答えが新しい答えを上書きする）
    var isBusy = false

    init(message: String, isBusy: Bool = false, retry: (() -> Void)? = nil) {
        self.message = message
        self.isBusy = isBusy
        self.retry = retry
    }

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
                RetryButton(isBusy: isBusy, action: retry)
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

/// 「もう一度試す」。**見た目は小さい札（36pt）のまま、押せる所は 44pt**。
///
/// `.buttonStyle(.bordered)` の外に `frame(minHeight: 44)` を付けても当たりは広がらない
/// （ボタンの外の余白は押せない・2026-10-02 のレビュー）。ラベルの中で広げる
/// （`webTappable` と同じ考え）。**読み直している間は押せない**（`isBusy`）
struct RetryButton: View {
    var isBusy = false
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(Labels.Common.retry)
                .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, compact ? 12 : 16)
                .frame(minHeight: compact ? 30 : 36)
                .background(Color.white.opacity(0.12), in: Capsule())
                // 見た目の札の外まで当たりを広げる（見た目は変えない）
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.4 : 1)
    }
}
