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

public enum AuthError: Error {
    case service(String, String, Error? = nil)
    case unknown(String, Error? = nil)
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
public struct AuthSignInResult { public let isSignedIn: Bool = false }
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
        public static func resetPassword(for username: String) async throws -> AuthResetPasswordResult {
            fatalError("模型")
        }
        public static func confirmResetPassword(for username: String, with newPassword: String,
                                                confirmationCode: String) async throws {}
        public static func update(oldPassword: String, to newPassword: String) async throws {}
    }
}
