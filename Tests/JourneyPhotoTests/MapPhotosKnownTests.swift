import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **地図の撮影スポットの行・画面が「写真の数を言ってよいか」**（`PhotoMapViewModel.photosKnown`）を動きで見る
/// （2026-11-11 確かめ役の指摘・main からの穴）。
///
/// 以前は地図の4か所が `SpotScreen.photosKnown(...)` を自分で書いていて、どこかを `true` に固定しても試験が
/// 何も落ちなかった。いまは全部が模型の1つの値を読む。ここでは読み込み前・写真が取れた回・取れなかった回の
/// 3つを実際に読み込んで見て、画面の4か所がその値を渡していることも確かめる
final class MapPhotosKnownTests: XCTestCase {

    private var session: URLSession!
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
        for name in snapshotNames {
            let file = caches.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: file.appendingPathExtension("validator"))
        }
        snapshotNames = []
        StubProtocol.reset()
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    /// 写真の一覧を `status` で返す地図の模型を読み込む
    @MainActor
    private func loadedMap(photosStatus: Int, photosBody: String) async -> PhotoMapViewModel {
        StubProtocol.respond(path: "/app/data/spots.json", status: 200, body: "[]")
        StubProtocol.respond(path: "/app/data/photos.json", status: photosStatus, body: photosBody)
        let legacy = UUID().uuidString
        let photos = UUID().uuidString
        snapshotNames += [legacy, photos]
        let spots = OfficialSpotService(url: URL(string: "https://site.example.test/app/data/spots.json")!,
                                        session: session, snapshot: SpotSnapshotStore(fileName: legacy))
        let gallery = PublicGalleryService(url: URL(string: "https://site.example.test/app/data/photos.json")!,
                                           session: session, snapshot: PhotoSnapshotStore(fileName: photos))
        let environment = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: gallery, spots: spots)
        let model = PhotoMapViewModel()
        await model.load(environment: environment)
        await model.awaitIndex()
        return model
    }

    /// 読み込む前は言わない（「写真 0枚」と言わない）
    @MainActor
    func testNotKnownBeforeLoad() async {
        XCTAssertFalse(PhotoMapViewModel().photosKnown)
    }

    /// 写真が取れた回は言う（0枚でも本当の0）
    @MainActor
    func testKnownAfterPhotosLoad() async {
        let model = await loadedMap(photosStatus: 200, photosBody: "[]")
        XCTAssertTrue(model.loaded)
        XCTAssertFalse(model.loadFailed)
        XCTAssertTrue(model.photosKnown)
    }

    /// 🔴 取れなかった回（手元も空）は言わない
    @MainActor
    func testNotKnownWhenPhotosFailed() async {
        let model = await loadedMap(photosStatus: 500, photosBody: "{}")
        XCTAssertTrue(model.loadFailed, "写真の一覧が失敗になっていない（試験の前提）")
        XCTAssertTrue(model.photos.isEmpty)
        XCTAssertFalse(model.photosKnown)
    }

    /// 地図の4か所（「スポット」の行・リストの行・札の撮影スポット・リストの撮影スポット）は全部この値を渡す。
    /// 画面ごとに式を書き直したり `true` に固定したりしない
    func testMapPassesModelValueEverywhere() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Map/PhotoMapView.swift"),
                              encoding: .utf8)
        let passed = text.components(separatedBy: "photosKnown:").count - 1
        XCTAssertEqual(passed, 4)
        XCTAssertEqual(text.components(separatedBy: "photosKnown: model.photosKnown").count - 1, passed,
                       "地図に模型の値でない photosKnown がある")
    }
}
