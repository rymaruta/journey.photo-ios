import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 「サインインの方法」（札 #601・2026-11-23 owner「設定に『サインインの方法』を足し、Apple と Google を解除できるようにする」）。
///
/// - 口が無いサーバー（Apple のスタックを配っていない本番）では設定の行を出さない（`list` が nil）
/// - 解除は `DELETE /user/signin-methods/{provider}`。最後の1つはサーバーが断り、その文をそのまま出す
/// - 文は「外す」ではなく「解除」（2026-11-23 owner）。中黒で区切らない
/// - 知らせ（`{type: "signin_methods"}`）を押すとこの画面が開く
@MainActor
final class SigninMethodsTests: XCTestCase {

    private func api() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "https://api.example.test")!,
                         tokenProvider: StubTokenProvider(token: "t"),
                         session: URLSession(configuration: config))
    }

    override func setUp() async throws {
        try await super.setUp()
        StubProtocol.reset()
    }

    override func tearDown() async throws {
        StubProtocol.reset()
        try await super.tearDown()
    }

    private let sample = #"""
    {"methods":[{"id":"email","linked":true,"removable":false,"email":"taro@example.com"},
    {"id":"apple","linked":true,"removable":true},
    {"id":"google","linked":false,"removable":false}]}
    """#

    // MARK: - サーバー

    func testListReadsMethodsWithAuth() async throws {
        StubProtocol.respond(path: "/user/signin-methods", status: 200, body: sample)
        let list = try await SigninMethodsService(api: api()).list()
        XCTAssertEqual(list, [
            SigninMethod(id: "email", linked: true, removable: false, email: "taro@example.com"),
            SigninMethod(id: "apple", linked: true, removable: true),
            SigninMethod(id: "google", linked: false, removable: false),
        ])
        XCTAssertEqual(StubProtocol.requests, ["GET /user/signin-methods"])
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer t", "ログインが要る口")
    }

    /// 🔴 口が無いサーバー（道の無い 404）は nil＝設定の行を出さない。ほかの失敗は投げる（行を出さないのと見分ける）
    func testMissingRouteMeansNoRow() async throws {
        StubProtocol.respond(path: "/elsewhere", status: 200, body: "{}")
        let missing = try await SigninMethodsService(api: api()).list()
        XCTAssertNil(missing)

        StubProtocol.reset()
        StubProtocol.respond(path: "/user/signin-methods", status: 500, body: #"{"error":"読み込めませんでした"}"#)
        do {
            _ = try await SigninMethodsService(api: api()).list()
            XCTFail("500 を口が無いと取り違えている")
        } catch {}
    }

    func testRemoveCallsDeleteAndShowsServerReasonWhenRefused() async throws {
        StubProtocol.respond(path: "/user/signin-methods/apple", status: 200,
                             body: #"{"methods":[{"id":"email","linked":true,"removable":false},{"id":"apple","linked":false,"removable":false}]}"#)
        let after = try await SigninMethodsService(api: api()).remove(.apple)
        XCTAssertEqual(StubProtocol.requests, ["DELETE /user/signin-methods/apple"])
        XCTAssertEqual(after.first { $0.id == "apple" }?.linked, false)

        StubProtocol.reset()
        let reason = "ほかに入る方法が無いので解除できません。ログイン画面の「パスワードを忘れた」から、パスワードを設定できます"
        StubProtocol.respond(path: "/user/signin-methods/google", status: 409,
                             body: #"{"error":"\#(reason)","code":"last_signin_method"}"#)
        do {
            _ = try await SigninMethodsService(api: api()).remove(.google)
            XCTFail("断られたのに通っている")
        } catch {
            XCTAssertEqual(error.localizedDescription, reason, "サーバーの理由をそのまま出す")
        }
    }

    // MARK: - 文

    func testWordingUsesKaijo() async {
        XCTAssertEqual(SigninMethodsText.title, "サインインの方法")
        XCTAssertEqual(SigninMethodsText.removeButton, "解除")
        XCTAssertEqual(SigninMethodsText.confirmTitle(.apple), "Apple の連携を解除しますか")
        XCTAssertEqual(SigninMethodsText.confirmTitle(.google), "Google の連携を解除しますか")
        XCTAssertEqual(SigninMethodsText.confirmButton, "解除する")
        let all = [SigninMethodsText.title, SigninMethodsText.removeButton, SigninMethodsText.removing,
                   SigninMethodsText.confirmTitle(.apple), SigninMethodsText.confirmMessage(.apple),
                   SigninMethodsText.confirmButton, SigninMethodsText.loadFailed,
                   SigninMethodsText.detail(SigninMethod(id: "apple", linked: true, removable: true)),
                   SigninMethodsText.detail(SigninMethod(id: "email", linked: false, removable: false, email: "a@b.c")),
                   SigninMethodsText.detail(SigninMethod(id: "email", linked: false, removable: false))]
        for text in all {
            XCTAssertFalse(text.contains("・"), "中黒で区切っている: \(text)")
            XCTAssertFalse(text.contains("外す") || text.contains("外せ"), "「外す」ではなく「解除」: \(text)")
        }
    }

    /// 状態を色だけでなく文字で言う。メールは、連携していればアドレス、パスワードが無ければそう言う
    func testDetailSpellsOutState() async {
        XCTAssertEqual(SigninMethodsText.detail(SigninMethod(id: "apple", linked: true, removable: true)), "連携しています")
        XCTAssertEqual(SigninMethodsText.detail(SigninMethod(id: "google", linked: false, removable: false)), "連携していません")
        XCTAssertEqual(SigninMethodsText.detail(SigninMethod(id: "email", linked: true, removable: false, email: "a@b.c")), "a@b.c")
        // 2026-11-23 確かめ役の見直し: アドレスと短い状態だけ。道の説明は解除できない行の理由の側だけ
        XCTAssertEqual(SigninMethodsText.detail(SigninMethod(id: "email", linked: false, removable: false, email: "a@b.c")),
                       "a@b.c（パスワードはまだありません）")
        XCTAssertEqual(SigninMethodsText.detail(SigninMethod(id: "email", linked: false, removable: false)),
                       "メールアドレスは登録されていません")
        for method in [SigninMethod(id: "email", linked: false, removable: false, email: "a@b.c"),
                       SigninMethod(id: "email", linked: false, removable: false)] {
            let text = SigninMethodsText.detail(method)
            XCTAssertFalse(text.contains("パスワードを忘れた") || text.contains("問い合わせ"), "道の説明が理由の側と重なっている: \(text)")
        }
    }

    /// 失敗の文（2026-11-23 確かめ役の指摘: `localizedDescription` をそのまま出さない）。
    /// 圏外は決まった文、サーバーが理由を書いた断りはその文、ほかは決まった文
    func testFailureTextIsFixedForNetworkAndUnknown() async {
        XCTAssertEqual(SigninMethodsText.failure(APIError.unreachable, fallback: "x"), SigninMethodsText.unreachable)
        XCTAssertEqual(SigninMethodsText.failure(URLError(.notConnectedToInternet), fallback: "x"), SigninMethodsText.unreachable)
        XCTAssertEqual(SigninMethodsText.failure(URLError(.timedOut), fallback: "x"), SigninMethodsText.unreachable)
        XCTAssertEqual(SigninMethodsText.failure(APIError.server(status: 409, message: "理由"), fallback: "x"), "理由")
        XCTAssertEqual(SigninMethodsText.failure(APIError.server(status: 503, message: "今は解除できません"), fallback: "x"), "今は解除できません")
        XCTAssertEqual(SigninMethodsText.failure(APIError.server(status: 500, message: "Internal"), fallback: "決まった文"), "決まった文")
        XCTAssertEqual(SigninMethodsText.failure(APIError.decoding("bad"), fallback: "決まった文"), "決まった文")
        XCTAssertEqual(SigninMethodsText.failure(CocoaError(.fileNoSuchFile), fallback: "決まった文"), "決まった文")
        XCTAssertEqual(SigninMethodsText.unreachable, "通信できませんでした。電波の届く所でもう一度お試しください")
    }

    /// 失敗の文には板の失敗の印（丸に「!」）を添える（色だけで伝えない）
    func testFailureShowsMark() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Settings/SigninMethodsView.swift")
        let view = try String(contentsOf: url, encoding: .utf8)
        guard let at = view.range(of: "if let errorMessage {") else { return XCTFail("失敗の文が無い") }
        let block = String(view[at.upperBound...].prefix(700))
        XCTAssertTrue(block.contains("Image(systemName: \"exclamationmark.circle\")"), "失敗の印が無い")
        XCTAssertFalse(view.contains("error.localizedDescription"), "失敗の文に localizedDescription をそのまま出している")
    }

    // MARK: - 知らせから開く

    func testPushOpensSigninMethods() async {
        XCTAssertTrue(NotificationRouter.isSigninMethods(["type": "signin_methods", "aps": [:]]))
        XCTAssertFalse(NotificationRouter.isSigninMethods(["type": "like"]))
        XCTAssertFalse(NotificationRouter.isSigninMethods([:]))

        let router = NotificationRouter.shared
        _ = router.takeSigninMethods()
        let before = router.signinMethodsRequests
        router.openSigninMethods()
        XCTAssertEqual(router.signinMethodsRequests, before + 1)
        XCTAssertTrue(router.takeSigninMethods())
        XCTAssertFalse(router.takeSigninMethods(), "受け取るのは1回だけ")
    }

    // MARK: - 見本の通信（UI テストの絵）

    func testPreviewReplies() async {
        guard case let .some(reply) = PreviewBackend.signinMethodsReply(method: "GET", parts: ["user", "signin-methods"], shape: "last"),
              let json = try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any],
              let methods = json["methods"] as? [[String: Any]] else { return XCTFail("見本の答えが無い") }
        let apple = methods.first { $0["id"] as? String == "apple" }
        XCTAssertEqual(apple?["removable"] as? Bool, false)
        XCTAssertNotNil(apple?["blockedReason"])
        XCTAssertEqual(PreviewBackend.signinMethodsReply(method: "DELETE", parts: ["user", "signin-methods", "apple"], shape: "last")?.status, 409)
        XCTAssertEqual(PreviewBackend.signinMethodsReply(method: "DELETE", parts: ["user", "signin-methods", "apple"], shape: "linked")?.status, 200)
    }
}
