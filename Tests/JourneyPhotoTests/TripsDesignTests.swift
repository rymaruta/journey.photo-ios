import XCTest
@testable import JourneyPhoto

/// 旅（旅の一覧・旅の一冊・一冊の共有・旅行プラン・日ごとの予定・プランの選び方）と
/// オフライン保存の画面の **v2 の決まり**（v2 の板 Trips ほか・2026-10-14）。
///
/// 画面は Linux では描けないので、**寸法と計算は数で**、**部品の作りは元のファイルを読んで**見張る
/// （`DesignFoundationTests` と同じやり方・注記の行は数えない）。
final class TripsDesignTests: XCTestCase {

    // MARK: - 道具

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
    }

    /// `marker` から次の `private func`・`private var`・型の宣言までを切り出す
    private func section(_ marker: String, in text: String,
                         file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = text.range(of: marker) else {
            XCTFail("「\(marker)」が無い", file: file, line: line)
            return ""
        }
        let rest = text[start.upperBound...]
        let ends = ["\n    private func ", "\n    private var ", "\n    func ",
                    "\nstruct ", "\nprivate struct ", "\nextension ", "\nenum "]
            .compactMap { rest.range(of: $0)?.lowerBound }
        return String(rest[..<(ends.min() ?? rest.endIndex)])
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

    private func photo(_ fields: [String: Any]) throws -> Photo {
        var all = fields
        all["src"] = all["src"] ?? "https://x/\(fields["id"] ?? "p").jpg"
        all["userId"] = all["userId"] ?? "owner"
        let data = try JSONSerialization.data(withJSONObject: all)
        return try JSONDecoder.api.decode(Photo.self, from: data)
    }

    private static let tripFiles = [
        "Features/Trips/TripShelf.swift", "Features/Trips/TripBookView.swift",
        "Features/Trips/TripPlansView.swift", "Features/Trips/TripPlanDetailView.swift",
        "Features/Trips/TripPlanPickSheet.swift", "Features/Trips/OfflineTripCard.swift",
        "Features/Trips/OfflineTripView.swift", "Features/Trips/OfflineSavedView.swift",
        "Features/Trips/TripParts.swift",
    ]

    // MARK: - 寸法（板の値）

    func testBoardMeasures() {
        XCTAssertEqual(TripStyle.coverCardHeight, 190)
        XCTAssertEqual(TripStyle.rowMinHeight, 72)
        XCTAssertEqual(TripStyle.rowThumb, CGSize(width: 72, height: 56))
        XCTAssertEqual(TripStyle.planThumb, 64)
        XCTAssertEqual(TripStyle.dateFieldHeight, 52)
        XCTAssertEqual(TripStyle.stopNumberSide, 24)
        XCTAssertEqual(TripStyle.pickRowMinHeight, 68)
        XCTAssertEqual(TripStyle.pickThumb, 48)
        XCTAssertEqual(TripStyle.pickMark, 26)
        XCTAssertEqual(TripStyle.progressHeight, 4)
        XCTAssertEqual(TripStyle.savedRowMinHeight, 84)
        XCTAssertEqual(TripStyle.savedThumb, 56)
        XCTAssertEqual(TripStyle.lightRowMinHeight, 36)
        XCTAssertEqual(TripStyle.disabledOpacity, 0.32, accuracy: 0.001)
        XCTAssertEqual(TripStyle.routeGround, 0x0B0C0E)
        XCTAssertEqual(TripStyle.departureWindowDays, 14)
    }

    /// 押せるもの・字の決まり（CLAUDE.md）: 押せる行は 44 以上、線は土台の値の間
    func testTapTargetsAndStrokes() {
        for height in [TripStyle.rowMinHeight, TripStyle.pickRowMinHeight, TripStyle.savedRowMinHeight,
                       TripStyle.dateFieldHeight] {
            XCTAssertGreaterThanOrEqual(height, WebTheme.minTapTarget)
        }
        XCTAssertGreaterThanOrEqual(TripStyle.stopNumberStroke, JPStroke.hairline)
        XCTAssertLessThanOrEqual(TripStyle.stopNumberStroke, JPStroke.emphasis)
    }

    // MARK: - 計算

    func testGroupedByUploadDate() throws {
        let noDate = try photo(["id": "a", "createdAt": "2026-02-10T09:00:00Z"])
        let dated = try photo(["id": "b", "date": "2026-02-10"])
        XCTAssertTrue(TripStyle.groupedByUploadDate([noDate]))
        XCTAssertFalse(TripStyle.groupedByUploadDate([noDate, dated]))
        XCTAssertFalse(TripStyle.groupedByUploadDate([]))
    }

    func testPageMetaJoinsOnlyWhatItHas() throws {
        let full = try photo(["id": "a", "date": "2026-09-12",
                              "exif": ["dateTimeOriginal": "2026:09:12 07:12:00", "focalLength": "24", "aperture": "8"]])
        XCTAssertEqual(TripStyle.pageMeta(full), "07:12 · 24mm · f/8")
        // 撮影日と食い違う時刻は出さない
        let other = try photo(["id": "b", "date": "2026-09-13",
                               "exif": ["dateTimeOriginal": "2026:09:12 07:12:00", "aperture": "f/2.8"]])
        XCTAssertEqual(TripStyle.pageMeta(other), "f/2.8")
        XCTAssertNil(TripStyle.pageMeta(try photo(["id": "c"])))
    }

    func testDepartureEyebrowOnlyForSoonTrips() {
        XCTAssertEqual(TripStyle.daysUntil(start: "2026-10-17", today: "2026-10-14"), 3)
        XCTAssertEqual(TripStyle.departureEyebrow(start: "2026-10-17", today: "2026-10-14"),
                       L("出発まで 3 日", "3 days to go"))
        XCTAssertEqual(TripStyle.departureEyebrow(start: "2026-10-14", today: "2026-10-14"),
                       L("今日出発", "Leaving today"))
        XCTAssertNil(TripStyle.departureEyebrow(start: "2026-12-24", today: "2026-10-14"), "遠い旅には出さない")
        XCTAssertNil(TripStyle.departureEyebrow(start: "2026-10-01", today: "2026-10-14"), "過ぎた日には出さない")
        XCTAssertNil(TripStyle.departureEyebrow(start: nil, today: "2026-10-14"))
        // 月をまたぐ・ちょうど 14 日
        XCTAssertNotNil(TripStyle.departureEyebrow(start: "2026-10-28", today: "2026-10-14"))
        XCTAssertNil(TripStyle.departureEyebrow(start: "2026-10-29", today: "2026-10-14"))
    }

    func testFinishedPlanLine() {
        XCTAssertTrue(TripStyle.isFinished(end: "2026-09-14", today: "2026-10-14"))
        XCTAssertFalse(TripStyle.isFinished(end: "2026-10-14", today: "2026-10-14"), "帰着の日の当日はまだ旅の中")
        XCTAssertFalse(TripStyle.isFinished(end: nil, today: "2026-10-14"))
        let line = TripStyle.planLine(start: nil, end: nil, places: 3, finished: false)
        XCTAssertEqual(line, "\(L("日付未定", "No dates yet")) · \(TripPlanText.placeCount(3))")
        XCTAssertTrue(TripStyle.planLine(start: "2026-09-12", end: "2026-09-14", places: 6, finished: true)
            .hasSuffix(L("帰着済み", "Back home")))
    }

    func testStopNumbersRunThroughTheWholePlan() {
        XCTAssertEqual(TripStyle.stopNumbers([2, 1]), [[1, 2], [3]])
        XCTAssertEqual(TripStyle.stopNumbers([0, 2, 0, 1]), [[], [1, 2], [], [3]])
        XCTAssertEqual(TripStyle.stopNumbers([]), [])
    }

    func testRemainingAndPickToggle() {
        XCTAssertEqual(TripStyle.remaining(dayCount: 3, max: 5), 2)
        XCTAssertEqual(TripStyle.remaining(dayCount: 7, max: 5), 0)
        var picked = TripPlanPickSheet.toggled([], id: "a", capacity: 2)
        picked = TripPlanPickSheet.toggled(picked, id: "b", capacity: 2)
        XCTAssertEqual(picked, ["a", "b"])
        XCTAssertEqual(TripPlanPickSheet.toggled(picked, id: "c", capacity: 2), ["a", "b"], "残りを超えて選ばない")
        XCTAssertEqual(TripPlanPickSheet.toggled(picked, id: "a", capacity: 2), ["b"], "外すのはいつでも")
        XCTAssertEqual(TripPlanPickSheet.toggled([], id: "a", capacity: 0), [])
        XCTAssertEqual(TripPlanPickSheet.addTitle(count: 3), L("3か所を追加", "Add 3 places"))
        XCTAssertEqual(TripPlanPickSheet.eyebrow(dayIndex: 0, date: "12月24日"), L("1日目 · 12月24日", "Day 1 · 12月24日"))
        XCTAssertEqual(TripPlanPickSheet.eyebrow(dayIndex: 1, date: nil), L("2日目", "Day 2"))
        XCTAssertEqual(TripPlanPickSheet.hint(capacity: 0), L("この日はいっぱいです", "This day is full"))
    }

    func testUsageAndBytes() {
        XCTAssertNil(TripStyle.usageFraction(used: 10, free: nil), "空きが読めなければ線を出さない")
        XCTAssertEqual(TripStyle.usageFraction(used: 25, free: 75) ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertNil(TripStyle.usageFraction(used: 0, free: 0))
        XCTAssertEqual(TripStyle.splitBytes("48 MB").number, "48")
        XCTAssertEqual(TripStyle.splitBytes("48 MB").unit, "MB")
        XCTAssertEqual(TripStyle.splitBytes("1.3 GB").unit, "GB")
        XCTAssertEqual(TripStyle.splitBytes("0 MB").number, "0")
    }

    /// 日の見出しの読み上げは「1日目 · 09.12」（眉の英字「DAY」を読ませない）
    func testSpokenDayHeader() {
        XCTAssertEqual(TripBookView.spokenDayHeader(1, monthDay: "09.12"), "\(TripBookView.spokenDay(1)) · 09.12")
        XCTAssertFalse(TripBookView.spokenDayHeader(2, monthDay: "09.13").contains("DAY"))
        let day = OfflineTripManifest.Day(number: 2, date: nil, stops: [])
        XCTAssertEqual(OfflineTripContent.dayHeading(day), L("2 日目", "Day 2"))
    }

    // MARK: - 旅の一覧（板 Trips）

    func testShelfUsesCoverCardThenRows() throws {
        let shelf = try source("Features/Trips/TripShelf.swift")
        let list = section("struct TripShelfList", in: shelf)
        assertInOrder(["if index == 0 {", "TripShelf(trip: trip)", "} else {", "TripShelfRow(trip: trip)"],
                      in: list, "最新の一冊だけ表紙の札、残りは行")
        XCTAssertTrue(list.contains(".accessibilityIdentifier(\"trips.book\")"), "画面写真で探す名前")
        XCTAssertTrue(list.contains("EmptyState(title:"), "0 冊は空の状態の部品")
        let card = section("struct TripShelf:", in: shelf)
        XCTAssertTrue(card.contains("TripStyle.coverCardHeight"))
        XCTAssertTrue(card.contains("JPRadius.l"))
        // 写真の上に真鍮を置かない（CLAUDE.md）
        XCTAssertFalse(card.contains("WebTheme.accent"), "表紙の札（写真の上）に真鍮がある")
        let row = section("struct TripShelfRow", in: shelf)
        XCTAssertTrue(row.contains("JPFont.rowTitle"), "行の題は明朝の下限 18")
        XCTAssertTrue(row.contains("TripStyle.rowThumb"))
    }

    // MARK: - 旅の一冊・共有（板 TripBook・TripBookShare）

    func testBookShareIsTheBottomWhiteButton() throws {
        let book = try source("Features/Trips/TripBookView.swift")
        let body = section("var body: some View {", in: book)
        XCTAssertFalse(body.contains(".toolbar"), "共有が右上の印に戻っている（下端に一本化）")
        assertInOrder([".safeAreaInset(edge: .bottom)", "TripBook.canShare(book, isMine: isMine)", "shareButton.jpBottomBar()"],
                      in: body, "下端の共有")
        let label = section("private var shareLabel", in: book)
        XCTAssertTrue(label.contains(".jpPillButton(.main(onPhoto: true))"), "写真のある画面の主ボタンは白")
        XCTAssertEqual(TripBookView.shareTitle, L("この一冊を送る", "Send this trip book"))
    }

    func testBookCoverStatsRouteAndDays() throws {
        let book = try source("Features/Trips/TripBookView.swift")
        let cover = section("private var cover: some View {", in: book)
        XCTAssertTrue(cover.contains("JPFont.photoTitle"), "表紙の題は字の段の Display")
        XCTAssertFalse(cover.contains("WebTheme.accent"), "表紙（写真の上）に真鍮がある")
        let stats = section("private func statCell(", in: book)
        XCTAssertTrue(stats.contains("JPFont.figureLarge"), "数は細い大きな数字")
        XCTAssertFalse(book.contains("dash:"), "たどった場所の線が点線に戻っている")
        XCTAssertTrue(book.contains("JPEyebrowLine(L(\"たどった場所\""))
        let header = section("private func dayHeader(", in: book)
        // 形は共通の節の見出し（眉 → 明朝 22。2026-10-14: ここだけ間が 4 だった）
        assertInOrder(["JPSectionHeading(eyebrow: \"DAY", "spoken: Self.spokenDayHeader(",
                       "title: day.place.isEmpty ? nil : LocationMatch.display(day.place)"], in: header, "日の見出しは眉 → 明朝の地名")
        let page = section("private func page(", in: book)
        assertInOrder(["pageImage(photo)", ".padding(.horizontal, -JPSpace.xs)", "JPFont.rowTitle",
                       "TripStyle.pageMeta(photo)"], in: page, "ページの写真 → 題 → 撮影時刻と設定")
        XCTAssertTrue(book.contains(".accessibilityIdentifier(\"trips.route\")"))
        XCTAssertTrue(book.contains(".accessibilityIdentifier(\"trips.stats\")"))
    }

    // MARK: - 旅行プラン（板 TripPlans・TripPlanDays・TripPlanPick）

    func testPlansListFollowsTheBoard() throws {
        let plans = try source("Features/Trips/TripPlansView.swift")
        let create = section("private var createRow: some View {", in: plans)
        assertInOrder(["JPHeight.field", "WebTheme.sheet", "JPPillStyle.main(onPhoto: false).fill",
                       ".opacity(canCreate ? 1 : TripStyle.disabledOpacity)", "題を入れると「作る」が押せます"],
                      in: create, "作る口")
        XCTAssertTrue(plans.contains("ErrorBanner(message: L(\"旅行プランを読み込めませんでした。\""), "読めなかったのは状態の部品")
        XCTAssertTrue(plans.contains("EmptyState(title: L(\"旅行プランはまだありません\""))
        XCTAssertTrue(plans.contains("JPLoadingState(kind: .rows)"))
        let card = section("private func card(_ plan: TripPlan)", in: plans)
        assertInOrder(["TripStyle.departureEyebrow(", ".jpEyebrow()", "WebTheme.accent", "JPFont.rowTitle",
                       "TripStyle.planLine("], in: card, "プランの札")
        XCTAssertFalse(plans.contains("WebTheme.surface,"), "白 7% の古い札の地が残っている")
        for id in ["\"trips.pickByPhoto\"", "\"trips.plan\""] {
            XCTAssertTrue(plans.contains(id), "画面写真で探す名前 \(id)")
        }
    }

    func testPlanDaysFollowTheBoard() throws {
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        let day = section("private func daySection(", in: detail)
        assertInOrder(["JPEyebrowLine(dayHeading(di, day))", "itemRow(di, ii, item, number:", "addRow(di,"],
                      in: day, "日の見出し → 項目 → 追加")
        XCTAssertFalse(day.contains("WebTheme.surface"), "日の札で囲んでいる（v2 は区切り線の行）")
        let label = section("private func itemLabel(", in: detail)
        assertInOrder(["TripStopNumber(number: number)", "isSpot ? JPFont.rowTitle : JPFont.bodyEmphasis"],
                      in: label, "番号の丸 → 名前")
        let add = section("private func addRow(", in: detail)
        XCTAssertTrue(add.contains(".foregroundStyle(WebTheme.accent)"), "追加は真鍮の字")
        let date = section("private func dateField(", in: detail)
        XCTAssertTrue(date.contains("TripStyle.dateFieldHeight"))
        let delete = section("private func deleteCard(", in: detail)
        assertInOrder([".foregroundStyle(WebTheme.danger)", "TripOutlineButton(title: L(\"削除する\", \"Delete\"), strong: true"],
                      in: delete, "削除は危険の色の行 → 確かめ")
        XCTAssertTrue(detail.contains("TripOutlineButton(title: L(\"削除する\", \"Remove\"), strong: true"), "日の削除の確かめ")
        XCTAssertFalse(detail.contains("Color.white.opacity(0.18)"), "v1 の白 18% の線が残っている")
        XCTAssertTrue(detail.contains("capacity: TripStyle.remaining("), "候補のシートに残りの数を渡す")
    }

    func testPickSheetIsMultiSelect() throws {
        let pick = try source("Features/Trips/TripPlanPickSheet.swift")
        let row = section("private func row(", in: pick)
        assertInOrder(["selected = Self.toggled(selected, id: choice.id, capacity: capacity)", "PickMark(isOn: isOn)",
                       ".disabled(locked)", ".accessibilityAddTraits(isOn ? .isSelected : [])"],
                      in: row, "選ぶ・外す")
        XCTAssertFalse(row.contains("dismiss()"), "1つ押すたびに閉じている（v2 は選んでからまとめて足す）")
        let body = section("var body: some View {", in: pick)
        assertInOrder([".safeAreaInset(edge: .bottom)", "Self.addTitle(count: selected.count)",
                       ".jpPillButton(.main(onPhoto: false))", ".jpBottomBar()"], in: body, "下の主ボタン")
        let mark = section("private struct PickMark", in: pick)
        assertInOrder(["Circle().fill(WebTheme.accent)", "WebTheme.accentText"], in: mark, "選んだ印は真鍮に墨のチェック")
    }

    // MARK: - 電波なしで使う（板 OfflineTripSave・OfflineSaveStates・OfflineTrip・OfflineSpot・OfflineSaved）

    func testOfflineCardStates() throws {
        let card = try source("Features/Trips/OfflineTripCard.swift")
        XCTAssertTrue(card.contains(".offlineCardFace()"))
        XCTAssertTrue(section("func offlineCardFace()", in: card).contains(".jpCardFace()"), "札の地は共通の surface-1 の札")
        let interrupted = section("private func interrupted(", in: card)
        XCTAssertTrue(interrupted.contains("OfflineProgressBar(done: p.done, total: p.total, stalled: true)"), "止まった棒は真鍮 50%")
        let saved = section("private func saved(", in: card)
        assertInOrder([".foregroundStyle(WebTheme.accent)", "WebTheme.accentSoft",
                       "TripOutlineButton(title: L(\"端末から削除\", \"Remove from iPhone\"), danger: true)"],
                      in: saved, "プランが変わった知らせは真鍮 8% の帯")
        let confirm = section("private func deleteConfirm(", in: card)
        XCTAssertTrue(confirm.contains("TripOutlineButton(title: L(\"削除する\", \"Remove\"), strong: true)"))
        let primary = section("private func primaryButton(", in: card)
        XCTAssertTrue(primary.contains(".jpPillButton(.main(onPhoto: false))"), "写真の無い札の主ボタンは真鍮")
        XCTAssertFalse(card.contains("WebTheme.surface"))
        // 進みの線（板 4pt・白 10%）
        let parts = try source("Features/Trips/TripParts.swift")
        let bar = section("struct OfflineProgressBar", in: parts)
        assertInOrder(["TripStyle.progressTrackOpacity", "TripStyle.stalledProgressOpacity", "TripStyle.progressHeight"],
                      in: bar, "進みの線")
        let button = section("struct TripOutlineButton", in: parts)
        XCTAssertTrue(button.contains(".jpOutlineButton(.regular, tone: strong ? .strong : danger ? .danger : .plain, fullWidth: fill)"),
                      "旅の線の小ボタンが土台の線の小ボタンでない")
        XCTAssertFalse(button.contains("strokeBorder("), "線の小ボタンの縁を画面に書き直している")
    }

    func testOfflineTripAndSpot() throws {
        let view = try source("Features/Trips/OfflineTripView.swift")
        XCTAssertTrue(section("struct OfflineStopNumber", in: view).contains("TripStopNumber(number: number)"),
                      "圏外の番号の丸は旅行プランと同じ部品")
        let banner = section("struct OfflineBanner", in: view)
        XCTAssertTrue(banner.contains("WebTheme.card"))
        XCTAssertFalse(banner.contains("accentSoft"), "圏外の帯が v1 の真鍮の地のまま")
        let row = section("private func row(", in: view)
        assertInOrder(["OfflineStopNumber(number: stop.number)", "JPFont.rowTitle", "JPHeight.tallRow"], in: row, "圏外の行")
        XCTAssertTrue(view.contains("JPEyebrowLine(Self.dayHeading(day))"))
        XCTAssertTrue(view.contains("JPEyebrowLine(lightHeading)"))
        let maps = section("private func mapsButton(", in: view)
        XCTAssertTrue(maps.contains(".jpPillButton(.main(onPhoto: true))"), "写真のある画面の主ボタンは白")
        let light = section("private var lightSection", in: view)
        XCTAssertTrue(light.contains("TripStyle.lightRowMinHeight"))
    }

    func testOfflineSavedList() throws {
        let saved = try source("Features/Trips/OfflineSavedView.swift")
        let usage = section("private var usageCard", in: saved)
        assertInOrder(["TripStyle.splitBytes(", "JPFont.figureLarge", "TripStyle.usageFraction(", "WebTheme.accent"],
                      in: usage, "使っている容量")
        let row = section("private func row(", in: saved)
        assertInOrder(["TripStyle.savedThumb", "JPFont.rowTitle", "TripStyle.savedRowMinHeight",
                       ".foregroundStyle(WebTheme.danger)"], in: row, "保存した旅の行")
        XCTAssertTrue(saved.contains(".accessibilityIdentifier(\"settings.offlineTrips\")"))
    }

    // MARK: - 全体の決まり

    /// 系統の赤・11pt 未満の固定の字・v1 の白 7% の札を、作り替えた画面に戻さない
    func testNoSystemRedOrTinyText() throws {
        for path in Self.tripFiles {
            let text = try source(path)
            XCTAssertFalse(text.contains("Color.red") || text.contains("(.red)"), "\(path) に系統の赤")
            for tiny in ["size: 9", "size: 10,", "size: 11", ".caption2)"] {
                XCTAssertFalse(text.contains(".font(.system(\(tiny)") || text.contains(".font(\(tiny)"),
                               "\(path) に 12pt 未満の字（\(tiny)）")
            }
        }
    }
}

/// 🔴 オフラインの札に緑を入れない（画面の色は白・黒・真鍮・危険の色だけ・2026-10-14 判断）
final class OfflineCardColorTests: XCTestCase {
    func testNoGreenOnOfflineCard() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Trips/OfflineTripCard.swift"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("WebTheme.success"), "オフラインの札に緑が入っている")
    }
}

/// 旅の記録の国名の行は 12pt で 4.5:1 を保つ（白 42% では約 3.9:1）
final class TravelRecordContrastTests: XCTestCase {
    func testCountriesLineUsesText3() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Profile/TravelRecordView.swift"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("faint.opacity(0.7)"))
    }
}
