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


    /// ログアウト。**結果を見る**（以前は `_ =` で捨てていた）。
    ///
    /// Amplify の `signOut` は投げずに結果を返す。Cognito では `AWSCognitoSignOutResult` で、
    /// `.failed` は**端末の中のログイン（Keychain の控え）も消せていない**——画面だけ
    /// ログアウトして、次の起動の `restore` で黙ってログイン中に戻っていた。
    /// `.partial` はサーバー側の取り消しだけが落ちた回で、端末からは消えている。
    ///
    /// 消せなかったらもう一度だけ試す。それでも駄目なら `SignOutLatch` に印を残す
    /// （→ `SignOutLatch` の「2026-10-02 判断」）
    @discardableResult
    static func signOut() async -> SignOutOutcome {
        guard isConfigured else { return .signedOut }
        return await signOut(
            attempt: { signedOutLocally(await Amplify.Auth.signOut()) },
            latch: SignOutLatch()
        )
    }

    /// 上の流れの本体（試験が Amplify の代わりの `attempt` を渡す）。
    /// - Parameter attempt: 1回ログアウトを頼み、端末から消せたら true
    static func signOut(attempt: () async -> Bool, latch: SignOutLatch) async -> SignOutOutcome {
        for _ in 0..<2 {
            if await attempt() {
                latch.clear()
                return .signedOut
            }
        }
        latch.set()
        return .notClearedLocally
    }

    /// 端末の中のログインが消えたか。**分からない形の結果は「消えた」と読む**
    /// ——消えていないと読むと、次の起動からずっとログインできない側へ倒れる
    static func signedOutLocally(_ result: any AuthSignOutResult) -> Bool {
        guard let cognito = result as? AWSCognitoSignOutResult else { return true }
        switch cognito {
        case .failed:
            return false
        case .complete, .partial:
            return true
        }
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

/// ログアウトの結果（`AuthGateway.signOut`）
enum SignOutOutcome: Equatable {
    case signedOut
    /// 2回頼んでも端末の中のログインを消せなかった（`SignOutLatch` に印を残した）
    case notClearedLocally
}

/// **端末の中のログインを消せなかった**印。
///
/// 🔴 **2026-10-02 判断:** Amplify の `signOut` が2回とも `.failed`（Keychain の控えを
/// 消せない）だったときは、**画面はログアウトの扱いのまま**にし、この印を
/// `UserDefaults` に残す。次の起動の `AuthStore.restore` は、Amplify が「ログイン中」と
/// 答えても印があればログイン中に戻さず、もう一度ログアウトを試してから
/// 未ログインとして始める（本人が押したログアウトを、起動し直しただけで黙って
/// 取り消さない）。印はログアウトが通った回・本人がログインし直せた回に外す。
///
/// **印は消せなかった回数を数え、`limit` 回に達したら諦める（2026-10-02 判断）。**
/// `.failed` が続く端末では、起動時の消し直しもログイン前の消し直しも落ち、Amplify は
/// 前の人でログイン中のまま——`signIn` は「既にログイン中」（invalidState）で断るので、
/// 印を持ち続けると**誰もログインできない抜け道の無い状態**になる。`limit` に達した
/// 起動では印を外し、印の無かった頃と同じ挙動（Amplify の答えどおりログイン中に戻る）
/// に倒す。本人のログアウトが1度取り消されることになるが、閉じ込めるよりはよい。
///
/// **ログイン前の消し直しが落ちて `signIn` が invalidState を返したときは、通さない
/// （2026-10-02 判断）。** 残っているのは前の人のログインで、いま打たれたメールと
/// パスワードは Cognito で確かめられていない——同じメールでも「同じ人」とは言えず、
/// 前の人のログインをそのまま渡すと、メールを知っているだけの人が入れてしまう。
/// 「アプリを開き直して」と案内し（`AuthFailure.alreadySignedIn`）、開き直しの消し直しで
/// 数を進める。`limit` に達すれば上のとおり前の人のログインに戻り、そこからログアウト
/// し直せる。
///
/// Keychain ではなく `UserDefaults` に置くのは、消せなかった相手が Keychain だから
/// （同じ所に書けない回がある）。アプリを入れ直すと印は消えるが、そのとき Amplify の
/// 控えがどうなるかは確かめていない
struct SignOutLatch: @unchecked Sendable {  // UserDefaults は複数のスレッドから読み書きしてよい
    static let key = "jp-signout-not-cleared"
    /// 消せなかった回数がこれに達したら諦める
    static let limit = 3
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 消せなかった回数（印の無いときは 0）
    var count: Int { defaults.integer(forKey: Self.key) }
    var isSet: Bool { count > 0 }
    /// 消せなかった。回数を1つ進める
    func set() { defaults.set(count + 1, forKey: Self.key) }
    func clear() { defaults.removeObject(forKey: Self.key) }

    /// 上限に達していれば印を外して true（＝もう印に従わない）
    func giveUpIfExhausted() -> Bool {
        guard count >= Self.limit else { return false }
        clear()
        return true
    }
}

extension Notification.Name {
    /// ログインの期限が切れた（`AuthGateway.idToken`）。`AuthStore` が受けてログアウトに倒す
    static let authSessionExpired = Notification.Name("jp.authSessionExpired")
    /// 自分のプロフィールが 410（退会の途中で止まったアカウント・`ProfileService.myProfile`）。
    /// `AuthStore` が受けて、退会の残り（Cognito の削除・端末の控え）を済ませる
    static let accountDeletionPending = Notification.Name("jp.accountDeletionPending")
}
