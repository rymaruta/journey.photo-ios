import XCTest
@testable import JourneyPhoto

/// ホームの上の札（旅行プラン）の「⋯」と長押し（2026-11-12 owner「削除するときは旅行プランのページに行かないと
/// いけないのめんどくさい」）。メニューの中身・出さない間は札が出ない・削除の「元に戻す」と送る時・共有のときの言葉
@MainActor
final class HomeTripCardMenuTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-09-27 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_790_510_400)
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() async throws {
        suite = "HomeTripCardMenuTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func plan(_ id: String, start: String?, end: String? = nil) -> TripPlan {
        TripPlan(planId: id, title: "[\(id)]", startDate: start, endDate: end)
    }

    // MARK: - メニューの中身

    func testMenuItemsByRole() async {
        XCTAssertEqual(HomeTripCardMenu.items(for: .mine), [.hideFromHome, .delete])
        XCTAssertEqual(HomeTripCardMenu.items(for: .sharedOwner), [.hideFromHome, .deleteForEveryone])
        // 持ち主でない仲間には「削除」を出さない
        XCTAssertEqual(HomeTripCardMenu.items(for: .sharedMember), [.hideFromHome, .leave])
        XCTAssertFalse(HomeTripCardMenu.items(for: .sharedMember).contains(.delete))
        XCTAssertFalse(HomeTripCardMenu.items(for: .sharedMember).contains(.deleteForEveryone))
    }

    /// 確かめを出すのは他人に影響する「仲間全員から削除」だけ（取り消せる操作は聞かない・CLAUDE.md）
    func testOnlyDeleteForEveryoneAsks() async {
        XCTAssertEqual(HomeTripCardMenu.Item.allCases.filter(\.needsConfirm), [.deleteForEveryone])
        XCTAssertFalse(HomeTripCardMenu.Item.hideFromHome.isDestructive, "出さないはプランを消さない")
        XCTAssertTrue(HomeTripCardMenu.Item.delete.isDestructive)
    }

    /// 共有していないプランは「自分のプラン」。共有したプランは持ち主か仲間かで分ける（1.1.84 のまとめで共有の枝と合わせた）
    func testRoleFollowsShare() async {
        XCTAssertEqual(HomeTripCardMenu.role(of: plan("a", start: "2026-09-29"), me: "me"), .mine)
        let shared = TripPlan(planId: "s", title: "[s]", startDate: "2026-09-29",
                              share: TripShare(ownerId: "me", memberIds: ["me", "friend"], rev: 1))
        XCTAssertEqual(HomeTripCardMenu.role(of: shared, me: "me"), .sharedOwner)
        XCTAssertEqual(HomeTripCardMenu.role(of: shared, me: "friend"), .sharedMember)
        XCTAssertEqual(HomeTripCardMenu.items(for: HomeTripCardMenu.role(of: shared, me: "friend")), [.hideFromHome, .leave],
                       "仲間に「削除」を出した")
    }

    func testWording() async {
        XCTAssertEqual(HomeTripCardMenu.Item.hideFromHome.title, "この旅をホームに出さない")
        XCTAssertEqual(HomeTripCardMenu.Item.delete.title, "旅行プランを削除")
        XCTAssertEqual(HomeTripCardMenu.Item.leave.title, "このプランから抜ける")
        XCTAssertEqual(HomeTripCardMenu.Item.leave.title, TripShareText.leave, "日程の画面と同じ言い方（1.1.84 のまとめ）")
        XCTAssertEqual(HomeTripCardMenu.Item.deleteForEveryone.title, "仲間全員から削除")
        // 持ち主の削除は、仲間からも消えることが分かる言葉
        XCTAssertTrue(HomeTripCardMenu.confirmTitle("鎌倉").contains("仲間全員から"))
        XCTAssertTrue(HomeTripCardMenu.confirmMessage.contains("仲間"))
        XCTAssertEqual(HomeTripCardMenu.doneText(.delete, planTitle: "鎌倉"), "「鎌倉」を削除しました")
        XCTAssertEqual(HomeTripCardMenu.doneText(.leave, planTitle: "鎌倉"), "「鎌倉」から抜けました")
        XCTAssertEqual(HomeTripCardMenu.doneText(.hideFromHome, planTitle: "鎌倉"), "「鎌倉」をホームに出しません")
        XCTAssertEqual(HomeTripCardMenu.undo, "元に戻す")
        XCTAssertEqual(TripPlanRemovalQueue.undoSeconds, 6, "「元に戻す」は6秒（owner の指示）")
        // 禁止語と、新しい文の区切り（2026-11-12 owner）
        let all = HomeTripCardMenu.Item.allCases.map(\.title)
            + HomeTripCardMenu.Item.allCases.map { HomeTripCardMenu.doneText($0, planTitle: "x") }
            + HomeTripCardMenu.Item.allCases.map { HomeTripCardMenu.failedText($0, planTitle: "x") }
            + [HomeTripCardMenu.confirmTitle("x"), HomeTripCardMenu.confirmMessage, HomeTripCardMenu.menuLabel]
        for text in all {
            XCTAssertFalse(text.contains("捨て"), text)
            XCTAssertFalse(text.contains("・") || text.contains("·"), text)
        }
    }

    // MARK: - ホームに出さない

    func testHiddenTripIsNotOnTheCards() async {
        let soon = plan("soon", start: "2026-09-29", end: "2026-09-30")
        let store = HomeHiddenTrips(defaults: defaults)
        func departure(_ plans: [TripPlan]) -> Bool {
            HomeTopCard.cards(now: now, plans: HomeHiddenTrips.visible(plans, hidden: store.entries(for: "me")),
                              myPhotos: [], openedBookDays: [], timeZone: utc)
                .contains { if case .departure = $0 { return true } else { return false } }
        }
        XCTAssertTrue(departure([soon]))
        store.hide(soon, for: "me")
        XCTAssertFalse(departure([soon]), "出さないにした旅の札が出ている")
        // ほかの人の端末の印では下げない
        XCTAssertTrue(HomeHiddenTrips.visible([soon], hidden: store.entries(for: "other")).contains(soon))
        // 日付を替えて次の旅にしたら、また出る
        let moved = plan("soon", start: "2026-10-02", end: "2026-10-03")
        XCTAssertTrue(departure([moved]), "別の日付の旅まで出さないままにした")
        store.unhide(planId: "soon", for: "me")
        XCTAssertTrue(departure([soon]), "元に戻すで札が戻らない")
    }

    func testRemovedPlansAreDroppedFromTheCards() async {
        let soon = plan("soon", start: "2026-09-29")
        XCTAssertEqual(HomeHiddenTrips.visible([soon], hidden: [], excluding: ["soon"]), [])
    }

    func testFinishedTripsArePruned() async {
        let store = HomeHiddenTrips(defaults: defaults)
        store.hide(plan("old", start: "2026-09-20", end: "2026-09-22"), for: "me")
        store.hide(plan("now", start: "2026-09-26", end: "2026-09-28"), for: "me")
        store.prune(today: "2026-09-27", for: "me")
        XCTAssertEqual(store.entries(for: "me").map(\.planId), ["now"])
        store.removeData(for: "me")
        XCTAssertEqual(store.entries(for: "me"), [])
    }

    // MARK: - 削除と「元に戻す」

    private final class Sent {
        var jobs: [TripPlanRemovalQueue.Job] = []
        var error: Error?
    }

    private func sender(_ sent: Sent) -> TripPlanRemovalQueue.Send {
        { job in
            if let error = sent.error { throw error }
            sent.jobs.append(job)
        }
    }

    /// 押すとすぐ札から落ち、「元に戻す」で戻る。戻したら送らない
    func testUndoBeforeTheTimerSendsNothing() async throws {
        let queue = TripPlanRemovalQueue(defaults: defaults, seconds: 0.2)
        let sent = Sent()
        queue.remove(planId: "a", title: "鎌倉", item: .delete, userId: "me", send: sender(sent))
        XCTAssertEqual(queue.removedIds, ["a"])
        XCTAssertEqual(queue.bar?.text, "「鎌倉」を削除しました")
        queue.undo()
        XCTAssertEqual(queue.removedIds, [])
        XCTAssertNil(queue.bar)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(sent.jobs, [], "元に戻したのに送った")
        XCTAssertEqual(queue.waiting(for: "me"), [])
    }

    /// 6秒（試験では短く）たってから1回だけ送り、書き残しを消す。送る前は書き残している（アプリを閉じても消える）
    func testTimerSendsOnce() async throws {
        let queue = TripPlanRemovalQueue(defaults: defaults, seconds: 0.05)
        let sent = Sent()
        queue.remove(planId: "a", title: "鎌倉", item: .delete, userId: "me", send: sender(sent))
        XCTAssertEqual(sent.jobs, [], "6秒を待たずに送った")
        XCTAssertEqual(queue.waiting(for: "me").map(\.planId), ["a"], "押した時点で書き残していない")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(sent.jobs.map(\.planId), ["a"])
        XCTAssertEqual(queue.waiting(for: "me"), [])
        XCTAssertNil(queue.bar, "送ったあとも「元に戻す」が残る")
        XCTAssertEqual(queue.removedIds, ["a"], "消し終えた札が戻った")
    }

    /// 次を押したら、前の1件は待たずに送る
    func testNextRemovalCommitsThePrevious() async throws {
        let queue = TripPlanRemovalQueue(defaults: defaults, seconds: 60)
        let sent = Sent()
        queue.remove(planId: "a", title: "A", item: .delete, userId: "me", send: sender(sent))
        queue.remove(planId: "b", title: "B", item: .delete, userId: "me", send: sender(sent))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sent.jobs.map(\.planId), ["a"])
        XCTAssertEqual(queue.bar?.text, "「B」を削除しました")
    }

    /// 圏外は札から落としたまま書き残し、電波が戻ったら（`resume`）送る
    func testOfflineWaitsAndResumes() async throws {
        let queue = TripPlanRemovalQueue(defaults: defaults, seconds: 0.05)
        let sent = Sent()
        sent.error = APIError.unreachable
        queue.remove(planId: "a", title: "A", item: .delete, userId: "me", send: sender(sent))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(queue.removedIds, ["a"], "圏外で札が戻った")
        XCTAssertEqual(queue.waiting(for: "me").map(\.planId), ["a"], "圏外で書き残しを消した")
        sent.error = nil
        queue.resume(userId: "me", send: sender(sent))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sent.jobs.map(\.planId), ["a"])
        XCTAssertEqual(queue.waiting(for: "me"), [])
    }

    /// 6秒の間にアプリを閉じた: 次に開いたとき（新しい入れ物）書き残しから送る
    func testClosedAppSendsOnNextLaunch() async throws {
        let first = TripPlanRemovalQueue(defaults: defaults, seconds: 60)
        first.remove(planId: "a", title: "A", item: .delete, userId: "me", send: sender(Sent()))
        let next = TripPlanRemovalQueue(defaults: defaults, seconds: 60)
        let sent = Sent()
        next.resume(userId: "other", send: sender(sent))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sent.jobs, [], "ほかの人の書き残しを送った")
        next.resume(userId: "me", send: sender(sent))
        XCTAssertEqual(next.removedIds, ["a"], "書き残した札を出してしまう")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sent.jobs.map(\.planId), ["a"])
    }

    /// 断られたら札を戻して知らせる。すでに無い（404）は消し終えたと読む
    func testRefusedRestoresAndGoneIsDone() async throws {
        let queue = TripPlanRemovalQueue(defaults: defaults, seconds: 0.05, failedSeconds: 60)
        let sent = Sent()
        sent.error = APIError.server(status: 403, message: "")
        queue.remove(planId: "a", title: "A", item: .delete, userId: "me", send: sender(sent))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(queue.removedIds, [], "断られたのに札が戻らない")
        XCTAssertEqual(queue.bar, .failed("「A」を削除できませんでした"))
        XCTAssertEqual(queue.waiting(for: "me"), [])

        XCTAssertEqual(TripPlanRemovalQueue.outcome(of: APIError.server(status: 404, message: "")), .done)
        XCTAssertEqual(TripPlanRemovalQueue.outcome(of: URLError(.notConnectedToInternet)), .later)
        XCTAssertEqual(TripPlanRemovalQueue.outcome(of: TripPlanRemovalQueue.NotNow()), .later)
    }

    /// 人が替わったら、前の人の分は送らず書き残しのまま。帯も消す
    func testUserChangeKeepsTheJob() async throws {
        let queue = TripPlanRemovalQueue(defaults: defaults, seconds: 0.05)
        let sent = Sent()
        queue.remove(planId: "a", title: "A", item: .delete, userId: "me", send: sender(sent))
        queue.userChanged()
        XCTAssertNil(queue.bar)
        XCTAssertEqual(queue.removedIds, [])
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(sent.jobs, [])
        XCTAssertEqual(queue.waiting(for: "me").map(\.planId), ["a"])
        TripPlanRemovalQueue.removeData(for: "me", defaults: defaults)
        XCTAssertEqual(queue.waiting(for: "me"), [])
    }

    /// 出さないも「元に戻す」で印が外れる
    func testHideAndUndo() async {
        let queue = TripPlanRemovalQueue(defaults: defaults, seconds: 60)
        let soon = plan("soon", start: "2026-09-29")
        queue.hide(soon, title: "鎌倉", userId: "me")
        XCTAssertEqual(queue.hiddenTrips.map(\.planId), ["soon"])
        XCTAssertEqual(queue.bar?.text, "「鎌倉」をホームに出しません")
        queue.undo()
        XCTAssertEqual(queue.hiddenTrips, [])
        XCTAssertEqual(HomeHiddenTrips(defaults: defaults).entries(for: "me"), [])
    }

    // MARK: - つながり（画面は Linux で描けないので、作りを読む）

    func testCardsAreWired() async throws {
        let view = try source("Sources/JourneyPhoto/Features/Gallery/HomeTopCardView.swift")
        XCTAssertTrue(view.contains("plans: HomeHiddenTrips.visible(plansOwner == auth.userId ? plans : [],"),
                      "出さない旅・消した旅を札に渡している")
        XCTAssertEqual(view.components(separatedBy: ".tripCardMenu(menuItems(for: plan)").count - 1, 2,
                       "出発が近い・旅の最中の両方の札に「⋯」が無い")
        // 「⋯」と長押しは同じ中身
        XCTAssertTrue(view.contains(".contextMenu { TripCardMenuItems(items: items, choose: choose) }"))
        XCTAssertTrue(view.contains("TripCardMenuItems(items: items, choose: choose)\n                } label: {"))
        XCTAssertTrue(view.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget"), "当たりが 44 ではない")
        XCTAssertTrue(view.contains("if phase == .background { removal.commitNow() }"), "裏に回ったときに送らない")
        XCTAssertTrue(view.contains("if item.needsConfirm { confirmingEveryone = plan } else { remove(plan, item) }"))

        let gallery = try source("Sources/JourneyPhoto/Features/Gallery/GalleryView.swift")
        XCTAssertTrue(gallery.contains(".overlay(alignment: .bottom) { TripRemovalBar(queue: TripPlanRemovalQueue.shared) }"),
                      "ホームの下に「元に戻す」が無い")
        let list = try source("Sources/JourneyPhoto/Features/Trips/TripPlansView.swift")
        XCTAssertTrue(list.contains("model.plans.filter { !removal.removedIds.contains($0.planId) }"),
                      "元に戻すを待っているプランが一覧に出る")
        let shots = try source("UITests/JourneyPhotoUITests/ScreenshotTests.swift")
        XCTAssertTrue(shots.contains("10h-ホーム（旅行プランの札のメニュー）"), "メニューの画面写真が無い")
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
