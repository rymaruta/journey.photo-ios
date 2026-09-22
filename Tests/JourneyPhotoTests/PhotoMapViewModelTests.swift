import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 撮影地マップの頭。**地図とリストが同じ結果を描くこと**と、
/// 打っている間に通信しないことを縛る。
@MainActor
final class PhotoMapViewModelTests: XCTestCase {

    private let photosJSON = """
    [{"id":"a","src":"https://x/a.jpg","location":"パリ","category":"風景","coords":{"lat":48.85,"lng":2.35}},
     {"id":"b","src":"https://x/b.jpg","location":"パリ, フランス","category":"建築","coords":{"lat":48.85,"lng":2.35}},
     {"id":"c","src":"https://x/c.jpg","location":"東京","category":"街","coords":{"lat":35.68,"lng":139.76}},
     {"id":"d","src":"https://x/d.jpg","location":"東京","category":"動物"},
     {"id":"e","src":"https://x/e.jpg","spotId":"sp_a1","category":"landscape","coords":{"lat":34.14,"lng":133.68}}]
    """

    private let spotsJSON = """
    [{"spotId":"sp_a1","slug":"takaya-jinja","name":"高屋神社","aliases":["天空の鳥居"],
      "coords":{"lat":34.14,"lng":133.68}}]
    """

    /// 通信は `URLProtocol` で差し替える（写真 → 台帳の順に返す）
    private func environment() -> AppEnvironment {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        StubProtocol.reset()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
        StubProtocol.respondInOrder([(status: 200, body: photosJSON), (status: 200, body: spotsJSON)])
        let gallery = PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: session,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        )
        let spots = SpotService(url: URL(string: "https://site.example.test/app/data/spots.json")!,
                                session: session)
        return AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: gallery, spots: spots)
    }

    private func loaded() async -> PhotoMapViewModel {
        let model = PhotoMapViewModel()
        await model.load(environment: environment())
        return model
    }

    /// 地図を動かしただけでは絞らない。**ボタンを押したときだけ**
    func testAreaFilterAppliesOnlyWhenAsked() async {
        let model = await loaded()
        XCTAssertEqual(model.shown.map(\.id), ["a", "b", "c", "e"])

        model.update(visible: MapFraming.Frame(latitude: 48.85, longitude: 2.35,
                                               latitudeSpan: 0.2, longitudeSpan: 0.2))
        XCTAssertEqual(model.shown.count, 4)
        XCTAssertNil(model.areaFrame)

        model.applyArea()
        XCTAssertEqual(model.shown.map(\.id), ["a", "b"])
        XCTAssertTrue(model.isFiltering)

        model.clearArea()
        XCTAssertEqual(model.shown.count, 4)
        XCTAssertFalse(model.isFiltering)
    }

    /// 範囲が届いていないうちに押しても何も変わらない（嘘の絞りを作らない）
    func testApplyAreaWithoutVisibleFrameIsNoop() async {
        let model = await loaded()
        model.applyArea()
        XCTAssertNil(model.areaFrame)
        XCTAssertEqual(model.shown.count, 4)
    }

    /// 「地図 / リスト」は同じ結果。行の枚数は数えた値
    func testPinsAndRowsComeFromTheSameFilteredSet() async {
        let model = await loaded()
        model.query = "パリ"
        XCTAssertEqual(model.pins.count, MapPin.group(model.shown).count)
        XCTAssertEqual(model.pins.count, 1)
        XCTAssertEqual(model.pins.first?.photos.count, 2)
        XCTAssertEqual(model.pins.flatMap(\.photos).count, model.shown.count)

        model.query = ""
        model.select(category: "風景")
        // `landscape` で保存された e も同じ分類
        XCTAssertEqual(model.shown.map(\.id), ["a", "e"])
        XCTAssertEqual(model.pins.count, 2)
        XCTAssertEqual(model.pins.flatMap(\.photos).count, model.shown.count)
    }

    /// 台帳の名前でも絞れ、札のスポット導線は台帳にあるものだけ
    func testSpotNameFiltersAndCardLinksOnlyLedgerSpots() async {
        let model = await loaded()
        model.query = "天空の鳥居"
        XCTAssertEqual(model.shown.map(\.id), ["e"])
        guard let pin = model.pins.first else { return XCTFail("ピンが無い") }
        XCTAssertEqual(model.spots(for: pin).map(\.spotId), ["sp_a1"])

        model.query = "パリ"
        guard let paris = model.pins.first else { return XCTFail("ピンが無い") }
        XCTAssertTrue(model.spots(for: paris).isEmpty)
    }

    /// 座標の無い写真だけが持つ種類（動物）はチップに出ない。並びは `all` の順
    func testCategoriesOnlyThoseWithCoordinates() async {
        let model = await loaded()
        XCTAssertEqual(model.categories, ["風景", "建築", "街"])
    }

    /// 押し直すと外れる
    func testCategoryChipTogglesOff() async {
        let model = await loaded()
        model.select(category: "建築")
        XCTAssertEqual(model.category, "建築")
        XCTAssertEqual(model.shown.map(\.id), ["b"])
        model.select(category: "建築")
        XCTAssertNil(model.category)
        XCTAssertEqual(model.shown.count, 4)
        model.select(category: "街")
        model.select(category: nil)
        XCTAssertNil(model.category)
    }

    /// 打ちながら絞るのは手元の配列だけ。**通信しない**
    func testSearchDoesNotHitTheNetwork() async {
        let model = await loaded()
        let before = StubProtocol.requestCount
        XCTAssertGreaterThan(before, 0)
        model.query = "パ"
        model.query = "パリ"
        model.query = "東京"
        model.select(category: "街")
        model.applyArea()
        _ = model.shown
        _ = model.pins
        XCTAssertEqual(StubProtocol.requestCount, before)
    }

    /// 台帳が取れなくても写真は出る（導線が無いだけ）
    func testLoadsPhotosEvenWhenLedgerFails() async {
        let model = PhotoMapViewModel()
        let env = environment()
        StubProtocol.respondInOrder([(status: 200, body: photosJSON), (status: 500, body: "")])
        await model.load(environment: env)
        XCTAssertEqual(model.shown.count, 4)
        XCTAssertTrue(model.spots.isEmpty)
        XCTAssertTrue(model.loaded)
    }
}
