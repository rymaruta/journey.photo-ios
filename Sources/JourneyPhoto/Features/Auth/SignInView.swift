import SwiftUI

/// ログイン・新規登録・パスワードの再設定。1画面で切り替える。
///
/// **行き止まりを作らない。** 確認コードが届かない／パスワードを忘れた、の
/// 出口が無いと、その人はアカウントを作り直すしかなくなる。
struct SignInView: View {

    var reason: String?

    @EnvironmentObject private var auth: AuthStore
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    /// signUp が返す UUID。確認コードの送り先を指す
    @State private var pendingUsername: String?
    /// 案内（送りました、など）。エラーとは別に出す
    @State private var notice: String?

    enum Mode {
        case signIn
        case signUp
        /// パスワードの再設定：コード待ち
        case resetRequested
        /// パスワードの再設定：新しいパスワードを決める
        case resetConfirm
    }

    var body: some View {
        Form {
            if let reason {
                Section { Text(reason).font(.callout).foregroundStyle(.secondary) }
            }

            if let pendingUsername {
                confirmSignUpSection(username: pendingUsername)
            } else {
                switch mode {
                case .signIn, .signUp:
                    credentialsSection
                case .resetRequested, .resetConfirm:
                    resetSection
                }
            }

            if let notice {
                Section { Text(notice).font(.callout).foregroundStyle(.secondary) }
            }
            if let error = auth.errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.callout) }
            }
        }
    }

    // MARK: - ログイン・新規登録

    private var credentialsSection: some View {
        Group {
            Section {
                TextField(L("メールアドレス", "Email"), text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(L("パスワード", "Password"), text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
            } footer: {
                if mode == .signUp {
                    Text(AuthMessage.passwordRule)
                }
            }

            Section {
                Button(mode == .signIn ? Labels.Navigation.login : L("登録する", "Create account")) {
                    Task { await submitCredentials() }
                }
                .disabled(auth.isWorking || email.isEmpty || password.isEmpty)

                Button(mode == .signIn
                       ? L("アカウントを作る", "Create an account")
                       : L("ログインに戻る", "Back to sign in")) {
                    mode = mode == .signIn ? .signUp : .signIn
                    clearMessages()
                }
                .font(.footnote)

                if mode == .signIn {
                    Button(L("パスワードを忘れた", "Forgot password?")) {
                        mode = .resetRequested
                        clearMessages()
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private func submitCredentials() async {
        clearMessages()
        if mode == .signIn {
            await auth.signIn(email: email, password: password)
        } else {
            pendingUsername = await auth.signUp(email: email, password: password)
        }
    }

    // MARK: - 登録の確認

    private func confirmSignUpSection(username: String) -> some View {
        Section {
            Text(L("メールに届いた確認コードを入力してください", "Enter the code we emailed you"))
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField(L("確認コード", "Verification code"), text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)

            Button(L("登録を完了する", "Finish sign up")) {
                Task {
                    clearMessages()
                    if await auth.confirmSignUp(username: username, code: code) {
                        pendingUsername = nil
                        // 確認が済んだらそのままログインする
                        await auth.signIn(email: email, password: password)
                    }
                }
            }
            .disabled(auth.isWorking || code.isEmpty)

            // **届かないときの出口。** 無いと作り直すしかなくなる
            Button(L("コードを送り直す", "Send a new code")) {
                Task {
                    clearMessages()
                    if await auth.resendSignUpCode(username: username) {
                        notice = L("送り直しました。メールをご確認ください。",
                                   "Sent. Please check your email.")
                    }
                }
            }
            .font(.footnote)
            .disabled(auth.isWorking)
        }
    }

    // MARK: - パスワードの再設定

    private var resetSection: some View {
        Group {
            Section {
                TextField(L("メールアドレス", "Email"), text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(mode == .resetConfirm)

                if mode == .resetConfirm {
                    TextField(L("確認コード", "Verification code"), text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    SecureField(L("新しいパスワード", "New password"), text: $password)
                        .textContentType(.newPassword)
                }
            } footer: {
                Text(mode == .resetConfirm
                     ? AuthMessage.passwordRule
                     : L("登録したメールアドレスに、確認コードを送ります。",
                         "We'll email a verification code to your address."))
            }

            Section {
                if mode == .resetRequested {
                    Button(L("コードを送る", "Send code")) {
                        Task {
                            clearMessages()
                            if await auth.startPasswordReset(email: email) {
                                mode = .resetConfirm
                                notice = L("送りました。メールをご確認ください。",
                                           "Sent. Please check your email.")
                            }
                        }
                    }
                    .disabled(auth.isWorking || email.isEmpty)
                } else {
                    Button(L("パスワードを変える", "Change password")) {
                        Task {
                            clearMessages()
                            let done = await auth.confirmPasswordReset(
                                email: email, code: code, newPassword: password
                            )
                            if done {
                                // そのままログインまで通す（もう一度打たせない）
                                await auth.signIn(email: email, password: password)
                                if auth.userId == nil {
                                    mode = .signIn
                                    notice = L("変えました。新しいパスワードでログインしてください。",
                                               "Changed. Please sign in with your new password.")
                                }
                            }
                        }
                    }
                    .disabled(auth.isWorking || code.isEmpty || password.isEmpty)
                }

                Button(L("ログインに戻る", "Back to sign in")) {
                    mode = .signIn
                    code = ""
                    password = ""
                    clearMessages()
                }
                .font(.footnote)
            }
        }
    }

    private func clearMessages() {
        notice = nil
        auth.errorMessage = nil
    }
}
