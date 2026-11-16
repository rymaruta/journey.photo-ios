import XCTest
@testable import JourneyPhoto

/// 使い勝手の見直し 2026-11-16 の「計画する」の段（A2・A5・A6）。
///
/// - A2 旅の日はホームの札1回で今日の日程（今日の日まで送る・見出し「今日」・札の縁は真鍮）。2日目からの投稿の入口は札の右の「＋」
/// - A5 日程の画面の「日付」の欄1つ（押すと作る流れと同じ暦と近くの休み）
/// - A6 Pro でない人の「電波なしで使えるようにする PRO」は最後の日の下・「誘う」は日付の欄の右・AI の「並べた理由」は1行に畳む
///
/// 画面は Linux では描けないので、**決まりは数と字で**、**部品のつなぎは元のファイルを読んで**見張る（`TripsDesignTests` と同じ）
final class UXPlanStageTests: XCTestCase {

    // MARK: - 道具

    private let utc = TimeZone(identifier: "UTC")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func at(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func days(_ n: Int) -> [TripDay] { Array(repeating: TripDay(), count: n) }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ text: String, from marker: String, to end: String) -> String {
        guard let s = text.range(of: marker) else { XCTFail("「\(marker)」が無い"); return "" }
        let rest = text[s.lowerBound...]
        guard let e = rest.range(of: end, range: rest.index(after: rest.startIndex)..<rest.endIndex) else { return String(rest) }
        return String(rest[..<e.lowerBound])
    }

