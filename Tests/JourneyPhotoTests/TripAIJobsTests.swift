import XCTest
@testable import JourneyPhoto

/// AI で作っている旅行プランの入れ物（`TripAIJobs`・札 #621）。確かめ役の指摘（2026-11-15）の
/// 二重に作らない・「やめる」の後に残さない・ログアウトで止める・人ごとの点・帯、と
/// AI で直した日程の重ね方（`TripAIRevise`）を縛る
final class TripAIJobsTests: XCTestCase {

    // MARK: - 材料

    private final class Box {
        var builds = 0
        var saves = 0
        var removed: [String] = []
        var current = true
        var offline = false
        /// 保存を止めておく（「やめる」を保存の途中で押す試験）
        var gate: CheckedContinuation<Void, Never>?
        var holdSave = false
        var saveStarted: CheckedContinuation<Void, Never>?
        /// 作ったプランを、この作業が作ったと確かに言えるか
        var certain = true
    }

    private func spot(_ id: String) throws -> OfficialSpot {
        let json = "{\"spotId\":\"\(id)\",\"slug\":\"\(id)\",\"name\":\"\(id)\",\"stage\":\"published\",\"region\":{\"prefecture\":\"石川県\",\"city\":\"金沢市\"},\"coords\":{\"lat\":36.5,\"lng\":136.6}}"
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    @MainActor
    private func backend(_ box: Box) throws -> TripAIJobs.Backend {
        let a = try spot("a"), b = try spot("b")
        return TripAIJobs.Backend(
            build: { _, _, _ in
                box.builds += 1
                return TripAIResult(title: "金沢の旅", days: [[a], [b]], reason: "朝を先に", removed: [], mode: .ai, candidates: [a, b])
            },
            save: { _, _ in
                box.saves += 1
                if box.holdSave {
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                        box.gate = c
                        box.saveStarted?.resume()
                        box.saveStarted = nil
                    }
                }
                return .success(TripAISaved(planId: "plan-\(box.saves)", certain: box.certain))
            },
            remove: { id in box.removed.append(id) },
            offline: { box.offline },
            isCurrent: { box.current })
    }

    private func ask() -> TripAIAsk {
        TripAIAsk(place: "金沢", prefectures: ["石川県"], cities: ["金沢市"], days: 2, preference: nil)
    }

    @MainActor
    private func fresh() -> (TripAIJobs, UserDefaults) {
        let name = "TripAIJobsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let jobs = TripAIJobs(defaults: defaults)
        jobs.use(userId: "me")
        return (jobs, defaults)
    }

    // MARK: - できたら保存して、帯と点

    @MainActor
    func testDoneOutsideTheScreenShowsBannerAndUnseenDot() async throws {
        let (jobs, _) = fresh()
        let box = Box()
        let job = jobs.start(ask(), owner: "me", usage: nil, backend: try backend(box), runner: TripAIRunner(onDevice: false))
        await jobs.settled(job)
        XCTAssertEqual(job.state, .saved(planId: "plan-1"))
        XCTAssertEqual(jobs.banner?.planId, "plan-1")
        XCTAssertTrue(jobs.unseen.contains("plan-1"))
        XCTAssertTrue(jobs.jobs.isEmpty, "終わった作業は片づける")
        XCTAssertNotNil(TripAINotes.shared.note("plan-1"))
        jobs.tapBanner()
        XCTAssertEqual(jobs.openPlanId, "plan-1")
        XCTAssertFalse(jobs.unseen.contains("plan-1"), "帯から開いたら点を消す")
        XCTAssertNil(jobs.banner)
    }

