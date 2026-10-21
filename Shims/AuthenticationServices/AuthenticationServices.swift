// AuthenticationServices の模型（Linux で型検査するためだけのもの・Apple でサインイン 2026-10-21）。
// 使っている口の「形」だけ。名前と引数ラベルは本物（iOS 13+ / SwiftUI は iOS 14+）に合わせる。
import Foundation
import SwiftUI
import UIKit

/// 本物は `UIWindow` の別名
public typealias ASPresentationAnchor = UIWindow

open class ASAuthorizationRequest: NSObject {}
open class ASAuthorizationOpenIDRequest: ASAuthorizationRequest {
    /// 本物は `[ASAuthorization.Scope]?`
    open var requestedScopes: [ASAuthorization.Scope]?
    /// Apple に渡す nonce（ID トークンの `nonce` にそのまま入る）
    open var nonce: String?
}
open class ASAuthorizationAppleIDRequest: ASAuthorizationOpenIDRequest {}

open class ASAuthorizationAppleIDProvider: NSObject {
    public override init() {}
    open func createRequest() -> ASAuthorizationAppleIDRequest { ASAuthorizationAppleIDRequest() }
}

public protocol ASAuthorizationCredential {}

open class ASAuthorizationAppleIDCredential: NSObject, ASAuthorizationCredential {
    open var user: String { "" }
    open var identityToken: Data? { nil }
    open var authorizationCode: Data? { nil }
    /// 初回の承認のときだけ入る（2回目からは nil）
    open var email: String? { nil }
    open var fullName: PersonNameComponents? { nil }
}

open class ASAuthorization: NSObject {
    public struct Scope: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let email = Scope(rawValue: "email")
        public static let fullName = Scope(rawValue: "full_name")
    }
    open var credential: any ASAuthorizationCredential { ASAuthorizationAppleIDCredential() }
}

/// 本物は `ASAuthorizationError`（`Error` の struct・`Code` は Int の enum）
public struct ASAuthorizationError: Error, Equatable {
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

public protocol ASAuthorizationControllerDelegate: AnyObject {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization)
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error)
}

public protocol ASAuthorizationControllerPresentationContextProviding: AnyObject {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor
}

open class ASAuthorizationController: NSObject {
    public init(authorizationRequests: [ASAuthorizationRequest]) {}
    open weak var delegate: (any ASAuthorizationControllerDelegate)?
    open weak var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)?
    open func performRequests() {}
}

/// SwiftUI の Apple でサインインのボタン（本物は `_AuthenticationServices_SwiftUI` にあり、
/// AuthenticationServices と SwiftUI を両方読むと使える）
public struct SignInWithAppleButton: View {
    public enum Label: Sendable { case signIn, `continue`, signUp }
    public struct Style: Sendable {
        public static let black = Style()
        public static let white = Style()
        public static let whiteOutline = Style()
    }
    public init(_ label: Label = .signIn,
                onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
                onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {}
    public var body: Never { fatalError("模型") }
}

extension View {
    public func signInWithAppleButtonStyle(_ style: SignInWithAppleButton.Style) -> Self { self }
}
