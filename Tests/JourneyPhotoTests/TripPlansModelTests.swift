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
}
