import SwiftUI

/// ログイン・新規登録・パスワードの再設定。1画面で切り替える。
///
/// **行き止まりを作らない。** 確認コードが届かない／パスワードを忘れた、の
/// 出口が無いと、その人はアカウントを作り直すしかなくなる。
struct SignInView: View {

    var reason: String?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    /// 登録のときの表示名。**入れないと、しばらく ID の頭8文字で呼ばれる**
    /// ——プロフィール行は登録時に作られるが、名前は入らない
    /// （`api/src/cognitoTrigger.ts` は `userId` と `createdAt` だけ書く）
    @State private var displayName = ""
    @State private var code = ""
    /// signUp が返す UUID。確認コードの送り先を指す
    @State private var pendingUsername: String?
    /// **端末に残る控え。** これが無いと、確認前にアプリを閉じた人が
    /// 二度と入れない（`PendingVerification` の長い注記）
    private let pending = PendingVerificationStore()
    /// 案内（送りました、など）。エラーとは別に出す
    @State private var notice: String?
    /// 「まだ確認していない」ことが分かったので、確認への入口を出す
    @State private var offerVerification = false

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
                Section { Text(reason).font(.callout).foregroundStyle(WebTheme.muted2) }
                    .listRowBackground(Color.clear)
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
                Section { Text(notice).font(.callout).foregroundStyle(WebTheme.muted2) }
                    .listRowBackground(Color.clear)
            }
            if let error = auth.errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.callout) }
                    .listRowBackground(Color.clear)
            }
            if offerVerification && pendingUsername == nil {
                Section {
                    Text(L("メールアドレスの確認がまだ終わっていません。",
                           "This email hasn't been verified yet."))
                        .font(.callout)
                    Button(L("確認コードを入力・再送する", "Enter or resend the code")) {
                        Task { await resumeVerification() }
                    }
                    .disabled(auth.isWorking)
                }
                .listRowBackground(Color.clear)
            }
        }
        // 実機の絵の道しるべ（`ScreenshotTests`）。**この画面が出ている回は、
        // 絵の名前にそう書く**——「14-マイページ」という名前で**ログイン画面**を
        // 撮っていた（run 55 まで）。名前と中身が食い違うと、見た人が
        // 「マイページはこういう画面だ」と誤読する
        .accessibilityIdentifier("signin.form")
        // **黒地にする。** 付け忘れていたので、ここだけ既定の灰色の
        // 段が並び、アプリの中で1枚だけ別のアプリに見えていた
        // （実機の絵で確認・run 38）
        .webScreen()
        .scrollContentBackground(.hidden)
    }

    // MARK: - ログイン・新規登録

    private var canSubmit: Bool {
        !auth.isWorking && !email.isEmpty && !password.isEmpty
    }

    /// 見出し付きの入力欄。**黒地の上で「押せる場所」を見せる**
    @ViewBuilder
    private func field<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
            content()
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .padding(.vertical, 4)
    }

    private var credentialsSection: some View {
        Group {
            Section {
                // **黒地では枠が要る。** 既定の入力欄は下線も背景も無く、
                // 黒の上では**どこを押すのか分からない**（実機の絵で確認）。
                // 見出しを添えて、枠と地を付ける
                field(L("メールアドレス", "Email")) {
                    TextField("", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                field(L("パスワード", "Password")) {
                    SecureField("", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                }
                if mode == .signUp {
                    field(L("表示名（あとで変えられます）", "Display name (you can change it later)")) {
                        TextField("", text: $displayName)
                            .textContentType(.name)
                    }
                }
            } footer: {
                if mode == .signUp {
                    Text(AuthMessage.passwordRule)
                }
            }
            .listRowBackground(Color.clear)

            Section {
                Button {
                    Task { await submitCredentials() }
                } label: {
                    // **いちばん押される場所を白い大ボタンに**（投稿と同じ作法）
                    Text(mode == .signIn ? Labels.Navigation.login : L("登録する", "Create account"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSubmit ? WebTheme.accentBackground : WebTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(canSubmit ? WebTheme.accentText : WebTheme.faint)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)

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
            .listRowBackground(Color.clear)
        }
    }

    private func submitCredentials() async {
        clearMessages()
        if mode == .signIn {
            await auth.signIn(email: email, password: password)
            // **未確認のまま戻ってきた人を、確認画面へ送る。**
            // 文言だけ出して入口が無いと、登録し直しても
            // 「すでに登録されています」で詰む（パスワード再設定も効かない）
            if auth.lastFailureWasUnconfirmed { await resumeVerification() }
            return
        }

        let username = await auth.signUp(email: email, password: password)
        if let username {
            // **UUID を端末に残す。** 画面の `@State` だけだと、
            // アプリを閉じた時点で送り直す手段が消える
            pending.remember(email: email, username: username,
                             displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines))
            pendingUsername = username
            return
        }
        // 「すでに登録されています」＝**確認前の自分**かもしれない
        if auth.lastFailureWasExistingAccount { await resumeVerification() }
    }

    /// 預かっていた表示名をプロフィールに入れる。
    ///
    /// **登録時にプロフィール行は作られるが、名前は入らない**
    /// （`api/src/cognitoTrigger.ts` が書くのは `userId` と `createdAt` だけ）。
    /// 入れないと、その人はしばらく ID の頭8文字で呼ばれる。
    /// **失敗してもログインは成功のまま**——あとからプロフィール編集で直せる。
    /// - Returns: 控えを捨ててよいか（入れ終えた／入れるものが無い）。
    @discardableResult
    private func applyDisplayName(_ name: String?) async -> Bool {
        guard let name, !name.isEmpty, auth.userId != nil else { return true }
        do {
            var patch = ProfilePatch()
            patch.displayName = name
            try await environment.profiles.update(patch)
            return true
        } catch {
            // 入れられなくてもログインは成功のまま（あとから編集で直せる）。
            // 控えは残すので、次のログインでもう一度試せる
            return false
        }
    }

    /// 控えてある UUID で確認画面に戻る。コードも送り直す。
    private func resumeVerification() async {
        guard let saved = pending.username(for: email) else { return }
        if await auth.resendSignUpCode(username: saved) {
            pendingUsername = saved
            notice = L("確認コードを送り直しました。メールをご確認ください。",
                       "We sent a new code. Please check your email.")
            return
        }
        // **捨てるのは「この控えはもう使えない」ときだけ。**
        // 回数制限や圏外で捨てると、唯一の手がかりを失う
        if auth.lastFailure.isPermanent {
            pending.forget(email: email)
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
                        let name = pending.displayName(for: email)
                        pendingUsername = nil
                        offerVerification = false
                        // 確認が済んだらそのままログインする。
                        // **失敗しても行き止まりにしない**——「すでに登録
                        // されています」から来た人は、登録欄に打った
                        // パスワードが古いものと違うことがある
                        await auth.signIn(email: email, password: password)
                        if auth.userId == nil {
                            notice = L("確認できました。パスワードを入れてログインしてください。",
                                       "Verified. Please sign in with your password.")
                            return
                        }
                        // **控えを捨てるのは、名前を入れ終えてから。**
                        // 先に捨てると、電波が悪くて1回落ちただけで
                        // 入れた名前が永久に消える（次のログインでやり直せない）
                        if await applyDisplayName(name) {
                            pending.forget(email: email)
                        }
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
        .listRowBackground(Color.clear)
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
            .listRowBackground(Color.clear)

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
            .listRowBackground(Color.clear)
        }
    }

    private func clearMessages() {
        notice = nil
        auth.errorMessage = nil
    }
}
