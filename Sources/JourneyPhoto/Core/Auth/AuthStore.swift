import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine
import Amplify
import AWSCognitoAuthPlugin

/// ログイン状態を画面に配る。
@MainActor
final class AuthStore: ObservableObject {

    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(userId: String)
    }

    @Published private(set) var state: State = .unknown
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false

    var userId: String? {
        if case .signedIn(let id) = state { return id }
        return nil
    }

    /// まだ分かっていない（起動直後の確認中）。
    ///
    /// **`userId == nil` だけで判断しない。** 確認が終わる前に
    /// 「ログインしてください」を出すと、ログイン済みの人にも一瞬それが
    /// 見える（Web 側の「確かめられなかった回に案内を出さない」と同じ話）。
    var isResolving: Bool { state == .unknown }

    /// 起動時に一度。**「確かめられなかった」と「ログインしていない」を
    /// 混ぜない**——圏外なだけの人をログイン画面に飛ばさないため、
    /// 判定できない回は `.unknown` のままにする。
    func restore() async {
        #if DEBUG
        // **絵を撮るためだけの、鍵を持たないログイン**（Debug のみ・owner 承認済み）。
        //
        // CI の巡回はログインしない（資格情報が無い）ので、マイページは
        // **実機の絵を1枚も撮れていなかった**——`docs/MOCK_PARITY.md` が
        // その1画面だけ ❌ にしていた理由。
        //
        // ここで入れるのは**利用者 ID だけ**で、トークンは1つも作らない:
        //
        //  - 公開の写真から「この人のぶん」を選り分ける画面（作品の格子・
        //    訪問した国・数え）は**本物のデータで描かれる**
        //  - 鍵の要る口（ハイライト・行きたい場所・投稿）は 401 になり、
        //    画面はその「取れなかった」側を出す。**嘘の中身は出ない**
        //
        // **Release には入らない**（`#if DEBUG`）。TestFlight に上げる
        // ビルドは Release なので、出荷物にこの口は無い。既存の
        // `-JPSiteBaseURL`（`AppConfig`）とまったく同じ形。
        // 渡す値は公開 API が返している `userId` そのもので、資格情報ではない。
        if let previewId = PreviewSession.userId {
            state = .signedIn(userId: previewId)
            return
        }
        #endif
        guard await AuthGateway.isSignedIn() else {
            state = .signedOut
            return
        }
        let id = try? await AuthGateway.currentUserId()
        if let id {
            state = .signedIn(userId: id)
        } else {
            state = .signedOut
        }
    }

    /// 直近の失敗の種類。**文言でも綴りでもなく、型で分岐する。**
    @Published private(set) var lastFailure: AuthFailure = .none

    /// 直近の失敗が「まだ確認していないアカウント」か。
    var lastFailureWasUnconfirmed: Bool { lastFailure == .userNotConfirmed }

    /// 直近の失敗が「もう登録されているメールアドレス」か。
    var lastFailureWasExistingAccount: Bool {
        lastFailure == .usernameExists || lastFailure == .aliasExists
    }

    func signIn(email: String, password: String) async {
        await run {
            _ = try await AuthGateway.signIn(email: email, password: password)
            let id = try await AuthGateway.currentUserId()
            self.state = .signedIn(userId: id)
        }
    }

    func signOut() async {
        await AuthGateway.signOut()
        state = .signedOut
    }

    /// - Returns: 確認コード送信に使う UUID。失敗したら nil。
    func signUp(email: String, password: String) async -> String? {
        var username: String?
        await run {
            username = try await AuthGateway.signUp(email: email, password: password)
        }
        return username
    }

    /// 確認コードを送り直す。**届かない／消したときの出口**が無いと、
    /// 登録の途中で詰んだ人はアカウントを作り直すしかなくなる。
    func resendSignUpCode(username: String) async -> Bool {
        var ok = false
        await run {
            try await AuthGateway.resendSignUpCode(username: username)
            ok = true
        }
        return ok
    }

    /// ログインしたままパスワードを変える。
    func changePassword(current: String, new: String) async -> Bool {
        var ok = false
        await run {
            try await AuthGateway.changePassword(current: current, new: new)
            ok = true
        }
        return ok
    }

    /// パスワードの再設定を始める（メールにコードが届く）。
    func startPasswordReset(email: String) async -> Bool {
        var ok = false
        await run {
            try await AuthGateway.resetPassword(email: email)
            ok = true
        }
        return ok
    }

    /// 届いたコードで新しいパスワードを決める。
    func confirmPasswordReset(email: String, code: String, newPassword: String) async -> Bool {
        var ok = false
        await run {
            try await AuthGateway.confirmResetPassword(
                email: email, newPassword: newPassword, code: code
            )
            ok = true
        }
        return ok
    }

    func confirmSignUp(username: String, code: String) async -> Bool {
        var ok = false
        await run {
            try await AuthGateway.confirmSignUp(username: username, code: code)
            ok = true
        }
        return ok
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        lastFailure = .none
        defer { isWorking = false }
        do {
            try await work()
        } catch let error as AuthError {
            // **文言だけでなく、種類も残す。** 画面は「未確認だから確認へ送る」
            // のような分岐をしたい——文言で判定すると、言い回しを直すたびに
            // 静かに壊れる
            lastFailure = AuthFailure(error)
            errorMessage = AuthMessage.text(for: lastFailure)
        } catch {
            lastFailure = .other
            errorMessage = error.localizedDescription
        }
    }
}

