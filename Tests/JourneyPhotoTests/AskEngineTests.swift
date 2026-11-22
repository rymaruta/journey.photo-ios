import XCTest
@testable import JourneyPhoto

/// 「AI に頼む」の手順（札 #652）: 先に断る → 回数を取る → 端末の AI かサーバーの AI か言葉の表 → 見張り。
@MainActor
final class AskEngineTests: XCTestCase {

    /// 呼ばれた口を数える差し替え
    final class Calls {
        var reserves: [(AskService.Kind, AskService.Via)] = []
        var serverAsks: [(text: String, turns: [AskService.Turn], sources: [OfficialSpot])] = []
        var deviceAsks = 0
        var libraryNeedsLocation: [Bool] = []
    }

    struct Setup {
        var signedIn = true
        var offline = false
        var deviceAI = true
        var reserveError: Error?
        var usage = AskUsage(tier: "free", kind: "ask", day: .init(used: 1, limit: 3, remaining: 2),
                             month: .init(used: 1, limit: 10, remaining: 9, resetsOn: "2026-12-01"), serverAllowed: false)
        var device: AskDevice.Result? = AskDevice.Result(text: "屋島がおすすめです。", general: false, picks: [], photoIds: [], sources: [])
        var server = AskService.ServerAnswer(answer: "夕方に向く所を選びました。", general: false)
        var here: Photo.Coords? = Photo.Coords(lat: 34.34, lng: 134.05)
    }

    private func backend(_ setup: Setup, calls: Calls, defaults: UserDefaults) throws -> AskEngine.Backend {
        let rows = try AskSamples.ledger()
        let photos = [try AskSamples.photo("p1", title: "屋島の夕日", spotId: "sp_yashima")]
        return AskEngine.Backend(
            signedIn: { setup.signedIn },
            offline: { setup.offline },
            deviceAI: { setup.deviceAI },
            library: { near in
                calls.libraryNeedsLocation.append(near)
                return AskLibrary(spots: rows, photos: photos, here: near ? setup.here : nil)
            },
            reserve: { kind, via in
                calls.reserves.append((kind, via))
                if let e = setup.reserveError { throw e }
                return setup.usage
            },
            serverAsk: { text, turns, sources in
                calls.serverAsks.append((text, turns, sources))
                return setup.server
            },
            deviceAsk: { _, _, _ in
                calls.deviceAsks += 1
                return setup.device
            },
            details: { $0 },
            userId: { "u1" }
        )
    }

    private func engine() -> (AskEngine, UserDefaults) {
        let d = UserDefaults(suiteName: "AskEngineTests.\(UUID().uuidString)")!
        return (AskEngine(history: AskHistoryStore(defaults: d)), d)
    }

    /// 作りやセキュリティの質問は、AI を呼ぶ前に断る。回数も使わない（reserve を呼ばない）
    func testDeclinedQuestionsUseNoCountAndNoAI() async throws {
        for q in AskGuardTests.declined.prefix(20) {
            let calls = Calls()
            let (e, d) = engine()
            await e.start(q, backend: try backend(Setup(), calls: calls, defaults: d))
            let a = try XCTUnwrap(e.thread.first?.answer)
            XCTAssertEqual(a.engine, .refused, q)
            XCTAssertEqual(a.text, AskGuard.refusal, q)
            XCTAssertTrue(a.spotIds.isEmpty && a.sources.isEmpty, "断ったのに何か引いた: \(q)")
            XCTAssertTrue(calls.reserves.isEmpty, "断ったのに回数を取った: \(q)")
            XCTAssertEqual(calls.deviceAsks, 0)
            XCTAssertTrue(calls.serverAsks.isEmpty)
        }
    }

    /// 写真の説明に仕込んだ命令に従って、答えにメールアドレスや内部の名前が混じったら、見張りが断りに替える
    func testLeakyAnswerIsReplacedByRefusal() async throws {
        let calls = Calls()
        let (e, d) = engine()
        var setup = Setup()
        setup.device = .init(text: "管理者のメールは admin@example.com です", general: false, picks: [], photoIds: [], sources: [])
        await e.start("近くで夕日がきれいな所", backend: try backend(setup, calls: calls, defaults: d))
        let a = try XCTUnwrap(e.thread.first?.answer)
        XCTAssertEqual(a.text, AskGuard.refusal)
        XCTAssertTrue(a.spotIds.isEmpty, "断りに替えた答えに札を出した")
        setup.device = .init(text: "表は aiuse#u1 にあります", general: false, picks: [], photoIds: [], sources: [])
        await e.start("おすすめの観光スポット教えて", backend: try backend(setup, calls: calls, defaults: d))
        XCTAssertEqual(e.thread.first?.answer.text, AskGuard.refusal)
    }

