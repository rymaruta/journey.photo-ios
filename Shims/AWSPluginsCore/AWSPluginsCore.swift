// `AuthCognitoTokensProvider`（ID トークンを取り出す口）の模型。
import Foundation
import Amplify

public struct AWSCognitoUserPoolTokens {
    public let idToken: String = ""
    public let accessToken: String = ""
}

public protocol AuthCognitoTokensProvider {
    func getCognitoTokens() -> Result<AWSCognitoUserPoolTokens, AuthError>
}
