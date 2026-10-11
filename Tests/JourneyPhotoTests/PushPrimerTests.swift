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

    /// 🔴 知らない状態（今後の iOS で増えたもの）は「断られた」にせず、読めない扱い（何も案内しない・2026-10-11）。
    /// Linux の模型の `UNAuthorizationStatus` には知らない値を作れないので、書いてあることを見る
    func testUnknownStatusIsNotTreatedAsDenied() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let text = try String(contentsOf: root.appendingPathComponent("Core/Push/PushPermission.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains("@unknown default: self = .unknown"), "知らない状態を読めない扱いにしていない")
        XCTAssertFalse(text.contains("@unknown default: self = .denied"), "知らない状態を「断られた」にしている")
        // 読めない扱いなら、行の案内も説明も出さない
        XCTAssertNil(LightAlertPushNotice.state(wants: true, knownNotPro: false, permission: .unknown, enabled: false))
        XCTAssertFalse(PushPrimer.shouldOffer(signedIn: true, permission: .unknown, alreadyOffered: false))
    }

    /// 説明の「Pro: 行きたい場所…」は Pro の人にだけ（届かない通知を約束しない・2026-10-11）
    func testPrimerShowsProPointOnlyToPro() async {
        let free = PushPrimerPoint.shown(isPro: false).map(\.systemImage)
        XCTAssertEqual(free, ["heart", "bubble.left"], "Pro でない人に Pro の通知を約束している")
        let pro = PushPrimerPoint.shown(isPro: true).map(\.systemImage)
        XCTAssertEqual(pro, ["heart", "bubble.left", "sunrise"])
        XCTAssertTrue(PushPrimerPoint.shown(isPro: true).last?.text.contains("Pro") ?? false)
    }

    /// 読み直すと段階が入る。読むまでは `.unknown`（何も案内しない）
    func testRefreshReadsPermission() async {
        let push = PushCenter(defaults: defaults, releaseDevice: {}, readAuthorization: { false },
                              readPermission: { .denied })
        XCTAssertEqual(push.permission, .unknown)
        await push.refreshAuthorization()
        XCTAssertEqual(push.permission, .denied)
    }

    /// 尋ねて断られたら `.denied`（次からは設定アプリへの案内に替わる）。
    /// 🔴 尋ねるのは差し替える——本物の OS のダイアログは試験では答えが返らず、Mac の試験が止まった
    func testEnableThatIsRefusedMarksDenied() async {
        let push = PushCenter(defaults: defaults, releaseDevice: {}, readAuthorization: { false },
                              readPermission: { .notDetermined }, requestPermission: { false })
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

    /// 🔴 **評価のお願いと重ねない**（2026-10-11）。説明を決めている途中は頼まず、
    /// 待っている間に説明を出した回も頼まない。説明を出さなかった回・前に出していた端末では頼める
    func testReviewWaitsForPrimerAndSkipsWhenPrimerShown() async {
        let store = PushPrimerStore(defaults: defaults, isPreview: { false })
        // 評価の側が待ち始める（説明はまだ出していない）
        let offeredAtStart = store.alreadyOffered
        store.notePosted()
        XCTAssertTrue(store.isDeciding)
        XCTAssertFalse(store.letsReviewAsk(offeredAtStart: offeredAtStart), "説明を決めている途中に評価を頼んでいる")
        // 説明を出した
        XCTAssertTrue(store.consume(signedIn: true, permission: .notDetermined))
        store.finishDeciding()
        XCTAssertFalse(store.isDeciding)
        XCTAssertFalse(store.letsReviewAsk(offeredAtStart: offeredAtStart), "説明を出した回に評価も頼んでいる")
        // 次のうれしい瞬間（説明はもう出してある端末）では頼める
        store.notePosted()
        XCTAssertFalse(store.isDeciding, "出したあとの投稿で評価を止めている")
        XCTAssertTrue(store.letsReviewAsk(offeredAtStart: store.alreadyOffered))
    }

    /// 説明を出さなかった回（許可済みなど）は、決め終えたら評価を頼める
    func testReviewAsksWhenPrimerNotShown() async {
        let store = PushPrimerStore(defaults: defaults, isPreview: { false })
        let offeredAtStart = store.alreadyOffered
        store.notePosted()
        XCTAssertFalse(store.consume(signedIn: true, permission: .allowed))
        store.finishDeciding()
        XCTAssertTrue(store.letsReviewAsk(offeredAtStart: offeredAtStart))
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