    private func assertInOrder(_ parts: [String], in text: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: cursor..<text.endIndex) else {
                XCTFail("\(what): 「\(part)」が無いか、順が違う", file: file, line: line)
                return
            }
            cursor = found.upperBound
        }
    }

    // MARK: - A2 今日の日

    /// 3日の旅の2日目（日本の昼）
    func testTodayIsTheSecondDay() {
        XCTAssertEqual(TripPlanText.todayIndex(days: days(3), start: "2026-12-16", end: "2026-12-18",
                                               now: at("2026-12-17T03:00:00Z"), in: tokyo), 1)
    }

    /// 日付の無いプランには今日の日が無い（送らない・札を囲まない）
    func testUndatedPlanHasNoToday() {
        XCTAssertNil(TripPlanText.todayIndex(days: days(3), start: nil, end: nil,
                                             now: at("2026-12-17T03:00:00Z"), in: tokyo))
    }

    /// 旅の前の日・旅のあとの日は nil
    func testNoTodayBeforeOrAfterTheTrip() {
        XCTAssertNil(TripPlanText.todayIndex(days: days(2), start: "2026-12-16", end: "2026-12-17",
                                             now: at("2026-12-15T03:00:00Z"), in: tokyo), "前の日")
        XCTAssertNil(TripPlanText.todayIndex(days: days(2), start: "2026-12-16", end: "2026-12-17",
                                             now: at("2026-12-18T03:00:00Z"), in: tokyo), "あとの日")
        // 日程の日の数が帰着より短い（3日の旅に2日分の予定）: 3日目は日程に無いので nil
        XCTAssertNil(TripPlanText.todayIndex(days: days(2), start: "2026-12-16", end: "2026-12-18",
                                             now: at("2026-12-18T03:00:00Z"), in: tokyo), "日程に無い日")
    }

    /// 年と月をまたぐ旅（12/31 → 1/2）の元日は2日目
    func testTodayAcrossTheNewYear() {
        XCTAssertEqual(TripPlanText.todayIndex(days: days(3), start: "2026-12-31", end: "2027-01-02",
                                               now: at("2027-01-01T03:00:00Z"), in: tokyo), 1)
    }

    /// その日が持っている日付（Web で付けた日付）を先に使う（`dayDate` と同じ）
    func testDayOwnDateWins() {
        let plan = [TripDay(date: "2026-12-20"), TripDay(date: "2026-12-16")]
        XCTAssertEqual(TripPlanText.todayIndex(days: plan, start: "2026-12-16", end: "2026-12-17",
                                               now: at("2026-12-16T03:00:00Z"), in: tokyo), 1)
    }

    /// 🔴 **時刻帯（TripBookFacts と同じ UTC の決まり）**: 日本の朝 7 時（UTC ではまだ前の日の 22 時）は日本の暦の日。
    /// UTC で今日を数えると、1日前の日を「今日」と言う
    func testTokyoMorningUsesTheLocalDay() {
        let morning = at("2026-12-16T22:00:00Z")   // JST 12/17 07:00
        XCTAssertEqual(TripPlanText.todayIndex(days: days(3), start: "2026-12-16", end: "2026-12-18",
                                               now: morning, in: tokyo), 1)
        XCTAssertEqual(TripPlanText.todayIndex(days: days(3), start: "2026-12-16", end: "2026-12-18",
                                               now: morning, in: utc), 0, "UTC の暦ではまだ 12/16")
    }

    /// 西の時刻帯: UTC で 12/17 05:00 はロサンゼルスでは 12/16 の夜
    func testLosAngelesEveningUsesTheLocalDay() {
        XCTAssertEqual(TripPlanText.todayIndex(days: days(3), start: "2026-12-16", end: "2026-12-18",
                                               now: at("2026-12-17T05:00:00Z"), in: losAngeles), 0)
    }

    /// ホームの「旅の最中 N日目」と、開いた日程の今日の日がそろう（同じ今日の数え方）
    func testHomeCardDayMatchesTodayInThePlan() {
        let plan = TripPlan(planId: "p", title: "金沢、福井の旅", startDate: "2026-12-16", endDate: "2026-12-18",
                            days: days(3))
        for (now, zone) in [(at("2026-12-16T22:00:00Z"), tokyo), (at("2026-12-17T05:00:00Z"), losAngeles),
                            (at("2026-12-18T12:00:00Z"), utc)] {
            let today = HomeTopCard.today(now, in: zone)!
            let index = TripPlanText.todayIndex(days: plan.days, start: plan.startDate, end: plan.endDate, now: now, in: zone)
            if case .onTrip(_, let dayNumber)? = HomeTopCard.onTrip(today: today, plans: [plan]) {
                XCTAssertEqual(index.map { $0 + 1 }, dayNumber, "\(zone.identifier) \(now)")
            } else if case .departure(_, let until)? = HomeTopCard.departure(today: today, plans: [plan]) {
                XCTAssertEqual(until, 0)
                XCTAssertEqual(index, 0, "\(zone.identifier) \(now)")
            } else {
                XCTFail("旅の日に札が出ない \(zone.identifier) \(now)")
            }
        }
    }

    /// UI テストの旅の途中の見本は、日本の朝でも「今日は2日目」（ホームの札と日程の今日がそろう）
    func testOnTripFixtureIsOnTheSecondDay() {
        let morning = at("2026-12-16T22:00:00Z")   // JST 12/17 07:00
        let plan = TripPlanFixture.onTripPlan(now: morning, zone: tokyo)
        XCTAssertEqual(plan.startDate, "2026-12-16")
        XCTAssertEqual(plan.endDate, "2026-12-18")
        let today = HomeTopCard.today(morning, in: tokyo)!
        XCTAssertEqual(HomeTopCard.onTrip(today: today, plans: [plan]), .onTrip(plan: plan, dayNumber: 2))
        XCTAssertEqual(TripPlanText.todayIndex(days: plan.days, start: plan.startDate, end: plan.endDate,
                                               now: morning, in: tokyo), 1)
    }

    /// 見出し「今日　2 日目　12月17日」（今日の日だけ頭に「今日」）
    func testTodayHeading() {
        let date = TakenDay.label("2026-12-17") ?? ""
        XCTAssertEqual(TripPlanDetailView.dayHeadingText(1, date: "2026-12-17", today: true),
                       L("今日\u{2002}2 日目\u{2002}", "Today\u{2002}Day 2\u{2002}") + date)
        XCTAssertEqual(TripPlanDetailView.dayHeadingText(1, date: "2026-12-17", today: false),
                       L("2 日目\u{2002}", "Day 2\u{2002}") + date)
        XCTAssertEqual(TripPlanDetailView.dayHeadingText(0, date: nil, today: false), L("1 日目", "Day 1"))
    }

    /// 札を押すとプランを直に開くのは出発の当日と旅の最中。出発の前の日までは一覧
    func testHomeCardOpensThePlanOnTripDays() throws {
        XCTAssertTrue(HomeTopCardView.opensPlan(daysUntil: 0))
        XCTAssertFalse(HomeTopCardView.opensPlan(daysUntil: 1))
        XCTAssertEqual(HomeTopCardView.onTripLine(dayNumber: 2), L("2日目\u{2002}今日の日程", "Day 2\u{2002}Today's plan"))

        let home = try source("Features/Gallery/HomeTopCardView.swift")
        let onTrip = slice(home, from: "case .onTrip(let plan, let dayNumber):", to: "case .bookReady")
        assertInOrder(["NavigationLink {", "TripPlanOpenView(planId: plan.planId, opensToday: true)",
                       "trailingSymbol: nil", ".overlay(alignment: .bottomTrailing) { onTripPostButton(inCarousel: inCarousel) }",
                       ".tripCardMenu("], in: onTrip, "旅の最中の札: 押すと今日の日程 → 右下に「＋」")
        XCTAssertFalse(onTrip.contains("Button {\n                MissionRouter.shared.post()"), "札全体が投稿の画面を開くまま")
        let post = slice(home, from: "private func onTripPostButton(", to: "nonisolated static let postCircle")
        XCTAssertTrue(post.contains("MissionRouter.shared.post()"), "「＋」は投稿の入口")
        XCTAssertTrue(post.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"), "「＋」の当たり 44")
        XCTAssertEqual(HomeTopCardView.postCircle, 36)
        let departure = slice(home, from: "case .departure(let plan, let daysUntil):", to: "case .onTrip")
        assertInOrder(["if Self.opensPlan(daysUntil: daysUntil) {", "TripPlanOpenView(planId: plan.planId, opensToday: true)",
                       "TripPlansView()"], in: departure, "出発の当日はプラン、前の日までは一覧")
        // 札の字が「＋」の下に潜らない（右の印の代わりに丸の幅を空ける）
        XCTAssertEqual(TopCardFace.trailingReserve, HomeTopCardView.postCircle)
    }

    /// 日程の画面: 今日の日まで送る（開いたときの1回だけ）・今日の日は札で囲む（縁は真鍮 55%）
    func testPlanScrollsToTodayAndFramesIt() throws {
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        let editor = slice(detail, from: "private func editor(_ plan: TripPlan)", to: "nonisolated static func dayAnchor")
        assertInOrder(["ScrollViewReader { proxy in", "isToday: di == today", ".id(Self.dayAnchor(di))",
                       ".onChange(of: today, initial: true)", "guard opensToday, !scrolledToToday, let index",
                       "proxy.scrollTo(Self.dayAnchor(index), anchor: .top)"], in: editor, "今日の日まで送る")
        let day = slice(detail, from: "private func daySection(", to: "private func daySpots(")
        assertInOrder(["JPEyebrowLine(dayHeading(di, day, today: isToday))", ".modifier(TripTodayFrame(on: isToday))"],
                      in: day, "見出しの「今日」と札")
        XCTAssertEqual(TripTodayFrame.borderOpacity, 0.55)
        let frame = slice(detail, from: "struct TripTodayFrame: ViewModifier {", to: "struct TripAISwapTarget")
        XCTAssertTrue(frame.contains("WebTheme.accent.opacity(Self.borderOpacity)"), "縁は真鍮")
        XCTAssertTrue(frame.contains("WebTheme.card"), "地は札の面（真鍮は黒い地の上）")
        XCTAssertTrue(frame.contains("JPRadius.l"), "角 16")
        let open = try source("Features/Trips/TripShareViews.swift")
        XCTAssertTrue(open.contains("TripPlanDetailView(planId: planId, model: model, startTab: startTab, opensToday: opensToday)"))
        XCTAssertTrue(try source("Features/Messages/DMInboxView.swift").contains("TripPlanOpenView(planId: planId, startTab: .chat)"),
                      "受信箱からは今どおり会話のタブ")
    }

    // MARK: - A5 日付の欄

    /// 「日付　1 泊 2 日」と「12月16日（水）〜 17日（木）」
    func testPeriodFieldForARange() throws {
        let field = try XCTUnwrap(TripDraft.periodField(start: "2026-12-16", end: "2026-12-17"))
        XCTAssertEqual(field.label, L("日付\u{3000}1 泊 2 日", "Dates\u{3000}1 night, 2 days"))
        XCTAssertEqual(field.value, L("12月16日（水）〜 17日（木）", "Dec 16 (Wed)〜 17 (Thu)"))
    }

    /// 月をまたぐ・日帰り
    func testPeriodFieldAcrossMonthsAndDayTrip() throws {
        let across = try XCTUnwrap(TripDraft.periodField(start: "2026-12-31", end: "2027-01-02"))
        XCTAssertEqual(across.label, L("日付\u{3000}2 泊 3 日", "Dates\u{3000}2 nights, 3 days"))
        XCTAssertEqual(across.value, L("12月31日（木）〜 1月2日（土）", "Dec 31 (Thu)〜 Jan 2 (Sat)"))
        let day = try XCTUnwrap(TripDraft.periodField(start: "2026-12-16", end: "2026-12-16"))
        XCTAssertEqual(day.label, L("日付\u{3000}日帰り", "Dates\u{3000}Day trip"))
        XCTAssertEqual(day.value, L("12月16日（水）", "Dec 16 (Wed)"))
    }

    /// 日付の無いプランは nil（欄は「日付を入れる」）。Web で作った片方だけ・帰着が前のプランは、入っている日付をそのまま見せる
    func testPeriodFieldKeepsWhatTheWebSaved() {
        XCTAssertNil(TripDraft.periodField(start: nil, end: nil))
        XCTAssertNil(TripDraft.periodField(start: "2026-02-30", end: nil), "実在しない日は出さない")
        XCTAssertEqual(TripDraft.periodField(start: nil, end: "2026-12-17")?.value, L("〜 12月17日（木）", "〜 Dec 17 (Thu)"))
        XCTAssertEqual(TripDraft.periodField(start: "2026-12-17", end: "2026-12-16")?.value,
                       L("12月17日（木）〜 12月16日（水）", "Dec 17 (Thu)〜 Dec 16 (Wed)"))
        XCTAssertEqual(TripDraft.periodField(start: "2026-12-17", end: "2026-12-16")?.label, L("日付", "Dates"))
    }

    /// 作る流れの1行は今までどおり
    func testRangeLineUnchanged() {
        XCTAssertEqual(TripDraft.rangeLine(start: "2026-12-24", end: "2026-12-25"),
                       L("12月24日（木）〜 25日（金）\u{2002}1 泊 2 日", "Dec 24 (Thu)〜 25 (Fri)\u{2002}1 night, 2 days"))
        XCTAssertEqual(TripDraft.rangeLine(start: "2026-12-24", end: nil), L("12月24日（木）\u{2002}日帰り", "Dec 24 (Thu)\u{2002}Day trip"))
    }

    /// シートの暦: 出発 → 帰着の2回で閉じる。前の日を押したら出発から選び直し。入っている期間を押すと出発から
    func testDatesSheetClosesWhenTheRangeIsComplete() {
        let first = TripPlanDatesSheet.tapped(start: nil, end: nil, day: "2026-12-16")
        XCTAssertEqual(first.start, "2026-12-16"); XCTAssertNil(first.end); XCTAssertFalse(first.closes)
        let second = TripPlanDatesSheet.tapped(start: first.start, end: first.end, day: "2026-12-17")
        XCTAssertEqual(second.start, "2026-12-16"); XCTAssertEqual(second.end, "2026-12-17"); XCTAssertTrue(second.closes)
        let earlier = TripPlanDatesSheet.tapped(start: "2026-12-16", end: nil, day: "2026-12-10")
        XCTAssertEqual(earlier.start, "2026-12-10"); XCTAssertNil(earlier.end); XCTAssertFalse(earlier.closes)
        let restart = TripPlanDatesSheet.tapped(start: "2026-12-16", end: "2026-12-17", day: "2026-12-20")
        XCTAssertEqual(restart.start, "2026-12-20"); XCTAssertNil(restart.end); XCTAssertFalse(restart.closes)
        let dayTrip = TripPlanDatesSheet.tapped(start: "2026-12-16", end: nil, day: "2026-12-16")
        XCTAssertEqual(dayTrip.end, "2026-12-16"); XCTAssertTrue(dayTrip.closes, "同じ日をもう一度で日帰り")
    }

    /// 欄1つ（端末の日付ピッカー2つをやめた）→ 作る流れと同じ暦と近くの休み → 決めた値は start・end へ（自動で保存）
    func testDateFieldOpensTheSameCalendar() throws {
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        XCTAssertFalse(detail.contains("DatePicker("), "端末の日付ピッカーが残っている")
        let header = slice(detail, from: "private func header(_ plan: TripPlan)", to: "private func shareSection(")
        assertInOrder(["HStack(spacing: JPSpace.xs) {", "dateField()", "if !isOffline { inviteButton(plan) }",
                       "shareSection(plan)", "TripPlanDatesSheet(start: start, end: end) { s, e in", "start = s", "end = e"],
                      in: header, "日付の欄 → 誘う → 仲間の段 → 暦のシート")
        let field = slice(detail, from: "private func dateField()", to: "private func inviteButton(")
        assertInOrder(["TripDraft.periodField(start: start, end: end)", "editingDates = true",
                       "TripStyle.dateFieldHeight", "\"tripPlan.dates\""], in: field, "日付の欄")
        let create = try source("Features/Trips/TripCreateView.swift")
        let sheet = slice(create, from: "struct TripPlanDatesSheet: View {", to: "// MARK: - ③ 下書き")
        assertInOrder(["TripHolidayChips(pairs: pairs, start: start, end: end)", "TripCalendar(month: $month",
                       "allowsPast: true", "L(\"日付を外す\""], in: sheet, "近くの休み → 暦 → 日付を外す")
        XCTAssertTrue(create.contains("TripHolidayChips(pairs: pairs, start: model.start, end: model.end)"),
                      "作る流れも同じ休みのチップ（写しを作らない）")
        XCTAssertTrue(create.contains("let past = !allowsPast && day < today"), "作る流れは今どおり今日から")
    }

    // MARK: - A6 日程を先に見せる

    /// Pro でない人の札は下だけ・Pro の人の札は上だけ・読めていない間はどちらにも出さない
    func testOfflineCardSlots() {
        XCTAssertTrue(OfflineTripCard.shows(.free, in: .bottom))
        XCTAssertFalse(OfflineTripCard.shows(.free, in: .top))
        XCTAssertTrue(OfflineTripCard.shows(.before, in: .top))
        XCTAssertFalse(OfflineTripCard.shows(.before, in: .bottom))
        XCTAssertFalse(OfflineTripCard.shows(.hidden, in: .top))
        XCTAssertFalse(OfflineTripCard.shows(.hidden, in: .bottom))
    }

    /// 並び: 題 → 日付と誘う → 上の札（Pro）→ 日 → 日を追加 → 下の札（無料）→ 削除。Pro かは上の1枚だけが読む
    func testPlanShowsDaysFirst() throws {
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        let editor = slice(detail, from: "private func editor(_ plan: TripPlan)", to: "nonisolated static func dayAnchor")
        assertInOrder(["header(plan)", "TripAICard(", "slot: .top, isPro: $offlinePro", "ForEach(Array(days.enumerated())",
                       "addDayButton", "slot: .bottom, isPro: $offlinePro", "deleteCard(plan)"], in: editor, "日程を先に")
        let card = try source("Features/Trips/OfflineTripCard.swift")
        XCTAssertTrue(card.contains("guard slot == .top else { return }"), "下の1枚も Pro かを読みに行く（2回読む）")
        XCTAssertTrue(card.contains("@Binding var isPro: Bool?"))
    }

    /// 誘うは日付の欄の右（日程の画面の仲間の段には出さない・会話の画面は今どおり段の中）
    func testInviteSitsBesideTheDates() throws {
        let plan = TripPlan(planId: "p", title: "t")
        XCTAssertFalse(TripShareStrip.hasContent(plan: plan, peer: nil, showsInvite: false), "共有していないプランに空の段")
        XCTAssertTrue(TripShareStrip.hasContent(plan: plan, peer: nil, showsInvite: true))
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(detail.contains("shareStrip(plan, showsInvite: false)"), "日程の画面の段に誘うが残っている")
        let chat = slice(detail, from: "private func chatScreen(_ plan: TripPlan)", to: "private func loadShare(")
        XCTAssertTrue(chat.contains("shareStrip(plan).padding"), "会話の画面の誘う")
        let invite = slice(detail, from: "private func inviteButton(", to: "// MARK: - 日ごと")
        assertInOrder(["await invite(plan)", "L(\"誘う\", \"Invite\")", "TripStyle.dateFieldHeight",
                       "JPRadius.field", ".accessibilityLabel(TripShareText.invite)", "\"tripShare.invite\""],
                      in: invite, "誘う（欄と同じ 52・角 12・読み上げは「仲間を誘う」）")
    }

    /// 並べた理由は1行に畳む（押すと開く）。理由の無いプランは押すだけの直しの名前
    func testAIReasonFoldsToOneLine() throws {
        let folded = TripAICard.foldedLine(reason: "  秋の案内がある所を入れ、朝に向く所を先に\n")
        XCTAssertEqual(folded.eyebrow, L("並べた理由", "Why this order"))
        XCTAssertEqual(folded.text, "秋の案内がある所を入れ、朝に向く所を先に")
        let empty = TripAICard.foldedLine(reason: " ")
        XCTAssertEqual(empty.eyebrow, L("押すだけで直す", "Quick changes"))
        XCTAssertEqual(empty.text, TripAITweak.allCases.map(\.title).joined(separator: L("、", ", ")))

        let card = try source("Features/Trips/AI/TripAICard.swift")
        XCTAssertTrue(card.contains("@State private var open = false"), "はじめから開いている")
        XCTAssertTrue(card.contains("if open { openCard } else { foldedCard }"))
        let fold = slice(card, from: "private var foldedCard: some View {", to: "private var openCard: some View {")
        assertInOrder([".lineLimit(1)", "chevron.down", "WebTheme.minTapTarget", "JPRadius.field", "\"tripAI.folded\"", "band"],
                      in: fold, "畳んだ行（1行・44・角 12）と、AI なしで組んだ帯")
    }
}
