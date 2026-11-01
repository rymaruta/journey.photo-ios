import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 撮影スポットの索引の解析の重さを数で見る（2026-10-31・札 #429 アプリ 1・3）。
///
/// 本番の索引（`spot-feed/index.json`）は 2026-10-31 に curl で見て **約 1.1MB・68 区分・2,853 件**。
/// 同じくらいの大きさの索引を作り、
///
/// - 索引を1回解析する時間（`decodeFeedIndex`）
/// - **サーバーが「変わっていない（304）」と答えた回**の取り直しの時間（`fetchIndex(force: true)`）
///
/// を `measure` で測る。数は試験のログ（`measured [Time, seconds] average: …`）と、Mac の結果（xcresult）に残る。
/// 合否は付けない（時間で落とすと、Mac の混み具合で赤くなる）。速くなったかは前後の数で比べる
final class SpotIndexPerfTests: XCTestCase {

    private var session: URLSession!
    private let url = URL(string: "https://site.example.test/app/data/spots.json")!
    private var prefixes: [String] = []
    private var legacyNames: [String] = []

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
        for name in prefixes.map({ "\($0)-index.json" }) + legacyNames {
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

    /// 本番と同じくらいの索引（68 区分 × 42 件 = 2,856 件・約 1MB）。
    /// 区分の `bytes` は大きめにして、詳細の和が `detailPrefetchBudget` を超える形にする
    /// （索引のあとに区分を全部読みに行かない＝索引の解析だけを測る）
    static func largeIndex(shards: Int = 68, perShard: Int = 42) -> Data {
        var parts: [String] = []
        for s in 0..<shards {
            var rows: [String] = []
            for r in 0..<perShard {
                let n = s * perShard + r
                let hex = String(n, radix: 16)
                let id = String(repeating: "0", count: max(0, 12 - hex.count)) + hex
                rows.append("""
                {"spotId":"sp_\(id)","slug":"spot-\(n)","name":"撮影スポット\(n)","nameEn":"Spot \(n)",\
                "reading":"さつえいすぽっと\(n)","aliases":["別名\(n)","Alias \(n)"],\
                "region":{"country":"日本","prefecture":"東京都","city":"千代田区"},\
                "coords":{"lat":\(35.0 + Double(r) * 0.01),"lng":\(139.0 + Double(s) * 0.01)},"category":"建築",\
                "stage":"published","seasons":["spring","autumn"],"times":["dusk"],"hasImage":true}
                """)
            }
            parts.append(#"{"key":"area-\#(s)","count":\#(perShard),"bytes":40000,"hash":"h\#(s)","spots":[\#(rows.joined(separator: ","))]}"#)
        }
        return Data(#"{"v":1,"shards":[\#(parts.joined(separator: ","))]}"#.utf8)
    }

    func service(prefix: String = UUID().uuidString) -> OfficialSpotService {
        prefixes.append(prefix)
        let legacy = UUID().uuidString
        legacyNames.append(legacy)
        return OfficialSpotService(url: url, session: session, snapshot: SpotSnapshotStore(fileName: legacy),
                                   feedSnapshotPrefix: prefix)
    }

    /// 作った索引が本番と同じくらいの大きさで、読めること（測る前提）
    func testLargeIndexIsRealisticAndDecodes() throws {
        let data = Self.largeIndex()
        XCTAssertGreaterThan(data.count, 900_000, "本番（約 1.1MB）より小さすぎる")
        guard case .ok(let parsed) = OfficialSpotService.decodeFeedIndex(data) else {
            return XCTFail("作った索引が読めない")
        }
        XCTAssertEqual(parsed.rows.count, 68 * 42)
        XCTAssertEqual(parsed.dropped, 0)
    }

    /// 索引を1回解析する時間
    func testMeasureDecodeFeedIndex() {
        let data = Self.largeIndex()
        measure {
            _ = OfficialSpotService.decodeFeedIndex(data)
        }
    }

    /// サーバーが「変わっていない（304）」と答えた回の取り直し（60秒の控えを過ぎた・引き下げた回）
    func testMeasureNotModifiedRefetch() {
        let spots = service()
        StubProtocol.responseHeaders = ["ETag": #""v1""#]
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 200,
                             body: String(decoding: Self.largeIndex(), as: UTF8.self))
        let first = expectation(description: "1回目")
        Task {
            let rows = try? await spots.fetchIndex()
            XCTAssertEqual(rows?.count, 68 * 42, "1回目に索引が読めない")
            first.fulfill()
        }
        wait(for: [first], timeout: 60)

        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/spot-feed/index.json", status: 304, body: "")
        measure {
            let done = expectation(description: "304 の取り直し")
            Task {
                let rows = try? await spots.fetchIndex(force: true)
                XCTAssertEqual(rows?.count, 68 * 42, "304 で控えの索引を返していない")
                done.fulfill()
            }
            wait(for: [done], timeout: 60)
        }
        // 304 のほかに叩いていない（区分を読みに行っていない＝索引だけを測れている）
        XCTAssertTrue(StubProtocol.requests.allSatisfy { $0 == "GET /app/data/spot-feed/index.json" },
                      "索引のほかに叩いている: \(StubProtocol.requests)")
    }
}
