import XCTest
@testable import JourneyPhoto

/// 旅行プラン作りの案 A の第 1 段（2026-11-10・札 #521）。
///
/// 固定したいのは:
///  1. 作る流れは1つの割り振り（地域で束ねる → 近い順 → 日へ）。撮影地も同じ下書きに入る。日付の押し方と期間の言い方
///  2. 日の中は時間帯の順（案内の無い所は動かさない）・重なりの1行・日の出と日の入り
///  3. 運ぶ印で運ぶ・自動保存の決まり（送る・止める・戻る）・季節の一文
///  4. 移動の見込み（手段の決め方・返った手段だけ・言い方・間に合わないとき・出る時刻の目安・地図のアプリへ）
///  5. どの頁からも入れる・地図の番号は通し番号・帰着済みの札の旅の一冊
final class TripPlanStage1Tests: XCTestCase {

    private func spot(_ slug: String, prefecture: String = "石川県", lat: Double? = nil, lng: Double? = nil,
                      times: [String] = [], seasons: [(String, String)] = []) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"sp_\(slug)\"", "\"slug\":\"\(slug)\"", "\"name\":\"\(slug)\"", "\"stage\":\"published\"",
                      "\"region\":{\"prefecture\":\"\(prefecture)\"}"]
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        if !times.isEmpty {
            fields.append("\"timeOfDayGuide\":[" + times.map { "{\"time\":\"\($0)\",\"text\":\"t\"}" }.joined(separator: ",") + "]")
        }
        if !seasons.isEmpty {
            fields.append("\"seasonalGuide\":[" + seasons.map { "{\"season\":\"\($0.0)\",\"text\":\"\($0.1)\"}" }
                .joined(separator: ",") + "]")
        }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func location(_ slug: String, lat: Double, lng: Double) -> DerivedSpot.Place {
        DerivedSpot.Place(label: slug, slug: slug, photos: [], broader: [], categories: [],
                          coords: Photo.Coords(lat: lat, lng: lng))
    }

    private func names(_ days: [[TripDraft.Place]]) -> [[String]] { days.map { $0.map(\.name) } }

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    // MARK: - 1. 作る流れ

    /// 撮影スポットと撮影地が同じ規則で日に割れる（地域を混ぜない・撮影地は1か所ずつ別の地域）
    func testPlanUsesOneAllocationForSpotsAndLocations() throws {
        let higashi = TripDraft.place(spot: try spot("higashi", lat: 36.57, lng: 136.67))
        let castle = TripDraft.place(spot: try spot("castle", lat: 36.56, lng: 136.66))
        let yoko = TripDraft.place(spot: try spot("yoko", prefecture: "福井県", lat: 36.06, lng: 136.22))
        let echizen = TripDraft.place(spot: try spot("echizen", prefecture: "福井県", lat: 35.98, lng: 135.96))
        let beach = TripDraft.place(location: location("beach", lat: 36.90, lng: 136.77))
        let days = TripDraft.plan([higashi, yoko, castle, beach, echizen], dayCount: 2)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(Set(days.flatMap { $0.map(\.name) }), ["higashi", "castle", "yoko", "echizen", "beach"],
                       "場所を落とさない")
        XCTAssertEqual(days[0].first?.name, "higashi", "最初に選んだ場所の地域から始める")
        // 写真から選ぶ（撮影スポットだけ）の割り振りと同じ答え
        let spots = try [spot("a", lat: 35.0, lng: 135.7), spot("b", lat: 35.01, lng: 135.71),
                         spot("c", prefecture: "奈良県", lat: 34.68, lng: 135.80)]
        XCTAssertEqual(TripDraft.plan(spots.map(TripDraft.place(spot:)), dayCount: nil).map { $0.map(\.name) },
                       TripPicker.days(TripPicker.grouped(spots), dayCount: nil).map { $0.map(\.slug) })
    }

    /// 暦: 1つ目で出発、2つ目で帰着。前の日を押したら出発を選び直す。両方の後はそこから選び直す
    func testCalendarTapsPickStartThenEnd() {
        var r = TripDraft.tap(start: nil, end: nil, day: "2026-12-24")
        XCTAssertEqual(r.start, "2026-12-24"); XCTAssertNil(r.end)
        r = TripDraft.tap(start: r.start, end: r.end, day: "2026-12-25")
        XCTAssertEqual(r.end, "2026-12-25")
        r = TripDraft.tap(start: r.start, end: r.end, day: "2026-12-30")
        XCTAssertEqual(r.start, "2026-12-30"); XCTAssertNil(r.end, "両方決まった後は選び直す")
        r = TripDraft.tap(start: r.start, end: r.end, day: "2026-12-28")
        XCTAssertEqual(r.start, "2026-12-28"); XCTAssertNil(r.end, "出発より前は出発を選び直す")
        r = TripDraft.tap(start: "2026-12-24", end: nil, day: "2026-12-24")
        XCTAssertEqual(r.end, "2026-12-24", "同じ日を2度で日帰り")
    }

    func testRangeLineSaysNightsAndDays() {
        XCTAssertEqual(TripDraft.rangeLine(start: "2026-12-24", end: "2026-12-25"), "12月24日（木）〜 25日（金）\u{2002}1 泊 2 日")
        XCTAssertEqual(TripDraft.rangeLine(start: "2026-12-24", end: nil), "12月24日（木）\u{2002}日帰り")
        XCTAssertEqual(TripDraft.rangeLine(start: "2026-12-31", end: "2027-01-02"), "12月31日（木）〜 1月2日（土）\u{2002}2 泊 3 日")
        XCTAssertNil(TripDraft.rangeLine(start: nil, end: nil))
        XCTAssertEqual(TripDraft.allocationNote(places: 5, days: 2), "5 か所を 2 日に割り振ります。日付は後から変えられます。")
    }

    func testMonthGridStartsOnSunday() {
        // 2026年12月1日は火曜 → 前に2つの空き
        let grid = TripDraft.monthGrid(year: 2026, month: 12)
        XCTAssertEqual(grid.prefix(3).map { $0 }, [nil, nil, "2026-12-01"])
        XCTAssertEqual(grid.compactMap { $0 }.count, 31)
        XCTAssertEqual(TripDraft.shiftMonth(year: 2026, month: 12, by: 1).year, 2027)
        XCTAssertEqual(TripDraft.shiftMonth(year: 2026, month: 1, by: -1).month, 12)
    }

    /// 作る流れの状態: 選ぶ・外す・上限・日付を決めない日数・送る日付
    @MainActor
    func testCreateModelSelectsAndPlans() async throws {
        let a = TripDraft.place(spot: try spot("a", lat: 36.5, lng: 136.6))
        let b = TripDraft.place(spot: try spot("b", lat: 36.51, lng: 136.61))
        let model = TripCreateModel(initial: [a])
        XCTAssertEqual(model.count, 1)
        XCTAssertTrue(model.toggle(b))
        XCTAssertEqual(model.picked.map(\.name), ["a", "b"])
        XCTAssertTrue(model.toggle(a), "押し直すと外れる")
        XCTAssertEqual(model.picked.map(\.name), ["b"])
        XCTAssertFalse(model.datesReady, "日付も日数も無いと下書きへ進めない")
        model.start = "2026-12-24"
        XCTAssertTrue(model.datesReady)
        XCTAssertEqual(model.sendDates.end, "2026-12-24", "帰着がまだなら日帰り")
        model.undated = true
        model.dayCount = 3
        XCTAssertEqual(model.days.count, 3)
        XCTAssertNil(model.sendDates.start, "日付を決めないときは送らない")
        XCTAssertEqual(TripCreatePickStep.nextTitle(count: 5), "5 か所で次へ")
    }

    /// 一覧の主ボタンは1つ（題から作る欄・写真から選ぶ入口は作る流れの中へ）
    func testListHasOneCreateButton() throws {
        let list = try source("Features/Trips/TripPlansView.swift")
        XCTAssertTrue(list.contains("TripCreateView(plans: model)"))
        XCTAssertTrue(list.contains("\"trips.create\""))
        XCTAssertFalse(list.contains("TextField(L(\"例: 冬のフィンランド\""), "空のプランを作る題の欄が残っている")
        XCTAssertFalse(list.contains("TripPickerView("), "写真から選ぶは作る流れのタブへ移した")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/JourneyPhoto/Features/Trips/TripPickerDraftView.swift").path),
                       "写真から選ぶ専用の下書きは作る流れの下書きに置き換えた")
        let map = try source("Features/Profile/SavedSpotsMapView.swift")
        XCTAssertTrue(map.contains("TripCreateView(plans: plans, initial: SavedSpotsTrip.draftPlaces(selectedItems), startAtDates: true)"),
                      "行きたい場所の地図からも同じ流れ（日付の段から）")
    }

    // MARK: - 2. 日の中の並び

    /// 時間帯の案内の順。案内の無い所は近い順の位置のまま
    func testDayIsOrderedByTimeKeepingUnguidedPlaces() throws {
        let sunset = TripDraft.place(spot: try spot("sunset", times: ["goldenHour"]))
        let none1 = TripDraft.place(spot: try spot("none1"))
        let dawn = TripDraft.place(spot: try spot("dawn", times: ["morning", "dawn"]))
        let night = TripDraft.place(spot: try spot("night", times: ["night"]))
        let none2 = TripDraft.place(spot: try spot("none2"))
        let day = TripDraft.timeOrdered([sunset, none1, night, dawn, none2])
        XCTAssertEqual(day.map(\.name), ["dawn", "none1", "sunset", "night", "none2"])
        XCTAssertEqual(TripDraft.primaryTime(["night", "morning"]), "morning")
        XCTAssertNil(TripDraft.primaryTime([]))
    }

    /// 短い時間帯（夜明け・夕方の斜光・日没後）が同じ日に2つ以上なら1行。朝が重なっても言わない
    func testOverlapNoteOnlyForShortWindows() {
        XCTAssertEqual(TripDraft.overlapNote([["goldenHour"], ["goldenHour"], ["morning"]]),
                       "夕方の斜光が 2 か所あります。1 日では回りきれないかもしれません")
        XCTAssertNil(TripDraft.overlapNote([["morning"], ["morning"]]))
        XCTAssertNil(TripDraft.overlapNote([["morning", "goldenHour"], ["goldenHour"]]),
                     "並べるときの時間帯（いちばん早いもの）で数える")
        XCTAssertEqual(TripDraft.timeChip(["morning", "dawn", "night"]), "夜明け\u{2002}朝")
        XCTAssertNil(TripDraft.timeChip([]))
    }

    /// 日の出・日の入りは最初の撮影スポット（座標のあるもの）で、その土地の時計
    func testSunUsesFirstLocatedSpot() throws {
        let noCoords = try spot("x")
        let kanazawa = try spot("k", lat: 36.56, lng: 136.66)
        let sun = try XCTUnwrap(TripDraft.sun(ymd: "2026-12-24", spots: [noCoords, kanazawa]))
        XCTAssertEqual(sun.zone.identifier, "Asia/Tokyo")
        XCTAssertEqual(sun.sunrise?.prefix(2), "07")
        XCTAssertEqual(sun.sunset?.prefix(2), "16")
        XCTAssertNil(TripDraft.sun(ymd: nil, spots: [kanazawa]), "日付が無ければ出さない")
        XCTAssertNil(TripDraft.sun(ymd: "2026-12-24", spots: [noCoords]))
    }

    // MARK: - 3. 日程の画面

    private func days(_ counts: [Int]) -> [TripDay] {
        var n = 0
        return counts.map { c in TripDay(items: (0..<c).map { _ in n += 1; return .spot(spotId: "s\(n)", note: nil) }) }
    }

    private func ids(_ days: [TripDay]) -> [[String]] {
        days.map { $0.items.map { if case .spot(let id, _) = $0 { return id } else { return "?" } } }
    }

    /// 運ぶ: 同じ日で下へは落とした行の下・上へは上・別の日へは落とした行の上・末尾へも
    func testDropMovesWithinAndAcrossDays() throws {
        let start = days([3, 2])   // [s1 s2 s3] [s4 s5]
        let s1 = TripPlanEdit.dragPayload(day: 0, item: 0, of: .spot(spotId: "s1", note: nil))
        // 🔴 確かめ役の指摘（2026-11-10）: 落とす先の印（真鍮の線）は行の**上**に出るのに、同じ日で下へ運ぶと
        // 行の**下**に入り、1つずれていた。どの向きでも「落とした行の上」に入れる（末尾へはその日の追加の行へ）
        XCTAssertEqual(ids(try XCTUnwrap(TripPlanEdit.dropped(start, payload: s1, toDay: 0, toItem: 2))),
                       [["s2", "s1", "s3"], ["s4", "s5"]], "下へも落とした行の上（線と同じ位置）")
        let s3 = TripPlanEdit.dragPayload(day: 0, item: 2, of: .spot(spotId: "s3", note: nil))
        XCTAssertEqual(ids(try XCTUnwrap(TripPlanEdit.dropped(start, payload: s3, toDay: 0, toItem: 0))),
                       [["s3", "s1", "s2"], ["s4", "s5"]], "上へは落とした行の上")
        XCTAssertEqual(ids(try XCTUnwrap(TripPlanEdit.dropped(start, payload: s1, toDay: 1, toItem: 1))),
                       [["s2", "s3"], ["s4", "s1", "s5"]], "別の日へ")
        XCTAssertEqual(ids(try XCTUnwrap(TripPlanEdit.dropped(start, payload: s1, toDay: 1, toItem: nil))),
                       [["s2", "s3"], ["s4", "s5", "s1"]], "その日の末尾")
        XCTAssertNil(TripPlanEdit.dropped(start, payload: s1, toDay: 0, toItem: 0), "動かない")
        XCTAssertNil(TripPlanEdit.dropped(start, payload: "x|0|0|spot:s1", toDay: 1, toItem: 0), "読めない中身")
        // 運んでいる間に日程が差し替わった: 位置がずれても同じ項目を探し直す
        let shifted = [TripDay(items: [.spot(spotId: "s9", note: nil)] + start[0].items), start[1]]
        XCTAssertEqual(ids(try XCTUnwrap(TripPlanEdit.dropped(shifted, payload: s1, toDay: 1, toItem: 0))),
                       [["s9", "s2", "s3"], ["s1", "s4", "s5"]])
        // いっぱいの日へは運べない
        let full = [TripDay(items: [.spot(spotId: "a", note: nil)]), days([TripPlanService.itemsPerDayMax])[0]]
        let a = TripPlanEdit.dragPayload(day: 0, item: 0, of: .spot(spotId: "a", note: nil))
        XCTAssertNil(TripPlanEdit.dropped(full, payload: a, toDay: 1, toItem: 0))
    }

    /// 自動保存: 戻るとき（送れるなら送ってから・送れないなら確かめ・送っている間は待つ）
    func testAutosaveLeave() {
        XCTAssertEqual(TripAutosave.leave(dirty: false, sending: false, problem: nil, offline: false), .now)
        XCTAssertEqual(TripAutosave.leave(dirty: true, sending: false, problem: nil, offline: false), .sendThenLeave)
        XCTAssertEqual(TripAutosave.leave(dirty: true, sending: false, problem: nil, offline: true), .confirm)
        XCTAssertEqual(TripAutosave.leave(dirty: true, sending: false, problem: .failed("x"), offline: false), .confirm)
        XCTAssertEqual(TripAutosave.leave(dirty: true, sending: true, problem: nil, offline: false), .wait)
        XCTAssertEqual(TripAutosave.unsaved(.sendThenLeave), .confirm, "自前の戻るを出す")
        XCTAssertEqual(TripAutosave.unsaved(.now), .now)
        XCTAssertFalse(TripAutosave.shouldSend(dirty: true, busy: false, problem: .conflict), "別の端末の変更があれば止める")
        XCTAssertTrue(TripAutosave.shouldSend(dirty: true, busy: false, problem: .offline))
        XCTAssertFalse(TripAutosave.shouldSend(dirty: true, busy: true, problem: nil))
        XCTAssertEqual(TripAutosave.standardDelayNanoseconds, 2_000_000_000, "打つたびに送らない（止まってから 2 秒）")
        XCTAssertEqual(TripAutosave.delayNanoseconds, TripAutosave.standardDelayNanoseconds, "見本でなければ 2 秒")
    }

    /// 送る前の読み直し: 版（updatedAt）が違えば止める・消されていても止める
    func testAutosaveConflict() {
        let base = TripPlan(planId: "p", title: "t", updatedAt: "2026-11-10T00:00:00Z")
        XCTAssertFalse(TripAutosave.conflicted(base: base, server: base))
        XCTAssertTrue(TripAutosave.conflicted(base: base, server: TripPlan(planId: "p", title: "t", updatedAt: "2026-11-10T01:00:00Z")))
        XCTAssertTrue(TripAutosave.conflicted(base: base, server: nil))
        XCTAssertNotNil(TripAutosave.banner(.offline, dirty: true))
        XCTAssertNil(TripAutosave.banner(.offline, dirty: false), "送れていない直しが無ければ出さない")
        XCTAssertNotNil(TripAutosave.banner(.conflict, dirty: false))
        XCTAssertEqual(TripAutosave.status(sending: false, problem: nil), "変更は自動で保存されます")
    }

    /// 画面: 右上の「保存」は無い・運ぶ印・日の削除は「…」の中
    func testDetailWiresAutosaveAndDrag() throws {
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        XCTAssertFalse(detail.contains("private var saveButton"), "右上の保存が残っている")
        XCTAssertTrue(detail.contains(".onChange(of: draft) { _, _ in scheduleAutosave() }"))
        XCTAssertTrue(detail.contains("autosave.schedule { _ = await flush() }"), "手を止めてから待って送る（TripAutosaveDebouncer）")
        XCTAssertTrue(detail.contains(".draggable(TripPlanEdit.dragPayload(day: di, item: ii, of: item))"))
        XCTAssertTrue(detail.contains("TripPlanEdit.dropped(days, payload: payload, toDay: toDay, toItem: toItem)"))
        XCTAssertTrue(detail.contains("Label(L(\"この日を削除\", \"Remove this day\"), systemImage: \"trash\")"))
        XCTAssertTrue(detail.contains("model.fetchFresh(environment: environment)"), "送る前に読み直す")
    }

    /// 季節の一文: その日の月の季節の案内があるときだけ
    func testSeasonLineFromTheDayMonth() throws {
        let s = try spot("k", seasons: [("winter", "雪吊りの庭"), ("spring", "桜")])
        XCTAssertEqual(TripDraft.seasonLine(s, ymd: "2026-12-24"), "冬（12月）\u{2002}雪吊りの庭")
        XCTAssertEqual(TripDraft.seasonLine(s, ymd: "2027-04-02"), "春（4月）\u{2002}桜")
        XCTAssertNil(TripDraft.seasonLine(s, ymd: "2026-08-01"), "夏の案内は無い")
        XCTAssertNil(TripDraft.seasonLine(s, ymd: nil), "日付の無いプランには出さない")
    }

    // MARK: - 4. 移動の見込み

    private func leg(_ from: (Double, Double), _ to: (Double, Double)) -> TripTravel.Leg {
        TripTravel.Leg(from: .init(name: "A", coords: Photo.Coords(lat: from.0, lng: from.1), number: 1),
                       to: .init(name: "B", coords: Photo.Coords(lat: to.0, lng: to.1), number: 2))
    }

    /// 近ければ歩きを先に・遠ければ車を先に。公共交通が使えなければ車と歩き
    func testModesByDistance() {
        let near = leg((36.5781, 136.6479), (36.5700, 136.6560))   // 約 1.1km
        let far = leg((36.5781, 136.6479), (36.2376, 136.1260))    // 約 60km
        XCTAssertEqual(TripTravel.modes(for: near, transitAvailable: true), [.walking, .automobile])
        XCTAssertEqual(TripTravel.modes(for: far, transitAvailable: true), [.automobile, .transit])
        XCTAssertEqual(TripTravel.modes(for: far, transitAvailable: false), [.automobile, .walking])
    }

    /// 返った手段だけ（最大2つ）・遠い区間の長い歩きは出さない
    func testShownOnlyReturnedModes() {
        XCTAssertEqual(TripTravel.shown([.automobile, .transit], results: [.automobile: 3000]).map(\.mode), [.automobile])
        XCTAssertEqual(TripTravel.shown([.automobile, .transit], results: [:]), [])
        XCTAssertEqual(TripTravel.shown([.automobile, .walking], results: [.automobile: 3000, .walking: 6 * 3600]).map(\.mode),
                       [.automobile], "遠い区間の6時間の歩きは並べない")
        XCTAssertEqual(TripTravel.shown([.walking, .automobile], results: [.walking: 900, .automobile: 360]).map(\.mode),
                       [.walking, .automobile])
    }

    func testDurationWords() {
        XCTAssertEqual(TripTravel.duration(900), "約 15 分")
        XCTAssertEqual(TripTravel.duration(20), "約 1 分")
        XCTAssertEqual(TripTravel.duration(80 * 60), "約 1 時間 20 分")
        XCTAssertEqual(TripTravel.duration(127 * 60), "約 2 時間 10 分")
        XCTAssertEqual(TripTravel.duration(118 * 60), "約 2 時間")
    }

    /// 区間: 座標の無い場所は飛ばす・番号は通し番号のまま
    func testLegsSkipUnlocatedStops() {
        let legs = TripTravel.legs([.init("a", Photo.Coords(lat: 1, lng: 1), 4), .init("b", nil, 5), .init("c", Photo.Coords(lat: 1.1, lng: 1), 6)])
        XCTAssertEqual(legs.count, 1)
        XCTAssertEqual(legs[0].from.number, 4)
        XCTAssertEqual(legs[0].to.number, 6)
        XCTAssertEqual(legs[0].key, leg((1, 1), (1.1, 1)).key, "同じ座標の区間は同じ控え")
    }

    /// 間に合わないとき: 移動の合計が昼の長さの半分以上、または夕方の場所に日の入りまでに着けない
    func testDayWarning() throws {
        let rise = Date(timeIntervalSince1970: 0)
        let sun = TripDraft.Sun(sunrise: "07:00", sunset: "17:00", sunriseDate: rise,
                                sunsetDate: rise.addingTimeInterval(10 * 3600), zone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertNil(TripTravel.dayWarning(travel: [3600, 1800], lateNames: [nil, nil], sun: sun))
        let long = try XCTUnwrap(TripTravel.dayWarning(travel: [3 * 3600, 2 * 3600], lateNames: [nil, nil], sun: sun))
        XCTAssertTrue(long.hasPrefix("移動だけで約 5 時間"))
        let late = try XCTUnwrap(TripTravel.dayWarning(travel: [4 * 3600, 7 * 3600], lateNames: [nil, "越前岬"], sun: sun))
        XCTAssertTrue(late.contains("越前岬は夕方の案内があり、日の入りに間に合わないかもしれません"))
        XCTAssertNil(TripTravel.dayWarning(travel: [nil, nil], lateNames: [nil, nil], sun: sun), "見込みが無ければ言わない")
        XCTAssertNil(TripTravel.dayWarning(travel: [9 * 3600], lateNames: [nil], sun: nil), "日の入りが分からなければ言わない")
    }

    /// 出る時刻の目安: 日の入り（夕方の斜光の案内なら、その始まり）から見込みを引き、30分の単位で早めに
    func testDepartureHint() throws {
        let zone = TimeZone(identifier: "Asia/Tokyo")!
        var c = Calendar(identifier: .gregorian); c.timeZone = zone
        let day = c.date(from: DateComponents(year: 2026, month: 12, day: 25))!
        let sun = TripDraft.Sun(sunrise: "07:02", sunset: "16:47", sunriseDate: day.addingTimeInterval(7 * 3600 + 120),
                                sunsetDate: day.addingTimeInterval(16 * 3600 + 47 * 60),
                                goldenStart: day.addingTimeInterval(16 * 3600), zone: zone)
        let plain = try XCTUnwrap(TripTravel.departureHint(travelSeconds: 2 * 3600, destinationTimes: [], sun: sun))
        XCTAssertEqual(plain.text, "14:30 ごろに出ると、日の入り 16:47 の前に着く見込み")
        XCTAssertEqual(plain.clock, "14:30")
        let evening = try XCTUnwrap(TripTravel.departureHint(travelSeconds: 2 * 3600, destinationTimes: ["goldenHour"], sun: sun))
        XCTAssertEqual(evening.text, "14:00 ごろに出ると、夕方の斜光（16:00〜）に間に合う見込み")
        let tooFar = try XCTUnwrap(TripTravel.departureHint(travelSeconds: 11 * 3600, destinationTimes: [], sun: sun))
        XCTAssertNil(tooFar.clock)
        XCTAssertNil(TripTravel.departureHint(travelSeconds: 3600, destinationTimes: [], sun: nil))
        // 前の場所の時間帯: 夕方の斜光（16:00〜）を見てから 14:30 に出るのは無理 → 一言添える。朝の場所なら添えない
        let afterEvening = try XCTUnwrap(TripTravel.departureHint(travelSeconds: 2 * 3600, destinationTimes: [], sun: sun,
                                                                  previous: ("金沢城公園", ["morning", "goldenHour"])))
        XCTAssertEqual(afterEvening.caution, "金沢城公園の夕方の斜光を見てからだと、間に合わない見込みです")
        let afterMorning = try XCTUnwrap(TripTravel.departureHint(travelSeconds: 2 * 3600, destinationTimes: [], sun: sun,
                                                                  previous: ("ひがし茶屋街", ["dawn", "morning"])))
        XCTAssertNil(afterMorning.caution)
    }

    /// 地図のアプリへ: Google は鍵の要らない Maps URLs・手段は電車などが返ればそれ
    func testMapsHandOff() throws {
        let url = try XCTUnwrap(TripTravel.googleURL(from: Photo.Coords(lat: 36.578, lng: 136.648),
                                                     to: Photo.Coords(lat: 36.2376, lng: 136.126), mode: .transit))
        XCTAssertEqual(url.absoluteString,
                       "https://www.google.com/maps/dir/?api=1&origin=36.578000,136.648000&destination=36.237600,136.126000&travelmode=transit")
        XCTAssertFalse(url.absoluteString.contains("key="), "鍵を付けない")
        XCTAssertEqual(TripTravel.openMode([.init(mode: .automobile, seconds: 1), .init(mode: .transit, seconds: 2)],
                                           modes: [.automobile, .transit]), .transit)
        XCTAssertEqual(TripTravel.openMode([], modes: [.walking, .automobile]), .walking)
    }

    /// 区間の行は1つの型（`TripTravel.Leg`）を受け取り、押すと区間のシート（第2段で中身だけ差し替える）
    func testLegRowOpensTheLegSheet() throws {
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(detail.contains("TripLegSheet(leg: target.leg"))
        XCTAssertTrue(detail.contains("TripLegRow(leg: leg"))
        let sheet = try source("Features/Trips/TripLegViews.swift")
        XCTAssertTrue(sheet.contains("MKMapItem.openMaps(with: [origin, target]"))
        XCTAssertTrue(sheet.contains("TripTravel.googleURL(from: from, to: to, mode: mode)"))
        XCTAssertFalse(sheet.contains("forCurrentLocation"), "今いる場所を取らない")
        let estimator = try source("Services/TravelEstimator.swift")
        XCTAssertTrue(estimator.contains("calculateETA()"))
        XCTAssertTrue(estimator.contains(".loadingThrottled"), "断られたら止める")
        XCTAssertTrue(estimator.contains("case .transit: return MKLaunchOptionsDirectionsModeTransit"),
                      "公共交通の区間は公共交通で Apple のマップを開く")
    }

    // MARK: - 5. どこからでも入れる・番号・旅の一冊

    func testAddingToAPlan() {
        let item = TripItem.spot(spotId: "new", note: nil)
        let d = days([1, 2])
        XCTAssertEqual(ids(TripPlanEdit.adding(item, to: d, day: 1)!), [["s1"], ["s2", "s3", "new"]])
        XCTAssertEqual(ids(TripPlanEdit.adding(item, to: d, day: nil)!), [["s1"], ["s2", "s3"], ["new"]], "日を足す")
        XCTAssertNil(TripPlanEdit.adding(item, to: days([TripPlanService.itemsPerDayMax]), day: 0), "いっぱいの日")
        XCTAssertNil(TripPlanEdit.adding(item, to: d, day: 5))
        XCTAssertEqual(TripPlanEdit.dayContaining(.spot(spotId: "s3", note: nil), in: d), 1)
        XCTAssertEqual(TripPlanAddSheetTitle.title(1), "2 日目に入れる")
        XCTAssertEqual(TripPlanAddSheetTitle.title(nil), "新しい日に入れる")
    }

    /// 先に選ぶプラン: 出発が近い → 旅の最中 → 日付なし → 帰着済み
    func testDefaultPlanIsTheNextDeparture() {
        let past = TripPlan(planId: "past", title: "p", startDate: "2026-10-01", endDate: "2026-10-02")
        let later = TripPlan(planId: "later", title: "l", startDate: "2027-01-10", endDate: "2027-01-12")
        let soon = TripPlan(planId: "soon", title: "s", startDate: "2026-12-24", endDate: "2026-12-25")
        let undated = TripPlan(planId: "undated", title: "u")
        XCTAssertEqual(TripPlanEdit.defaultPlan([past, later, undated, soon], today: "2026-11-10")?.planId, "soon")
        XCTAssertEqual(TripPlanEdit.defaultPlan([past, undated], today: "2026-11-10")?.planId, "undated")
        XCTAssertEqual(TripPlanEdit.defaultPlan([past], today: "2026-11-10")?.planId, "past")
        XCTAssertNil(TripPlanEdit.defaultPlan([], today: "2026-11-10"))
    }

    /// 先に選ぶ日: 入れる場所にいちばん近い場所がある日
    func testSuggestedDayIsTheNearestDay() {
        let d = [TripDay(items: [.spot(spotId: "kanazawa", note: nil)]), TripDay(items: [.spot(spotId: "fukui", note: nil)])]
        let coords: [String: Photo.Coords] = ["kanazawa": Photo.Coords(lat: 36.56, lng: 136.66),
                                              "fukui": Photo.Coords(lat: 36.06, lng: 136.22)]
        let near = TripPlanEdit.suggestedDay(d, coords: Photo.Coords(lat: 35.98, lng: 135.96)) { item in
            if case .spot(let id, _) = item { return coords[id] } else { return nil }
        }
        XCTAssertEqual(near, 1, "越前岬は福井の日")
        XCTAssertEqual(TripPlanEdit.suggestedDay(d, coords: nil) { _ in nil }, 1, "座標が分からなければ最後の日")
        XCTAssertNil(TripPlanEdit.suggestedDay([], coords: nil) { _ in nil })
    }

    /// 撮影スポットの頁の札: 行きたい・旅行プランに入れる・経路。地図で見るは下の1行
    func testSpotPageActions() throws {
        XCTAssertEqual(SpotScreen.officialActions(hasCoords: true), [.wish, .trip, .directions])
        XCTAssertEqual(SpotScreen.officialActions(hasCoords: false), [.wish, .trip])
        XCTAssertTrue(SpotScreen.officialMapRow(hasCoords: true))
        XCTAssertTrue(try source("Features/Spots/OfficialSpotView.swift").contains("TripAddTarget(place: TripDraft.place(spot: shown)"))
        XCTAssertTrue(try source("Features/Spots/SpotDetailView.swift").contains("TripAddTarget(place: TripDraft.place(location: spot)"))
        XCTAssertTrue(try source("Features/PhotoDetail/PhotoTripSection.swift").contains("TripAddTarget(place: Self.tripPlace(destination)"))
    }

    /// 地図の番号は日程の通し番号（2日目は前の日の続き）
    func testDayMapNumbersContinueAcrossDays() throws {
        let a = try spot("a", lat: 35, lng: 135)
        let b = try spot("b", lat: 35.1, lng: 135)
        let day2 = TripDay(items: [.spot(spotId: "sp_a", note: nil), .spot(spotId: "sp_b", note: nil)])
        XCTAssertEqual(TripDayMap.stops(of: day2, index: [a, b], places: [], startNumber: 4).map(\.number), [4, 5])
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(detail.contains("TripDayMap.stops(of: day, index: index, places: places, startNumber: numbers.first ?? 1)"),
                      "日の地図に通し番号を渡していない")
    }

    /// 帰着済みの札の旅の一冊: 期間が重なる一冊だけ（いちばん多く重なるもの）
    func testBookForFinishedPlan() {
        let utc = TripPlanText.calendar
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date { utc.date(from: DateComponents(year: y, month: m, day: day))! }
        let plan = TripPlan(planId: "p", title: "t", startDate: "2026-09-12", endDate: "2026-09-14")
        let overlapping = TripBook.Trip(id: "a", place: "", start: d(2026, 9, 13), end: d(2026, 9, 15), photos: [])
        let more = TripBook.Trip(id: "b", place: "", start: d(2026, 9, 11), end: d(2026, 9, 14), photos: [])
        let apart = TripBook.Trip(id: "c", place: "", start: d(2026, 8, 1), end: d(2026, 8, 3), photos: [])
        XCTAssertEqual(TripPlanText.book(for: plan, in: [overlapping, apart])?.id, "a")
        XCTAssertEqual(TripPlanText.book(for: plan, in: [overlapping, more, apart])?.id, "b")
        XCTAssertNil(TripPlanText.book(for: plan, in: [apart]))
        XCTAssertNil(TripPlanText.book(for: TripPlan(planId: "x", title: "x"), in: [overlapping]), "日付の無いプラン")
        XCTAssertTrue(try source("Features/Trips/TripPlansView.swift").contains("TripPlanText.book(for: plan, in: myTrips)"))
    }
}

