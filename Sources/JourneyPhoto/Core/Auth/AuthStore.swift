import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine
import Amplify

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

    /// 起動時に一度。**「確かめられなかった」と「ログインしていない」を
    /// 混ぜない**——圏外なだけの人をログイン画面に飛ばさないため、
    /// 判定できない回は `.unknown` のままにする。
    func restore() async {
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
        defer { isWorking = false }
        do {
            try await work()
        } catch let error as AuthError {
            errorMessage = AuthMessage.text(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
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

    static func text(for error: AuthError) -> String {
        let underlying = String(describing: error)
        if underlying.contains("UsernameExists") || underlying.contains("AliasExists") {
            return L("このメールアドレスはすでに登録されています", "This email is already registered")
        }
        if underlying.contains("InvalidPassword") {
            return passwordRule
        }
        if underlying.contains("InvalidParameter") {
            return L("メールアドレスの形式か、\(passwordRule)", "Check the email address, or: \(passwordRule)")
        }
        if underlying.contains("NotAuthorized") {
            return L("メールアドレスかパスワードが違います", "Wrong email or password")
        }
        if underlying.contains("UserNotConfirmed") {
            return L("メールに届いた確認コードで登録を完了してください", "Finish sign up with the code we emailed you")
        }
        if underlying.contains("CodeMismatch") {
            return L("確認コードが違います", "That code is wrong")
        }
        if underlying.contains("ExpiredCode") {
            return L("確認コードの有効期限が切れています。再送してください", "That code expired. Send a new one.")
        }
        if underlying.contains("LimitExceeded") || underlying.contains("TooManyRequests") {
            return L("回数が多すぎます。しばらく待ってからお試しください", "Too many attempts. Please wait and try again.")
        }
        if underlying.contains("Network") {
            return Labels.Common.unreachable
        }
        return L("うまくいきませんでした。しばらくしてからもう一度お試しください", "That didn't work. Please try again in a moment.")
    }
}
