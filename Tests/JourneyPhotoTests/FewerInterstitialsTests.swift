import XCTest
@testable import JourneyPhoto

/// 札 #628「入口の画面が多い」（2026-11-22）。使いたい画面の前に割り込む画面を、**起動で1つ、投稿のあとで1つまで**にする。
/// 決まりは値で試し、つなぎ（`RootView` などが決まりを使っているか）はソースの字で試す。どれも直しを戻すと落ちる
@MainActor
final class FewerInterstitialsTests: XCTestCase {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "fewer-interstitials-\(UUID().uuidString)")!
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func release(_ version: String, announce: Bool = false) -> WhatsNew.Release {
        WhatsNew.Release(version: version, items: [
            WhatsNew.Item(symbol: "star", title: .init(ja: "題", en: "Title"), detail: .init(ja: "説明", en: "Detail"),
                          destination: nil),
        ], announce: announce)
    }

    // MARK: - 1. 新しくなったこと: 起動のシートをやめ、ホームの印に

    /// ふつうの版は印だけ。`announce` の版が入っているときだけシート。読む版が無ければ何も出さない
    func testWhatsNewIsBadgeUnlessAnnounced() async {
        XCTAssertEqual(WhatsNew.launchPresentation([]), .none)
        XCTAssertEqual(WhatsNew.launchPresentation([release("1.2.1"), release("1.2.0")]), .badge)
        XCTAssertEqual(WhatsNew.launchPresentation([release("1.2.1"), release("1.2.0", announce: true)]), .sheet)
    }

    /// JSON の `announce` を読む。無い・壊れた値は false（古い JSON も読める）
    func testAnnounceDecodes() async throws {
        let json = #"""
        {"releases":[
          {"version":"1.2.0","announce":true,"items":[{"symbol":"star","title":{"ja":"a","en":"a"},"detail":{"ja":"b","en":"b"}}]},
          {"version":"1.1.0","items":[{"symbol":"star","title":{"ja":"a","en":"a"},"detail":{"ja":"b","en":"b"}}]},
          {"version":"1.0.0","announce":"yes","items":[{"symbol":"star","title":{"ja":"a","en":"a"},"detail":{"ja":"b","en":"b"}}]}
        ]}
        """#
        let releases = WhatsNew.decode(Data(json.utf8))
        XCTAssertEqual(releases.map(\.announce), [true, false, false])
    }

    /// 同梱の版には、いまは `announce` を付けていない（付けるのは owner が決める）＝起動でシートは出ない
    func testBundledReleasesDoNotAnnounce() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/WhatsNew.json"))
        let releases = WhatsNew.decode(data)
        XCTAssertFalse(releases.isEmpty)
        XCTAssertEqual(WhatsNew.launchPresentation(releases), .badge)
    }

    /// 更新した人の門: 印を出す（`shouldPresent`）が、起動の出し方は印。読んだら消える
    func testGateBadgeUntilSeen() async {
        let d = defaults()
        d.set("1.0.0", forKey: WhatsNewGate.seenKey)
        let gate = WhatsNewGate(defaults: d, current: "1.1.0", releases: [release("1.1.0")])
        XCTAssertTrue(gate.shouldPresent)
        XCTAssertEqual(gate.presentation, .badge)
        gate.markSeen()
        XCTAssertFalse(gate.shouldPresent)
        XCTAssertEqual(gate.presentation, .none)
    }

    /// 起動のシートは `presentation == .sheet` のときだけ。ホームに印を置く
    func testRootPresentsWhatsNewSheetOnlyWhenAnnounced() async throws {
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("guard whatsNew.presentation == .sheet else {"), "起動でいつもシートを出す形に戻っている")
        XCTAssertFalse(root.contains("guard whatsNew.shouldPresent else {"), "読む版があるだけで起動のシートを出している")
        let home = try source("Features/Gallery/GalleryView.swift")
        XCTAssertTrue(home.contains("WhatsNewHomeBadge()"), "ホームに「新しくなったこと」の印が無い")
        let badge = try source("Features/Settings/WhatsNewHomeBadge.swift")
        XCTAssertTrue(badge.contains(".accessibilityIdentifier(\"home.whatsNew\")"))
        XCTAssertTrue(badge.contains("onDismiss: { gate.markSeen() }"), "印から読んでも、読んだことにならない")
    }

    // MARK: - 4. 起動の案内は1回の起動で1つまで

    func testLaunchSlotAllowsOnlyOneKind() async {
        var slot = LaunchNoticeSlot()
        XCTAssertTrue(slot.mayShow(.foundingGift))
        XCTAssertTrue(slot.claim(.foundingGift))
        // 同じものの出し直しはよい
        XCTAssertTrue(slot.claim(.foundingGift))
        // ほかは次の起動へ
        XCTAssertFalse(slot.mayShow(.trunkWelcome))
        XCTAssertFalse(slot.claim(.trunkWelcome))
        XCTAssertFalse(slot.claim(.likedCover))
        XCTAssertFalse(slot.claim(.whatsNew))
        XCTAssertEqual(slot.taken, .foundingGift)
    }

    /// 起動の案内（新しくなったこと、初期ユーザー章、はじめての硬貨、いいねの1枚）が、どれも同じ1枠を取ってから出る
    func testRootClaimsLaunchSlotForEveryLaunchNotice() async throws {
        let root = try source("App/RootView.swift")
        for kind in ["whatsNew", "foundingGift", "trunkWelcome", "likedCover"] {
            XCTAssertTrue(root.contains("launchSlot.claim(.\(kind))"), "\(kind) が起動の1枠を取らずに出る")
        }
    }

    /// 初期ユーザー章は1回まで（前は3回）
    func testFoundingGiftOnlyOnce() async {
        XCTAssertEqual(FoundingGiftGate.maxShows, 1)
    }

    /// アイコン・カバーのお礼は全画面で割り込まず、知らせ「硬貨 N 枚が届きました　見る」
    func testRewardBecomesNotice() async throws {
        let grant = ProfileReward.Grant(kinds: [.cover], added: 3, coins: 5)
        XCTAssertEqual(ProfileRewardText.notice(grant), "硬貨 3 枚が届きました")
        XCTAssertEqual(ProfileRewardText.noticeAction, "見る")
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("toasts.show(ProfileRewardText.notice(grant), kind: .success, actionTitle: ProfileRewardText.noticeAction)"),
                      "お礼が知らせになっていない")
    }

    // MARK: - 2・3. 初めての投稿のあとは「投稿しました」1枚、2回目からは知らせだけ

    private func summary(card: Bool = false, cover: Bool = false, push: Bool = false,
                         labels: Int = 0) -> PostedSummaryCenter.Summary {
        let offer = CoverOfferStore.Offer(kind: .firstPost, photoId: "p1", imageURL: nil, title: "朝", hasCover: false,
                                          showsCoins: false)
        let batch = labels == 0 ? nil : TrunkArrivals.Batch(
            arrivals: (0..<labels).map { TrunkArrivals.Arrival(label: TrunkSample.pocket[$0 % TrunkSample.pocket.count],
                                                                photoTitle: "") })
        return PostedSummaryCenter.Summary(ownerId: "u1", card: nil, cover: cover ? offer : nil, offersPush: push,
                                           labels: batch)
    }

    /// 行の並びは 通知 → カバー → ラベル。押した人だけが進む（行はただの行）
    func testSummaryRows() async {
        XCTAssertEqual(PostedSummaryCenter.rows(summary()), [])
        XCTAssertEqual(PostedSummaryCenter.rows(summary(cover: true, push: true, labels: 2)),
                       [.push, .cover, .labels(count: 2)])
        // カードも行も無ければ1枚は出さない（知らせだけで足りる）
        XCTAssertFalse(PostedSummaryCenter.showsSheet(summary()))
        XCTAssertTrue(PostedSummaryCenter.showsSheet(summary(push: true)))
    }

    /// 開いている間に届いたラベルは行に足す。閉じていれば知らせ（全画面は自分からは出さない）
    func testLabelsJoinOpenSummaryOtherwiseNotice() async {
        let center = PostedSummaryCenter()
        let batch = TrunkArrivals.Batch(arrivals: [TrunkArrivals.Arrival(label: TrunkSample.arrived, photoTitle: "")])
        XCTAssertFalse(center.addLabels(batch), "閉じているのに行に足した")
        XCTAssertEqual(PostedSummaryCenter.labelArrival(summaryOpen: false), .notice)
        XCTAssertTrue(center.present(summary(push: true)))
        XCTAssertEqual(PostedSummaryCenter.labelArrival(summaryOpen: true), .summaryRow)
        XCTAssertTrue(center.addLabels(batch))
        XCTAssertTrue(center.addLabels(batch))
        XCTAssertEqual(center.presented.map(PostedSummaryCenter.rows), [.push, .labels(count: 2)])
    }

    /// 「見る」で閉じたら、閉じきってから届いた画面を開く（中身は閉じる前に預かる）。人が替わったら閉じる
    func testSummaryFollowUpAndUserChange() async {
        let center = PostedSummaryCenter()
        XCTAssertTrue(center.present(summary(labels: 1)))
        center.close(then: .labels)
        XCTAssertNil(center.presented)
        guard case .labels(let batch)? = center.takeFollowUp() else { return XCTFail("届いたラベルを預かっていない") }
        XCTAssertEqual(batch.arrivals.count, 1)
        XCTAssertNil(center.takeFollowUp())
        XCTAssertTrue(center.present(summary(push: true)))
        center.userChanged(to: "u2")
        XCTAssertNil(center.presented, "前の人の「投稿しました」が残っている")
    }

    /// つなぎ: 初めての投稿はカバーの差し出し・通知の説明・届いた画面を別々に出さず、1枚にまとめる
    func testRootMergesFirstPostScreens() async throws {
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("postedSummary.present(summary)"), "初めての投稿のあとに「投稿しました」を出していない")
        XCTAssertTrue(root.contains("PostedSummarySheet(summary: summary)"))
        // 初めての投稿のカバーは行に（別のシートの待ちへ入れない）
        XCTAssertFalse(root.contains("coverOffers.finishFirstPost(userId: userId, offer: .init("),
                       "初めての投稿のカバーの差し出しを、別のシートで出す形に戻っている")
        // 投稿のあとの通知の説明のシートは出さない（行の「オンにする」に置いた）
        XCTAssertFalse(root.contains("pushPrimerMoment = .firstPost"), "投稿のあとに通知の説明のシートを出している")
        // 届いた画面を自分からは出さない（行か知らせの「見る」から）
        XCTAssertFalse(root.contains("""
            if let batch = trunkArrivals.consume() {
                    trunkBatch = batch
            """), "届いた画面を自分から全画面で出している")
        XCTAssertTrue(root.contains("PostedSummaryCenter.labelArrival(summaryOpen: postedSummary.presented != nil)"))
        // 2回目からの投稿は今までどおり知らせ「投稿しました　カードにする」だけ（カードの画面を自分から出さない）
        let center = try source("Core/Storage/PostUploadCenter.swift")
        XCTAssertTrue(center.contains("model.showsCardSheet = { false }"))
        XCTAssertTrue(center.contains("toasts.show(PostedCardHabit.quietText, kind: .success, actionTitle: PostedCardHabit.quietAction)"))
    }

    // MARK: - 5. 未ログインでいいね等: 確かめの窓をやめ、すぐログインのシート

    func testAskOpensSignInDirectly() async throws {
        let asked = SignInRequest(reason: SignInPrompt.like, signUpReason: SignInPrompt.likeSignUp)
        let opened = SignInPromptOpening.opened(from: asked)
        XCTAssertEqual(opened.entry, .signUp)
        XCTAssertEqual(opened.reason, SignInPrompt.likeSignUp)
        let text = try source("Features/Auth/SignInPrompt.swift")
        XCTAssertFalse(text.contains(".alert(Labels.Common.signInRequired"), "確かめの窓（ログインが必要です）が残っている")
        XCTAssertTrue(text.contains("open = SignInPromptOpening.opened(from: request)"))
    }

    // MARK: - 6. とおまわり号の「はじめての方へ」: 触れば消える1行

    func testCamperCoachIsOneTouchThroughLine() async throws {
        let room = try source("Features/Camper/Room/CamperRoomView.swift")
        XCTAssertFalse(room.contains("camper.room.coach.done"), "「わかった」まで触れない札が残っている")
        XCTAssertTrue(room.contains("coachLine"))
        XCTAssertTrue(room.contains(".simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in dismissCoach() },"),
                      "部屋を触っても手引きが消えない")
        XCTAssertFalse(CamperRoomView.coachText.isEmpty)
    }

    // MARK: - 確かめ役の指摘（2026-11-22）

    /// 手引きの指の受け口は、手引きが出ている間だけ効く。一度見せたら済んだと覚え、別の場面へ移っても消す
    func testCamperCoachGestureOnlyWhileShowingAndRememberedOnShow() async throws {
        XCTAssertEqual(CamperRoomView.coachGestureMask(showing: true), .all)
        XCTAssertEqual(CamperRoomView.coachGestureMask(showing: false), .subviews)
        let room = try source("Features/Camper/Room/CamperRoomView.swift")
        XCTAssertTrue(room.contains("including: Self.coachGestureMask(showing: showCoach))"), "ふだんの操作にも手引きの受け口が重なっている")
        XCTAssertTrue(room.contains("if showCoach, !CamperRoomPreview.coach { CamperRoomCoach.done() }"),
                      "見せただけでは済んだと覚えない（読み上げの人に毎回出る）")
        XCTAssertTrue(room.contains("""
            private func enter(_ m: Mode) {
                    dismissCoach()
            """), "別の場面へ移っても手引きが残る")
    }

    /// ほかの画面・差し出しが出ている間は出さない（出すと黙って無視され、待ちが全部止まる）。決めている途中は見ない
    func testSummaryWaitsForOtherScreens() async throws {
        XCTAssertTrue(PostedSummaryCenter.mayPresent(PostModalSnapshot(coverOfferBusy: true)))
        XCTAssertFalse(PostedSummaryCenter.mayPresent(PostModalSnapshot(modalPresenting: true)))
        XCTAssertFalse(PostedSummaryCenter.mayPresent(PostModalSnapshot(extrasShowing: true)))
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("until: PostedSummaryCenter.mayPresent,"), "ほかの画面が閉じるのを待たずに出している")
        XCTAssertTrue(root.contains("if ready, auth.userId == userId, !Task.isCancelled, !ModalProbe.isPresenting(), postedSummary.present(summary) {"),
                      "出す直前に見直していない（待ちきれない回にも出す・知らせを下ろす）")
    }

    /// 下ろすのは同じ投稿の知らせ（「投稿しました」）だけ。別の投稿の失敗の知らせは残す
    func testDismissOnlyPostedNotice() async throws {
        let toasts = ToastCenter()
        toasts.show(PostUploadOutcome.failedText, kind: .failure, actionTitle: PostUploadOutcome.retryAction) {}
        toasts.dismiss(ifShowing: PostedCardHabit.quietText)
        XCTAssertEqual(toasts.current?.text, PostUploadOutcome.failedText, "失敗の知らせ（もう一度）まで下ろした")
        toasts.show(PostedCardHabit.quietText, kind: .success, actionTitle: PostedCardHabit.quietAction) {}
        toasts.dismiss(ifShowing: PostedCardHabit.quietText)
        XCTAssertNil(toasts.current)
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("toasts.dismiss(ifShowing: PostedCardHabit.quietText)"))
        XCTAssertFalse(root.contains("postedSummary.present(summary) { toasts.dismiss() }"))
    }

    /// 1枚を出した投稿では評価のお願いを見送る（1回だけ）。その投稿の評価の待ちが先に抜けても、印は残さない
    func testSummarySkipsReviewOnce() async throws {
        let center = PostedSummaryCenter()
        XCTAssertFalse(center.takeReviewSkip())
        // 同じ投稿の評価が待っている間に出した: 見送る
        center.beginReviewWait()
        XCTAssertTrue(center.present(summary(push: true)))
        XCTAssertTrue(center.takeReviewSkip())
        XCTAssertFalse(center.takeReviewSkip(), "次のうれしい瞬間まで見送っている")
        center.endReviewWait()
        // 評価の側が先に抜けた（印を受け取らずに終わった）: 次のうれしい瞬間は見送らない
        center.beginReviewWait()
        XCTAssertTrue(center.present(summary(push: true)))
        center.endReviewWait()
        center.beginReviewWait()
        XCTAssertFalse(center.takeReviewSkip(), "先に抜けた投稿の印が残り、次のうれしい瞬間を黙って見送る")
        center.endReviewWait()
        // 評価が待っていないときに出した: 印を立てない
        XCTAssertTrue(center.present(summary(push: true)))
        XCTAssertFalse(center.takeReviewSkip())
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("!postedSummary.takeReviewSkip(),"), "評価のお願いが1枚の後にも出る")
        XCTAssertTrue(root.contains("postedSummary.beginReviewWait()"))
        XCTAssertTrue(root.contains("defer { postedSummary.endReviewWait() }"), "待ちが終わっても見送りの印を下ろさない")
    }

    /// 人が替わったら閉じる・出ている間は他を待たせる、のつなぎ
    func testRootWiresUserChangeAndExtrasShowing() async throws {
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("postedSummary.userChanged(to: userId)"), "人が替わっても前の人の「投稿しました」が残る")
        XCTAssertTrue(root.contains("extrasShowing: rewardGrant != nil || coverOffer != nil || postedSummary.presented != nil"),
                      "1枚が出ている間に評価・届いた画面・案内が重なる")
    }

    /// 設定から読んでも印を消す
    func testSettingsHistoryClearsBadge() async throws {
        let settings = try source("Features/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains(".sheet(isPresented: $showWhatsNew, onDismiss: { WhatsNewGate.shared.markSeen() })"))
        let badge = try source("Features/Settings/WhatsNewHomeBadge.swift")
        XCTAssertTrue(badge.contains(".jpSystemFont(13, weight: .semibold, relativeTo: .footnote)"), "印の字が大きな字に合わせて変わらない")
    }

    /// カバーの行は、初めてのカバーで硬貨が届くときだけ枚数を言う
    func testCoverRowMentionsCoins() async {
        XCTAssertEqual(PostedSummaryText.coverRow(showsCoins: false), "この写真をカバーに")
        XCTAssertEqual(PostedSummaryText.coverRow(showsCoins: true), "この写真をカバーに（硬貨 \(ProfileRewardText.coinsPerKind) 枚）")
    }
}
