import Foundation

/// アカウントの削除。
///
/// **審査要件（5.1.1(v)）。** アカウントを作れるアプリは、アプリの中から
/// 削除できなければならない。Web 版は `DeleteAccountModal` で満たしていて、
/// 叩く口は同じ `DELETE /user/account`。
struct AccountService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// 退会する。**戻せない。**
    ///
    /// サーバー側はプロフィールに墓石（`deletedAt`）を立て、写真と画像の実体と
    /// 端末の宛先（`devices#`）を消す。🔴 **Cognito の利用者は消さない**——
    /// 呼び手が続けて `AuthStore.deleteCognitoUser()` を呼ぶ（Web と同じ分担）。
    /// コメントは各写真に散らばっていて per-user の索引が無いため
    /// スコープ外で、読むときに名前を伏せる扱いになっている
    /// （`api-user/src/account.ts` / `comments.ts` の注記）。
    func deleteAccount() async throws {
        try await api.authorizedVoid(.delete, "/user/account", timeout: Self.deleteTimeout)
    }

    /// 退会の直前に Apple でサインインの許可を取り消す（`POST /user/apple/revoke`・審査 5.1.1(v)・2026-10-21）。
    /// 認可コードは Apple のシートで取り直したもの（`AppleIDAuthorizer`）。サーバーが Apple の
    /// `/auth/token` で交換し `/auth/revoke` で取り消す。**落ちても退会は続ける**（`AppleSignInRevoke`）
    func revokeAppleSignIn(authorizationCode: String) async throws {
        try await api.authorizedVoid(.post, "/user/apple/revoke", body: AppleRevokeBody(authorizationCode: authorizationCode),
                                     timeout: Self.revokeTimeout)
    }

    /// サーバーは Apple へ2往復（打ち切り8秒ずつ・関数の上限20秒）
    static let revokeTimeout: TimeInterval = 25

    /// 🔴 **一律の20秒では足りない。** サーバーは写真の多い人で最長およそ23秒
    /// （`serverless.yml` の timeout 29）掛かり、20秒で切ると「失敗」と出たのに
    /// データは消えている、になる。Web も同じ理由で 35秒（`context.tsx`）
    static let deleteTimeout: TimeInterval = 35
}

private struct AppleRevokeBody: Encodable {
    let authorizationCode: String
}
