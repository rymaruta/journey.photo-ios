import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 旅行プランを作る流れの保存（`TripCreateModel.save`・2026-11-12）。DM から作る流れは日付の段で保存するので、
/// **保存の最中にもう一度押しても二重に作らない**・選んだ場所が無ければ送らない、を縛る
@MainActor
final class TripCreateSaveTests: XCTestCase {

    /// 通信は `URLProtocol` で差し替える（`TripPlansModelTests` と同じ組み立て）
    private func environment(tokens: TokenProviding = StubTokenProvider(token: "t")) -> AppEnvironment {
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
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: tokens, session: session)
        return AppEnvironment(tokenProvider: tokens, gallery: gallery, spots: index, trips: TripPlanService(api: api))
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

    private func place() -> TripDraft.Place {
        TripDraft.place(location: DerivedSpot.Place(label: "兼六園", slug: "kenrokuen", photos: [], broader: [],
                                                    categories: [], coords: Photo.Coords(lat: 36.56, lng: 136.66)))
    }

    func testSavesOnceAndReturnsThePlan() async {
        let env = environment()
        StubProtocol.respond(path: "/user/trips", status: 200, body: #"{"plans":[{"planId":"new","title":"旅","days":[]}]}"#)
        let model = TripCreateModel(initial: [place()])
        model.title = "旅"
        model.start = "2026-11-22"
        model.end = "2026-11-23"
        let made = await model.save(plans: TripPlansModel(), environment: env)
        XCTAssertEqual(made, "new")
        XCTAssertEqual(StubProtocol.requestCount, 1)
        XCTAssertFalse(model.saving)
    }

    /// 保存の最中（二度押し）は通信しない
    func testSecondSaveWhileSavingDoesNothing() async {
        let env = environment()
        StubProtocol.respond(path: "/user/trips", status: 200, body: #"{"plans":[{"planId":"new","title":"旅","days":[]}]}"#)
        let model = TripCreateModel(initial: [place()])
        model.saving = true
        let made = await model.save(plans: TripPlansModel(), environment: env)
        XCTAssertNil(made)
        XCTAssertEqual(StubProtocol.requestCount, 0, "保存の最中にもう一度送った")
        XCTAssertTrue(model.saving, "最中の印を下ろさない（1回目がまだ終わっていない）")
    }

    /// 1回目が通信している間の2回目も送らない（印は押した瞬間に立つ）
    func testOverlappingSavesSendOnce() async {
        let gate = Gate(holds: 1)
        let env = environment(tokens: GatedTokenProvider(token: "t", gate: gate))
        StubProtocol.respond(path: "/user/trips", status: 200, body: #"{"plans":[{"planId":"new","title":"旅","days":[]}]}"#)
        let model = TripCreateModel(initial: [place()])
        let plans = TripPlansModel()
        let first = Task { await model.save(plans: plans, environment: env) }
        await gate.untilWaiting()
        XCTAssertTrue(model.saving)
        let second = await model.save(plans: plans, environment: env)
        await gate.open()
        let made = await first.value
        XCTAssertNil(second)
        XCTAssertEqual(made, "new")
        XCTAssertEqual(StubProtocol.requestCount, 1, "二重に作っている")
    }

    /// 選んだ場所が無ければ送らない（空のプランを作らない）
    func testNothingPickedDoesNotSend() async {
        let env = environment()
        let model = TripCreateModel(initial: [])
        let made = await model.save(plans: TripPlansModel(), environment: env)
        XCTAssertNil(made)
        XCTAssertEqual(StubProtocol.requestCount, 0)
    }
}
