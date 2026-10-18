import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 旅のトランクの入口（マイページの上の札・設定の行・2026-10-18 owner「入口がわかりずらい」）。
/// 札の出し分け・数・読み上げ・読み過ぎない決まり
@MainActor
final class TrunkEntryTests: XCTestCase {

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        return URLSession(configuration: config)
    }()

    override func setUp() {
        super.setUp()
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func service() -> TrunkService {
        TrunkService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                    tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    private func label(_ id: String) -> String {
        #"{"id":"\#(id)","kind":"place","place":{"name":"京都"},"seed":1,"at":"2026-10-17T00:00:00Z"}"#
    }

    private func body(coins: Int, pocket: Int) -> String {
        let labels = (0..<pocket).map { label("p-\($0)") }.joined(separator: ",")
        return #"{"pocket":[\#(labels)],"stuck":[\#(label("s-1"))],"coins":\#(coins)}"#
    }

    private var trunkReads: Int { ScriptedProtocol.calls.filter { $0.path == "/user/trunk" }.count }

    // MARK: - 出し分け

    /// 🔴 使えない人（口が読めたことが無い・入っていない）には出さない
    func testShowsOnlyWhenAvailable() async {
        XCTAssertTrue(TrunkEntryRule.shows(signedIn: true, available: true))
        XCTAssertFalse(TrunkEntryRule.shows(signedIn: true, available: false), "口が無いのに入口を出している")
        XCTAssertFalse(TrunkEntryRule.shows(signedIn: false, available: true), "入っていないのに入口を出している")
        XCTAssertFalse(TrunkEntryRule.shows(signedIn: false, available: false))
    }

    /// 硬貨 0 と N・貼っていないラベルのあり／なし（点を出すか）
    func testSummaryCoinsAndUnstuckMark() async {
        let none = TrunkEntrySummary(TrunkSample.state(isPro: false, empty: true, coins: 0))
        XCTAssertEqual(none.coins, 0)
        XCTAssertFalse(none.hasUnstuck, "手持ちが空なのに点を出している")
        let some = TrunkEntrySummary(TrunkSample.state(isPro: false, coins: 7))
        XCTAssertEqual(some.coins, 7)
        XCTAssertTrue(some.hasUnstuck, "手持ちに貼っていないラベルがあるのに点を出さない")
        XCTAssertEqual(some.unstuck, TrunkSample.pocket.count)
        XCTAssertEqual(TrunkEntryText.coins(0), L("硬貨 0", "0 coins"))
        XCTAssertEqual(TrunkEntryText.coins(7), L("硬貨 7", "7 coins"))
        XCTAssertEqual(TrunkEntrySummary(coins: -3, unstuck: -1), TrunkEntrySummary(coins: 0, unstuck: 0))
    }

    /// 読み上げで、硬貨の枚数と貼っていないラベルの有無が伝わる（点の色だけで伝えない）
    func testAccessibilityValueSaysCoinsAndLabels() async {
        let with = TrunkEntryText.accessibilityValue(TrunkEntrySummary(coins: 3, unstuck: 2))
        XCTAssertTrue(with.contains(L("硬貨 3枚", "3 coins")), with)
        XCTAssertTrue(with.contains(L("まだ貼っていないラベルが 2枚あります", "2 labels not stuck yet")), with)
        let without = TrunkEntryText.accessibilityValue(TrunkEntrySummary(coins: 0, unstuck: 0))
        XCTAssertTrue(without.contains(L("硬貨 0枚", "0 coins")), without)
        XCTAssertTrue(without.contains(L("貼っていないラベルはありません", "No labels waiting")), without)
        XCTAssertEqual(TrunkEntryText.accessibilityValue(nil), "")
    }

    // MARK: - 読み過ぎない

    func testNeedsReadRule() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(TrunkEntryRule.needsRead(readAt: nil, failedAt: nil, stale: false, now: now), "まだ読んでいない")
        XCTAssertFalse(TrunkEntryRule.needsRead(readAt: now.addingTimeInterval(-3600), failedAt: nil, stale: false, now: now),
                       "開くたびに読んでいる")
        XCTAssertTrue(TrunkEntryRule.needsRead(readAt: now.addingTimeInterval(-6 * 3600), failedAt: nil, stale: false, now: now))
        XCTAssertTrue(TrunkEntryRule.needsRead(readAt: now, failedAt: nil, stale: true, now: now), "トランクから戻っても読まない")
        XCTAssertFalse(TrunkEntryRule.needsRead(readAt: nil, failedAt: now.addingTimeInterval(-60), stale: false, now: now),
                       "失敗のすぐ後に読み直している")
        XCTAssertTrue(TrunkEntryRule.needsRead(readAt: nil, failedAt: now.addingTimeInterval(-601), stale: false, now: now))
    }

    /// 🔴 マイページを何度開いても `GET /user/trunk` は1回。トランクから戻った・前面に戻ったときだけ読み直す
    func testStoreReadsOnceUntilStale() async {
        let store = TrunkEntryStore()
        let svc = service()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200, body: body(coins: 4, pocket: 2), once: true)]
        await store.refresh(userId: "u1", available: true, service: svc, now: now, preview: nil)
        XCTAssertEqual(store.summary, TrunkEntrySummary(coins: 4, unstuck: 2))
        for i in 1...3 {
            await store.refresh(userId: "u1", available: true, service: svc, now: now.addingTimeInterval(Double(i) * 60), preview: nil)
        }
        XCTAssertEqual(trunkReads, 1, "マイページを開くたびに読んでいる")
        // トランクの画面で硬貨を使って戻った
        store.markStale()
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200, body: body(coins: 3, pocket: 0), once: true)]
        await store.refresh(userId: "u1", available: true, service: svc, now: now.addingTimeInterval(300), preview: nil)
        XCTAssertEqual(trunkReads, 2)
        XCTAssertEqual(store.summary, TrunkEntrySummary(coins: 3, unstuck: 0))
        // 前面に戻った
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200, body: body(coins: 13, pocket: 0), once: true)]
        await store.refresh(userId: "u1", available: true, service: svc, force: true, now: now.addingTimeInterval(320), preview: nil)
        XCTAssertEqual(trunkReads, 3)
        XCTAssertEqual(store.summary?.coins, 13, "応答の coins をそのまま出していない")
    }

    /// 口が無い人のためには読まない・数も出さない
    func testStoreDoesNotReadWhenUnavailable() async {
        let store = TrunkEntryStore()
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200, body: body(coins: 4, pocket: 2))]
        await store.refresh(userId: "u1", available: false, service: service(), preview: nil)
        XCTAssertEqual(trunkReads, 0)
        XCTAssertNil(store.summary)
        await store.refresh(userId: nil, available: true, service: service(), preview: nil)
        XCTAssertEqual(trunkReads, 0)
    }

    /// 読み直しの失敗で前の数を消さない。人が替わったら前の人の数を持ち越さない
    func testFailureKeepsSummaryAndUserSwitchClears() async {
        let store = TrunkEntryStore()
        let svc = service()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200, body: body(coins: 2, pocket: 1), once: true)]
        await store.refresh(userId: "u1", available: true, service: svc, now: now, preview: nil)
        store.markStale()
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 500, body: "", once: true)]
        await store.refresh(userId: "u1", available: true, service: svc, now: now.addingTimeInterval(10), preview: nil)
        XCTAssertEqual(store.summary, TrunkEntrySummary(coins: 2, unstuck: 1), "一時の失敗で札の数が消えた")
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 500, body: "")]
        await store.refresh(userId: "u2", available: true, service: svc, now: now.addingTimeInterval(20), preview: nil)
        XCTAssertNil(store.summary, "前の人の硬貨が次の人の札に出ている")
    }

    /// 見本（画面写真）ではサーバーに送らず、トランクの画面と同じ見本から出す
    func testPreviewUsesSampleWithoutReading() async {
        let store = TrunkEntryStore()
        await store.refresh(userId: "u1", available: true, service: service(), preview: .sample, previewPro: false)
        XCTAssertEqual(trunkReads, 0)
        XCTAssertEqual(store.summary?.unstuck, TrunkSample.pocket.count)
        await store.refresh(userId: "u2", available: true, service: service(), preview: .empty, previewPro: false)
        XCTAssertEqual(store.summary?.hasUnstuck, false)
    }

    // MARK: - 配線（Linux では描けないので文で確かめる）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// マイページの上（数の並びと旅の実績のすぐ下・タブより上）に札。設定にも行。どちらも同じ出し分け。
    /// **札は1つの部品（`TrunkProfileChip`）に閉じ、マイページは出し分けと置く1行だけ**（あとで絵に差し替える）
    func testEntriesAreWired() async throws {
        let page = try source("Features/Profile/MyPageView.swift")
        let header = try XCTUnwrap(page.range(of: "                        travelRecord\n"
            + "                        if TrunkEntryRule.shows(signedIn: auth.userId != nil, available: trunkAvailability.isAvailable) {\n"
            + "                            TrunkProfileChip(ownerName: model.profile?.name)\n"),
                                   "札が見出しの数の並びのすぐ下に無い")
        let tabs = try XCTUnwrap(page.range(of: "tabPicker\n"))
        XCTAssertLessThan(header.lowerBound, tabs.lowerBound, "札がタブより下にある")
        // マイページは札の中身（読み込み・状態・見た目）を持たない
        XCTAssertFalse(page.contains("TrunkEntryStore.shared.summary"))
        XCTAssertFalse(page.contains("entry.refresh("), "マイページが札の数を読んでいる（部品の側に置く）")
        XCTAssertFalse(page.contains("mypage.trunk"))
        let chip = try source("Features/Profile/TrunkProfileChip.swift")
        XCTAssertTrue(chip.contains(#".accessibilityIdentifier("mypage.trunk")"#))
        XCTAssertTrue(chip.contains(".onDisappear { entry.markStale() }"), "トランクから戻っても数を読み直さない")
        XCTAssertTrue(chip.contains("if phase == .active { Task { await refresh(force: true) } }"), "前面に戻ったときに数を読み直さない")
        XCTAssertTrue(chip.contains(".onChange(of: tabRouter.postSheetsClosed)"), "投稿を閉じても数を読み直さない")
        // 真鍮は点だけ（黒地の札の上）。硬貨の数は白
        XCTAssertTrue(chip.contains(".fill(WebTheme.accent)\n                        .frame(width: 8, height: 8)"))
        XCTAssertTrue(chip.contains("Text(TrunkEntryText.coins(summary.coins))\n                        .font(JPFont.mono(15, relativeTo: .subheadline))\n                        .foregroundStyle(WebTheme.text)"))
        let settings = try source("Features/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains("passSection\n                    trunkSection\n                    privacySection"))
        XCTAssertTrue(settings.contains("TrunkEntryRule.shows(signedIn: auth.userId != nil, available: trunkAvailability.isAvailable)"))
        XCTAssertTrue(settings.contains(#".accessibilityIdentifier("settings.trunk")"#))
    }
}
