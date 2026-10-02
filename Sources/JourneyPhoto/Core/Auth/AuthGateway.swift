import Foundation
import Amplify
import AWSCognitoAuthPlugin
// `AuthCognitoTokensProvider`（ID トークンを取り出す口）はこちらに居る。
// プラグイン側が再輸出している保証がないので明示的に入れる
import AWSPluginsCore

/// Cognito との入出力をここに閉じ込める。
///
/// **SRP を自前で実装しない。** Web 版は `amazon-cognito-identity-js` に
/// 任せている。iOS で同じことをするなら Amplify の Cognito プラグインが
/// 相当品で、トークンの更新と Keychain 保存まで面倒を見る。
///
/// **設定ファイル（amplifyconfiguration.json）は置かない。** プール ID は
/// ビルド構成で変わるので、JSON を1本置くと staging ビルドが本番プールを
/// 向く。`AppConfig` の値からその場で組み立てる。
enum AuthGateway {

    /// `private` にしない: 試験が「未設定の起動」を作るため。Xcode の試験はアプリの中で
    /// 走り、アプリが起動時に `configure()` を済ませているので、放っておくと
    /// 未設定の状態を試せない（本物の Cognito にログインしに行っていた・TestFlight run 163）
    static var isConfigured = false

    /// 🔴 **設定に失敗した起動では Amplify を呼ばない。** `configure()` が投げても起動は
    /// 続ける（公開の画面は出せる）が、その後 `restore()` などが Amplify を呼ぶと、
    /// 未設定の Amplify は処理を止める（`preconditionFailure`——手元に Amplify の
    /// ソースが無く、確かめてはいない）。ログインの口は「使えない」として返す
    struct NotConfigured: LocalizedError {
        var errorDescription: String? {
            L("ログインの設定を読み込めませんでした。アプリを入れ直してください",
              "Sign-in isn't configured. Please reinstall the app.")
        }
    }

    private static func requireConfigured() throws {
        guard isConfigured else { throw NotConfigured() }
    }

    /// アプリ起動時に一度だけ呼ぶ。
    static func configure() throws {
        guard !isConfigured else { return }
        let plugin: JSONValue = [
            "CognitoUserPool": [
                "Default": [
                    "PoolId": .string(AppConfig.cognitoUserPoolId),
                    "AppClientId": .string(AppConfig.cognitoClientId),
                    "Region": .string(AppConfig.cognitoRegion),
                ]
            ],
            "Auth": [
                "Default": [
                    // メールアドレスでログインする（プールは AliasAttributes: email）
                    "authenticationFlowType": .string("USER_SRP_AUTH"),
                ]
            ],
        ]
        let configuration = AmplifyConfiguration(
            auth: AuthCategoryConfiguration(plugins: ["awsCognitoAuthPlugin": plugin])
        )
        try Amplify.add(plugin: AWSCognitoAuthPlugin())
        try Amplify.configure(configuration)
        isConfigured = true
    }

    // MARK: - セッション

    /// いまログインしているか。
    static func isSignedIn() async -> Bool {
        guard isConfigured else { return false }
        return (try? await Amplify.Auth.fetchAuthSession().isSignedIn) ?? false
    }

    /// API Gateway に送る **ID トークン**。未ログインなら nil。
    ///
    /// 🔴 **ログインの期限切れを「ログアウト」に倒す。** 更新トークン（既定30日）が
    /// 切れても Amplify は `isSignedIn == true` を返し、トークンだけ
    /// `sessionExpired` で落ちる。そのまま投げると画面は「読み込めませんでした」
    /// を出し続け、ログイン中の見た目のまま何もできなくなっていた
    /// （`APIError.isAuthExpired` はどこからも呼ばれていなかった）。
    /// ここで `AuthStore` に知らせ、呼び手には「未ログイン」として nil を返す
    static func idToken() async throws -> String? {
        guard isConfigured else { return nil }
        let session: any AuthSession
        do {
            session = try await Amplify.Auth.fetchAuthSession()
        } catch {
            throw tokenFailure(error)
        }
        guard session.isSignedIn else { return nil }
        guard let provider = session as? AuthCognitoTokensProvider else { return nil }
        // **`switch` で分ける。** `do/catch … where` の catch の中で await すると、
        // Xcode 26.3 のコンパイラが SILGenCleanup で落ちた（run 148。Linux の
        // Swift 6.0 では通るので手元の検証では見つからない）
        switch provider.getCognitoTokens() {
        case .success(let tokens):
            return tokens.idToken
        case .failure(let error):
            guard AuthFailure(error) == .notAuthorized else { throw tokenFailure(error) }
            await announceSessionExpired()
            return nil
        }
    }

