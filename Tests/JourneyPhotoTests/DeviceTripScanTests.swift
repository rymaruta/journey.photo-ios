import XCTest
import Photos
@testable import JourneyPhoto

/// 端末の写真の一冊の**読みの流れ**（`DeviceTripScan`・`DeviceTripShelfStore`・2026-10-16）。
/// owner の「重くしない」を見張る: 続きから・新しい写真だけ・突き合わせは知らない写真だけ・
/// 変わらなければ書かない・取り消したら書かない・読みの間隔の下限
final class DeviceTripScanTests: XCTestCase {

    /// 2026-09-12 00:00 JST
    private let base = Date(timeIntervalSince1970: 1_789_138_800)
    private var now: Date { base.addingTimeInterval(86_400) }
    private let home = (lat: 35.68, lng: 139.76)
    private let kyoto = (lat: 35.01, lng: 135.77)

    private func item(_ id: String, hours: Double, _ place: (lat: Double, lng: Double)?, skipped: Bool = false) -> DeviceTripSummary {
        DeviceTripSummary(shot: LibraryShot(id: id, date: base.addingTimeInterval(hours * 3600),
                                            lat: place?.lat, lng: place?.lng), isSkipped: skipped)
    }

    /// 家の日常20枚＋京都の旅6枚＋スクリーンショット1枚
    private func library() -> [DeviceTripSummary] {
        (0..<20).map { item("h\($0)", hours: -24 * 30 + Double($0) * 5, home) }
            + (0..<6).map { item("k\($0)", hours: 10 + Double($0), kyoto) }
            + [item("screen", hours: 1, nil, skipped: true)]
    }

