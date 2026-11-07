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

final class APIClientThrottleRetryTests: XCTestCase {

    private var session: URLSession!

    /// 待った秒数を覚えるだけ（実際には待たない）
    private final class Pauses: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [TimeInterval] = []
        var values: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return _values }
        func add(_ v: TimeInterval) { lock.lock(); _values.append(v); lock.unlock() }
    }

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
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

    private struct Payload: Decodable, Equatable { let ok: Bool }

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