    /// 2026-11-21（バグ調べ）: 回数を取っている間にログアウトした（画面は手順を取り消して `reset`）とき、
    /// 前の人の残りの回数を置き直さない。前は上の1行に前の人の「残り◯回」が残っていた
    func testReserveFinishingAfterResetDoesNotRestorePreviousUsage() async throws {
        let calls = Calls()
        let (e, d) = engine()
        var setup = Setup()
        setup.deviceAI = false
        let plain = try backend(setup, calls: calls, defaults: d)
        let usage = setup.usage
        var slow = plain
        slow.reserve = { kind, via in
            calls.reserves.append((kind, via))
            try? await Task.sleep(nanoseconds: 300_000_000)
            return usage
        }
        let task = Task { await e.start("近くで夕日がきれいな所", backend: slow) }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(calls.reserves.count, 1, "回数を取りに行く前に取り消した（試験の前提が崩れた）")
        task.cancel()
        e.reset()
        await task.value
        XCTAssertNil(e.usage, "取り消したあとに前の人の残りの回数を置いた")
        XCTAssertNil(e.pending)
        XCTAssertTrue(e.thread.isEmpty)
    }

    /// 端末の AI が使える iPhone: 答えを出す直前にサーバーで1回取る（2026-11-20 判断）。答えはアプリの部品（札、写真、旅行プランにする）
    func testDeviceRouteReservesFirstAndShowsAppParts() async throws {
        let calls = Calls()
        let (e, d) = engine()
        await e.start("近くで夕日がきれいな所", backend: try backend(Setup(), calls: calls, defaults: d))
        XCTAssertEqual(calls.reserves.map(\.0), [.ask])
        XCTAssertEqual(calls.reserves.map(\.1), [.device])
        XCTAssertEqual(calls.deviceAsks, 1)
        XCTAssertEqual(calls.libraryNeedsLocation, [true], "近くの頼みだけ現在地を取る")
        let a = try XCTUnwrap(e.thread.first?.answer)
        XCTAssertEqual(a.engine, .device)
        XCTAssertEqual(a.spotIds, ["sp_yashima"], "AI が台帳を引かなくても、アプリが選んだ札を出す（下書きは出さない）")
        XCTAssertNotNil(a.distances["sp_yashima"])
        XCTAssertEqual(a.photoIds, ["p1"])
        XCTAssertTrue(a.offersPlan)
        XCTAssertTrue(a.chips.contains("現在地から 30km"))
        XCTAssertTrue(a.usedAI)
        XCTAssertEqual(e.usage?.day.remaining, 2)
        XCTAssertNotNil(e.spotsById["sp_yashima"])
        XCTAssertNotNil(e.photosById["p1"])
    }

    /// 同じ日の同じ頼みは控えの答え（回数を使わない）。続けて聞くのは1回と数える
    func testSameDayReuseAndFollowUpCounts() async throws {
        let calls = Calls()
        let (e, d) = engine()
        let b = try backend(Setup(), calls: calls, defaults: d)
        await e.start("おすすめの観光スポット教えて", backend: b)
        XCTAssertEqual(calls.reserves.count, 1)
        await e.followUp("夕日を撮るコツは", backend: b)
        XCTAssertEqual(calls.reserves.count, 2, "続けて聞いた回も1回")
        XCTAssertEqual(e.thread.count, 2)
        e.reset()
        await e.start("おすすめの観光スポット教えて", backend: b)
        XCTAssertEqual(calls.reserves.count, 2, "同じ日の同じ頼みで回数を使った")
        XCTAssertEqual(e.thread.count, 2, "続けて聞いた所まで戻る")
    }

