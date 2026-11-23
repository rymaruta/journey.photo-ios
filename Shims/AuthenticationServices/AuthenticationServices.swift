// AuthenticationServices（Apple でサインイン）の模型（Linux で型検査を通すためだけのもの・札 #601）。
//
// **使っている口の形だけ**を写した。ボタンは何も出さず、押されることもない。
// 本物の振る舞い（シート・Face ID・資格情報）は Mac の CI（シミュレータ）と実機でしか確かめられない。
// 本物の `SignInWithAppleButton` は AuthenticationServices と SwiftUI の両方を読むと使える
import Foundation
import SwiftUI

/// 頼みの範囲（名前・メール）
public struct ASAuthorizationScope: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let fullName = ASAuthorizationScope(rawValue: "full_name")
    public static let email = ASAuthorizationScope(rawValue: "email")
}

/// Apple ID の頼み（本物は class。`requestedScopes` と `nonce` を書く）
open class ASAuthorizationAppleIDRequest {
    public init() {}
    open var requestedScopes: [ASAuthorizationScope]?
    open var nonce: String?
}

/// 渡される資格情報の口（本物は protocol）
public protocol ASAuthorizationCredential {}

/// Apple ID の資格情報（本物は class）
open class ASAuthorizationAppleIDCredential: ASAuthorizationCredential {
    public init(user: String = "", identityToken: Data? = nil, authorizationCode: Data? = nil,
                fullName: PersonNameComponents? = nil, email: String? = nil) {
        self.user = user
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.fullName = fullName
        self.email = email
    }
    open var user: String
    open var identityToken: Data?
    open var authorizationCode: Data?
    open var fullName: PersonNameComponents?
    open var email: String?
}

/// 頼みの答え（本物は class）
open class ASAuthorization {
    public init(credential: ASAuthorizationCredential) { self.credential = credential }
    open var credential: ASAuthorizationCredential
}

/// 失敗（本物は `ASAuthorizationError`・`Code` を持つ）
public struct ASAuthorizationError: Error {
    public enum Code: Int, Sendable {
        case unknown = 1000
        case canceled = 1001
        case invalidResponse = 1002
        case notHandled = 1003
        case failed = 1004
        case notInteractive = 1005
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
}

/// SwiftUI の Apple でサインインのボタン
public struct SignInWithAppleButton: View {
    public enum Label: Sendable {
        case signIn
        case `continue`
        case signUp
    }
    public enum Style: Sendable {
        case black
        case white
        case whiteOutline
    }
    public init(_ label: Label = .signIn,
                onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
                onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {}
    public var body: Never { fatalError("模型") }
}

extension View {
    /// 本物: ボタンの色（黒地には白）
    public func signInWithAppleButtonStyle(_ style: SignInWithAppleButton.Style) -> Self { self }
}
