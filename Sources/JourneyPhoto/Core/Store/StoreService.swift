import Combine
import Foundation
import StoreKit

/// Pro（定期購入）の StoreKit 2 の窓口（第2段階・2026-10-09）。
///
/// ## 流れ
///
/// 1. 起動したら `start()` で `Transaction.updates` を聞き始める（Apple の決まり: 起動直後から聞く。
///    更新・別の端末での購入・家族共有・返金がここに届く）
/// 2. 購入は `purchase(_:)`。`appAccountToken` に本人の印（`AppAccountToken.make(userId:)`）を添える
/// 3. 届いた取引（検証済みのものだけ）は、署名された文字列（`jwsRepresentation`）を
///    `POST /user/purchases` へ渡す。**権利を決めるのはサーバー**
/// 4. サーバーが受け取ったら `finish()` し、`deliveredRevision` を進める（画面はプロフィールを読み直す）
///
/// ## 取引を終える時（Apple のガイダンス）
///
/// **中身を渡し終えてから終える。** サーバーに届かなかった（圏外・5xx・ログイン切れ）取引は
/// 終えずに残す——`Transaction.unfinished` と次の起動の `updates` で届き直すので、
/// ログインした時（`deliverUnfinished()`）と起動時にもう一度送る。
/// サーバーが「受け取れない」と言い切った取引（ほかの人の購入など）は終える（`PurchaseDelivery`）。
/// **ただし、同じ端末で前にログインしていた人の印（`appAccountToken`）が付いた取引は送らない**
/// ——送ると 403 で終えてしまい、その人の購入が二度と自動で届かない（`belongsToSomeoneElse`）。
/// **検証に失敗した取引は送らず、終えもしない**（Apple が直せば次に検証済みで届く）
///
/// ## 復元
///
/// `restore()` は `AppStore.sync()`（App Store のサインインを求めることがある）のあと、
/// いま有効な権利（`Transaction.currentEntitlements`）をサーバーへ送り直す。
@MainActor
final class StoreService: ObservableObject {

    enum LoadState: Equatable {
        case idle, loading, loaded, failed
    }

    /// 購入の結果（画面の出し分けに使う）
    enum PurchaseOutcome: Equatable {
        /// サーバーが受け取った（Pro になった）
        case purchased
        /// 支払いは済んだが、サーバーにまだ渡せていない（あとで自動でやり直す）
        case purchasedPendingServer
        /// 承認待ち（ファミリーの「承認と購入のリクエスト」など）
        case pending
        case cancelled
        /// この購読では Pro にならない（別のアカウント・ファミリー共有。`PurchaseDelivery.message(for:)`）
        case refused(PurchaseDelivery.Refusal)
        case failed(String)
    }

    enum RestoreOutcome: Equatable {
        /// 有効な購入を見つけてサーバーへ渡した
        case restored
        /// 有効な購入が無かった
        case nothing
        /// 有効な購入はあるが、Pro にならない（別のアカウント・ファミリー共有）
        case refused(PurchaseDelivery.Refusal)
        case failed(String)
    }

    /// 読めた商品（プランごと）
    @Published private(set) var products: [ProPlan: Product] = [:]
    @Published private(set) var loadState: LoadState = .idle
    /// この端末の App Store で見える定期購入のいまの姿（設定の行）
    @Published private(set) var subscription: ProSubscriptionState?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    /// サーバーに渡し終えた回数。進んだらプロフィールを読み直す
    @Published private(set) var deliveredRevision = 0

    let prefix: String
    private var currentUserId: () -> String? = { nil }
    private var submit: ((String) async -> PurchaseDelivery.Result)?
    private var onDelivered: () -> Void = {}
    private var updatesTask: Task<Void, Never>?

    init(prefix: String = ProProducts.currentPrefix) {
        self.prefix = prefix
    }

    /// 誰が使っているかと、サーバーへの渡し方を受け取る（アプリの起動時に1回）
    func configure(currentUserId: @escaping () -> String?,
                   submit: @escaping (String) async -> PurchaseDelivery.Result,
                   onDelivered: @escaping () -> Void) {
        self.currentUserId = currentUserId
        self.submit = submit
        self.onDelivered = onDelivered
    }

