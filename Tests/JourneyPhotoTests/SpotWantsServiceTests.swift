import XCTest
@testable import JourneyPhoto

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// みんなの「行きたい」の読み込み（`SpotWantsService.file`）。その日のあいだ覚える・日をまたいだら読み直す・
/// 読めなかった（404 など）回は覚えない（2026-11-11 確かめ役の指摘 11）。海外は数だけ（順位なし）
final class SpotWantsServiceTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private final class Day: @unchecked Sendable { var value = "2026-11-11" }

    private let body = """
    {"month":"2026-11","updatedAt":"x","spots":[{"slug":"a","name":"A","n":20,"rank":1},{"slug":"louvre","name":"L","n":30}]}
    """

    private func service(_ day: Day) -> SpotWantsService {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        return SpotWantsService(api: api, session: session,
                                url: { URL(string: "https://site.example.test/app/data/spot-wants.json")! },
                                today: { day.value })
    }

    func testRemembersForTheDayAndReadsAgainNextDay() async throws {
        let day = Day()
        let s = service(day)
        StubProtocol.respond(status: 200, body: body, contentType: "application/json")
        let first = await s.file()
        XCTAssertEqual(first?.shown.count, 2)
        StubProtocol.respond(status: 500, body: "")
        let same = await s.file()
        XCTAssertEqual(same?.shown.count, 2, "同じ日は覚えた中身")
        day.value = "2026-11-12"
        let next = await s.file()
        XCTAssertNil(next, "日をまたいだら読み直す（読めなければ出さない）")
    }

    func testDoesNotRememberMissingFile() async throws {
        let s = service(Day())
        StubProtocol.respond(status: 404, body: "Not Found")
        let missing = await s.file()
        XCTAssertNil(missing)
        StubProtocol.respond(status: 200, body: body, contentType: "application/json")
        let later = await s.file()
        XCTAssertEqual(later?.entry(slug: "a")?.rank, 1, "無かった回を覚え続けない")
    }

    func testAbroadHasCountButNoRank() throws {
        let file = try XCTUnwrap(SpotWants.decode(Data(body.utf8)))
        XCTAssertEqual(SpotWants.line(try XCTUnwrap(file.entry(slug: "louvre"))), "今月の行きたい 30")
        XCTAssertEqual(SpotWants.line(try XCTUnwrap(file.entry(slug: "a"))), "今月の行きたい 20\u{2002}全国1位")
    }
}
