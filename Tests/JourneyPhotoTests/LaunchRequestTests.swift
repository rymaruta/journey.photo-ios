import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 起動の要求の山を均す仕組み（2026-11-07・本番 Lambda の同時実行上限 10 でスロットルになる件）。
/// 同時数の絞り（`RequestLimiter`）・503/429 の1回だけの再試行（`APIClient`）・起動同期の遅らせ（`LaunchDeferral`）・
/// 診断ログの整形（`DiagnosticsSummary`）。

// MARK: - 同時数の絞り

final class RequestLimiterTests: XCTestCase {

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return await condition()
    }

    func testDefaultLimitIsFour() {
        XCTAssertEqual(RequestLimiter.defaultLimit, 4)
    }

    /// 上限の本数までは待たずに通り、次の1本は枠が返るまで待つ
    func testExtraRequestWaitsUntilASlotIsReleased() async throws {
        let limiter = RequestLimiter(limit: 2)
        try await limiter.acquire()
        try await limiter.acquire()
        let third = Task { try await limiter.acquire() }
        let queued = await waitUntil { await limiter.queued == 1 }
        XCTAssertTrue(queued, "3本目が待たされていない")
        let running = await limiter.inFlight
        XCTAssertEqual(running, 2)

        await limiter.release()
        try await third.value
        let after = await limiter.inFlight
        XCTAssertEqual(after, 2, "枠は待っていた1本に渡る（空きにはならない）")
        let left = await limiter.queued
        XCTAssertEqual(left, 0)
    }

    /// 待っている間に取り消された要求は、列から外れて `CancellationError` を投げ、枠を食わない
    func testCancelledWaiterLeavesTheQueueWithoutLeakingASlot() async throws {
        let limiter = RequestLimiter(limit: 1)
        try await limiter.acquire()
        let waiting = Task { try await limiter.acquire() }
        let queued = await waitUntil { await limiter.queued == 1 }
        XCTAssertTrue(queued)
        waiting.cancel()
        do {
            try await waiting.value
            XCTFail("取り消したのに枠を取れた")
        } catch is CancellationError {
        }
        let left = await limiter.queued
        XCTAssertEqual(left, 0)

        await limiter.release()
        let free = await limiter.inFlight
        XCTAssertEqual(free, 0, "取り消された待ちが枠を持ち出している")
        try await limiter.acquire()
    }

    /// `run` は失敗しても枠を返す
    func testRunReleasesTheSlotWhenTheBodyThrows() async {
        struct Boom: Error {}
        let limiter = RequestLimiter(limit: 1)
        do {
            try await limiter.run { throw Boom() }
            XCTFail()
        } catch {}
        let free = await limiter.inFlight
        XCTAssertEqual(free, 0)
    }
}

// MARK: - 503・429 の再試行