    /// 書いた回数と棚へ出した回数を数える
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _saves = 0
        private var _progress = 0
        var saves: Int { lock.lock(); defer { lock.unlock() }; return _saves }
        var progress: Int { lock.lock(); defer { lock.unlock() }; return _progress }
        func saved() { lock.lock(); _saves += 1; lock.unlock() }
        func published() { lock.lock(); _progress += 1; lock.unlock() }
    }

    private func scan(_ source: FakeTripSource, _ counter: Counter) -> DeviceTripScan {
        DeviceTripScan(source: source,
                       save: { _ in counter.saved() },
                       progress: { _, _ in counter.published() },
                       pauseNanos: 0)
    }

    // MARK: - 読み

    func testFirstRunReadsEverythingAndCompletes() async {
        let source = FakeTripSource(library())
        let counter = Counter()
        let index = await scan(source, counter).run(start: nil, now: now, publishCached: false)
        XCTAssertTrue(index.complete)
        XCTAssertNil(index.frontier)
        XCTAssertEqual(index.shots.count, 26)
        XCTAssertEqual(index.skipped.map(\.id), ["screen"], "スクリーンショットは旅に入れず、数だけ覚える")
        XCTAssertEqual(counter.saves, 1)
        XCTAssertEqual(counter.progress, 1)
        XCTAssertEqual(DeviceTrips.found(in: index.shots).count, 1)
    }

    /// 🔴 **変わっていなければ書かず、旅も探し直さない**（確かめ役の指摘 1）
    func testUnchangedRunNeitherSavesNorSearches() async {
        let source = FakeTripSource(library())
        let first = await scan(source, Counter()).run(start: nil, now: now, publishCached: false)
        source.resetCounts()
        let counter = Counter()
        let second = await scan(source, counter).run(start: first, now: now, publishCached: false)
        XCTAssertEqual(second, first)
        XCTAssertEqual(counter.saves, 0, "変わっていないのに 約5MB を書いた")
        XCTAssertEqual(counter.progress, 0, "変わっていないのに5万枚で旅を探し直した")
        XCTAssertEqual(source.summaryReads, 0)
    }

    /// 🔴 **次からは前回より新しい写真だけ読む**（owner の条件 2）
    func testNextRunReadsOnlyNewerPhotos() async {
        let source = FakeTripSource(library())
        let first = await scan(source, Counter()).run(start: nil, now: now, publishCached: false)
        source.items.append(item("new1", hours: 20, kyoto))
        source.items.append(item("new2", hours: 21, kyoto))
        source.resetCounts()
        let counter = Counter()
        let second = await scan(source, counter).run(start: first, now: now, publishCached: false)
        XCTAssertEqual(source.summaryReads, 2, "古い写真まで読み直した")
        XCTAssertEqual(source.idReads, 0, "数が合っているのに突き合わせた")
        XCTAssertEqual(second.shots.count, 28)
        XCTAssertEqual(counter.saves, 1)
    }

    /// 途中で閉じたら続きから（読んだ所より古い写真だけ）
    func testResumeReadsOnlyOlderThanTheFrontier() async {
        let source = FakeTripSource(library())
        var partial = DeviceTrips.Index()
        let newest = source.items.map(\.shot).sorted { $0.date > $1.date }
        partial.shots = Array(newest.prefix(5))
        partial.frontier = newest[4].date
        partial.newest = newest[0].date
        let index = await scan(source, Counter()).run(start: partial, now: now, publishCached: false)
        XCTAssertTrue(index.complete)
        XCTAssertEqual(index.shots.count + index.skipped.count, 27)
        XCTAssertEqual(source.summaryReads, 27 - 4, "読んだ所（境目の1枚を除く）を読み直した")
    }

    /// 写真を消した・古い写真を選び足した: **知らない写真だけ読む**
    func testSweepDropsDeletedAndReadsOnlyUnknownPhotos() async {
        let source = FakeTripSource(library())
        let first = await scan(source, Counter()).run(start: nil, now: now, publishCached: false)
        source.items.removeAll { $0.shot.id == "h3" }
        source.items.append(item("old", hours: -24 * 60, home))
        source.items.append(item("old2", hours: -24 * 61, home))
        source.resetCounts()
        let index = await scan(source, Counter()).run(start: first, now: now, publishCached: false)
        XCTAssertFalse(index.shots.contains { $0.id == "h3" })
        XCTAssertTrue(index.shots.contains { $0.id == "old" })
        XCTAssertEqual(source.summaryReads, 2, "覚えている写真の日時・位置を読み直した")
        XCTAssertEqual(index.lastSweep, now)
    }

    /// 🔴 **突き合わせは10分に1回まで**（確かめ役の指摘 2）
    func testSweepRunsAtMostOncePerInterval() async {
        let source = FakeTripSource(library())
        var first = await scan(source, Counter()).run(start: nil, now: now, publishCached: false)
        first.lastSweep = now.addingTimeInterval(-60)
        source.items.removeAll { $0.shot.id == "h3" }
        source.resetCounts()
        let index = await scan(source, Counter()).run(start: first, now: now, publishCached: false)
        XCTAssertEqual(source.idReads, 0)
        XCTAssertTrue(index.shots.contains { $0.id == "h3" }, "10分たたないうちに突き合わせた")
    }

    /// 🔴 **知らない写真が多ければ頭から区切って読む**（一部→全部の許可・確かめ役の指摘 3）
    func testManyUnknownPhotosFallBackToTheChunkedFullRead() async {
        var many = library()
        many += (0..<(DeviceTrips.maxSweepReads + 10)).map { item("m\($0)", hours: -48 - Double($0) * 0.1, home) }
        let source = FakeTripSource(library())
        let first = await scan(source, Counter()).run(start: nil, now: now, publishCached: false)
        source.items = many
        source.resetCounts()
        let index = await scan(source, Counter()).run(start: first, now: now, publishCached: false)
        XCTAssertEqual(index.shots.count + index.skipped.count, many.count)
        XCTAssertEqual(source.idsLookups, 0, "数千枚を識別子で1度に引いた")
        XCTAssertTrue(index.complete)
    }

    /// 取り消したら（サインアウトで消した）書かない
    func testCancelledRunDoesNotSave() async {
        let source = FakeTripSource(library())
        let counter = Counter()
        let scanner = scan(source, counter)
        let now = now
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await scanner.run(start: nil, now: now, publishCached: false)
        }
        let index = await task.value
        XCTAssertFalse(index.complete)
        XCTAssertEqual(counter.saves, 0)
    }

    // MARK: - 間隔

    func testRunDelayKeepsTheMinimumInterval() {
        XCTAssertEqual(DeviceTrips.runDelay(lastRunStart: nil, now: now), DeviceTrips.changeDelay)
        XCTAssertEqual(DeviceTrips.runDelay(lastRunStart: now.addingTimeInterval(-10), now: now), 50, accuracy: 0.001)
        XCTAssertEqual(DeviceTrips.runDelay(lastRunStart: now.addingTimeInterval(-600), now: now), DeviceTrips.changeDelay)
        XCTAssertTrue(DeviceTrips.maySweep(lastSweep: nil, now: now))
        XCTAssertFalse(DeviceTrips.maySweep(lastSweep: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(DeviceTrips.maySweep(lastSweep: now.addingTimeInterval(-DeviceTrips.sweepInterval), now: now))
    }

    // MARK: - 書き込みの列

    /// 🔴 **消したあとに届いた古い書き込みは捨てる**（確かめ役の指摘 5）
    func testWriterDropsWritesOlderThanTheRemoval() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceTripScanTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("index.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = DeviceTripIndexWriter(url: url)
        var index = DeviceTrips.Index()
        index.complete = true
        let first = await writer.save(index, generation: 0)
        XCTAssertTrue(first)
        await writer.remove(generation: 1)
        let stale = await writer.save(index, generation: 0)
        XCTAssertFalse(stale)
        XCTAssertNil(DeviceTripIndexFile.load(from: url), "消したあとに書き戻した")
        let fresh = await writer.save(index, generation: 1)
        XCTAssertTrue(fresh)
    }

    // MARK: - 棚の店（runLoop）

    private final class Box: @unchecked Sendable {
        var status: PHAuthorizationStatus = .authorized
        var lookups = 0
    }

    @MainActor
    private func makeStore(_ source: FakeTripSource, box: Box, url: URL?) throws -> DeviceTripShelfStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceTripScanTests-\(UUID().uuidString)"))
        let now = now
        return DeviceTripShelfStore(defaults: defaults, url: url, source: source,
                                    status: { box.status },
                                    place: { _ in box.lookups += 1; return ("京都市", TimeZone(identifier: "Asia/Tokyo")) },
                                    pauseNanos: 0, lookupPauseNanos: 0, now: { now }, observesLibrary: false)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceTripScanTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("index.json")
    }

    /// 読み終えたら棚に一冊。地名は一冊につき1回。**もう一度読んでも変わらなければ書かない**
    @MainActor
    func testStoreReadsOnceThenOnlyChecksForChanges() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let source = FakeTripSource(library())
        let box = Box()
        let store = try makeStore(source, box: box, url: url)
        store.startIfAllowed()
        await store.waitUntilIdle()
        let books = store.books(posted: [], isMine: true)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(store.names[books[0].id], "京都市")
        XCTAssertEqual(box.lookups, 1)
        let saves = await store.saveCount()
        XCTAssertEqual(saves, 2, "読み終えた1回＋地名の1回")

        source.resetCounts()
        store.startIfAllowed()
        await store.waitUntilIdle()
        XCTAssertEqual(box.lookups, 1, "引けた地名をまた引いた")
        let again = await store.saveCount()
        XCTAssertEqual(again, saves, "変わっていないのに書いた")
        XCTAssertEqual(source.summaryReads, 0)
        XCTAssertFalse(store.isScanning)
    }

    /// 次の起動は端末に覚えた要約から（ライブラリを読み直さない）
    @MainActor
    func testNextLaunchStartsFromTheStoredSummary() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let source = FakeTripSource(library())
        let first = try makeStore(source, box: Box(), url: url)
        first.startIfAllowed()
        await first.waitUntilIdle()
        source.resetCounts()
        let box = Box()
        let second = try makeStore(source, box: box, url: url)
        second.startIfAllowed()
        await second.waitUntilIdle()
        XCTAssertEqual(source.summaryReads, 0)
        XCTAssertEqual(second.books(posted: [], isMine: true).count, 1, "覚えた要約で棚を出さなかった")
        XCTAssertEqual(box.lookups, 0)
    }

    /// 🔴 **許可を外したら要約を消し、棚に出さない**（確かめ役の指摘 6）
    @MainActor
    func testRevokedAccessForgetsTheSummary() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let box = Box()
        let store = try makeStore(FakeTripSource(library()), box: box, url: url)
        store.startIfAllowed()
        await store.waitUntilIdle()
        XCTAssertFalse(store.books(posted: [], isMine: true).isEmpty)
        box.status = .denied
        store.startIfNeeded()
        await store.waitForRemoval()
        XCTAssertTrue(store.books(posted: [], isMine: true).isEmpty)
        XCTAssertTrue(store.shots.isEmpty)
        XCTAssertNil(DeviceTripIndexFile.load(from: url), "読めなくなった写真の位置の控えが残った")
    }

    /// 消したあと（サインアウト）に読み直しても、古い読みが新しい読みの印を消さない
    @MainActor
    func testForgetThenRestartLeavesOneCleanRun() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try makeStore(FakeTripSource(library()), box: Box(), url: url)
        store.startIfAllowed()
        store.forget()
        store.startIfAllowed()
        await store.waitUntilIdle()
        await store.waitForRemoval()
        XCTAssertFalse(store.isScanning)
        XCTAssertEqual(store.books(posted: [], isMine: true).count, 1)
    }
}