    /// ログインしていない・圏外・回数を使い切った: AI を使わず言葉の表で答える。使い切ったら帯1本
    func testFallsBackToTableWithoutAI() async throws {
        var setup = Setup()
        setup.signedIn = false
        var calls = Calls()
        var (e, d) = engine()
        await e.start("近くで夕日がきれいな所", backend: try backend(setup, calls: calls, defaults: d))
        XCTAssertEqual(e.thread.first?.answer.engine, .table)
        XCTAssertEqual(e.thread.first?.answer.note, AskText.signedOutLine)
        XCTAssertTrue(calls.reserves.isEmpty)
        XCTAssertEqual(calls.deviceAsks, 0)
        XCTAssertEqual(e.thread.first?.answer.spotIds, ["sp_yashima"], "AI が無くても台帳の札で答える")

        setup = Setup(); setup.offline = true
        calls = Calls(); (e, d) = engine()
        await e.start("近くで夕日がきれいな所", backend: try backend(setup, calls: calls, defaults: d))
        XCTAssertEqual(e.thread.first?.answer.state, .offline)
        XCTAssertTrue(calls.reserves.isEmpty)

        for reason in [AskLimitReason.day, .month, .global, .userCost] {
            setup = Setup(); setup.reserveError = AskService.Failure.limit(reason, nil)
            calls = Calls(); (e, d) = engine()
            await e.start("近くで夕日がきれいな所", backend: try backend(setup, calls: calls, defaults: d))
            let a = try XCTUnwrap(e.thread.first?.answer)
            XCTAssertEqual(a.limit, reason)
            XCTAssertEqual(a.engine, .table)
            XCTAssertFalse(a.usedAI, "上限なのに AI の答えを出した")
            XCTAssertTrue(a.text.isEmpty || !a.text.contains("屋島がおすすめ"), "上限なのに AI の文を出した")
            XCTAssertFalse(a.spotIds.isEmpty, "答えは言葉の表で出し続ける")
        }
    }

    /// 端末の AI が失敗・時間切れ: 言葉の表で答える（行き止まりにしない）
    func testDeviceSilenceFallsBack() async throws {
        var setup = Setup()
        setup.device = nil
        let calls = Calls()
        let (e, d) = engine()
        await e.start("おすすめの観光スポット教えて", backend: try backend(setup, calls: calls, defaults: d))
        XCTAssertEqual(e.thread.first?.answer.engine, .table)
        XCTAssertEqual(e.thread.first?.answer.note, AskText.silentLine)
        XCTAssertTrue(calls.reserves.isEmpty, "端末の AI が答えなかった回を数えた（0円の回は数えない）")
    }