/// 失敗の種類。
///
/// **`String(describing:)` の中身で判定しない。** Amplify Swift が持っている
/// のは `AWSCognitoAuthError`（**lowerCamel**——`userNotConfirmed`）で、
/// JS SDK の `UserNotConfirmedException` とは綴りが違う。Web から写した
/// 文字列で照合していたので、**どの分岐も一度も当たらない**状態だった。
enum AuthFailure: Equatable {
    case none
    case userNotConfirmed
    case usernameExists
    case aliasExists
    case invalidPassword
    case invalidParameter
    case notAuthorized
    case userNotFound
    case codeMismatch
    case codeExpired
    case limitExceeded
    case network
    case other

    init(_ error: AuthError) {
        if let cognito = error.underlyingError as? AWSCognitoAuthError {
            switch cognito {
            case .userNotConfirmed: self = .userNotConfirmed
            case .usernameExists: self = .usernameExists
            case .aliasExists: self = .aliasExists
            case .invalidPassword: self = .invalidPassword
            case .invalidParameter: self = .invalidParameter
            case .userNotFound: self = .userNotFound
            case .codeMismatch: self = .codeMismatch
            case .codeExpired: self = .codeExpired
            case .limitExceeded, .requestLimitExceeded, .failedAttemptsLimitExceeded:
                self = .limitExceeded
            case .network: self = .network
            default: self = .other
            }
            return
        }
        // 種別が入っていない回もある（`AuthError` そのものの種類で見る）
        switch error {
        case .notAuthorized: self = .notAuthorized
        case .sessionExpired: self = .notAuthorized
        default: self = .other
        }
    }

    /// 控えを捨ててよい失敗か（**この控えはもう使えない**ときだけ）。
    var isPermanent: Bool {
        self == .notAuthorized || self == .userNotFound || self == .invalidParameter
    }
}

/// Cognito の英文をそのまま出さない。
///
/// Web 側の反省がそのまま当てはまる: `InvalidParameterException` の
/// `message` は "Member must satisfy regular expression pattern: ..." の
/// ような英文で、**読んでも直し方が分からない**。
enum AuthMessage {

    static let passwordRule =
        L("パスワードは8文字以上で、英大文字・小文字・数字・記号（!@#$%など）をそれぞれ1文字以上含める必要があります",
          "Password must be at least 8 characters and include an uppercase letter, a lowercase letter, a number and a symbol (!@#$% etc.)")

    static func text(for failure: AuthFailure) -> String {
        switch failure {
        case .usernameExists, .aliasExists:
            return L("このメールアドレスはすでに登録されています", "This email is already registered")
        case .invalidPassword:
            return passwordRule
        case .invalidParameter:
            return L("メールアドレスの形式か、\(passwordRule)", "Check the email address, or: \(passwordRule)")
        case .notAuthorized:
            return L("メールアドレスかパスワードが違います", "Wrong email or password")
        case .userNotFound:
            return L("そのメールアドレスのアカウントが見つかりません", "No account for that email")
        case .userNotConfirmed:
            return L("メールに届いた確認コードで登録を完了してください", "Finish sign up with the code we emailed you")
        case .codeMismatch:
            return L("確認コードが違います", "That code is wrong")
        case .codeExpired:
            return L("確認コードの有効期限が切れています。再送してください", "That code expired. Send a new one.")
        case .limitExceeded:
            return L("回数が多すぎます。しばらく待ってからお試しください", "Too many attempts. Please wait and try again.")
        case .network:
            return Labels.Common.unreachable
        case .none, .other:
            return L("うまくいきませんでした。しばらくしてからもう一度お試しください", "That didn't work. Please try again in a moment.")
        }
    }
}
