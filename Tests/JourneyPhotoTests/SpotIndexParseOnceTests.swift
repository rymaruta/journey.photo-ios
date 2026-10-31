import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 撮影スポットの索引を何度も解析しない（2026-10-31・札 #429 アプリ 3）。
///
/// - 解析した結果を中身の指紋つきでメモリに持ち、サーバーが「変わっていない（304）」と答えた回・圏外の回は
///   それを使う（端末の控えを読み直して解析し直さない）
/// - 1回の解析で JSON を1度だけ読む（前は版を読む復号と全体を読む復号の2回）
/// - 🔴 **壊れた索引は控えない**（`fetchFeedIndex` の `.broken`）。解析した結果も持たない
final class SpotIndexParseOnceTests: XCTestCase {

    private var session: URLSession!
    private let url = URL(string: "https://site.example.test/app/data/spots.json")!
    private var prefixes: [String] = []
    private var legacyNames: [String] = []
    private let indexPath = "/app/data/spot-feed/index.json"

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
        let names = legacyNames + prefixes.flatMap { p in ["index", "jp-kanto", "fr"].map { "\(p)-\($0).json" } }
        for name in names {
            let file = caches.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: file.appendingPathExtension("validator"))
        }
        prefixes = []
        legacyNames = []
        StubProtocol.reset()
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    private func service(prefix: String) -> OfficialSpotService {
        if !prefixes.contains(prefix) { prefixes.append(prefix) }
        let legacy = UUID().uuidString
        legacyNames.append(legacy)
        return OfficialSpotService(url: url, session: session, snapshot: SpotSnapshotStore(fileName: legacy),
                                   feedSnapshotPrefix: prefix)
    }

    /// 索引と区分（`SpotFeedShardsTests` と同じ置き場）を返す。`etag` があれば応答に付ける
    private func serve(index: String = SpotFeedShardsTests.index(), etag: String?) {
        StubProtocol.reset()
        if let etag { StubProtocol.responseHeaders = ["ETag": etag] }
        StubProtocol.respond(path: indexPath, status: 200, body: index)
        StubProtocol.respond(path: "/app/data/spot-feed/jp-kanto.json", status: 200, body: SpotFeedShardsTests.kanto)
        StubProtocol.respond(path: "/app/data/spot-feed/fr.json", status: 200, body: SpotFeedShardsTests.france)
    }

    private func serveNotModified() {
        StubProtocol.reset()
        StubProtocol.respond(path: indexPath, status: 304, body: "")
    }

    /// 関東の区分の名前だけ変えた索引（中身の違う、読める索引）
    private static let renamedIndex = SpotFeedShardsTests.index().replacingOccurrences(of: "\"東京駅\"", with: "\"東京駅（丸の内）\"")

    // MARK: - 304 で解析し直さない

    /// 🔴 200 で1回解析したら、304 の取り直しでは解析しない（前は 304 のたびに端末の控えを解析し直していた）
    func testNotModifiedReusesTheParsedIndex() async throws {
        let spots = service(prefix: UUID().uuidString)
        serve(etag: #""v1""#)
        let first = try await spots.fetchIndex()
        XCTAssertEqual(first.count, 2)
        var decodes = await spots.feedIndexDecodeCount
        XCTAssertEqual(decodes, 1)

        for _ in 0..<3 {
            serveNotModified()
            let again = try await spots.fetchIndex(force: true)
            XCTAssertEqual(again.map(\.spotId), first.map(\.spotId), "304 で前と同じ索引を返していない")
            XCTAssertEqual(again.map(\.name), first.map(\.name))
            XCTAssertEqual(StubProtocol.allRequests.first?.value(forHTTPHeaderField: "If-None-Match"), #""v1""#,
                           "条件付きで取っていない（304 の道を通っていない）")
        }
        decodes = await spots.feedIndexDecodeCount
        XCTAssertEqual(decodes, 1, "304 のたびに索引を解析し直している")
    }

    /// 圏外（前回の控えを出す）でも解析し直さない
    func testOfflineReusesTheParsedIndex() async throws {
        let spots = service(prefix: UUID().uuidString)
        serve(etag: #""v1""#)
        _ = try await spots.fetchIndex()
        StubProtocol.reset()
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await spots.fetchIndex(force: true)
        XCTAssertEqual(offline.count, 2)
        let decodes = await spots.feedIndexDecodeCount
        XCTAssertEqual(decodes, 1, "圏外のたびに索引を解析し直している")
    }

    /// アプリを開き直した後（解析した結果をまだ持っていない入れ物）は、304 で控えを1回だけ解析する
    func testFreshServiceParsesTheSnapshotOnceOnNotModified() async throws {
        let prefix = UUID().uuidString
        serve(etag: #""v1""#)
        _ = try await service(prefix: prefix).fetchIndex()

        let reopened = service(prefix: prefix)
        serveNotModified()
        let first = try await reopened.fetchIndex(force: true)
        XCTAssertEqual(first.count, 2, "304 で端末の控えを返していない")
        serveNotModified()
        _ = try await reopened.fetchIndex(force: true)
        let decodes = await reopened.feedIndexDecodeCount
        XCTAssertEqual(decodes, 1, "開き直した後の 304 で、2回目も解析している")
    }

    /// 🔴 **指紋で照らす。** 別の入れ物が端末の控えを新しい索引で書き替えたあとの 304 では、
    /// 持っている古い解析結果ではなく、書き替わった控えを解析して返す
    func testRewrittenSnapshotIsParsedAgain() async throws {
        let prefix = UUID().uuidString
        let a = service(prefix: prefix)
        serve(etag: #""v1""#)
        _ = try await a.fetchIndex()

        // 別の入れ物が新しい索引（v2）を取って控えを書き替える
        serve(index: Self.renamedIndex, etag: #""v2""#)
        _ = try await service(prefix: prefix).fetchIndex()

        // a は控えの印（v2）で条件付きに取り、304 を受ける
        serveNotModified()
        let rows = try await a.fetchIndex(force: true)
        XCTAssertEqual(StubProtocol.allRequests.first?.value(forHTTPHeaderField: "If-None-Match"), #""v2""#)
        XCTAssertTrue(rows.contains { $0.name == "東京駅（丸の内）" }, "書き替わった控えではなく、古い解析結果を返している")
        let decodes = await a.feedIndexDecodeCount
        XCTAssertEqual(decodes, 2, "書き替わった控えを解析していない")
    }

    // MARK: - 壊れた索引を控えない（`fetchFeedIndex` の `.broken`）

    /// 🔴 壊れた索引（区分が全部壊れた）を受けても、控え・印・解析した結果のどれも上書きしない。
    /// 前回の良い控えを返し、次は条件なしで取る（壊れた回の印で 304 を受けない）
    func testBrokenIndexIsNeitherSavedNorRemembered() async throws {
        let prefix = UUID().uuidString
        let spots = service(prefix: prefix)
        serve(etag: #""v1""#)
        let good = try await spots.fetchIndex()
        XCTAssertEqual(good.count, 2)

        // 壊れた索引に、新しい印（v2）が付いて届く
        StubProtocol.reset()
        StubProtocol.responseHeaders = ["ETag": #""v2""#]
        StubProtocol.respond(path: indexPath, status: 200, body: #"{"v":1,"shards":[{"key":"jp-kanto"}]}"#)
        let afterBroken = try await spots.fetchIndex(force: true)
        XCTAssertEqual(afterBroken.map(\.spotId), good.map(\.spotId), "壊れた索引で前回の良い控えを出していない")

        // 端末の控えは良い索引のまま（解析した結果を持たない、開き直した入れ物で圏外）
        StubProtocol.reset()
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let reopened = service(prefix: prefix)
        let offline = try await reopened.fetchIndex()
        XCTAssertEqual(offline.map(\.spotId).sorted(), good.map(\.spotId).sorted(), "壊れた索引で控えを上書きしている")

        // 次の取得は条件なし（壊れた回の印 v2 も、前の印 v1 も送らない）
        serve(etag: nil)
        _ = try await spots.fetchIndex(force: true)
        XCTAssertNil(StubProtocol.allRequests.first?.value(forHTTPHeaderField: "If-None-Match"),
                     "壊れた索引の後も条件付きで取っている（304 で壊れた回を「変わっていない」と扱いうる）")
    }

    /// 壊れた索引の後の圏外は、持っている良い解析結果をそのまま使う（壊れた中身を解析結果として持っていない）
    func testBrokenIndexDoesNotReplaceTheParsedIndex() async throws {
        let spots = service(prefix: UUID().uuidString)
        serve(etag: #""v1""#)
        let good = try await spots.fetchIndex()
        StubProtocol.reset()
        StubProtocol.respond(path: indexPath, status: 200, body: #"{"v":1,"shards":[{"key":"jp-kanto","spots":[{"spotId":1}]}]}"#)
        _ = try await spots.fetchIndex(force: true)
        StubProtocol.reset()
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await spots.fetchIndex(force: true)
        XCTAssertEqual(offline.map(\.spotId), good.map(\.spotId))
        // 良い索引 1回 + 壊れた索引 1回。控えに戻るときは解析し直さない
        let decodes = await spots.feedIndexDecodeCount
        XCTAssertEqual(decodes, 2)
    }

    // MARK: - 1回の解析で JSON を1度だけ読む

    /// 🔴 索引の解析は `JSONDecoder` を1回だけ呼ぶ（前は版を読む復号と全体を読む復号の2回）
    func testDecodeFeedIndexParsesTheJSONOnce() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Services/OfficialSpotService.swift"),
                              encoding: .utf8)
        let start = try XCTUnwrap(text.range(of: "static func decodeFeedIndex(_ data: Data) -> FeedIndexDecoding {"))
        let end = try XCTUnwrap(text.range(of: "static func isSafeKey(", range: start.upperBound..<text.endIndex))
        let body = String(text[start.upperBound..<end.lowerBound])
        XCTAssertEqual(body.components(separatedBy: "JSONDecoder.api.decode(").count - 1, 1,
                       "索引の JSON を2度以上解析している")
    }

    /// 1回で読むようにしても、版の扱いは前と同じ: 知らない版は**形が違っても**古い置き場へ（壊れた扱いにしない）。
    /// 版が無い・数でない・中身が JSON でないのは壊れた扱い。知っている版で区分が読めなければ壊れた扱い
    func testVersionHandlingIsUnchanged() {
        func kind(_ json: String) -> String {
            switch OfficialSpotService.decodeFeedIndex(Data(json.utf8)) {
            case .ok: return "ok"
            case .unknownVersion: return "unknown"
            case .broken: return "broken"
            }
        }
        XCTAssertEqual(kind(#"{"v":2,"shards":"新しい形"}"#), "unknown")
        XCTAssertEqual(kind(#"{"v":2}"#), "unknown")
        XCTAssertEqual(kind(#"{"v":2,"shards":[]}"#), "unknown")
        XCTAssertEqual(kind(#"{"shards":[]}"#), "broken")
        XCTAssertEqual(kind(#"{"v":"1","shards":[]}"#), "broken")
        XCTAssertEqual(kind("<html>login</html>"), "broken")
        XCTAssertEqual(kind(#"{"v":1}"#), "broken")
        XCTAssertEqual(kind(#"{"v":1,"shards":"違う形"}"#), "broken")
        XCTAssertEqual(kind(#"{"v":1,"shards":[]}"#), "ok")
        XCTAssertEqual(kind(SpotFeedShardsTests.index()), "ok")
        // 大きな索引（本番と同じくらい）も同じ結果
        if case .ok(let parsed) = OfficialSpotService.decodeFeedIndex(SpotIndexPerfTests.largeIndex()) {
            XCTAssertEqual(parsed.rows.count, 68 * 42)
            XCTAssertEqual(parsed.table.count, 68)
        } else {
            XCTFail("大きな索引が読めない")
        }
    }
}
