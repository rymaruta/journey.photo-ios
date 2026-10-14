import SwiftUI

/// パスワードを変える（ログインしたまま）。
///
/// 忘れたときの再設定はログイン画面にあるが、**覚えているけど変えたい**は
/// そこからだと一度ログアウトすることになる。
///
/// **v2（2026-10-14・板 ChangePassword）**: 左寄せの明朝 30 の大見出し（設定と同じ・バーの中央には出さない）、
/// 入力中の欄は真鍮の縁（`ChangePasswordLayout.focusRing`）、主ボタンは写真の無い画面なので真鍮の塗りに墨。
/// 板の「目の印」（表示・非表示）は**足さない**（新しい機能を入れない・owner の決め）
struct ChangePasswordView: View {

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var updated = ""

    private enum Field { case current, updated }
    @FocusState private var focused: Field?

    var body: some View {
        Form {
            Section {
                Text(L("パスワードを変える", "Change password"))
                    .font(JPFont.display(SettingsLayout.titleSize, relativeTo: .largeTitle))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            .jpFormRow()

            // 板 44: 欄の上に小さい見出し
            Section {
                JPField(L("いまのパスワード", "Current password")) {
                    SecureField("", text: $current)
                        .textContentType(.password)
                        .focused($focused, equals: .current)
                }
                .overlay(alignment: .bottom) { focusRing(focused == .current) }
                JPField(L("新しいパスワード", "New password")) {
                    SecureField("", text: $updated)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .updated)
                }
                .overlay(alignment: .bottom) { focusRing(focused == .updated) }
            } footer: {
                // 板には無いが残す——決まりを知らずに打つと、送ってから断られる
                Text(AuthMessage.passwordRule)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            .jpFormRow()

            if let error = auth.errorMessage {
                Section { Text(error).foregroundStyle(WebTheme.danger).font(JPFont.body) }
                    .jpFormRow()
            }

            Section {
                Button {
                    Task {
                        auth.errorMessage = nil
                        if await auth.changePassword(current: current, new: updated) {
                            dismiss()
                        }
                    }
                } label: {
                    // 写真の無い画面の主ボタンは真鍮の塗り（owner「デザインの箇所は白より真鍮色が好き」（2026-09-29））
                    Text(L("変える", "Change"))
                        .jpPillButton(ChangePasswordLayout.submitStyle)
                }
                .buttonStyle(.plain)
                .disabled(auth.isWorking || current.isEmpty || updated.isEmpty)
                .opacity(auth.isWorking || current.isEmpty || updated.isEmpty ? 0.4 : 1)
            }
            .jpFormRow()
        }
        .webScreen()
        // 戻るボタンの文言のために題は持つが、バーの中央には出さない（板は左寄せの大見出しだけ・設定と同じ）
        .navigationTitle(L("パスワードを変える", "Change password"))
        // **前に開いたときの失敗を持ち越さない。** 失敗の文は共有の `auth.errorMessage`
        // なので、戻って開き直すと何も押していないのに赤い文が出ていた
        .onAppear { auth.errorMessage = nil }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        }
    }

    /// 入力中の欄の真鍮の縁（板 v2: 真鍮 1 の縁＋真鍮 18% の 3 の光）。欄（`JPField` の 48 の箱）の上に重ねる。
    /// **色だけでなく、カーソルと鍵盤でも入力中と分かる**
    private func focusRing(_ on: Bool) -> some View {
        ZStack {
            // 外の光（線の太さ 6 の半分＝3 が欄の外に出る）
            RoundedRectangle(cornerRadius: JPRadius.field)
                .stroke(WebTheme.accent.opacity(ChangePasswordLayout.focusGlowOpacity), lineWidth: 6)
            RoundedRectangle(cornerRadius: JPRadius.field)
                .strokeBorder(WebTheme.accent, lineWidth: JPStroke.hairline)
        }
            .frame(height: JPHeight.field)
            .opacity(on ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// パスワードを変える画面の決まり（v2 の板 ChangePassword）。テストで見張る
enum ChangePasswordLayout {
    /// 主ボタン: 写真の無い画面なので真鍮の塗りに墨
    static let submitStyle = JPPillStyle.main(onPhoto: false)
    /// 入力中の欄の外の光（板: 真鍮 18%・3pt）
    static let focusGlowOpacity = 0.18
}
