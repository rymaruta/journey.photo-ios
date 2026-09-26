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
    /// 上に敷く写真のタイル（板 41 の 3×3）。取れなければ地の色のまま
    @State private var tiles: [Photo] = []

    enum Mode {
        case signIn
        case signUp
        /// パスワードの再設定：コード待ち
        case resetRequested
        /// パスワードの再設定：新しいパスワードを決める
        case resetConfirm
    }

    var body: some View {
        // 板 41: 上に写真のタイル、その下へ溶かしてロゴと一文、欄、2つの大きいボタン
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                tileHeader
                VStack(alignment: .leading, spacing: 14) {
                    brand
                    if let reason {
                        Text(reason).font(.callout).foregroundStyle(WebTheme.muted2)
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
                        Text(notice).font(.callout).foregroundStyle(WebTheme.muted2)
                    }
                    if let error = auth.errorMessage {
                        Text(error).foregroundStyle(WebTheme.danger).font(.callout)
                    }
                    if offerVerification && pendingUsername == nil {
                        verificationOffer
                    }
                }
                .padding(.horizontal, 24)
                // 写真の下の暗がりに重ねる（板は写真 340 の上から 262 で本文が始まる）
                .padding(.top, -78)
                .padding(.bottom, 30)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        // 実機の絵の道しるべ（`ScreenshotTests`）。**この画面が出ている回は、
        // 絵の名前にそう書く**——「14-マイページ」という名前で**ログイン画面**を
        // 撮っていた（run 55 まで）。名前と中身が食い違うと、見た人が
        // 「マイページはこういう画面だ」と誤読する
        .accessibilityIdentifier("signin.form")
        // **黒地にする。** 付け忘れていたので、ここだけ既定の灰色の
        // 段が並び、アプリの中で1枚だけ別のアプリに見えていた
        // （実機の絵で確認・run 38）
        .webScreen()
        .task { await loadTiles() }
    }

    // MARK: - 上の写真とロゴ

    /// 3×3 の写真（板: 高さ340・隙間3、下 212 を黒へ溶かす）。飾りなので読み上げない
    private var tileHeader: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(0..<9, id: \.self) { index in
                tile(index < tiles.count ? tiles[index] : nil)
            }
        }
        .frame(height: 340, alignment: .top)
        .clipped()
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [Color.black.opacity(0), Color.black],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 212)
        }
        .accessibilityHidden(true)
    }

    /// 1枚。**読めたときだけ描く**（読み込み中の回転や壊れた記号を並べない）
    private func tile(_ photo: Photo?) -> some View {
        WebTheme.surface
            .frame(height: 112)
            .overlay {
                if let photo {
                    AsyncImage(url: photo.gridImageURL,
                               transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if case .success(let image) = phase {
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: photo.gridAlignment)
                        }
                    }
                }
            }
            .clipped()
    }

    /// 大きいロゴと一文（板: マーク＋serif 40・「旅の写真を、一冊の記録に。」）
    private var brand: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image("BrandMark")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundStyle(WebTheme.foreground)
                Text("Journey Photo")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .tracking(-1.0)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Journey Photo")
            .accessibilityAddTraits(.isHeader)
            Text(L("旅の写真を、一冊の記録に。", "Your travels, bound into one book."))
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
        }
        .padding(.bottom, 6)
    }

    /// 公開一覧の先頭9枚（端末で落とした人・写真は一覧の側で除かれている）。
    /// **失敗しても黙る**（飾りなので、地の色のまま）
    private func loadTiles() async {
        guard tiles.isEmpty, let photos = try? await environment.gallery.fetchPhotos() else { return }
        tiles = Array(photos.filter { $0.gridImageURL != nil }.prefix(9))
    }

    private var verificationOffer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("メールアドレスの確認がまだ終わっていません。",
                   "This email hasn't been verified yet."))
                .font(.callout)
            Button {
                Task { await resumeVerification() }
            } label: {
                // 形は**中身の側**に付ける（`.plain` は外の枠を押せる範囲にしない）
                Text(L("確認コードを入力・再送する", "Enter or resend the code"))
                    .jpPillButton(.outline)
            }
            .buttonStyle(.plain)
            .disabled(auth.isWorking)
            .opacity(auth.isWorking ? 0.4 : 1)
        }
    }

    // MARK: - ログイン・新規登録

    private var canSubmit: Bool {
        !auth.isWorking && !email.isEmpty && !password.isEmpty
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // **黒地では枠が要る。** 既定の入力欄は下線も背景も無く、
            // 黒の上では**どこを押すのか分からない**（実機の絵で確認）
            JPField(L("メールアドレス", "Email")) {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            JPField(L("パスワード", "Password")) {
                SecureField("", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
            }
            if mode == .signUp {
                JPField(L("表示名（あとで変えられます）", "Display name (you can change it later)")) {
                    TextField("", text: $displayName)
                        .textContentType(.name)
                }
                Text(AuthMessage.passwordRule)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
            }
            if mode == .signIn {
                // 板: 欄の下に右寄せ・13px・白72%
                Button {
                    mode = .resetRequested
                    clearMessages()
                } label: {
                    // 押せる範囲は文字の周りの 44pt（外に付けた枠は広げない）
                    Text(L("パスワードを忘れた", "Forgot password?"))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted2)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // **いちばん押される場所を白い大ボタンに**（板: 52pt・白のカプセル）
            Button {
                Task { await submitCredentials() }
            } label: {
                Text(mode == .signIn ? Labels.Navigation.login : L("登録する", "Create account"))
                    .jpPillButton()
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.4)

            // 2番手は枠線のカプセル（板）
            Button {
                mode = mode == .signIn ? .signUp : .signIn
                clearMessages()
            } label: {
                Text(mode == .signIn
                     ? L("アカウントを作る", "Create an account")
                     : L("ログインに戻る", "Back to sign in"))
                    .jpPillButton(.outline)
            }
            .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 14) {
            Text(L("メールに届いた確認コードを入力してください", "Enter the code we emailed you"))
                .font(.callout)
                .foregroundStyle(WebTheme.muted2)
            JPField(L("確認コード", "Verification code")) {
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            }

            Button {
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
            } label: {
                Text(L("登録を完了する", "Finish sign up")).jpPillButton()
            }
            .buttonStyle(.plain)
            .disabled(auth.isWorking || code.isEmpty)
            .opacity(auth.isWorking || code.isEmpty ? 0.4 : 1)

            // **届かないときの出口。** 無いと作り直すしかなくなる
            Button {
                Task {
                    clearMessages()
                    if await auth.resendSignUpCode(username: username) {
                        notice = L("送り直しました。メールをご確認ください。",
                                   "Sent. Please check your email.")
                    }
                }
            } label: {
                Text(L("コードを送り直す", "Send a new code"))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted2)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .disabled(auth.isWorking)
        }
    }

    // MARK: - パスワードの再設定

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            JPField(L("メールアドレス", "Email")) {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(mode == .resetConfirm)
            }
            if mode == .resetConfirm {
                JPField(L("確認コード", "Verification code")) {
                    TextField("", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                }
                JPField(L("新しいパスワード", "New password")) {
                    SecureField("", text: $password)
                        .textContentType(.newPassword)
                }
            }
            Text(mode == .resetConfirm
                 ? AuthMessage.passwordRule
                 : L("登録したメールアドレスに、確認コードを送ります。",
                     "We'll email a verification code to your address."))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)

            if mode == .resetRequested {
                Button {
                    Task {
                        clearMessages()
                        if await auth.startPasswordReset(email: email) {
                            mode = .resetConfirm
                            notice = L("送りました。メールをご確認ください。",
                                       "Sent. Please check your email.")
                        }
                    }
                } label: {
                    Text(L("コードを送る", "Send code")).jpPillButton()
                }
                .buttonStyle(.plain)
                .disabled(auth.isWorking || email.isEmpty)
                .opacity(auth.isWorking || email.isEmpty ? 0.4 : 1)
            } else {
                Button {
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
                } label: {
                    Text(L("パスワードを変える", "Change password")).jpPillButton()
                }
                .buttonStyle(.plain)
                .disabled(auth.isWorking || code.isEmpty || password.isEmpty)
                .opacity(auth.isWorking || code.isEmpty || password.isEmpty ? 0.4 : 1)
            }

            Button {
                mode = .signIn
                code = ""
                password = ""
                clearMessages()
            } label: {
                Text(L("ログインに戻る", "Back to sign in")).jpPillButton(.outline)
            }
            .buttonStyle(.plain)
        }
    }

    private func clearMessages() {
        notice = nil
        auth.errorMessage = nil
    }
}