    /// `Transaction.updates` を聞き始める。**起動直後に呼ぶ**（2回目以降は何もしない）
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                _ = await self.handle(result)
                await self.refreshSubscription()
            }
        }
    }

    // MARK: - 商品

    func product(_ plan: ProPlan) -> Product? { products[plan] }

    /// 商品の取り方（試験で差し替える）
    var fetchProducts: ([String]) async throws -> [Product] = { ids in
        try await Product.products(for: ids)
    }
    /// 走っている読み込み。**後から来た呼び手はこれを待つ**（2026-10-09 判断）。
    /// 読み込み中に即座に戻していた頃は、設定の節が読んでいる最中に購入を押すと、`purchase` の
    /// `loadProducts(force: true)` が読み終わる前に戻り、「App Store に接続できませんでした」を出していた
    private var loadTask: Task<Void, Never>?

    /// 商品を読む（読めていれば読み直さない。`force` で読み直す）。読んでいる最中なら、その読み込みを待つ
    func loadProducts(force: Bool = false) async {
        if let loadTask { return await loadTask.value }
        if loadState == .loaded, !force { return }
        loadState = .loading
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
            self.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        do {
            let list = try await fetchProducts(ProProducts.allIDs(prefix: prefix))
            var map: [ProPlan: Product] = [:]
            for product in list {
                if let plan = ProProducts.plan(for: product.id, prefix: prefix) { map[plan] = product }
            }
            products = map
            // 1つも無いのは失敗と同じ扱い（App Store Connect に商品が無い・審査待ちで出ていない）
            loadState = map.isEmpty ? .failed : .loaded
        } catch {
            loadState = .failed
        }
        await refreshSubscription()
    }

    // MARK: - 購入

    func purchase(_ plan: ProPlan) async -> PurchaseOutcome {
        guard !isPurchasing else { return .cancelled }
        guard let userId = currentUserId() else {
            return .failed(Labels.Common.signInRequired)
        }
        // **商品を読み直す前に「買っている最中」にする**（2026-10-09 判断）。後で立てていた頃は、
        // 商品が読めていない案内（圏外で開いた）で主ボタンを2度押すと、2度目が読み込みの最中に
        // 入り込んで「App Store に接続できませんでした」を出し、その裏で1度目の購入の画面が開いた
        isPurchasing = true
        defer { isPurchasing = false }
        if products[plan] == nil { await loadProducts(force: true) }
        guard let product = products[plan] else {
            return .failed(L("App Store に接続できませんでした。時間をおいてもう一度お試しください。",
                             "Couldn't reach the App Store. Please try again later."))
        }
        do {
            let result = try await product.purchase(options: [.appAccountToken(AppAccountToken.make(userId: userId))])
            switch result {
            case .success(let verification):
                let delivery = await handle(verification)
                await refreshSubscription()
                // 退会して作り直したアカウントで、前のアカウントの購読が返ってきた（App Store は
                // 「購読中」として前の取引を返す）。待っても通らないので「反映待ち」と言わない
                if let refusal = delivery.refusal { return .refused(refusal) }
                switch delivery.outcome {
                case .accepted: return .purchased
                case .retryLater: return .purchasedPendingServer
                case .rejected:
                    return .failed(delivery.message
                                   ?? L("購入をアカウントに結びつけられませんでした。お問い合わせください。",
                                        "We couldn't link this purchase to your account. Please contact us."))
                }
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            if let storeError = error as? StoreKitError, case .userCancelled = storeError { return .cancelled }
            return .failed(L("購入できませんでした。時間をおいてもう一度お試しください。",
                             "The purchase didn't go through. Please try again later."))
        }
    }

    // MARK: - 復元

    func restore() async -> RestoreOutcome {
        guard !isRestoring else { return .nothing }
        guard currentUserId() != nil else { return .failed(Labels.Common.signInRequired) }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            if let storeError = error as? StoreKitError, case .userCancelled = storeError { return .nothing }
            return .failed(L("App Store に接続できませんでした。時間をおいてもう一度お試しください。",
                             "Couldn't reach the App Store. Please try again later."))
        }
        var found = false
        var delivered = false
        var lastMessage: String?
        var refusal: PurchaseDelivery.Refusal?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // ファミリー共有の購読しか無いときは「復元できる購入はありません」ではなく、その理由を出す
            if transaction.ownershipType == .familyShared,
               ProProducts.plan(for: transaction.productID, prefix: prefix) != nil {
                if refusal == nil { refusal = .familyShared }
                continue
            }
            guard isOurs(transaction) else { continue }
            found = true
            let sent = await send(result.jwsRepresentation, transaction: transaction)
            if sent.outcome == .accepted {
                delivered = true
            } else if let refused = sent.refusal {
                refusal = refused
            } else if let message = sent.message {
                lastMessage = message
            }
        }
        await refreshSubscription()
        if delivered { return .restored }
        if let refusal { return .refused(refusal) }
        if found {
            return .failed(lastMessage
                           ?? L("購入をサーバーに届けられませんでした。時間をおいてもう一度お試しください。",
                                "Couldn't send your purchase to our server. Please try again later."))
        }
        return .nothing
    }

    /// 終えていない取引をサーバーへ送り直す（ログインした時・起動時）
    func deliverUnfinished() async {
        guard currentUserId() != nil else { return }
        for await result in StoreKit.Transaction.unfinished {
            _ = await handle(result)
        }
        await refreshSubscription()
    }

    // MARK: - いまの姿（設定の行）

    /// この端末の App Store で見える定期購入を読む。**表示のためだけ**（Pro かどうかはサーバーの `pro`）
    func refreshSubscription() async {
        var best: ProSubscriptionState?
        for (plan, product) in products {
            guard let statuses = try? await product.subscription?.status else { continue }
            for status in statuses {
                guard status.state == .subscribed || status.state == .inGracePeriod
                        || status.state == .inBillingRetryPeriod,
                      case .verified(let transaction) = status.transaction,
                      transaction.productID == product.id,
                      StoreTransactionFilter.counts(transaction, prefix: prefix) else { continue }
                // 同じ端末（同じ Apple ID）で前の人が買った定期購入を、次の人の設定の行に出さない
                if let userId = currentUserId(),
                   PurchaseDelivery.belongsToSomeoneElse(appAccountToken: transaction.appAccountToken, userId: userId) {
                    continue
                }
                var willRenew = true
                if case .verified(let renewal) = status.renewalInfo { willRenew = renewal.willAutoRenew }
                best = ProSubscriptionState(plan: plan, renewalDate: transaction.expirationDate,
                                            willAutoRenew: willRenew, displayPrice: product.displayPrice)
            }
        }
        subscription = best
    }

    // MARK: - 取引をサーバーへ

    private func isOurs(_ transaction: StoreKit.Transaction) -> Bool {
        StoreTransactionFilter.counts(transaction, prefix: prefix)
    }

    /// 届いた取引を1件さばく。検証済みで自分たちの商品だけ送る
    @discardableResult
    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async -> PurchaseDelivery.Result {
        guard case .verified(let transaction) = result else { return PurchaseDelivery.Result(.retryLater) }
        guard isOurs(transaction) else { return PurchaseDelivery.Result(.retryLater) }
        return await send(result.jwsRepresentation, transaction: transaction)
    }

    /// 送って、結果で終えるかを決める（終え済みの取引をもう一度終えても何も起きない）
    private func send(_ jws: String, transaction: StoreKit.Transaction) async -> PurchaseDelivery.Result {
        // ログインしていなければ送らない（終えずに残し、ログインした時に送る）
        guard let userId = currentUserId(), let submit else { return PurchaseDelivery.Result(.retryLater) }
        // ほかの人の印が付いた取引は送らず、終えもしない（その人がログインし直したときに届ける・
        // `PurchaseDelivery.belongsToSomeoneElse` の注記）
        if PurchaseDelivery.belongsToSomeoneElse(appAccountToken: transaction.appAccountToken, userId: userId) {
            return PurchaseDelivery.Result(.retryLater, message: PurchaseDelivery.otherAccountMessage, refusal: .otherAccount)
        }
        let result = await submit(jws)
        if PurchaseDelivery.shouldFinish(result.outcome) {
            await transaction.finish()
        }
        if result.outcome == .accepted {
            deliveredRevision += 1
            onDelivered()
        }
        return result
    }
}

/// さばく取引か（`StoreService` の外に置く——試験から主スレッドに縛られずに呼べるように）
enum StoreTransactionFilter {
    /// **自分たちの商品**で、**ファミリー共有ではない**（owner 2026-10-09: ファミリー共有は切ってある。
    /// `Transaction.updates`・`unfinished`・`currentEntitlements`・設定の行のどれでも数えない）
    static func counts(_ transaction: StoreKit.Transaction, prefix: String) -> Bool {
        counts(productID: transaction.productID, isFamilyShared: transaction.ownershipType == .familyShared, prefix: prefix)
    }

    /// 上の中身（本物の StoreKit の取引は試験で作れないので、値で見る口を分ける）
    static func counts(productID: String, isFamilyShared: Bool, prefix: String) -> Bool {
        ProProducts.plan(for: productID, prefix: prefix) != nil
            && PurchaseDelivery.countsAsOwnPurchase(isFamilyShared: isFamilyShared)
    }
}