    @MainActor
    func testWatchingTheScreenShowsNoBanner() async throws {
        let (jobs, _) = fresh()
        let box = Box()
        box.holdSave = true
        let job = jobs.start(ask(), owner: "me", usage: nil, backend: try backend(box), runner: TripAIRunner(onDevice: false))
        jobs.watching = job.id
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in box.saveStarted = c }
        box.gate?.resume()
        await jobs.settled(job)
        XCTAssertNil(jobs.banner)
        XCTAssertFalse(jobs.unseen.contains("plan-1"))
    }

    // MARK: - 二重に作らない

    @MainActor
    func testSameAskWhileRunningOpensTheSameJob() async throws {
        let (jobs, _) = fresh()
        let box = Box()
        box.holdSave = true
        let be = try backend(box)
        let first = jobs.start(ask(), owner: "me", usage: nil, backend: be, runner: TripAIRunner(onDevice: false))
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in box.saveStarted = c }
        let second = jobs.start(ask(), owner: "me", usage: nil, backend: be, runner: TripAIRunner(onDevice: false))
        XCTAssertTrue(first === second, "同じ頼みが動いていれば、その作業を開く")
        XCTAssertEqual(box.builds, 1)
        box.gate?.resume()
        await jobs.settled(first)
        XCTAssertEqual(box.saves, 1)
    }

    // MARK: - やめる

    @MainActor
    func testStopDuringSaveRemovesThePlanWithoutBannerOrDot() async throws {
        let (jobs, _) = fresh()
        let box = Box()
        box.holdSave = true
        let job = jobs.start(ask(), owner: "me", usage: nil, backend: try backend(box), runner: TripAIRunner(onDevice: false))
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in box.saveStarted = c }
        XCTAssertTrue(job.saving, "保存に入ったら「やめる」を隠す")
        jobs.cancel(job)
        box.gate?.resume()
        await jobs.settled(job)
        XCTAssertEqual(box.removed, ["plan-1"], "保存の途中で止められた回は作ったプランを消す")
        XCTAssertNil(jobs.banner)
        XCTAssertFalse(jobs.unseen.contains("plan-1"))
        XCTAssertNotEqual(job.state, .saved(planId: "plan-1"))
    }

    @MainActor
    func testStopDoesNotRemoveAPlanItCannotBeSureItMade() async throws {
        let (jobs, _) = fresh()
        let box = Box()
        box.holdSave = true
        box.certain = false
        let job = jobs.start(ask(), owner: "me", usage: nil, backend: try backend(box), runner: TripAIRunner(onDevice: false))
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in box.saveStarted = c }
        jobs.cancel(job)
        box.gate?.resume()
        await jobs.settled(job)
        XCTAssertEqual(box.removed, [], "作ったと確かに言えないプランは消さない（別の作業のプランかもしれない）")
        XCTAssertNil(jobs.banner)
        XCTAssertFalse(jobs.unseen.contains("plan-1"))
    }

    func testPickIsCertainOnlyWithOneNewPlanOfThatTitle() {
        func plan(_ id: String, _ title: String, _ at: String) -> TripPlan {
            TripPlan(planId: id, title: title, startDate: nil, endDate: nil, days: [], createdAt: at, updatedAt: at)
        }
        let old = plan("old", "金沢の旅", "2026-11-01")
        let one = TripAICreated.pick(in: [plan("new", "金沢の旅", "2026-11-15"), old], before: ["old"], title: "金沢の旅")
        XCTAssertEqual(one, TripAISaved(planId: "new", certain: true))
        // 別の作業が同じ題で同時に作った: いちばん新しいものを採るが、確かとは言わない
        let two = TripAICreated.pick(in: [plan("n1", "金沢の旅", "2026-11-15T01"), plan("n2", "金沢の旅", "2026-11-15T02"), old],
                                     before: ["old"], title: "金沢の旅")
        XCTAssertEqual(two, TripAISaved(planId: "n2", certain: false))
    }

    // MARK: - 人が替わった・ログアウト

    @MainActor
    func testOtherPersonBeforeSaveDoesNotSave() async throws {
        let (jobs, _) = fresh()
        let box = Box()
        box.current = false
        let job = jobs.start(ask(), owner: "me", usage: nil, backend: try backend(box), runner: TripAIRunner(onDevice: false))
        await jobs.settled(job)
        XCTAssertEqual(box.builds, 1)
        XCTAssertEqual(box.saves, 0, "保存に入る前に今の人か確かめる")
        XCTAssertNil(jobs.banner)
        XCTAssertTrue(jobs.unseen.isEmpty)
    }


    @MainActor
    func testOtherPersonAtSaveTimeKeepsNothing() async throws {
        let (jobs, _) = fresh()
        let box = Box()
        box.holdSave = true
        let job = jobs.start(ask(), owner: "me", usage: nil, backend: try backend(box), runner: TripAIRunner(onDevice: false))
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in box.saveStarted = c }
        box.current = false
        box.gate?.resume()
        await jobs.settled(job)
        XCTAssertEqual(box.removed, ["plan-1"], "保存の間に人が替わったら消す")
        XCTAssertNil(jobs.banner)
    }

    @MainActor
    func testSignOutStopsEverythingAndForgetsPerPersonDots() async throws {
        let (jobs, defaults) = fresh()
        let box = Box()
        let job = jobs.start(ask(), owner: "me", usage: nil, backend: try backend(box), runner: TripAIRunner(onDevice: false))
        await jobs.settled(job)
        XCTAssertTrue(jobs.unseen.contains("plan-1"))
        jobs.openPlanId = "plan-1"
        jobs.signOut()
        XCTAssertNil(jobs.banner)
        XCTAssertNil(jobs.openPlanId)
        XCTAssertTrue(jobs.jobs.isEmpty)
        XCTAssertTrue(jobs.unseen.isEmpty)
        XCTAssertNil(TripAINotes.shared.note("plan-1"), "候補と理由も次の人に残さない")
        // 点は人ごと。別の人には出さない。戻った本人には残る。退会で消える
        jobs.use(userId: "other")
        XCTAssertTrue(jobs.unseen.isEmpty)
        jobs.use(userId: "me")
        XCTAssertTrue(jobs.unseen.contains("plan-1"))
        TripAIUnseen.removeData(for: "me", defaults: defaults)
        jobs.use(userId: nil)
        jobs.use(userId: "me")
        XCTAssertTrue(jobs.unseen.isEmpty)
    }

    func testAccountDeletionRemovesUnseenDots() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto/Core/Storage/AccountLocalData.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("TripAIUnseen.removeData(for: userId, defaults: defaults)"))
        let auth = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto/Core/Auth/AuthStore.swift"), encoding: .utf8)
        XCTAssertTrue(auth.contains("TripAIJobs.shared.signOut()"), "ログアウトと退会で止める")
    }

    // MARK: - 失敗は帯で、やり直しは1回

    @MainActor
    func testOfflineFailureShowsRetryBannerAndRetryRuns() async throws {
        let (jobs, _) = fresh()
        let box = Box()
        box.offline = true
        let job = jobs.start(ask(), owner: "me", usage: nil, backend: try backend(box), runner: TripAIRunner(onDevice: false))
        await jobs.settled(job)
        XCTAssertEqual(job.state, .failed(.offline))
        XCTAssertEqual(jobs.banner?.failed, true)
        XCTAssertEqual(box.builds, 0, "圏外で端末の AI も無いときは組まない")
        box.offline = false
        jobs.tapBanner()
        await jobs.settled(job)
        XCTAssertEqual(job.state, .saved(planId: "plan-1"))
    }

    // MARK: - AI で直した日程の重ね方

    func testReviseKeepsLocationsUnknownSpotsDaysAndDates() {
        let before = [
            TripDay(date: "2026-12-01", items: [.spot(spotId: "a", note: "朝いちばん"), .location(slug: "kanazawa-st", note: nil),
                                               .spot(spotId: "zz", note: nil)]),
            TripDay(date: "2026-12-02", items: [.spot(spotId: "b", note: nil), .spot(spotId: "c", note: nil)]),
        ]
        // AI は1日に縮め、b と a だけ選び、c を選ばず、新しい d を足した
        let merged = TripAIRevise.merge(before: before, aiDays: [["b", "a", "d"]], sent: ["a", "b", "c"])
        XCTAssertEqual(merged.days.count, 2, "日の数は元を下回らない")
        XCTAssertEqual(merged.days.map(\.date), ["2026-12-01", "2026-12-02"], "日付を残す")
        XCTAssertEqual(merged.days[0].items, [.spot(spotId: "b", note: nil), .spot(spotId: "a", note: "朝いちばん"),
                                              .spot(spotId: "d", note: nil),
                                              .location(slug: "kanazawa-st", note: nil), .spot(spotId: "zz", note: nil)],
                       "撮影地と台帳に無い場所は元の日に残し、メモも残す")
        XCTAssertEqual(merged.days[1].items, [])
        XCTAssertEqual(merged.dropped, [TripAIRevise.Dropped(day: 1, index: 1, item: .spot(spotId: "c", note: nil))],
                       "選ばれなかった場所は「外しました　戻す」へ")
    }

    // MARK: - 帯と画面の決まり（確かめ役の指摘 2026-11-15）

    func testBannerSitsBelowNavigationBarWithWhiteDotAndFailureSaidOnce() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func source(_ p: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + p), encoding: .utf8)
        }
        XCTAssertTrue(try source("App/RootView.swift").contains("TripAIBannerView().padding(.top, TripAIBannerLayout.belowNavigationBar)"),
                      "帯が戻るのガラスの丸にかぶさる")
        XCTAssertGreaterThanOrEqual(TripAIBannerLayout.belowNavigationBar, 44)
        let views = try source("Features/Trips/AI/TripAIViews.swift")
        XCTAssertTrue(views.contains("Circle().fill(b.failed ? WebTheme.danger : WebTheme.foreground)"), "ガラスの上の点は白")
        XCTAssertTrue(views.contains("if !isFailed {"), "作れなかったときに同じ言葉を2回出す")
        XCTAssertTrue(views.contains("if job.state == .building, !job.saving {"), "保存に入ったら「やめる」を隠す")
    }

    // MARK: - 直すときの日の番号と、渡した場所（確かめ役の見直し 2026-11-15）

    @MainActor
    func testReviseKeepsDayNumbersWithEmptyDays() async throws {
        let a = try spot("a"), b = try spot("b"), c = try spot("c")
        // AI は 1日目を空にし、2日目に c、3日目に a と b を置いた
        let runner = TripAIRunner(onDevice: false) { _, _, _, _ in
            TripAIPlan(title: "", days: 3, stops: [.init(n: 3, day: 2), .init(n: 1, day: 3), .init(n: 2, day: 3)], reason: "r")
        }
        let built = await runner.revise(request: "ゆっくり", current: [[a], [b], [c]], candidates: [], index: [], offline: false,
                                        service: TripAIService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                                                              tokenProvider: NoToken())),
                                        title: "金沢の旅") { _, _ in 10 }
        let result = try XCTUnwrap(built)
        XCTAssertEqual(result.days.map { (d: [OfficialSpot]) in d.map { $0.spotId } }, [[], ["c"], ["a", "b"]], "空の日を詰めない（日の番号のまま）")
        let before = [TripDay(date: "2026-12-01", items: [.spot(spotId: "a", note: nil)]),
                      TripDay(date: "2026-12-02", items: [.spot(spotId: "b", note: nil)]),
                      TripDay(date: "2026-12-03", items: [.spot(spotId: "c", note: nil)])]
        let merged = TripAIRevise.merge(before: before, aiDays: result.days.map { (d: [OfficialSpot]) in d.map { $0.spotId } }, sent: ["a", "b", "c"])
        XCTAssertEqual(merged.days[1], TripDay(date: "2026-12-02", items: [.spot(spotId: "c", note: nil)]),
                       "2日目の場所が 2日目の日付に入る")
    }

    func testOnlyCandidatesSentToAIAreTreatedAsSent() throws {
        let rows = try (1...22).map { try spot("s\($0)") }
        let current = [Array(rows.prefix(12)), Array(rows.suffix(10))]
        let sent = TripAIRevise.sentIds(current: current, candidates: Array(rows.prefix(20)))
        XCTAssertEqual(sent.count, 20)
        XCTAssertFalse(sent.contains("s21"), "21か所目から後は AI に渡していない")
        let before = current.map { (d: [OfficialSpot]) in TripDay(items: d.map { TripItem.spot(spotId: $0.spotId, note: nil) }) }
        let merged = TripAIRevise.merge(before: before, aiDays: [rows.prefix(12).map { $0.spotId }, rows[12..<20].map { $0.spotId }], sent: sent)
        XCTAssertTrue(merged.dropped.isEmpty, "渡していない場所を棚に回さない")
        XCTAssertTrue(merged.days[1].items.contains(.spot(spotId: "s22", note: nil)))
    }

    private struct NoToken: TokenProviding {
        func idToken() async throws -> String? { nil }
        func accountGone(idToken: String) async {}
    }

    // MARK: - 字数

    func testRequestIsClippedTo200() {
        XCTAssertEqual(TripAILimits.clipped(String(repeating: "あ", count: 250)).count, 200)
        XCTAssertEqual(TripAILimits.clipped("金沢"), "金沢")
        let long = String(repeating: "い", count: 300)
        XCTAssertFalse(TripAIDevice.message(request: long, days: 1, candidates: [], current: []).contains(String(repeating: "い", count: 201)))
    }
}
