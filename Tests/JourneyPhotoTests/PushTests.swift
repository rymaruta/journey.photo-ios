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
}
