import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 読むたびにサーバーの中身で置き換える（2026-10-17: 投稿から24時間以内に削除・非公開にした写真のラベルは、
/// 手持ちからも貼ったラベルからも消える）。端末に消えたラベルが残らない
final class TrunkReloadTests: XCTestCase {

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

    private func label(_ id: String) -> String {
        #"{"id":"\#(id)","kind":"place","place":{"name":"京都"},"seed":1,"at":"2026-10-17T00:00:00Z"}"#
    }

    @MainActor
    func testReloadDropsLabelsTheServerRevoked() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil)
        model.bind(TrunkService(api: api))
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[\#(label("p-1")),\#(label("p-2"))],"stuck":[\#(label("s-1")),\#(label("s-2"))],"posts":5}"#,
                                         once: true)]
        await model.load(offline: false)
        XCTAssertEqual(model.state?.pocket.count, 2)
        XCTAssertEqual(model.state?.stuck.count, 2)
        // サーバーが p-2 と s-1 を取り消した（削除・非公開）
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[\#(label("p-1"))],"stuck":[\#(label("s-2"))]}"#)]
        await model.load(offline: false)
        XCTAssertEqual(model.state?.pocket.map(\.id), ["p-1"], "取り消された手持ちのラベルが残っている")
        XCTAssertEqual(model.state?.stuck.map(\.id), ["s-2"], "取り消された貼ったラベルが残っている")
        XCTAssertEqual(model.state?.posts, 5, "引き継ぐのは投稿の数だけ")
        // 手持ちも貼ったものも空になったら空のまま（前の中身を混ぜない）
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[]}"#)]
        await model.load(offline: false)
        XCTAssertTrue(model.isEmpty)
    }
}
