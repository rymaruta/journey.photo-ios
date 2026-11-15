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

    // MARK: - 初めてのフォロー・コメント・メッセージのあと（2026-11-15 札 #618 案2）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 🔴 投稿しない人にも聞く。ただし**端末で1回だけ**（投稿の場面と同じ印）。評価のお願いの待ちには触らない
    func testReachOutAsksOnceSharingTheSameMark() async {
        let store = PushPrimerStore(defaults: defaults, isPreview: { false })
        store.noteReachedOut()
        XCTAssertEqual(store.reachOutRequests, 1)
        XCTAssertEqual(store.requests, 0, "投稿の合図と混ぜている")
        XCTAssertFalse(store.isDeciding, "フォローで評価のお願いの待ちを立てている")
        XCTAssertTrue(store.consume(signedIn: true, permission: .notDetermined))
        store.noteReachedOut()
        XCTAssertEqual(store.reachOutRequests, 1, "出したあともフォロー・コメントのたびに合図している")
        store.notePosted()
        XCTAssertEqual(store.requests, 0, "フォローのあとで出したのに、投稿でもう一度出そうとしている")
    }

    /// 投稿のあとで出した端末では、フォロー・コメント・メッセージでは出さない（逆の順）
    func testReachOutSkipsWhenAlreadyOfferedAfterPost() async {
        let store = PushPrimerStore(defaults: defaults, isPreview: { false })
        store.notePosted()
        XCTAssertTrue(store.consume(signedIn: true, permission: .notDetermined))
        store.noteReachedOut()
        XCTAssertEqual(store.reachOutRequests, 0)
        // 画面写真の入り方では合図しない（巡回の絵を覆わない）
        let preview = PushPrimerStore(defaults: UserDefaults(suiteName: "PushPrimerTests.p.\(UUID().uuidString)")!,
                                      isPreview: { true })
        preview.noteReachedOut()
        XCTAssertEqual(preview.reachOutRequests, 0)
    }

    /// 断られた人・許可済みの人には出さない（今と同じ決まり。OS はもう聞かない）
    func testReachOutFollowsTheSamePermissionRule() async {
        let store = PushPrimerStore(defaults: defaults, isPreview: { false })
        store.noteReachedOut()
        XCTAssertFalse(store.consume(signedIn: true, permission: .denied))
        XCTAssertFalse(store.consume(signedIn: true, permission: .allowed))
        XCTAssertFalse(store.alreadyOffered, "出していないのに覚えた")
    }

    /// 会話・コメントのシートの上や、投稿のあとの案内と重ねない。裏にいる間も出さない
    func testReachOutWaitsForOtherScreens() async {
        XCTAssertTrue(PostModalGate.reachOutPrimerMayShow(PostModalSnapshot()))
        for blocked in [PostModalSnapshot(modalPresenting: true), PostModalSnapshot(pushPrimerDeciding: true),
                        PostModalSnapshot(pushPrimerShowing: true), PostModalSnapshot(reviewDeciding: true),
                        PostModalSnapshot(trunkShowing: true), PostModalSnapshot(launchNoticesDeciding: true),
                        PostModalSnapshot(sceneActive: false), PostModalSnapshot(coverOfferBusy: true),
                        PostModalSnapshot(extrasShowing: true)] {
            XCTAssertFalse(PostModalGate.reachOutPrimerMayShow(blocked), "\(blocked) の上に出している")
        }
        XCTAssertLessThanOrEqual(PostModalGate.reachOutWaitLimit, 600)
    }

    /// 見出しと項目は場面に合わせる（返信・メンション・メッセージが先）。投稿の場面は owner の承認した言い方のまま
    func testReachOutCopy() async {
        XCTAssertEqual(PushPrimerPoint.title(.firstPost), "いいね、コメントが届いたらお知らせしますか？")
        XCTAssertEqual(PushPrimerPoint.title(.reachOut), "返事や反応が来たら、お知らせしますか？")
        XCTAssertEqual(PushPrimerPoint.shown(isPro: false, moment: .reachOut).map(\.systemImage),
                       ["bubble.left", "paperplane", "heart"])
        XCTAssertEqual(PushPrimerPoint.shown(isPro: true, moment: .reachOut).last?.systemImage, "sunrise")
        for text in PushPrimerPoint.shown(isPro: true, moment: .reachOut).map(\.text) + [PushPrimerPoint.title(.reachOut)] {
            XCTAssertFalse(text.contains("・") || text.contains("·"), "中黒で区切っている: \(text)")
        }
    }

    /// 合図はフォロー・コメント・メッセージ（DM と旅の仲間）の送る口が、**送れたあとに**出す
    func testReachOutIsSignalledAfterSending() async throws {
        let social = try source("Services/SocialService.swift")
        XCTAssertTrue(social.contains("if result.following { PushPrimerStore.reachedOut() }"), "フォローで合図していない")
        let comment = try XCTUnwrap(social.range(of: "func postComment("))
        let follow = try XCTUnwrap(social.range(of: "func follow(userId:"))
        XCTAssertTrue(social[comment.upperBound..<follow.lowerBound].contains("PushPrimerStore.reachedOut()"),
                      "コメントで合図していない")
        XCTAssertTrue(try source("Services/DMService.swift").contains("PushPrimerStore.reachedOut()"), "メッセージで合図していない")
        XCTAssertTrue(try source("Services/TripShareService.swift").contains("PushPrimerStore.reachedOut()"))
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains(".onChange(of: pushPrimer.reachOutRequests) { _, _ in offerReachOutPrimerWhenIdle() }"))
        XCTAssertTrue(root.contains("PostModalGate.reachOutPrimerMayShow(postModalSnapshot())"))
    }

    /// 合図は主スレッドへ渡ってから数える（送る口は主スレッドでないことがある）
    func testStaticEntryReachesTheSharedStore() async throws {
        let before = PushPrimerStore.shared.reachOutRequests
        let offered = PushPrimerStore.shared.alreadyOffered
        PushPrimerStore.reachedOut()
        for _ in 0..<20 where PushPrimerStore.shared.reachOutRequests == before { await Task.yield() }
        if !offered && PreviewSession.userId == nil {
            XCTAssertEqual(PushPrimerStore.shared.reachOutRequests, before + 1)
        }
    }
}
