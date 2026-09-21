import SwiftUI

/// 画面の下に一瞬だけ出る知らせ。**Web の `Toast` と同じ役目。**
///
/// うまくいった操作を**何も言わない**のをやめる。いいね・ブロック・
/// コピーのように画面がほとんど変わらない操作は、押せたのかどうかが
/// 分からない。
struct ToastOverlay: View {

    @EnvironmentObject private var toasts: ToastCenter

    var body: some View {
        if let message = toasts.current {
            HStack(spacing: 8) {
                Image(systemName: message.kind == .success
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(message.text)
                    .font(.footnote)
                    .lineLimit(2)
            }
            .foregroundStyle(WebTheme.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(radius: 10)
            .padding(.horizontal, 24)
            // **押したら消せる。** 読み終わった人を3秒待たせない
            .onTapGesture { toasts.dismiss() }
            .transition(.opacity)
            .id(message.id)
            .accessibilityIdentifier("toast")
        }
    }
}
