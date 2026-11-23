import XCTest
@testable import JourneyPhoto

/// サーバーの AI に送る前の同意（審査 5.1.2(i)・`AIServerConsent`・2026-11-22 判断）。
/// 同意前は送らない、同意後は聞かない、取り消すとまた聞く、端末だけの道では出ない、全ての送信の道が同意を通る、文に内部の名前が無い
@MainActor
final class AIServerConsentTests: XCTestCase {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "AIServerConsentTests.\(UUID().uuidString)")!
    }

    final class Count { var n = 0 }

    private struct NoToken: TokenProviding {
        func idToken() async throws -> String? { nil }
        func accountGone(idToken: String) async {}
    }

    // MARK: - 覚える、聞く、取り消す

    func testAsksOnceAndRemembersAgreement() async {
        let d = defaults(), shown = Count()
        let consent = AIServerConsent(defaults: d, presenter: { _, _ in shown.n += 1; return true })
        XCTAssertFalse(consent.isAccepted)
        let first = await consent.request()
        XCTAssertTrue(first)
        XCTAssertTrue(consent.isAccepted)
        let second = await consent.request()
        XCTAssertTrue(second)
        XCTAssertEqual(shown.n, 1, "同意したあとにまた聞いた")
        // 端末に覚えている（アプリを開き直しても聞かない）
        XCTAssertTrue(AIServerConsent(defaults: d, presenter: { _, _ in shown.n += 1; return false }).isAccepted)
        XCTAssertTrue(AIServerConsent.accepted(defaults: d))
    }

    func testCancelDoesNotRememberAndAsksAgainNextTime() async {
        let d = defaults(), shown = Count()
        let consent = AIServerConsent(defaults: d, presenter: { _, _ in shown.n += 1; return false })
        let first = await consent.request()
        XCTAssertFalse(first)
        XCTAssertFalse(consent.isAccepted)
        XCTAssertFalse(AIServerConsent.accepted(defaults: d))
        _ = await consent.request()
        XCTAssertEqual(shown.n, 2)
    }

    func testRevokeAsksAgainBeforeNextSend() async {
        let d = defaults(), shown = Count()
        let consent = AIServerConsent(defaults: d, presenter: { _, _ in shown.n += 1; return true })
        _ = await consent.request()
        consent.revoke()
        XCTAssertFalse(consent.isAccepted)
        XCTAssertThrowsError(try AIServerConsent.requireAccepted(defaults: d))
        _ = await consent.request()
        XCTAssertEqual(shown.n, 2, "取り消したのに次の送信の前に聞かなかった")
    }

    func testNoPresenterMeansNotSent() async {
        let consent = AIServerConsent(defaults: defaults(), presenter: nil)
        let ok = await consent.request()
        XCTAssertFalse(ok, "シートを出せないのに送ってよいことにした")
    }

    func testNewerVersionAsksAgain() async {
        let d = defaults()
        AIServerConsent(defaults: d, requiredVersion: 1).accept()
        XCTAssertTrue(AIServerConsent(defaults: d, requiredVersion: 1).isAccepted)
        XCTAssertFalse(AIServerConsent(defaults: d, requiredVersion: 2).isAccepted)
    }

    func testTwoPathsAtOnceShowOneSheet() async {
        let shown = Count()
        let consent = AIServerConsent(defaults: defaults(), presenter: { _, _ in
            shown.n += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
            return true
        })
        async let a = consent.request()
        async let b = consent.request()
        let (x, y) = await (a, b)
        XCTAssertTrue(x && y)
        XCTAssertEqual(shown.n, 1, "同時に頼まれてシートを2枚出した")
    }

    // MARK: - 送る口が止める（画面で聞き忘れても送らない）

    func testAskServiceRefusesToSendWithoutConsent() async throws {
        let std = UserDefaults.standard
        let saved = std.object(forKey: AIServerConsent.key)
        defer { if let saved { std.set(saved, forKey: AIServerConsent.key) } else { std.removeObject(forKey: AIServerConsent.key) } }
        std.removeObject(forKey: AIServerConsent.key)
        do {
            _ = try await AskService(api: nil).ask(text: "夕日がきれいな所", history: [], sources: [])
            XCTFail("同意の無いまま送った")
        } catch let e as AIServerConsent.NotAccepted {
            XCTAssertEqual(e, AIServerConsent.NotAccepted())
        }
        // 同意したら送る口まで進む（ここでは送り先が無いので「使えない」）
        std.set(AIServerConsent.currentVersion, forKey: AIServerConsent.key)
        do {
            _ = try await AskService(api: nil).ask(text: "夕日がきれいな所", history: [], sources: [])
            XCTFail("送り先が無いのに答えた")
        } catch is AIServerConsent.NotAccepted {
            XCTFail("同意したのに止めた")
        } catch {}
    }

    func testTripPlanRefusesToSendWithoutConsent() async throws {
        let std = UserDefaults.standard
        let saved = std.object(forKey: AIServerConsent.key)
        std.removeObject(forKey: AIServerConsent.key)
        // 見本の AI でも、シートを出す試験の形（`JPAIConsentAsk`）なら同意を求める
        std.set(true, forKey: TripAIFixture.key)
        std.set(true, forKey: AIServerConsent.askKey)
        std.set(0.0, forKey: TripAIFixture.delayKey)
        defer {
            if let saved { std.set(saved, forKey: AIServerConsent.key) } else { std.removeObject(forKey: AIServerConsent.key) }
            std.removeObject(forKey: TripAIFixture.key)
            std.removeObject(forKey: AIServerConsent.askKey)
            std.removeObject(forKey: TripAIFixture.delayKey)
        }
        let rows = try AskSamples.ledger()
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())
        do {
            _ = try await TripAIService(api: api).plan(request: "香川で日帰り", days: 1, candidates: Array(rows.prefix(3)))
            XCTFail("同意の無いまま旅行プランの頼みを送った")
        } catch is AIServerConsent.NotAccepted {}
        std.set(AIServerConsent.currentVersion, forKey: AIServerConsent.key)
        let (plan, _) = try await TripAIService(api: api).plan(request: "香川で日帰り", days: 1, candidates: Array(rows.prefix(3)))
        XCTAssertFalse(plan.stops.isEmpty)
    }

    // MARK: - AI に頼む

    private let pro = AskUsage(tier: "pro", kind: "ask", day: .init(used: 1, limit: 20, remaining: 19),
                               month: .init(used: 1, limit: 300, remaining: 299), serverAllowed: true)
    private let free = AskUsage(tier: "free", kind: "ask", day: .init(used: 1, limit: 3, remaining: 2),
                                month: .init(used: 1, limit: 10, remaining: 9), serverAllowed: false)

    final class Calls {
        var reserves: [AskService.Via] = []
        var serverAsks = 0
        var deviceAsks = 0
        var consents = 0
    }

    private func backend(deviceAI: Bool, usage: AskUsage, consent: Bool, likely: Bool = true,
                         accepted: @escaping () -> Bool = { false }, calls: Calls) throws -> AskEngine.Backend {
        let rows = try AskSamples.ledger()
        return AskEngine.Backend(
            signedIn: { true }, offline: { false }, deviceAI: { deviceAI },
            library: { _ in AskLibrary(spots: rows, photos: []) },
            reserve: { _, via in calls.reserves.append(via); return usage },
            serverAsk: { _, _, _ in calls.serverAsks += 1; return .init(answer: "夕方に向く所を選びました。", general: false) },
            deviceAsk: { _, _, _ in
                calls.deviceAsks += 1
                return AskDevice.Result(text: "屋島がおすすめです。", general: false, picks: [], photoIds: [], sources: [])
            },
            details: { $0 }, userId: { "u1" },
            serverConsent: { calls.consents += 1; return consent },
            serverLikely: { likely }, consentAccepted: accepted)
    }

    private func engine() -> AskEngine {
        AskEngine(history: AskHistoryStore(defaults: defaults()))
    }

    /// 「やめる」なら送らない。回数も取らない（回数を取る前に聞く）。言葉の表で答え、会話の間は聞き直さない
    func testAskCancelSendsNothingAndAnswersWithoutAI() async throws {
        let calls = Calls(), e = engine()
        let b = try backend(deviceAI: false, usage: pro, consent: false, calls: calls)
        await e.start("香川で夕日がきれいな所を教えて", backend: b)
        XCTAssertEqual(calls.serverAsks, 0, "やめたのにサーバーへ送った")
        XCTAssertTrue(calls.reserves.isEmpty, "やめたのに回数を取った")
        let a = try XCTUnwrap(e.thread.first?.answer)
        XCTAssertEqual(a.engine, .table)
        XCTAssertEqual(a.note, AskText.consentDeclinedLine)
        XCTAssertNotEqual(a.engine, .server)
        await e.followUp("おすすめの観光スポット教えて", backend: b)
        XCTAssertEqual(calls.consents, 1, "同じ会話で「やめる」のあとにまた聞いた")
        XCTAssertEqual(calls.serverAsks, 0)
        // 新しい会話ではまた聞く
        e.reset()
        await e.start("香川で夕日がきれいな所を教えて", backend: b)
        XCTAssertEqual(calls.consents, 2)
    }

    /// 同意したら送る（同意済みの口は聞かずに true を返す）
    func testAskAgreeSends() async throws {
        let calls = Calls(), e = engine()
        await e.start("香川で夕日がきれいな所を教えて", backend: try backend(deviceAI: false, usage: pro, consent: true, calls: calls))
        XCTAssertEqual(calls.serverAsks, 1)
        XCTAssertEqual(calls.reserves, [.server])
        XCTAssertEqual(e.thread.first?.answer.engine, .server)
    }

    /// 端末の AI の iPhone では聞かない（送らない）
    func testDeviceRouteNeverAsks() async throws {
        let calls = Calls(), e = engine()
        await e.start("香川で夕日がきれいな所を教えて", backend: try backend(deviceAI: true, usage: free, consent: false, calls: calls))
        XCTAssertEqual(calls.consents, 0, "端末の AI だけの道で同意を聞いた")
        XCTAssertEqual(calls.deviceAsks, 1)
        XCTAssertEqual(calls.serverAsks, 0)
    }

    /// 無料と分かっている人（サーバーが送らせない）には聞かない
    func testFreeWithoutDeviceAIIsNotAsked() async throws {
        let calls = Calls(), e = engine()
        await e.start("香川で夕日がきれいな所を教えて",
                      backend: try backend(deviceAI: false, usage: free, consent: false, likely: false, calls: calls))
        XCTAssertEqual(calls.consents, 0, "送らない人に同意を聞いた")
        XCTAssertEqual(calls.serverAsks, 0)
        XCTAssertEqual(e.thread.first?.answer.note, AskText.noDeviceAILine)
    }

    /// 見立てで無料でも、サーバーが送ってよいと答えたら送る直前に聞く（聞かずに送らない）
    func testMisjudgedFreeIsAskedRightBeforeSending() async throws {
        let calls = Calls(), e = engine()
        await e.start("香川で夕日がきれいな所を教えて",
                      backend: try backend(deviceAI: false, usage: pro, consent: false, likely: false, calls: calls))
        XCTAssertEqual(calls.consents, 1)
        XCTAssertEqual(calls.serverAsks, 0, "同意を聞かずに送った")
    }

    // MARK: - 旅行プラン

    /// 「AI に送らなかった」の札から「AI で整える」→ 同意して送ったら、札の帯は「送らなかった」のまま残らない（Mac run 1729）
    func testDeclinedBandClearsAfterAgreeing() async throws {
        let std = UserDefaults.standard
        std.set(true, forKey: TripAIFixture.key)
        std.set(0.0, forKey: TripAIFixture.delayKey)
        defer {
            std.removeObject(forKey: TripAIFixture.key)
            std.removeObject(forKey: TripAIFixture.delayKey)
        }
        let rows = try AskSamples.ledger()
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())
        let runner = TripAIRunner(onDevice: false, consent: { true })
        let result = await runner.revise(request: "整えて", current: [Array(rows.prefix(3))], candidates: [], index: rows,
                                         offline: false, service: TripAIService(api: api), title: "香川", countAfter: true) { _, _ in 10 }
        let r = try XCTUnwrap(result)
        XCTAssertTrue(runner.askedServer)
        XCTAssertEqual(r.mode, .ai)
        XCTAssertEqual(TripReplan.noteMode(after: r, current: .declined), .ai, "同意して送ったのに「送らなかった」の帯が残る")
        // 送った回の理由に替える（回数など）。また「やめる」なら今のまま。ほかの帯は組み直しでは替えない
        let limited = TripAIResult(title: "", days: [], reason: "", removed: [], mode: .limited(.day), candidates: [])
        XCTAssertEqual(TripReplan.noteMode(after: limited, current: .declined), .limited(.day))
        let declinedAgain = TripAIResult(title: "", days: [], reason: "", removed: [], mode: .declined, candidates: [])
        XCTAssertEqual(TripReplan.noteMode(after: declinedAgain, current: .declined), .declined)
        XCTAssertEqual(TripReplan.noteMode(after: nil, current: .declined), .declined)
        XCTAssertEqual(TripReplan.noteMode(after: r, current: .offline), .offline)
        XCTAssertEqual(TripReplan.noteMode(after: r, current: .ai), .ai)
        // 画面はこの決まりで札を替える（組み直しの結果を受けたあと）
        let detail = try text("TripPlanDetailView.swift")
        XCTAssertTrue(detail.contains("TripReplan.noteMode(after: result, current: now.mode)"), "日程の画面が札の帯の理由を替えていない")
    }

    /// 「やめる」の当たりは 48（半分の高さのシートは iOS 26 で約 96% に縮む。44 だと 42.4 になった・Mac run 1729）
    func testCancelHitAreaSurvivesSheetScaling() async {
        XCTAssertGreaterThanOrEqual(AIServerConsentLayout.cancelHitHeight * 0.96, 44)
    }

    func testTripPlanCancelBuildsWithoutAIAndSendsNothing() async throws {
        let std = UserDefaults.standard
        std.set(true, forKey: TripAIFixture.key)
        std.set(0.0, forKey: TripAIFixture.delayKey)
        defer {
            std.removeObject(forKey: TripAIFixture.key)
            std.removeObject(forKey: TripAIFixture.delayKey)
        }
        let rows = try AskSamples.ledger()
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())
        let asked = Count()
        let runner = TripAIRunner(onDevice: false, consent: { asked.n += 1; return false })
        let built = await runner.build(TripAIAsk.reading("香川で日帰り", spots: rows), index: rows, wishlist: [], offline: false,
                                       service: TripAIService(api: api)) { _, _ in 10 }
        XCTAssertEqual(asked.n, 1)
        XCTAssertEqual(built?.mode, .declined)
        XCTAssertFalse(built?.days.isEmpty ?? true, "やめても AI なしで組んで行き止まりにしない")
        XCTAssertFalse(runner.askedServer, "やめたのに送った扱いにした")
        XCTAssertNotNil(AskPlanFlowText.modeNote(.declined))
    }

    func testTripDeviceRouteNeverAsks() async throws {
        let rows = try AskSamples.ledger()
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())
        let asked = Count()
        let runner = TripAIRunner(onDevice: true, devicePlanner: { _, _ in TripAIPlan(title: "", days: 1, stops: [.init(n: 1, day: 1)], reason: "") },
                                  reserver: { _ in AskUsage(tier: "free", kind: "trip", day: .init(used: 1, limit: 5, remaining: 4),
                                                            month: .init(used: 1, limit: 30, remaining: 29), serverAllowed: false) },
                                  consent: { asked.n += 1; return false })
        _ = await runner.revise(request: "ゆっくり", current: [Array(rows.prefix(2))], candidates: [], index: rows,
                                offline: false, service: TripAIService(api: api), title: "香川", countAfter: true) { _, _ in 10 }
        XCTAssertEqual(asked.n, 0, "端末の AI の道で同意を聞いた")
    }

    // MARK: - 待ちが必ず解ける（2026-11-22 確かめ役の指摘）

    /// シートが返事をしない（出し損ねた、下の画面ごと閉じられた）ままでも、時間切れで「やめる」になり、待ちが残らない
    func testTimeoutReleasesTheWait() async {
        let shown = Count()
        let consent = AIServerConsent(defaults: defaults(), timeout: 0.05, presenter: { _, _ in
            shown.n += 1
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return false
        })
        let started = Date()
        let first = await consent.request()
        XCTAssertFalse(first)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "返事の来ないシートを待ち続けた")
        // 待ちが残っていない: 次の頼みはシートを出し直す（前の待ちに相乗りして止まらない）
        let second = await consent.request()
        XCTAssertFalse(second)
        XCTAssertEqual(shown.n, 2)
    }

    /// 時間切れで返したら、出ているシートも閉じる（次の頼みで2枚目を重ねない）。ボタンで答えた回は閉じる口を呼ばない
    func testTimeoutClosesTheOpenSheet() async throws {
        let closed = Count()
        let consent = AIServerConsent(defaults: defaults(), timeout: 0.05, presenter: { _, handle in
            handle.close = { closed.n += 1 }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return false
        })
        let ok = await consent.request()
        XCTAssertFalse(ok)
        XCTAssertEqual(closed.n, 1, "時間切れなのに出ているシートを閉じなかった")
        let answered = Count()
        let byButton = AIServerConsent(defaults: defaults(), timeout: 5, presenter: { _, handle in
            handle.close = { answered.n += 1 }
            handle.close = nil   // ボタンで答えたとき、出す側は閉じる口を外す
            return true
        })
        let agreed = await byButton.request()
        XCTAssertTrue(agreed)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(answered.n, 0)
        let h = AIConsentSheetHandle()
        h.close = { closed.n += 1 }
        h.closeIfOpen(); h.closeIfOpen()
        XCTAssertEqual(closed.n, 2, "閉じる口を2回呼んだ")
    }

    /// 時間切れのあとで「同意して続ける」が押されたら、同意は覚える（その回は送らない）
    func testLateAgreeIsRemembered() async throws {
        let d = defaults()
        let consent = AIServerConsent(defaults: d, timeout: 0.05, presenter: { _, _ in
            try? await Task.sleep(nanoseconds: 200_000_000)
            return true
        })
        let ok = await consent.request()
        XCTAssertFalse(ok)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(consent.isAccepted)
    }

    /// 答えは1回だけ返す（ボタン、払って閉じる、閉じられた、時間切れが重なっても）
    func testOnceAnswersOnlyOnce() async {
        var keep: AIConsentOnce?
        let got = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let once = AIConsentOnce(c)
            keep = once
            XCTAssertFalse(once.isDone)
            once.finish(true)
            once.finish(false)
        }
        XCTAssertTrue(got)
        XCTAssertEqual(keep?.isDone, true)
    }

    /// シートが消えたとき「もう戻らない」と見る条件。上に別の画面が出ただけなら待ち続ける
    func testGoneRules() async {
        XCTAssertTrue(AIServerConsentPresenter.gone(isBeingDismissed: true, hasPresenter: true, presenterDismissing: false))
        XCTAssertTrue(AIServerConsentPresenter.gone(isBeingDismissed: false, hasPresenter: false, presenterDismissing: false))
        XCTAssertTrue(AIServerConsentPresenter.gone(isBeingDismissed: false, hasPresenter: true, presenterDismissing: true),
                      "下の画面ごと閉じられたのに待ち続ける")
        XCTAssertFalse(AIServerConsentPresenter.gone(isBeingDismissed: false, hasPresenter: true, presenterDismissing: false))
        XCTAssertTrue(AIServerConsentPresenter.mustSettle(isBeingPresented: true, isBeingDismissed: false))
        XCTAssertTrue(AIServerConsentPresenter.mustSettle(isBeingPresented: false, isBeingDismissed: true))
        XCTAssertFalse(AIServerConsentPresenter.mustSettle(isBeingPresented: false, isBeingDismissed: false))
        // 上の頼みのシートが閉じる途中（探すときに飛ばした）、最前面が動きの途中なら待つ
        XCTAssertTrue(AIServerConsentPresenter.mustSettle(isBeingPresented: false, isBeingDismissed: false, skippedDismissing: true),
                      "上の画面が閉じる途中なのにすぐ出した")
        XCTAssertTrue(AIServerConsentPresenter.mustSettle(isBeingPresented: false, isBeingDismissed: false, inTransition: true),
                      "動きの途中なのにすぐ出した")
        XCTAssertFalse(AIServerConsentPresenter.mustSettle(isBeingPresented: false, isBeingDismissed: false,
                                                           skippedDismissing: false, inTransition: false))
    }

    /// 設定から開くシートは「この iPhone では」と言わない（端末の AI のある iPhone でも開ける）
    func testSettingsLeadDoesNotClaimThisIPhone() async {
        XCTAssertTrue(AIServerConsentText.lead(.send).hasPrefix("この iPhone では"))
        XCTAssertFalse(AIServerConsentText.lead(.settings).contains("この iPhone"))
        XCTAssertTrue(AIServerConsentText.lead(.settings).contains("サーバーに送信し、委託先の AI で処理します"))
    }

    /// 会話の中で「やめる」のあと設定でオンにしたら、同じ会話でも送る
    func testAgreeInSettingsAfterCancelSendsInSameConversation() async throws {
        let calls = Calls(), e = engine()
        var accepted = false
        let b = try backend(deviceAI: false, usage: pro, consent: false, accepted: { accepted }, calls: calls)
        await e.start("香川で夕日がきれいな所を教えて", backend: b)
        XCTAssertEqual(calls.serverAsks, 0)
        accepted = true
        await e.followUp("おすすめの観光スポット教えて", backend: b)
        XCTAssertEqual(calls.serverAsks, 1, "設定で同意したのに、この会話では送らなかった")
    }

    /// 同意を待つ間に画面を閉じた（取り消した）なら送らない
    func testTripCancelledWhileAskingSendsNothing() async throws {
        let std = UserDefaults.standard
        std.set(true, forKey: TripAIFixture.key)
        std.set(0.0, forKey: TripAIFixture.delayKey)
        defer {
            std.removeObject(forKey: TripAIFixture.key)
            std.removeObject(forKey: TripAIFixture.delayKey)
        }
        let rows = try AskSamples.ledger()
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())
        final class Holder { var task: Task<TripAIResult?, Never>? }
        let holder = Holder()
        let runner = TripAIRunner(onDevice: false, consent: {
            holder.task?.cancel()
            return true
        })
        let task = Task { @MainActor in
            await runner.build(TripAIAsk.reading("香川で日帰り", spots: rows), index: rows, wishlist: [], offline: false,
                               service: TripAIService(api: api)) { _, _ in 10 }
        }
        holder.task = task
        let built = await task.value
        XCTAssertNil(built)
        XCTAssertFalse(runner.askedServer, "取り消したのに送った")
    }

    // MARK: - 見張り: 送る道を足したら落ちる

    private var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
    }

    private func swiftFiles() -> [(name: String, text: String)] {
        FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            .compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { (url.lastPathComponent, $0) } }
    }

    /// サーバーの AI の口（`/user/trip-ai`）を呼ぶのは2つのファイルだけ。送る action は決まった4つだけで、
    /// 文を送る2つ（ask、plan）は送る前に `requireAccepted` を通す。新しい口や action を足したら、ここで落ちる
    func testEveryServerAISendPassesConsent() async throws {
        let files = swiftFiles()
        XCTAssertFalse(files.isEmpty)
        let callers = files.filter { $0.text.contains("\"/user/trip-ai\"") }.map(\.name).sorted()
        XCTAssertEqual(callers, ["AskService.swift", "TripAIService.swift"], "サーバーの AI の口を呼ぶ所が増えた。同意を通してから足す")

        let regex = try NSRegularExpression(pattern: #"action(?:\s*=|:)\s*"([a-z]+)""#)
        var actions = Set<String>()
        for f in files where callers.contains(f.name) {
            let ns = f.text as NSString
            for m in regex.matches(in: f.text, range: NSRange(location: 0, length: ns.length)) {
                actions.insert(ns.substring(with: m.range(at: 1)))
            }
        }
        XCTAssertEqual(actions, ["status", "reserve", "ask", "plan"],
                       "サーバーの AI に送る action が増えた。文や日程を送るなら `AIServerConsent.requireAccepted` を通す")

        let ask = try body(of: "func ask(text: String", in: try text("AskService.swift"))
        try assertGuarded(ask, before: "AskRequest(", "AskService.ask")
        let plan = try body(of: "func plan(request: String", in: try text("TripAIService.swift"))
        try assertGuarded(plan, before: "action: \"plan\"", "TripAIService.plan")
        // 文を送る形は、見張った関数の中でしか作らない
        XCTAssertEqual(try text("AskService.swift").components(separatedBy: "AskRequest(text:").count - 1, 1)
        XCTAssertEqual(try text("TripAIService.swift").components(separatedBy: "action: \"plan\"").count - 1, 1)
    }

    /// 画面の道も同意を聞く（聞かずに送る口へ行くと、言葉の表の答えになってしまう）:
    /// AI に頼むの外の口は `serverConsent` を渡し、旅行プランはサーバーへ送る前に `serverConsented` を通す
    func testScreensAskBeforeSending() async throws {
        for f in swiftFiles() where f.text.contains("AskEngine.Backend(") {
            XCTAssertTrue(f.text.contains("serverConsent: { await AIServerConsent.shared.request() }"),
                          "\(f.name) が AI に頼むの外の口に同意の口を渡していない")
        }
        let runner = try text("TripAIRunner.swift")
        let gate = try XCTUnwrap(runner.range(of: "!(await serverConsented())"))
        let send = try XCTUnwrap(runner.range(of: "service.plan(request:"))
        XCTAssertLessThan(gate.lowerBound, send.lowerBound, "旅行プランの AI が同意を聞く前に送る")
        XCTAssertEqual(runner.components(separatedBy: "service.plan(request:").count - 1, 1)
        let planCallers = swiftFiles().filter { $0.text.contains(".plan(request:") }.map(\.name)
        XCTAssertEqual(planCallers, ["TripAIRunner.swift"], "旅行プランの AI を呼ぶ所が増えた。同意を通してから足す")
        let askCallers = swiftFiles().filter { $0.text.contains(".ask(text:") }.map(\.name).sorted()
        XCTAssertEqual(askCallers, ["AskScreen.swift"], "AI に頼むのサーバーの口を呼ぶ所が増えた。同意を通してから足す")
    }

    private func text(_ name: String) throws -> String {
        try XCTUnwrap(swiftFiles().first { $0.name == name }?.text, name)
    }

    /// 関数の頭から、次の `func ` までを返す（見張りの範囲）
    private func body(of head: String, in text: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: head), head)
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n    func ")?.lowerBound ?? rest.range(of: "\n    private func ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    private func assertGuarded(_ body: String, before marker: String, _ name: String) throws {
        let gate = try XCTUnwrap(body.range(of: "try AIServerConsent.requireAccepted()"), "\(name) が同意を見ずに送る")
        let send = try XCTUnwrap(body.range(of: marker), "\(name) の送る形が見つからない")
        XCTAssertLessThan(gate.lowerBound, send.lowerBound, "\(name) が同意を見る前に送る形を作る")
    }

    // MARK: - 文

    /// 同意のシートと設定の行の文に、内部の名前（使っている AI、サービス、地域、モデル）が無い。中黒で区切らない
    func testWordingHasNoInternalNames() async {
        let shown = AIServerConsentText.all + [AskText.consentDeclinedLine, AskPlanFlowText.modeNote(.declined) ?? ""]
        let banned = ["AWS", "Amazon", "Bedrock", "東京", "Tokyo", "Nova", "Claude", "Anthropic", "Lambda", "モデル", "model", "API"]
        for line in shown {
            for word in banned {
                XCTAssertFalse(line.localizedCaseInsensitiveContains(word), "文に内部の名前「\(word)」: \(line)")
            }
            XCTAssertFalse(line.contains("・") || line.contains("·"), "中黒で区切っている: \(line)")
        }
        // 何を、どこへ、何のために（プライバシーポリシー第9条と注記の言い方）
        XCTAssertTrue(AIServerConsentText.askItem.contains("入力内容と直前のやりとり"))
        XCTAssertTrue(AIServerConsentText.tripItem.contains("頼みの内容と日程"))
        XCTAssertTrue(AIServerConsentText.lead.contains("サーバーに送信し、委託先の AI で処理します"))
        XCTAssertTrue(AIServerConsentText.lead.contains("回答と旅行プランの作成のため"))
        XCTAssertEqual(AIServerConsentText.agree, "同意して続ける")
        XCTAssertEqual(AIServerConsentText.cancel, "やめる")
    }
}
