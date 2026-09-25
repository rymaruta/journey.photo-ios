import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 撮影スポットの索引（`app/data/spots.json`）の読み込み。
///
/// **写真の一覧（`PublicGalleryService`）と同じ4段**——控え → 通信 →
/// 圏外なら前回のぶん → 読めなければ前回のぶん。違いは1つ、
/// **取れなくても写真の機能を止めない**こと（呼ぶ側が `try?` で受ける）。
final class OfficialSpotServiceTests: XCTestCase {

    private var session: URLSession!
    private let url = URL(string: "https://site.example.test/app/data/spots.json")!

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
        StubProtocol.reset()
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    private func service(snapshot: String = UUID().uuidString) -> OfficialSpotService {
        OfficialSpotService(url: url, session: session, snapshot: SpotSnapshotStore(fileName: snapshot))
    }

    /// Web が配る索引の形（`content/spots.json` → `app/data/spots.json`）。
    /// **知らない項目（`extra`）は無視される**ことも、ここで一緒に見る
    static let threeSpots = """
    [{"spotId":"sp_391f85dded70","slug":"abashiri-ryuhyo","name":"網走の流氷","nameEn":"Drift Ice of Abashiri",
      "reading":"あばしりのりゅうひょう","region":{"prefecture":"北海道","city":"網走市"},
      "coords":{"lat":44.02,"lng":144.28},"category":"自然現象","summary":"オホーツク海を埋める流氷。",
      "stage":"review","draftedAt":"2026-09-24","extra":{"ignored":true}},
     {"spotId":"sp_7b2c9d1e0f34","slug":"takaya-jinja","name":"高屋神社","reading":"たかやじんじゃ",
      "region":{"prefecture":"香川県","city":"観音寺市"},"coords":{"lat":34.14,"lng":133.68},
      "stage":"published","verifiedAt":"2026-10-01"},
     {"spotId":"sp_000000000001","slug":"no-coords","name":"座標なし","stage":"review"}]
    """

    func testReadsTheIndex() async throws {
        StubProtocol.respond(status: 200, body: Self.threeSpots)
        let spots = try await service().fetchIndex()
        XCTAssertEqual(spots.map(\.slug), ["abashiri-ryuhyo", "takaya-jinja", "no-coords"])
        XCTAssertEqual(spots[0].region?.prefecture, "北海道")
        XCTAssertEqual(spots[0].coords, Photo.Coords(lat: 44.02, lng: 144.28))
        XCTAssertTrue(spots[0].isDraft, "review は下書き")
        XCTAssertFalse(spots[1].isDraft, "published だけが下書きでない")
        XCTAssertNil(spots[2].coords)
    }

    /// **1件の型違いで索引が丸ごと消えない**（`LenientPhotoList` と同じ判断）
    func testDropsOnlyTheBadItem() async throws {
        StubProtocol.respond(status: 200, body: """
        [{"spotId":"sp_1","slug":"a","name":"A","stage":"review"},
         {"spotId":"sp_2","slug":123,"name":"B","stage":"review"},
         {"spotId":"sp_3","slug":"c","name":"C","stage":"review"}]
        """)
        let spots = try await service().fetchIndex()
        XCTAssertEqual(spots.map(\.slug), ["a", "c"])
    }

