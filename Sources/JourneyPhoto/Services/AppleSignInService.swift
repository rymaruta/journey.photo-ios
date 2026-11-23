import Foundation

/// 「Apple でサインイン」のサーバーの口（札 #601・2026-11-23 owner「すすめたい！」）。
///
/// 流れ（押す回数は2回: ボタン → Face ID）:
/// 1. Apple の標準シートで identity token・認可コード・（初回だけ）名前を受け取る（`SignInView`）
/// 2. `POST /auth/apple`: サーバーが Apple の鍵で確かめ、**今の Cognito の利用者**を決める（結ぶ・作る）。
///    答えは Cognito のユーザー名だけ
/// 3. Cognito の CUSTOM_AUTH でそのユーザー名にログインし、同じ identity token を答えに出す
///    （`AuthGateway.signInWithApple`）。出てくるのは今と同じ Cognito のトークン
///
/// サーバーの作りは photo-gallery の `api-user/src/appleSignin.ts`（別スタック `serverless.apple-signin.yml`）。
struct AppleSignInService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private struct Status: Decodable {
        let available: Bool
    }

    /// サーバーで使えるか。**確かめられなければ使えない扱い**（ボタンを出さない）。
    /// 鍵の入っていない環境は `available: false`、口がまだ無い本番は 404 になり、どちらも false
    func isAvailable() async -> Bool {
        (try? await api.anonymous(.get, "/auth/apple/status", as: Status.self).available) ?? false
    }

    private struct StartBody: Encodable {
        let identityToken: String
        let authorizationCode: String?
        let displayName: String?
    }

    /// `POST /auth/apple` の答え
    struct Started: Decodable, Equatable {
        /// ログインに使う Cognito のユーザー名（UUID）
        let username: String
        /// 新しいアカウントを作ったか
        let created: Bool?
    }

    /// サーバーに Apple の資格情報を渡し、ログインに使う Cognito のユーザー名を受け取る
    func start(_ credential: AppleSignInCredential) async throws -> Started {
        try await api.anonymous(.post, "/auth/apple",
                                body: StartBody(identityToken: credential.identityToken,
                                                authorizationCode: credential.authorizationCode,
                                                displayName: credential.displayName),
                                as: Started.self)
    }
}

/// Apple の標準シートから受け取ったもの（サーバーに渡す形）
struct AppleSignInCredential: Equatable, Sendable {
    let identityToken: String
    let authorizationCode: String?
    /// 表示名。Apple は**最初の1回しか**名前を渡さない（2回目からは nil）
    let displayName: String?

    /// 資格情報の生の値から作る。identity token が読めなければ nil（サインインできない）
    init?(identityToken: Data?, authorizationCode: Data?, givenName: String?, familyName: String?) {
        guard let identityToken, let token = String(data: identityToken, encoding: .utf8), !token.isEmpty else { return nil }
        self.identityToken = token
        self.authorizationCode = authorizationCode.flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
        self.displayName = AppleSignInName.displayName(given: givenName, family: familyName)
    }
}

/// Apple から来た名前を表示名にする
enum AppleSignInName {
    /// 漢字・かなの名前は「姓 名」、それ以外は「名 姓」。片方だけならそれだけ。両方無ければ nil。
    /// 2026-11-23 判断: 日本の利用者を先に考える（CLAUDE.md「国産」）。表示名はあとで本人が変えられる
    static func displayName(given: String?, family: String?) -> String? {
        let g = (given ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let f = (family ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch (g.isEmpty, f.isEmpty) {
        case (true, true): return nil
        case (false, true): return g
        case (true, false): return f
        case (false, false):
            return isJapanese(g + f) ? "\(f) \(g)" : "\(g) \(f)"
        }
    }

    /// 漢字・ひらがな・カタカナを含むか
    static func isJapanese(_ s: String) -> Bool {
        s.unicodeScalars.contains { u in
            (0x3040...0x30FF).contains(u.value) || (0x4E00...0x9FFF).contains(u.value) || (0x3400...0x4DBF).contains(u.value)
        }
    }
}

/// Apple の頼みに入れる使い捨ての印（nonce）。
///
/// サーバー（Cognito のトリガー）は同じ nonce の identity token を2回は通さない（使い回しを止める）。
/// 中身は見ないので、毎回違う乱数ならよい（ハッシュは要らない）
enum AppleSignInNonce {
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }
}
