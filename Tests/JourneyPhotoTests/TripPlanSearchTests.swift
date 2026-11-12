import XCTest
@testable import JourneyPhoto

/// 旅行プランを簡単に操作する（2026-11-12・1.1.85・札 #570・資料「みんなで埋める旅行プラン」の場面5〜7）。
///
/// - 場所を足すシートの探す欄（`TripPlanSearch`）: ひらがな・別名で観光スポットが当たる・打った字は入れない
/// - 持ち手 ≡ の読み上げの操作（`TripPlanEdit.accessibilityMoves`）と、「…」の「2日目へ移す」
/// - 外した場所を戻す（`TripPlanEdit.Removed`・この画面を開いている間）
final class TripPlanSearchTests: XCTestCase {

    // MARK: - 道具

    private func spot(_ slug: String, name: String, reading: String? = nil, stage: String = "published",
                      prefecture: String? = "石川県") throws -> OfficialSpot {
        var fields = ["\"spotId\":\"sp_\(slug)\"", "\"slug\":\"\(slug)\"", "\"name\":\"\(name)\"", "\"stage\":\"\(stage)\""]
        if let reading { fields.append("\"reading\":\"\(reading)\"") }
        if let prefecture { fields.append("\"region\":{\"prefecture\":\"\(prefecture)\"}") }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func choice(_ s: OfficialSpot) -> TripPlanText.Choice {
        TripPlanText.Choice(item: .spot(spotId: s.spotId, note: nil), name: s.name, regionLabel: s.regionLabel)
    }

    private func s(_ id: String) -> TripItem { .spot(spotId: "sp_\(id)", note: nil) }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    // MARK: - 探す（場面5）

    /// 欄が空なら今までどおり行きたい場所だけ（観光スポットの組は出さない）
    func testEmptyQueryShowsWantedOnly() throws {
        let kenroku = try spot("kenroku", name: "兼六園", reading: "けんろくえん")
        let wanted = [choice(kenroku)]
        let g = TripPlanSearch.groups(query: "  ", wanted: wanted, index: [kenroku])
        XCTAssertEqual(g.wanted, wanted)
        XCTAssertTrue(g.spots.isEmpty)
    }

    /// ひらがなの読みで台帳の観光スポットが当たる（行きたい場所に入れていなくても）
    func testHiraganaReadingFindsLedgerSpot() throws {
        let tojinbo = try spot("tojinbo", name: "東尋坊", reading: "とうじんぼう", prefecture: "福井県")
        let other = try spot("kenroku", name: "兼六園", reading: "けんろくえん")
        let g = TripPlanSearch.groups(query: "とうじんぼう", wanted: [], index: [other, tojinbo])
        XCTAssertEqual(g.spots.map(\.item), [.spot(spotId: "sp_tojinbo", note: nil)])
        XCTAssertEqual(g.spots.first?.name, "東尋坊", "入るのは台帳の鍵。名前は台帳の名前（打った字ではない）")
    }

    /// 別名でも当たる（`fetchAliases` の slug → 別名）
    func testAliasFindsSpot() throws {
        let castle = try spot("castle", name: "金沢城公園", reading: "かなざわじょうこうえん")
        let g = TripPlanSearch.groups(query: "石川門", wanted: [], index: [castle], aliases: ["castle": ["石川門"]])
        XCTAssertEqual(g.spots.map(\.id), ["spot:sp_castle"])
    }

    /// 行きたい場所に入っている観光スポットは上の組だけ（同じ所を2つ並べない）。撮影地は名前で当てる
    func testWantedFirstAndNotDuplicated() throws {
        let kenroku = try spot("kenroku", name: "兼六園", reading: "けんろくえん")
        let kenrokuLoc = TripPlanText.Choice(item: .location(slug: "兼六園周辺", note: nil), name: "兼六園周辺", regionLabel: nil)
        let other = TripPlanText.Choice(item: .location(slug: "福井", note: nil), name: "福井", regionLabel: nil)
        let g = TripPlanSearch.groups(query: "けんろく", wanted: [choice(kenroku), kenrokuLoc, other], index: [kenroku])
        XCTAssertEqual(g.wanted.map(\.id), ["spot:sp_kenroku"], "読みで当てる。撮影地はひらがなの読みを持たないので当たらない")
        XCTAssertTrue(g.spots.isEmpty, "行きたい場所と同じ観光スポットを下の組に重ねない")
        let byName = TripPlanSearch.groups(query: "兼六", wanted: [choice(kenroku), kenrokuLoc, other], index: [kenroku])
        XCTAssertEqual(byName.wanted.map(\.id), ["spot:sp_kenroku", "location:兼六園周辺"])
    }

    /// 運営の下書きは結果に出さない・上限で切る・何も無ければ空
    func testDraftsHiddenAndLimit() throws {
        let draft = try spot("d", name: "下書きの寺", reading: "したがきのてら", stage: "draft")
        XCTAssertTrue(TripPlanSearch.groups(query: "したがき", wanted: [], index: [draft]).isEmpty)
        let many = try (0..<40).map { try spot("t\($0)", name: "寺\($0)", reading: "てら") }
        XCTAssertEqual(TripPlanSearch.groups(query: "てら", wanted: [], index: many).spots.count, TripPlanSearch.spotLimit)
        XCTAssertTrue(TripPlanSearch.groups(query: "ぜんぜんない", wanted: [], index: many).isEmpty)
        XCTAssertTrue(TripPlanSearch.noResults(" ぜんぜんない ").contains("「ぜんぜんない」"))
    }

    /// 行の状態: 前から入っている場所は押せない・このシートで入れた場所は取り消せる・いっぱいの日は押せない
    func testRowState() {
        let days = [TripDay(items: [s("a")]), TripDay(items: [s("b")])]
        XCTAssertEqual(TripPlanSearch.state(of: s("c"), days: days, selectedDay: 1, addedHere: []), .open)
        XCTAssertEqual(TripPlanSearch.state(of: s("a"), days: days, selectedDay: 1, addedHere: []), .inPlan(day: 0))
        let added = [TripPlanSearch.Added(key: "spot:sp_b", day: 1)]
        XCTAssertEqual(TripPlanSearch.state(of: s("b"), days: days, selectedDay: 1, addedHere: added), .added)
        XCTAssertEqual(TripPlanSearch.state(of: s("b"), days: days, selectedDay: 0, addedHere: added), .inPlan(day: 1),
                       "別の日を選んでいる間は取り消しにしない")
        let full = [TripDay(items: (0..<TripPlanService.itemsPerDayMax).map { s("f\($0)") })]
        XCTAssertEqual(TripPlanSearch.state(of: s("z"), days: full, selectedDay: 0, addedHere: []), .full)
        XCTAssertNil(TripPlanSearch.stateLine(.open))
        XCTAssertEqual(TripPlanSearch.stateLine(.inPlan(day: 1)), L("2日目に入っています", "Already on day 2"))
    }

    /// 取り消しは、その日の中の最後の同じ項目だけを外す
    func testUndoRemovesLastMatchOnThatDay() {
        let days = [TripDay(items: [s("a")]), TripDay(items: [s("b"), s("c")])]
        XCTAssertEqual(TripPlanSearch.undoing(s("c"), day: 1, in: days), [TripDay(items: [s("a")]), TripDay(items: [s("b")])])
        XCTAssertNil(TripPlanSearch.undoing(s("a"), day: 1, in: days), "その日に無ければ何もしない")
        XCTAssertNil(TripPlanSearch.undoing(s("a"), day: 5, in: days))
    }

    // MARK: - 持ち手と「…」（場面7）

    /// 読み上げの操作: 上へ・下へ（端では出さない）→ 移せる日 → 外す
    func testAccessibilityMoves() {
        let days = [TripDay(items: [s("a"), s("b"), s("c")]), TripDay(items: [s("d")])]
        XCTAssertEqual(TripPlanEdit.accessibilityMoves(days, day: 0, item: 0), [.down, .toDay(1), .remove])
        XCTAssertEqual(TripPlanEdit.accessibilityMoves(days, day: 0, item: 1), [.up, .down, .toDay(1), .remove])
        XCTAssertEqual(TripPlanEdit.accessibilityMoves(days, day: 1, item: 0), [.toDay(0), .remove])
        XCTAssertEqual(TripPlanEdit.accessibilityMoves(days, day: 3, item: 0), [])
        XCTAssertEqual(TripPlanDetailView.moveTitle(.toDay(1)), L("2日目へ移す", "Move to day 2"))
    }

    /// 移せる日が1つだけなら「2日目へ移す」を直接出す（日を選ぶ段を挟まない）
    func testDirectMoveTarget() {
        let two = [TripDay(items: [s("a")]), TripDay()]
        XCTAssertEqual(TripPlanEdit.directMoveTarget(two, from: 0), 1)
        let three = [TripDay(items: [s("a")]), TripDay(), TripDay()]
        XCTAssertNil(TripPlanEdit.directMoveTarget(three, from: 0))
        XCTAssertNil(TripPlanEdit.directMoveTarget([TripDay(items: [s("a")])], from: 0), "1日だけなら移す先が無い")
    }

    // MARK: - 外して戻す（場面6）

    /// 戻すと外したときの位置へ。日が短くなっていれば末尾。もう入っていれば戻さない
    func testRestoreGoesBackToItsPlace() {
        let removed = TripPlanEdit.Removed(id: 1, day: 0, index: 1, item: s("b"))
        let now = [TripDay(items: [s("a"), s("c")])]
        XCTAssertEqual(TripPlanEdit.restoring(now, removed), [TripDay(items: [s("a"), s("b"), s("c")])])
        let shorter = [TripDay()]
        XCTAssertEqual(TripPlanEdit.restoring(shorter, removed), [TripDay(items: [s("b")])])
        XCTAssertNil(TripPlanEdit.restoring([TripDay(items: [s("b")])], removed), "もう入っている")
        XCTAssertNil(TripPlanEdit.restoring([], removed), "日が無い")
        let full = [TripDay(items: (0..<TripPlanService.itemsPerDayMax).map { s("f\($0)") })]
        XCTAssertNil(TripPlanEdit.restoring(full, removed), "いっぱいの日へは戻さない")
    }

    /// 日の下の控え: その日の分だけ・戻った場所は出さない。日を消したら詰める
    func testShelf() {
        let a = TripPlanEdit.Removed(id: 1, day: 0, index: 0, item: s("a"))
        let b = TripPlanEdit.Removed(id: 2, day: 1, index: 0, item: s("b"))
        let c = TripPlanEdit.Removed(id: 3, day: 2, index: 0, item: s("c"))
        let days = [TripDay(), TripDay(items: [s("b")]), TripDay()]
        XCTAssertEqual(TripPlanEdit.shelf([a, b, c], day: 0, days: days), [a])
        XCTAssertEqual(TripPlanEdit.shelf([a, b, c], day: 1, days: days), [], "足し直した場所は出さない")
        let after = TripPlanEdit.shelfAfterRemovingDay([a, b, c], removedDay: 1)
        XCTAssertEqual(after.map(\.id), [1, 3])
        XCTAssertEqual(after.last?.day, 1, "後ろの日は1つ前へ")
    }

    // MARK: - 画面のつなぎ（元のファイルを読む）

    /// 持ち手は常に出す（見本だけの版をやめた）。運ぶのは持ち手だけ。読み上げは上下のスワイプと操作
    func testHandleIsAlwaysShown() throws {
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        XCTAssertFalse(detail.contains("dragHandleVariant"), "持ち手が見本のときだけになっている")
        XCTAssertFalse(try source("Services/TripPlanFixture.swift").contains("dragHandleVariant"))
        guard let row = detail.range(of: "private func itemRow("),
              let end = detail.range(of: "private func dragHandle(") else { return XCTFail("行が無い") }
        let rowText = String(detail[row.lowerBound..<end.lowerBound])
        XCTAssertTrue(rowText.contains("dragHandle(di, ii, item, name: name)"), "行に持ち手が無い")
        XCTAssertFalse(rowText.contains(".draggable("), "行全体を運ぶ形が残っている（押した所と運ぶ所が混ざる）")
        guard let handle = detail.range(of: "private func dragHandle("),
              let handleEnd = detail.range(of: "nonisolated static func moveTitle(") else { return XCTFail("持ち手が無い") }
        let h = String(detail[handle.lowerBound..<handleEnd.lowerBound])
        for part in ["Image(systemName: \"line.3.horizontal\")", ".webTappable()",
                     ".draggable(TripPlanEdit.dragPayload(day: di, item: ii, of: item))",
                     "case .increment: perform(.up, di, ii, item, name: name)",
                     "case .decrement: perform(.down, di, ii, item, name: name)",
                     ".accessibilityActions {", ".accessibilityIdentifier(\"tripPlan.dragHandle\")"] {
            XCTAssertTrue(h.contains(part), "持ち手に \(part) が無い")
        }
    }

    /// 外したら控えに積み、日の下に「戻す」を出す
    func testRemoveKeepsRestoreRow() throws {
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(detail.contains("removedShelf.append(TripPlanEdit.Removed(id: removedSeq, day: di, index: at, item: item))"))
        XCTAssertTrue(detail.contains("ForEach(TripPlanEdit.shelf(removedShelf, day: di, days: days)) { removed in"))
        XCTAssertTrue(detail.contains("guard let next = TripPlanEdit.restoring(days, removed) else {"))
        XCTAssertTrue(detail.contains("if let only = TripPlanEdit.directMoveTarget(days, from: di) {"))
    }
}
