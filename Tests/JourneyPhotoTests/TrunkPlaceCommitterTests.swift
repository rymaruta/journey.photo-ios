import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 応答を少し遅らせる口（書き込みの最中を作る）。PUT の本文を控える
final class SlowTrunkProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var puts: [(path: String, body: Data?)] = []
    nonisolated(unsafe) static var delay: TimeInterval = 0.2
    /// この字を含む道だけ 500 にする
    nonisolated(unsafe) static var failPath: String?

    static func reset() {
        failPath = nil
        status = 200
        body = ""
        puts = []
        delay = 0.2
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? ""
        let path = request.url?.path ?? ""
        if method == "PUT" { Self.puts.append((path, request.httpBody ?? Self.read(request.httpBodyStream))) }
        let wait = method == "GET" ? 0 : Self.delay
        let status = method == "GET" ? 200 : (Self.failPath.map { path.contains($0) } == true ? 500 : Self.status)
        DispatchQueue.global().asyncAfter(deadline: .now() + wait) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data((status == 200 ? Self.body : #"{"error":"x"}"#).utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

/// 自分の手で貼る画面の保存（2026-10-17 の見直し 3回目）: 「完了」の数え方・保存せずに閉じる・新しい頼みが勝つ
final class TrunkPlaceCommitterTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowTrunkProtocol.self]
        session = URLSession(configuration: config)
        SlowTrunkProtocol.reset()
        let label = { (id: String) in #"{"id":"\#(id)","kind":"place","place":{"name":"京都"},"seed":1,"at":"2026-10-17T00:00:00Z"}"# }
        SlowTrunkProtocol.body = #"{"pocket":[],"stuck":[\#(label("a")),\#(label("b")),\#(label("c"))]}"#
    }

    override func tearDown() {
        SlowTrunkProtocol.reset()
        super.tearDown()
    }

    @MainActor
    private func makeModel() async -> TrunkViewModel {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil)
        model.bind(TrunkService(api: api))
        await model.load(offline: false)
        return model
    }

    private func rot(_ body: Data?) -> Double? {
        guard let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return json["rot"] as? Double
    }

    /// 🔴 A を回して保存待ち → B を運んで離す（B が先に送られる）→ すぐ「完了」: もう溜まっていない B を失敗と数えない
    @MainActor
    func testFlushCountsAlreadySentAsSuccess() async {
        let model = await makeModel()
        let places = TrunkPlaceCommitter()
        places.bind(model)
        let p0 = TrunkPos(x: 0.5, y: 0.5, rot: 0)
        places.note("a", from: p0, to: TrunkPos(x: 0.5, y: 0.5, rot: 8))
        places.note("b", from: p0, to: TrunkPos(x: 0.2, y: 0.2, rot: 0))
        let drop = Task { await places.commit("b") }
        while !model.busy { await Task.yield() }
        let ok = await places.flush()
        _ = await drop.value
        XCTAssertTrue(ok, "もう送れた B を失敗と数えて閉じない")
        XCTAssertTrue(places.pending.isEmpty)
        XCTAssertEqual(SlowTrunkProtocol.puts.count, 2)
    }

    /// 送れなかった（圏外など）: 「完了」は false で、置き場は残る（閉じずに聞く）
    @MainActor
    func testFlushKeepsWhatFailed() async {
        let model = await makeModel()
        SlowTrunkProtocol.status = 500
        SlowTrunkProtocol.delay = 0
        let places = TrunkPlaceCommitter()
        places.bind(model)
        places.note("a", from: TrunkPos(x: 0.5, y: 0.5, rot: 0), to: TrunkPos(x: 0.5, y: 0.5, rot: 8))
        let ok = await places.flush()
        XCTAssertFalse(ok)
        XCTAssertNotNil(places.pending["a"], "送れなかった置き場を黙って消した")
    }

    /// 「保存せずに閉じる」: 溜まった置き場を送らない（閉じたあとの送り残しも出さない）
    @MainActor
    func testDiscardAllSendsNothing() async throws {
        let model = await makeModel()
        let places = TrunkPlaceCommitter()
        places.bind(model)
        places.note("a", from: TrunkPos(x: 0.5, y: 0.5, rot: 0), to: TrunkPos(x: 0.5, y: 0.5, rot: 8))
        places.schedule("a", delay: 0.05)
        places.discardAll()
        places.sendLeftovers()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(SlowTrunkProtocol.puts.isEmpty, "保存せずに閉じたのに送った")
        XCTAssertTrue(places.pending.isEmpty)
    }

    /// 🔴 書き込みの最中に、同じラベルへ古い値 → 新しい値の順で頼む: 送られるのは新しい値の1回だけ
    @MainActor
    func testOnlyTheNewestPlaceIsSent() async throws {
        let model = await makeModel()
        let other = Task { await model.placeWhenFree("c", at: TrunkPos(x: 0.9, y: 0.9, rot: 0)) }
        while !model.busy { await Task.yield() }
        let old = Task { await model.placeWhenFree("a", at: TrunkPos(x: 0.2, y: 0.2, rot: 5)) }
        // 古い頼みが番号を受けて待ち始めるまで
        try await Task.sleep(nanoseconds: 60_000_000)
        let new = Task { await model.placeWhenFree("a", at: TrunkPos(x: 0.3, y: 0.3, rot: -9)) }
        let results = [await other.value, await old.value, await new.value]
        XCTAssertEqual(results, [.saved, .superseded, .saved])
        let sent = SlowTrunkProtocol.puts.filter { $0.path == "/user/trunk/labels/a/place" }
        XCTAssertEqual(sent.count, 1, "古い置き場も送った")
        XCTAssertEqual(rot(sent.first?.body), -9, "古い値で上書きした")
    }

    /// 🔴 「完了」の頼みが新しい頼みに負けても、その新しい頼みが失敗したら閉じない（成功と数えない）
    @MainActor
    func testFlushWaitsForTheNewerRequest() async throws {
        let model = await makeModel()
        SlowTrunkProtocol.failPath = "/labels/a/"
        let places = TrunkPlaceCommitter()
        places.bind(model)
        places.note("a", from: TrunkPos(x: 0.5, y: 0.5, rot: 0), to: TrunkPos(x: 0.5, y: 0.5, rot: 8))
        let other = Task { await model.placeWhenFree("c", at: TrunkPos(x: 0.9, y: 0.9, rot: 0)) }
        while !model.busy { await Task.yield() }
        let flushing = Task { await places.flush() }
        try await Task.sleep(nanoseconds: 60_000_000)
        // すぐ後に同じ1枚を回した（新しい頼み）。それが失敗する
        places.note("a", from: TrunkPos(x: 0.5, y: 0.5, rot: 0), to: TrunkPos(x: 0.5, y: 0.5, rot: 16))
        let later = Task { await places.commit("a") }
        _ = await other.value
        let ok = await flushing.value
        _ = await later.value
        XCTAssertFalse(ok, "後の頼みが失敗したのに閉じた")
        XCTAssertNotNil(places.pending["a"])
    }
}
