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
        await reopened.use(userId: "A")
        XCTAssertTrue(reopened.isEnabled, "オンのまま開き直せる")

        await reopened.disable()
        let again = PushCenter(service: { PushService(api: APIClient(tokenProvider: StubTokenProvider(token: nil))) },
                               defaults: defaults)
        await again.use(userId: "A")
        XCTAssertFalse(again.isEnabled, "オフにしたら、次の起動でもオフ")
        _ = push
    }

    private func reopen(_ defaults: UserDefaults) -> PushCenter {
        PushCenter(service: { PushService(api: APIClient(tokenProvider: StubTokenProvider(token: nil))) },
                   defaults: defaults)
    }

    /// 🔴 **「受け取る」は人ごと。** A が「受け取る」にした端末で B がログインしても、
    /// B は選んでいないので受け取る側に入らない（登録まで進まない）。
    /// 端末全体だった頃の値は、**更新後に最初にログイン済みと分かった人**（A）にだけ引き継ぐ
    func testIntentBelongsToThePersonWhoChoseIt() async {
        let (push, defaults) = center("push-3")
        defaults.set(true, forKey: "photo-gallery-push-enabled")   // 端末全体だった頃の値

        await push.use(userId: nil)          // 起動直後（確認中）では引き継がない
        XCTAssertFalse(push.isEnabled, "未ログインで受け取る側に入っている")
        await push.use(userId: "A")
        XCTAssertTrue(push.isEnabled, "ログインしていた本人（A）に引き継いでいない")

        await push.use(userId: nil)
        await push.use(userId: "B")
        XCTAssertFalse(push.isEnabled, "A が選んだ「受け取る」で B が受け取る側に入った")

        // 開き直しても人ごとに残る
        let reopened = reopen(defaults)
        await reopened.use(userId: "B")
        XCTAssertFalse(reopened.isEnabled, "開き直したら B が受け取る側に入った")
        await reopened.use(userId: "A")
        XCTAssertTrue(reopened.isEnabled, "A の「受け取る」が消えた")
    }

    /// **起動の時点でログアウトしていたら、端末全体の値は誰にも引き継がない**
    /// ——あとからログインする人は、それを選んだ本人とは限らない
    func testLegacyIntentIsDroppedWhenNobodyWasSignedIn() async {
        let (push, defaults) = center("push-4")
        defaults.set(true, forKey: "photo-gallery-push-enabled")

        push.dropLegacyIntent()
        await push.use(userId: "B")
        XCTAssertFalse(push.isEnabled, "誰のものか分からない「受け取る」を B に渡した")
    }

    /// **本人がオフにしてから開き直しても、端末全体の古い値で上書きしない**
    func testLegacyIntentDoesNotOverrideThePersonsOwnChoice() async {
        let (push, defaults) = center("push-5")
        await push.use(userId: "A")
        await push.disable()                                       // A は自分でオフ
        defaults.set(true, forKey: "photo-gallery-push-enabled")   // 古い値が残っていた

        let reopened = reopen(defaults)
        await reopened.use(userId: "A")
        XCTAssertFalse(reopened.isEnabled, "本人のオフを古い値で上書きした")
    }
}

/// 通知を押したときの行き先。
///
/// **真偽値にしない**——お知らせタブを開いたまま2回続けて押すと、
/// 「変わっていない」と見なされて2回目が効かなくなる。画面側は
/// この数を `.task(id:)` に渡して読み直している。
@MainActor
final class NotificationRouterTests: XCTestCase {

    func testEachTapIsDistinguishable() async {
        let router = NotificationRouter.shared
        let before = router.openActivityRequests
        router.openActivity()
        router.openActivity()
        XCTAssertEqual(router.openActivityRequests, before + 2,
                       "2回押したのに1回ぶんしか数えていない")
    }
}

/// 🔴 **前の人の通知の後始末。**
///
/// ログアウトで宛先を外す口は、その人の鍵が要る。圏外などで外せないまま
/// ログアウトすると、**前の人あての通知がこの端末に届き続ける**——
/// 以前は `try?` で握りつぶしていたので、誰も気づけず、やり直しもしなかった。
@MainActor
final class PushSignOutTests: XCTestCase {

    /// 呼ぶたびに今の鍵で口を作る（ログアウトで鍵が無くなるのを写す）
    private final class Keys { var idToken: String? = "t" }

