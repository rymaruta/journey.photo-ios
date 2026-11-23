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

    /// サーバーの答えが「途中」か（同じ 409 の「解除されています」は除く・`FederatedSignInUnlinked`）
    static func matches(_ error: Error) -> Bool {
        if case APIError.server(status: 409, message: _) = error { return FederatedSignInUnlinked(error) == nil }
        return false
    }
}

/// 本人が設定の「サインインの方法」で解除した Apple ID・Google アカウントで、また入ろうとした
/// （サーバーの 409・`apple_signin_unlinked`・`google_signin_unlinked`・2026-11-23 確かめ役の指摘）。
/// サーバーは黙って空の別アカウントを作らずに断る。ログイン画面の失敗の文には、サーバーの文をそのまま出す
/// （例「この Apple ID の連携は解除されています。メールアドレスでログインしてください」）
struct FederatedSignInUnlinked: LocalizedError, Equatable {
    /// サーバーの文（日本語）
    let message: String

    /// 409 の本文がこの断りか（`APIError` は `code` を持たないので、サーバーの決まった文の一部で見分ける）
    init?(_ error: Error) {
        guard case APIError.server(status: 409, message: let text) = error,
              text.contains(Self.marker) else { return nil }
        message = text
    }

    /// サーバーの文の目印（`federatedAccount.ts` の `unlinkedMessage`）
    static let marker = "連携は解除されています"

    var errorDescription: String? {
        APIError.displayableServerText(message)
            ?? "This account was disconnected in Sign-in methods. Please sign in with your email."
    }
}