/// 試験から主ボタンの字を呼ぶ（`TripAddSheet.addTitle` は `View` の中にある）
private enum TripPlanAddSheetTitle {
    static func title(_ day: Int?) -> String { TripAddSheet.addTitle(day: day) }
}

/// 見本のプラン（UI テスト用・Debug のときだけ）と、追加の4つ（2026-11-10 札 #521 の続き）
final class TripPlanStage1FollowUpTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 見本: 2 日・5 か所・出発は先（30 日後）。**Release では効かない**（`#if DEBUG` の外は false）
    func testFixtureShapeAndReleaseGuard() throws {
        let plans = TripPlanFixture.initialPlans(today: TripPlanText.date(fromYMD: "2026-11-10")!)
        XCTAssertEqual(plans.first?.days.map(\.items.count), [3, 2])
        XCTAssertEqual(plans.last?.days.map(\.items.count), [1, 1, 0, 1], "1 日 1 か所・空の日・ブラジル（2026-11-11）")
        XCTAssertEqual(plans.first?.startDate, "2026-12-10")
        let text = try source("Services/TripPlanFixture.swift")
        for name in ["isOn", "offline", "failing"] {
            let body = text.components(separatedBy: "static var \(name): Bool {").dropFirst().first ?? ""
            XCTAssertTrue(body.prefix(200).contains("#if DEBUG") && body.prefix(260).contains("#else\n        return false"),
                          "\(name) が Release で false にならない")
        }
        XCTAssertTrue(try source("Services/TripPlanService.swift").contains("if TripPlanFixture.isOn { return TripPlanList(plans: try await TripPlanFixtureStore.shared.update"))
    }

    /// 見本の書き込みは送った回数を数える（サーバーへは送らない）
    func testFixtureStoreCountsWrites() async throws {
        let store = TripPlanFixtureStore()
        let before = try await store.list()
        var patch = TripPlanService.Patch()
        patch.startDate = ""
        let after = try await store.update(planId: "fixture-kanazawa", patch)
        XCTAssertNil(after.first?.startDate, "空文字で日付を消す（サーバーと同じ）")
        XCTAssertNotEqual(after.first?.updatedAt, before.first?.updatedAt, "版が進む（送る前の読み直しが見分ける）")
    }

    /// 電波なしで使える旅に移動の見込みを残す（同じ日の座標のある前の場所から・日をまたがない）
    func testOfflineStopsCarryTravel() {
        func stop(_ n: Int, day: Int, lat: Double?) -> OfflineTripPlan.Stop {
            OfflineTripPlan.Stop(number: n, dayIndex: day, date: nil, key: "spot:\(n)", item: .spot(spotId: "\(n)", note: nil),
                                 name: "S\(n)", address: nil, coords: lat.map { Photo.Coords(lat: $0, lng: 136) },
                                 note: nil, light: nil)
        }
        let stops = [stop(1, day: 0, lat: 36.5), stop(2, day: 0, lat: nil), stop(3, day: 0, lat: 36.6), stop(4, day: 1, lat: 36.7)]
        let out = OfflineTripPlan.withTravel(stops) { leg in
            [TripTravel.Estimate(mode: .automobile, seconds: 3000), TripTravel.Estimate(mode: .transit, seconds: 4800)]
                .filter { _ in leg.from.number != 2 }   // どの区間にも見込みがある（日をまたぐ区間も）
        }
        XCTAssertEqual(out.map(\.travel), [nil, nil, "前の場所から 車 約 50 分\u{2002}電車など 約 1 時間 20 分", nil],
                       "座標の無い場所を飛ばし、日をまたいでは添えない")
        XCTAssertTrue(try source("Features/Trips/OfflineTripCard.swift").contains("OfflineTripPlan.withTravel(planned.stops)"))
        XCTAssertTrue(try source("Core/Storage/OfflineTripStore.swift").contains("samples: samples, map: map, travel: stop.travel)"))
    }

    /// 古い保存（移動の見込みの無い記録）も読める
    func testOldManifestStopWithoutTravelDecodes() throws {
        let json = #"{"number":1,"key":"spot:a","name":"A","samples":[]}"#
        let stop = try JSONDecoder().decode(OfflineTripManifest.Stop.self, from: Data(json.utf8))
        XCTAssertNil(stop.travel)
    }

    /// 候補のシートの季節の一文。**マイページは変えない**（2026-11-10 owner「マイページはかえなくていい」・札 #519）
    func testPickSheetSeasonAndMyPageUnchanged() throws {
        let page = try source("Features/Profile/MyPageView.swift")
        XCTAssertFalse(page.contains("TripAddTarget"), "マイページの行に「旅行プランに入れる」を置かない")
        let pick = try source("Features/Trips/TripPlanPickSheet.swift")
        // 2026-11-12: 入れる日をシートの中で替えられるので、その日の季節の一文を行ごとに引く
        XCTAssertTrue(pick.contains("let season = seasonLine(choice, day)"))
        XCTAssertTrue(pick.contains("if let season {"))
        XCTAssertTrue(try source("Features/Trips/TripPlanDetailView.swift").contains("seasonLine: { choice, day in seasonLine(for: choice, day: day) }"))
    }
}

