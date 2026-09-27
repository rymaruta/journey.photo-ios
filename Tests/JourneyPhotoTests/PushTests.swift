import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 端末トークンの形。
///
/// **`Data.description` を使わない。** iOS 15 までは `<a1b2 c3d4>`、
/// それ以降は `32 bytes` が返る——どちらを送ってもサーバーに弾かれ、
/// 「許可したのに通知が来ない」という調べにくい形になる。
final class PushTokenTests: XCTestCase {

    func testTokenIsLowercaseHexWithoutSeparators() {
        let data = Data([0x0a, 0x1b, 0xff, 0x00])
        XCTAssertEqual(PushToken.hex(from: data), "0a1bff00")
    }

    func testEveryByteIsTwoCharacters() {
        // **0 埋めを落とさない。** 落とすと長さが変わり、別の端末の
        // トークンと衝突しうる
        XCTAssertEqual(PushToken.hex(from: Data([0x01, 0x02])), "0102")
        XCTAssertEqual(PushToken.hex(from: Data(repeating: 0xab, count: 32)).count, 64)
    }

    /// サーバー（`api-user/src/devices.ts` の `isDeviceToken`）と同じ判定。
    func testOnlyHexOfTheRightLengthIsSent() {
        XCTAssertTrue(PushToken.isValid(String(repeating: "a", count: 64)))
        XCTAssertFalse(PushToken.isValid(""))
        XCTAssertFalse(PushToken.isValid("<a1b2 c3d4>"), "iOS 15 までの description の形")
        XCTAssertFalse(PushToken.isValid("32 bytes"), "iOS 15 以降の description の形")
        XCTAssertFalse(PushToken.isValid(String(repeating: "a", count: 16)), "短すぎる")
        // **全角を通さない。** Swift の `isHexDigit` は `ａ` も `９` も真に
        // するので、それだけに頼るとサーバーの
        // `/^[0-9a-f]{32,200}$/i` と食い違い、**通らない要求を出す**
        XCTAssertFalse(PushToken.isValid(String(repeating: "ａ", count: 64)),
                       "全角の a を通している")
        XCTAssertFalse(PushToken.isValid(String(repeating: "９", count: 64)),
                       "全角の 9 を通している")
    }
}

/// 宛先の預け方。
@MainActor
final class PushServiceTests: XCTestCase {

    private var session: URLSession!

    private func prepare() {
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

    private func service(token: String? = "t") -> PushService {
        PushService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                   tokenProvider: StubTokenProvider(token: token),
                                   session: session))
    }

    func testRegisterSendsTheTokenToTheServer() async throws {
        prepare()
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)

        try await service().register(token: String(repeating: "a", count: 64))

        let request = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/user/devices")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["token"] as? String, String(repeating: "a", count: 64))
    }

    /// **ログアウトの前に外す。** あとだと認証が通らず、外せないまま
    /// 次にこの端末を使う人へ前の人あての通知が飛ぶ。
    func testUnregisterUsesDelete() async throws {
        prepare()
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)

        try await service().unregister(token: String(repeating: "b", count: 64))

        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/devices")
    }

    /// 未ログインでは投げる（呼び出し側が握り潰す）。
    func testWithoutSignInItFails() async {
        prepare()
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        do {
            try await service(token: nil).register(token: String(repeating: "a", count: 64))
            XCTFail("投げるはず")
        } catch {
            XCTAssertNil(StubProtocol.lastRequest, "サーバーを叩く前に止まる")
        }
    }
}

/// 「受け取る」の意思。
///
/// **画面の拠り所をどこに置くかで3通りの壊れ方がある**（全部踏んだ）:
/// - 「預けられたか」で見る → APNs のトークンは遅れて届くので、押した直後は
///   必ずオフに戻る
/// - 「端末の許可」で見る → 自分でオフにしたのに、再起動で復活する
///   （OS の許可は残るため）
/// - どこにも残さない → 再起動のたびに判断できない
@MainActor
final class PushIntentTests: XCTestCase {

    private func center(_ suite: String) -> (PushCenter, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (PushCenter(service: { PushService(api: APIClient(tokenProvider: StubTokenProvider(token: nil))) },
                           defaults: defaults), defaults)
    }

    func testStartsOff() async {
        let (push, _) = center("push-1")
        XCTAssertFalse(push.isEnabled)
    }

