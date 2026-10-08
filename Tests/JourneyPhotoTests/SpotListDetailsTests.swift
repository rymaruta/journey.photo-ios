import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **地図の「スポット」「リスト」の札も、出す行の詳細を読む**（分けた置き場・2026-10-08）。
///
/// 詳細の和が予算（`OfficialSpotService.detailPrefetchBudget`）を超えると、索引のあとは全区分を読まない。
/// そのとき詳細を読んでいたのはピン・ホーム・行きたい場所・旅行の札などだけで、地図の一覧の行は
/// 索引だけのまま——丸写真が出ずカメラの印になっていた。ここでは予算0のサービスでその回を作り、
///   1. 一覧に出す行（頭の頁・開いた県）だけを選ぶ
///   2. 読んだら行に写真が入り、鍵が空になって通信が止まる
///   3. 待っている間に変わった行を古い写しで戻さない
/// を見る。
final class SpotListDetailsTests: XCTestCase {

    private var session: URLSession!
    private var prefixes: [String] = []
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
        let names = snapshotNames + prefixes.flatMap { p in ["index", "jp-kanto", "fr"].map { "\(p)-\($0).json" } }
        for name in names {
            let file = caches.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: file.appendingPathExtension("validator"))
        }
        prefixes = []
        snapshotNames = []
        StubProtocol.reset()
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    private func count(_ path: String) -> Int {
        StubProtocol.requests.filter { $0 == "GET \(path)" }.count
    }

    /// 予算0（＝詳細の和が予算を超えた本番と同じ）の地図の模型。索引まで読み終えたもの
    @MainActor
    private func overBudgetMap(beforeShardRequest: (@Sendable () async -> Void)? = nil) async -> PhotoMapViewModel {
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200, body: SpotFeedShardsTests.index())
        StubProtocol.respond(path: "/app/data/spot-feed/jp-kanto.json", status: 200, body: SpotFeedShardsTests.kanto)
        StubProtocol.respond(path: "/app/data/spot-feed/fr.json", status: 200, body: SpotFeedShardsTests.france)
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: "[]")
        let prefix = UUID().uuidString
        prefixes.append(prefix)
        let legacy = UUID().uuidString
        let photos = UUID().uuidString
        snapshotNames += [legacy, photos]
        let spots = OfficialSpotService(url: URL(string: "https://site.example.test/app/data/spots.json")!,
                                        session: session, snapshot: SpotSnapshotStore(fileName: legacy),
                                        feedSnapshotPrefix: prefix, detailPrefetchBudget: 0,
                                        beforeShardRequest: beforeShardRequest)
        let gallery = PublicGalleryService(url: URL(string: "https://site.example.test/app/data/photos.json")!,
                                           session: session, snapshot: PhotoSnapshotStore(fileName: photos))
        let environment = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: gallery, spots: spots)
        let model = PhotoMapViewModel()
        await model.load(environment: environment)
        await model.awaitIndex()
        self.environment = environment
        return model
    }

    /// `overBudgetMap` の環境（読み直し `load` を呼ぶのに使う）
    private var environment: AppEnvironment?

    // MARK: - 「スポット」の札（近い順の一覧）

    /// 🔴 予算を超えた回も、一覧の頭の行に丸写真が入る（直す前は索引だけの行のままカメラの印）
    @MainActor
    func testSpotListGetsPhotosWhenOverBudget() async throws {
        let model = await overBudgetMap()
        let before = OfficialSpotList.rows(model.officialSpots, photos: [], from: nil)
        XCTAssertEqual(before.count, 2)
        XCTAssertTrue(before.allSatisfy { $0.spot.isIndexOnly && $0.spot.photo == nil }, "予算を超えた回を作れていない")

        let needs = SpotDetailNeeds.mapSpotList(before, through: SpotDetailNeeds.listPage)
        XCTAssertEqual(needs.map(\.slug).sorted(), ["tokyo-station", "versailles"], "一覧に出す行を詳細に選んでいない")
        await model.loadListDetails(needs)

        let after = OfficialSpotList.rows(model.officialSpots, photos: [], from: nil)
        let tokyo = try XCTUnwrap(after.first { $0.spot.slug == "tokyo-station" })
        XCTAssertEqual(tokyo.spot.photo?.author, "撮った人", "一覧の行に丸写真の詳細を重ねていない")
        XCTAssertEqual(tokyo.spot.summary, "赤れんがの駅舎。")
        XCTAssertEqual(model.listDetailsRevision, 1, "行を入れ替えたのに一覧に描き直させていない")

        // 重ねたら鍵が空になって止まる（同じ一覧で叩き直さない）
        let again = SpotDetailNeeds.mapSpotList(after, through: SpotDetailNeeds.listPage)
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(SpotDetailNeeds.key(again), "")
        await model.loadListDetails(again)
        XCTAssertEqual(count("/app/data/spot-feed/jp-kanto.json"), 1)
        XCTAssertEqual(count("/app/data/spot-feed/fr.json"), 1)
        XCTAssertEqual(model.listDetailsRevision, 1, "何も変わらないのに描き直させている")
    }

    /// 全件を読まない——**見えた行の頁と次の頁まで**
    func testSpotListReadsOnlyThePagesSeen() throws {
        let rows = OfficialSpotList.rows(try Self.manyIndexOnly(100), photos: [], from: nil)
        XCTAssertEqual(rows.count, 100)
        let page = SpotDetailNeeds.listPage
        XCTAssertEqual(SpotDetailNeeds.mapSpotList(rows, through: page).map(\.spotId),
                       rows.prefix(page).map(\.spot.spotId), "頭の頁の外まで読んでいる")
        // 頭の行が見えたら次の頁まで。頁の中では深さが変わらない（1行ごとに鍵を変えない）
        XCTAssertEqual(SpotDetailNeeds.listDepth(after: 0, current: page), page * 2)
        XCTAssertEqual(SpotDetailNeeds.listDepth(after: page - 1, current: page * 2), page * 2)
        XCTAssertEqual(SpotDetailNeeds.listDepth(after: page, current: page * 2), page * 3)
        // 戻っても浅くしない
        XCTAssertEqual(SpotDetailNeeds.listDepth(after: 3, current: page * 3), page * 3)
        XCTAssertEqual(SpotDetailNeeds.mapSpotList(rows, through: 1_000).count, 100)
    }

    /// 最初の深さは頭の頁と次の頁。頭の行が見えても上がらない（`.task` を走り直させない）
    func testFirstDepthDoesNotMoveOnTheFirstPage() {
        let start = SpotDetailNeeds.ListDepth()
        XCTAssertEqual(start.depth, SpotDetailNeeds.listPage * 2)
        for index in 0..<SpotDetailNeeds.listPage {
            XCTAssertEqual(start.seen(index, query: "", category: nil), start, "頭の頁の \(index) 行目で深さが動いた")
        }
    }

    /// 🔴 絞り込み（語・カテゴリ）が変わったら、**同じ描く回の中で**深さを頭に戻す（`onChange` の1回遅れを作らない）
    func testDepthResetsWhenTheFilterChanges() {
        let page = SpotDetailNeeds.listPage
        let deep = SpotDetailNeeds.ListDepth().seen(page * 5, query: "東京", category: nil)
        XCTAssertEqual(deep.depth(query: "東京", category: nil), page * 7)
        XCTAssertEqual(deep.depth(query: "京都", category: nil), SpotDetailNeeds.firstDepth, "語が変わったのに古い深さで読む")
        XCTAssertEqual(deep.depth(query: "東京", category: "夜景"), SpotDetailNeeds.firstDepth,
                       "カテゴリが変わったのに古い深さで読む")
        // 新しい絞り込みで見えた行は、頭から測り直す
        XCTAssertEqual(deep.seen(0, query: "京都", category: nil),
                       SpotDetailNeeds.ListDepth(query: "京都", category: nil, depth: SpotDetailNeeds.firstDepth))
    }

    /// `.task(id:)` の鍵は読み込みの回でも変わる。要る行が無ければ回によらず空
    func testTaskIdChangesWithTheLoadGeneration() throws {
        let rows = try Self.manyIndexOnly(3)
        XCTAssertNotEqual(SpotDetailNeeds.listTaskId(rows, generation: 1), SpotDetailNeeds.listTaskId(rows, generation: 2))
        XCTAssertEqual(SpotDetailNeeds.listTaskId([], generation: 1), "")
        XCTAssertEqual(SpotDetailNeeds.listTaskId([], generation: 2), "")
    }

    /// 🔴 一覧の詳細を読んでいる途中に読み直し（`load`）が始まると、その回の答えは捨てる。
    /// 索引は60秒の控えから同じ索引だけの行で返る——`needs` だけの鍵では `.task` が走り直さず、
    /// 行がカメラの印のまま残っていた。回を混ぜた鍵なら変わり、同じ `needs` でもう一度読めば埋まる
    @MainActor
    func testReloadDuringListLoadIsHealedByTheNextRun() async throws {
        let gate = Gate()
        let model = await overBudgetMap(beforeShardRequest: { await gate.wait() })
        let rows = OfficialSpotList.rows(model.officialSpots, photos: [], from: nil)
        let needs = SpotDetailNeeds.mapSpotList(rows, through: SpotDetailNeeds.firstDepth)
        XCTAssertFalse(needs.isEmpty)
        let before = SpotDetailNeeds.listTaskId(needs, generation: model.loadGeneration)

        let first = Task { await model.loadListDetails(needs) }
        await gate.untilWaiting(1)
        // 区分を読んでいる途中に読み直す（引き下げ更新・「もう一度試す」）
        let environment = try XCTUnwrap(environment)
        await model.load(environment: environment)
        await model.awaitIndex()
        await gate.open()
        await first.value
        XCTAssertTrue(model.officialSpots.allSatisfy(\.isIndexOnly), "前の回の答えを新しい回に書いている")

        // 行は同じ索引だけの行（控えから）なので needs は同じ。鍵は回で変わる＝画面の `.task` が走り直す
        let again = SpotDetailNeeds.mapSpotList(OfficialSpotList.rows(model.officialSpots, photos: [], from: nil),
                                                through: SpotDetailNeeds.firstDepth)
        XCTAssertEqual(again.map(\.spotId), needs.map(\.spotId))
        XCTAssertNotEqual(SpotDetailNeeds.listTaskId(again, generation: model.loadGeneration), before,
                          "読み直しても鍵が変わらない（.task が走り直さず、行が空のまま残る）")
        await model.loadListDetails(again)
        let tokyo = try XCTUnwrap(model.officialSpots.first { $0.slug == "tokyo-station" })
        XCTAssertEqual(tokyo.photo?.author, "撮った人", "走り直した回で行が埋まらない")
    }

    /// ピンの側が先に重ねた回も、一覧に描き直させる（一覧の鍵はその行を重ね済みと見て読まない）
    @MainActor
    func testPinDetailsAlsoRedrawTheList() async throws {
        let model = await overBudgetMap()
        XCTAssertEqual(model.listDetailsRevision, 0)
        model.update(visible: MapFraming.Frame(latitude: 35.68, longitude: 139.76, latitudeSpan: 0.2, longitudeSpan: 0.2))
        await model.awaitPinDetails()
        XCTAssertEqual(model.officialSpots.first { $0.slug == "tokyo-station" }?.photo?.author, "撮った人")
        XCTAssertEqual(model.listDetailsRevision, 1, "ピンの側で行を入れ替えたのに一覧に知らせていない")
    }

    // MARK: - 「リスト」の札（県ごと）

    /// 🔴 開いた県の行だけ詳細を読み、読んだら写真が入る。閉じた県の区分は読まない
    @MainActor
    func testRegionListLoadsOnlyOpenSections() async throws {
        let model = await overBudgetMap()
        let isTokyo: (RegionList.Section) -> Bool = { $0.spots.contains { $0.spot.slug == "tokyo-station" } }
        let sections = RegionList.sections(photos: [], spots: model.officialSpots, from: nil)
        XCTAssertTrue(sections.contains(where: isTokyo))
        XCTAssertTrue(sections.contains { $0.spots.contains { $0.spot.slug == "versailles" } })

        let needs = SpotDetailNeeds.listed(SpotDetailNeeds.mapRegionRows(sections, isOpen: isTokyo),
                                           through: SpotDetailNeeds.firstDepth)
        XCTAssertEqual(needs.map(\.slug), ["tokyo-station"], "閉じた県の行まで選んでいる・開いた県の行を選んでいない")
        await model.loadListDetails(needs)

        let after = RegionList.sections(photos: [], spots: model.officialSpots, from: nil)
        let tokyo = try XCTUnwrap(after.first(where: isTokyo)?.spots.first { $0.spot.slug == "tokyo-station" })
        XCTAssertEqual(tokyo.spot.photo?.author, "撮った人", "開いた県の行に丸写真の詳細を重ねていない")
        XCTAssertEqual(count("/app/data/spot-feed/fr.json"), 0, "閉じた県の区分まで読んでいる")
        XCTAssertTrue(SpotDetailNeeds.listed(SpotDetailNeeds.mapRegionRows(after, isOpen: isTokyo),
                                             through: SpotDetailNeeds.firstDepth).isEmpty,
                      "重ねたのに鍵が空にならない（叩き直し続ける）")
    }

    /// 開いた県の行を並ぶ順につなぎ、頭から `depth` 行だけ
    func testRegionListIsBoundedByDepth() throws {
        let sections = RegionList.sections(photos: [], spots: try Self.manyIndexOnly(80), from: nil)
        let open = SpotDetailNeeds.mapRegionRows(sections, isOpen: { _ in true })
        XCTAssertEqual(open.count, 80)
        XCTAssertEqual(SpotDetailNeeds.listed(open, through: 30).map(\.spotId),
                       open.prefix(30).map(\.spotId))
        XCTAssertTrue(SpotDetailNeeds.listed(SpotDetailNeeds.mapRegionRows(sections, isOpen: { _ in false }), through: 30).isEmpty,
                      "閉じた県の行を読んでいる")
    }

    // MARK: - 重ね方

    /// 待っている間に変わった行（別の回が先に重ねた行）を、届いた古い写しで戻さない
    func testOverlayKeepsRowsChangedWhileWaiting() throws {
        guard case .ok(let parsed) = OfficialSpotService.decodeFeedIndex(Data(SpotFeedShardsTests.index().utf8)) else {
            return XCTFail("索引が読めない")
        }
        let rows = parsed.rows
        let tokyoDetail = try XCTUnwrap(OfficialSpotService.decodeShard(Data(SpotFeedShardsTests.kanto.utf8))?["sp_tokyo000001"])
        let parisDetail = try XCTUnwrap(OfficialSpotService.decodeShard(Data(SpotFeedShardsTests.france.utf8))?["sp_paris0000001"])
        let tokyoIndex = try XCTUnwrap(rows.first { $0.slug == "tokyo-station" })
        let parisIndex = try XCTUnwrap(rows.first { $0.slug == "versailles" })
        // 今: 東京駅はもう重ね済み（ピンの側が先に読んだ）、ヴェルサイユは索引だけ
        let current = [tokyoIndex.merged(with: tokyoDetail), parisIndex]
        // 届いたもの: 古い写し（東京駅は索引だけ）と、ヴェルサイユの詳細
        let merged = [tokyoIndex, parisIndex.merged(with: parisDetail)]
        let next = SpotDetailNeeds.overlay(current, with: merged)
        XCTAssertEqual(next[0].photo?.author, "撮った人", "重ね済みの行を古い索引の写しで戻している")
        XCTAssertFalse(next[1].isIndexOnly)
        XCTAssertEqual(next[1].timeZone, "Europe/Paris")
        XCTAssertEqual(SpotDetailNeeds.overlay(current, with: [tokyoIndex, parisIndex]), current)
    }

    // MARK: - 試験の行

    /// 索引だけの行を `count` 件（関東に縦に並べる）
    static func manyIndexOnly(_ count: Int) throws -> [OfficialSpot] {
        var items: [String] = []
        for i in 0..<count {
            let number = String(i)
            let id: String = String(repeating: "0", count: 12 - number.count) + number
            let name: String = String(repeating: "0", count: max(0, 3 - number.count)) + number
            let lat: Double = 35.0 + Double(i) * 0.001
            var row = #"{"spotId":"sp_"# + id + #"","slug":"spot-"# + number + #"","name":"スポット"# + name + #"","#
            row += #""region":{"prefecture":"東京都"},"coords":{"lat":"# + String(lat) + #","lng":139.7},"#
            row += #""stage":"published","hasImage":true}"#
            items.append(row)
        }
        var spots = try JSONDecoder.api.decode([OfficialSpot].self, from: Data("[\(items.joined(separator: ","))]".utf8))
        for i in spots.indices {
            spots[i].isIndexOnly = true
            spots[i].shard = "jp-kanto"
        }
        return spots
    }
}
