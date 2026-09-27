// Amplify Swift の模型（使っている口だけ）。
import Foundation

public enum JSONValue: ExpressibleByDictionaryLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral {
    case string(String)
    case object([String: JSONValue])
    case array([JSONValue])

    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

public struct AuthCategoryConfiguration {
    public init(plugins: [String: JSONValue]) {}
}

public struct AmplifyConfiguration {
    public init(auth: AuthCategoryConfiguration? = nil) {}
}

public protocol Plugin {}

/// 本物の `Amplify.AuthError`（`Amplify/Categories/Auth/Error/AuthError.swift`）に
/// 合わせる。**`underlyingError` があるのが肝**——種別はこの中の
/// `AWSCognitoAuthError` に入っていて、説明文の綴りで見てはいけない。
public enum AuthError: Error {
    case configuration(String, String, Error? = nil)
    case service(String, String, Error? = nil)
    case unknown(String, Error? = nil)
    case validation(String, String, String, Error? = nil)
    case notAuthorized(String, String, Error? = nil)
    case invalidState(String, String, Error? = nil)
    case signedOut(String, String, Error? = nil)
    case sessionExpired(String, String, Error? = nil)

    public var underlyingError: Error? {
        switch self {
        case .configuration(_, _, let underlying),
             .service(_, _, let underlying),
             .notAuthorized(_, _, let underlying),
             .invalidState(_, _, let underlying),
             .signedOut(_, _, let underlying),
             .sessionExpired(_, _, let underlying):
            return underlying
        case .validation(_, _, _, let underlying):
            return underlying
        case .unknown(_, let underlying):
            return underlying
        }
    }
}

public struct AuthUserAttributeKey {
    public static let email = AuthUserAttributeKey()
}
public struct AuthUserAttribute {
    public init(_ key: AuthUserAttributeKey, value: String) {}
}
public enum AuthSignUpRequest {
    public struct Options {
        public init(userAttributes: [AuthUserAttribute] = []) {}
    }
}
public struct AuthSignUpResult { public let isSignUpComplete: Bool = false }
/// 本物（amplify-swift 2.27 の `AuthCodeDeliveryDetails.swift`）と同じ
public typealias AdditionalInfo = [String: String]

/// ログインの次の一手（本物は `Amplify/Categories/Auth/Models/AuthSignInStep.swift`）。
///
/// **本物は未確認のアカウントで例外を投げない。** Cognito の
/// `UserNotConfirmedException` を `.confirmSignUp(nil)` に、
/// `PasswordResetRequiredException` を `.resetPassword(nil)` に畳んで返す
/// （`UserPoolSignInHelper.validateError`）。形は本物に合わせ、使わない
/// 多要素認証の一部（SMS・TOTP の設定・選択）は省いてある
public enum AuthSignInStep {
    case confirmSignInWithCustomChallenge(AdditionalInfo?)
    case confirmSignInWithNewPassword(AdditionalInfo?)
    case confirmSignInWithTOTPCode
    case resetPassword(AdditionalInfo?)
    case confirmSignUp(AdditionalInfo?)
    case done
}

/// 本物と同じく `isSignedIn` は `nextStep == .done` のときだけ真
public struct AuthSignInResult {
    public var nextStep: AuthSignInStep
    public var isSignedIn: Bool {
        if case .done = nextStep { return true }
        return false
    }
    public init(nextStep: AuthSignInStep) { self.nextStep = nextStep }
}
public struct AuthCodeDeliveryDetails {}
public struct AuthResetPasswordResult {}
public struct AuthSignOutResult {}
public protocol AuthUser { var userId: String { get } }

public protocol AuthSession { var isSignedIn: Bool { get } }

public enum Amplify {
    public static func add(plugin: any Plugin) throws {}
    public static func configure(_ configuration: AmplifyConfiguration) throws {}

    public enum Auth {
        public static func fetchAuthSession() async throws -> any AuthSession { fatalError("模型") }
        public static func getCurrentUser() async throws -> any AuthUser { fatalError("模型") }
        public static func signUp(username: String, password: String,
                                  options: AuthSignUpRequest.Options? = nil) async throws -> AuthSignUpResult {
            fatalError("模型")
        }
        public static func confirmSignUp(for username: String,
                                         confirmationCode: String) async throws -> AuthSignUpResult {
            fatalError("模型")
        }
        public static func resendSignUpCode(for username: String) async throws -> AuthCodeDeliveryDetails {
            fatalError("模型")
        }
        public static func signIn(username: String?, password: String?) async throws -> AuthSignInResult {
            fatalError("模型")
        }
        public static func signOut() async -> AuthSignOutResult { AuthSignOutResult() }
        /// サインイン中の利用者を Cognito から消す（本物は済むとローカルのサインアウトもする）
        public static func deleteUser() async throws {}
        public static func resetPassword(for username: String) async throws -> AuthResetPasswordResult {
            fatalError("模型")
        }
        public static func confirmResetPassword(for username: String, with newPassword: String,
                                                confirmationCode: String) async throws {}
        public static func update(oldPassword: String, to newPassword: String) async throws {}
    }
}
