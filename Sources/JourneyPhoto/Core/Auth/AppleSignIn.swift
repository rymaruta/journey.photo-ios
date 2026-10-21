import Foundation
import AuthenticationServices
import UIKit

// MARK: - Apple でサインイン（2026-10-21）
//
// **流れ**（サーバー側の注記は photo-gallery の `api/src/appleSignIn.ts`）:
//
//   1. Apple のシート（`SignInWithAppleButton`）。生の nonce を作り、Apple には SHA-256 を渡す
//   2. `POST /auth/apple`（管理 API・未認証）に ID トークンと生の nonce → Cognito のユーザー名
//      （探す・既存のメールのアカウントにつなぐ・作るはサーバーが決める）
//   3. Cognito のカスタム認証（SRP なし）をそのユーザー名で始め、同じトークンと nonce を答えにする
//   4. あとはふつうのログインと同じ（Amplify が更新トークンを持つ）
//
// **2026-10-21 判断: 方式はネイティブ（B）。** Cognito の Hosted UI（ブラウザのシート）より、純正のシートの
// ほうが登録で離れる人が減る。退会のときの Apple の取り消しも、アプリが認可コードを取れるこの形が確実。
// 比べた表は owner への計画（apple-signin-plan.md）。

/// nonce（使い回しを止める・Apple の決まりどおり、Apple には SHA-256 だけを渡す）
enum AppleNonce {
    /// 生の nonce（32 バイトの乱数を16進で 64 文字）。**サーバーは16字未満を断る**
    static func make() -> String {
        var rng = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &rng)) }.joined()
    }

    /// Apple に渡す形（SHA-256 の16進・小文字）。サーバーの `hashNonce` と同じ
    static func sha256Hex(_ raw: String) -> String {
        SHA256Digest.hash(Array(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// SHA-256（FIPS 180-4）。**CryptoKit は Linux の試験に無い**ので、nonce の1か所のためだけに持つ。
/// 正しさは試験の既知の値（空文字・"abc"・2ブロックの文）で縛る（`AppleSignInTests`）
enum SHA256Digest {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var data = message
        let bitLength = UInt64(message.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for i in (0..<8).reversed() { data.append(UInt8(truncatingIfNeeded: bitLength >> (UInt64(i) * 8))) }
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: data.count, by: 64) {
            for t in 0..<16 {
                let b = chunk + t * 4
                w[t] = UInt32(data[b]) << 24 | UInt32(data[b + 1]) << 16 | UInt32(data[b + 2]) << 8 | UInt32(data[b + 3])
            }
            for t in 16..<64 {
                let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
                let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for t in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[t] &+ w[t]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
            h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        return h.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - UInt32($0) * 8)) } }
    }
}

/// Apple のシートから受け取った、サーバーと Cognito に渡すもの
struct AppleProof: Equatable, Sendable {
    let identityToken: String
    /// 生の nonce（Apple に渡したのはこの SHA-256）
    let nonce: String
    /// 初回の承認のときだけ入る名前（新しく作ったアカウントの表示名に使う）
    var displayName: String?

    /// Cognito のカスタム認証の答え（サーバーの `appleChallenge.ts` が読む形）
    var challengeAnswer: String {
        let body = ["identityToken": identityToken, "nonce": nonce]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

/// シートの結果の読み方
enum AppleAuthorizationOutcome: Equatable {
    case proof(AppleProof)
    /// 本人が閉じた。**何も言わない**（失敗の文を出さない）
    case canceled
    case failed
}

extension AppleProof {
    /// シートの結果から読む（取り消し・トークンの無い答えを分ける）
    static func read(_ result: Result<ASAuthorization, Error>, nonce: String) -> AppleAuthorizationOutcome {
        switch result {
        case .failure(let error):
            return AppleSignInError.isCancel(error) ? .canceled : .failed
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return .failed }
            return read(identityToken: credential.identityToken, fullName: credential.fullName, nonce: nonce)
        }
    }

    /// 中身だけの読み方（試験から）
    static func read(identityToken: Data?, fullName: PersonNameComponents?, nonce: String) -> AppleAuthorizationOutcome {
        guard !nonce.isEmpty, let data = identityToken, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            return .failed
        }
        return .proof(AppleProof(identityToken: token, nonce: nonce, displayName: displayName(of: fullName)))
    }

