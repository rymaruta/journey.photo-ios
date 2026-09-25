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

    /// 撮影スポットの索引（`app/data/spots.json`）。2件は写真 e の座標のすぐそば
    private let spotsJSON = """
    [{"spotId":"sp_a1","slug":"takaya-jinja","name":"高屋神社","reading":"たかやじんじゃ",
      "region":{"prefecture":"香川県","city":"観音寺市"},"coords":{"lat":34.14,"lng":133.68},"stage":"review","draftedAt":"2026-09-24"},
     {"spotId":"sp_b2","slug":"kotohira","name":"金刀比羅宮","coords":{"lat":34.18,"lng":133.81},"stage":"review"},
     {"spotId":"sp_c3","slug":"abashiri-ryuhyo","name":"網走の流氷","coords":{"lat":44.02,"lng":144.28},"stage":"review"}]
    """

    /// 通信は `URLProtocol` で差し替える。**写真と索引は別の口**なので道で
    /// 叩き分ける。`spots` が nil なら索引の口は 404（本番の今の姿）。
    /// `indexDelay` は索引の応答を遅らせる秒数
    private func environment(spots: String? = nil, indexDelay: TimeInterval = 0) -> AppEnvironment {
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
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: photosJSON)
        if let spots {
            StubProtocol.respond(path: "/app/data/spots.json", status: 200, body: spots, delay: indexDelay)
        }
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
        return AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: gallery, spots: index)
    }

    /// 写真も索引も届いた状態（索引は写真と並行に来るので、両方待つ）
    private func loaded(spots: String? = nil) async -> PhotoMapViewModel {
        let model = PhotoMapViewModel()
        await model.load(environment: environment(spots: spots))
        await model.awaitIndex()
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
    func testLoadsPhotos() async {
        let model = PhotoMapViewModel()
        let env = environment()
        await model.load(environment: env)
        XCTAssertEqual(model.shown.count, 4)
        XCTAssertTrue(model.loaded)
    }
}

// MARK: - 撮影スポットのピン

extension PhotoMapViewModelTests {

    /// 寄せた枠（幅 0.3° ≈ 33km・線の 0.5° より狭い）。既定の中心は高屋神社で、
    /// 金刀比羅宮（経度 +0.13°）が枠に入り、網走は入らない
    private func narrow(lat: Double = 34.14, lng: Double = 133.68) -> MapFraming.Frame {
        MapFraming.Frame(latitude: lat, longitude: lng, latitudeSpan: 0.3, longitudeSpan: 0.3)
    }

    /// 引いているうちは出ない。**寄せたら枠の中だけ**出る
    func testOfficialPinsAppearOnlyWhenZoomedIn() async {
        let model = await loaded(spots: spotsJSON)
        XCTAssertTrue(model.officialPins.isEmpty, "枠が届く前に置いている")

        model.update(visible: MapFraming.Frame(latitude: 36, longitude: 138, latitudeSpan: 12, longitudeSpan: 12))
        XCTAssertTrue(model.officialPins.isEmpty, "日本全体の倍率で置いている")

        model.update(visible: narrow())
        XCTAssertEqual(model.officialPins.map(\.slug), ["takaya-jinja", "kotohira"])
        // 写真のピンは今までどおり
        XCTAssertEqual(model.shown.count, 4)
    }

    /// **同じ枠で2回届いても入れ替えない。** 入れ替えるたびに描き直し →
    /// カメラの知らせ → … と回るのが run 37 の固まり方
    func testSameFrameDoesNotRepublishOfficialPins() async {
        let model = await loaded(spots: spotsJSON)
        model.update(visible: narrow())
        let after = model.officialPinsUpdates
        XCTAssertGreaterThan(after, 0)
        model.update(visible: narrow())
        model.update(visible: narrow(lat: 34.141, lng: 133.681))
        XCTAssertEqual(model.officialPinsUpdates, after, "同じ集まりなのに入れ替えている")
    }

    /// **索引が 404 でも写真のピンは出る**（本番は Web が main に入るまでこの姿）
    func testPhotoPinsSurviveAMissingIndex() async {
        let model = await loaded(spots: nil)
        model.update(visible: narrow())
        XCTAssertTrue(model.loaded)
        XCTAssertEqual(model.shown.count, 4)
        XCTAssertFalse(model.pins.isEmpty)
        XCTAssertTrue(model.officialPins.isEmpty)
    }

    /// 「このエリアを検索」のあとは**押したときの枠**で数える（写真と同じ）
    func testAppliedAreaDrivesOfficialPins() async {
        let model = await loaded(spots: spotsJSON)
        model.update(visible: narrow())
        model.applyArea()
        // 地図を網走へ動かしても、固定した範囲のぶんが出たまま
        model.update(visible: narrow(lat: 44.02, lng: 144.28))
        XCTAssertEqual(model.officialPins.map(\.slug), ["takaya-jinja", "kotohira"])
        model.clearArea()
        XCTAssertEqual(model.officialPins.map(\.slug), ["abashiri-ryuhyo"])
    }

    /// 名前で絞っているときは倍率に関係なく当たったものが出る（owner が名前で探す入口）
    func testQueryShowsMatchingSpotsRegardlessOfZoom() async {
        let model = await loaded(spots: spotsJSON)
        model.query = "たかや"
        XCTAssertEqual(model.officialPins.map(\.slug), ["takaya-jinja"])
        model.query = ""
        XCTAssertTrue(model.officialPins.isEmpty)
        XCTAssertTrue(model.stillShown(official: nil) == false)
    }