extension DeviceTripScanTests {
    /// 🔴 **古い読みが終わっても、新しい読みの印を消さない**（確かめ役の指摘 4）。
    /// 消すと、次の「読んで」で読みが2本走る
    @MainActor
    func testOldRunDoesNotClearTheNewRun() async throws {
        let url = tempURLForGate()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let source = FakeTripSource(library())
        source.blockLiveReads = true   // 取り消されていない読み（新しい読み）だけを止める
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceTripScanTests-\(UUID().uuidString)"))
        let store = DeviceTripShelfStore(defaults: defaults, url: url, source: source,
                                         status: { .authorized }, place: { _ in (nil, nil) },
                                         pauseNanos: 0, lookupPauseNanos: 0, observesLibrary: false)
        store.startIfAllowed()      // 1本目
        store.forget()              // サインアウト（1本目を取り消す）
        store.startIfAllowed()      // 2本目
        // **1本目が読みの輪を抜けきり、2本目が読みの途中で止まっている**場面を待つ
        var waited = 0
        while (store.loopsFinished < 1 || source.blockedCalls < 1), waited < 400 {
            try await Task.sleep(nanoseconds: 5_000_000)
            waited += 1
        }
        XCTAssertEqual(store.loopsFinished, 1, "古い読みが終わる場面を作れなかった")
        XCTAssertEqual(source.blockedCalls, 1)
        XCTAssertTrue(store.isScanning, "古い読みが新しい読みの印を消した")
        store.startIfAllowed()      // 2本目の最中の「読んで」は、終わったあとの1回にまとまる
        XCTAssertEqual(store.runsStarted, 2, "読みが2本走った")
        source.release()
        await store.waitUntilIdle()
        await store.waitForRemoval()
    }

