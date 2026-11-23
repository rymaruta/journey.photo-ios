import Foundation
#if canImport(GoogleSignIn) && canImport(UIKit)
import GoogleSignIn
import UIKit
#endif

/// 「Google でログイン」のサーバーの口（札 #715・2026-11-23 owner「Google でサインインも必要」）。
///
/// 流れは「Apple でサインイン」（`AppleSignInService`）と同じ:
/// 1. 乱数の nonce を作り、その **SHA-256** を Google の頼みに入れる（GoogleSignIn-iOS の `nonce`）。
///    Google の画面でアカウントを選び、ID トークンを受け取る（`GoogleSignInClient`）
/// 2. `POST /auth/google`: ID トークンと **nonce の元の値**を渡す。サーバーが Google の鍵で確かめ、nonce を照らし（1回きり）、
///    今の Cognito の利用者を決める（結ぶ・作る）。答えは Cognito のユーザー名と使い捨ての券
/// 3. Cognito の CUSTOM_AUTH でそのユーザー名にログインし、券を答えに出す（`AuthGateway.signInWithTicket`）
///
/// Google の更新トークンは受け取らない（サーバー用の認可コードを頼まない）ので、退会で取り消すものは無い。
/// サーバーの作りは photo-gallery の `api-user/src/googleSignin.ts`（別スタック `serverless.google-signin.yml`）
struct GoogleSignInService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private struct Status: Decodable {
        let available: Bool
    }

    /// サーバーで使えるか。**確かめられなければ使えない扱い**（ボタンを出さない）。口がまだ無い本番は 404 で false
    func isAvailable() async -> Bool {
        (try? await api.anonymous(.get, "/auth/google/status", as: Status.self).available) ?? false
    }

    struct StartBody: Encodable, Equatable {
        let idToken: String
        /// nonce の元の値（Google に渡したのはこの SHA-256）
        let nonce: String
        let displayName: String?
    }

    static func body(for credential: GoogleSignInCredential) -> StartBody {
        StartBody(idToken: credential.idToken, nonce: credential.rawNonce, displayName: credential.displayName)
    }

    func start(_ credential: GoogleSignInCredential) async throws -> FederatedSignInStart {
        // 解除済みの断り（409・`code`）は `FederatedSignInUnlinked` に包む
        try await FederatedSignInUnlinked.refusing {
            try await api.anonymous(.post, "/auth/google", body: Self.body(for: credential), as: FederatedSignInStart.self)
        }
    }
}

/// Google から受け取ったもの（サーバーに渡す形）
struct GoogleSignInCredential: Equatable, Sendable {
    let idToken: String
    /// 頼みに入れた nonce の元の値（Google にはこの SHA-256 を渡した）
    let rawNonce: String
    /// Google のプロフィールの名前（無ければサーバーが ID トークンの名前を使う）
    let displayName: String?

    /// ID トークンが無い・nonce が無ければ nil（サインインできない）
    init?(idToken: String?, rawNonce: String?, displayName: String?) {
        guard let idToken, !idToken.isEmpty, let rawNonce, !rawNonce.isEmpty else { return nil }
        self.idToken = idToken
        self.rawNonce = rawNonce
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.displayName = name.isEmpty ? nil : name
    }
}

/// Google の設定（公開の値）。iOS の OAuth クライアント ID は owner が Google Cloud で作った（2026-11-23・札 #715 のコメント）。
/// 秘密ではない（アプリに書き込む値）。`project.yml` の `GIDClientID` と URL の型（逆さのクライアント ID）も同じ値
enum GoogleSignInConfig {
    static let clientID = "280167931666-24o92d38usbft3ouk3jc4dk8tvgh3t8p.apps.googleusercontent.com"
    static let urlScheme = "com.googleusercontent.apps.280167931666-24o92d38usbft3ouk3jc4dk8tvgh3t8p"
}

/// Google の公式の部品（GoogleSignIn-iOS）を呼ぶ所。部品の口はここだけにする
enum GoogleSignInClient {
    /// 本人が Google の画面を閉じた（何も言わない）
    struct Canceled: Error {}

    #if canImport(GoogleSignIn) && canImport(UIKit)
    /// Google の画面を出し、ID トークンと名前を受け取る。nonce は SHA-256 を渡す
    @MainActor
    static func signIn(nonce: SignInNonce) async throws -> (idToken: String?, name: String?) {
        guard let presenter = topController() else { throw Canceled() }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: GoogleSignInConfig.clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: nonce.hashed)
            return (result.user.idToken?.tokenString, result.user.profile?.name)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw Canceled()
        }
    }

    /// Google の画面から戻ってきた URL（URL の型 `GoogleSignInConfig.urlScheme`）を部品に渡す
    @MainActor
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// 部品の中のログインを外す（アプリのログアウト・退会のとき）。Google でログインしていない人には何もしない
    @MainActor
    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    @MainActor
    private static func topController() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                var top = window.rootViewController
                while let next = top?.presentedViewController { top = next }
                return top
            }
        }
        return nil
    }
    #else
    /// Linux の模型（部品が無い）。呼ばれない
    @MainActor
    static func signIn(nonce: SignInNonce) async throws -> (idToken: String?, name: String?) { throw Canceled() }

    @MainActor
    static func handle(_ url: URL) -> Bool { false }

    @MainActor
    static func signOut() {}
    #endif
}
