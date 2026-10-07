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
    /// `indexGate` を渡すと、索引の要求をその手前で止める（索引が遅い回）
    private func environment(spots: String? = nil, aliases: String? = nil, indexGate: Gate? = nil) -> AppEnvironment {
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
            StubProtocol.respond(path: "/app/data/spots.json", status: 200, body: spots)
        }
        if let aliases {
            StubProtocol.respond(path: "/app/data/spot-search.json", status: 200, body: aliases)
        }
        let gallery = PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: session,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        )
        let index = OfficialSpotService(
            url: URL(string: "https://site.example.test/app/data/spots.json")!,
            session: session,
            snapshot: SpotSnapshotStore(fileName: UUID().uuidString),
            beforeRequest: indexGate.map { gate in { @Sendable () async in await gate.wait() } }
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

    /// 欄に打っている間は**1字ごとに絞り直さない**。止まってから1回だけ絞る
    /// （docs/QUALITY_2026-10-03.md の P2・`typedQuery`）
    func testTypingIsDebouncedBeforeFiltering() async {
        let model = await loaded()
        model.queryDebounce = .seconds(60)
        let before = model.refreshCount
        model.typedQuery = "パ"
        model.typedQuery = "パリ"
        model.typedQuery = "パリ,"
        model.typedQuery = "パリ"
        // 打っている途中は、絞りもピンも前のまま
        XCTAssertEqual(model.refreshCount, before)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.shown.count, 4)

        // 止まったら1回だけ絞る（待ちを短くして、最後の字で写す）
        model.queryDebounce = .milliseconds(20)
        model.typedQuery = "パリ,"
        model.typedQuery = "パリ"
        await model.awaitTypedQuery()
        XCTAssertEqual(model.query, "パリ")
        XCTAssertEqual(model.shown.map(\.id), ["a", "b"])
        XCTAssertEqual(model.refreshCount, before + 1)
    }

    /// 確定（return）と × は**待たずに**効く。打ち止めの待ちが後から古い字で上書きしない
    func testSubmitAndClearApplyImmediately() async {
        let model = await loaded()
        model.queryDebounce = .seconds(60)
        model.typedQuery = "東京"
        model.commitTypedQuery()
        XCTAssertEqual(model.query, "東京")
        XCTAssertEqual(model.shown.map(\.id), ["c"])

        // 打ちかけ（待ち中）に × を押す → その場で空に戻り、欄も空
        model.typedQuery = "パリ"
        model.query = ""
        XCTAssertEqual(model.typedQuery, "")
        XCTAssertEqual(model.shown.count, 4)
        model.queryDebounce = .zero
        await model.awaitTypedQuery()
        XCTAssertEqual(model.query, "")

        // 探すから語を入れた回も、欄の字がそろう
        model.query = "パリ"
        XCTAssertEqual(model.typedQuery, "パリ")
        XCTAssertEqual(model.shown.count, 2)
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

    /// 🔴 **札から開いた画面を積んでいる間は、地図が動いても札を下げない（M-10）。**
    /// 札の「スポットを見る」は `NavigationLink` なので、裏で遅れて届いた現在地などで
    /// 地図が動いてピンが外れると、札ごと消えて開いている画面が閉じていた
    func testOfficialCardStaysWhileSpotIsOpen() async {
        let model = await loaded(spots: spotsJSON)
        model.update(visible: narrow())
        guard let takaya = model.officialPins.first(where: { $0.slug == "takaya-jinja" }) else {
            return XCTFail("高屋神社のピンが出ていない")
        }
        XCTAssertTrue(model.showsCard(official: takaya, onScreen: true))
        // 裏で地図が網走へ動いた（高屋神社のピンは外れる）
        model.update(visible: narrow(lat: 44.02, lng: 144.28))
        XCTAssertFalse(model.stillShown(official: takaya))
        XCTAssertTrue(model.showsCard(official: takaya, onScreen: false), "積んでいる間に札を下げている")
        // 戻ってきたら、いま出ているピンのぶんだけ
        XCTAssertFalse(model.showsCard(official: takaya, onScreen: true))
        XCTAssertFalse(model.showsCard(official: nil, onScreen: false))
    }

    /// 🔴 **カテゴリで絞っている間は撮影スポットのピンを置かない**（Web の `filterMapSpots` と同じ）。
    /// チップは写真の分類で、スポットには対応が無い。以前は写真のピンだけ絞れ、スポットのピンは全部残った
    func testCategoryHidesOfficialPins() async {
        let model = await loaded(spots: spotsJSON)
        model.update(visible: narrow())
        XCTAssertEqual(model.officialPins.map(\.slug), ["takaya-jinja", "kotohira"], "下ごしらえ: 寄せると出る")

        model.select(category: "landscape")
        XCTAssertEqual(model.shown.map(\.id), ["a", "e"], "写真のピンはカテゴリで絞る（風景と landscape は同じ鍵）")
        XCTAssertTrue(model.officialPins.isEmpty, "カテゴリで絞っているのにスポットのピンが残っている")
        // 地図を動かしても、名前で当てても置かない
        model.update(visible: narrow(lat: 34.141, lng: 133.681))
        XCTAssertTrue(model.officialPins.isEmpty, "地図を動かしたらスポットのピンが戻った")
        model.query = "たかや"
        XCTAssertTrue(model.officialPins.isEmpty, "語で当たったスポットはカテゴリを無視して出ている")

        // 「すべて」に戻すと出る
        model.query = ""
        model.select(category: nil)
        XCTAssertEqual(model.officialPins.map(\.slug), ["takaya-jinja", "kotohira"])
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

    /// 🔴 **別名でも当てる（「さがす」と同じ当て方）。** 「さがす」で別名に当たったスポットを
    /// 地図へ持ってくると、地図は名前・読み・地域だけで当てていて「見つかりませんでした」になった
    func testQueryMatchesSpotAliasesLikeSearch() async {
        let model = PhotoMapViewModel()
        // 語は先に入っている（「さがす」から持ってきた回）。別名が届いた時点で数え直す
        model.query = "天空の鳥居"
        await model.load(environment: environment(
            spots: spotsJSON, aliases: #"[{"s":"takaya-jinja","n":"高屋神社","a":["天空の鳥居"]}]"#))
        await model.awaitIndex()
        XCTAssertEqual(model.officialPins.map(\.slug), ["takaya-jinja"])
        XCTAssertFalse(model.hasNothingToShow, "別名で当たるのに「見つかりませんでした」")
    }

    /// 🔴 **別名を取り終えた印が立った時点で、別名のピンがもう出ている。** 印より先に
    /// 「当たらなかった」と決めると、探すから別名だけで当たる語が来た回に語への寄せが下りていた
    func testAliasesSettledOnlyAfterAliasPinsAreIn() async {
        let model = PhotoMapViewModel()
        model.query = "天空の鳥居"
        let loading = Task { await model.load(environment: environment(
            spots: spotsJSON, aliases: #"[{"s":"takaya-jinja","n":"高屋神社","a":["天空の鳥居"]}]"#)) }
        var spins = 0
        while !model.aliasesSettled && spins < 100_000 { spins += 1; await Task.yield() }
        XCTAssertTrue(model.aliasesSettled, "別名を取り終えた印が立たない")
        XCTAssertEqual(model.officialPins.map(\.slug), ["takaya-jinja"],
                       "取り終えたと知らせたのに、別名のピンがまだ無い（寄せが下りる）")
        await loading.value
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

    /// **枠は描き直しのたびに計算しない**（run 206 の調べ）。画面は描くたびに `frame` を読み、
    /// 塊の計算は地点が世界に数百あると Debug で1回 60ms ほどかかる。材料が変わったときだけ計算し直す
    func testFrameIsComputedOnlyWhenPinsChange() async throws {
        let model = await loaded(spots: spotsJSON)
        let first = model.frame
        let computed = model.frameComputations
        for _ in 0..<5 { XCTAssertEqual(model.frame, first) }
        XCTAssertEqual(model.frameComputations, computed, "同じピンのまま読み直すたびに計算した")

        model.query = "パリ"
        let paris = try XCTUnwrap(model.frame)
        XCTAssertEqual(paris.latitude, 48.85, accuracy: 0.01, "絞ったら新しいピンで計算し直す")
        XCTAssertEqual(model.frameComputations, computed + 1)
        model.query = "たかや"
        XCTAssertEqual(model.frame?.latitude ?? 0, 34.14, accuracy: 0.01, "スポットだけ当たった回も古い枠を返さない")
    }

    /// **地図を動かしてスポットが入れ替わっても、写真の枠は計算し直さない**（67f4f26 のレビュー）。
    /// 検索語が空の間、枠はスポットを使わない
    func testMovingTheMapDoesNotRecomputeThePhotoFrame() async {
        let model = await loaded(spots: spotsJSON)
        let first = model.frame
        let computed = model.frameComputations
        model.update(visible: narrow())
        XCTAssertFalse(model.officialPins.isEmpty, "下ごしらえ: 寄せるとスポットのピンが入れ替わる")
        XCTAssertEqual(model.frame, first)
        XCTAssertEqual(model.frameComputations, computed, "スポットが入れ替わるたびに写真の枠を計算し直した")
    }

    /// **索引が届く前に打った検索語でも、届いたらスポットの枠に寄る**（67f4f26 のレビュー）。
    /// 覚えた「枠なし」を、スポットが届いたときに捨てる
    func testSpotFrameFollowsAnIndexThatArrivesLate() async {
        let model = PhotoMapViewModel()
        let gate = Gate()
        await model.load(environment: environment(spots: spotsJSON, indexGate: gate))
        model.query = "たかや"
        XCTAssertNil(model.frame, "下ごしらえ: 索引が届く前は当たるものが無い")
        await gate.open()
        await model.awaitIndex()
        XCTAssertEqual(model.frame?.latitude ?? 0, 34.14, accuracy: 0.01, "届いたスポットに寄らない")
    }

    /// 🔴 **写真は索引を待たない。** 索引が届かない間も写真が届いた時点で
    /// `loaded` になり、索引はあとから届いてピンだけ入れ替わる。
    /// 直列に待つと、写真のピンと最初の寄せが最大20秒（通信の上限）遅れる
    func testPhotosDoNotWaitForTheIndex() async throws {
        let model = PhotoMapViewModel()
        let gate = Gate()
        let env = environment(spots: spotsJSON, indexGate: gate)
        let loading = Task { await model.load(environment: env) }
        var waited = 0.0
        while !model.loaded && waited < 0.5 {
            try await Task.sleep(nanoseconds: 50_000_000)
            waited += 0.05
        }
        XCTAssertTrue(model.loaded, "索引を待ってから写真を出している（\(waited)秒待った）")
        XCTAssertEqual(model.shown.count, 4)
        XCTAssertTrue(model.officialSpots.isEmpty, "索引はまだ届いていないはず")

        // 索引を放す（写真が索引を待つ作りだと、ここまで load が返らない）
        await gate.open()
        await loading.value
        await model.awaitIndex()
        model.update(visible: narrow())
        XCTAssertEqual(model.officialPins.map(\.slug), ["takaya-jinja", "kotohira"])
    }

    /// 🔴 **「もう一度試す」を続けて押しても、古い回の答えで新しい回を上書きしない**
    /// （2026-10-02 のレビュー: 前の回の索引を取り消さずに作り直していた）
    func testOlderLoadDoesNotOverwriteNewerOne() async throws {
        let model = PhotoMapViewModel()
        let gate = Gate()
        // 1回目: 索引の手前で止める
        await model.load(environment: environment(spots: spotsJSON, indexGate: gate))
        await gate.untilWaiting(1)
        // 2回目: すぐ届く（3件）
        await model.load(environment: environment(spots: spotsJSON))
        await model.awaitIndex()
        XCTAssertEqual(model.officialSpots.count, 3)
        XCTAssertFalse(model.isLoading)
        // 1回目が遅れて別の答え（1件）を受け取っても書かない（道は先に足した方が勝つので消してから）
        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/spots.json", status: 200, body: """
        [{"spotId":"sp_c3","slug":"abashiri-ryuhyo","name":"網走の流氷","coords":{"lat":44.02,"lng":144.28},"stage":"review"}]
        """)
        await gate.open()
        for _ in 0..<40 {
            await Task.yield()
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(model.officialSpots.count, 3, "古い回の索引が新しい回を上書きした")
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
        XCTAssertNotNil(PhotoMapViewModel.refreshed(tokyo, in: model.pins))

        model.query = "パリ"
        XCTAssertNil(PhotoMapViewModel.refreshed(tokyo, in: model.pins))
        // 残っている方の札は出したまま
        XCTAssertNotNil(PhotoMapViewModel.refreshed(model.pins.first, in: model.pins))
    }

    func testNilIsNeverShown() async {
        let model = await loaded()
        XCTAssertNil(PhotoMapViewModel.refreshed(nil, in: model.pins))
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

/// 地図の文字（B8・B12）。アプリは日本語固定（`AppLanguageTests`）なので
/// 英語の単数形はここでは動かせない——日本語の出方と読み上げ名だけ確かめる
final class PhotoMapTextTests: XCTestCase {
    func testCounts() {
        XCTAssertEqual(PhotoMapViewModel.photoCountLabel(1), "1枚")
        XCTAssertEqual(PhotoMapViewModel.nearbyCountLabel(3), "この周辺の写真 3枚")
    }

    /// B12: 範囲の帯は枚数・地点数の関数を通す（英語の単数形「1 place」はその関数が持つ）
    func testAreaCountLabel() {
        XCTAssertEqual(PhotoMapViewModel.placeCountLabel(1), "1地点")
        XCTAssertEqual(PhotoMapViewModel.areaCountLabel(photos: 3, places: 1), "この範囲の写真 3枚・1地点")
    }

    /// 写真のピンは撮影地と枚数を読み上げる。撮影地が無ければ札と同じ語
    func testPinSpokenLabel() {
        XCTAssertEqual(PhotoMapViewModel.pinSpokenLabel(place: "パリ", count: 3), "パリ、写真 3枚")
        XCTAssertEqual(PhotoMapViewModel.pinSpokenLabel(place: nil, count: 1), "場所の名前なし、写真 1枚")
        XCTAssertEqual(PhotoMapViewModel.pinSpokenLabel(place: " ", count: 1), "場所の名前なし、写真 1枚")
    }
}