    private func center(_ suite: String, keys: Keys) -> PushCenter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        StubProtocol.reset()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let push = PushCenter(service: {
            PushService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                       tokenProvider: StubTokenProvider(token: keys.idToken),
                                       session: session))
        }, defaults: defaults)
        push.accept(deviceToken: Data(repeating: 0xab, count: 32))
        return push
    }

    func testFailedReleaseIsRetriedWhenTheSamePersonComesBack() async {
        let keys = Keys()
        let push = center("push-release-1", keys: keys)
        await push.use(userId: "A")

        // 圏外で外せないままログアウト
        StubProtocol.respond(status: 500, body: "{}")
        await push.signingOut()
        XCTAssertEqual(push.pendingReleaseOwner, "A", "外せなかったことを覚えていない")
        keys.idToken = nil
        await push.use(userId: nil)

        // 別の人（B）では A の宛先は外せない。印は残す
        keys.idToken = "t"
        StubProtocol.respond(status: 200, body: "{}")
        await push.use(userId: "B")
        await push.signingOut()
        XCTAssertEqual(push.pendingReleaseOwner, "A", "外せていないのに印を消した")
        keys.idToken = nil
        await push.use(userId: nil)

        // A が戻ってきたら、A の鍵で外し直す
        keys.idToken = "t"
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: "{}")
        await push.use(userId: "A")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "DELETE", "外し直していない")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/devices")
        XCTAssertNil(push.pendingReleaseOwner, "外し直せたのに印が残っている")
    }

    /// 🔴 **「受け取らない」で宛先を外せなかったら、次の起動で外し直す。**
    /// 意思（オフ）は先に残るので、以前は次の `use` が「受け取らない人」として
    /// 素通りし、トグルはオフなのに通知が届き続けた
    func testFailedDisableIsRetriedOnTheNextLaunch() async {
        let keys = Keys()
        let push = center("push-release-4", keys: keys)
        await push.use(userId: "A")

        StubProtocol.respond(status: 500, body: "{}")
        await push.disable()
        XCTAssertFalse(push.isEnabled)
        XCTAssertEqual(push.pendingReleaseOwner, "A", "外せなかったことを覚えていない")

        // 開き直す（同じ端末・同じ人）
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        let reopened = PushCenter(service: {
            PushService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                       tokenProvider: StubTokenProvider(token: keys.idToken),
                                       session: session))
        }, defaults: UserDefaults(suiteName: "push-release-4")!)
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: "{}")
        await reopened.use(userId: "A")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "DELETE", "外し直していない")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/devices")
        XCTAssertNil(reopened.pendingReleaseOwner, "外し直せたのに印が残っている")
    }

    /// **別の人の外しそびれを上書きしない。** 印は1人ぶんで、前の人の宛先は
    /// その人の鍵でしか外せない
    func testFailedDisableDoesNotOverwriteAnotherPersonsPendingRelease() async {
        let keys = Keys()
        let push = center("push-release-5", keys: keys)
        await push.use(userId: "A")
        StubProtocol.respond(status: 500, body: "{}")
        await push.signingOut()
        await push.use(userId: nil)
        XCTAssertEqual(push.pendingReleaseOwner, "A")

        await push.use(userId: "B")
        await push.disable()
        XCTAssertEqual(push.pendingReleaseOwner, "A", "A の外しそびれを B で上書きした")
    }

    /// 🔴 **ログアウトで外せなかったときも、別の人の外しそびれを上書きしない**
    /// （`disable` と同じ決まり）。A の印が残っている＝その後この端末で登録は
    /// 通っていないので、宛先はまだ A のもの。B の空振りで A の手がかりを消していた
    func testFailedSignOutDoesNotOverwriteAnotherPersonsPendingRelease() async {
        let keys = Keys()
        let push = center("push-release-6", keys: keys)
        await push.use(userId: "A")
        StubProtocol.respond(status: 500, body: "{}")
        await push.signingOut()
        keys.idToken = nil
        await push.use(userId: nil)
        XCTAssertEqual(push.pendingReleaseOwner, "A")

        keys.idToken = "t"
        await push.use(userId: "B")
        await push.signingOut()                       // B も外せない（まだ 500）
        XCTAssertEqual(push.pendingReleaseOwner, "A", "A の外しそびれを B のログアウトで上書きした")
    }

    /// 印が無ければ、ログアウトで外せなかった人に印を付ける（従来どおり）
    func testFailedSignOutMarksWhenNothingIsPending() async {
        let keys = Keys()
        let push = center("push-release-7", keys: keys)
        await push.use(userId: "B")
        StubProtocol.respond(status: 500, body: "{}")
        await push.signingOut()
        XCTAssertEqual(push.pendingReleaseOwner, "B")
    }

    /// **前の人の失敗文を次の人に見せない**（設定画面の赤字）
    func testErrorMessageDoesNotCarryOverToTheNextPerson() async {
        let keys = Keys()
        let push = center("push-release-3", keys: keys)
        await push.use(userId: "A")
        push.errorMessage = "通知を止められませんでした"
        await push.use(userId: "B")
        XCTAssertNil(push.errorMessage, "人が替わったのに前の人の失敗文が残っている")

        push.errorMessage = "通知を止められませんでした"
        StubProtocol.respond(status: 200, body: "{}")
        await push.signingOut()
        XCTAssertNil(push.errorMessage, "ログアウトしたのに失敗文が残っている")
    }
}

/// **前の人の失敗文を、ログアウトのあとのログイン画面に出さない。**
@MainActor
final class AuthSignOutTests: XCTestCase {

    func testSignOutForgetsTheError() async {
        let auth = AuthStore()
        auth.errorMessage = "現在のパスワードが違います"
        await auth.signOut()
        XCTAssertNil(auth.errorMessage, "前の人の失敗文がログイン画面に残る")
        XCTAssertEqual(auth.lastFailure, .none)
    }

    func testDeletingTheAccountForgetsTheError() async throws {
        let auth = AuthStore()
        auth.errorMessage = "うまくいきませんでした"
        try await auth.deleteCognitoUser()
        XCTAssertNil(auth.errorMessage)
    }
}
