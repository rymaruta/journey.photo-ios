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
        // 🔴 端末の時計を戻した（前の読みの始まりが「未来」）。待ちは下限の60秒まで（1日待たせない）
        XCTAssertEqual(DeviceTrips.runDelay(lastRunStart: now.addingTimeInterval(86_400), now: now),
                       DeviceTrips.minRunInterval, accuracy: 0.001, "時計を戻した分だけ待ちが延びた")
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
                                    pauseNanos: 0, lookupPauseNanos: 0, now: { now }, observesLibrary: false,
                                    signedIn: true, priority: .userInitiated)
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
        let gate = FetchGate()
        source.gate = gate          // 取り出しのたびに門で止まる（試験が1つずつ放す）
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceTripScanTests-\(UUID().uuidString)"))
        let store = DeviceTripShelfStore(defaults: defaults, url: url, source: source,
                                         status: { .authorized }, place: { _ in (nil, nil) },
                                         pauseNanos: 0, lookupPauseNanos: 0, observesLibrary: false,
                                         signedIn: true, priority: .userInitiated)
        // **時間に頼らず、順を手で進める**:
        // 1本目を読みの途中（取り出し）で止める → 消す → 2本目を始めて同じく止める → 1本目だけ放す
        store.startIfAllowed()                  // 1本目
        await gate.waitForWaiting(1)            // 1本目が門で止まった
        store.forget()                          // サインアウト（1本目を取り消す）
        store.startIfAllowed()                  // 2本目
        await gate.waitForWaiting(2)            // 2本目も門で止まった
        await gate.releaseFirst()               // 1本目だけ放す（取り消されているので輪を抜ける）
        await store.waitForLoopsFinished(1)     // 1本目が輪を抜けきった
        XCTAssertEqual(store.loopsFinished, 1)
        XCTAssertTrue(store.isScanning, "古い読みが新しい読みの印を消した")
        store.startIfAllowed()                  // 2本目の最中の「読んで」は、終わったあとの1回にまとまる
        XCTAssertEqual(store.runsStarted, 2, "読みが2本走った")
        await gate.open()                       // 残りは止めない
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

    /// 🔴 **ログインしていなければ、どの入口から頼まれても読まない**（2026-10-16）。
    /// ログインせずに「投稿」→「旅の写真から」で許可すると `startIfAllowed` が直に呼ばれ、
    /// サインアウトで消した要約（撮影日時と位置）を作り直していた
    @MainActor
    func testSignedOutDirectStartDoesNotRead() async throws {
        let url = tempURLForGate()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceTripScanTests-\(UUID().uuidString)"))
        let store = DeviceTripShelfStore(defaults: defaults, url: url, source: FakeTripSource(library()),
                                         status: { .authorized }, place: { _ in (nil, nil) },
                                         pauseNanos: 0, lookupPauseNanos: 0, observesLibrary: false,
                                         signedIn: false)
        store.startIfAllowed()      // 「旅の写真から」で許可した
        store.startIfNeeded()       // 棚が出た
        await store.waitUntilIdle()
        XCTAssertEqual(store.runsStarted, 0, "ログインしていないのに読んだ")
        XCTAssertNil(DeviceTripIndexFile.load(from: url), "ログインしていないのに要約を書いた")
        store.setSignedIn(true)
        store.startIfAllowed()
        await store.waitUntilIdle()
        XCTAssertEqual(store.runsStarted, 1, "ログインしたら読む")
        await store.waitForRemoval()
    }

    /// 🔴 **読み終えていない要約は「旅の写真から」に渡さない**（2026-10-16）。
    /// 初めての読みの途中で渡すと、まだ読んでいない古い旅が一覧から抜けていた
    @MainActor
    func testPreloadedShotsOnlyAfterTheSummaryIsComplete() async throws {
        let url = tempURLForGate()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var stored = DeviceTrips.Index()
        stored.shots = Array(library().suffix(7).map(\.shot))   // 途中まで読んだ要約（京都の旅だけ）
        stored.complete = false
        DeviceTripIndexFile.save(stored, to: url)
        let source = FakeTripSource(library())
        let gate = FetchGate()
        source.gate = gate
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceTripScanTests-\(UUID().uuidString)"))
        let store = DeviceTripShelfStore(defaults: defaults, url: url, source: source,
                                         status: { .authorized }, place: { _ in (nil, nil) },
                                         pauseNanos: 0, lookupPauseNanos: 0, observesLibrary: false,
                                         signedIn: true, priority: .userInitiated)
        XCTAssertNil(store.preloadedShots, "まだ何も読んでいない")
        store.startIfAllowed()
        await gate.waitForWaiting(1)            // 覚えた要約を出し、続きを取り出すところで止まった
        XCTAssertFalse(store.shots.isEmpty, "前提: 途中までの要約が棚に出ている")
        XCTAssertNil(store.preloadedShots, "読み終えていない要約を渡している")
        await gate.open()
        await store.waitUntilIdle()
        XCTAssertEqual(store.preloadedShots?.count, store.shots.count, "読み終えたら渡す")
        XCTAssertFalse(store.shots.isEmpty)
        await store.waitForRemoval()
    }

    /// 🔴 一冊から開く「旅の写真から」は `preloadedShots` を渡す（`shots` を直に渡すと読みかけを渡す）
    func testRootViewHandsOnlyCompleteShotsToTheTripFlow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/App/RootView.swift"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("DeviceTripShelfStore.shared.preloadedShots"), "読み終えた要約だけを渡していない")
        XCTAssertFalse(text.contains("DeviceTripShelfStore.shared.shots"), "読みかけの要約を渡している")
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
                                         signedIn: true, priority: .userInitiated)
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

    /// 取り出しのたびに止まる門（nil なら止めない）
    var gate: FetchGate?

    func fetch(since: Date, before: Date?, after: Date?) async -> any DeviceTripAssets {
        if let gate { await gate.enter() }
        let picked = items.filter { item in
            let date = item.shot.date
            return date >= since && (before.map { date <= $0 } ?? true) && (after.map { date > $0 } ?? true)
        }.sorted { $0.shot.date > $1.shot.date }
        return FakeTripAssets(items: picked, source: self)
    }

    func assets(ids: [String]) async -> any DeviceTripAssets {
        lock.lock(); _idsLookups += ids.count; lock.unlock()
        let wanted = Set(ids)
        return FakeTripAssets(items: items.filter { wanted.contains($0.shot.id) }, source: self)
    }
}

/// 取り出しを止める門。**時間に頼らず**、止まった読みを試験が1つずつ放す
actor FetchGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var isOpen = false

    /// 読みが門に入る（開いていなければ放されるまで止まる）
    func enter() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            let ready = watchers.filter { $0.count <= waiting.count }
            watchers.removeAll { $0.count <= waiting.count }
            ready.forEach { $0.continuation.resume() }
        }
    }

    /// 門で止まっている読みが `count` 本になるまで待つ
    func waitForWaiting(_ count: Int) async {
        guard waiting.count < count else { return }
        await withCheckedContinuation { watchers.append((count, $0)) }
    }

    /// いちばん先に止まった読みを放す
    func releaseFirst() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }

    /// 止まっている読みを全部放し、以後は止めない
    func open() {
        isOpen = true
        let all = waiting
        waiting = []
        all.forEach { $0.resume() }
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
