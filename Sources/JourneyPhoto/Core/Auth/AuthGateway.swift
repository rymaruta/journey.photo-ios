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

    private static var isConfigured = false

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
        (try? await Amplify.Auth.fetchAuthSession().isSignedIn) ?? false
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
    /// 取り消し（`URLError.cancelled`）は `CancellationError` にする（`APIClient` と同じ。
    /// 画面は取り消しを失敗と言わない）
    static func tokenFailure(_ error: Error) -> Error {
        let auth = error as? AuthError
        let url = (error as? URLError) ?? (auth?.underlyingError as? URLError)
        if url?.code == .cancelled { return CancellationError() }
        if url != nil { return APIError.unreachable }
        if let auth, AuthFailure(auth) == .network { return APIError.unreachable }
        return error
    }

    @MainActor
    private static func announceSessionExpired() {
        NotificationCenter.default.post(name: .authSessionExpired, object: nil)
    }

    /// ログインの期限が切れているか（起動時の確認用・知らせは出さない）。
    /// **確かめられなかった回は false**——圏外の人をログアウトさせない
    static func isSessionExpired() async -> Bool {
        guard let session = try? await Amplify.Auth.fetchAuthSession(),
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
        try await Amplify.Auth.getCurrentUser().userId
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
        _ = try await Amplify.Auth.confirmSignUp(for: username, confirmationCode: code)
    }

    static func resendSignUpCode(username: String) async throws {
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
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await Amplify.Auth.signIn(username: trimmed, password: password)
        if case .confirmSignUp = result.nextStep {
            throw AuthError.service("", "", AWSCognitoAuthError.userNotConfirmed)
        }
        return result.isSignedIn
    }

    static func signOut() async {
        _ = await Amplify.Auth.signOut()
    }

    /// Cognito の利用者そのものを消す。**サーバーの `DELETE /user/account` は
    /// Cognito を消さない**（データと墓石だけ）——Web も同じく画面側で消している
    /// （`lib/auth/cognito.ts` の `deleteAccount`）。消さないと、退会したのに
    /// 同じメールとパスワードでログインでき、そのメールで登録し直すこともできない
    static func deleteUser() async throws {
        try await Amplify.Auth.deleteUser()
    }

    // MARK: - パスワード

    static func resetPassword(email: String) async throws {
        _ = try await Amplify.Auth.resetPassword(
            for: email.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// ログインしたままパスワードを変える。
    static func changePassword(current: String, new: String) async throws {
        try await Amplify.Auth.update(oldPassword: current, to: new)
    }

    static func confirmResetPassword(email: String, newPassword: String, code: String) async throws {
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
}

extension Notification.Name {
    /// ログインの期限が切れた（`AuthGateway.idToken`）。`AuthStore` が受けてログアウトに倒す
    static let authSessionExpired = Notification.Name("jp.authSessionExpired")
}