    /// **圏外なら前回のぶんを出す。**
    func testFallsBackToSnapshotWhenOffline() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: Self.threeSpots)
        _ = try await service(snapshot: name).fetchIndex()

        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await service(snapshot: name).fetchIndex()
        XCTAssertEqual(offline.count, 3)
    }

    /// **控えが無くて圏外なら投げる**（呼ぶ側が `try?` で空にする）
    func testThrowsWhenOfflineWithoutSnapshot() async {
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        do {
            _ = try await service().fetchIndex()
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual(error as? APIError, .unreachable)
        }
    }

    /// **5xx は控えに落ちる**（サーバーの都合。索引が消えたわけではない）。
    /// 控えが無ければ投げる（写真の機能は呼ぶ側で守る——`PhotoMapViewModelTests`）
    func testServerErrorFallsBackToSnapshotOrThrows() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 500, body: "oops")
        do {
            _ = try await service(snapshot: name).fetchIndex()
            XCTFail("控えが無いのに投げていない")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 500, message: ""))
        }

        StubProtocol.respond(status: 200, body: Self.threeSpots)
        _ = try await service(snapshot: name).fetchIndex()
        StubProtocol.respond(status: 500, body: "oops")
        let after = try await service(snapshot: name).fetchIndex()
        XCTAssertEqual(after.count, 3, "500 で控えに落ちていない")
    }

    /// 🔴 **404 は「索引を下げた」。** 古い控えを出し続けない——空を返して
    /// 控えも消す（本番は Web が main に入るまでこの姿。何も出ないだけ）
    func testNotFoundMeansTheIndexIsGone() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: Self.threeSpots)
        _ = try await service(snapshot: name).fetchIndex()

        StubProtocol.respond(status: 404, body: "not found")
        let gone = try await service(snapshot: name).fetchIndex()
        XCTAssertTrue(gone.isEmpty, "下げた索引を控えから出している")

        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        do {
            _ = try await service(snapshot: name).fetchIndex()
            XCTFail("404 のあとも控えが残っている")
        } catch {
            XCTAssertEqual(error as? APIError, .unreachable)
        }
    }

    /// **200 の HTML を控えない。** キャプティブポータル（ホテルの Wi-Fi）は
    /// 画像にも JSON にも 200 でログイン画面を返す。控えると圏外でそれが出る。
    /// `content-type` が `text/html` の回は**読もうとする前に**退ける
    func testDoesNotSnapshotHtmlEvenWhenItIsJsonShaped() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: Self.threeSpots)
        _ = try await service(snapshot: name).fetchIndex()

        // 中身は配列として読めてしまう形。種別だけが HTML
        StubProtocol.respond(status: 200, body: "[]", contentType: "text/html; charset=utf-8")
        let portal = try await service(snapshot: name).fetchIndex()
        XCTAssertEqual(portal.count, 3, "HTML の応答が控えを潰した")

        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await service(snapshot: name).fetchIndex()
        XCTAssertEqual(offline.count, 3)
    }

    /// 種別が無くても、配列として読めなければ控えない
    func testDoesNotSnapshotUnreadableBody() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: Self.threeSpots)
        _ = try await service(snapshot: name).fetchIndex()

        StubProtocol.respond(status: 200, body: "<html>Wi-Fi にログインしてください</html>")
        let garbage = try await service(snapshot: name).fetchIndex()
        XCTAssertEqual(garbage.count, 3)
    }

    /// 60秒以内の2回目は落とし直さない。**引き下げ（force）は取り直す**
    func testSecondReadUsesTheCacheUnlessForced() async throws {
        StubProtocol.respond(status: 200, body: Self.threeSpots)
        let spots = service()
        _ = try await spots.fetchIndex()
        let after = StubProtocol.requestCount
        _ = try await spots.fetchIndex()
        XCTAssertEqual(StubProtocol.requestCount, after, "控えがあるのに落とし直している")
        _ = try await spots.fetchIndex(force: true)
        XCTAssertEqual(StubProtocol.requestCount, after + 1, "引き下げても取り直していない")
    }

    /// **写真の一覧とは別の口。** 道で叩き分けても、それぞれ自分のぶんを読む
    func testHitsItsOwnPathNotThePhotos() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200,
                             body: #"[{"id":"a","src":"https://x/a.jpg"}]"#)
        StubProtocol.respond(path: "/app/data/spots.json", status: 200, body: Self.threeSpots)
        let spots = try await service().fetchIndex()
        XCTAssertEqual(spots.count, 3)
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/app/data/spots.json")
    }
}
