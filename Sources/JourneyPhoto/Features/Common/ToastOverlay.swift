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
                Image(systemName: Self.symbol(message.kind))
                Text(message.text)
                    .font(.subheadline)
                    .lineLimit(2)
                // 「取り消す」（2026-11-12 判断）。ガラスの上なので白の字（真鍮はガラスの上に置かない）・当たり 44
                if let undo = toasts.undo {
                    Button { Task { await toasts.performUndo() } } label: {
                        Text(undo.title)
                            .font(.subheadline.weight(.semibold))
                            .underline()
                            .padding(.horizontal, 6)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("toast.undo")
                } else if let title = message.actionTitle, let action = message.action {
                    // 押せる一手（1.1.83「カードにする」）。当たりは 44
                    // 1.1.84 のまとめ: 「取り消す」と同じ所に置く（1つの知らせにはどちらか1つ・`ToastCenter.show`）
                    Button {
                        toasts.dismiss()
                        action()
                    } label: {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .underline()
                            .frame(minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("toast.action")
                }
            }
            .foregroundStyle(WebTheme.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, toasts.undo == nil ? 10 : 0)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(radius: 10)
            .padding(.horizontal, 24)
            // **押したら消せる。** 読み終わった人を3秒待たせない
            .onTapGesture { if toasts.undo == nil { toasts.dismiss() } }
            .transition(.opacity)
            .id(message.id)
            // 子の「取り消す」の目印を消さないよう、入れ物の要素にしてから名前を付ける
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("toast")
        }
    }

    /// 知らせの印。案内（`info`）に成功の ✓ や失敗の △ を付けない
    nonisolated static func symbol(_ kind: ToastCenter.Message.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}
