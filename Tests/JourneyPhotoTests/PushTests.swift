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

/// 🔴 **前の人の宛先を、次にログインした人で外す**（バグ探し 2026-09-27 #6）。
///
/// サーバーの `DELETE /user/devices` はその人の集合からしか消せず、前の持ち主から
/// 外せるのは `POST` だけ（`devices.ts` の `releasePreviousOwner`）。この端末を
/// 最後に登録した人（`photo-gallery-push-owner`）が残っていたら、次の人で
/// 「登録してから外す」を流す。
@MainActor
final class PushTakeoverTests: XCTestCase {

    private let token = Data(repeating: 0xab, count: 32)
    private let ownerKey = "photo-gallery-push-owner"
    private func center(_ defaults: UserDefaults) -> PushCenter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        return PushCenter(service: {
            PushService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                       tokenProvider: StubTokenProvider(token: "t"),
                                       session: session))
        }, defaults: defaults)
    }

    /// A がこの端末で通知を受け取っていた（サーバーの `devices#A` にトークンがある）
    private func registeredByA(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(String(repeating: "ab", count: 32), forKey: "photo-gallery-apns-token")
        defaults.set(true, forKey: "photo-gallery-push-enabled.a")
        defaults.set("a", forKey: ownerKey)
        defaults.set(true, forKey: "photo-gallery-push-owner-known")
        return defaults
    }

    override func setUp() {
        super.setUp()
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    /// 🔴 **起動時に期限切れが見つかった**（`restore` → 一度も A にならない）→
    /// B がログイン → 登録してから外す
    func testExpiredAtLaunchIsReleasedByTheNextUser() async {
        let defaults = registeredByA("push-release-1")
        let push = center(defaults)
        await push.use(userId: nil)
        StubProtocol.requests = []

        await push.use(userId: "b")

        XCTAssertEqual(StubProtocol.requests, ["POST /user/devices", "DELETE /user/devices"],
                       "前の人の宛先を外していない")
        XCTAssertNil(defaults.string(forKey: ownerKey), "外せたのに持ち主が残っている（次のログインでまた流す）")
    }

    /// 通信中の期限切れ（`expireSession` は `signingOut` を通らない）も同じ
    func testExpiredWhileSignedInIsReleasedByTheNextUser() async {
        let defaults = registeredByA("push-release-2")
        let push = center(defaults)
        await push.use(userId: "a")
        await push.use(userId: nil)
        StubProtocol.requests = []

        await push.use(userId: "b")

        XCTAssertEqual(StubProtocol.requests, ["POST /user/devices", "DELETE /user/devices"])
    }

    /// 圏外のログアウト（`signingOut` が外せなかった）も同じ
    func testFailedSignOutIsReleasedByTheNextUser() async {
        let defaults = registeredByA("push-release-3")
        let push = center(defaults)
        await push.use(userId: "a")
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        await push.signingOut()
        XCTAssertEqual(defaults.string(forKey: ownerKey), "a", "外せなかったのに持ち主を消している")
        await push.use(userId: nil)
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        StubProtocol.requests = []

        await push.use(userId: "b")

        XCTAssertEqual(StubProtocol.requests, ["POST /user/devices", "DELETE /user/devices"])
    }

    /// ふつうのログアウトで外せていたら、次の人で余計に流さない
    func testCleanSignOutNeedsNoRelease() async {
        let defaults = registeredByA("push-release-4")
        let push = center(defaults)
        await push.use(userId: "a")
        await push.signingOut()
        await push.use(userId: nil)
        StubProtocol.requests = []

        await push.use(userId: "b")

        XCTAssertEqual(StubProtocol.requests, [])
    }

    /// 🔴 **引き取ったあと外せなかった**（POST は通り DELETE が落ちた）→ 持ち主は B。
    /// 次の起動で B のまま外し直す（通知をオフにしている B に届き続けない）
    func testUnregisterRetriesOnNextLaunchWhenOnlyDeleteFailed() async {
        let defaults = registeredByA("push-release-5")
        let push = center(defaults)
        await push.use(userId: nil)
        StubProtocol.respondInOrder([(200, #"{"ok":true}"#), (500, #"{"error":"x"}"#)])
        await push.use(userId: "b")
        XCTAssertEqual(defaults.string(forKey: ownerKey), "b", "引き取ったことを覚えていない")

        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        StubProtocol.requests = []
        let relaunched = center(defaults)
        await relaunched.use(userId: "b")

        XCTAssertEqual(StubProtocol.requests, ["DELETE /user/devices"], "外し損ねをやり直していない")
        XCTAssertNil(defaults.string(forKey: ownerKey))
    }

    /// 前の人の POST が落ちたら持ち主は前の人のまま（次のログインでやり直す）
    func testReleaseRetriesAfterPostFailure() async {
        let defaults = registeredByA("push-release-6")
        let push = center(defaults)
        await push.use(userId: nil)
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        await push.use(userId: "b")
        XCTAssertEqual(defaults.string(forKey: ownerKey), "a")

        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        StubProtocol.requests = []
        let relaunched = center(defaults)
        await relaunched.use(userId: "b")

        XCTAssertEqual(StubProtocol.requests, ["POST /user/devices", "DELETE /user/devices"])
    }

    /// 🔴 **持ち主を書く前の版から上げた端末**（持ち主が分からない）。旧版で A が
    /// 受け取っていたまま期限切れになっても、次の人で引き取る
    func testUpgradedDeviceWithUnknownOwnerIsReleased() async {
        let defaults = registeredByA("push-release-8")
        defaults.removeObject(forKey: ownerKey)
        defaults.removeObject(forKey: "photo-gallery-push-owner-known")
        let push = center(defaults)
        await push.use(userId: nil)
        StubProtocol.requests = []

        await push.use(userId: "b")

        XCTAssertEqual(StubProtocol.requests, ["POST /user/devices", "DELETE /user/devices"])
        XCTAssertNil(defaults.string(forKey: ownerKey))
        // 一度引き取ったら、持ち主は分かっている（次の起動で流し直さない）
        StubProtocol.requests = []
        let relaunched = center(defaults)
        await relaunched.use(userId: "b")
        XCTAssertEqual(StubProtocol.requests, [])
    }

    /// 受け取る人が引き取るときは外さない（外すと、APNs からトークンが返らない回に
    /// その人の通知まで止まる）
    func testReceivingUserTakesOverWithoutDelete() async {
        let defaults = registeredByA("push-release-9")
        defaults.set(true, forKey: "photo-gallery-push-enabled.b")
        let push = center(defaults)
        await push.use(userId: nil)
        StubProtocol.requests = []

        await push.use(userId: "b")

        XCTAssertEqual(StubProtocol.requests, ["POST /user/devices"])
        XCTAssertEqual(defaults.string(forKey: ownerKey), "b")
    }

    /// 「受け取らない」で外せたら持ち主を消す（次の人で余計に流さない）
    func testDisableClearsTheOwner() async {
        let defaults = registeredByA("push-release-10")
        let push = center(defaults)
        await push.use(userId: "a")
        await push.disable()
        XCTAssertNil(defaults.string(forKey: ownerKey))
    }

    /// 🔴 **2つの後始末が続けて効く**（C と F1 の併合）。A の宛先が残ったまま
    /// 誰もログインしない間は端末ごと APNs から外し（`registeredOwner`）、
    /// そのあと B がログインしたらサーバーからも引き取って外す（`owner`）。
    /// 端末ごと外したときにサーバーの持ち主まで消すと、A の集合に 410 まで残る
    func testNobodyThenNextUserReleasesBothOnDeviceAndOnServer() async {
        let defaults = registeredByA("push-release-11")
        // この版で登録した端末は、2つの印が両方 A
        defaults.set("a", forKey: "photo-gallery-push-registered-owner")
        var released = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        let push = PushCenter(service: {
            PushService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                       tokenProvider: StubTokenProvider(token: "t"),
                                       session: session))
        }, defaults: defaults, releaseDevice: { released += 1 })

        await push.use(userId: nil)
        XCTAssertEqual(released, 1, "誰もログインしないのに A の宛先が届く形のまま")
        XCTAssertEqual(defaults.string(forKey: ownerKey), "a", "端末ごと外しただけでサーバーの持ち主を消した")
        XCTAssertEqual(StubProtocol.requests, [], "認証の無い間にサーバーへ送っている")

        StubProtocol.requests = []
        await push.use(userId: "b")
        XCTAssertEqual(StubProtocol.requests, ["POST /user/devices", "DELETE /user/devices"],
                       "B でサーバーから A の宛先を引き取っていない")
        XCTAssertEqual(released, 1, "印を消したのに端末ごと外し直している")
        XCTAssertNil(defaults.string(forKey: ownerKey))
        XCTAssertNil(defaults.string(forKey: "photo-gallery-push-registered-owner"))
    }

    /// 本人が戻ってきただけなら、前の人の外しは流さない
    func testSameOwnerNeedsNoRelease() async {
        let defaults = registeredByA("push-release-7")
        let push = center(defaults)
        await push.use(userId: nil)
        StubProtocol.requests = []

        await push.use(userId: "a")

        XCTAssertFalse(StubProtocol.requests.contains("POST /user/devices"), "本人から本人へ引き取っている")
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
        router.noteRead(owner: "u1")
        XCTAssertEqual(router.readOwner, "u1", "誰の既読かを持っていない（前の人の合図で次の人のベルを消す）")
        XCTAssertEqual(router.readMarks, before + 1)
        XCTAssertFalse(router.takePendingActivity())
    }
}
