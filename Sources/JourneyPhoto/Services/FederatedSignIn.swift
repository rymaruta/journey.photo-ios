import Foundation

/// 外のアカウントでのログイン（Apple・札 #601 と Google・札 #715）のサーバーの答え。
/// `POST /auth/apple` と `POST /auth/google` は同じ形で答える（photo-gallery の `federatedAccount.ts` が土台）
struct FederatedSignInStart: Decodable, Equatable, Sendable {
    /// ログインに使う Cognito のユーザー名（UUID）
    let username: String
    /// CUSTOM_AUTH の問いに出す使い捨ての券（5分・1回きり）
    let challengeAnswer: String
    /// 新しいアカウントを作ったか
    let created: Bool?
}

/// サーバーが「同じ ID のログインが途中」と断った（409・`apple_signin_busy`・`google_signin_busy`）。
/// 2つの端末で同時に押したときに起きる。少し待てば通る
struct FederatedSignInBusy: LocalizedError, Equatable {
    var errorDescription: String? { AuthStore.federatedBusy }

    /// サーバーの答えが「途中」か
    static func matches(_ error: Error) -> Bool {
        if case APIError.server(status: 409, message: _) = error { return true }
        return false
    }
}
