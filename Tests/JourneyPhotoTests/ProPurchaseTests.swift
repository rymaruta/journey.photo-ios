import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Pro の購入（第2段階・2026-10-09）: 商品名・購入者の印・取引を終えるか・設定の行の文字。
final class ProPurchaseTests: XCTestCase {

    // MARK: - 購入者の印（サーバーと同じ UUIDv5）

    /// 🔴 **サーバーのテストと同じ値**（`api-user/src/__tests__/appStore.test.ts`）。
    /// ずれると、買った取引がすべて「別のアカウントで購入された」（403）になる
    func testAppAccountTokenMatchesServerVector() {
        XCTAssertEqual(AppAccountToken.make(userId: "7b1c2d3e-0000-4000-8000-000000000001").uuidString.lowercased(),
                       "6d109146-376e-5175-8e4c-2439a6bc3c3b")
        // Python の uuid.uuid5 で作った値（名前が UTF-8 で読まれること）
        XCTAssertEqual(AppAccountToken.make(userId: "user-123").uuidString.lowercased(),
                       "18196bb8-1702-5880-8d3c-5a7c0a267af9")
        XCTAssertEqual(AppAccountToken.make(userId: "丸田").uuidString.lowercased(),
                       "2951b28c-4515-50ad-837f-dec7691b4dcd")
    }

    /// 名前空間はサーバーの `APP_ACCOUNT_TOKEN_NAMESPACE` と同じ（変えない）
    func testNamespaceIsServerConstant() {
        XCTAssertEqual(AppAccountToken.namespace.uuidString.lowercased(), "5bbfc476-7442-4f3d-8d7e-4f55931ae30f")
    }

    /// UUIDv5 の作り方そのもの（RFC の DNS 名前空間の既知の値）
    func testUUIDv5KnownValue() {
        let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        XCTAssertEqual(AppAccountToken.uuidV5(namespace: dns, name: "www.example.com").uuidString.lowercased(),
                       "2ed6657d-e927-568b-95e1-2665a8aea6a2")
    }

