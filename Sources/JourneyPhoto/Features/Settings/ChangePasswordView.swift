import SwiftUI

/// パスワードを変える（ログインしたまま）。
///
/// 忘れたときの再設定はログイン画面にあるが、**覚えているけど変えたい**は
/// そこからだと一度ログアウトすることになる。
struct ChangePasswordView: View {

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var updated = ""

    var body: some View {
        Form {
            // 板 44: 欄の上に小さい見出し
            Section {
                labeled(L("いまのパスワード", "Current password")) {
                    SecureField("", text: $current)
                        .textContentType(.password)
                }
                labeled(L("新しいパスワード", "New password")) {
                    SecureField("", text: $updated)
                        .textContentType(.newPassword)
                }
            } footer: {
                // 板には無いが残す——決まりを知らずに打つと、送ってから断られる
                Text(AuthMessage.passwordRule)
            }
            .listRowBackground(Color.clear)

            if let error = auth.errorMessage {
                Section { Text(error).foregroundStyle(WebTheme.danger).font(.callout) }
            }

            Section {
                // 板は幅いっぱいの白いカプセル
                Button {
                    Task {
                        auth.errorMessage = nil
                        if await auth.changePassword(current: current, new: updated) {
                            dismiss()
                        }
                    }
                } label: {
                    Text(L("変える", "Change"))
                        .frame(maxWidth: .infinity)
                        .webPrimaryButton()
                }
                .buttonStyle(.plain)
                .disabled(auth.isWorking || current.isEmpty || updated.isEmpty)
                .opacity(auth.isWorking || current.isEmpty || updated.isEmpty ? 0.4 : 1)
            }
            .listRowBackground(Color.clear)
        }
        .webScreen()
        .navigationTitle(L("パスワードを変える", "Change password"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labeled<Field: View>(_ title: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.muted2)
                .accessibilityHidden(true)
            field()
                .accessibilityLabel(title)
        }
    }
}
