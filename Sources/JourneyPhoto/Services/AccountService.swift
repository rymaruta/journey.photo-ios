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

    /// 🔴 **一律の20秒では足りない。** サーバーは写真の多い人で最長およそ23秒
    /// （`serverless.yml` の timeout 29）掛かり、20秒で切ると「失敗」と出たのに
    /// データは消えている、になる。Web も同じ理由で 35秒（`context.tsx`）
    static let deleteTimeout: TimeInterval = 35
}