    /// SHA-1（RFC 3174 の既知の値・64 バイトの区切りをまたぐもの）
    func testSHA1KnownValues() {
        func hex(_ s: String) -> String { SHA1.digest(Array(s.utf8)).map { String(format: "%02x", $0) }.joined() }
        XCTAssertEqual(hex(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(hex("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                       "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
    }

    // MARK: - 商品名

    /// サーバーの `proProductIds(bundleId)` と同じ（`<束>.pro.monthly` / `<束>.pro.yearly`）
    func testProductIDsFollowBundle() {
        XCTAssertEqual(Set(ProProducts.allIDs(prefix: "com.journeyphoto.JourneyPhoto")),
                       ["com.journeyphoto.JourneyPhoto.pro.monthly", "com.journeyphoto.JourneyPhoto.pro.yearly"])
        XCTAssertEqual(ProProducts.productID(.monthly, prefix: "com.journeyphoto.JourneyPhoto.staging"),
                       "com.journeyphoto.JourneyPhoto.staging.pro.monthly")
        XCTAssertEqual(ProProducts.plan(for: "com.journeyphoto.JourneyPhoto.pro.yearly", prefix: "com.journeyphoto.JourneyPhoto"),
                       .yearly)
        // staging の束で本番の商品名は自分たちのものとして扱わない（逆も）
        XCTAssertNil(ProProducts.plan(for: "com.journeyphoto.JourneyPhoto.pro.yearly",
                                      prefix: "com.journeyphoto.JourneyPhoto.staging"))
        XCTAssertNil(ProProducts.plan(for: "com.example.other", prefix: "com.journeyphoto.JourneyPhoto"))
    }

    /// 板 63 の並び（1年ごとが左・選んである）
    func testPlanOrderMatchesBoard() {
        XCTAssertEqual(ProPlan.allCases, [.yearly, .monthly])
        XCTAssertEqual(ProPlan.yearly.cycleLabel, "1年ごと")
        XCTAssertEqual(ProPlan.monthly.cycleLabel, "月ごと")
    }

    /// 商品が読めない（staging・圏外）ときは板どおりの値段
    func testFallbackPriceLine() {
        XCTAssertEqual(ProPlan.yearly.priceLine(displayPrice: nil), "¥5,000 / 年")
        XCTAssertEqual(ProPlan.monthly.priceLine(displayPrice: nil), "¥500 / 月")
        XCTAssertEqual(ProPlan.monthly.priceLine(displayPrice: "¥480"), "¥480 / 月")
    }

    /// 🔴 StoreKit の設定ファイルの商品名がアプリの求める名前と同じ（本番と staging の両方）
    func testStoreKitConfigurationHasProducts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Config/JourneyPhotoPro.storekit"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(json["subscriptionGroups"] as? [[String: Any]])
        var ids: Set<String> = []
        var prices: [String: String] = [:]
        for group in groups {
            for sub in (group["subscriptions"] as? [[String: Any]]) ?? [] {
                if let id = sub["productID"] as? String {
                    ids.insert(id)
                    prices[id] = sub["displayPrice"] as? String
                    // 無料の試用は付けない（owner の決定）
                    XCTAssertTrue(sub["introductoryOffer"] is NSNull || sub["introductoryOffer"] == nil, id)
                }
            }
        }
        for prefix in ["com.journeyphoto.JourneyPhoto", "com.journeyphoto.JourneyPhoto.staging"] {
            for id in ProProducts.allIDs(prefix: prefix) { XCTAssertTrue(ids.contains(id), id) }
        }
        XCTAssertEqual(prices["com.journeyphoto.JourneyPhoto.pro.monthly"], "500")
        XCTAssertEqual(prices["com.journeyphoto.JourneyPhoto.pro.yearly"], "5000")
        XCTAssertEqual(groups.first?["name"] as? String, ProProducts.groupName)
    }

    // MARK: - 取引を終えるか

    func testDeliveryOutcomeByStatus() {
        XCTAssertEqual(PurchaseDelivery.outcome(statusCode: 200), .accepted)
        for code in [400, 403, 410] {
            XCTAssertEqual(PurchaseDelivery.outcome(statusCode: code), .rejected, "\(code)")
        }
        // ログイン切れ・重なり・サーバーの不調・設定なし・送れなかった → あとでやり直す（終えない）
        for code in [401, 409, 429, 500, 503] {
            XCTAssertEqual(PurchaseDelivery.outcome(statusCode: code), .retryLater, "\(code)")
        }
        XCTAssertEqual(PurchaseDelivery.outcome(statusCode: nil), .retryLater)
    }

    /// Apple の決まり: 渡し終えてから終える。やり直す取引は終えない
    func testFinishOnlyWhenServerDecided() {
        XCTAssertTrue(PurchaseDelivery.shouldFinish(.accepted))
        XCTAssertTrue(PurchaseDelivery.shouldFinish(.rejected))
        XCTAssertFalse(PurchaseDelivery.shouldFinish(.retryLater))
    }

    func testDeliveryResultDropsEmptyMessage() {
        XCTAssertNil(PurchaseDelivery.Result(.rejected, message: "").message)
        XCTAssertEqual(PurchaseDelivery.Result(.rejected, message: "別のアカウント").message, "別のアカウント")
    }

    /// 🔴 **前にログインしていた人の取引を、次の人の名前で送って終えない**（2026-10-09）。
    /// A が買う → サーバーに届かず残る → 同じ端末で B がログイン → 送り直しが 403 → 終えて、
    /// A の購入が二度と自動で届かなかった
    func testOtherPersonsTransactionIsNotSent() {
        let a = "7b1c2d3e-0000-4000-8000-000000000001", b = "user-123"
        XCTAssertTrue(PurchaseDelivery.belongsToSomeoneElse(appAccountToken: AppAccountToken.make(userId: a), userId: b))
        XCTAssertFalse(PurchaseDelivery.belongsToSomeoneElse(appAccountToken: AppAccountToken.make(userId: b), userId: b))
        // 印の無い取引（コードで買った等）はサーバーに任せる
        XCTAssertFalse(PurchaseDelivery.belongsToSomeoneElse(appAccountToken: nil, userId: b))
    }

    /// 送る口・設定の行の両方が、ほかの人の取引を見分けている（Linux の模型では取引を作れないので文で確かめる）
    func testStoreServiceChecksOwnerBeforeSending() throws {
        let src = try source("Sources/JourneyPhoto/Core/Store/StoreService.swift")
        let send = try XCTUnwrap(src.range(of: "private func send("))
        let body = String(src[send.lowerBound...])
        let check = try XCTUnwrap(body.range(of: "belongsToSomeoneElse"))
        let submit = try XCTUnwrap(body.range(of: "await submit(jws)"))
        XCTAssertLessThan(check.lowerBound, submit.lowerBound, "送る前に見分ける")
        let refresh = try XCTUnwrap(src.range(of: "func refreshSubscription()"))
        let refreshBody = String(src[refresh.lowerBound..<send.lowerBound])
        XCTAssertTrue(refreshBody.contains("belongsToSomeoneElse"), "前の人の定期購入を設定の行に出さない")
    }

    /// 🔴 主ボタンを2度押しても2度目が入り込まない: 商品を読み直す**前に**「買っている最中」にする
    func testPurchaseMarksBusyBeforeLoadingProducts() throws {
        let src = try source("Sources/JourneyPhoto/Core/Store/StoreService.swift")
        let start = try XCTUnwrap(src.range(of: "func purchase(_ plan: ProPlan)"))
        let body = String(src[start.lowerBound...])
        let busy = try XCTUnwrap(body.range(of: "isPurchasing = true"))
        let load = try XCTUnwrap(body.range(of: "await loadProducts(force: true)"))
        XCTAssertLessThan(busy.lowerBound, load.lowerBound)
    }

    /// 🔴 **裏から戻るたびに、渡し損ねた購入を送り直す**（案内の「アプリを開いたときに自動でやり直します」）。
    /// ログインした時と起動し直した時だけだった頃は、閉じずに戻しても Pro にならなかった
    func testRedeliversUnfinishedWhenReturningToForeground() throws {
        let src = try source("Sources/JourneyPhoto/App/JourneyPhotoApp.swift")
        let start = try XCTUnwrap(src.range(of: ".onChange(of: scenePhase)"))
        let end = try XCTUnwrap(src.range(of: ".task(id: auth.state)", range: start.upperBound..<src.endIndex))
        XCTAssertTrue(src[start.upperBound..<end.lowerBound].contains("store.deliverUnfinished()"))
    }

    // MARK: - 別のアカウントの購読・ファミリー共有（owner 2026-10-09）

    /// 🔴 サーバーの 403（この購読は別のアカウントのもの＝退会して作り直したアカウントなど）は
    /// 「別のアカウント」として返し、終える（待っても通らない）
    func testServer403IsOtherAccount() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.reset()
        defer { StubProtocol.reset() }
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "ID"), session: URLSession(configuration: config))
        func submit(_ status: Int, _ body: String) async -> PurchaseDelivery.Result {
            StubProtocol.respond(status: status, body: body)
            return await PurchaseService(api: api).submit(signedTransaction: "a.b.c")
        }
        // 403 linked_to_other_account（退会した前のアカウントの購読）→ 別のアカウント・終える
        let linked = await submit(403, #"{"error":"別のアカウントで購入されたサブスクリプションです","code":"linked_to_other_account"}"#)
        XCTAssertEqual(linked.refusal, .otherAccount)
        XCTAssertEqual(linked.outcome, .rejected)
        XCTAssertTrue(PurchaseDelivery.shouldFinish(linked.outcome))
        // 403 family_shared_not_supported → ファミリー共有・終える
        let family = await submit(403, #"{"error":"ファミリー共有のサブスクリプションでは Pro になりません","code":"family_shared_not_supported"}"#)
        XCTAssertEqual(family.refusal, .familyShared)
        XCTAssertTrue(PurchaseDelivery.shouldFinish(family.outcome))
        // 409 claimed_by_other_account（ほかの生きているアカウント）→ 別のアカウント（終えないのは今までどおり）
        let claimed = await submit(409, #"{"error":"このサブスクリプションは別のアカウントで使われています","code":"claimed_by_other_account"}"#)
        XCTAssertEqual(claimed.refusal, .otherAccount)
        XCTAssertEqual(claimed.outcome, .retryLater)
        // 409 の書き込みの重なり（code なし）・500 は理由なし（やり直す）
        let conflict = await submit(409, #"{"error":"他の変更と重なりました。もう一度お試しください"}"#)
        XCTAssertNil(conflict.refusal)
        let server = await submit(500, #"{"error":"x"}"#)
        XCTAssertNil(server.refusal)
        // 🔴 日本語の本文では見ない: 本文が同じでも code が違えば理由も違う
        let wording = await submit(403, #"{"error":"別のアカウントで購入されたサブスクリプションです","code":"family_shared_not_supported"}"#)
        XCTAssertEqual(wording.refusal, .familyShared)
    }

    /// 失敗の本文の `code` を読む
    func testDecodesErrorCode() {
        XCTAssertEqual(APIClient.errorCode(from: Data(#"{"error":"x","code":"linked_to_other_account"}"#.utf8)), "linked_to_other_account")
        XCTAssertNil(APIClient.errorCode(from: Data(#"{"error":"x"}"#.utf8)))
        XCTAssertNil(APIClient.errorCode(from: Data(#"{"error":"x","code":""}"#.utf8)))
        XCTAssertNil(APIClient.errorCode(from: Data("not json".utf8)))
        XCTAssertNil(APIClient.errorCode(from: nil))
    }

    /// `code` → 理由 → 画面の1行（owner 2026-10-09 の文言）
    func testRefusalMapping() {
        XCTAssertEqual(PurchaseDelivery.refusal(statusCode: 403, code: "linked_to_other_account"), .otherAccount)
        XCTAssertEqual(PurchaseDelivery.refusal(statusCode: 409, code: "claimed_by_other_account"), .otherAccount)
        XCTAssertEqual(PurchaseDelivery.refusal(statusCode: 403, code: "family_shared_not_supported"), .familyShared)
        XCTAssertEqual(PurchaseDelivery.refusal(statusCode: 403, code: nil), .otherAccount, "code を返す前のサーバーの 403")
        XCTAssertNil(PurchaseDelivery.refusal(statusCode: 409, code: nil))
        XCTAssertNil(PurchaseDelivery.refusal(statusCode: 400, code: nil))
        XCTAssertNil(PurchaseDelivery.refusal(statusCode: nil, code: nil))
        XCTAssertEqual(PurchaseDelivery.message(for: .otherAccount), "この Apple ID の購読は、別のアカウントで使われています。")
        XCTAssertEqual(PurchaseDelivery.message(for: .familyShared), "ファミリー共有の購読では Pro を使えません。")
    }

    /// 購入・復元・案内が「別のアカウント」を、回し続けず・Pro にせず・ふつうの字で出す（Linux では描けないので文で）
    func testOtherAccountIsShownAsPlainNote() throws {
        let store = try source("Sources/JourneyPhoto/Core/Store/StoreService.swift")
        XCTAssertTrue(store.contains("if let refusal = delivery.refusal { return .refused(refusal) }"), "購入: 反映待ちと言わない")
        XCTAssertTrue(store.contains("if let refusal { return .refused(refusal) }"), "復元")
        let paywall = try source("Sources/JourneyPhoto/Features/Pro/PaywallView.swift")
        XCTAssertEqual(paywall.components(separatedBy: "show(PurchaseDelivery.message(for: refusal), error: false)").count - 1, 2,
                       "購入と復元の両方で、赤ではない字で出す")
    }

    /// 🔴 **ファミリー共有の取引は Pro として扱わない**（`Transaction.updates`・`unfinished` で届いた分）
    func testFamilySharedTransactionIsIgnoredFromUpdates() {
        let prefix = "com.journeyphoto.JourneyPhoto"
        let id = ProProducts.productID(.monthly, prefix: prefix)
        XCTAssertTrue(StoreTransactionFilter.counts(productID: id, isFamilyShared: false, prefix: prefix))
        XCTAssertFalse(StoreTransactionFilter.counts(productID: id, isFamilyShared: true, prefix: prefix), "ファミリー共有は送らない")
        XCTAssertFalse(StoreTransactionFilter.counts(productID: "com.example.other", isFamilyShared: false, prefix: prefix))
        // 届いた取引をさばく口がこの見分けを通る
        let src = (try? source("Sources/JourneyPhoto/Core/Store/StoreService.swift")) ?? ""
        let handle = src.range(of: "private func handle(")
        XCTAssertNotNil(handle)
        if let handle {
            XCTAssertTrue(src[handle.lowerBound...].prefix(400).contains("isOurs(transaction)"))
        }
    }

    /// 🔴 **復元（`Transaction.currentEntitlements`）と設定の行でも、ファミリー共有を数えない**
    func testFamilySharedEntitlementIsIgnoredOnRestore() throws {
        let src = try source("Sources/JourneyPhoto/Core/Store/StoreService.swift")
        let restore = try XCTUnwrap(src.range(of: "for await result in StoreKit.Transaction.currentEntitlements"))
        XCTAssertTrue(src[restore.lowerBound...].prefix(700).contains("isOurs(transaction)"))
        XCTAssertTrue(src.contains("StoreTransactionFilter.counts(transaction, prefix: prefix) else { continue }"), "設定の行")
        XCTAssertTrue(src.contains("isFamilyShared: transaction.ownershipType == .familyShared"), "本物の取引の持ち方で見る")
        XCTAssertFalse(PurchaseDelivery.countsAsOwnPurchase(isFamilyShared: true))
        XCTAssertTrue(PurchaseDelivery.countsAsOwnPurchase(isFamilyShared: false))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 送る形はサーバーの名前（`signedTransaction`）
    func testPurchaseBodyShape() throws {
        let data = try JSONEncoder().encode(PurchaseService.Body(signedTransaction: "a.b.c"))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"signedTransaction":"a.b.c"}"#)
    }

    // MARK: - 設定の行（板 43）

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testSettingsDetailForPro() {
        let state = ProSubscriptionState(plan: .monthly, renewalDate: date("2026-11-09T03:00:00Z"),
                                         willAutoRenew: true, displayPrice: "¥500")
        XCTAssertEqual(ProStatusText.settingsDetail(isPro: true, state: state, timeZone: tokyo),
                       "月 ¥500 · 次の更新 2026.11.09 · App Store で管理")
    }

    /// 解約を予約している → 「2026.11.09 まで」
    func testSettingsDetailWhenCancelled() {
        let state = ProSubscriptionState(plan: .yearly, renewalDate: date("2027-10-09T03:00:00Z"),
                                         willAutoRenew: false, displayPrice: nil)
        XCTAssertEqual(ProStatusText.settingsDetail(isPro: true, state: state, timeZone: tokyo),
                       "年 ¥5,000 · 2027.10.09 まで · App Store で管理")
    }

    /// Pro だが、この端末の App Store では読めない（別の Apple ID など）
    func testSettingsDetailProWithoutState() {
        XCTAssertEqual(ProStatusText.settingsDetail(isPro: true, state: nil), "App Store で管理")
    }

    func testSettingsDetailNotPro() {
        XCTAssertEqual(ProStatusText.settingsDetail(isPro: false, state: nil),
                       "月 ¥500 から。サポーターバッジも付きます")
        // 🔴 App Store の値段が読めたらそれを出す（日本以外の App Store で「¥500」と出さない）
        XCTAssertEqual(ProStatusText.settingsDetail(isPro: false, state: nil, monthlyPrice: "$4.99"),
                       "月 $4.99 から。サポーターバッジも付きます")
        XCTAssertTrue(SupporterText.note(monthlyPrice: "$4.99").hasSuffix("月 $4.99。"))
        XCTAssertTrue(SupporterText.note(monthlyPrice: nil).hasSuffix("月 ¥500。"))
    }

    func testSupporterRowDetail() {
        XCTAssertEqual(ProStatusText.supporterDetail(number: 1), "No. 0001 · 手に取って回せます")
    }

    private func profile(_ json: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
    }

    func testNameSideRowDetail() throws {
        let pro = try profile("""
        {"userId":"u1","badges":{"earlyUser":{"tier":1,"at":"2026-09-01T00:00:00Z"}},
         "displayBadge":"earlyUser","pro":true,"proMarkStyle":"iris"}
        """)
        XCTAssertEqual(ProStatusText.nameSideDetail(pro), "初期ユーザー · Pro マークは 絞り羽根")
        let free = try profile(#"{"userId":"u2","pro":false}"#)
        XCTAssertEqual(ProStatusText.nameSideDetail(free), "バッジなし")
    }
}

/// サポーターの印（プロフィールの `supporter`）とサポーター証の文字（板 64）
final class SupporterTests: XCTestCase {

    private func profile(_ json: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
    }

    func testReadsSupporter() throws {
        let p = try profile("""
        {"userId":"u1","pro":true,"supporter":{"number":12,"since":"2026-10-09T01:00:00.000Z","months":13}}
        """)
        XCTAssertTrue(p.isPro)
        XCTAssertEqual(p.supporterInfo, SupporterInfo(number: 12, since: "2026-10-09T01:00:00.000Z", months: 13))
    }

    /// 古いサーバー・申し込んだことのない人: 無い
    func testNoSupporter() throws {
        XCTAssertNil(try profile(#"{"userId":"u1"}"#).supporterInfo)
    }

    /// **形が違っても全体を落とさない**（番号の無いものはサポーターではない）
    func testMalformedSupporterDoesNotBreakProfile() throws {
        XCTAssertNil(try profile(#"{"userId":"u1","supporter":{"since":"2026-10-09"}}"#).supporterInfo)
        XCTAssertNil(try profile(#"{"userId":"u1","supporter":"yes"}"#).supporterInfo)
        XCTAssertNil(try profile(#"{"userId":"u1","supporter":{"number":0}}"#).supporterInfo)
        // サーバーは since を空の文字で返すことがある（読めない日付）
        let p = try profile(#"{"userId":"u1","displayName":"丸田","supporter":{"number":3,"since":"","months":-2}}"#)
        XCTAssertEqual(p.supporterInfo?.number, 3)
        XCTAssertEqual(p.supporterInfo?.months, 0)
        XCTAssertEqual(p.name, "丸田")
    }

    func testCardText() {
        XCTAssertEqual(SupporterText.numberLabel(1), "No. 0001")
        XCTAssertEqual(SupporterText.numberLabel(12345), "No. 12345")
        XCTAssertEqual(SupporterText.since("2026-10-08T16:00:00Z", timeZone: TimeZone(identifier: "Asia/Tokyo")!), "2026.10")
        XCTAssertNil(SupporterText.since(""))
        XCTAssertNil(SupporterText.since(nil))
        XCTAssertEqual(SupporterText.monthOrdinal(0), 1)
        XCTAssertEqual(SupporterText.monthOrdinal(12), 12)
    }

    /// 12・24・36 か月で1つずつ（サーバーの `supporterYearTier`）
    func testYearMedals() {
        XCTAssertEqual(SupporterText.yearsReached(months: 11), 0)
        XCTAssertEqual(SupporterText.yearsReached(months: 12), 1)
        XCTAssertEqual(SupporterText.yearsReached(months: 35), 2)
        XCTAssertEqual(SupporterText.yearsReached(months: 99), 3)
        // サーバーの段の方が進んでいればそちら（段は下がらない）・3 を超えない
        XCTAssertEqual(SupporterText.yearsReached(months: 5, badgeTier: 2), 2)
        XCTAssertEqual(SupporterText.yearsReached(months: 40, badgeTier: nil), 3)
        XCTAssertEqual(SupporterText.yearsReached(months: 0, badgeTier: 9), 3)
        XCTAssertEqual(SupporterText.yearLabel(1), "1年目")
        XCTAssertEqual(SupporterText.yearImage(2), "medal-year-2")
        XCTAssertEqual(SupporterText.yearImage(7), "medal-year-3")
    }

    func testCardAccessibilityLabel() {
        let face = SupporterCardFace(name: "丸田", handle: "maruta", number: 1, since: "2026.10")
        XCTAssertEqual(face.accessibilityLabel, "サポーター証、No. 0001、丸田、@maruta、MEMBER SINCE 2026.10")
    }

    /// 板 64 の札（342×216・角 16）。狭い画面では左右 24 を残して縮める
    func testCardLayout() {
        XCTAssertEqual(SupporterCardLayout.aspect, 342.0 / 216.0, accuracy: 1e-9)
        XCTAssertEqual(SupporterCardLayout.cardWidth(screenWidth: 390), 342)
        XCTAssertEqual(SupporterCardLayout.cardWidth(screenWidth: 320), 272)
        XCTAssertEqual(SupporterCardLayout.cardWidth(screenWidth: 430), 342)
    }

    /// 金の小口（板 Badge3D）の色の段
    func testGiltEdgeStops() {
        let stops: [(Double, (Double, Double, Double))] = [(0, (0, 0, 0)), (1, (100, 200, 50))]
        let mid = SupporterCardTextures.interpolate(stops, at: 0.5)
        XCTAssertEqual(mid.0, 50, accuracy: 1e-9)
        XCTAssertEqual(mid.1, 100, accuracy: 1e-9)
        XCTAssertEqual(mid.2, 25, accuracy: 1e-9)
        XCTAssertEqual(SupporterCardTextures.interpolate(stops, at: -1).1, 0)
        XCTAssertEqual(SupporterCardTextures.interpolate(stops, at: 2).1, 200)
    }
}

/// Pro 限定のバッジ（サポーター章・続けた年・季節の章）
final class ProBadgeTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func day(_ y: Int, _ m: Int, _ d: Int = 15) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tokyo
        return cal.date(from: c)!
    }

    /// サーバーの `parseProSeasonKey` と同じ読み方
    func testParseSeasonKeys() {
        XCTAssertEqual(ProChapters.parse("proAutumn2026"), ProChapters.Chapter(season: .autumn, year: 2026))
        XCTAssertEqual(ProChapters.parse("proWinter2999")?.year, 2999)
        XCTAssertNil(ProChapters.parse("proAutumn2025"))   // 2026 より前は鍵にしない
        XCTAssertNil(ProChapters.parse("proautumn2026"))
        XCTAssertNil(ProChapters.parse("proAutumn20261"))
        XCTAssertNil(ProChapters.parse("proAutumn"))
        XCTAssertNil(ProChapters.parse("supporter"))
        XCTAssertEqual(ProChapters.Chapter(season: .spring, year: 2027).key, "proSpring2027")
    }

    /// 板 BadgePicker（2026年10月）: 春 2027・夏 2027・秋 2026・冬 2026。**冬は12月の年**
    func testUpcomingSeasons() {
        XCTAssertEqual(ProChapters.upcoming(now: day(2026, 10), timeZone: tokyo).map(\.key),
                       ["proSpring2027", "proSummer2027", "proAutumn2026", "proWinter2026"])
        // 1月はいまの冬（前の年の鍵）
        XCTAssertEqual(ProChapters.upcoming(now: day(2027, 1), timeZone: tokyo).map(\.key),
                       ["proSpring2027", "proSummer2027", "proAutumn2027", "proWinter2026"])
        XCTAssertEqual(ProChapters.upcoming(now: day(2026, 12), timeZone: tokyo).map(\.key),
                       ["proSpring2027", "proSummer2027", "proAutumn2027", "proWinter2026"])
    }

    /// 板の「PRO 限定」の並び: サポーター → 季節の章 → 暁・構図・圏外。持っているものは外す
    func testLockedItems() {
        let none = ProChapters.lockedItems(owned: BadgeSet(), now: day(2026, 10))
        XCTAssertEqual(none.map(\.name), ["サポーター", "春 2027", "夏 2027", "秋 2026", "冬 2026", "暁", "構図", "圏外"])
        let owned = BadgeSet([EarnedBadge(key: "supporter", tier: 1, at: nil),
                              EarnedBadge(key: "proAutumn2026", tier: 1, at: nil)])
        XCTAssertEqual(ProChapters.lockedItems(owned: owned, now: day(2026, 10)).map(\.id),
                       ["proSpring2027", "proSummer2027", "proWinter2026", "dawn", "compose", "summit"])
    }

    func testCatalogKnowsProKeys() {
        XCTAssertTrue(BadgeCatalog.isKnown("supporter"))
        XCTAssertTrue(BadgeCatalog.isKnown("supporterYear"))
        XCTAssertTrue(BadgeCatalog.isKnown("proAutumn2026"))
        // 絵の無い年の章は出さない
        XCTAssertFalse(BadgeCatalog.isKnown("proAutumn2027"))
        XCTAssertTrue(BadgeCatalog.isPro("proWinter2026"))
        XCTAssertFalse(BadgeCatalog.isPro("morning"))
        XCTAssertEqual(BadgeCatalog.metal("supporterYear", tier: 2), .brass)
        XCTAssertEqual(BadgeCatalog.metal("proAutumn2026", tier: 1), .brass)
        XCTAssertEqual(BadgeCatalog.name("proAutumn2026"), "秋 2026")
        XCTAssertEqual(BadgeCatalog.fullName("proAutumn2026", tier: 1), "秋の章 2026")
        XCTAssertEqual(BadgeCatalog.fullName("supporterYear", tier: 2), "続けた年 · 2年目")
        XCTAssertEqual(BadgeCatalog.discRatio("proAutumn2026"), 0.91)
    }

    func testProImagesNames() {
        XCTAssertEqual(BadgeCatalog.largeImage("proAutumn2026", tier: 1), "medal-pro-autumn-2026")
        XCTAssertEqual(BadgeCatalog.smallImage("proAutumn2026", tier: 1), "medal-pro-autumn-2026-s")
        XCTAssertEqual(BadgeCatalog.smallImage("supporter", tier: 1), "medal-supporter-s")
        // 続けた年は小さい絵を持たない（大きい絵を縮める）
        XCTAssertEqual(BadgeCatalog.smallImage("supporterYear", tier: 3), "medal-year-3")
    }

    /// 🔴 **引く絵がすべて絵の入れ物に在る**（無いと実機で黙って空になる）
    func testEveryProImageExists() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var names: Set<String> = ["supporter-card-front", "supporter-card-back"]
        for key in ["supporter", "proSpring2027", "proSummer2027", "proAutumn2026", "proWinter2026"] {
            names.insert(BadgeCatalog.largeImage(key, tier: 1))
            names.insert(BadgeCatalog.smallImage(key, tier: 1))
        }
        for tier in 1...3 { names.insert(BadgeCatalog.largeImage("supporterYear", tier: tier)) }
        for item in ProChapters.lockedItems(owned: BadgeSet(), now: Date()) { names.insert(item.image) }
        names.insert(BadgeCatalog.Metal.brass.reverseImage)
        names.insert(BadgeCatalog.Metal.brass.edgeImage)
        let assets = root.appendingPathComponent("Sources/JourneyPhoto/Assets.xcassets")
        let found = Set((FileManager.default.enumerator(atPath: assets.path)?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix(".imageset") }
            .map { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".imageset", with: "") })
        for name in names { XCTAssertTrue(found.contains(name), name) }
    }

    /// 棚: 季節の章は持っているものだけ・年 → 春夏秋冬の順で、決まった鍵の後ろ
    func testShelfAndOwnedIncludeChapters() {
        let badges = BadgeSet([EarnedBadge(key: "proWinter2026", tier: 1, at: nil),
                               EarnedBadge(key: "proAutumn2026", tier: 1, at: nil),
                               EarnedBadge(key: "proAutumn2027", tier: 1, at: nil),   // 絵が無い
                               EarnedBadge(key: "supporter", tier: 1, at: nil)])
        XCTAssertEqual(BadgeCatalog.owned(badges).map(\.key), ["supporter", "proAutumn2026", "proWinter2026"])
        let shelf = BadgeCatalog.shelf(badges: badges, progress: nil).map(\.key)
        XCTAssertEqual(shelf, ["supporter", "proAutumn2026", "proWinter2026"])
    }
}
