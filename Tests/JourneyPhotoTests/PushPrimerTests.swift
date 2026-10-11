import XCTest
@testable import JourneyPhoto

/// 通知の許可を尋ねる頃合い（`PushPrimer`・`PushPrimerStore`）と、Pro の「前の晩に知らせる」の
/// 「通知がオフのため届きません」（`LightAlertPushNotice`）・2026-10-11。
///
/// 前は設定の「プッシュ通知を受け取る」を押したときにしか尋ねず、「前の晩に知らせる」は
/// 既定でオンなのに、通知が届かない端末でもオンに見えて何も来なかった
@MainActor
final class PushPrimerTests: XCTestCase {

    /// 試験ごとに別の控え（端末の控えを汚さない・`ReviewPromptTests` と同じ形）
    private let defaults = UserDefaults(suiteName: "PushPrimerTests.\(UUID().uuidString)")!

    // MARK: - 許可の段階

    /// 「まだ聞いていない」と「断られた」を分ける（断られた人に OS はもう聞かない）
    func testPermissionSeparatesUndecidedFromDenied() async {
        XCTAssertEqual(PushPermission(.notDetermined), .notDetermined)
        XCTAssertEqual(PushPermission(.denied), .denied)
        XCTAssertEqual(PushPermission(.authorized), .allowed)
        XCTAssertEqual(PushPermission(.provisional), .allowed)
        XCTAssertEqual(PushPermission(.ephemeral), .allowed)
    }

    /// 読み直すと段階が入る。読むまでは `.unknown`（何も案内しない）
    func testRefreshReadsPermission() async {
        let push = PushCenter(defaults: defaults, releaseDevice: {}, readAuthorization: { false },
                              readPermission: { .denied })
        XCTAssertEqual(push.permission, .unknown)
        await push.refreshAuthorization()
        XCTAssertEqual(push.permission, .denied)
    }

    /// 尋ねて断られたら `.denied`（次からは設定アプリへの案内に替わる。模型の OS は必ず断る）
    func testEnableThatIsRefusedMarksDenied() async {
        let push = PushCenter(defaults: defaults, releaseDevice: {}, readAuthorization: { false },
                              readPermission: { .notDetermined })
        await push.refreshAuthorization()
        XCTAssertEqual(push.permission, .notDetermined)
        let granted = await push.enable()
        XCTAssertFalse(granted)
        XCTAssertEqual(push.permission, .denied)
    }

    // MARK: - 説明を出す頃合い

    /// **まだ聞いていない・ログインしている・この端末で出していない**ときだけ
    func testOffersOnlyWhenUndecidedSignedInAndNotYetOffered() async {
        XCTAssertTrue(PushPrimer.shouldOffer(signedIn: true, permission: .notDetermined, alreadyOffered: false))
        XCTAssertFalse(PushPrimer.shouldOffer(signedIn: false, permission: .notDetermined, alreadyOffered: false),
                       "ログインしていないのに尋ねている（宛先を預ける人がいない）")
        XCTAssertFalse(PushPrimer.shouldOffer(signedIn: true, permission: .notDetermined, alreadyOffered: true),
                       "一度出したのにまた出している（押しつけ）")
        for permission in [PushPermission.unknown, .denied, .allowed] {
            XCTAssertFalse(PushPrimer.shouldOffer(signedIn: true, permission: permission, alreadyOffered: false),
                           "\(permission) なのに尋ねている")
        }
    }

    /// 🔴 **端末で1回だけ。** 出したら（「あとで」でも）覚えて、二度と合図しない
    func testStoreOffersOnceAndRemembers() async {
        let store = PushPrimerStore(defaults: defaults, isPreview: { false })
        store.notePosted()
        XCTAssertEqual(store.requests, 1)
        XCTAssertTrue(store.consume(signedIn: true, permission: .notDetermined))
        XCTAssertTrue(store.alreadyOffered)
        XCTAssertFalse(store.consume(signedIn: true, permission: .notDetermined), "二度出している")
        store.notePosted()
        XCTAssertEqual(store.requests, 1, "出したあとも投稿のたびに合図している")
        // 端末に覚える（アプリを入れ直すまで残る）
        XCTAssertTrue(PushPrimerStore(defaults: defaults, isPreview: { false }).alreadyOffered)
    }

    /// 出せなかった回（許可済み・断られた・未ログイン）は覚えない——覚えるのは出したときだけ
    func testStoreDoesNotRememberWhenNotShown() async {
        let store = PushPrimerStore(defaults: defaults, isPreview: { false })
        XCTAssertFalse(store.consume(signedIn: true, permission: .unknown))
        XCTAssertFalse(store.consume(signedIn: false, permission: .notDetermined))
        XCTAssertFalse(store.alreadyOffered)
        XCTAssertTrue(store.consume(signedIn: true, permission: .notDetermined))
    }

    /// 絵を撮る入り方では投稿で合図しない（巡回の絵を覆わない）
    func testPreviewDoesNotSignal() async {
        let store = PushPrimerStore(defaults: defaults, isPreview: { true })
        store.notePosted()
        XCTAssertEqual(store.requests, 0)
    }

    // MARK: - 「前の晩に知らせる」の行

    /// 🔴 **オンなのに届かない端末では知らせる。** まだ聞いていない → 受け取る、断られた → 設定アプリ
    func testLightAlertNoticeFollowsPermission() async {
        XCTAssertEqual(LightAlertPushNotice.state(wants: true, knownNotPro: false,
                                                  permission: .notDetermined, enabled: false), .turnOn)
        XCTAssertEqual(LightAlertPushNotice.state(wants: true, knownNotPro: false,
                                                  permission: .denied, enabled: true), .openSettings)
        XCTAssertEqual(LightAlertPushNotice.state(wants: true, knownNotPro: false,
                                                  permission: .allowed, enabled: false), .turnOn,
                       "アプリの中で通知をオフにしているのに黙っている")
        XCTAssertNil(LightAlertPushNotice.state(wants: true, knownNotPro: false,
                                                permission: .allowed, enabled: true), "届くのに知らせている")
    }

    /// オフにしている・Pro でない・まだ読んでいない、は言わない
    func testLightAlertNoticeStaysQuietWhenIrrelevant() async {
        XCTAssertNil(LightAlertPushNotice.state(wants: false, knownNotPro: false,
                                                permission: .denied, enabled: false))
        XCTAssertNil(LightAlertPushNotice.state(wants: true, knownNotPro: true,
                                                permission: .denied, enabled: false))
        XCTAssertNil(LightAlertPushNotice.state(wants: true, knownNotPro: false,
                                                permission: .unknown, enabled: false))
    }

    /// 文言（行の1行目は同じ・2行目と読み上げは押すと何が起きるか）
    func testLightAlertNoticeTexts() async {
        XCTAssertEqual(LightAlertPushNotice.turnOn.title, "通知がオフのため届きません")
        XCTAssertEqual(LightAlertPushNotice.openSettings.title, "通知がオフのため届きません")
        XCTAssertTrue(LightAlertPushNotice.openSettings.detail.contains("設定アプリ"))
        XCTAssertEqual(LightAlertPushNotice.openSettings.hint, "設定アプリを開きます")
        XCTAssertEqual(LightAlertPushNotice.turnOn.hint, "通知の許可を求めます")
    }
}