/// **試験の間、仕事の割り振りがどれだけ遅れたかを測る**（札 #610・2026-11-14 判断）。
/// Mac の単体テストで、この組のふだん 0.1秒の試験が、ときどき1本だけ 30〜43秒かかった（run 1330・1334。
/// 組は単体テストの2番目で、テストを載せるアプリが立ち上がった直後に流れる）。どこで待っているかを数で見るため、
/// 試験の外のスレッドから 50ms ごとに、Swift の仕事の列（`Task.detached`）と主スレッドへ小さな仕事を出し、
/// 着くまでの遅れの最大を `measured [throttle]` の行に出す。試験の中の段の時刻（`step`）も出す
final class SchedulingProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var poolMax = 0.0, mainMax = 0.0, poolSlowAt = 0.0, mainSlowAt = 0.0, samples = 0
    private var steps: [String] = []
    let started = Date()

    init() {
        let thread = Thread { [self] in
            while self.isRunning {
                let pool = Self.latency { done in Task.detached { done() } }
                let main = Self.latency { done in DispatchQueue.main.async { done() } }
                self.record(pool: pool, main: main)
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        thread.start()
    }

    private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// 仕事を出してから着くまでの秒（60秒で打ち切り）
    private static func latency(_ submit: (@escaping @Sendable () -> Void) -> Void) -> Double {
        let semaphore = DispatchSemaphore(value: 0)
        let t0 = Date()
        submit { semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 60)
        return Date().timeIntervalSince(t0)
    }

    private func record(pool: Double, main: Double) {
        lock.lock(); defer { lock.unlock() }
        samples += 1
        let at = Date().timeIntervalSince(started)
        if pool > poolMax { poolMax = pool; poolSlowAt = at }
        if main > mainMax { mainMax = main; mainSlowAt = at }
    }

    func step(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        steps.append(name + "=" + String(format: "%.3f", Date().timeIntervalSince(started)))
    }

    /// 止めて1行にする（秒）
    func finish(_ test: String) -> String {
        lock.lock(); running = false; defer { lock.unlock() }
        return "measured [throttle] \(test) total=" + String(format: "%.3f", Date().timeIntervalSince(started))
            + " poolMax=" + String(format: "%.3f", poolMax) + "@" + String(format: "%.2f", poolSlowAt)
            + " mainMax=" + String(format: "%.3f", mainMax) + "@" + String(format: "%.2f", mainSlowAt)
            + " samples=\(samples) steps=[\(steps.joined(separator: " "))]"
    }
}

/// **組の間ずっと、主スレッドが止まった時を記録する**（札 #610・2026-11-15 判断）。
/// run 1345 で、XCTest の数えた1件の秒（2.351秒）と、setUp から tearDown までの秒（0.116秒）が合わなかった
/// ＝待ちは試験の本体の外。XCTest は setUp・試験・tearDown の出入りを主スレッドで回すので、主スレッドが
/// 0.3秒以上止まった時を、組の頭からの秒で `measured [throttle-main]` の行に出す
final class MainThreadWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var stalls: [String] = []
    let started = Date()

    init() {
        let thread = Thread { [self] in
            while self.isRunning {
                let semaphore = DispatchSemaphore(value: 0)
                let t0 = Date()
                DispatchQueue.main.async { semaphore.signal() }
                _ = semaphore.wait(timeout: .now() + 120)
                let waited = Date().timeIntervalSince(t0)
                if waited >= 0.3 { self.note(at: t0.timeIntervalSince(self.started), waited: waited) }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        thread.start()
    }

    private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    private func note(at: Double, waited: Double) {
        lock.lock(); defer { lock.unlock() }
        stalls.append(String(format: "%.2f+%.2f", at, waited))
    }

    /// 組の頭からの秒
    func now() -> Double { Date().timeIntervalSince(started) }

    func finish() -> String {
        lock.lock(); running = false; defer { lock.unlock() }
        return "measured [throttle-main] 組の頭から " + String(format: "%.2f", Date().timeIntervalSince(started))
            + "s 主スレッドが止まった時（頭からの秒+止まった秒）=[\(stalls.joined(separator: " "))]"
    }
}

final class APIClientThrottleRetryTests: XCTestCase {

    nonisolated(unsafe) private static var watch: MainThreadWatch?
    private var session: URLSession!
    private var probe: SchedulingProbe!
    /// この1件の出入りの時刻（組の頭からの秒）
    private var entered = 0.0
    private var setUpAt = 0.0

    override class func setUp() {
        super.setUp()
        watch = MainThreadWatch()
    }

    override class func tearDown() {
        if let watch { print(watch.finish()) }
        watch = nil
        super.tearDown()
    }

    /// XCTest が1件を始めてから終えるまで（setUp・tearDown の外も含む）を、組の頭からの秒で出す
    override func invokeTest() {
        entered = Self.watch?.now() ?? 0
        super.invokeTest()
        let left = Self.watch?.now() ?? 0
        print("measured [throttle-invoke] \(name) in=" + String(format: "%.3f", entered)
              + " out=" + String(format: "%.3f", left) + " took=" + String(format: "%.3f", left - entered))
    }

    /// 待った秒数を覚えるだけ（実際には待たない）
    private final class Pauses: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [TimeInterval] = []
        var values: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return _values }
        func add(_ v: TimeInterval) { lock.lock(); _values.append(v); lock.unlock() }
    }

    override func setUp() {
        super.setUp()
        setUpAt = Self.watch?.now() ?? 0
        probe = SchedulingProbe()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
        probe.step("setUp")
    }

    override func tearDown() {
        print(probe.finish(name) + " setUpAt=" + String(format: "%.3f", setUpAt)
              + " tearDownAt=" + String(format: "%.3f", Self.watch?.now() ?? 0))
        StubProtocol.reset()
        super.tearDown()
    }

    private func client(pauses: Pauses, limit: Int = RequestLimiter.defaultLimit) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "ID-TOKEN"),
            session: session,
            maxConcurrentRequests: limit,
            retryPause: { pauses.add($0) }
        )
    }

    /// 再試行の待ちを `pauseGate` で止められる、枠を取った後を `holdGate` で止められる版
    private func client(limit: Int, pauseGate: Gate? = nil, holdGate: Gate? = nil) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "ID-TOKEN"),
            session: session,
            maxConcurrentRequests: limit,
            retryPause: { _ in await pauseGate?.wait() },
            afterAcquire: { _ in await holdGate?.wait() }
        )
    }

    private struct Payload: Decodable, Equatable { let ok: Bool }

    private final class DoneFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return _value }
        func set() { lock.lock(); _value = true; lock.unlock() }
    }

    func testGetIsRetriedOnceAfter503AndThenSucceeds() async throws {
        StubProtocol.respondInOrder([(503, #"{"error":"busy"}"#), (200, #"{"ok":true}"#)])
        let pauses = Pauses()
        let result = try await client(pauses: pauses).authorized(.get, "/user/profile", as: Payload.self)
        XCTAssertEqual(result, Payload(ok: true))
        XCTAssertEqual(StubProtocol.requestCount, 2)
        XCTAssertEqual(pauses.values.count, 1)
        let pause = try XCTUnwrap(pauses.values.first)
        XCTAssertTrue(APIClient.retryJitter.contains(pause), "待ちが 0.5〜1.5 秒の範囲に入っていない: \(pause)")
    }

    func testGetIsRetriedOnceAfter429() async throws {
        StubProtocol.respondInOrder([(429, ""), (200, #"{"ok":true}"#)])
        let result = try await client(pauses: Pauses()).authorized(.get, "/user/profile", as: Payload.self)
        XCTAssertEqual(result, Payload(ok: true))
        XCTAssertEqual(StubProtocol.requestCount, 2)
    }

    /// `Retry-After`（秒）があればそれに従う。長すぎる指示は上限に丸める
    func testRetryAfterHeaderIsHonouredAndCapped() async throws {
        StubProtocol.responseHeaders = ["Retry-After": "2"]
        StubProtocol.respondInOrder([(503, ""), (200, #"{"ok":true}"#)])
        let pauses = Pauses()
        _ = try await client(pauses: pauses).authorized(.get, "/user/profile", as: Payload.self)
        XCTAssertEqual(pauses.values, [2])

        StubProtocol.reset()
        StubProtocol.responseHeaders = ["Retry-After": "120"]
        StubProtocol.respondInOrder([(503, ""), (200, #"{"ok":true}"#)])
        let capped = Pauses()
        _ = try await client(pauses: capped).authorized(.get, "/user/profile", as: Payload.self)
        XCTAssertEqual(capped.values, [APIClient.retryAfterCap])
    }

    func testRetryDelayAndHeaderParsing() {
        XCTAssertEqual(APIClient.retryDelay(retryAfter: nil, jitter: 0.8), 0.8)
        XCTAssertEqual(APIClient.retryDelay(retryAfter: 3, jitter: 0.8), 3)
        XCTAssertEqual(APIClient.retryDelay(retryAfter: 99, jitter: 0.8), APIClient.retryAfterCap)
        XCTAssertEqual(APIClient.retryAfterSeconds("2"), 2)
        XCTAssertEqual(APIClient.retryAfterSeconds(" 1 "), 1)
        XCTAssertNil(APIClient.retryAfterSeconds("Wed, 21 Oct 2026 07:28:00 GMT"), "日付の形は読まず、ばらつきの待ちに倒す")
        XCTAssertNil(APIClient.retryAfterSeconds("-1"))
        XCTAssertNil(APIClient.retryAfterSeconds(nil))
    }

    /// 送り直しも 503 なら、そこで諦める（1回だけ）
    func testGivesUpAfterOneRetry() async {
        StubProtocol.respond(status: 503, body: #"{"error":"busy"}"#)
        let pauses = Pauses()
        do {
            _ = try await client(pauses: pauses).authorized(.get, "/user/profile", as: Payload.self)
            XCTFail("503 のまま成功した")
        } catch let error as APIError {
            guard case .server(let status, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(status, 503)
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertEqual(StubProtocol.requestCount, 2, "1回だけ送り直す")
        XCTAssertEqual(pauses.values.count, 1)
    }

    /// 🔴 書く要求は送り直さない（サーバーが処理したあとの 503 かもしれず、二重に書く）
    func testWritesAreNeverRetried() async {
        for method in [APIClient.Method.post, .put, .patch, .delete] {
            StubProtocol.reset()
            StubProtocol.respondInOrder([(503, ""), (200, #"{"ok":true}"#)])
            let pauses = Pauses()
            do {
                _ = try await client(pauses: pauses).authorizedVoid(method, "/user/likes")
                XCTFail("\(method) が 503 のあと成功した（送り直している）")
            } catch {}
            XCTAssertEqual(StubProtocol.requestCount, 1, "\(method) を送り直した")
            XCTAssertTrue(pauses.values.isEmpty)
        }
    }

    /// 500 などスロットル以外は送り直さない
    func testOtherServerErrorsAreNotRetried() async {
        StubProtocol.respondInOrder([(500, ""), (200, #"{"ok":true}"#)])
        do {
            _ = try await client(pauses: Pauses()).authorized(.get, "/user/profile", as: Payload.self)
            XCTFail()
        } catch {}
        XCTAssertEqual(StubProtocol.requestCount, 1)
    }

    /// 🔴 `APIClient` が同時に飛ばすのは `maxConcurrentRequests` 本まで。枠を取った後で止まる要求が
    /// 2本あれば、3本目以降は通信（`afterAcquire`）に着かない。`transfer` の `limiter.acquire()` を消すと
    /// 4本全部が着いて落ちる
    func testApiClientNeverRunsMoreThanTheLimitAtOnce() async throws {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        let hold = Gate()
        let api = client(limit: 2, holdGate: hold)
        let tasks = (0..<4).map { _ in
            Task { try await api.authorized(.get, "/user/profile", as: Payload.self) }
        }
        probe.step("tasks")
        await hold.untilWaiting(2)
        probe.step("waiting")
        try? await Task.sleep(nanoseconds: 100_000_000)
        probe.step("slept")
        let arrived = await hold.arrived
        XCTAssertEqual(arrived, 2, "上限(2)を超えて同時に通信へ入った")
        XCTAssertEqual(StubProtocol.requestCount, 0, "止めている間に通信が出た")

        await hold.open()
        probe.step("opened")
        for task in tasks { _ = try await task.value }
        probe.step("done")
        let total = await hold.arrived
        XCTAssertEqual(total, 4, "待たされた要求が最後まで通っていない")
        XCTAssertEqual(StubProtocol.requestCount, 4)
    }

    /// 🔴 再試行の待ちの途中で枠を握らない。枠1本で、1本目が待ちの最中でも2本目が通る
    /// （待ちの間も枠を持つ作りに戻すと、2本目が通らず落ちる）
    func testOtherRequestPassesWhileARetryIsWaiting() async throws {
        StubProtocol.respondInOrder([(503, ""), (200, #"{"ok":true}"#)])
        let pauseGate = Gate()
        let api = client(limit: 1, pauseGate: pauseGate)
        let first = Task { try await api.authorized(.get, "/user/profile", as: Payload.self) }
        await pauseGate.untilWaiting(1)
        probe.step("waiting")

        let done = DoneFlag()
        let second = Task { () -> Payload in
            let value = try await api.authorized(.get, "/user/profile", as: Payload.self)
            done.set()
            return value
        }
        let deadline = Date().addingTimeInterval(2)
        while !done.value, Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        let passedWhileWaiting = done.value
        probe.step("second")
        await pauseGate.open()
        let secondValue = try await second.value
        let firstValue = try await first.value
        probe.step("done")
        XCTAssertEqual(secondValue, Payload(ok: true))
        XCTAssertEqual(firstValue, Payload(ok: true))
        XCTAssertTrue(passedWhileWaiting, "再試行の待ちの間、枠を握ったままになっている")
    }

    /// 🔴 再試行の待ちの最中に取り消されたら送り直さず、枠も返る
    /// （待ちのあとの `Task.checkCancellation` を消すと、2本目が出て落ちる）
    func testCancelDuringRetryWaitDoesNotResendAndFreesTheSlot() async throws {
        StubProtocol.respondInOrder([(503, ""), (200, #"{"ok":true}"#)])
        let pauseGate = Gate()
        let api = client(limit: 1, pauseGate: pauseGate)
        let first = Task { try await api.authorized(.get, "/user/profile", as: Payload.self) }
        await pauseGate.untilWaiting(1)
        probe.step("waiting")
        first.cancel()
        await pauseGate.open()
        probe.step("opened")
        do {
            _ = try await first.value
            probe.step("value")
            XCTFail("取り消したのに成功した")
        } catch is CancellationError {
        } catch {
            XCTFail("取り消しが別の失敗になった: \(error)")
        }
        XCTAssertEqual(StubProtocol.requestCount, 1, "取り消されたのに送り直した")

        probe.step("cancelled")
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        let next = try await api.authorized(.get, "/user/profile", as: Payload.self)
        probe.step("next")
        XCTAssertEqual(next, Payload(ok: true), "枠が返っていない")
    }

    /// 🔴 書く要求(POST など)は、読む要求の枠が埋まっていても通る(別の枠・2026-11-07)。
    /// 読む枠が 1 本で、その 1 本が止まっている間に POST が完了する。書く要求も同じ枠に入れる作りに戻すと、
    /// POST が詰まって 2 秒待っても終わらず落ちる
    func testWriteRequestIsNotBlockedBySlowReads() async throws {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        let hold = Gate()
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "ID-TOKEN"), session: session,
                            maxConcurrentRequests: 1, retryPause: { _ in },
                            afterAcquire: { request in
            if request.httpMethod == "GET" { await hold.wait() }
        })
        let read = Task { try await api.authorized(.get, "/user/profile", as: Payload.self) }
        await hold.untilWaiting(1)
        probe.step("waiting")

        let done = DoneFlag()
        let write = Task { () -> Void in
            _ = try await api.authorizedVoid(.post, "/user/likes")
            done.set()
        }
        let deadline = Date().addingTimeInterval(2)
        while !done.value, Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        let passed = done.value
        probe.step("write")
        await hold.open()
        _ = try await read.value
        try await write.value
        probe.step("done")
        XCTAssertTrue(passed, "書く要求が読む要求の列に詰まった")
    }

    /// 書く枠の同時数にも上限がある(既定 2・読み4+書き2=6 が本番の上限 10 の内)
    func testWriteLimitIsSmallAndWithinTheBudget() {
        XCTAssertEqual(RequestLimiter.defaultWriteLimit, 2)
        XCTAssertLessThanOrEqual(RequestLimiter.defaultLimit + RequestLimiter.defaultWriteLimit, 10)
    }

    /// 本番の配線は書く枠も共通のものを渡す
    func testProductionWiringUsesTheSharedWriteLimiter() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        for path in ["Sources/JourneyPhoto/App/AppEnvironment.swift", "Sources/JourneyPhoto/Core/Networking/PreviewBackend.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains("writeLimiter: RequestLimiter.sharedWrites"), "\(path) が共通の書く枠を使っていない")
        }
    }

    /// 🔴 同じ絞りを渡した `APIClient` どうしは、合わせて上限までしか出さない(本番は `RequestLimiter.shared`)。
    /// 絞りを `APIClient` ごとに持つ作りに戻すと、2本ずつ計4本が出て落ちる
    func testClientsSharingALimiterShareTheLimit() async throws {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        let hold = Gate()
        let shared = RequestLimiter(limit: 2)
        func make() -> APIClient {
            APIClient(baseURL: URL(string: "https://api.example.test")!,
                      tokenProvider: StubTokenProvider(token: "ID-TOKEN"), session: session,
                      limiter: shared, afterAcquire: { _ in await hold.wait() })
        }
        let a = make(), b = make()
        let tasks = (0..<2).map { _ in Task { try await a.authorized(.get, "/user/profile", as: Payload.self) } }
            + (0..<2).map { _ in Task { try await b.authorized(.get, "/user/profile", as: Payload.self) } }
        probe.step("tasks")
        await hold.untilWaiting(2)
        probe.step("waiting")
        try? await Task.sleep(nanoseconds: 100_000_000)
        probe.step("slept")
        let arrived = await hold.arrived
        XCTAssertEqual(arrived, 2, "別の APIClient が別枠で出している")
        await hold.open()
        probe.step("opened")
        for task in tasks { _ = try await task.value }
        probe.step("done")
    }

    /// 本番の配線(`AppEnvironment`・`APIClient.app()`)は共通の絞りを渡す。外すと画面ごとの実体が別枠になる
    func testProductionWiringUsesTheSharedLimiter() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        for path in ["Sources/JourneyPhoto/App/AppEnvironment.swift", "Sources/JourneyPhoto/Core/Networking/PreviewBackend.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains("limiter: RequestLimiter.shared"), "\(path) が共通の絞りを使っていない")
        }
    }

    /// 待っている間は枠を握らない（枠が1本でも、送り直しが詰まらない）
    func testRetryWaitDoesNotHoldTheConcurrencySlot() async throws {
        StubProtocol.respondInOrder([(503, ""), (200, #"{"ok":true}"#)])
        let result = try await client(pauses: Pauses(), limit: 1)
            .authorized(.get, "/user/profile", as: Payload.self)
        XCTAssertEqual(result, Payload(ok: true))
    }

    /// 枠が1本でも、通信が終われば次の要求が通る（枠の返し忘れが無い）
    func testSlotIsReturnedAfterEachRequestEvenOnFailure() async throws {
        let api = client(pauses: Pauses(), limit: 1)
        StubProtocol.respond(status: 404, body: "")
        for _ in 0..<3 {
            _ = try? await api.authorized(.get, "/user/profile", as: Payload.self)
        }
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        let result = try await api.authorized(.get, "/user/profile", as: Payload.self)
        XCTAssertEqual(result, Payload(ok: true))
    }
}

// MARK: - 起動同期の遅らせ

final class LaunchDeferralTests: XCTestCase {

    private final class Pauses: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [TimeInterval] = []
        var values: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return _values }
        func add(_ v: TimeInterval) { lock.lock(); _values.append(v); lock.unlock() }
    }

    func testOnlyTheFirstCallWaits() async {
        let pauses = Pauses()
        let deferral = LaunchDeferral(pause: { pauses.add($0) })
        let first = await deferral.waitOnce()
        let second = await deferral.waitOnce()
        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(pauses.values, [LaunchDeferral.grace], "最初の1回だけ待つ")
    }

    func testSkipDoesNotWaitAndStillConsumesTheTurn() async {
        let pauses = Pauses()
        let deferral = LaunchDeferral(pause: { pauses.add($0) })
        _ = await deferral.waitOnce(skip: true)
        _ = await deferral.waitOnce()
        XCTAssertTrue(pauses.values.isEmpty)
    }

    /// 🔴 ログインしていない回(`eligible: false`)は待たず、「最初の1回」も使わない。
    /// そのあとログインした回がちゃんと待てる(使い切ると、ログイン後の同期が遅れず山を作る)
    func testIneligibleCallDoesNotConsumeTheFirstTurn() async {
        let pauses = Pauses()
        let deferral = LaunchDeferral(pause: { pauses.add($0) })
        let signedOut = await deferral.waitOnce(eligible: false)
        XCTAssertTrue(signedOut)
        XCTAssertTrue(pauses.values.isEmpty, "ログインしていない回で待った")
        _ = await deferral.waitOnce(eligible: true)
        XCTAssertEqual(pauses.values, [LaunchDeferral.grace], "ログインした回が待てていない")
    }

    /// 🔴 取り消された回は「最初の1回」を使わない。次の回(取り消した側の後継)がちゃんと待つ。
    /// 先頭の取り消し確認を外すと、取り消された回が使い切って次が待たず落ちる
    func testCancelledCallDoesNotConsumeTheFirstTurn() async {
        let pauses = Pauses()
        let deferral = LaunchDeferral(pause: { pauses.add($0) })
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return await deferral.waitOnce()
        }
        let first = await task.value
        XCTAssertFalse(first)
        XCTAssertTrue(pauses.values.isEmpty, "取り消された回が待った")
        let next = await deferral.waitOnce()
        XCTAssertTrue(next)
        XCTAssertEqual(pauses.values, [LaunchDeferral.grace], "取り消された回が最初の1回を使い切った")
    }

    func testCancelledCallerIsToldToStop() async {
        let deferral = LaunchDeferral(pause: { _ in })
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return await deferral.waitOnce()
        }
        let proceed = await task.value
        XCTAssertFalse(proceed, "取り消されたのに続きを走らせる")
    }

    func testGraceIsShort() {
        XCTAssertLessThanOrEqual(LaunchDeferral.grace, 3, "端末登録・ブロックの反映を長く遅らせない")
        XCTAssertGreaterThan(LaunchDeferral.grace, 0)
    }
}

// MARK: - 診断ログの整形

final class DiagnosticsSummaryTests: XCTestCase {

    func testCrashLine() {
        let line = DiagnosticsSummary.crash(signal: 11, exceptionType: 1, exceptionCode: nil,
                                            terminationReason: "Namespace SIGNAL", appVersion: "1.1.20")
        XCTAssertEqual(line, "crash version=1.1.20 signal=11 exceptionType=1 exceptionCode=- termination=Namespace SIGNAL")
    }

    func testHangAndExceptionLines() {
        XCTAssertEqual(DiagnosticsSummary.hang(milliseconds: 2_345.6, appVersion: "1.1.20"),
                       "hang version=1.1.20 duration_ms=2346")
        XCTAssertEqual(DiagnosticsSummary.exception(kind: "cpu", appVersion: "1.1.20"), "cpu-exception version=1.1.20")
    }

    func testLaunchLineSkipsEmptyBuckets() {
        let line = DiagnosticsSummary.launch(
            buckets: [(0, 500, 12), (500, 1_000, 0), (1_000, 1_500, 3)], appVersion: "1.1.20")
        XCTAssertEqual(line, "launch version=1.1.20 samples=15 firstDraw=[0-500ms:12 1000-1500ms:3]")
    }

    func testChunksSplitAndClip() {
        XCTAssertEqual(DiagnosticsSummary.chunks(""), [])
        XCTAssertEqual(DiagnosticsSummary.chunks("abcdef", size: 4, limit: 100), ["abcd", "ef"])
        let clipped = DiagnosticsSummary.chunks(String(repeating: "x", count: 25), size: 10, limit: 20)
        XCTAssertEqual(clipped.count, 3)
        XCTAssertEqual(clipped[0].count, 10)
        XCTAssertTrue(clipped[2].contains("5"), "省いた文字数を最後に書く")
    }
}