    /// **オフにした意思は残る**（次の起動で勝手に復活しない）。
    func testTurningOffSurvivesRelaunch() async {
        let (push, defaults) = center("push-2")
        defaults.set(true, forKey: "photo-gallery-push-enabled")

        let reopened = PushCenter(service: { PushService(api: APIClient(tokenProvider: StubTokenProvider(token: nil))) },
                                  defaults: defaults)
        XCTAssertTrue(reopened.isEnabled, "オンのまま開き直せる")

        await reopened.disable()
        let again = PushCenter(service: { PushService(api: APIClient(tokenProvider: StubTokenProvider(token: nil))) },
                               defaults: defaults)
        XCTAssertFalse(again.isEnabled, "オフにしたら、次の起動でもオフ")
        _ = push
    }

    /// 🔴 **「受け取る」は人ごと。** 前の人がオンにしたまま次の人がログインしても、
    /// 次の人はオンにならない（本人が何もしていないのに宛先を登録しない）
    func testIntentIsPerUser() async {
        let (push, defaults) = center("push-3")
        defaults.set(true, forKey: "photo-gallery-push-enabled.a")
        await push.use(userId: "b")
        XCTAssertFalse(push.isEnabled, "前の人のオンが次の人に移っている")
        await push.use(userId: "a")
        XCTAssertTrue(push.isEnabled)
    }

    /// 人ごとの鍵でも「オフにした」は次の起動まで残る
    func testTurningOffSurvivesRelaunchPerUser() async {
        let (push, defaults) = center("push-5")
        defaults.set(true, forKey: "photo-gallery-push-enabled.a")
        await push.use(userId: "a")
        XCTAssertTrue(push.isEnabled)
        await push.disable()
        let reopened = PushCenter(service: { PushService(api: APIClient(tokenProvider: StubTokenProvider(token: nil))) },
                                  defaults: defaults)
        await reopened.use(userId: "a")
        XCTAssertFalse(reopened.isEnabled, "オフにしたのに次の起動で戻っている")
    }

    /// 更新前に端末共通の鍵でオンにしていた人は、最初のログインでそのまま引き継ぐ（一度だけ）
    func testLegacyIntentMovesToTheFirstUserOnce() async {
        let (push, defaults) = center("push-4")
        defaults.set(true, forKey: "photo-gallery-push-enabled")
        await push.use(userId: "a")
        XCTAssertTrue(push.isEnabled)
        await push.use(userId: "b")
        XCTAssertFalse(push.isEnabled, "昔の鍵が次の人にも効いている")
    }
}

/// 通知を押したときの行き先。
///
/// **真偽値にしない**——お知らせタブを開いたまま2回続けて押すと、
/// 「変わっていない」と見なされて2回目が効かなくなる。画面側は
/// この数を `.task(id:)` に渡して読み直している。
@MainActor
final class NotificationRouterTests: XCTestCase {

    /// 共有の1つを使うので、**前の試験が残した「押された」印を消してから**使う
    private func freshRouter() -> NotificationRouter {
        let router = NotificationRouter.shared
        _ = router.takePendingActivity()
        return router
    }

    func testEachTapIsDistinguishable() async {
        let router = freshRouter()
        let before = router.openActivityRequests
        router.openActivity()
        router.openActivity()
        XCTAssertEqual(router.openActivityRequests, before + 2,
                       "2回押したのに1回ぶんしか数えていない")
        _ = router.takePendingActivity()
    }

    /// **画面が居ない間に押した分を落とさない**（冷えた起動・規約の同意画面）。
    /// 画面が出てきたときに1回だけ受け取れる
    func testTapBeforeTheScreenExistsIsKeptUntilTaken() async {
        let router = freshRouter()
        router.openActivity()
        XCTAssertTrue(router.takePendingActivity(), "画面が出る前に押した分が残っていない")
        XCTAssertFalse(router.takePendingActivity(), "同じ1回を2度開いている")
    }

    /// アプリを開いている間に届いた通知は、ベルの数え直しの合図になる
    func testArrivalWhileOpenIsSignalled() async {
        let router = freshRouter()
        let before = router.arrivals
        router.noteArrival()
        XCTAssertEqual(router.arrivals, before + 1)
        XCTAssertFalse(router.takePendingActivity(), "届いただけで（押していないのに）お知らせを開いている")
    }

    /// 既読にできたことは合図になる（ベルを 0 にする）。押した扱いにはしない
    func testMarkingReadIsSignalledWithoutOpening() async {
        let router = freshRouter()
        let before = router.readMarks
        router.noteRead()
        XCTAssertEqual(router.readMarks, before + 1)
        XCTAssertFalse(router.takePendingActivity())
    }
}