    /// 名前。日本語の画面は「姓 名」、ほかは「名 姓」。空なら nil。
    /// `PersonNameComponentsFormatter` は使わない（Linux の Foundation で試験できない）
    static func displayName(of name: PersonNameComponents?, language: String = Locale.preferredAppLanguage) -> String? {
        guard let name else { return nil }
        let given = (name.givenName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let family = (name.familyName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = language.hasPrefix("ja") ? [family, given] : [given, family]
        let text = parts.filter { !$0.isEmpty }.joined(separator: " ")
        return text.isEmpty ? nil : String(text.prefix(PostLimits.Profile.displayName))
    }
}

/// `POST /auth/apple` の答え
struct AppleAccountLink: Decodable, Equatable, Sendable {
    let username: String
    /// 新しく作った（表示名を入れる）
    let created: Bool
    /// 既存のメールのアカウントにつないだ
    let linked: Bool
}

/// Apple でサインインの失敗の種類（画面の文は `AuthMessage`）
enum AppleSignInError: Error, Equatable {
    /// そのメールのアカウントにはつなげない（409）
    case conflict
    /// Apple の確認が通らなかった・Cognito が答えを断った
    case rejected
    /// サーバーの準備ができていない（503）
    case unavailable

    var failure: AuthFailure {
        switch self {
        case .conflict: return .appleConflict
        case .rejected: return .appleFailed
        case .unavailable: return .appleUnavailable
        }
    }

    /// サーバーの答えから種類を決める。通信できない回は `nil`（呼び手が `unreachable` のまま投げる）
    static func from(serverError error: Error) -> Error {
        guard case .server(let status, _)? = error as? APIError else { return error }
        switch status {
        case 409: return AppleSignInError.conflict
        case 503: return AppleSignInError.unavailable
        default: return AppleSignInError.rejected
        }
    }

    /// 本人がシートを閉じた
    static func isCancel(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }
}

/// Apple でサインインの文言
enum AppleSignInText {
    /// 「または」の区切り
    static let divider = L("または", "or")
    /// 退会のときに Apple の取り消しを済ませられなかった（退会は済んでいる）
    static let revokeSkipped =
        L("アカウントは削除しました。Apple でサインインのつながりは、iPhone の「設定」→ 自分の名前 →「サインインとセキュリティ」→「Apple でサインイン」から外せます",
          "Your account was deleted. To also remove Sign in with Apple, open Settings → your name → Sign-In & Security → Sign in with Apple.")
}

// MARK: - 退会のときの取り消し（審査 5.1.1(v)）

/// 退会の直前に Apple の許可を取り消す。
///
/// 🔴 **2026-10-21 判断: 取り消しが落ちても退会は止めない。** 退会（データと Cognito の削除）の方が大事。
/// 落ちた回・シートを閉じた回は `.skipped` を返し、画面が「設定から外せます」と案内する。
/// Apple の人かどうかは ID トークンの `custom:apple_sub` で見る（パスワードだけの人には何も出さない）
enum AppleSignInRevoke {
    enum Outcome: Equatable {
        case notAppleUser
        case revoked
        case skipped
    }

    /// 判定に使う ID トークン。**Cognito から取り直したもの**を先に使う（2026-10-21 の見直し）——
    /// 手元の控えは、Apple とつないだ（`custom:apple_sub` が書かれた）前のトークンのことがある。
    /// 取り直せない（圏外）回だけ手元の控え
    static func freshIdToken() async -> String? {
        let fresh = try? await AuthGateway.refreshedIdToken()
        if let fresh { return fresh }
        return try? await AuthGateway.idToken()
    }

    /// - Parameters:
    ///   - idToken: いまの ID トークン（`freshIdToken`）
    ///   - authorize: Apple のシートを出して認可コードを返す
    ///   - revoke: サーバーに認可コードを渡す（`AccountService.revokeAppleSignIn`）
    static func beforeDeletion(idToken: String?,
                               authorize: () async throws -> String,
                               revoke: (String) async throws -> Void) async -> Outcome {
        guard let idToken, IdTokenClaims.appleSubject(fromJWT: idToken) != nil else { return .notAppleUser }
        do {
            let code = try await authorize()
            try await revoke(code)
            return .revoked
        } catch {
            return .skipped
        }
    }
}

/// Apple のシートを**ボタンの外から**出す（退会のときの取り直し）。ログインはボタン（`SignInWithAppleButton`）
@MainActor
final class AppleIDAuthorizer: NSObject, ASAuthorizationControllerDelegate,
                               ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    /// 走っている間は自分を持っておく（コントローラは delegate を弱く持つ）
    private var keepAlive: AppleIDAuthorizer?

    struct NoCode: Error {}

    /// シートを出して認可コードを返す（スコープは要らない・本人の確かめだけ）
    static func authorizationCode() async throws -> String {
        let credential = try await AppleIDAuthorizer().authorize()
        guard let data = credential.authorizationCode, let code = String(data: data, encoding: .utf8), !code.isEmpty else {
            throw NoCode()
        }
        return code
    }

    func authorize() async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        keepAlive = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        Task { @MainActor in
            if let credential { self.finish(.success(credential)) } else { self.finish(.failure(NoCode())) }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { Self.keyWindow() ?? UIWindow() }
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        keepAlive = nil
    }

    private static func keyWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let window = windowScene.windows.first(where: { $0.isKeyWindow }) { return window }
        }
        return nil
    }
}
