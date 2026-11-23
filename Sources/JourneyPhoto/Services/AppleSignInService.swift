import CryptoKit
import Foundation

/// 「Apple でサインイン」のサーバーの口（札 #601・2026-11-23 owner「すすめたい！」）。
///
/// 流れ（押す回数は2回: ボタン → Face ID）:
/// 1. 乱数の nonce を作り、その **SHA-256** を Apple の頼みに入れる。Apple の標準シートで identity token・
///    認可コード・（初回だけ）名前を受け取る（`SignInView`）
/// 2. `POST /auth/apple`: identity token と **nonce の元の値**を渡す。サーバーが Apple の鍵で確かめ、
///    元の値の SHA-256 が token の nonce と同じかを照らし（使った nonce は1回きり）、**今の Cognito の利用者**を決める
///    （結ぶ・作る）。答えは Cognito のユーザー名と**使い捨ての券**（5分）
/// 3. Cognito の CUSTOM_AUTH でそのユーザー名にログインし、券を答えに出す
///    （`AuthGateway.signInWithTicket`）。出てくるのは今と同じ Cognito のトークン
///
/// 退会のときの Apple の取り消しはサーバーの退会（`DELETE /user/account`）が行う（2026-11-23 確かめ役の指摘）
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
        await availability() ?? false
    }

    /// サーバーの答え。**はっきり答えたときだけ** true / false、圏外・サーバーの不調は nil
    /// （前回の答えを変えない・`ExternalSignInMemory`・2026-11-23 判断）。口がまだ無い 404・読めない答えは false
    func availability() async -> Bool? {
        do {
            return try await api.anonymous(.get, "/auth/apple/status", as: Status.self).available
        } catch {
            return ExternalSignInAvailability.answer(for: error)
        }
    }

    struct StartBody: Encodable, Equatable {
        let identityToken: String
        /// nonce の元の値（Apple に渡したのはこの SHA-256）
        let nonce: String
        let authorizationCode: String?
        let displayName: String?
    }

    /// `POST /auth/apple` の答え（Google と同じ形・`FederatedSignInStart`）
    typealias Started = FederatedSignInStart

    static func body(for credential: AppleSignInCredential) -> StartBody {
        StartBody(identityToken: credential.identityToken, nonce: credential.rawNonce,
                  authorizationCode: credential.authorizationCode, displayName: credential.displayName)
    }

    /// サーバーに Apple の資格情報と nonce の元の値を渡し、ログインに使う Cognito のユーザー名と券を受け取る
    func start(_ credential: AppleSignInCredential) async throws -> Started {
        // 解除済みの断り（409・`code`）は `FederatedSignInUnlinked` に包む
        try await FederatedSignInUnlinked.refusing {
            try await api.anonymous(.post, "/auth/apple", body: Self.body(for: credential), as: Started.self)
        }
    }
}

/// Apple の標準シートから受け取ったもの（サーバーに渡す形）
struct AppleSignInCredential: Equatable, Sendable {
    let identityToken: String
    /// 頼みに入れた nonce の元の値（Apple にはこの SHA-256 を渡した）
    let rawNonce: String
    let authorizationCode: String?
    /// 表示名。Apple は**最初の1回しか**名前を渡さない（2回目からは nil）
    let displayName: String?

    /// 資格情報の生の値から作る。identity token が読めない・nonce が無ければ nil（サインインできない）
    init?(identityToken: Data?, rawNonce: String?, authorizationCode: Data?, givenName: String?, familyName: String?) {
        guard let identityToken, let token = String(data: identityToken, encoding: .utf8), !token.isEmpty,
              let rawNonce, !rawNonce.isEmpty else { return nil }
        self.identityToken = token
        self.rawNonce = rawNonce
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

/// Apple・Google の頼みに入れる使い捨ての印（nonce）。
///
/// 🔴 **提供元には SHA-256（`hashed`）を、サーバーには元の値（`raw`）を渡す**（Apple の案内どおり・
/// 2026-11-23 確かめ役の指摘。Google も同じ形・札 #715）。サーバーは「元の値の SHA-256 が token の nonce と同じか」を照らし、
/// 使った nonce を1回きりにする。ID トークンだけ盗まれても、元の値が無いので入れない
typealias AppleSignInNonce = SignInNonce

struct SignInNonce: Equatable, Sendable {
    /// 元の値（32 バイトの乱数の16進・64字）。端末の中とサーバーへの1回の送信にだけ使う
    let raw: String

    /// 提供元の頼み（Apple の `ASAuthorizationAppleIDRequest.nonce`・Google の `signIn(… nonce:)`）に入れる値
    var hashed: String { Self.sha256Hex(raw) }

    static func make() -> SignInNonce {
        var generator = SystemRandomNumberGenerator()
        return SignInNonce(raw: (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined())
    }

    static func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
