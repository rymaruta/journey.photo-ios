// Cognito プラグインの模型。
import Foundation
import Amplify

public struct AWSCognitoAuthPlugin: Plugin {
    public init() {}
}

/// 本物の `AWSCognitoAuthError`
/// （`AmplifyPlugins/Auth/Sources/AWSCognitoAuthPlugin/Models/Errors/`）。
/// **綴りは lowerCamel**——JS SDK の `UserNotConfirmedException` とは違う。
public enum AWSCognitoAuthError: Error {
    case userNotFound
    case userNotConfirmed
    case usernameExists
    case aliasExists
    case codeDelivery
    case codeMismatch
    case codeExpired
    case invalidParameter
    case invalidPassword
    case limitExceeded
    case mfaMethodNotFound
    case softwareTokenMFANotEnabled
    case passwordResetRequired
    case resourceNotFound
    case failedAttemptsLimitExceeded
    case requestLimitExceeded
    case network
}

/// 本物の `AWSCognitoSignOutResult`
/// （`AmplifyPlugins/Auth/Sources/AWSCognitoAuthPlugin/Models/AWSCognitoSignOutResult.swift`）。
/// `.failed` は**端末の中のログインも消せていない**（本物の `signedOutLocally` が false）。
/// `.partial` はサーバー側の取り消しだけが落ちた回で、端末からは消えている
public enum AWSCognitoSignOutResult: AuthSignOutResult {
    case complete
    case partial(revokeTokenError: AWSCognitoRevokeTokenError?,
                 globalSignOutError: AWSCognitoGlobalSignOutError?,
                 hostedUIError: AWSCognitoHostedUIError?)
    case failed(AuthError)
}
public struct AWSCognitoRevokeTokenError: Sendable {
    public let refreshToken: String
    public let error: AuthError
}
public struct AWSCognitoGlobalSignOutError: Sendable {
    public let accessToken: String
    public let error: AuthError
}
public struct AWSCognitoHostedUIError: Sendable {
    public let error: AuthError
}
