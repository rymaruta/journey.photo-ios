import SwiftUI

/// 設定。**審査で必要な導線をここに集める**
/// （規約・プライバシー・ブロック一覧・退会・問い合わせ）。
struct SettingsView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushCenter
    @State private var wantsPush = false
    @State private var showDeniedHint = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        list
            .task {
                await push.refreshAuthorization()
                // **サーバーに預けてあるかで見る。** 端末が許可していても
                // 宛先を預けていなければ届かない＝「オン」と言ってはいけない
                wantsPush = push.isRegistered
            }
    }

    /// 受け取る／受け取らないを切り替える。
    private func apply(on: Bool) async {
        showDeniedHint = false
        if on {
            let granted = await push.enable()
            // **断られたら見た目も戻す**（オンのまま届かない、を作らない）
            wantsPush = granted && push.isRegistered
            showDeniedHint = !granted
        } else {
            await push.disable()
            wantsPush = false
        }
    }

    private var list: some View {
        List {
            if auth.userId != nil {
                Section {
                    Toggle(L("プッシュ通知を受け取る", "Push notifications"), isOn: $wantsPush)
                        .onChange(of: wantsPush) { _, on in
                            Task { await apply(on: on) }
                        }
                    if showDeniedHint {
                        // **端末の許可は取り消せない。** 断られたあとは
                        // 設定アプリへ行ってもらうしかない——黙って
                        // 戻るだけだと「押しても何も起きない」に見える
                        Text(L("この端末で通知が許可されていません。iPhone の「設定 → 通知 → Journey Photo」から許可してください。",
                               "Notifications are off for this device. Allow them in Settings → Notifications → Journey Photo."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let message = push.errorMessage {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text(L("お知らせ", "Activity"))
                } footer: {
                    Text(L("いいね・コメント・フォロー・ストーリーへの返信を、アプリを開いていなくても受け取れます。",
                           "Get likes, comments, follows and story replies even when the app is closed."))
                }

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
                    Button(Labels.Navigation.logout) {
                        Task {
                            // **通知の宛先は、ログアウトの前に外す。**
                            // あとだと認証が通らず、外せないまま次にこの端末を
                            // 使う人へ前の人あての通知が飛ぶ
                            await push.signingOut()
                            await auth.signOut()
                        }
                    }
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
