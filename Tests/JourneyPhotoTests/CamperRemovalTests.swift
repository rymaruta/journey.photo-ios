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
        // マイページは荷札（札 #714）。件数バッジは同じ数、「いま何があるか」は読み上げで言う
        let page = try String(contentsOf: root.appendingPathComponent("Features/Profile/MyPageView.swift"), encoding: .utf8)
        XCTAssertTrue(page.contains("TripToolTag(title: TripTool.trunk.title, badge: TrunkEntryText.badge(trunkEntry.summary))"))
        XCTAssertTrue(page.contains(".accessibilityValue(TrunkEntryText.accessibilityValue(trunkEntry.summary))"))
        let tag = try String(contentsOf: root.appendingPathComponent("Features/Profile/TripToolTag.swift"), encoding: .utf8)
        XCTAssertTrue(tag.contains("CountBadge(count: badge, maximum: 99)"), "マイページの札に件数バッジが無い")
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

    // MARK: - 端末全体の鍵は、起動のときに1回だけ消す

    func testDeviceKeysAreRemovedOnceAtLaunch() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "camper-device-" + UUID().uuidString))
        // 前の版の綴り（`CamperRoomCoach.key`・`CamperRoomPanelSplit` の defaultsKey）
        let device = ["camper.room.coach.v1", "camper.room.editPanelFraction"]
        XCTAssertEqual(Set(LeftoverCamperData.deviceKeys), Set(device), "前の鍵の綴りとずれている")
        defaults.set(true, forKey: "camper.room.coach.v1")
        defaults.set(0.5, forKey: "camper.room.editPanelFraction")
        // 消してはいけないもの: 人ごとの控え（退会のときに消す）と、関係ない鍵
        defaults.set("x", forKey: "camper.loadout.A")
        defaults.set("x", forKey: "camper.room.A.car")
        defaults.set(true, forKey: "trunk.welcome.A")
        defaults.set(1, forKey: "unrelated.setting")
        LeftoverCamperData.removeDeviceDataOnce(defaults: defaults)
        for key in device { XCTAssertNil(defaults.object(forKey: key), "起動しても \(key) が残る") }
        for key in ["camper.loadout.A", "camper.room.A.car", "trunk.welcome.A", "unrelated.setting"] {
            XCTAssertNotNil(defaults.object(forKey: key), "関係ない鍵 \(key) まで消した")
        }
        // 2回目は何もしない（消し終えた印を見る）
        defaults.set(true, forKey: "camper.room.coach.v1")
        LeftoverCamperData.removeDeviceDataOnce(defaults: defaults)
        XCTAssertNotNil(defaults.object(forKey: "camper.room.coach.v1"), "毎回の起動で消している（1回だけのはず）")
    }

    /// 起動の入口が呼んでいる
    func testAppLaunchCallsDeviceCleanup() async throws {
        let app = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/App/JourneyPhotoApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("LeftoverCamperData.removeDeviceDataOnce()"), "起動で端末全体の鍵を消していない")
    }

    // MARK: - 投稿の応答に `camper` が入っていても壊れない

    func testDealtIgnoresCamperInResponse() async {
        let dealt = TrunkDealt.read(Data(#"{"success":true,"coin":1,"camper":{"added":["x"]}}"#.utf8))
        XCTAssertEqual(dealt.coin, 1, "camper の欄があると硬貨を読めない")
        XCTAssertNil(dealt.label)
        let odd = TrunkDealt.read(Data(#"{"coin":1,"camper":"broken","label":null}"#.utf8))
        XCTAssertEqual(odd.coin, 1)
    }

    // MARK: - 引っ越した CPU とメモリの読み取り（前の `CamperRenderMeter`）

    func testProcessUsageReadsOnDevice() async {
        #if canImport(Darwin)
        let usage = ProcessUsage.current()
        XCTAssertNotNil(usage)
        XCTAssertGreaterThan(usage?.cpuMs ?? 0, 0)
        XCTAssertGreaterThan(usage?.memMB ?? 0, 0)
        XCTAssertTrue(ProcessUsage.vmTagSummary().hasPrefix("TOTAL="))
        #else
        XCTAssertNil(ProcessUsage.current(), "Linux では読まない")
        #endif
    }

    // MARK: - 消した部屋の古い注記

    func testNoNotesAboutTheCamperRoom() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var found: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("キャンピングカーの部屋") { found.append(url.lastPathComponent) }
        }
        XCTAssertEqual(found, [], "消した「キャンピングカーの部屋」の注記が残っている")
    }
}
