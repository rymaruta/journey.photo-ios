import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 旅のトランクの読み直し（2026-10-17・別の担当の確かめの指摘）を振る舞いで見張る
final class TrunkReviewFixesTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        session = URLSession(configuration: config)
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func trunkService() -> TrunkService {
        TrunkService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                    tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    private func label(_ id: String, country: String? = nil) -> String {
        let c = country.map { #","country":"\#($0)""# } ?? ""
        return #"{"id":"\#(id)","kind":"place","place":{"name":"京都"\#(c)},"seed":1,"at":"2026-10-17T00:00:00Z"}"#
    }

    // MARK: 1. 口が無い間は入口を出さない

    func testDecideEntryFromResponse() {
        XCTAssertEqual(TrunkAvailabilityRule.decide(nil), true)
        XCTAssertEqual(TrunkAvailabilityRule.decide(APIError.server(status: 404, message: "")), false, "道の無い 404 で出している")
        XCTAssertEqual(TrunkAvailabilityRule.decide(APIError.server(status: 403, message: "")), false)
        XCTAssertNil(TrunkAvailabilityRule.decide(APIError.unreachable), "圏外で行を消している")
        XCTAssertNil(TrunkAvailabilityRule.decide(APIError.server(status: 500, message: "")))
        XCTAssertNil(TrunkAvailabilityRule.decide(APIError.server(status: 404, message: "ラベルが見つかりません")),
                     "口が在っての 404（本文あり）は口が無いとは言わない")
    }

    @MainActor
    func testEntryAppearsOnlyAfterTheServerAnswers() async {
        let defaults = UserDefaults(suiteName: "trunk-availability-\(UUID().uuidString)")!
        let availability = TrunkAvailability(defaults: defaults)
        // 口が無い（API Gateway の道の無い 404 は本文に error が無い）
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 404, body: #"{"message":"Not Found"}"#)]
        await availability.refresh(userId: "u1", service: trunkService(), preview: false)
        XCTAssertFalse(availability.isAvailable)
        // 口が出た
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[]}"#)]
        await availability.refresh(userId: "u1", service: trunkService(), preview: false)
        XCTAssertTrue(availability.isAvailable)
        // 一時の失敗では消さない・次に開いたときは読み終わる前から出す（覚えている）
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 500, body: "")]
        let again = TrunkAvailability(defaults: defaults)
        await again.refresh(userId: "u1", service: trunkService(), preview: false)
        XCTAssertTrue(again.isAvailable)
        // 別の人は別に数える・ログアウトしたら出さない
        await again.refresh(userId: "u2", service: trunkService(), preview: false)
        XCTAssertFalse(again.isAvailable)
        await again.refresh(userId: nil, service: trunkService(), preview: false)
        XCTAssertFalse(again.isAvailable)
    }

    // MARK: 3. 通知の説明 → 評価 → 届いた画面の順

    func testGateOrder() {
        var s = PostModalSnapshot(pushPrimerDeciding: true, trunkPending: true)
        XCTAssertFalse(PostModalGate.trunkMayShow(s), "通知の説明が決める前に届いた画面を出した")
        XCTAssertFalse(PostModalGate.reviewWaitIsOver(s))
        s.pushPrimerDeciding = false
        s.reviewDeciding = true
        XCTAssertFalse(PostModalGate.trunkMayShow(s), "評価のお願いが決める前に届いた画面を出した")
        XCTAssertFalse(PostModalGate.reviewMayAsk(s), "届いた画面が残っているのに評価を頼んだ")
        s.reviewDeciding = false
        XCTAssertTrue(PostModalGate.trunkMayShow(s))
        s.trunkPending = false
        s.trunkShowing = true
        XCTAssertFalse(PostModalGate.reviewMayAsk(s), "届いた画面の上に評価の窓を重ねた")
        XCTAssertFalse(PostModalGate.trunkMayShow(s), "届いた画面を二重に出した")
        s.trunkShowing = false
        XCTAssertTrue(PostModalGate.reviewMayAsk(s))
        XCTAssertFalse(PostModalGate.reviewMayAsk(PostModalSnapshot(modalPresenting: true)))
        XCTAssertFalse(PostModalGate.trunkMayShow(PostModalSnapshot(pushPrimerShowing: true)))
    }

    /// 待ちの流れ: 投稿の画面 → 通知の説明 → 評価の判断 が順に終わってから、届いた画面の番が来る
    @MainActor
    func testWaitFollowsTheTimeline() async {
        let timeline: [PostModalSnapshot] = [
            PostModalSnapshot(modalPresenting: true, trunkPending: true),
            PostModalSnapshot(pushPrimerDeciding: true, trunkPending: true),
            PostModalSnapshot(pushPrimerShowing: true, trunkPending: true),
            PostModalSnapshot(reviewDeciding: true, trunkPending: true),
            PostModalSnapshot(trunkPending: true),
        ]
        var tick = 0
        let ready = await PostModalGate.wait(tries: 10, snapshot: { timeline[min(tick, timeline.count - 1)] },
                                             until: PostModalGate.trunkMayShow, sleep: { tick += 1 })
        XCTAssertTrue(ready)
        XCTAssertEqual(tick, 4, "届いた画面の番が早すぎる・遅すぎる")
        // 待ちきれなければ出さない
        var ticks = 0
        let never = await PostModalGate.wait(tries: 3, snapshot: { PostModalSnapshot(modalPresenting: true) },
                                             until: PostModalGate.trunkMayShow, sleep: { ticks += 1 })
        XCTAssertFalse(never)
        XCTAssertEqual(ticks, 3)
    }

    // MARK: 4. 読めていないときの「トランクに貼る」

    @MainActor
    func testStickReloadsFirstAndSaysWhenItCannot() async {
        let model = TrunkViewModel(preview: nil)
        model.bind(trunkService())
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 500, body: #"{"error":"処理に失敗しました"}"#)]
        let failed = await model.stickEnsuringLoaded("p-1")
        XCTAssertFalse(failed)
        XCTAssertEqual(model.actionError, "処理に失敗しました", "読めなかったのに黙っている")
        XCTAssertFalse(ScriptedProtocol.calls.contains { $0.path.hasSuffix("/stick") }, "読めないまま貼る口を叩いた")

        ScriptedProtocol.reset()
        ScriptedProtocol.script = [
            .init(match: "/stick", status: 200, body: #"{"pocket":[],"stuck":[\#(label("p-1"))]}"#),
            .init(match: "/user/trunk", status: 200, body: #"{"pocket":[\#(label("p-1"))],"stuck":[]}"#),
        ]
        let stuck = await model.stickEnsuringLoaded("p-1")
        XCTAssertTrue(stuck)
        XCTAssertEqual(ScriptedProtocol.calls.map(\.method), ["GET", "POST"], "読み直してから貼っていない")
        XCTAssertEqual(model.state?.stuck.map(\.id), ["p-1"])
    }

    // MARK: 6. 開いただけでは作り直しの回数を使わない

    func testRerollStartsOnlyWhenAsked() throws {
        let pro = TrunkSample.state(isPro: true)
        let id = pro.pocket[0].id
        XCTAssertEqual(TrunkText.rerollStep(pro, labelId: id), .start(left: 2), "開いた時点で候補を出す段になっている")
        let rolled = TrunkLocal.reroll(pro, id: id, seeds: [7, 8, 9])
        XCTAssertEqual(TrunkText.rerollStep(rolled, labelId: id), .choosing([7, 8, 9]))
        XCTAssertEqual(TrunkText.rerollStep(rolled, labelId: pro.pocket[1].id), .start(left: 1))
        XCTAssertEqual(TrunkText.rerollStep(TrunkSample.state(isPro: false), labelId: id), .notPro)
        let spent = TrunkState(model: .leather, pocket: pro.pocket, stuck: [], limit: 150, isPro: true,
                               rerollsLeft: 0, posts: 0, receiveLabels: true)
        XCTAssertEqual(TrunkText.rerollStep(spent, labelId: id), .noneLeft)
        XCTAssertEqual(TrunkText.rerollStartTitle(left: 2), L("作り直す · 今月あと 2 回", "Redo · 2 left this month"))
    }

    /// 作り直しの画面の作りが、開いたときに口を叩かない（候補を出す段は押してから）
    @MainActor
    func testOpeningRerollDoesNotSpend() async {
        let model = TrunkViewModel(preview: nil)
        model.bind(trunkService())
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[\#(label("p-1"))],"stuck":[],"isPro":true,"rerolls":{"left":3}}"#)]
        await model.load(offline: false)
        // 画面を開いた（= 段を読むだけ）
        XCTAssertEqual(TrunkText.rerollStep(model.state, labelId: "p-1"), .start(left: 3))
        XCTAssertFalse(ScriptedProtocol.calls.contains { $0.path.hasSuffix("/reroll") })
    }

    // MARK: 8. か国・地域

    func testCountriesCountOnlyKnownCountries() throws {
        let s = try JSONDecoder.api.decode(TrunkState.self, from: Data("""
        {"stuck":[\(label("a", country: "日本")),\(label("b")),\(label("c", country: "フランス")),\(label("d"))]}
        """.utf8))
        XCTAssertEqual(TrunkText.stats(s).countries, 2, "国名の無いラベルを日本と数えた")
        let none = try JSONDecoder.api.decode(TrunkState.self, from: Data(#"{"stuck":[\#(label("x"))]}"#.utf8))
        XCTAssertEqual(TrunkText.stats(none).countries, 0)
    }

    // MARK: 10. 人の切り替えで空にする

    @MainActor
    func testArrivalsAreDroppedWhenTheUserChanges() async {
        let arrivals = TrunkArrivals()
        arrivals.noteUser("u1")
        arrivals.deliver([.init(label: TrunkSample.arrived, photoTitle: "")], notice: nil)
        arrivals.noteUser("u1")
        XCTAssertTrue(arrivals.hasPending, "同じ人なのに捨てた")
        arrivals.noteUser(nil)
        XCTAssertFalse(arrivals.hasPending, "ログアウトしても前の人の束が残っている")
        XCTAssertNil(arrivals.consume())
        arrivals.noteUser("u2")
        arrivals.deliver([], notice: .full)
        arrivals.noteUser("u3")
        XCTAssertNil(arrivals.consumeNotice(), "別の人に前の人の一言を出した")
    }

    // MARK: 11. Pro を買ったあとに読み直す

    @MainActor
    func testRefreshAfterPaywallPicksUpPro() async {
        let model = TrunkViewModel(preview: nil)
        model.bind(trunkService())
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[],"stuck":[],"isPro":false,"limit":30}"#, once: true),
                                   .init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[],"stuck":[],"isPro":true,"limit":150,"rerolls":{"left":3}}"#)]
        await model.load(offline: false)
        XCTAssertEqual(model.state?.isPro, false)
        await model.refreshAfterPaywall()
        XCTAssertEqual(model.state?.isPro, true)
        XCTAssertEqual(model.state?.limit, 150)
        XCTAssertEqual(model.state?.rerollsLeft, 3)
    }
}
