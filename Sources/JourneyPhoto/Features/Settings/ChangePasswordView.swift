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
            Section {
                SecureField(L("いまのパスワード", "Current password"), text: $current)
                    .textContentType(.password)
                SecureField(L("新しいパスワード", "New password"), text: $updated)
                    .textContentType(.newPassword)
            } footer: {
                Text(AuthMessage.passwordRule)
            }
            .listRowBackground(Color.clear)

            if let error = auth.errorMessage {
                Section { Text(error).foregroundStyle(WebTheme.danger).font(.callout) }
            }

            Section {
                Button(L("変える", "Change")) {
                    Task {
                        auth.errorMessage = nil
                        if await auth.changePassword(current: current, new: updated) {
                            dismiss()
                        }
                    }
                }
                .disabled(auth.isWorking || current.isEmpty || updated.isEmpty)
            }
            .listRowBackground(Color.clear)
        }
        .webScreen()
        .navigationTitle(L("パスワードを変える", "Change password"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
