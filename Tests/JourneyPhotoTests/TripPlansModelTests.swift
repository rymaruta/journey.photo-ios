import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 旅行プランの一覧の状態（キャンバス 17）。
///
/// **「まだ」「聞けなかった」「0件」を混ぜない**・**書き込みの応答をそのまま映す**・
/// **連打で二重に作らない**（Web の `useTripPlans` と同じ約束）。
@MainActor
final class TripPlansModelTests: XCTestCase {

    /// 通信は `URLProtocol` で差し替える（`PhotoMapViewModelTests` と同じ組み立て）。
    /// 写真の一覧と索引も差し替えておく——既定のままだと本物のサイトを見にいく
    private func environment() -> AppEnvironment {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
        let gallery = PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: session,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        )
        let index = OfficialSpotService(
            url: URL(string: "https://site.example.test/app/data/spots.json")!,
            session: session,
            snapshot: SpotSnapshotStore(fileName: UUID().uuidString)
        )
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        return AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: gallery, spots: index,
                              trips: TripPlanService(api: api))
    }

    override func setUp() async throws {
        try await super.setUp()
        StubProtocol.reset()
    }

    override func tearDown() async throws {
        StubProtocol.reset()
        AppConfig.testOverrides = nil
        try await super.tearDown()
    }

    /// 取れなかったら「失敗」。**0件とは言わない**。赤い行も重ねない（再試行の1行が出る）
    func testFailedLoadIsNotEmpty() async {
        StubProtocol.respond(status: 500, body: "")
        let model = TripPlansModel()
        await model.load(environment: environment())
        XCTAssertEqual(model.status, .failed)
        XCTAssertTrue(model.plans.isEmpty)
        XCTAssertNil(model.errorMessage, "「読み込めませんでした」の1行と赤い行が重なる")
    }

    /// 取れていた一覧は、取り直しに失敗しても消さない（引き下げ更新で消さない）
    func testRefreshFailureKeepsTheList() async {
        let env = environment()
        let model = TripPlansModel()
        StubProtocol.respond(status: 200, body: #"{"plans":[{"planId":"p1","title":"冬","days":[]}]}"#)
        await model.load(environment: env)
        StubProtocol.respond(status: 500, body: "")
        await model.load(environment: env)
        XCTAssertEqual(model.status, .loaded)
        XCTAssertEqual(model.plans.map(\.planId), ["p1"])
        XCTAssertNotNil(model.errorMessage, "取り直せなかったことを黙っている")
    }

    /// 作ったら**増えた1件**を返す（作った直後にそのプランを開く）。一覧は応答そのもの
    func testCreateReturnsTheNewPlan() async {
        let env = environment()
        let model = TripPlansModel()
        StubProtocol.respond(status: 200, body: #"{"plans":[{"planId":"old","title":"前","days":[]}]}"#)
        await model.load(environment: env)
        StubProtocol.respond(status: 200, body: #"{"plans":[{"planId":"new","title":"冬","days":[]},{"planId":"old","title":"前","days":[]}]}"#)
        let made = await model.create(title: "冬", environment: env)
        XCTAssertEqual(made?.planId, "new")
        XCTAssertEqual(model.plans.map(\.planId), ["new", "old"])
        XCTAssertNil(model.busy)
    }

    /// 🔴 **最初の読み込みに失敗していても、既にある別のプランを開かない。**
    /// 手元が空だと全部が「増えた」に入るので、題と作った時刻で選ぶ
    func testCreateAfterFailedLoadPicksTheNewPlan() async {
        let env = environment()
        let model = TripPlansModel()
        StubProtocol.respond(status: 500, body: "{}")
        await model.load(environment: env)
        StubProtocol.respond(status: 200, body: #"{"plans":[{"planId":"old","title":"前","days":[],"createdAt":"2026-09-01T00:00:00Z"},{"planId":"old2","title":"冬","days":[],"createdAt":"2026-09-02T00:00:00Z"},{"planId":"new","title":"冬","days":[],"createdAt":"2026-09-27T00:00:00Z"}]}"#)
        let made = await model.create(title: "冬", environment: env)
        XCTAssertEqual(made?.planId, "new")
    }

    /// **連打で二重に作らない。** 書き込み中の2回目は通信しない
    func testSecondWriteWhileBusyDoesNothing() async {
        let env = environment()
        let model = TripPlansModel()
        StubProtocol.respond(path: "/user/trips", status: 200,
                             body: #"{"plans":[{"planId":"new","title":"冬","days":[]}]}"#, delay: 0.3)
        async let first = model.create(title: "冬", environment: env)
        // 1回目が飛んでから押す
        try? await Task.sleep(nanoseconds: 50_000_000)
        let second = await model.create(title: "冬", environment: env)
        _ = await first
        XCTAssertNil(second)
        XCTAssertEqual(StubProtocol.requestCount, 1, "二重に作っている")
    }

    /// 断られたら**サーバーの言い分**を出し、一覧は書き換えない
    func testRefusalKeepsListAndShowsServerMessage() async {
        let env = environment()
        let model = TripPlansModel()
        StubProtocol.respond(status: 200, body: #"{"plans":[{"planId":"p1","title":"冬","days":[]}]}"#)
        await model.load(environment: env)
        StubProtocol.respond(status: 403, body: #"{"error":"旅行プランは50個までです"}"#)
        let made = await model.create(title: "51件目", environment: env)
        XCTAssertNil(made)
        XCTAssertEqual(model.plans.map(\.planId), ["p1"])
        XCTAssertEqual(model.errorMessage, "旅行プランは50個までです")
    }

    /// **取り直しが成功したら、前の失敗の文は消える**（残ると一覧にも詳細にも出続ける）
    func testSuccessfulReloadClearsTheError() async {
        let env = environment()
        let model = TripPlansModel()
        StubProtocol.respond(status: 200, body: #"{"plans":[{"planId":"p1","title":"冬","days":[]}]}"#)
        await model.load(environment: env)
        StubProtocol.respond(status: 500, body: "")
        await model.load(environment: env)
        XCTAssertNotNil(model.errorMessage, "前提: 失敗の文が出ている")
        StubProtocol.respond(status: 200, body: #"{"plans":[{"planId":"p1","title":"冬","days":[]}]}"#)
        await model.load(environment: env)
        XCTAssertNil(model.errorMessage, "成功したのに赤い行が残っている")
    }

    /// **打ち切りは失敗にしない**（画面を離れて `.task` が打ち切られただけ）。
    ///
    /// 打ち切るのは**トークンを待っている間**。通信の途中で打ち切ると、Linux の
    /// FoundationNetworking が遅れて届く後始末でプロセスごと落ちる（実測）ので、
    /// 通信に入る前の await で打ち切る——画面で起きるのと同じ「待っている間の打ち切り」
    func testCancelledLoadIsNotAFailure() async {
        let env = environment()
        let model = TripPlansModel()
        StubProtocol.respond(status: 200, body: #"{"plans":[{"planId":"p1","title":"冬","days":[]}]}"#)
        await model.load(environment: env)
        let slow = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"),
                                  gallery: env.gallery, spots: env.spots,
                                  trips: TripPlanService(api: APIClient(
                                      baseURL: URL(string: "https://api.example.test")!,
                                      tokenProvider: SlowTokenProvider())))
        let task = Task { await model.load(environment: slow) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await task.value
        XCTAssertNil(model.errorMessage, "打ち切りを失敗の文にしている")
        XCTAssertEqual(model.status, .loaded)
        XCTAssertEqual(model.plans.map(\.planId), ["p1"])
    }

    /// 🔴 **作る前に始めた読み込みが後から返っても、作ったプランを消さない**
    /// （バグ探し 2026-09-27 L-6）。読み込みはトークン待ちで遅らせ、その間に作る
    func testLoadStartedBeforeCreateDoesNotDropTheNewPlan() async {
        let env = environment()
        let model = TripPlansModel()
        // 1本目に届くのは「作る」（作った後の一覧）、2本目が遅れた読み込み（作る前の姿）
        StubProtocol.respondInOrder([
            (200, #"{"plans":[{"planId":"new","title":"夏","days":[]},{"planId":"p1","title":"冬","days":[]}]}"#),
            (200, #"{"plans":[{"planId":"p1","title":"冬","days":[]}]}"#),
        ])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let slow = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"),
                                  gallery: env.gallery, spots: env.spots,
                                  trips: TripPlanService(api: APIClient(
                                      baseURL: URL(string: "https://api.example.test")!,
                                      tokenProvider: DelayedTokenProvider(),
                                      session: URLSession(configuration: config))))
        let loading = Task { await model.load(environment: slow) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let created = await model.create(title: "夏", environment: env)
        XCTAssertEqual(created?.planId, "new", "前提: 作れていない")
        await loading.value
        XCTAssertEqual(model.plans.map(\.planId), ["new", "p1"], "作る前の読み込みの答えで、作ったプランを消している")
        XCTAssertEqual(model.status, .loaded)
    }

    /// 失敗したあとも `busy` は戻る（戻らないと、以後どのボタンも押せない）
    func testBusyResetsAfterFailure() async {
        let env = environment()
        let model = TripPlansModel()
        StubProtocol.respond(status: 500, body: "")
        _ = await model.create(title: "冬", environment: env)
        XCTAssertNil(model.busy)
        XCTAssertNotNil(model.errorMessage)
    }
}

/// トークンを返すまで待つ（その間に打ち切られると `CancellationError`）
/// 通信に入る前に少しだけ待つ（読み込みの要求を「作る」より後に届かせる）
private struct DelayedTokenProvider: TokenProviding {
    func idToken() async throws -> String? {
        try await Task.sleep(nanoseconds: 300_000_000)
        return "t"
    }
}

private struct SlowTokenProvider: TokenProviding {
    func idToken() async throws -> String? {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        return "t"
    }
}