    /// ID トークンを取れなかった理由を、画面が読める形にする。
    ///
    /// 🔴 **通信による失敗は `APIError.unreachable` に包む。** 圏外で
    /// トークンを更新できない回に Amplify のエラーのまま投げていたので、
    /// `as? APIError` で読む画面は「通信できません」ではなく汎用の
    /// 「読み込めませんでした」を出していた。それ以外はそのまま投げる
    /// （ログインの期限切れは呼び出し元が `notAuthorized` で見分ける）
    ///
    /// 取り消し（`URLError.cancelled`）は、**呼んだ側が取り消されているときだけ**
    /// `CancellationError` にする（画面は取り消しを失敗と言わない）。Amplify の中の
    /// 通信は別の URLSession なので、呼び手が生きているのに `.cancelled` が来たら
    /// 失敗として出す——黙ると「まだ写真がありません」のような空の画面になる
    static func tokenFailure(_ error: Error) -> Error {
        let auth = error as? AuthError
        let url = (error as? URLError) ?? (auth?.underlyingError as? URLError)
        if url?.code == .cancelled, Task.isCancelled { return CancellationError() }
        if url != nil { return APIError.unreachable }
        if let auth, AuthFailure(auth) == .network { return APIError.unreachable }
        return error
    }

    @MainActor
    static func announceSessionExpired() {
        NotificationCenter.default.post(name: .authSessionExpired, object: nil)
    }

    /// サーバーに 401 を返された後の取り直し（`APIClient.send`）。**1本にまとめる**
    /// ——画面の口が一斉に 401 になっても、Cognito に頼むのは1回（`TokenRefresher`）
    static let refresher = TokenRefresher { try await forcedIdToken() }

    static func refreshedIdToken() async throws -> String? {
        guard isConfigured else { return nil }
        return try await refresher.refresh()
    }

    /// 手元の控えを使わず、Cognito から ID トークンを取り直す。
    ///
    /// 取り直せない（更新トークンも切れた・取り消された）回は nil。**ここでは知らせない**
    /// ——知らせるのは `APIClient` が「取り直せなかった」と決めたとき（`sessionExpired`）。
    /// 通信できない回は `tokenFailure` で `unreachable` にして投げる（ログアウトさせない）
    private static func forcedIdToken() async throws -> String? {
        let session: any AuthSession
        do {
            session = try await Amplify.Auth.fetchAuthSession(options: .forceRefresh())
        } catch {
            throw tokenFailure(error)
        }
        guard session.isSignedIn,
              let provider = session as? AuthCognitoTokensProvider else { return nil }
        switch provider.getCognitoTokens() {
        case .success(let tokens):
            return tokens.idToken
        case .failure(let error):
            guard AuthFailure(error) == .notAuthorized else { throw tokenFailure(error) }
            return nil
        }
    }

    /// ログインの期限が切れているか（起動時の確認用・知らせは出さない）。
    /// **確かめられなかった回は false**——圏外の人をログアウトさせない
    static func isSessionExpired() async -> Bool {
        guard isConfigured, let session = try? await Amplify.Auth.fetchAuthSession(),
              session.isSignedIn,
              let provider = session as? AuthCognitoTokensProvider else { return false }
        switch provider.getCognitoTokens() {
        case .success:
            return false
        case .failure(let error):
            return AuthFailure(error) == .notAuthorized
        }
    }

    static func currentUserId() async throws -> String {
        try requireConfigured()
        return try await Amplify.Auth.getCurrentUser().userId
    }

    /// Cognito のユーザー名（登録のときの UUID・`signUp`）。`userId`（sub）とは別
    static func currentUsername() async throws -> String {
        try await Amplify.Auth.getCurrentUser().username
    }

    // MARK: - 登録・ログイン

    /// 新規登録。
    ///
    /// **ユーザー名は UUID、メールは属性として渡す。** このプールは
    /// `AliasAttributes: email` で作られていて（作成後に変更できない）、
    /// Web 版も同じことをしている（`lib/auth/cognito.ts` の `signUp`）。
    /// メールをそのままユーザー名にすると、あとでメールを変えられなくなる。
    ///
    /// - Returns: 確認コードの送り先を指す UUID。`confirmSignUp` に渡す。
    @discardableResult
    static func signUp(email: String, password: String) async throws -> String {
        // **前後の空白を落とす。** スマホのキーボードは補完のあとに空白を
        // 付けることがあり、そのまま登録すると確認コードは届くのに
        // ログインで打ち直したメールと一致しない（Web 側で踏んだ）。
        // 大文字小文字はここでは触らない——プールの `UsernameConfiguration`
        // が未確認で、揃え方を間違えると既存アカウントが入れなくなる。
        try requireConfigured()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = UUID().uuidString
        let options = AuthSignUpRequest.Options(
            userAttributes: [AuthUserAttribute(.email, value: trimmed)]
        )
        _ = try await Amplify.Auth.signUp(username: username, password: password, options: options)
        return username
    }

