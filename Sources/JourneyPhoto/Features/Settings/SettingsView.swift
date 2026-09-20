import SwiftUI

/// 設定。**審査で必要な導線をここに集める**
/// （規約・プライバシー・ブロック一覧・退会・問い合わせ）。
struct SettingsView: View {

    @EnvironmentObject private var auth: AuthStore

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            if auth.userId != nil {
                Section(L("安全", "Safety")) {
                    NavigationLink(L("ブロックした人", "Blocked people")) { BlockedUsersView() }
                }
            }

            Section(L("このアプリについて", "About")) {
                Link(L("利用規約", "Terms of Use"), destination: LegalConsent.termsURL)
                Link(L("プライバシーポリシー", "Privacy Policy"), destination: LegalConsent.privacyURL)
                if let contact = LegalConsent.contactURL {
                    Link(L("問い合わせ", "Contact"), destination: contact)
                }
                HStack {
                    Text(L("バージョン", "Version"))
                    Spacer()
                    Text(version).foregroundStyle(.secondary)
                }
                if AppConfig.environment == .staging {
                    HStack {
                        Text(L("接続先", "Environment"))
                        Spacer()
                        Text("staging").foregroundStyle(.orange)
                    }
                }
            }

            if auth.userId != nil {
                Section {
                    NavigationLink(L("パスワードを変える", "Change password")) { ChangePasswordView() }
                    Button(Labels.Navigation.logout) { Task { await auth.signOut() } }
                }
                Section {
                    NavigationLink(L("アカウントの削除", "Delete account")) { DeleteAccountView() }
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(L("設定", "Settings"))
    }
}
