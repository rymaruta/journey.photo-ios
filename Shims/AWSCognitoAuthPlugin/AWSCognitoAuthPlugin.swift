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
