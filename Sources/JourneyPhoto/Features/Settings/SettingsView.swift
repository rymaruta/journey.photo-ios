import SwiftUI

/// 設定。**審査で必要な導線をここに集める**
/// （規約・プライバシー・ブロック一覧・退会・問い合わせ）。
struct SettingsView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushCenter
    @State private var wantsPush = false
    @State private var showDeniedHint = false
    /// 切り替えている最中。二度押しで登録と解除が交差しないようにする
    @State private var isApplying = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        list
            .task {
                await push.refreshAuthorization()
                // **本人の意思で見る。** 「預けられたか」で見ると、
                // シミュレータや圏外では必ず false になり、画面に入り直す
                // たびにオフへ戻る。端末の許可だけで見ると、オフにしたのに
                // 復活する（OS の許可は残る）
                wantsPush = push.isEnabled && push.isAuthorized
            }
    }

    /// 受け取る／受け取らないを切り替える。
    /// 押されたあとの本体（門は呼ぶ側で閉じてある）。
    private func apply(on: Bool) async {
        showDeniedHint = false
        defer { isApplying = false }
        if on {
            // **許可されたかだけで決める。** 宛先を預け終えたかで見ると、
            // APNs のトークンは少し遅れて届くので**必ず false になる**
            // ——押した直後に自分でオフへ戻る
            let granted = await push.enable()
            wantsPush = granted
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
                    // **`onChange` で拾わない。** 画面側から `wantsPush` を
                    // 戻したときにも発火し、**許可した直後に自分でオフへ
                    // 戻す**（`enable()` の返りは APNs のトークンより先に来る）。
                    // 押された瞬間だけを受ける形にする
                    Toggle(L("プッシュ通知を受け取る", "Push notifications"),
                           isOn: Binding(get: { wantsPush },
                                         set: { on in
                                             // **門は同期で閉じる。** `Task` の
                                             // 中で立てると、連打の2発目が来る
                                             // 時点ではまだ開いている
                                             guard !isApplying else { return }
                                             isApplying = true
                                             wantsPush = on
                                             Task { await apply(on: on) }
                                         }))
                        .disabled(isApplying)
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
        .webScreen()
        .navigationTitle(L("設定", "Settings"))
    }
}
