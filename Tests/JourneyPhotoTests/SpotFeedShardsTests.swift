import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **分けた置き場**（`/app/data/spot-feed/index.json` と `<区分>.json`・2026-10-07）の読み方。
///
/// 見るもの:
///   1. 索引を先に読み、詳細の和が小さいうちは全区分を重ねる（画面の見え方は今と同じ）
///   2. 大きければ索引だけで返し、`withDetails` で**要る区分だけ**読む
///   3. 端末の控えの指紋が索引と同じ区分は取りに行かない
///   4. 新しい置き場が無い（404）・知らない版なら古い `spots.json` に戻る
///   5. 圏外は控え（索引・区分）で出す
///   6. 候補選び（季節・写真の有無）は索引の「種類」で答える
final class SpotFeedShardsTests: XCTestCase {

    private var session: URLSession!
    private let url = URL(string: "https://site.example.test/app/data/spots.json")!
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
        let names = snapshotNames + prefixes.flatMap { p in ["index", "jp-kanto", "fr", "jp-tokyo"].map { "\(p)-\($0).json" } }
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

    private func service(prefix: String? = nil, budget: Int = OfficialSpotService.detailPrefetchBudget) -> OfficialSpotService {
        let prefix = prefix ?? UUID().uuidString
        if !prefixes.contains(prefix) { prefixes.append(prefix) }
        let legacy = UUID().uuidString
        snapshotNames.append(legacy)
        return OfficialSpotService(url: url, session: session, snapshot: SpotSnapshotStore(fileName: legacy),
                                   feedSnapshotPrefix: prefix, detailPrefetchBudget: budget)
    }

    // MARK: - 試験の置き場（Web の `spotFeedShards.ts` と同じ形）

    /// 関東の詳細（行は `spots.json` と同じ形）
    static let kanto = """
    [{"spotId":"sp_tokyo000001","slug":"tokyo-station","name":"東京駅","region":{"prefecture":"東京都","city":"千代田区"},
      "coords":{"lat":35.68,"lng":139.76},"summary":"赤れんがの駅舎。","stage":"published",
      "image":{"url":"https://journey-photo.com/images/spots/tokyo-station.jpg","author":"撮った人","license":"CC BY-SA 4.0"},
      "seasonalGuide":[{"season":"autumn","text":"秋の夕方に赤れんがが映える"}],
      "timeOfDayGuide":[{"time":"dusk","text":"日没後の駅舎"}]}]
    """

    /// フランスの詳細
    static let france = """
    [{"spotId":"sp_paris0000001","slug":"versailles","name":"ヴェルサイユ宮殿","region":{"country":"フランス","prefecture":"イヴリーヌ県"},
      "coords":{"lat":48.80,"lng":2.12},"summary":"鏡の間。","stage":"published","timeZone":"Europe/Paris",
      "seasonalGuide":[{"season":"spring","text":"庭園の花"}]}]
    """

    static func hash(_ json: String) -> String { ValidatorStore.fingerprint(Data(json.utf8)) }

    /// 索引。`kantoHash`・`franceHash` を変えると「区分が替わった」索引になる
    static func index(kanto: String = SpotFeedShardsTests.kanto, france: String = SpotFeedShardsTests.france,
                      version: Int = 1) -> String {
        """
        {"v":\(version),"shards":[
          {"key":"fr","count":1,"bytes":\(Data(france.utf8).count),"hash":"\(hash(france))",
           "spots":[{"spotId":"sp_paris0000001","slug":"versailles","name":"ヴェルサイユ宮殿","aliases":["ベルサイユ"],
                     "region":{"country":"フランス","prefecture":"イヴリーヌ県"},"coords":{"lat":48.80,"lng":2.12},
                     "stage":"published","seasons":["spring"]}]},
          {"key":"jp-kanto","count":1,"bytes":\(Data(kanto.utf8).count),"hash":"\(hash(kanto))",
           "spots":[{"spotId":"sp_tokyo000001","slug":"tokyo-station","name":"東京駅","region":{"prefecture":"東京都","city":"千代田区"},
                     "coords":{"lat":35.68,"lng":139.76},"stage":"published","seasons":["autumn"],"times":["dusk"],"hasImage":true}]}
        ]}
        """
    }