    /// 🔴 **ログインしていない間は、前面に戻っても読まない**（サインアウトで消した要約を作り直さない）
    @MainActor
    func testSignedOutForegroundDoesNotRead() async throws {
        let url = tempURLForGate()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceTripScanTests-\(UUID().uuidString)"))
        let store = DeviceTripShelfStore(defaults: defaults, url: url, source: FakeTripSource(library()),
                                         status: { .authorized }, place: { _ in (nil, nil) },
                                         pauseNanos: 0, lookupPauseNanos: 0, observesLibrary: false,
                                         signedIn: false)
        store.setActive(false)
        store.setActive(true)
        store.libraryChanged()
        await store.waitUntilIdle()
        XCTAssertEqual(store.runsStarted, 0, "ログインしていないのに読んだ")
        XCTAssertNil(DeviceTripIndexFile.load(from: url), "サインアウトのあとに要約を作り直した")
        store.setSignedIn(true)
        store.setActive(false)
        store.setActive(true)
        await store.waitUntilIdle()
        XCTAssertEqual(store.runsStarted, 1, "ログインしたら前面に戻ったときに読む")
    }

    /// 🔴 **読めない段なら、メモリが空でも端末のファイルを消す**（許可を外すと iOS がアプリを終わらせる）
    @MainActor
    func testUnreadableRemovesTheStoredFileOnAFreshLaunch() async throws {
        let url = tempURLForGate()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var stored = DeviceTrips.Index()
        stored.complete = true
        stored.shots = library().map(\.shot)
        DeviceTripIndexFile.save(stored, to: url)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceTripScanTests-\(UUID().uuidString)"))
        let store = DeviceTripShelfStore(defaults: defaults, url: url, source: FakeTripSource([]),
                                         status: { .denied }, place: { _ in (nil, nil) },
                                         pauseNanos: 0, lookupPauseNanos: 0, observesLibrary: false,
                                         signedIn: true)
        store.setActive(true)
        await store.waitForRemoval()
        XCTAssertNil(DeviceTripIndexFile.load(from: url), "読めない写真の位置の控えが残った")
    }

