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
                Section("安全") {
                    NavigationLink("ブロックした人") { BlockedUsersView() }
                }
            }

            Section("このアプリについて") {
                Link("利用規約", destination: LegalConsent.termsURL)
                Link("プライバシーポリシー", destination: LegalConsent.privacyURL)
                if let contact = LegalConsent.contactURL {
                    Link("問い合わせ", destination: contact)
                }
                HStack {
                    Text("バージョン")
                    Spacer()
                    Text(version).foregroundStyle(.secondary)
                }
                if AppConfig.environment == .staging {
                    HStack {
                        Text("接続先")
                        Spacer()
                        Text("staging").foregroundStyle(.orange)
                    }
                }
            }

            if auth.userId != nil {
                Section {
                    Button("ログアウト") { Task { await auth.signOut() } }
                }
                Section {
                    NavigationLink("アカウントの削除") { DeleteAccountView() }
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("設定")
    }
}