    /// 2026-11-20 判断（run 1612）: 答えと「使い切った」帯は、案内の文（詳細・通信）を待たずに先に出す。案内の文はあとから札に差し込む
    func testAnswerAndBandAppearBeforeDetails() async throws {
        final class Gate: @unchecked Sendable {
            var continuation: CheckedContinuation<Void, Never>?
            var asked = false
        }
        let gate = Gate()
        var setup = Setup()
        setup.reserveError = AskService.Failure.limit(.day, nil)
        let calls = Calls()
        let (e, d) = engine()
        var b = try backend(setup, calls: calls, defaults: d)
        b.details = { spots in
            gate.asked = true
            await withCheckedContinuation { gate.continuation = $0 }
            // 本物の `withDetails` と同じく、詳細を重ねた行は索引だけではない（`OfficialSpot.merged`。
            // 2026-11-22: 札には索引だけの行にだけ差し込む `overlayDetails` に替えた）
            return spots.map { s in var t = s; t.summary = "詳細の案内"; t.isIndexOnly = false; return t }
        }
        let task = Task { await e.start("近くで夕日がきれいな所", backend: b) }
        // 詳細を止めたまま、答えと帯が出るか（止めたまま答えを待つ作りなら、ここで出ない）
        var shown = false
        for _ in 0..<200 {
            if let a = e.thread.first?.answer, a.limit == .day { shown = true; break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(shown, "案内の文を待ってから答えと帯を出している（段: \(e.stageLog)）")
        XCTAssertTrue(e.stageLog.contains { $0.hasPrefix("band@") })
        // 詳細はあとから届いて札に差し込まれる
        for _ in 0..<200 where gate.continuation == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(gate.asked)
        XCTAssertNotEqual(e.spotsById["sp_yashima"]?.summary, "詳細の案内")
        gate.continuation?.resume()
        await task.value
        XCTAssertEqual(e.spotsById["sp_yashima"]?.summary, "詳細の案内")
        XCTAssertTrue(e.stageLog.last?.hasPrefix("detailsDone@") ?? false)
    }

    /// 人が替わったら、会話、残りの回数、札の中身を手放す
    func testResetDropsUsageAndCards() async throws {
        let calls = Calls()
        let (e, d) = engine()
        await e.start("近くで夕日がきれいな所", backend: try backend(Setup(), calls: calls, defaults: d))
        XCTAssertNotNil(e.usage)
        XCTAssertFalse(e.spotsById.isEmpty)
        e.reset()
        XCTAssertTrue(e.thread.isEmpty)
        XCTAssertNil(e.usage)
        XCTAssertTrue(e.spotsById.isEmpty)
        XCTAssertTrue(e.photosById.isEmpty)
    }

    /// 控えに残すのは AI で答えた回と断った回だけ。ログインしていない回の答えは残さず、入ったあとは AI で答え直す
    func testOnlyAIAndRefusedAnswersAreKept() async throws {
        var setup = Setup()
        setup.signedIn = false
        let calls = Calls()
        let (e, d) = engine()
        await e.start("おすすめの観光スポット教えて", backend: try backend(setup, calls: calls, defaults: d))
        XCTAssertEqual(e.thread.first?.answer.engine, .table)
        setup.signedIn = true
        e.reset()
        await e.start("おすすめの観光スポット教えて", backend: try backend(setup, calls: calls, defaults: d))
        XCTAssertEqual(calls.reserves.count, 1, "言葉の表の答えを控えから出して、AI で答え直さなかった")
        XCTAssertEqual(e.thread.first?.answer.engine, .device)
        XCTAssertEqual(AskEngine.keepable([AskExchange(question: "a", answer: AskAnswer(engine: .refused)),
                                           AskExchange(question: "b", answer: AskAnswer(engine: .table))]).count, 1)
    }

    /// 端末の AI が無い iPhone: 無料（serverAllowed=false）は言葉の表、Pro だけサーバーの AI。
    /// サーバーへ送るのは打った文、直前の2往復、公開の観光スポットの行だけ（現在地は送らない）
    func testServerRouteOnlyWhenAllowed() async throws {
        var setup = Setup()
        setup.deviceAI = false
        var calls = Calls()
        var (e, d) = engine()
        await e.start("おすすめの観光スポット教えて", backend: try backend(setup, calls: calls, defaults: d))
        XCTAssertEqual(calls.reserves.map(\.1), [.server])
        XCTAssertTrue(calls.serverAsks.isEmpty, "無料の人にサーバーの AI を使った")
        XCTAssertEqual(e.thread.first?.answer.note, AskText.noDeviceAILine)

        setup.usage = AskUsage(tier: "pro", kind: "ask", day: .init(used: 1, limit: 20, remaining: 19),
                               month: .init(used: 1, limit: 300, remaining: 299), serverAllowed: true)
        calls = Calls(); (e, d) = engine()
        let b = try backend(setup, calls: calls, defaults: d)
        await e.start("香川で夕日がきれいな所を教えて", backend: b)
        await e.followUp("おすすめの観光スポット教えて", backend: b)
        XCTAssertEqual(calls.serverAsks.count, 2)
        let second = try XCTUnwrap(calls.serverAsks.last)
        XCTAssertEqual(second.turns.count, 1, "直前の往復を渡す")
        XCTAssertFalse(second.sources.contains { $0.isDraft })
        let first = try XCTUnwrap(calls.serverAsks.first)
        XCTAssertTrue(first.sources.allSatisfy { $0.region?.prefecture == "香川県" })
        XCTAssertEqual(e.thread.first?.answer.engine, .server)
        // 送る形: 現在地、行きたい場所、旅行プランの欄を持たない
        let body = try JSONEncoder().encode(AskService.Source(first.sources[0]))
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any]).keys.sorted()
        XCTAssertEqual(keys, ["area", "category", "kind", "name", "note", "seasons", "times"])
    }

    /// 使い方の質問は、AI が無くても使い方の頁の3行で答える。引けない質問は「AI でないと答えられません」
    func testHowToAndUnansweredWithoutAI() async throws {
        var setup = Setup()
        setup.signedIn = false
        let calls = Calls()
        let (e, d) = engine()
        await e.start("ストーリーに曲を付けるには", backend: try backend(setup, calls: calls, defaults: d))
        let a = try XCTUnwrap(e.thread.first?.answer)
        XCTAssertTrue(a.text.contains("曲"))
        XCTAssertEqual(a.sources.first?.kind, .help)
        XCTAssertTrue(a.spotIds.isEmpty)
        e.reset()
        await e.start("夕日を撮るコツは", backend: try backend(setup, calls: calls, defaults: d))
        XCTAssertEqual(e.thread.first?.answer.text, AskText.unansweredLine)
    }

    /// 合う所が無い: 理由と言い替え。言い替えはアプリが選び直すだけ（回数を使わない）
    func testEmptyAndRelaxWithoutCount() async throws {
        var setup = Setup()
        setup.signedIn = false
        let calls = Calls()
        let (e, d) = engine()
        let b = try backend(setup, calls: calls, defaults: d)
        await e.start("香川で冬の雪景色がきれいな所は", backend: b)
        let a = try XCTUnwrap(e.thread.first?.answer)
        XCTAssertEqual(a.state, .empty)
        XCTAssertNotNil(a.relaxedQuery)
        let before = calls.reserves.count
        await e.relax(try XCTUnwrap(e.thread.first), backend: b)
        XCTAssertEqual(calls.reserves.count, before)
        XCTAssertEqual(e.thread.count, 2)
    }
}