    private func serve(index: String = SpotFeedShardsTests.index(), kanto: String = SpotFeedShardsTests.kanto,
                       france: String = SpotFeedShardsTests.france) {
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200, body: index)
        StubProtocol.respond(path: "/app/data/spot-feed/jp-kanto.json", status: 200, body: kanto)
        StubProtocol.respond(path: "/app/data/spot-feed/fr.json", status: 200, body: france)
    }

    private func count(_ path: String) -> Int {
        StubProtocol.requests.filter { $0 == "GET \(path)" }.count
    }

    // MARK: - 1. 小さいうちは全区分

    func testReadsIndexThenAllShardsWhileSmall() async throws {
        serve()
        let spots = try await service().fetchIndex()
        XCTAssertEqual(spots.map(\.slug).sorted(), ["tokyo-station", "versailles"])
        let tokyo = try XCTUnwrap(spots.first { $0.slug == "tokyo-station" })
        XCTAssertFalse(tokyo.isIndexOnly, "詳細を重ねていない")
        XCTAssertEqual(tokyo.shard, "jp-kanto")
        XCTAssertEqual(tokyo.photo?.author, "撮った人")
        XCTAssertEqual(tokyo.summary, "赤れんがの駅舎。")
        XCTAssertEqual(tokyo.seasons.first?.text, "秋の夕方に赤れんがが映える")
        XCTAssertEqual(tokyo.times.map(\.time), ["dusk"])
        // 時刻帯は詳細にだけ載る（光の時刻・旅の当日の行が使う）。重ねた行で読める
        XCTAssertEqual(spots.first { $0.slug == "versailles" }?.timeZone, "Europe/Paris", "詳細の時刻帯を落としている")
        XCTAssertEqual(count("/app/data/spots.json"), 0, "新しい置き場があるのに古い置き場も読んでいる")
        XCTAssertEqual(count("/app/data/spot-feed/jp-kanto.json"), 1)
        XCTAssertEqual(count("/app/data/spot-feed/fr.json"), 1)
    }

    // MARK: - 2. 大きければ要る区分だけ

    func testLargeFeedReturnsIndexOnlyAndLoadsOnlyTheNeededShard() async throws {
        serve()
        let spots = service(budget: 0)
        let rows = try await spots.fetchIndex()
        XCTAssertTrue(rows.allSatisfy(\.isIndexOnly))
        XCTAssertEqual(count("/app/data/spot-feed/jp-kanto.json") + count("/app/data/spot-feed/fr.json"), 0,
                       "大きいのに全区分を読んでいる")
        let tokyo = try XCTUnwrap(rows.first { $0.slug == "tokyo-station" })
        // 索引だけでも候補選びに答えられる（種類・写真の有無）
        XCTAssertNil(tokyo.photo)
        XCTAssertTrue(tokyo.hasPhoto)
        XCTAssertEqual(tokyo.seasonKeys, ["autumn"])
        XCTAssertEqual(tokyo.timeKeys, ["dusk"])
        XCTAssertTrue(tokyo.seasons.isEmpty, "索引に文は無い")

        let merged = await spots.withDetails(rows, for: [tokyo])
        XCTAssertEqual(count("/app/data/spot-feed/jp-kanto.json"), 1)
        XCTAssertEqual(count("/app/data/spot-feed/fr.json"), 0, "要らない区分まで読んでいる")
        let after = try XCTUnwrap(merged.first { $0.slug == "tokyo-station" })
        XCTAssertFalse(after.isIndexOnly)
        XCTAssertEqual(after.photo?.author, "撮った人")
        XCTAssertEqual(after.seasonKeys, ["autumn"], "重ねても種類が変わらない（候補が入れ替わらない）")
        XCTAssertTrue(try XCTUnwrap(merged.first { $0.slug == "versailles" }).isIndexOnly)

        // 読めた区分は、次の索引の読み直しでも重なったまま（控えを使う・取り直さない）
        let again = try await spots.fetchIndex(force: true)
        XCTAssertFalse(try XCTUnwrap(again.first { $0.slug == "tokyo-station" }).isIndexOnly)
        XCTAssertEqual(count("/app/data/spot-feed/jp-kanto.json"), 1)
        // 重ね済みの行だけを渡しても通信しない
        _ = await spots.withDetails(again, for: [after])
        XCTAssertEqual(count("/app/data/spot-feed/jp-kanto.json"), 1)
    }

    // MARK: - 3. 指紋が合う控えは取りに行かない・替わった区分だけ取り直す

    func testShardSnapshotWithSameHashIsNotRefetched() async throws {
        let prefix = UUID().uuidString
        serve()
        _ = try await service(prefix: prefix).fetchIndex()
        XCTAssertEqual(count("/app/data/spot-feed/fr.json"), 1)

        // 新しい起動（メモリの控えは無い）。索引は同じ → 区分は端末の控え
        _ = try await service(prefix: prefix).fetchIndex()
        XCTAssertEqual(count("/app/data/spot-feed/fr.json"), 1, "指紋の合う控えがあるのに取り直している")
        XCTAssertEqual(count("/app/data/spot-feed/jp-kanto.json"), 1)

        // フランスだけ替わった索引 → フランスだけ取り直す
        let changed = Self.france.replacingOccurrences(of: "庭園の花", with: "庭園のバラ")
        StubProtocol.reset()
        serve(index: Self.index(france: changed), france: changed)
        let spots = try await service(prefix: prefix).fetchIndex()
        XCTAssertEqual(count("/app/data/spot-feed/fr.json"), 1)
        XCTAssertEqual(count("/app/data/spot-feed/jp-kanto.json"), 0)
        XCTAssertEqual(spots.first { $0.slug == "versailles" }?.seasons.first?.text, "庭園のバラ")
    }

    /// 🔴 索引が替わって指紋の合わなくなった詳細は、**取り直すまで重ねない**（下げた写真・直した文を出し続けない）
    func testChangedHashDropsTheOldDetailUntilReloaded() async throws {
        serve()
        let spots = service(budget: 0)
        let rows = try await spots.fetchIndex()
        _ = await spots.withDetails(rows, for: rows)
        let changed = Self.kanto.replacingOccurrences(of: "撮った人", with: "別の人")
        serve(index: Self.index(kanto: changed), kanto: changed)
        StubProtocol.reset()
        serve(index: Self.index(kanto: changed), kanto: changed)
        let next = try await spots.fetchIndex(force: true)
        XCTAssertTrue(try XCTUnwrap(next.first { $0.slug == "tokyo-station" }).isIndexOnly, "古い詳細を重ねたまま")
        let merged = await spots.withDetails(next, for: next)
        XCTAssertEqual(merged.first { $0.slug == "tokyo-station" }?.photo?.author, "別の人")
    }

    // MARK: - 4. 古い置き場に戻る

    func testFallsBackToLegacyWhenTheSplitFeedIsMissing() async throws {
        // 道を持たない口は 404（本番に新しい置き場がまだ無い姿）
        StubProtocol.respond(path: "/app/data/spots.json", status: 200, body: OfficialSpotServiceTests.threeSpots)
        let spots = try await service().fetchIndex()
        XCTAssertEqual(spots.map(\.slug), ["abashiri-ryuhyo", "takaya-jinja", "no-coords"])
        XCTAssertFalse(spots.contains(where: \.isIndexOnly))
        XCTAssertEqual(StubProtocol.requests, ["GET /app/data/spot-feed/index.json", "GET /app/data/spots.json"])
    }

    func testUnknownVersionFallsBackToLegacy() async throws {
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200, body: Self.index(version: 2))
        StubProtocol.respond(path: "/app/data/spots.json", status: 200, body: OfficialSpotServiceTests.threeSpots)
        let spots = try await service().fetchIndex()
        XCTAssertEqual(spots.count, 3, "知らない版の索引を読もうとしている")
        XCTAssertEqual(count("/app/data/spots.json"), 1)
    }

    /// 壊れた索引（控えも無い）も古い置き場へ
    func testBrokenIndexWithoutSnapshotFallsBackToLegacy() async throws {
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200, body: "<html>login</html>")
        StubProtocol.respond(path: "/app/data/spots.json", status: 200, body: OfficialSpotServiceTests.threeSpots)
        let spots = try await service().fetchIndex()
        XCTAssertEqual(spots.count, 3)
    }

    // MARK: - 5. 圏外

    func testOfflineUsesTheIndexAndShardSnapshots() async throws {
        let prefix = UUID().uuidString
        serve()
        _ = try await service(prefix: prefix).fetchIndex()
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await service(prefix: prefix).fetchIndex()
        XCTAssertEqual(offline.count, 2)
        XCTAssertEqual(offline.first { $0.slug == "tokyo-station" }?.photo?.author, "撮った人",
                       "圏外で区分の控えを重ねていない")
    }

    /// 取れなかった区分は叩き直さない（地図が動くたびに叩かない）。行は索引のまま返す
    func testFailedShardIsNotRetriedImmediately() async throws {
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200, body: Self.index())
        StubProtocol.respond(path: "/app/data/spot-feed/jp-kanto.json", status: 500, body: "oops")
        let spots = service(budget: 0)
        let rows = try await spots.fetchIndex()
        let first = await spots.withDetails(rows, for: rows)
        XCTAssertTrue(first.allSatisfy(\.isIndexOnly))
        _ = await spots.withDetails(rows, for: rows)
        XCTAssertEqual(count("/app/data/spot-feed/jp-kanto.json"), 1)
    }

    // MARK: - レビュー（2026-10-07）で足した試験

    /// 🔴 404（分けた置き場を下げた）は索引の控えも消す——圏外で下げた索引を出し続けない
    func testNotFoundClearsTheIndexSnapshot() async throws {
        let prefix = UUID().uuidString
        serve()
        _ = try await service(prefix: prefix).fetchIndex()
        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/spots.json", status: 200, body: OfficialSpotServiceTests.threeSpots)
        let legacy = try await service(prefix: prefix).fetchIndex()
        XCTAssertEqual(legacy.count, 3, "404 なのに古い置き場に戻っていない")
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        do {
            let offline = try await service(prefix: prefix).fetchIndex()
            XCTAssertFalse(offline.contains { $0.slug == "tokyo-station" }, "下げた索引の控えを圏外で出している")
        } catch {
            // 控え（索引も古い置き場も）が無ければ投げる。下げた索引を出さなければよい
        }
    }

    /// 🔴 200 の HTML（キャプティブポータル）は読まずに退け、前回の控えを出す。控えも上書きしない
    func testHTMLIndexIsRejectedAndDoesNotReplaceTheSnapshot() async throws {
        let prefix = UUID().uuidString
        serve()
        _ = try await service(prefix: prefix).fetchIndex()
        StubProtocol.reset()
        // 中身は読める索引（1か所だけ）でも、種別が HTML なら信じない
        let onlyFrance = """
        {"v":1,"shards":[{"key":"fr","bytes":1,"hash":"x","spots":[{"spotId":"sp_x","slug":"x","name":"X","stage":"published"}]}]}
        """
        StubProtocol.respond(status: 200, body: "", contentType: "text/html; charset=utf-8")
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200, body: onlyFrance)
        let spots = try await service(prefix: prefix).fetchIndex()
        XCTAssertEqual(spots.map(\.slug).sorted(), ["tokyo-station", "versailles"], "HTML の応答を索引として読んでいる")
        StubProtocol.reset()
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await service(prefix: prefix).fetchIndex()
        XCTAssertEqual(offline.count, 2, "HTML で控えを上書きしている")
    }

    /// 取れなかった区分は、指紋の合わない前回の控えでも重ねる（圏外・5xx で写真が消えない）
    func testStaleShardSnapshotIsUsedWhenTheShardFails() async throws {
        let prefix = UUID().uuidString
        serve()
        _ = try await service(prefix: prefix).fetchIndex()
        StubProtocol.reset()
        let changed = Self.kanto.replacingOccurrences(of: "赤れんがの駅舎。", with: "直した概要。")
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200, body: Self.index(kanto: changed))
        StubProtocol.respond(path: "/app/data/spot-feed/fr.json", status: 200, body: Self.france)
        StubProtocol.respond(path: "/app/data/spot-feed/jp-kanto.json", status: 500, body: "oops")
        let spots = try await service(prefix: prefix).fetchIndex()
        let tokyo = try XCTUnwrap(spots.first { $0.slug == "tokyo-station" })
        XCTAssertEqual(tokyo.photo?.author, "撮った人", "取れなかった区分の前回の控えを重ねていない")
        XCTAssertEqual(tokyo.summary, "赤れんがの駅舎。")
    }

    /// 🔴 区分が1つも読めず捨てた索引は壊れている。控えにも保存しない（前回の良い控えを出す）
    func testIndexWithOnlyBrokenShardsIsBroken() async throws {
        if case .broken = OfficialSpotService.decodeFeedIndex(Data(#"{"v":1,"shards":[{"key":"jp-kanto"}]}"#.utf8)) {} else {
            XCTFail("区分が全部壊れた索引を読めたことにしている")
        }
        if case .broken = OfficialSpotService.decodeFeedIndex(Data(
            #"{"v":1,"shards":[{"key":"jp-kanto","spots":[{"spotId":1}]}]}"#.utf8)) {} else {
            XCTFail("行が全部壊れた索引を読めたことにしている")
        }
        // 区分が無い（0件）だけの索引は壊れていない
        if case .ok(let empty) = OfficialSpotService.decodeFeedIndex(Data(#"{"v":1,"shards":[]}"#.utf8)) {
            XCTAssertTrue(empty.rows.isEmpty)
        } else {
            XCTFail("空の索引")
        }

        let prefix = UUID().uuidString
        serve()
        _ = try await service(prefix: prefix).fetchIndex()
        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200, body: #"{"v":1,"shards":[{"key":"jp-kanto"}]}"#)
        let spots = try await service(prefix: prefix).fetchIndex()
        XCTAssertEqual(spots.count, 2, "壊れた索引で前回の控えを出していない")
        StubProtocol.reset()
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await service(prefix: prefix).fetchIndex()
        XCTAssertEqual(offline.count, 2, "壊れた索引で控えを上書きしている")
    }

    /// 詳細を重ねても、名前・座標・stage は索引の値（区分が古い・食い違う回にピンや下書きの印が入れ替わらない）
    func testMergeKeepsTheIndexValues() async throws {
        let stale = Self.kanto
            .replacingOccurrences(of: "\"name\":\"東京駅\"", with: "\"name\":\"古い名前\"")
            .replacingOccurrences(of: "\"lat\":35.68", with: "\"lat\":10.0")
            .replacingOccurrences(of: "\"stage\":\"published\"", with: "\"stage\":\"review\"")
        serve(kanto: stale)
        // 索引の指紋は詳細の中身から作るので、食い違った詳細でも読む
        StubProtocol.reset()
        serve(index: Self.index(kanto: stale), kanto: stale)
        let spots = try await service().fetchIndex()
        let tokyo = try XCTUnwrap(spots.first { $0.slug == "tokyo-station" })
        XCTAssertFalse(tokyo.isIndexOnly)
        XCTAssertEqual(tokyo.name, "東京駅", "詳細の名前で索引を上書きしている")
        XCTAssertEqual(tokyo.coords?.lat, 35.68)
        XCTAssertFalse(tokyo.isDraft)
        XCTAssertEqual(tokyo.photo?.author, "撮った人")
    }

    /// サーバーが区分を割り直したあとも、画面が持っている古い行に詳細が載る（今の索引から区分を引く）
    func testWithDetailsUsesTheCurrentShardAfterResplit() async throws {
        serve()
        let spots = service(budget: 0)
        let old = try await spots.fetchIndex()
        let oldTokyo = try XCTUnwrap(old.first { $0.slug == "tokyo-station" })
        XCTAssertEqual(oldTokyo.shard, "jp-kanto")
        // 東京駅を `jp-tokyo` に移した索引
        let resplit = Self.index().replacingOccurrences(of: "\"key\":\"jp-kanto\"", with: "\"key\":\"jp-tokyo\"")
        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200, body: resplit)
        StubProtocol.respond(path: "/app/data/spot-feed/jp-tokyo.json", status: 200, body: Self.kanto)
        _ = try await spots.fetchIndex(force: true)
        let merged = await spots.withDetails(old, for: [oldTokyo])
        let tokyo = try XCTUnwrap(merged.first { $0.slug == "tokyo-station" })
        XCTAssertEqual(tokyo.photo?.author, "撮った人", "割り直したあと、古い行の区分で探して詳細が載らない")
        XCTAssertEqual(tokyo.shard, "jp-tokyo")
        XCTAssertEqual(count("/app/data/spot-feed/jp-tokyo.json"), 1)
    }

    /// 🔴 区分を読んでいる間に来た呼び出しにも、詳細を重ねた行を返す（60秒の控えに索引だけの行を置かない）
    func testConcurrentCallsGetDetailedRows() async throws {
        serve()
        let gate = Gate()
        let prefix = UUID().uuidString
        prefixes.append(prefix)
        let legacy = UUID().uuidString
        snapshotNames.append(legacy)
        let spots = OfficialSpotService(url: url, session: session, snapshot: SpotSnapshotStore(fileName: legacy),
                                        feedSnapshotPrefix: prefix,
                                        beforeShardRequest: { await gate.wait() })
        let a = Task { try await spots.fetchIndex() }
        // 1本目が区分を読んでいる途中で、2本目が来る
        await gate.untilWaiting(1)
        let b = Task { try await spots.fetchIndex() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()
        let first = try await a.value
        let second = try await b.value
        XCTAssertFalse(first.contains(where: \.isIndexOnly))
        XCTAssertFalse(second.contains(where: \.isIndexOnly), "読んでいる間の呼び出しに索引だけの行を返している")
    }

    /// 🔴 **送る前の索引の待ち（`PlaceCoordsRule.index`・2秒）は、区分を読んでいる途中でも上限で終わる**
    /// （2026-10-09 owner「ストーリーで写真を選んだのに投稿できない」）。区分の読み込みは呼んだ側の
    /// 取り消しを受けない（`loadShard`）ので、以前は区分が届くまで（本番は通信の時間切れまで）
    /// 待ち続け、ストーリーの「シェアする」は押しても何も起きないままだった
    func testSubmitIndexWaitDoesNotWaitForShardDownloads() async {
        serve()
        let gate = Gate()
        let prefix = UUID().uuidString
        prefixes.append(prefix)
        let legacy = UUID().uuidString
        snapshotNames.append(legacy)
        let spots = OfficialSpotService(url: url, session: session, snapshot: SpotSnapshotStore(fileName: legacy),
                                        feedSnapshotPrefix: prefix,
                                        beforeShardRequest: { await gate.wait() })
        final class Box: @unchecked Sendable { var result: [OfficialSpot]? }
        let box = Box()
        let run = Task {
            box.result = await PlaceCoordsRule.index(current: [], needed: true, wait: .milliseconds(100),
                                                     fetch: { try? await spots.fetchIndex() })
        }
        // 区分を読んでいる途中（門で止まっている）にする
        await gate.untilWaiting(1)
        let deadline = Date().addingTimeInterval(2)
        while box.result == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let returned = box.result != nil
        await gate.open()
        await run.value
        XCTAssertTrue(returned, "区分の読み込みを待ち続けて、送る前の索引の待ちが2秒で終わらない")
    }

    // MARK: - 別名は索引から

    func testAliasesComeFromTheIndex() async throws {
        serve()
        let spots = service()
        _ = try await spots.fetchIndex()
        let aliases = await spots.fetchAliases()
        XCTAssertEqual(aliases["versailles"], ["ベルサイユ"])
        XCTAssertEqual(count("/app/data/spot-search.json"), 0, "索引に別名があるのに spot-search.json を読んでいる")
    }

    // MARK: - 索引の読み方（純関数）

    func testDecodeDropsUnsafeShardKeysDuplicatesAndBrokenRows() {
        let json = """
        {"v":1,"shards":[
          {"key":"../x","bytes":1,"hash":"h","spots":[{"spotId":"sp_1","slug":"a","name":"A","stage":"published"}]},
          {"key":"jp-kanto","bytes":10,"hash":"h1","spots":[
             {"spotId":"sp_2","slug":"b","name":"B","stage":"published","seasons":["spring",3,"monsoon"],"hasImage":"yes"},
             {"spotId":"sp_3","slug":123,"name":"C","stage":"published"}]},
          {"key":"fr","bytes":5,"hash":"h2","spots":[{"spotId":"sp_2","slug":"b2","name":"B2","stage":"published"}]}
        ]}
        """
        guard case .ok(let parsed) = OfficialSpotService.decodeFeedIndex(Data(json.utf8)) else {
            return XCTFail("読めていない")
        }
        XCTAssertEqual(parsed.rows.map(\.slug), ["b"])
        XCTAssertEqual(Set(parsed.table.keys), ["jp-kanto", "fr"])
        XCTAssertEqual(parsed.dropped, 3, "区分の鍵の悪い行・壊れた行・重複を数えていない")
        let b = parsed.rows[0]
        XCTAssertEqual(b.shard, "jp-kanto")
        XCTAssertTrue(b.isIndexOnly)
        XCTAssertEqual(b.seasonKeys, ["spring"], "知らない季節・文字でない種類を落としていない")
        XCTAssertFalse(b.hasPhoto, "真偽でない hasImage を有ると読んでいる")
    }

    func testDecodeTellsUnknownVersionAndBroken() {
        if case .unknownVersion = OfficialSpotService.decodeFeedIndex(Data(#"{"v":2,"shards":[]}"#.utf8)) {} else {
            XCTFail("知らない版")
        }
        if case .broken = OfficialSpotService.decodeFeedIndex(Data("[]".utf8)) {} else {
            XCTFail("古い置き場の形は壊れた索引")
        }
    }

    /// 区分の指紋は Web（`spotFeedShards.ts` の `fingerprint`）と同じ式。検査値も同じ
    func testFingerprintMatchesTheServer() {
        XCTAssertEqual(ValidatorStore.fingerprint(Data()), "0-cbf29ce484222325")
        XCTAssertEqual(ValidatorStore.fingerprint(Data("a".utf8)), "1-af63dc4c8601ec8c")
        XCTAssertEqual(ValidatorStore.fingerprint(Data("foobar".utf8)), "6-85944171f73967e8")
    }

    // MARK: - 6. 候補選びは種類で答える

    private func indexOnlyRows() throws -> [OfficialSpot] {
        guard case .ok(let parsed) = OfficialSpotService.decodeFeedIndex(Data(Self.index().utf8)) else {
            throw XCTSkip("索引が読めない")
        }
        return parsed.rows
    }

    func testSelectorsWorkOnIndexOnlyRows() throws {
        let rows = try indexOnlyRows()
        // 写真がある・秋の案内がある東京駅だけが、秋の季節の札の候補
        let autumn = try XCTUnwrap(TripPlanText.date(fromYMD: "2026-10-07"))
        guard case .inSeason(let spot, let season, let guide)? = HomeTopCard.inSeason(today: autumn, spots: rows) else {
            return XCTFail("索引だけの行で季節の札を選べていない")
        }
        XCTAssertEqual(spot.slug, "tokyo-station")
        XCTAssertEqual(season, "autumn")
        XCTAssertEqual(guide, "", "索引に文は無い（詳細を重ねてから入る）")
        XCTAssertEqual(TripPicker.deck(from: rows, excluding: [], seed: 1).map(\.slug), ["tokyo-station"])
        XCTAssertEqual(ShootingTime.spots(rows, filter: ShootingTime.Filter(season: .spring, dayPart: nil)).map(\.slug),
                       ["versailles"])
        XCTAssertTrue(ShootingTime.hasAnything(photos: [], spots: rows))
        let plan = SeasonReminder.plan(now: autumn, spots: rows,
                                       wishlist: [SavedSpotKey.official("versailles")], calendar: SeasonReminder.calendar)
        XCTAssertNil(plan, "冬の案内の無い場所で知らせている")
    }

    func testDetailNeedsPickOnlyShownIndexOnlyRows() throws {
        let rows = try indexOnlyRows()
        let autumn = try XCTUnwrap(TripPlanText.date(fromYMD: "2026-10-07"))
        let choice = try XCTUnwrap(HomeTopCard.inSeason(today: autumn, spots: rows))
        XCTAssertEqual(SpotDetailNeeds.home(choices: [choice], shelf: nil, spots: rows).map(\.slug), ["tokyo-station"])
        XCTAssertEqual(SpotDetailNeeds.wished([SavedSpotKey.official("versailles")], spots: rows).map(\.slug), ["versailles"])
        // 重ね済みの行は要らない
        var detailed = rows
        detailed[1].isIndexOnly = false
        XCTAssertEqual(SpotDetailNeeds.home(choices: [choice], shelf: nil, spots: detailed), [])
        XCTAssertEqual(SpotDetailNeeds.key(detailed), rows[0].spotId)
    }

    /// 旅行の札: めくる先の札と選んだ場所に詳細を重ね、並び・決めごとは変えない
    @MainActor
    func testTripPickerAppliesDetailsWithoutReordering() async throws {
        serve()
        let spots = service(budget: 0)
        let model = TripPickerModel()
        await model.load(fetch: { try await spots.fetchIndex() }, excluding: [], seed: 1)
        XCTAssertEqual(model.deck.map(\.slug), ["tokyo-station"])
        XCTAssertNil(model.current?.photo)
        XCTAssertEqual(model.detailNeeds.map(\.slug), ["tokyo-station"])
        await model.applyDetails { await spots.withDetails($0, for: $1) }
        XCTAssertEqual(model.deck.map(\.slug), ["tokyo-station"])
        XCTAssertEqual(model.current?.photo?.author, "撮った人")
        XCTAssertTrue(model.detailNeeds.isEmpty)
    }

    /// 地図: 寄せて置いたピンの区分だけ読み、写真の印に替える
    @MainActor
    func testMapLoadsDetailsOnlyForPlacedPins() async throws {
        serve()
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: "[]")
        let gallery = PublicGalleryService(url: URL(string: "https://site.example.test/app/data/photos.json")!,
                                           session: session, snapshot: PhotoSnapshotStore(fileName: UUID().uuidString))
        let environment = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: gallery,
                                         spots: service(budget: 0))
        let model = PhotoMapViewModel()
        await model.load(environment: environment)
        await model.awaitIndex()
        model.update(visible: MapFraming.Frame(latitude: 35.68, longitude: 139.76, latitudeSpan: 0.2, longitudeSpan: 0.2))
        XCTAssertEqual(model.officialPins.map(\.slug), ["tokyo-station"])
        await model.awaitPinDetails()
        XCTAssertEqual(model.officialPins.first?.photo?.author, "撮った人", "置いたピンに写真を重ねていない")
        XCTAssertEqual(count("/app/data/spot-feed/jp-kanto.json"), 1)
        XCTAssertEqual(count("/app/data/spot-feed/fr.json"), 0, "置いていないピンの区分まで読んでいる")
    }
}
