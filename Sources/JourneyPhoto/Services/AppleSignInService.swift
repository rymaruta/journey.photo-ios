import Foundation

/// Apple でサインインの入口（`POST /auth/apple`・**管理 API**＝photo-gallery の `api/`・2026-10-21）。
///
/// 未認証で呼ぶ（まだログインしていない・`anonymous` はトークンを読まない）。サーバーは Apple の ID トークンを確かめて、
/// その Apple ID の Cognito のユーザー名を返す（探す・既存のメールのアカウントにつなぐ・作る）。
/// トークンは返さない——Cognito のトークンは、このあとのカスタム認証（`AuthGateway.signInWithApple`）で出る。
///
/// 向く先は `AppConfig.apiBaseURL`（api-user ではない）。`Tools/check-api-parity.py` はこの目印で
/// `api/serverless.yml` と突き合わせる
struct AppleSignInService {

    private let api: APIClient

    init(api: APIClient = APIClient(baseURL: AppConfig.apiBaseURL, tokenProvider: CognitoTokenProvider())) {
        self.api = api
    }

    /// - Throws: 409 → `AppleSignInError.conflict`、503 → `.unavailable`、ほかの断り → `.rejected`、
    ///   通信できない → `APIError.unreachable`
    func link(_ proof: AppleProof) async throws -> AppleAccountLink {
        do {
            return try await api.anonymous(.post, "/auth/apple",
                                           body: Body(identityToken: proof.identityToken, nonce: proof.nonce),
                                           as: AppleAccountLink.self)
        } catch {
            throw AppleSignInError.from(serverError: error)
        }
    }

    private struct Body: Encodable {
        let identityToken: String
        let nonce: String
    }
}
