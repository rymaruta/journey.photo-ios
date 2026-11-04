import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 地図の「スポット」の札の行は、body の評価のたびに計算しない（2026-11-04）。
/// 入力（query・photos・officialSpots・photoLinks・spotAliases・起点）が変わった回だけ計算する。
final class SpotListCacheTests: XCTestCase {

    private var session: URLSession!
    private var prefix = ""
    private var snapshotNames: [String] = []

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
    }

    override func tearDown() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let names = snapshotNames + ["index", "jp-kanto", "fr"].map { "\(prefix)-\($0).json" }
        for name in names {
            let file = caches.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: file.appendingPathExtension("validator"))
        }
        StubProtocol.reset()
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    private let tokyo = Photo.Coords(lat: 35.68, lng: 139.76)
    private let paris = Photo.Coords(lat: 48.85, lng: 2.35)

    @MainActor
    private func loadedModel() async -> (PhotoMapViewModel, AppEnvironment) {
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200, body: SpotFeedShardsTests.index())
        StubProtocol.respond(path: "/app/data/spot-feed/jp-kanto.json", status: 200, body: SpotFeedShardsTests.kanto)
        StubProtocol.respond(path: "/app/data/spot-feed/fr.json", status: 200, body: SpotFeedShardsTests.france)
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: "[]")
        prefix = UUID().uuidString
        let legacy = UUID().uuidString
        let photos = UUID().uuidString
        snapshotNames += [legacy, photos]
        let spots = OfficialSpotService(url: URL(string: "https://site.example.test/app/data/spots.json")!,
                                        session: session, snapshot: SpotSnapshotStore(fileName: legacy),
                                        feedSnapshotPrefix: prefix)
        let gallery = PublicGalleryService(url: URL(string: "https://site.example.test/app/data/photos.json")!,
                                           session: session, snapshot: PhotoSnapshotStore(fileName: photos))
        let environment = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: gallery, spots: spots)
        let model = PhotoMapViewModel()
        await model.load(environment: environment)
        await model.awaitIndex()
        return (model, environment)
    }

    /// 同じ入力で何度呼んでも計算は1回・入力が変われば計算し直す・結果は従来の `rows` と同じ
    @MainActor
    func testComputesOnlyWhenInputsChange() async throws {
        let (model, environment) = await loadedModel()
        XCTAssertEqual(model.spotRowsComputeCount, 0)

        let first = model.spotRows(center: tokyo)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first, OfficialSpotList.rows(model.officialSpots, photos: model.photos, from: tokyo,
                                                    links: model.photoLinks), "従来の計算と違う")
        XCTAssertEqual(first.map(\.spot.slug), ["tokyo-station", "versailles"])
        for _ in 0..<5 { _ = model.spotRows(center: tokyo) }
        XCTAssertEqual(model.spotRowsComputeCount, 1, "同じ入力で計算し直している")

        // 起点
        XCTAssertEqual(model.spotRows(center: paris).map(\.spot.slug), ["versailles", "tokyo-station"])
        XCTAssertEqual(model.spotRowsComputeCount, 2, "起点が変わったのに計算し直していない")
        _ = model.spotRows(center: paris)
        XCTAssertEqual(model.spotRowsComputeCount, 2)

        // query（名前で絞る・従来の絞りと同じ当たり）
        model.query = "東京"
        let filtered = model.spotRows(center: paris)
        XCTAssertEqual(filtered.map(\.spot.slug), ["tokyo-station"])
        XCTAssertEqual(filtered, OfficialSpotList.rows(
            OfficialSpotIndex.matches(model.officialSpots, query: "東京", aliases: model.spotAliases),
            photos: model.photos, from: paris, links: model.photoLinks))
        XCTAssertEqual(model.spotRowsComputeCount, 3, "query が変わったのに計算し直していない")
        _ = model.spotRows(center: paris)
        XCTAssertEqual(model.spotRowsComputeCount, 3)
        model.query = ""
        XCTAssertEqual(model.spotRows(center: paris).count, 2)
        XCTAssertEqual(model.spotRowsComputeCount, 4)

        // photos・officialSpots・photoLinks・spotAliases は読み直し（load）で入れ替わる
        await model.load(environment: environment)
        await model.awaitIndex()
        XCTAssertEqual(model.spotRows(center: paris).count, 2)
        XCTAssertEqual(model.spotRowsComputeCount, 5, "読み直したのに計算し直していない")
        _ = model.spotRows(center: paris)
        XCTAssertEqual(model.spotRowsComputeCount, 5)
    }

    /// 入力5つの変更が、それぞれ番号を上げる（どれかの `didSet` が消えると古い行のまま残る）
    func testEveryInputBumpsTheRevision() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Map/PhotoMapViewModel.swift"), encoding: .utf8)
        for decl in ["private(set) var photos: [Photo] = [] { didSet { spotInputsRevision &+= 1 } }",
                     "private(set) var officialSpots: [OfficialSpot] = [] { didSet { spotInputsRevision &+= 1 } }",
                     "private(set) var photoLinks = SpotPhotoLinks.empty { didSet { spotInputsRevision &+= 1 } }",
                     "private(set) var spotAliases: [String: [String]] = [:] { didSet { spotInputsRevision &+= 1 } }",
                     "@Published var query = \"\" {\n        didSet {\n            spotInputsRevision &+= 1"] {
            XCTAssertTrue(model.contains(decl), "入力の変更で番号を上げていない: \(decl)")
        }
        // 画面の body では計算しない
        let view = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Map/PhotoMapView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("model.spotRows(center: center)"))
        XCTAssertFalse(view.contains("OfficialSpotList.rows("), "body の中で毎回計算している")
    }

    /// 控えの部品: 鍵が同じなら計算しない
    func testCacheReusesForSameKey() {
        var cache = SpotListCache()
        var calls = 0
        let key = SpotListCache.Key(revision: 1, center: nil)
        _ = cache.rows(for: key) { calls += 1; return [] }
        _ = cache.rows(for: key) { calls += 1; return [] }
        XCTAssertEqual(calls, 1)
        _ = cache.rows(for: .init(revision: 2, center: nil)) { calls += 1; return [] }
        _ = cache.rows(for: .init(revision: 2, center: Photo.Coords(lat: 1, lng: 2))) { calls += 1; return [] }
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(cache.computeCount, 3)
    }
}
