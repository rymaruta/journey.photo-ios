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
    /// サーバー側は Cognito のユーザーを消し、プロフィールに墓石
    /// （`deletedAt`）を立て、写真と画像の実体を消す。
    /// コメントは各写真に散らばっていて per-user の索引が無いため
    /// スコープ外で、読むときに名前を伏せる扱いになっている
    /// （`api-user/src/account.ts` / `comments.ts` の注記）。
    func deleteAccount() async throws {
        try await api.authorizedVoid(.delete, "/user/account")
    }
}
