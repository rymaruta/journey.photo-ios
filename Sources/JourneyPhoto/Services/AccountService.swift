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
        await revokeAppleSignIn()
        try await api.authorizedVoid(.delete, "/user/account", timeout: Self.deleteTimeout)
    }

    /// 「Apple でサインイン」の結び付けを取り消す（Apple の更新トークンを `/auth/revoke` で取り消す。
    /// Apple の決まり・札 #601）。**退会の前に呼ぶ**——サーバーの退会のあとは、本人の行が墓石になる。
    ///
    /// 🔴 **失敗しても退会は止めない（2026-11-23 判断）。** Apple で入っていない人は何もしない口で、
    /// 口がまだ無い本番（404）・Apple が落ちている回に退会できなくなるほうが困る。サーバーは墓石に
    /// Apple の番号を残すので、退会の途中で止まった人のやり直し（`finishPendingDeletion` もここを通る）で取り消せる
    func revokeAppleSignIn() async {
        _ = try? await api.authorizedVoid(.post, "/auth/apple/revoke", timeout: Self.revokeTimeout)
    }

    /// Apple の取り消しの待ちの上限。サーバーは Apple に最大5秒で問い合わせる
    static let revokeTimeout: TimeInterval = 12

    /// 🔴 **一律の20秒では足りない。** サーバーは写真の多い人で最長およそ23秒
    /// （`serverless.yml` の timeout 29）掛かり、20秒で切ると「失敗」と出たのに
    /// データは消えている、になる。Web も同じ理由で 35秒（`context.tsx`）
    static let deleteTimeout: TimeInterval = 35
}
