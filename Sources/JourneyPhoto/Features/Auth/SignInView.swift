import SwiftUI

/// ログインと新規登録。1画面で切り替える。
struct SignInView: View {

    var reason: String?

    @EnvironmentObject private var auth: AuthStore
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    /// signUp が返す UUID。確認コードの送り先を指す
    @State private var pendingUsername: String?

    enum Mode { case signIn, signUp }

    var body: some View {
        Form {
            if let reason {
                Section { Text(reason).font(.callout).foregroundStyle(.secondary) }
            }

            if let pendingUsername {
                confirmSection(username: pendingUsername)
            } else {
                credentialsSection
            }

            if let error = auth.errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.callout) }
            }
        }
    }

    private var credentialsSection: some View {
        Group {
            Section {
                TextField("メールアドレス", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("パスワード", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
            } footer: {
                if mode == .signUp {
                    Text(AuthMessage.passwordRule)
                }
            }

            Section {
                Button(mode == .signIn ? "ログイン" : "登録する") {
                    Task {
                        if mode == .signIn {
                            await auth.signIn(email: email, password: password)
                        } else {
                            pendingUsername = await auth.signUp(email: email, password: password)
                        }
                    }
                }
                .disabled(auth.isWorking || email.isEmpty || password.isEmpty)

                Button(mode == .signIn ? "アカウントを作る" : "ログインに戻る") {
                    mode = mode == .signIn ? .signUp : .signIn
                    auth.errorMessage = nil
                }
                .font(.footnote)
            }
        }
    }

    private func confirmSection(username: String) -> some View {
        Section {
            Text("メールに届いた確認コードを入力してください")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("確認コード", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            Button("登録を完了する") {
                Task {
                    if await auth.confirmSignUp(username: username, code: code) {
                        pendingUsername = nil
                        // 確認が済んだらそのままログインする
                        await auth.signIn(email: email, password: password)
                    }
                }
            }
            .disabled(auth.isWorking || code.isEmpty)
        }
    }
}
