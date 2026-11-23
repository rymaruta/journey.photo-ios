import XCTest
@testable import JourneyPhoto

/// とおまわり号（写真で作るキャンピングカー）を消したあと（2026-11-23・札 #709）に残したもの・足したもの。
/// 戻すには枝 `archive/camper`（1d8dbfc251b0）から
@MainActor
final class CamperRemovalTests: XCTestCase {

    // MARK: - 引っ越した県の読み取り（前の `CamperCounting.prefecture(in:)`）

    func testPrefectureTextReadsTheSameAsBefore() async {
        XCTAssertEqual(PrefectureText.prefecture(in: "神奈川県"), "神奈川", "奈良に当たっている")
        XCTAssertEqual(PrefectureText.prefecture(in: "京都府京都市"), "京都")
        XCTAssertEqual(PrefectureText.prefecture(in: "長野県 松本市"), "長野")
        XCTAssertEqual(PrefectureText.prefecture(in: "和歌山市"), "和歌山")
        XCTAssertNil(PrefectureText.prefecture(in: "Paris"))
        XCTAssertNil(PrefectureText.prefecture(in: ""))
        XCTAssertNil(PrefectureText.prefecture(in: nil))
        XCTAssertEqual(PrefectureText.shortNames.count, 47)
        XCTAssertEqual(Set(PrefectureText.shortNames).count, 47)
    }

    // MARK: - 旅のトランクの行（マイページとメニュー・案の頁「トランクを見やすく」版3）

    /// 貼っていないラベルがあれば、その枚数を言う（硬貨があっても先にラベル）
    func testStockSaysLabelsFirst() async {
        let summary = TrunkEntrySummary(coins: 3, unstuck: 2)
        XCTAssertEqual(TrunkEntryText.stock(summary), L("貼っていないラベルが2枚あります", "2 labels to stick"))
        XCTAssertEqual(TrunkEntryText.badge(summary), 2)
        XCTAssertEqual(TrunkEntryText.stock(TrunkEntrySummary(coins: 0, unstuck: 1)),
                       L("貼っていないラベルが1枚あります", "1 label to stick"))
    }

    /// ラベルが無くて硬貨があれば「カプセルを回せます」。件数バッジは出さない（0 は出さない）
    func testStockSaysCoinsWhenNoLabels() async {
        let summary = TrunkEntrySummary(coins: 3, unstuck: 0)
        XCTAssertEqual(TrunkEntryText.stock(summary),
                       L("硬貨が3枚あります。カプセルを回せます", "3 coins. Spin the capsule machine"))
        XCTAssertNil(TrunkEntryText.badge(summary), "0 枚の件数バッジを出している")
    }

    /// どちらも 0・まだ読めていないときは今までの説明の文。件数バッジは出さない
    func testStockFallsBackToTheUsualLine() async {
        XCTAssertEqual(TrunkEntryText.stock(TrunkEntrySummary(coins: 0, unstuck: 0)), TrunkEntryText.detail)
        XCTAssertEqual(TrunkEntryText.stock(nil), TrunkEntryText.detail)
        XCTAssertNil(TrunkEntryText.badge(TrunkEntrySummary(coins: 0, unstuck: 0)))
        XCTAssertNil(TrunkEntryText.badge(nil))
        // 負の数は 0 に丸める（`TrunkEntrySummary`）
        XCTAssertNil(TrunkEntryText.badge(TrunkEntrySummary(coins: -1, unstuck: -2)))
    }

    /// 画面の文に中黒を使わない（owner の好み・2026-11-12）
    func testStockHasNoMiddleDot() async {
        for summary in [TrunkEntrySummary(coins: 3, unstuck: 2), TrunkEntrySummary(coins: 3, unstuck: 0), nil] {
            let text = TrunkEntryText.stock(summary)
            XCTAssertFalse(text.contains("・") || text.contains("·"), text)
        }
    }

    /// メニューとマイページの行が同じ文と件数バッジを使う
    func testBothRowsUseTheSameWords() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
        let menu = try String(contentsOf: root.appendingPathComponent("Features/Common/SiteMenuView.swift"), encoding: .utf8)
        XCTAssertTrue(menu.contains("note: TrunkEntryText.stock(trunkEntry.summary),"))
        XCTAssertTrue(menu.contains("badge: TrunkEntryText.badge(trunkEntry.summary))"))
        XCTAssertTrue(menu.contains("CountBadge(count: badge, maximum: 99)"), "メニューの行に件数バッジが無い")
        let page = try String(contentsOf: root.appendingPathComponent("Features/Profile/MyPageView.swift"), encoding: .utf8)
        XCTAssertTrue(page.contains("detail: TrunkEntryText.stock(trunkEntry.summary),"))
        XCTAssertTrue(page.contains("badge: TrunkEntryText.badge(trunkEntry.summary))"))
        let parts = try String(contentsOf: root.appendingPathComponent("Core/Design/FormParts.swift"), encoding: .utf8)
        XCTAssertTrue(parts.contains("CountBadge(count: badge, maximum: 99)"), "マイページの行に件数バッジが無い")
    }

    // MARK: - 退会で、端末に残ったとおまわり号の控えを消す

    func testAccountRemovalForgetsLeftoverCamperData() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "camper-removal-" + UUID().uuidString))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // 前の版が書いていた鍵（`CamperStore`・`CamperServerState`・`CamperRoomStore`・`CamperRoomSeenStore`）
        let mine = ["camper.loadout.A", "camper.seen.A", "camper.inbox.A", "camper.room.seen.A",
                    "camper.room.A.car", "camper.room.A.sideRear", "camper.room.A.trailer"]
        for key in mine { defaults.set("x", forKey: key) }
        defaults.set("x", forKey: "camper.loadout.B")
        XCTAssertEqual(Set(LeftoverCamperData.keys(for: "A")).intersection(mine).count, mine.count, "前の鍵の綴りとずれている")
        AccountLocalData.remove(userId: "A", username: nil, defaults: defaults, draftDirectory: temp,
                                offlineTripsRoot: temp, passRoot: temp, feedbackRoot: temp)
        for key in mine { XCTAssertNil(defaults.object(forKey: key), "退会しても \(key) が残る") }
        XCTAssertNotNil(defaults.object(forKey: "camper.loadout.B"), "ほかの人の控えまで消した")
    }
}
