// StoreKit 2 の模型（Linux で型検査を通すためだけのもの）。
//
// **使っている口の形だけ**を写した。中身はどれも何もしない（商品は0件・購入は取り消し扱い）。
// 本物の StoreKit の振る舞いは Mac の CI（シミュレータ）と実機でしか確かめられない。
//
// 🔴 本物の StoreKit の `Transaction` は SwiftUI の `Transaction`（アニメーションの入れ物）と
// 名前が重なる。両方を読むファイルでは `StoreKit.Transaction` と書く（模型でも同じ形にしてある）
import Foundation
import SwiftUI

public enum VerificationResult<SignedType> {
    case unverified(SignedType, VerificationError)
    case verified(SignedType)

    public enum VerificationError: Error {
        case revokedCertificate
        case invalidCertificateChain
        case invalidDeviceVerification
        case invalidEncoding
        case invalidSignature
        case missingRequiredProperties
    }

    /// 署名された元の文字列（JWS）。サーバーへ渡す
    public var jwsRepresentation: String { "" }

    public var payloadValue: SignedType {
        get throws {
            switch self {
            case .verified(let value): return value
            case .unverified(_, let error): throw error
            }
        }
    }

    public var unsafePayloadValue: SignedType {
        switch self {
        case .verified(let value): return value
        case .unverified(let value, _): return value
        }
    }
}

extension VerificationResult: Sendable where SignedType: Sendable {}

public struct Transaction: Sendable {
    public let id: UInt64
    public let originalID: UInt64
    public let productID: String
    public let purchaseDate: Date
    public let originalPurchaseDate: Date
    public let expirationDate: Date?
    public let revocationDate: Date?
    public let isUpgraded: Bool
    public let appAccountToken: UUID?
    public let productType: Product.ProductType
    /// 自分で買ったか、ファミリー共有で使えているか
    public let ownershipType: OwnershipType

    public struct OwnershipType: Equatable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let purchased = OwnershipType(rawValue: "PURCHASED")
        public static let familyShared = OwnershipType(rawValue: "FAMILY_SHARED")
    }


    public func finish() async {}

    public struct Transactions: AsyncSequence {
        public typealias Element = VerificationResult<Transaction>
        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> VerificationResult<Transaction>? { nil }
        }
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }

    /// 端末の外（別の端末・更新・返金）で起きた取引が届く
    public static var updates: Transactions { Transactions() }
    /// 終えていない取引（サーバーへ渡し損ねたもの）
    public static var unfinished: Transactions { Transactions() }
    /// いま有効な権利
    public static var currentEntitlements: Transactions { Transactions() }
}

public struct Product: Identifiable, Sendable {
    public let id: String
    public let type: ProductType
    public let displayName: String
    public let description: String
    public let price: Decimal
    public let displayPrice: String
    public let subscription: SubscriptionInfo?

    public struct ProductType: Equatable, Hashable, Sendable {
        public let rawValue: String
        public static let autoRenewable = ProductType(rawValue: "Auto-Renewable Subscription")
        public static let nonRenewable = ProductType(rawValue: "Non-Renewing Subscription")
        public static let consumable = ProductType(rawValue: "Consumable")
        public static let nonConsumable = ProductType(rawValue: "Non-Consumable")
    }

    public static func products<C: Collection>(for identifiers: C) async throws -> [Product] where C.Element == String { [] }

    public struct PurchaseOption: Hashable, Sendable {
        public static func appAccountToken(_ token: UUID) -> PurchaseOption { PurchaseOption() }
    }

    public enum PurchaseResult {
        case success(VerificationResult<Transaction>)
        case userCancelled
        case pending
    }

    public enum PurchaseError: Error {
        case invalidQuantity
        case productUnavailable
        case purchaseNotAllowed
        case ineligibleForOffer
        case invalidOfferIdentifier
        case invalidOfferPrice
        case invalidOfferSignature
        case missingOfferParameters
    }

    public func purchase(options: Set<PurchaseOption> = []) async throws -> PurchaseResult { .userCancelled }

    public struct SubscriptionPeriod: Equatable, Sendable {
        public enum Unit: Sendable { case day, week, month, year }
        public let unit: Unit
        public let value: Int
    }

    public struct SubscriptionInfo: Sendable {
        public let subscriptionGroupID: String
        public let subscriptionPeriod: SubscriptionPeriod

        public var status: [Status] {
            get async throws { [] }
        }

        public struct RenewalState: Equatable, Hashable, Sendable {
            public let rawValue: Int
            public static let subscribed = RenewalState(rawValue: 1)
            public static let expired = RenewalState(rawValue: 2)
            public static let inBillingRetryPeriod = RenewalState(rawValue: 3)
            public static let inGracePeriod = RenewalState(rawValue: 4)
            public static let revoked = RenewalState(rawValue: 5)
        }

        public struct RenewalInfo: Sendable {
            public let willAutoRenew: Bool
            public let autoRenewPreference: String?
            public let currentProductID: String
        }

        public struct Status: Sendable {
            public let state: RenewalState
            public let transaction: VerificationResult<Transaction>
            public let renewalInfo: VerificationResult<RenewalInfo>
        }
    }
}

public enum StoreKitError: Error {
    case unknown
    case userCancelled
    case networkError(URLError)
    case systemError(Error)
    case notAvailableInStorefront
    case notEntitled
}

public enum AppStore {
    /// 購入を App Store と合わせ直す（「購入を復元」）。サインインを求めることがある
    public static func sync() async throws {}
    public static var canMakePayments: Bool { false }
}

// MARK: - SwiftUI と重なる口（本物は StoreKit と SwiftUI の両方を読んだファイルで見える）

extension View {
    /// サブスクリプションの管理（解約・プラン変更）の画面を出す（iOS 15+）
    public func manageSubscriptionsSheet(isPresented: Binding<Bool>) -> Self { self }
}

/// App Store の評価のお願い（iOS 16+・`RootView`）
public struct RequestReviewAction {
    public func callAsFunction() {}
}

extension EnvironmentValues {
    public var requestReview: RequestReviewAction { RequestReviewAction() }
}
