import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 旅のトランクの細かい直し（2026-10-17・見直しの続き）を振る舞いで見張る
final class TrunkFollowUpTests: XCTestCase {

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

    private func api() -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: StubTokenProvider(token: "t"),
                  session: session)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "trunk-followup-\(UUID().uuidString)")!
    }

    // 1. 残った束は評価のお願いを少しの間だけ止める
    @MainActor
    func testLeftoverBatchStopsBlockingReview() async {
        let arrivals = TrunkArrivals()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(arrivals.blocksReview(now: t0))
        arrivals.deliver([.init(label: TrunkSample.arrived, photoTitle: "")], notice: nil, now: t0)
        XCTAssertTrue(arrivals.blocksReview(now: t0.addingTimeInterval(60)))
        XCTAssertFalse(arrivals.blocksReview(now: t0.addingTimeInterval(TrunkArrivals.reviewHoldSeconds + 1)),
                       "待ちきれずに残った束が評価のお願いをずっと止める")
        XCTAssertTrue(arrivals.hasPending, "止めないだけで、束は出し直せるよう残す")
        _ = arrivals.consume()
        XCTAssertFalse(arrivals.blocksReview(now: t0.addingTimeInterval(1)))
    }

    // 3. 入口の確かめは間を空ける
    func testNeedsCheck() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertTrue(TrunkAvailabilityRule.needsCheck(remembered: false, checkedAt: now, now: now, force: false),
                      "まだ口が無い人は開くたびに確かめる")
        XCTAssertFalse(TrunkAvailabilityRule.needsCheck(remembered: true, checkedAt: now.addingTimeInterval(-3600), now: now, force: false))
        XCTAssertTrue(TrunkAvailabilityRule.needsCheck(remembered: true, checkedAt: now.addingTimeInterval(-6 * 3600), now: now, force: false))
        XCTAssertTrue(TrunkAvailabilityRule.needsCheck(remembered: true, checkedAt: now, now: now, force: true), "前面に戻っても確かめない")
        XCTAssertTrue(TrunkAvailabilityRule.needsCheck(remembered: true, checkedAt: nil, now: now, force: false))
    }

    @MainActor
    func testEntryCheckIsSpacedOut() async {
        let defaults = freshDefaults()
        let service = TrunkService(api: api())
        let availability = TrunkAvailability(defaults: defaults, entry: TrunkEntryStore())
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[]}"#)]
        await availability.refresh(userId: "u1", service: service, now: t0, preview: false)
        XCTAssertTrue(availability.isAvailable)
        XCTAssertEqual(ScriptedProtocol.calls.count, 1)
        // マイページを開き直した（1時間後）: 叩かずに覚えている値で出す
        await availability.refresh(userId: "u1", service: service, now: t0.addingTimeInterval(3600), preview: false)
        XCTAssertTrue(availability.isAvailable)
        XCTAssertEqual(ScriptedProtocol.calls.count, 1, "開くたびに GET /user/trunk を叩いている")
        // 6時間たった・前面に戻った: 読み直す
        await availability.refresh(userId: "u1", service: service, now: t0.addingTimeInterval(6 * 3600), preview: false)
        XCTAssertEqual(ScriptedProtocol.calls.count, 2)
        await availability.refresh(userId: "u1", service: service, force: true,
                                   now: t0.addingTimeInterval(6 * 3600 + 10), preview: false)
        XCTAssertEqual(ScriptedProtocol.calls.count, 3)
    }

    // 4. 届いた画面で貼った知らせは閉じたあとに1つだけ
    @MainActor
    func testStuckToastIsHandedToTheRootOnce() async {
        let arrivals = TrunkArrivals()
        XCTAssertFalse(arrivals.consumeStuckFromArrival())
        arrivals.noteStuckFromArrival()
        XCTAssertTrue(arrivals.consumeStuckFromArrival())
        XCTAssertFalse(arrivals.consumeStuckFromArrival(), "知らせを2回出す")
        arrivals.noteUser("a")
        arrivals.noteStuckFromArrival()
        arrivals.noteUser("b")
        XCTAssertFalse(arrivals.consumeStuckFromArrival(), "前の人の知らせを出す")
    }

    // 5. 断りの storage
    func testStorageRefusal() {
        let text = TrunkText.refusal(code: "storage", fallback: "FALLBACK")
        XCTAssertNotEqual(text, "FALLBACK")
        XCTAssertNotEqual(text, TrunkText.refusal(code: "full", fallback: ""))
        XCTAssertTrue(text.contains(L("容量", "storage limit")))
    }

    // 6. 下書きを公開した応答のラベル
    @MainActor
    func testPublishingADraftHandsTheLabelOver() async throws {
        let photos = PhotoService(api: api())
        var patch = PhotoPatch()
        patch.published = true
        ScriptedProtocol.script = [.init(match: "/photos/p1", status: 200,
                                         body: #"{"success":true,"label":{"id":"p1","kind":"place","place":{"name":"京都"},"seed":2,"at":"2026-10-17T00:00:00Z"}}"#,
                                         once: true),
                                   .init(match: "/photos/p1", status: 200, body: #"{"success":true,"label":null,"labelSkipped":"storage"}"#,
                                         once: true),
                                   .init(match: "/photos/p1", status: 200, body: #"{"success":true}"#)]
        let dealt = try await photos.update(photoId: "p1", patch: patch)
        XCTAssertEqual(dealt.label?.id, "p1")
        let arrivals = TrunkArrivals()
        arrivals.deliver(dealt, photoTitle: "朝")
        XCTAssertEqual(arrivals.consume()?.first.photoTitle, "朝")

        let storage = try await photos.update(photoId: "p1", patch: patch)
        arrivals.deliver(storage, photoTitle: "")
        XCTAssertEqual(arrivals.consumeNotice(), .storage)

        let none = try await photos.update(photoId: "p1", patch: patch)
        XCTAssertEqual(none, TrunkDealt())
        arrivals.deliver(none, photoTitle: "")
        XCTAssertFalse(arrivals.hasPending, "何も配られていないのに届いた画面を出す")
        XCTAssertEqual(TrunkDealt.read(Data("not json".utf8)), TrunkDealt())
    }
}

/// 退会で旅のトランクの印を消す（`AccountLocalData` は @MainActor なので組を分ける）
@MainActor
final class TrunkAccountRemovalTests: XCTestCase {

    // 2. 退会で消す
    func testAccountRemovalForgetsTrunkKeys() async {
        let defaults = UserDefaults(suiteName: "trunk-removal-\(UUID().uuidString)")!
        defaults.set(true, forKey: "trunk.available.gone")
        defaults.set(Date(), forKey: "trunk.availableCheckedAt.gone")
        defaults.set(20, forKey: TrunkAgingNotice.key("gone"))
        defaults.set(true, forKey: "trunk.available.other")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AccountLocalData.remove(userId: "gone", username: nil, defaults: defaults, draftDirectory: dir,
                                offlineTripsRoot: dir, passRoot: dir)
        XCTAssertNil(defaults.object(forKey: "trunk.available.gone"))
        XCTAssertNil(defaults.object(forKey: "trunk.availableCheckedAt.gone"))
        XCTAssertNil(defaults.object(forKey: "trunk.agingSeen.gone"))
        XCTAssertEqual(defaults.bool(forKey: "trunk.available.other"), true, "別の人の印まで消した")
    }

}
