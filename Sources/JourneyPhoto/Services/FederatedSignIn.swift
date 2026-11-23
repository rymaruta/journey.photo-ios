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

    /// サーバーの答えが「途中」か（解除済みの断りは、口の側で `FederatedSignInUnlinked` に包んであるので、ここには来ない）
    static func matches(_ error: Error) -> Bool {
        if case APIError.server(status: 409, message: _) = error { return true }
        return false
    }
}

/// 本人が設定の「サインインの方法」で解除した Apple ID・Google アカウントで、また入ろうとした
/// （サーバーの 409・`apple_signin_unlinked`・`google_signin_unlinked`・2026-11-23 確かめ役の指摘）。
/// サーバーは黙って空の別アカウントを作らずに断る。ログイン画面の失敗の文には、サーバーの文をそのまま出す
/// （例「この Apple ID の連携は解除されています。メールアドレスでログインしてください」）
///
/// 2026-11-23 判断（確かめ役の見直し）: サーバーの文の一部では見分けず、本文の `code` で見分ける。
/// `APIError.server` に `code` を足すと、状態と本文の2つで分けている呼び手（約40か所）の形が全部変わるので
/// （`APIError.statusText` の注記）、`code` を読むのは今ある決まった口（`APIClient.errorBodySink`・トランクと購入と同じ）
struct FederatedSignInUnlinked: LocalizedError, Equatable {
    /// サーバーの文（日本語）
    let message: String

    /// 解除済みの断りの `code`（サーバーの `appleSignin.ts`・`googleSignin.ts`）
    static let codes: Set<String> = ["apple_signin_unlinked", "google_signin_unlinked"]

    /// 失敗が解除済みの断りなら包む（409 で、本文の `code` が `codes` のどれか）
    static func wrap(_ error: Error, code: String?) -> Error {
        guard case APIError.server(status: 409, message: let text) = error,
              let code, codes.contains(code) else { return error }
        return FederatedSignInUnlinked(message: text)
    }

    /// 外のアカウントのログインの口を呼ぶ。解除済みの断りは `FederatedSignInUnlinked` にして投げる
    static func refusing<T>(_ call: () async throws -> T) async throws -> T {
        let body = APIErrorBody()
        do {
            return try await APIClient.$errorBodySink.withValue(body) { try await call() }
        } catch {
            throw wrap(error, code: APIClient.errorCode(from: body.data))
        }
    }

    var errorDescription: String? {
        APIError.displayableServerText(message)
            ?? "This account was disconnected in Sign-in methods. Please sign in with your email."
    }
}