/// 旅行プランの AI（札 #621）の回数を「AI に頼む」と同じ reserve で取る（札 #652）
@MainActor
final class TripAIReserveTests: XCTestCase {

    private struct NoToken: TokenProviding {
        func idToken() async throws -> String? { nil }
        func accountGone(idToken: String) async {}
    }

    final class Kinds: @unchecked Sendable { var seen: [AskService.Kind] = [] }

    /// 端末の AI が無い iPhone の無料の人は、サーバーで組まず「AI なしで組む」
    func testFreeWithoutDeviceAIPlansWithoutAI() async throws {
        UserDefaults.standard.set(true, forKey: TripAIFixture.key)
        UserDefaults.standard.set("free", forKey: TripAIFixture.modeKey)
        UserDefaults.standard.set(0.0, forKey: TripAIFixture.delayKey)
        defer {
            UserDefaults.standard.removeObject(forKey: TripAIFixture.key)
            UserDefaults.standard.removeObject(forKey: TripAIFixture.modeKey)
            UserDefaults.standard.removeObject(forKey: TripAIFixture.delayKey)
        }
        let rows = try AskSamples.ledger()
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())
        let runner = TripAIRunner(onDevice: false)
        let ask = TripAIAsk.reading("香川で日帰り", spots: rows)
        let built = await runner.build(ask, index: rows, wishlist: [], offline: false, service: TripAIService(api: api)) { _, _ in 10 }
        XCTAssertEqual(built?.mode, .proOnly)
        XCTAssertFalse(built?.days.isEmpty ?? true, "AI なしで組んで行き止まりにしない")
        XCTAssertFalse(runner.askedServer, "無料の人の文をサーバーへ送った扱いにした")
    }

    /// Pro かどうか読めない（status の失敗）ときは「Pro だけ」と言わず、AI なしで組んだ理由（.silent）
    func testUnknownTierIsNotProOnly() async throws {
        let rows = try AskSamples.ledger()
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())
        let runner = TripAIRunner(onDevice: false)
        let built = await runner.build(TripAIAsk.reading("香川で日帰り", spots: rows), index: rows, wishlist: [], offline: false,
                                       service: TripAIService(api: api)) { _, _ in 10 }
        XCTAssertEqual(built?.mode, .silent)
        XCTAssertFalse(runner.askedServer)
    }

    /// 見本の Pro は今までどおりサーバーで組む
    func testProWithoutDeviceAIUsesServer() async throws {
        UserDefaults.standard.set(true, forKey: TripAIFixture.key)
        UserDefaults.standard.set(0.0, forKey: TripAIFixture.delayKey)
        defer {
            UserDefaults.standard.removeObject(forKey: TripAIFixture.key)
            UserDefaults.standard.removeObject(forKey: TripAIFixture.delayKey)
        }
        let rows = try AskSamples.ledger()
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())
        let runner = TripAIRunner(onDevice: false)
        let built = await runner.build(TripAIAsk.reading("香川で日帰り", spots: rows), index: rows, wishlist: [], offline: false,
                                       service: TripAIService(api: api)) { _, _ in 10 }
        XCTAssertEqual(built?.mode, .ai)
        XCTAssertTrue(runner.askedServer, "サーバーへ送ったことを残していない（AI に頼むの知らせが出ない）")
    }

    /// 旅行プランの reserve は kind "trip"。上限なら `.limit`
    func testTripReserveUsesTripKind() async throws {
        UserDefaults.standard.set(true, forKey: TripAIFixture.key)
        UserDefaults.standard.set("usedUp", forKey: TripAIFixture.modeKey)
        defer {
            UserDefaults.standard.removeObject(forKey: TripAIFixture.key)
            UserDefaults.standard.removeObject(forKey: TripAIFixture.modeKey)
        }
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())
        do {
            _ = try await TripAIService(api: api).reserve(via: .device)
            XCTFail("使い切ったのに取れた")
        } catch AskService.Failure.limit(let reason, _) {
            XCTAssertEqual(reason, .day)
        }
        let kinds = Kinds()
        var service = AskService(api: nil)
        service.reserveOverride = { kind, _ in
            kinds.seen.append(kind)
            return AskUsage(tier: "free", kind: kind.rawValue, day: .init(used: 1, limit: 5, remaining: 4),
                            month: .init(used: 1, limit: 30, remaining: 29), serverAllowed: false)
        }
        _ = try await service.reserve(kind: .trip, via: .device)
        XCTAssertEqual(kinds.seen, [.trip])
    }
}
