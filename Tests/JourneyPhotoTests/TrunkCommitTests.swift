import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 自分の手で貼る画面の保存（2026-10-17 の見直し）: 予定はラベルごと・書き込みの最中でも落とさない
final class TrunkCommitTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        session = URLSession(configuration: config)
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    func testPendingPlacesAreKeptPerLabel() {
        var p = TrunkPendingPlaces()
        let a0 = TrunkPos(x: 0.1, y: 0.1, rot: 0), b0 = TrunkPos(x: 0.5, y: 0.5, rot: 0)
        p.note("a", from: a0, to: TrunkPos(x: 0.1, y: 0.1, rot: 8))
        p.note("b", from: b0, to: TrunkPos(x: 0.5, y: 0.5, rot: -8))
        p.note("a", from: TrunkPos(x: 0.9, y: 0.9, rot: 0), to: TrunkPos(x: 0.1, y: 0.1, rot: 16))
        XCTAssertEqual(p.ids, ["a", "b"], "別のラベルを回したら前の予定が消えた")
        XCTAssertEqual(p["a"]?.from, a0, "はじめの置き場を上書きした（戻す1手が狂う）")
        XCTAssertEqual(p.overrides["a"]?.rot, 16)
        // 送っている間にまた回した: 古い値の返事では消さない
        p.done("a", sent: TrunkPos(x: 0.1, y: 0.1, rot: 8))
        XCTAssertNotNil(p["a"], "送ったあとに回した分を捨てた")
        p.done("a", sent: TrunkPos(x: 0.1, y: 0.1, rot: 16))
        XCTAssertNil(p["a"])
        XCTAssertFalse(p.isEmpty)
    }

    private func label(_ id: String) -> String {
        #"{"id":"\#(id)","kind":"place","place":{"name":"京都"},"seed":1,"at":"2026-10-17T00:00:00Z"}"#
    }

    /// 🔴 書き込みの最中に置き直しても、黙って捨てずに、終わるのを待って送る
    @MainActor
    func testPlaceWaitsForTheOtherWrite() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil)
        model.bind(TrunkService(api: api))
        let body = #"{"pocket":[],"stuck":[\#(label("s-1")),\#(label("s-2"))]}"#
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200, body: body)]
        await model.load(offline: false)
        async let first = model.placeWhenFree("s-1", at: TrunkPos(x: 0.2, y: 0.2, rot: 8))
        async let second = model.placeWhenFree("s-2", at: TrunkPos(x: 0.6, y: 0.6, rot: -8))
        let results = await [first, second]
        XCTAssertEqual(results, [.saved, .saved], "書き込みの最中だった方を捨てた")
        let puts = ScriptedProtocol.calls.filter { $0.method == "PUT" }.map(\.path)
        XCTAssertEqual(Set(puts), ["/user/trunk/labels/s-1/place", "/user/trunk/labels/s-2/place"])
    }

    /// 断られたら refused（画面は置き場を戻す）
    @MainActor
    func testPlaceRefused() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil)
        model.bind(TrunkService(api: api))
        ScriptedProtocol.script = [
            .init(match: "/place", status: 409, body: #"{"error":"まだ貼っていないラベルです","code":"notStuck"}"#),
            .init(match: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[\#(label("s-1"))]}"#),
        ]
        await model.load(offline: false)
        let r = await model.placeWhenFree("s-1", at: TrunkPos(x: 0.2, y: 0.2, rot: 8))
        XCTAssertEqual(r, .refused)
        XCTAssertEqual(model.actionError, TrunkText.refusal(code: "notStuck", fallback: ""))
    }

    /// 🔴 同じラベルに古い置き場と新しい置き場が続けて頼まれたら、新しい方だけが送る
    /// （閉じたあとの送り残しと、開き直した画面の新しい置き場がぶつかっても古い値で上書きしない）
    func testNewerPlaceWinsForTheSameLabel() {
        var t = TrunkPlaceTickets()
        let old = t.issue("s-1")
        let other = t.issue("s-2")
        let new = t.issue("s-1")
        XCTAssertFalse(t.isLatest("s-1", old), "古い頼みも送る")
        XCTAssertTrue(t.isLatest("s-1", new))
        XCTAssertTrue(t.isLatest("s-2", other), "別のラベルの頼みを止めた")
    }

    /// 圏外（断りではない失敗）は failed（画面は置き場を残して、閉じずに一言）
    @MainActor
    func testPlaceFailedIsNotRefused() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil)
        model.bind(TrunkService(api: api))
        ScriptedProtocol.script = [
            .init(match: "/place", status: 500, body: #"{"error":"x"}"#),
            .init(match: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[\#(label("s-1"))]}"#),
        ]
        await model.load(offline: false)
        let r = await model.placeWhenFree("s-1", at: TrunkPos(x: 0.2, y: 0.2, rot: 8))
        XCTAssertEqual(r, .failed, "やり直せる失敗を「断られた」と数えた（置き場が黙って消える）")
        XCTAssertFalse(TrunkText.placeNotSaved.isEmpty)
    }
}
