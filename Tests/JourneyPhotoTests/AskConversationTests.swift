import XCTest
@testable import JourneyPhoto

/// AI に頼むの会話を残す（札 #678・2026-11-21 owner「閉じたら AI との会話履歴消えちゃうんだね」
/// 「AI との会話で別スレッドにするには月額500円の有料プラン（Pro）なら使えるようにしたい」）。
/// 閉じて開き直す・アプリを落としても続きが出る（AI は呼ばない・回数も使わない）。無料は会話1本、Pro は前の会話から選べる。
@MainActor
final class AskConversationTests: XCTestCase {

    final class Calls {
        var reserves = 0
        var deviceAsks = 0
        var serverAsks = 0
        /// 端末の AI に渡した直前のやりとり（続けて聞くときの文脈）
        var deviceHistories: [[String]] = []
    }

    struct Setup {
        var offline = false
        var reserveError: Error?
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "AskConversationTests.\(UUID().uuidString)")!
    }

    private func backend(_ calls: Calls, setup: Setup = Setup(), user: String = "u1") throws -> AskEngine.Backend {
        let rows = try AskSamples.ledger()
        return AskEngine.Backend(
            signedIn: { true },
            offline: { setup.offline },
            deviceAI: { true },
            library: { _ in AskLibrary(spots: rows, photos: []) },
            reserve: { kind, _ in
                calls.reserves += 1
                if let e = setup.reserveError { throw e }
                return AskUsage(tier: "free", kind: kind.rawValue, day: .init(used: 1, limit: 3, remaining: 2),
                                month: .init(used: 1, limit: 10, remaining: 9, resetsOn: "2026-12-01"), serverAllowed: false)
            },
            serverAsk: { _, _, _ in calls.serverAsks += 1; return AskService.ServerAnswer(answer: "", general: false) },
            deviceAsk: { text, history, _ in
                calls.deviceAsks += 1
                calls.deviceHistories.append(history.map(\.question))
                return AskDevice.Result(text: "\(text)への答えです。", general: false, picks: [], photoIds: [], sources: [])
            },
            details: { $0 },
            userId: { user })
    }

    // MARK: - 閉じて開き直す・アプリを落とす

    /// 答えた会話は控えに残り、新しいエンジン（アプリを落として開き直した）でも続きが出る。AI も回数も使わない
    func testRelaunchRestoresLastConversationWithoutAI() async throws {
        let d = defaults()
        let calls = Calls()
        let first = AskEngine(history: AskHistoryStore(defaults: d))
        await first.start("香川で夕日がきれいな所は？", backend: try backend(calls))
        await first.followUp("雨の日は？", backend: try backend(calls))
        XCTAssertEqual(first.thread.count, 2)
        let usedBefore = calls.reserves + calls.deviceAsks + calls.serverAsks

        let relaunched = AskEngine(history: AskHistoryStore(defaults: d))
        relaunched.resume(userId: "u1")
        XCTAssertEqual(relaunched.thread.map(\.question), ["香川で夕日がきれいな所は？", "雨の日は？"], "最後の会話が戻らない")
        XCTAssertTrue(relaunched.needsRefill)
        await relaunched.refill(backend: try backend(calls))
        XCTAssertFalse(relaunched.needsRefill)
        XCTAssertEqual(calls.reserves + calls.deviceAsks + calls.serverAsks, usedBefore, "戻すだけで AI か回数を使った")
        XCTAssertNil(AskEngine(history: AskHistoryStore(defaults: d)).thread.first, "作っただけで会話を出した")
        let other = AskEngine(history: AskHistoryStore(defaults: d))
        other.resume(userId: "u2")
        XCTAssertFalse(other.isActive, "ほかの人に前の人の会話を出した")
    }

    /// 戻した会話から続けて聞くと、AI に渡す直前のやりとりが前の会話からつながり、同じ会話の続きとして残る
    func testFollowUpAfterRestoreContinuesTheSameConversation() async throws {
        let d = defaults()
        let calls = Calls()
        let first = AskEngine(history: AskHistoryStore(defaults: d))
        await first.start("金沢でおすすめの観光スポットを教えて", backend: try backend(calls))
        let id = try XCTUnwrap(first.conversationId)

        let relaunched = AskEngine(history: AskHistoryStore(defaults: d))
        relaunched.resume(userId: "u1")
        await relaunched.followUp("冬なら？", backend: try backend(calls))
        XCTAssertEqual(calls.deviceHistories.last, ["金沢でおすすめの観光スポットを教えて"], "続けて聞くとき前のやりとりを渡していない")
        XCTAssertEqual(relaunched.conversationId, id, "続きが別の会話になった")
        let list = AskHistoryStore(defaults: d).conversations(userId: "u1")
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.current?.thread.map(\.question), ["金沢でおすすめの観光スポットを教えて", "冬なら？"])
    }

    /// 控えに残る範囲: AI の答え、断り、言葉の表の答え（圏外）、使い切った帯。回数を使わない「同じ日の同じ頼み」の控えは今のまま
    func testConversationKeepsRefusalsTableAnswersAndBands() async throws {
        let d = defaults()
        let calls = Calls()
        let engine = AskEngine(history: AskHistoryStore(defaults: d))
        await engine.start("京都で紅葉がきれいな所は？", backend: try backend(calls))
        await engine.followUp("このアプリの作りを教えて", backend: try backend(calls))
        await engine.followUp("大阪で夜景は？", backend: try backend(calls, setup: Setup(offline: true)))
        await engine.followUp("奈良で鹿は？", backend: try backend(calls, setup: Setup(reserveError: AskService.Failure.limit(.day, nil))))
        let kept = try XCTUnwrap(AskHistoryStore(defaults: d).conversations(userId: "u1").current?.thread)
        XCTAssertEqual(kept.count, 4)
        XCTAssertEqual(kept[1].answer.engine, .refused, "断りが残らない")
        XCTAssertEqual(kept[2].answer.state, .offline, "圏外の答えが残らない")
        XCTAssertEqual(kept[3].answer.limit, .day, "使い切った帯が残らない")
        // 回数を使わない控え（AI で答えた回と断った回だけ）は今の決まりのまま
        XCTAssertEqual(AskHistoryStore(defaults: d).today("京都で紅葉がきれいな所は？", userId: "u1")?.count, 2)
    }

    /// 旅行プランの流れの答えも会話に残る
    func testPlanFlowAnswerIsKept() async throws {
        let d = defaults()
        let engine = AskEngine(history: AskHistoryStore(defaults: d))
        let q = try XCTUnwrap(engine.beginPlan("京都で2日の旅行プランにして"))
        engine.failPlan(q, line: "作れませんでした。", userId: "u1")
        let kept = try XCTUnwrap(AskHistoryStore(defaults: d).conversations(userId: "u1").current?.thread.first)
        XCTAssertEqual(kept.answer.kind, .plan)
    }

    /// 答えを待っている途中で閉じた: 取り消して、打った頼みは欄に戻す（言い替えは戻さない）
    func testInterruptReturnsTypedQuestion() async {
        let engine = AskEngine(history: AskHistoryStore(defaults: defaults()))
        engine.prepare("近くで夕日がきれいな所は？")
        XCTAssertEqual(engine.interrupt(), "近くで夕日がきれいな所は？")
        XCTAssertNil(engine.pending)
        XCTAssertNil(engine.interrupt(), "待っていないのに字を返した")
        _ = engine.beginPlan("京都で2日の旅行プランにして")
        XCTAssertNil(engine.interrupt(), "旅行プラン（作り続けて帯で知らせる）の頼みを欄に戻した")
    }

    // MARK: - 新しく頼む（無料と Pro）

    /// 無料: 新しく頼むと今の会話は控えから消え、開き直しても空のまま
    func testFreeNewDeletesConversation() async throws {
        let d = defaults()
        let calls = Calls()
        let engine = AskEngine(history: AskHistoryStore(defaults: d))
        await engine.start("香川で夕日がきれいな所は？", backend: try backend(calls))
        XCTAssertTrue(AskConversationRule.confirmsNew(isPro: false, hasConversation: true), "無料で消す前に確かめない")
        engine.startNew(keep: AskConversationRule.keepsOnNew(isPro: false), userId: "u1")
        XCTAssertFalse(engine.isActive)
        XCTAssertTrue(AskHistoryStore(defaults: d).conversations(userId: "u1").items.isEmpty, "無料で前の会話が残った")
        let reopened = AskEngine(history: AskHistoryStore(defaults: d))
        reopened.resume(userId: "u1")
        XCTAssertFalse(reopened.isActive, "新しく頼んだのに開き直すと前の会話が出た")
        XCTAssertEqual(engine.usage?.day.remaining, 2, "新しく頼むと残りの回数まで消えた")
    }

    /// Pro: 新しく頼むと今の会話は一覧に残り、選べばその続きから話せる（AI は呼ばない）
    func testProKeepsConversationsAndContinues() async throws {
        let d = defaults()
        let calls = Calls()
        let engine = AskEngine(history: AskHistoryStore(defaults: d))
        await engine.start("香川で夕日がきれいな所は？", backend: try backend(calls))
        let a = try XCTUnwrap(engine.conversationId)
        XCTAssertFalse(AskConversationRule.confirmsNew(isPro: true, hasConversation: true), "Pro で確かめを出した")
        engine.startNew(keep: AskConversationRule.keepsOnNew(isPro: true), userId: "u1")
        var list = AskHistoryStore(defaults: d).conversations(userId: "u1")
        XCTAssertNil(list.currentId)
        XCTAssertEqual(AskConversationRule.listed(list, isPro: true).map(\.id), [a], "Pro で前の会話が一覧に無い")

        await engine.start("京都で紅葉は？", backend: try backend(calls))
        let b = try XCTUnwrap(engine.conversationId)
        XCTAssertNotEqual(a, b, "新しく頼んだのに同じ会話になった")
        list = AskHistoryStore(defaults: d).conversations(userId: "u1")
        XCTAssertEqual(AskConversationRule.listed(list, isPro: true).map(\.id), [a], "一覧に今の会話を混ぜた")

        let used = calls.reserves + calls.deviceAsks
        let saved = try XCTUnwrap(list.items.first { $0.id == a })
        await engine.open(saved, backend: try backend(calls))
        XCTAssertEqual(engine.thread.map(\.question), ["香川で夕日がきれいな所は？"])
        XCTAssertEqual(calls.reserves + calls.deviceAsks, used, "前の会話を開くだけで AI か回数を使った")
        await engine.followUp("雨の日は？", backend: try backend(calls))
        list = AskHistoryStore(defaults: d).conversations(userId: "u1")
        XCTAssertEqual(list.currentId, a)
        XCTAssertEqual(list.items.first?.id, a, "続けた会話が一覧の先頭に来ない")
        XCTAssertEqual(list.current?.thread.count, 2)
        XCTAssertEqual(list.items.count, 2)
    }

    /// Pro が切れたら一覧は出さず、今の会話（最後の1本）だけ。控えは消さないので、また Pro になれば戻る
    func testLapsedProShowsOnlyLastConversation() async throws {
        var list = AskHistoryStore.Conversations()
        list.items = [.init(id: "b", thread: [AskExchange(question: "B", answer: AskAnswer(engine: .device, text: "b"))]),
                      .init(id: "a", thread: [AskExchange(question: "A", answer: AskAnswer(engine: .device, text: "a"))])]
        list.currentId = "b"
        XCTAssertTrue(AskConversationRule.listed(list, isPro: false).isEmpty, "Pro でないのに前の会話の一覧を出した")
        XCTAssertEqual(list.current?.id, "b", "最後の1本が見えない")
        XCTAssertEqual(AskConversationRule.listed(list, isPro: true).map(\.id), ["a"], "また Pro になっても一覧が戻らない")
    }

    /// Pro かどうか: サーバーの回数の返事があればそれ、無ければプロフィール。分からなければ無料
    func testProDecision() async {
        let pro = AskUsage(tier: "pro", kind: "ask", day: .init(used: 1, limit: 20, remaining: 19),
                           month: .init(used: 1, limit: 300, remaining: 299), serverAllowed: true)
        let free = AskUsage(tier: "free", kind: "ask", day: .init(used: 1, limit: 3, remaining: 2),
                            month: .init(used: 1, limit: 10, remaining: 9), serverAllowed: false)
        XCTAssertTrue(AskConversationRule.isPro(usage: pro, profile: false))
        XCTAssertFalse(AskConversationRule.isPro(usage: free, profile: true), "サーバーが無料と言ったのに Pro の扱い（切れた）")
        XCTAssertTrue(AskConversationRule.isPro(usage: nil, profile: true))
        XCTAssertFalse(AskConversationRule.isPro(usage: nil, profile: nil))
    }

    /// 残すのは `AskHistoryStore.limit` 件まで。古い順に落とす
    func testConversationsCappedOldestDropped() async {
        let store = AskHistoryStore(defaults: defaults())
        for i in 0..<(AskHistoryStore.limit + 3) {
            store.saveConversation(id: "c\(i)", thread: [AskExchange(question: "Q\(i)", answer: AskAnswer(engine: .device))], userId: "u1")
        }
        let list = store.conversations(userId: "u1")
        XCTAssertEqual(list.items.count, AskHistoryStore.limit)
        XCTAssertEqual(list.items.first?.id, "c\(AskHistoryStore.limit + 2)")
        XCTAssertFalse(list.items.contains { $0.id == "c0" }, "古い会話から落としていない")
    }

    // MARK: - 消える所（他の人に前の人の会話を出さない）

    func testClearedBySignOutClearAllRemoveAndAccountRemoval() async throws {
        let d = defaults()
        let store = AskHistoryStore(defaults: d)
        let thread = [AskExchange(question: "香川で夕日は？", answer: AskAnswer(engine: .device, text: "屋島"))]
        store.saveConversation(id: "x", thread: thread, userId: "u1")
        store.forgetOnSignOut(userId: "u1")
        XCTAssertTrue(store.conversations(userId: "u1").items.isEmpty, "ログアウトで会話が残った")

        store.saveConversation(id: "x", thread: thread, userId: "u1")
        store.removeAll(userId: "u1")
        XCTAssertTrue(store.conversations(userId: "u1").items.isEmpty, "「すべて消す」で会話が残った")

        store.saveConversation(id: "x", thread: thread, userId: "u1")
        store.saveConversation(id: "y", thread: [AskExchange(question: "京都で紅葉は？", answer: AskAnswer(engine: .device))], userId: "u1")
        store.remove("香川で夕日は？", userId: "u1")
        XCTAssertEqual(store.conversations(userId: "u1").items.map(\.id), ["y"], "最近の検索の × でその会話が残った")

        store.saveConversation(id: "z", thread: thread, userId: "u9")
        AccountLocalData.remove(userId: "u9", username: nil, defaults: d,
                                draftDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                offlineTripsRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                passRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                feedbackRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertTrue(store.conversations(userId: "u9").items.isEmpty, "退会で会話が残った")
    }

    /// 画面を閉じている間に「すべて消す」をした: 開き直すと、持っていた会話も外す。人が替わったら空にする
    func testResumeDropsConversationClearedElsewhereAndResetOnAccountChange() async throws {
        let d = defaults()
        let calls = Calls()
        let engine = AskEngine(history: AskHistoryStore(defaults: d))
        await engine.start("香川で夕日がきれいな所は？", backend: try backend(calls))
        AskHistoryStore(defaults: d).removeAll(userId: "u1")
        engine.resume(userId: "u1")
        XCTAssertFalse(engine.isActive, "消した会話を画面に残した")

        await engine.start("京都で紅葉は？", backend: try backend(calls))
        engine.carriedDraft = "打ちかけ"
        engine.reset()
        XCTAssertFalse(engine.isActive)
        XCTAssertNil(engine.conversationId)
        XCTAssertNil(engine.takeCarriedDraft(), "人が替わっても打ちかけの字を残した")
    }

    /// 前からある答えの控えは、会話の一覧に移して見せる（今の会話は無し＝開くと何も頼んでいない画面）
    func testMigratesExistingAnswersIntoConversations() async {
        let store = AskHistoryStore(defaults: defaults())
        let a = AskExchange(question: "金沢のおすすめは？", answer: AskAnswer(engine: .device, text: "兼六園です。"))
        let b = AskExchange(question: "京都で紅葉は？", answer: AskAnswer(engine: .device, text: "永観堂です。"))
        store.remember([a], userId: "u1", now: Date(timeIntervalSince1970: 1_795_000_000))
        store.remember([b], userId: "u1", now: Date(timeIntervalSince1970: 1_795_000_000 + 86_400))
        let list = store.conversations(userId: "u1")
        XCTAssertEqual(list.items.map(\.question), ["京都で紅葉は？", "金沢のおすすめは？"])
        XCTAssertNil(list.currentId)
        // 見本の UI テストで空にしたら、移し直さない
        store.forgetConversations(userId: "u1")
        XCTAssertTrue(store.conversations(userId: "u1").items.isEmpty)
    }

    // MARK: - 探すの最近の検索に AI の頼みを出さない（2026-11-21 owner「探すの方にまで AI で頼んだ履歴出てくるのいやだな」）

    /// 頼みと質問の形の文は出さない・覚えない。前から混ざっていた文は読むときに控えからも外す。ふつうの検索の言葉は残す
    func testRecentSearchesHideAskSentences() async {
        let d = defaults()
        XCTAssertTrue(RecentSearchesStore.isAsk("近くで夕日がきれいな所は？"))
        XCTAssertTrue(RecentSearchesStore.isAsk("金沢でおすすめの観光スポットを教えて"))
        XCTAssertFalse(RecentSearchesStore.isAsk("京都"), "ふつうの検索の言葉を AI の頼みとみなした")
        XCTAssertFalse(RecentSearchesStore.isAsk("嵐山"), "ふつうの検索の言葉を AI の頼みとみなした")
        // 前の作りで混ざった履歴（#675 より前は探すの欄から AI に頼んでいた）
        d.set(["近くで夕日がきれいな所は？", "京都", "金沢でおすすめの観光スポットを教えて", "嵐山"], forKey: RecentSearchesStore.key(for: "u1"))
        let store = RecentSearchesStore(defaults: d)
        XCTAssertEqual(store.searchWords(userId: "u1"), ["京都", "嵐山"])
        XCTAssertEqual(store.words(userId: "u1"), ["京都", "嵐山"], "古い AI の頼みを控えから外していない")
        // 探すの「すべて消す」は探すの言葉だけ。AI の会話は残る
        let ask = AskHistoryStore(defaults: d)
        ask.saveConversation(id: "c", thread: [AskExchange(question: "香川で夕日は？", answer: AskAnswer(engine: .device))], userId: "u1")
        store.removeAll(userId: "u1")
        XCTAssertEqual(ask.conversations(userId: "u1").items.map(\.id), ["c"], "探すの「すべて消す」で AI の会話まで消えた")
    }

    /// Pro の前の会話の一覧から、1つずつ・全部消せる（いま画面に出ている会話は残す）
    func testConversationListDeletion() async {
        let store = AskHistoryStore(defaults: defaults())
        for id in ["a", "b", "c"] {
            store.saveConversation(id: id, thread: [AskExchange(question: id, answer: AskAnswer(engine: .device))], userId: "u1")
        }
        store.removeConversation("b", userId: "u1")
        XCTAssertEqual(store.conversations(userId: "u1").items.map(\.id), ["c", "a"])
        store.removeConversations(keeping: "c", userId: "u1")
        let list = store.conversations(userId: "u1")
        XCTAssertEqual(list.items.map(\.id), ["c"], "すべて消すで今の会話まで消えたか、前の会話が残った")
        XCTAssertEqual(list.currentId, "c")
        store.removeConversations(keeping: nil, userId: "u1")
        XCTAssertTrue(store.conversations(userId: "u1").items.isEmpty)
    }
}