    /// 🔴 **名前で絞ってスポットだけ当たった回に「見つかりませんでした」と言わない。**
    /// 帯は写真もスポットも無いときだけ
    func testNoResultsOnlyWhenNeitherPhotosNorSpotsMatch() async {
        let model = await loaded(spots: spotsJSON)
        XCTAssertFalse(model.hasNothingToShow)
        model.query = "たかや"
        XCTAssertTrue(model.shown.isEmpty, "下ごしらえ: 写真は当たらない")
        XCTAssertFalse(model.hasNothingToShow, "スポットが出ているのに「見つかりませんでした」")
        model.query = "どこにもない場所"
        XCTAssertTrue(model.hasNothingToShow)
    }

    /// 🔴 **名前で当たったスポットへ寄せる。** 写真が当たらずスポットだけ
    /// 当たった回は、その座標群から枠を作る（写真が当たれば今までどおり写真の枠）
    func testFrameFallsBackToMatchingSpots() async throws {
        let model = await loaded(spots: spotsJSON)
        model.query = "たかや"
        let frame = try XCTUnwrap(model.frame, "スポットだけ当たった回に枠が無い")
        XCTAssertEqual(frame.latitude, 34.14, accuracy: 0.01)
        XCTAssertEqual(frame.longitude, 133.68, accuracy: 0.01)

        model.query = "パリ"
        let paris = try XCTUnwrap(model.frame)
        XCTAssertEqual(paris.latitude, 48.85, accuracy: 0.01, "写真が当たる回は写真の枠")

        model.query = "どこにもない場所"
        XCTAssertNil(model.frame)
    }

    /// 🔴 **写真は索引を待たない。** 索引が遅い回（1秒）でも写真が届いた時点で
    /// `loaded` になり、索引はあとから届いてピンだけ入れ替わる。
    /// 直列に待つと、写真のピンと最初の寄せが最大20秒（通信の上限）遅れる
    func testPhotosDoNotWaitForTheIndex() async throws {
        let model = PhotoMapViewModel()
        let env = environment(spots: spotsJSON, indexDelay: 1.0)
        let loading = Task { await model.load(environment: env) }
        var waited = 0.0
        while !model.loaded && waited < 0.5 {
            try await Task.sleep(nanoseconds: 50_000_000)
            waited += 0.05
        }
        XCTAssertTrue(model.loaded, "索引を待ってから写真を出している（\(waited)秒待った）")
        XCTAssertEqual(model.shown.count, 4)
        XCTAssertTrue(model.officialSpots.isEmpty, "索引はまだ届いていないはず")

        await loading.value
        await model.awaitIndex()
        model.update(visible: narrow())
        XCTAssertEqual(model.officialPins.map(\.slug), ["takaya-jinja", "kotohira"])
    }

    /// 札は**いま出ているピンのぶんだけ**（写真の札と同じ約束）
    func testOfficialCardFollowsThePins() async throws {
        let model = await loaded(spots: spotsJSON)
        model.update(visible: narrow())
        let pin = try XCTUnwrap(model.officialPins.first)
        XCTAssertTrue(model.stillShown(official: pin))
        XCTAssertEqual(model.officialSpot(for: pin)?.name, "高屋神社")
        model.update(visible: narrow(lat: 44.02, lng: 144.28))
        XCTAssertFalse(model.stillShown(official: pin))
    }
}

// MARK: - 押した札の始末

extension PhotoMapViewModelTests {

    /// **絞り込みで消えたピンの札は出さない。**
    /// 札は値の写しなので、消えても無関係な地図の上に浮いたまま残っていた
    func testDropsTheCardWhenItsPinIsFilteredOut() async throws {
        let model = await loaded()
        let tokyo = try XCTUnwrap(model.pins.first { $0.photos.contains { $0.id == "c" } })
        XCTAssertTrue(model.stillShown(tokyo))

        model.query = "パリ"
        XCTAssertFalse(model.stillShown(tokyo))
        // 残っている方の札は出したまま
        XCTAssertTrue(model.stillShown(model.pins.first))
    }

    func testNilIsNeverShown() async {
        let model = await loaded()
        XCTAssertFalse(model.stillShown(nil))
    }
}

// MARK: - 地図を動かしたときの静けさ

extension PhotoMapViewModelTests {

    /// **地図を動かしても結果は入れ替わらない。**
    ///
    /// 見えている範囲で絞るのは「このエリアを検索」を押したときだけ。
    /// ここが動くと、地図を動かすたびに絞り直し → 描き直し →
    /// またカメラの知らせ、と回り続ける（実機で固まった形）。
    func testMovingTheMapDoesNotChangeTheResult() async {
        let model = await loaded()
        let before = model.shown.map(\.id)
        for i in 0..<5 {
            model.update(visible: MapFraming.Frame(latitude: 35.0 + Double(i), longitude: 139.0,
                                                   latitudeSpan: 0.2, longitudeSpan: 0.2))
        }
        XCTAssertEqual(model.shown.map(\.id), before)
        XCTAssertNil(model.areaFrame)
    }

    /// 「このエリアを検索」は**押せるようになったら、それきり**
    /// （動かすたびに知らせを出さないための形）
    func testCanSearchAreaFlipsOnce() async {
        let model = await loaded()
        XCTAssertFalse(model.canSearchArea)
        model.update(visible: MapFraming.Frame(latitude: 35.0, longitude: 139.0,
                                               latitudeSpan: 0.2, longitudeSpan: 0.2))
        XCTAssertTrue(model.canSearchArea)
        model.update(visible: MapFraming.Frame(latitude: 36.0, longitude: 140.0,
                                               latitudeSpan: 0.2, longitudeSpan: 0.2))
        XCTAssertTrue(model.canSearchArea)
    }
}