    /// メールに届いた確認コードで登録を確定する。username は signUp が返した UUID。
    static func confirmSignUp(username: String, code: String) async throws {
        try requireConfigured()
        _ = try await Amplify.Auth.confirmSignUp(for: username, confirmationCode: code)
    }

    static func resendSignUpCode(username: String) async throws {
        try requireConfigured()
        _ = try await Amplify.Auth.resendSignUpCode(for: username)
    }

    /// ログイン。username にはメールアドレスを渡す（エイリアス）。
    /// - Returns: 完了したら true。未確認アカウントなどで続きが要るなら false。
    ///
    /// 🔴 **未確認のアカウントは「投げる」に揃える。** Amplify Swift v2 は
    /// 未確認の人に `userNotConfirmed` を投げず、`nextStep == .confirmSignUp` を
    /// 返す。戻り値を捨てていたので、確認コードの画面へ進む分岐
    /// （`lastFailureWasUnconfirmed`）が一度も当たらなかった
    @discardableResult
    static func signIn(email: String, password: String) async throws -> Bool {
        try requireConfigured()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await Amplify.Auth.signIn(username: trimmed, password: password)
        return try outcome(of: result.nextStep, isSignedIn: result.isSignedIn)
    }

    /// ログインの答えの次の段から、結果を決める。
    ///
    /// 🔴 **続きの段を黙って捨てない。** `.confirmSignUp` しか見ていなかったので、管理者が
    /// パスワードを再設定した人（`.resetPassword`）やコンソールで作られた人（新しいパスワードの
    /// 設定待ち）は、false が捨てられて「しばらくしてからもう一度」が出るだけで、待っても
    /// 押し直しても進めなかった（Web は再設定へ案内している）
    static func outcome(of step: AuthSignInStep, isSignedIn: Bool) throws -> Bool {
        switch step {
        case .done:
            return isSignedIn
        case .confirmSignUp:
            throw AuthError.service("", "", AWSCognitoAuthError.userNotConfirmed)
        case .resetPassword:
            throw SignInIncomplete.passwordResetRequired
        default:
            // アプリで続けられない段（新しいパスワードの設定・多要素認証など）
            throw SignInIncomplete.unsupportedStep
        }
    }


    static func signOut() async {
        guard isConfigured else { return }
        _ = await Amplify.Auth.signOut()
    }

    /// Cognito の利用者そのものを消す。**サーバーの `DELETE /user/account` は
    /// Cognito を消さない**（データと墓石だけ）——Web も同じく画面側で消している
    /// （`lib/auth/cognito.ts` の `deleteAccount`）。消さないと、退会したのに
    /// 同じメールとパスワードでログインでき、そのメールで登録し直すこともできない
    static func deleteUser() async throws {
        try requireConfigured()
        try await Amplify.Auth.deleteUser()
    }

    // MARK: - パスワード

    static func resetPassword(email: String) async throws {
        try requireConfigured()
        _ = try await Amplify.Auth.resetPassword(
            for: email.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// ログインしたままパスワードを変える。
    static func changePassword(current: String, new: String) async throws {
        try requireConfigured()
        try await Amplify.Auth.update(oldPassword: current, to: new)
    }

    static func confirmResetPassword(email: String, newPassword: String, code: String) async throws {
        try requireConfigured()
        try await Amplify.Auth.confirmResetPassword(
            for: email.trimmingCharacters(in: .whitespacesAndNewlines),
            with: newPassword,
            confirmationCode: code
        )
    }
}

/// `APIClient` に渡すトークンの出どころ。
struct CognitoTokenProvider: TokenProviding {
    func idToken() async throws -> String? {
        try await AuthGateway.idToken()
    }

    func refreshedIdToken() async throws -> String? {
        try await AuthGateway.refreshedIdToken()
    }

    /// 取り直しても 401。`AuthStore` が受けてログアウトに倒す
    func sessionExpired() async {
        await AuthGateway.announceSessionExpired()
    }
}

extension Notification.Name {
    /// ログインの期限が切れた（`AuthGateway.idToken`）。`AuthStore` が受けてログアウトに倒す
    static let authSessionExpired = Notification.Name("jp.authSessionExpired")
}