    /// 本人が「写真を追加で選ぶ」で選び足した直後は、10分の制限を外して突き合わせる
    func testForcedSweepIgnoresTheInterval() async {
        let source = FakeTripSource(library())
        var first = await scan(source, Counter()).run(start: nil, now: now, publishCached: false)
        first.lastSweep = now.addingTimeInterval(-60)
        source.items.append(item("picked", hours: -24 * 60, home))
        let index = await scan(source, Counter()).run(start: first, now: now, publishCached: false, forceSweep: true)
        XCTAssertTrue(index.shots.contains { $0.id == "picked" }, "選び足した写真が棚に入らない")
    }

    private func tempURLForGate() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceTripScanTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("index.json")
    }
}

/// 試験の写真ライブラリ（新しい順に返す・読んだ数を数える）
final class FakeTripSource: DeviceTripSource, @unchecked Sendable {
    private let lock = NSLock()
    var items: [DeviceTripSummary]
    private var _summaryReads = 0
    private var _idReads = 0
    private var _idsLookups = 0

    init(_ items: [DeviceTripSummary]) {
        self.items = items
    }

    var summaryReads: Int { lock.lock(); defer { lock.unlock() }; return _summaryReads }
    var idReads: Int { lock.lock(); defer { lock.unlock() }; return _idReads }
    /// 識別子で引いた写真の枚数
    var idsLookups: Int { lock.lock(); defer { lock.unlock() }; return _idsLookups }

    func resetCounts() {
        lock.lock(); _summaryReads = 0; _idReads = 0; _idsLookups = 0; lock.unlock()
    }

    fileprivate func countSummary() { lock.lock(); _summaryReads += 1; lock.unlock() }
    fileprivate func countId() { lock.lock(); _idReads += 1; lock.unlock() }

    /// 取り消されていない読みの取り出しを `release()` まで止める（取り消された読みは止めない）
    var blockLiveReads = false
    private var _blockedCalls = 0
    private let gate = DispatchSemaphore(value: 0)
    private var released = false
    /// 止めている取り出しの数
    var blockedCalls: Int { lock.lock(); defer { lock.unlock() }; return _blockedCalls }

    func release() {
        lock.lock(); released = true; lock.unlock()
        for _ in 0..<8 { gate.signal() }
    }

    func fetch(since: Date, before: Date?, after: Date?) -> any DeviceTripAssets {
        lock.lock()
        let mustWait = blockLiveReads && !released && !Task.isCancelled
        if mustWait { _blockedCalls += 1 }
        lock.unlock()
        if mustWait { gate.wait() }
        let picked = items.filter { item in
            let date = item.shot.date
            return date >= since && (before.map { date <= $0 } ?? true) && (after.map { date > $0 } ?? true)
        }.sorted { $0.shot.date > $1.shot.date }
        return FakeTripAssets(items: picked, source: self)
    }

    func assets(ids: [String]) -> any DeviceTripAssets {
        lock.lock(); _idsLookups += ids.count; lock.unlock()
        let wanted = Set(ids)
        return FakeTripAssets(items: items.filter { wanted.contains($0.shot.id) }, source: self)
    }
}

private struct FakeTripAssets: DeviceTripAssets {
    let items: [DeviceTripSummary]
    let source: FakeTripSource
    var count: Int { items.count }
    func id(at position: Int) -> String {
        source.countId()
        return items[position].shot.id
    }
    func summary(at position: Int, since: Date) -> DeviceTripSummary? {
        source.countSummary()
        let item = items[position]
        return item.shot.date >= since ? item : nil
    }
}