/// 自動保存の待ち直し（実際の 2 秒の待ち・時計を差し替えて数える・2026-11-10 札 #521）
@MainActor
final class TripAutosaveDebouncerTests: XCTestCase {

    /// 手で進める時計。`sleep` は時計が進むまで待ち、取り消されたら投げる。
    /// 🔴 **主アクタに縛る**（確かめ役の指摘・2026-11-10）: 縛らないと、取り消しの知らせ（`onCancel`）や
    /// 待つ仕事が別のスレッドから `waiters` を書き換え、「Index out of range」「CONTINUATION MISUSE」で止まった
    @MainActor
    private final class ManualClock {
        private(set) var now: UInt64 = 0
        private var waiters: [(id: Int, at: UInt64, done: CheckedContinuation<Void, Error>)] = []
        private var nextId = 0

        func sleep(_ ns: UInt64) async throws {
            nextId += 1
            let id = nextId
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled { c.resume(throwing: CancellationError()); return }
                    waiters.append((id, now + ns, c))
                }
            } onCancel: {
                Task { @MainActor in self.drop(id) }
            }
        }

        private func drop(_ id: Int) {
            guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
            waiters.remove(at: i).done.resume(throwing: CancellationError())
        }

        func advance(seconds: Double) async {
            await settle()
            now += UInt64(seconds * 1_000_000_000)
            let due = waiters.filter { $0.at <= now }
            waiters.removeAll { $0.at <= now }
            due.forEach { $0.done.resume() }
            await settle()
        }

        func settle() async {
            for _ in 0..<50 { await Task.yield() }
        }
    }

    private func run(editsEvery seconds: Double, edits: Int) async -> Int {
        let clock = ManualClock()
        let debouncer = TripAutosaveDebouncer(delay: TripAutosave.standardDelayNanoseconds,
                                              sleep: { try await clock.sleep($0) })
        var sends = 0
        for i in 0..<edits {
            if i > 0 { await clock.advance(seconds: seconds) }
            debouncer.schedule { sends += 1 }
        }
        await clock.advance(seconds: 3)
        return sends
    }

    /// 0.5 秒おきに 5 回直す → 2 秒の待ちの中なので、送るのは最後の 1 回
    func testEditsWithinTwoSecondsSendOnce() async {
        let sends = await run(editsEvery: 0.5, edits: 5)
        XCTAssertEqual(sends, 1)
    }

    /// 2.5 秒おきに 5 回直す → 毎回待ちを越えるので 5 回送る
    func testEditsFartherApartSendEachTime() async {
        let sends = await run(editsEvery: 2.5, edits: 5)
        XCTAssertEqual(sends, 5)
    }

    /// 取り消せば送らない（保存せずに戻る）
    func testCancelStopsTheSend() async {
        let clock = ManualClock()
        let debouncer = TripAutosaveDebouncer(delay: TripAutosave.standardDelayNanoseconds,
                                              sleep: { try await clock.sleep($0) })
        var sends = 0
        debouncer.schedule { sends += 1 }
        await clock.settle()
        debouncer.cancel()
        await clock.advance(seconds: 3)
        XCTAssertEqual(sends, 0)
    }
}
