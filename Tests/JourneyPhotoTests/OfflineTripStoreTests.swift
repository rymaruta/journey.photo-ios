import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 端末に保存した旅の置き場（`OfflineTripStore`）。保存・止める・続きから・保存し直し・削除・人ごとの置き場
@MainActor
final class OfflineTripStoreTests: XCTestCase {

    private var root: URL!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("offline-store-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: "offline-store-\(UUID().uuidString)")!
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func plan(_ count: Int, notes: String? = nil) -> TripPlan {
        TripPlan(planId: "plan-1", title: "山形", startDate: "2026-10-10", endDate: "2026-10-10",
                 days: [TripDay(items: (1...count).map { .spot(spotId: "sp_\($0)", note: notes) })])
    }

    private func stops(_ p: TripPlan) -> [OfflineTripPlan.Stop] {
        OfflineTripPlan.stops(of: p, index: [], places: [])
    }

    /// 作例を2枚ずつ返す。`failAt` 番目の場所の画像で圏外になる。`gate` があれば、その場所の前で待つ
    private final class Fake: @unchecked Sendable {
        var downloads: [String] = []
        var failAt: Int?
        var gate: (number: Int, continuation: CheckedContinuation<Void, Never>?)?
        var reachedGate: (() -> Void)?
    }

    private func sources(_ fake: Fake) -> OfflineTripSources {
        OfflineTripSources(
            samples: { stop in
                (1...4).map { i in
                    OfflineSampleSource(url: URL(string: "https://example.com/\(stop.number)-\(i).jpg")!,
                                        title: "作例\(i)", credit: "写真: 作者 / CC BY 4.0",
                                        sourceUrl: nil, licenseUrl: nil)
                }
            },
            download: { url in
                let name = url.lastPathComponent
                let n = Int(name.split(separator: "-")[0]) ?? 0
                if let gate = fake.gate, gate.number == n, gate.continuation == nil {
                    await withCheckedContinuation { c in
                        fake.gate?.continuation = c
                        fake.reachedGate?()
                    }
                }
                if fake.failAt == n { throw URLError(.notConnectedToInternet) }
                fake.downloads.append(name)
                return Data(repeating: 1, count: 1_000)
            },
            stopMap: { _ in Data(repeating: 2, count: 500) },
            overviewMap: { _ in Data(repeating: 3, count: 700) })
    }

    private func waitUntil(_ store: OfflineTripStore, timeout: TimeInterval = 5,
                           _ done: @escaping (OfflineTripStore) -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !done(store), Date() < end {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeStore() -> OfflineTripStore {
        let store = OfflineTripStore(root: root, defaults: defaults)
        store.use(userId: "u1")
        return store
    }

    func testSavesThreeSamplesPerStopAndCountsBytes() async throws {
        let store = makeStore()
        let fake = Fake()
        let p = plan(2)
        // 座標が無いので地図の画像は撮らない。旅全体の地図は座標に関わらず渡したものを使う
        store.save(plan: p, stops: stops(p), sources: sources(fake))
        await waitUntil(store) { $0.manifest("plan-1") != nil }
        let m = try XCTUnwrap(store.manifest("plan-1"))
        XCTAssertEqual(m.stopCount, 2)
        XCTAssertEqual(m.days.first?.stops.map { $0.samples.count }, [3, 3], "1か所あたり3枚（owner 2026-10-09）")
        XCTAssertEqual(m.days.first?.stops.first?.samples.first?.credit, "写真: 作者 / CC BY 4.0", "出典を画像と一緒に残す")
        // 書いたファイルを全部数える（画像 6 枚・旅全体の地図・記録）
        let size = Int64(try manifestSize())
        XCTAssertTrue((6_700 + size - 5...6_700 + size + 5).contains(m.bytes), "\(m.bytes)")
        XCTAssertEqual(store.totalBytes, m.bytes)
        XCTAssertFalse(store.isRunning("plan-1"))
        if case .saved = store.status("plan-1").phase(isPro: true, change: .none) {} else { XCTFail("保存済み") }
        let sample = try XCTUnwrap(store.fileURL(planId: "plan-1", file: m.days[0].stops[0].samples[0].file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sample.path))
        XCTAssertNil(store.fileURL(planId: "plan-1", file: "../x"), "置き場の外を指さない")

        // 読み直しても同じ（次に開いたとき）
        let again = OfflineTripStore(root: root, defaults: defaults)
        again.use(userId: "u1")
        XCTAssertEqual(again.manifest("plan-1"), m)
    }

    private func manifestSize() throws -> Int {
        let dir = root.appendingPathComponent(OfflineTripStore.hex("u1")).appendingPathComponent(OfflineTripStore.hex("plan-1"))
        return try Data(contentsOf: dir.appendingPathComponent(OfflineTripStore.manifestName)).count
    }

    func testOfflineMidwayLeavesPartialAndResumeReusesDoneStops() async throws {
        let store = makeStore()
        let fake = Fake()
        fake.failAt = 2
        let p = plan(3)
        store.save(plan: p, stops: stops(p), sources: sources(fake))
        await waitUntil(store) { !$0.isRunning("plan-1") }
        let status = store.status("plan-1")
        XCTAssertEqual(status.phase(isPro: true, change: .none), .interrupted(.init(done: 1, total: 3)))
        XCTAssertEqual(status.error, OfflineTripText.failureMessage(.offline))
        XCTAssertNil(store.manifest("plan-1"))

        // アプリを閉じて開き直した: 途中のものが「続きから保存」で出る
        let reopened = OfflineTripStore(root: root, defaults: defaults)
        reopened.use(userId: "u1")
        XCTAssertEqual(reopened.status("plan-1").phase(isPro: true, change: .none), .interrupted(.init(done: 1, total: 3)))

        // 続きから: 済んだ1か所目は取り直さない
        fake.failAt = nil
        fake.downloads = []
        reopened.save(plan: p, stops: stops(p), sources: sources(fake))
        XCTAssertEqual(reopened.status("plan-1").running?.done, 1)
        await waitUntil(reopened) { $0.manifest("plan-1") != nil }
        XCTAssertFalse(fake.downloads.contains { $0.hasPrefix("1-") }, "済んだ場所は使い回す: \(fake.downloads)")
        XCTAssertEqual(reopened.manifest("plan-1")?.stopCount, 3)
    }

    func testChangedNoteRedoesThatStop() async throws {
        let store = makeStore()
        let fake = Fake()
        fake.failAt = 2
        let p = plan(2)
        store.save(plan: p, stops: stops(p), sources: sources(fake))
        await waitUntil(store) { !$0.isRunning("plan-1") }
        fake.failAt = nil
        fake.downloads = []
        let edited = plan(2, notes: "朝")
        store.save(plan: edited, stops: stops(edited), sources: sources(fake))
        await waitUntil(store) { $0.manifest("plan-1") != nil }
        XCTAssertTrue(fake.downloads.contains { $0.hasPrefix("1-") }, "メモが変わった場所は取り直す")
        XCTAssertEqual(store.manifest("plan-1")?.days.first?.stops.first?.note, "朝")
    }

    func testStopButtonKeepsPartial() async throws {
        let store = makeStore()
        let fake = Fake()
        var reached = false
        fake.gate = (2, nil)
        fake.reachedGate = { reached = true }
        let p = plan(3)
        store.save(plan: p, stops: stops(p), sources: sources(fake))
        await waitUntil(store) { _ in reached }
        XCTAssertTrue(reached, "2か所目で待つ")
        store.stop("plan-1")
        fake.gate?.continuation?.resume()
        await waitUntil(store) { !$0.isRunning("plan-1") }
        XCTAssertEqual(store.status("plan-1").partial, .init(done: 1, total: 3))
        XCTAssertNil(store.status("plan-1").error, "止めたのは失敗ではない")
    }

    func testDeleteAndPerUserFolders() async throws {
        let store = makeStore()
        let p = plan(1)
        store.save(plan: p, stops: stops(p), sources: sources(Fake()))
        await waitUntil(store) { $0.manifest("plan-1") != nil }

        // 別の人に替わったら見えない
        store.use(userId: "u2")
        XCTAssertNil(store.manifest("plan-1"))
        // 圏外で起動して ID が取れなかった回は、前に使っていた人（u2）
        let offlineLaunch = OfflineTripStore(root: root, defaults: defaults)
        offlineLaunch.useLastUser()
        XCTAssertNil(offlineLaunch.manifest("plan-1"))
        store.use(userId: "u1")
        offlineLaunch.useLastUser()
        XCTAssertNotNil(offlineLaunch.manifest("plan-1"), "前に使っていた人の旅を出す")

        store.delete("plan-1")
        XCTAssertNil(store.manifest("plan-1"))
        XCTAssertEqual(store.status("plan-1"), OfflineSaveStatus())
        XCTAssertEqual(OfflineTripBytes.count(in: root), 0, "画像も消える")
    }

    func testAccountRemovalDeletesUsersTrips() async throws {
        let store = makeStore()
        let p = plan(1)
        store.save(plan: p, stops: stops(p), sources: sources(Fake()))
        await waitUntil(store) { $0.manifest("plan-1") != nil }
        AccountLocalData.remove(userId: "u1", username: nil, defaults: defaults,
                                draftDirectory: root.appendingPathComponent("drafts"), offlineTripsRoot: root)
        XCTAssertEqual(OfflineTripBytes.count(in: root.appendingPathComponent(OfflineTripStore.hex("u1"))), 0)
        XCTAssertNil(defaults.string(forKey: OfflineTripStore.lastUserKey))
    }

    func testDeleteAll() async throws {
        let store = makeStore()
        let p = plan(1)
        store.save(plan: p, stops: stops(p), sources: sources(Fake()))
        await waitUntil(store) { $0.manifest("plan-1") != nil }
        store.deleteAll()
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(store.totalBytes, 0)
    }
}
