import XCTest
@testable import JourneyPhoto

/// 行った県マップ（札 #503）の判定・保存・数え方。
///
/// 守るのは次の3つ:
/// 1. 写真から導けるのは**候補だけ**（サーバー `prefectureOfPhoto` と同じ順序）。回数は本人の記録でしか増えない
/// 2. 周は**回数から出す**（全47県が n 回以上で n 周そろった）。祝いは周が増えたときに1回だけ
/// 3. 端末の中だけ・人ごとに分け・退会で消す。塗り・回数は報酬にも公開にも結びつけない
final class VisitedPrefecturesTests: XCTestCase {

    // MARK: - 道具

    private func spot(_ slug: String, prefecture: String?, lat: Double, lng: Double,
                      stage: String = "published") throws -> OfficialSpot {
        let region = prefecture.map { ",\"region\":{\"prefecture\":\"\($0)\"}" } ?? ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(slug)\",\"stage\":\"\(stage)\"\(region),\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}}".utf8))
    }

    private func photo(_ id: String, location: String? = nil, lat: Double? = nil, lng: Double? = nil,
                       spotId: String? = nil, published: Bool? = nil) throws -> Photo {
        var extra = ""
        if let location { extra += ",\"location\":\"\(location)\"" }
        if let lat, let lng { extra += ",\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}" }
        if let spotId { extra += ",\"spotId\":\"\(spotId)\"" }
        if let published { extra += ",\"published\":\(published)" }
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(extra)}".utf8))
    }

    private func resolver() throws -> PrefectureResolver {
        PrefectureResolver(spots: [
            try spot("zojoji", prefecture: "東京都", lat: 35.657, lng: 139.748),
            try spot("kinkakuji", prefecture: "京都府", lat: 35.039, lng: 135.729),
            try spot("versailles", prefecture: "イヴリーヌ県", lat: 48.80, lng: 2.12),
            try spot("draft", prefecture: "北海道", lat: 43.06, lng: 141.35, stage: "draft"),
        ])
    }

    private func fullBook(times: Int = 1) -> VisitedPrefectures {
        var book = VisitedPrefectures()
        for name in RegionList.prefectures {
            for _ in 0..<times { book.add(name, day: "2026-01-01") }
        }
        return book
    }

    // MARK: - 写真 → 県の候補（サーバーの順序）

    func testTextPrefectureOfficialShortAndEnglish() {
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "長野県 松本市"), "長野県")
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "京都駅"), "京都府")
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "東京駅"), "東京都")
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "札幌, 北海道"), "北海道")
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "Kyoto, Japan"), "京都府")
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "Hyōgo Prefecture"), "兵庫県")
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "Tokyo Metropolis"), "東京都")
        XCTAssertNil(PrefectureResolver.prefecture(inText: "Akitaka"), "単語の一部は当てない")
        XCTAssertNil(PrefectureResolver.prefecture(inText: "Paris, France"))
        XCTAssertNil(PrefectureResolver.prefecture(inText: "  "))
        XCTAssertNil(PrefectureResolver.prefecture(inText: nil))
    }

    /// 🔴 「東京都」は「京都」を含む。京都府に当てない
    func testTokyoIsNotKyoto() {
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "東京都庁"), "東京都")
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "東京都 渋谷区"), "東京都")
    }

    /// 正式名が短い名より先（「香川県 観音寺市」に「川」…は無いが、先に書かれた県を採る）
    func testEarliestPrefectureWins() {
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "香川県 観音寺市 愛媛県境"), "香川県")
        XCTAssertEqual(PrefectureResolver.prefecture(inText: "大阪府から奈良県へ"), "大阪府")
    }

    func testOrderSpotThenTextThenCoords() throws {
        let r = try resolver()
        // ① 撮影スポット（撮影地の文字・座標と食い違っても、スポットの県）
        XCTAssertEqual(r.prefecture(of: try photo("a", location: "北海道", lat: 43.0, lng: 141.3, spotId: "sp_kinkakuji")),
                       "京都府")
        // ② 文字（座標より先）
        XCTAssertEqual(r.prefecture(of: try photo("b", location: "京都市", lat: 35.657, lng: 139.748)), "京都府")
        // ③ 座標（文字に県が無い）
        XCTAssertEqual(r.prefecture(of: try photo("c", location: "どこかの海", lat: 35.66, lng: 139.75)), "東京都")
        // 知らない spotId は文字へ進む
        XCTAssertEqual(r.prefecture(of: try photo("d", location: "京都", spotId: "sp_unknown")), "京都府")
    }

    func testNearestSpotLimitIs40kmAndJapanBox() throws {
        let r = try resolver()
        XCTAssertEqual(r.nearestPrefecture(to: Photo.Coords(lat: 35.70, lng: 139.80)), "東京都")
        // 約 90km 北は寄せない
        XCTAssertNil(r.nearestPrefecture(to: Photo.Coords(lat: 36.50, lng: 139.75)))
        // 日本の外枠の外
        XCTAssertNil(r.nearestPrefecture(to: Photo.Coords(lat: 48.80, lng: 2.12)),
                     "フランスのスポットの近くを県に当てない")
        XCTAssertNil(r.nearestPrefecture(to: Photo.Coords(lat: .nan, lng: 139.8)))
    }

    func testSpotsFromLedgerSkipDraftsAndForeignDivisions() throws {
        let r = try resolver()
        XCTAssertEqual(r.spotPrefectures["sp_zojoji"], "東京都")
        XCTAssertNil(r.spotPrefectures["sp_versailles"], "フランスの「県」を拾わない")
        XCTAssertNil(r.spotPrefectures["sp_draft"], "下書きのスポットは使わない")
        XCTAssertEqual(r.anchors.count, 2)
    }

    func testFoundSkipsDraftsAndKeepsJISOrder() throws {
        let r = try resolver()
        let found = r.found(in: [
            try photo("1", location: "京都市"),
            try photo("2", location: "長野県"),
            try photo("3", location: "沖縄県", published: false),
            try photo("4", location: "北海道"),
        ])
        XCTAssertEqual(found, ["北海道", "長野県", "京都府"])
    }

    // MARK: - 記録・回数・段

    func testAddAndRemoveKeepSortedDaysAndDropEmpty() {
        var book = VisitedPrefectures()
        XCTAssertNotNil(book.add("東京都", day: "2026-03-01"))
        XCTAssertNotNil(book.add("東京都", day: "2026-01-15"))
        XCTAssertEqual(book.days("東京都"), ["2026-01-15", "2026-03-01"])
        XCTAssertEqual(book.count("東京都"), 2)
        XCTAssertNil(book.add("パリ", day: "2026-03-01"), "県の名前でないものは入れない")
        XCTAssertNotNil(book.removeLast("東京都"))
        XCTAssertEqual(book.days("東京都"), ["2026-01-15"])
        XCTAssertNotNil(book.removeLast("東京都"))
        XCTAssertEqual(book.count("東京都"), 0)
        XCTAssertEqual(book.visitedCount, 0)
        XCTAssertNil(book.removeLast("東京都"), "0 回の県は減らせない")
    }

    func testMaxCountIs99() {
        var book = VisitedPrefectures()
        for _ in 0..<VisitedPrefectures.maxCount { XCTAssertNotNil(book.add("沖縄県", day: "2026-01-01")) }
        XCTAssertNil(book.add("沖縄県", day: "2026-01-02"))
        XCTAssertEqual(book.count("沖縄県"), 99)
    }

    func testLevelsAndCountText() {
        XCTAssertEqual((0...6).map(VisitedPrefectures.level(forCount:)), [0, 1, 2, 3, 3, 3, 3])
        XCTAssertEqual(VisitedPrefectures.level(forCount: -3), 0)
        XCTAssertEqual([0, 1, 8, 9, 10, 99].map(VisitedPrefectures.countText), ["", "1", "8", "9+", "9+", "9+"])
    }

    func testSameDayCheck() {
        var book = VisitedPrefectures()
        book.add("京都府", day: "2026-11-08")
        XCTAssertTrue(book.hasVisit("京都府", on: "2026-11-08"))
        XCTAssertFalse(book.hasVisit("京都府", on: "2026-11-09"))
        XCTAssertFalse(book.hasVisit("大阪府", on: "2026-11-08"))
    }

    func testChangeDay() {
        var book = VisitedPrefectures()
        book.add("京都府", day: "2026-05-01")
        book.add("京都府", day: "2026-07-01")
        XCTAssertNotNil(book.changeDay("京都府", at: 0, to: "2026-09-01"))
        XCTAssertEqual(book.days("京都府"), ["2026-07-01", "2026-09-01"])
        XCTAssertNil(book.changeDay("京都府", at: 5, to: "2026-09-01"))
        XCTAssertNil(book.changeDay("京都府", at: 0, to: "2026-07-01"), "同じ日なら変えない")
    }

    // MARK: - 周

    func testRoundsComeFromCounts() {
        var book = VisitedPrefectures()
        XCTAssertEqual(book.completedRounds, 0)
        XCTAssertEqual(book.inProgress.round, 1)
        for name in RegionList.prefectures.dropLast() { book.add(name, day: "2026-01-01") }
        XCTAssertEqual(book.visitedCount, 46)
        XCTAssertEqual(book.completedRounds, 0)
        book.add("沖縄県", day: "2026-01-01")
        XCTAssertEqual(book.completedRounds, 1)
        XCTAssertEqual(book.inProgress.round, 2)
        XCTAssertEqual(book.inProgress.done, 0)
        book.add("東京都", day: "2026-02-01")
        book.add("東京都", day: "2026-03-01")
        book.add("京都府", day: "2026-03-01")
        XCTAssertEqual(book.completedRounds, 1, "3 回の県があっても全県が 2 回になるまで 2 周ではない")
        XCTAssertEqual(book.inProgress.done, 2)
        XCTAssertEqual(book.count("東京都"), 3)
    }

    // MARK: - 候補と内訳

    func testCandidatesAreNotRecordedOrDismissed() {
        var book = VisitedPrefectures()
        book.add("東京都", day: "2026-01-01")
        book.dismissCandidate("長野県")
        let found = ["北海道", "東京都", "長野県", "京都府"]
        XCTAssertEqual(book.candidates(found: found), ["北海道", "京都府"])
        book.restoreCandidate("長野県")
        XCTAssertEqual(book.candidates(found: found), ["北海道", "長野県", "京都府"])
    }

    /// 候補は記録でも回数でもない（本人のタップまで数に入らない）
    func testCandidatesDoNotCount() {
        let book = VisitedPrefectures()
        _ = book.candidates(found: ["東京都", "京都府"])
        XCTAssertEqual(book.visitedCount, 0)
        XCTAssertEqual(book.counts.reduce(0, +), 0)
    }

    func testBreakdownPhotosAndHand() {
        var book = VisitedPrefectures()
        book.add("東京都", day: "2026-01-01")
        book.add("沖縄県", day: "2026-01-01")
        let b = book.breakdown(found: ["東京都", "京都府"])
        XCTAssertEqual(b.fromPhotos, 2)
        XCTAssertEqual(b.recordedOnly, 1)
    }

    // MARK: - 戻す

    func testUndoKeepsTheLast20() {
        var book = VisitedPrefectures()
        var history = VisitedHistory()
        for i in 0..<25 {
            let day = "2026-01-\(i < 9 ? "0" : "")\(i + 1)"
            if let change = book.add("東京都", day: day) { history.push(change) }
        }
        XCTAssertEqual(history.changes.count, VisitedHistory.limit)
        for _ in 0..<20 { XCTAssertNotNil(history.undo(on: &book)) }
        XCTAssertFalse(history.canUndo)
        XCTAssertNil(history.undo(on: &book))
        XCTAssertEqual(book.count("東京都"), 5, "20 手戻したあと、戻せなかった 5 回が残る")
    }

    func testUndoRestoresRemovedAndBulk() {
        var book = VisitedPrefectures()
        var history = VisitedHistory()
        book.add("東京都", day: "2026-01-01")
        if let c = book.removeLast("東京都") { history.push(c) }
        XCTAssertEqual(book.count("東京都"), 0)
        history.undo(on: &book)
        XCTAssertEqual(book.days("東京都"), ["2026-01-01"])

        if let c = book.markAllVisited(day: "2026-02-02") { history.push(c) }
        XCTAssertEqual(book.visitedCount, 47)
        XCTAssertEqual(book.days("東京都"), ["2026-01-01"], "すでに記録のある県は変えない")
        history.undo(on: &book)
        XCTAssertEqual(book.visitedCount, 1)
        XCTAssertEqual(book.days("東京都"), ["2026-01-01"])
    }

    func testClearAllCanBeUndone() {
        var book = fullBook()
        var history = VisitedHistory()
        if let c = book.clearAll() { history.push(c) }
        XCTAssertEqual(book.visitedCount, 0)
        history.undo(on: &book)
        XCTAssertEqual(book.visitedCount, 47)
    }

    // MARK: - 祝い

    /// すでに47県そろっている人が初めて開いても祝わない
    func testNoCelebrationWhenAlreadyCompleteOnFirstOpen() {
        var book = fullBook()
        book.settleOnOpen()
        XCTAssertNil(book.takeCelebration())
        book.add("東京都", day: "2026-02-01")
        XCTAssertNil(book.takeCelebration())
    }

    func testCelebratesOnceWhenAllVisitedThenOnEachNewRound() {
        var book = VisitedPrefectures()
        book.settleOnOpen()
        for name in RegionList.prefectures.dropLast() {
            book.add(name, day: "2026-01-01")
            XCTAssertNil(book.takeCelebration())
        }
        book.add("沖縄県", day: "2026-01-01")
        XCTAssertEqual(book.takeCelebration(), .allVisited)
        XCTAssertNil(book.takeCelebration(), "同じ周で2度祝わない")

        for name in RegionList.prefectures { book.add(name, day: "2026-06-01") }
        XCTAssertEqual(book.takeCelebration(), .roundCompleted(2))
    }

    func testCelebrationNotRepeatedAfterUndoAndRedo() {
        var book = VisitedPrefectures()
        book.settleOnOpen()
        for name in RegionList.prefectures.dropLast() { book.add(name, day: "2026-01-01") }
        let last = book.add("沖縄県", day: "2026-01-01")
        XCTAssertEqual(book.takeCelebration(), .allVisited)
        book.revert(last!)
        XCTAssertNil(book.takeCelebration())
        book.add("沖縄県", day: "2026-01-02")
        XCTAssertNil(book.takeCelebration(), "取り消して足し直しても、見せた周は繰り返さない")
    }

    func testNoCelebrationBeforeScreenWasOpened() {
        var book = fullBook()
        XCTAssertNil(book.takeCelebration(), "開く前は返さない（開いたときに覚える）")
    }

    // MARK: - 保存

    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    func testStoreRoundTripPerPerson() {
        let d = defaults()
        let store = VisitedPrefectureStore(defaults: d)
        var book = VisitedPrefectures()
        book.add("東京都", day: "2026-01-01")
        book.add("東京都", day: "2026-02-01")
        book.dismissCandidate("長野県")
        book.settleOnOpen()
        store.save(book, for: "a")
        XCTAssertEqual(store.load(for: "a"), book)
        XCTAssertEqual(store.load(for: "b").visitedCount, 0, "別の人の記録は見えない")
        store.save(VisitedPrefectures(), for: nil)
        store.save(book, for: "")
        XCTAssertEqual(store.load(for: nil).visitedCount, 0)
    }

    func testStoreRemoveDataForOnePerson() {
        let d = defaults()
        let store = VisitedPrefectureStore(defaults: d)
        var book = VisitedPrefectures()
        book.add("東京都", day: "2026-01-01")
        store.save(book, for: "gone")
        store.save(book, for: "stays")
        store.removeData(for: "gone")
        XCTAssertEqual(store.load(for: "gone").visitedCount, 0)
        XCTAssertEqual(store.load(for: "stays").visitedCount, 1)
    }

    func testStoreReadsBrokenValuesAsEmptyAndDropsBadRows() {
        let d = defaults()
        let store = VisitedPrefectureStore(defaults: d)
        d.set(Data("not json".utf8), forKey: VisitedPrefectureStore.key(for: "a"))
        XCTAssertEqual(store.load(for: "a").visitedCount, 0)
        let json = #"{"v":1,"visits":{"東京都":["2026-01-01","いつか"],"パリ":["2026-01-01"],"京都府":[]}}"#
        d.set(Data(json.utf8), forKey: VisitedPrefectureStore.key(for: "b"))
        let book = store.load(for: "b")
        XCTAssertEqual(book.days("東京都"), ["2026-01-01"], "読めない日付は落とす")
        XCTAssertEqual(book.visitedCount, 1, "県でない名前・空の行は落とす")
        XCTAssertNil(book.seenRounds)
    }

    func testDayString() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 0, minute: 30))!
        let s = VisitedDay.string(from: date, calendar: cal)
        XCTAssertEqual(s, "2026-11-08", "端末のカレンダーの日で数える（この時刻は UTC では前日の 15:30）")
        XCTAssertTrue(VisitedDay.isValid(s), s)
        XCTAssertEqual(s.count, 10)
        let back = VisitedDay.date(from: "2026-11-08", calendar: cal)
        XCTAssertEqual(back.map { VisitedDay.string(from: $0, calendar: cal) }, "2026-11-08")
        XCTAssertNil(VisitedDay.date(from: "いつか", calendar: cal))
        XCTAssertFalse(VisitedDay.isValid("2026-13-01"))
        XCTAssertFalse(VisitedDay.isValid("26-1-1"))
    }

    /// 🔴 和暦・仏暦の端末でも、保存する日付は西暦（以前は和暦で「0008-11-08」になり、読み込みで落ちて記録が消えた）
    func testDayIsGregorianWhateverTheDeviceCalendar() {
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        var g = Calendar(identifier: .gregorian)
        g.timeZone = tz
        let date = g.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))!
        for id in [Calendar.Identifier.japanese, .buddhist, .republicOfChina, .islamicCivil, .hebrew] {
            var cal = Calendar(identifier: id)
            cal.timeZone = tz
            let s = VisitedDay.string(from: date, calendar: cal)
            XCTAssertEqual(s, "2026-11-08", "\(id) の端末で西暦にならない")
            XCTAssertTrue(VisitedDay.isValid(s))
            // 読み戻しも西暦（その日の正午）
            let back = VisitedDay.date(from: s, calendar: cal)
            XCTAssertEqual(back, date)
        }
    }

    /// 和暦の端末で足した記録が、保存して読み直しても消えない
    func testRecordSurvivesSaveAndLoadOnJapaneseCalendar() async throws {
        var cal = Calendar(identifier: .japanese)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var g = Calendar(identifier: .gregorian)
        g.timeZone = cal.timeZone
        let date = g.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))!
        let d = defaults()
        let store = VisitedPrefectureStore(defaults: d)
        var book = VisitedPrefectures()
        book.add("東京都", day: VisitedDay.string(from: date, calendar: cal))
        store.save(book, for: "u")
        XCTAssertEqual(store.load(for: "u").days("東京都"), ["2026-11-08"])
    }

    func testChangeDayNeverMakesDuplicatesAndLoadSortsDays() {
        var book = VisitedPrefectures()
        book.add("京都府", day: "2026-05-01")
        book.add("京都府", day: "2026-07-01")
        XCTAssertNil(book.changeDay("京都府", at: 0, to: "2026-07-01"), "ほかの記録と同じ日には直せない")
        XCTAssertEqual(book.days("京都府"), ["2026-05-01", "2026-07-01"])
        // 読み込みで並べ直す
        let loaded = VisitedPrefectures(visits: ["京都府": ["2026-09-01", "2026-01-01", "2026-05-01"]])
        XCTAssertEqual(loaded.days("京都府"), ["2026-01-01", "2026-05-01", "2026-09-01"])
    }

    /// 🔴 読めない値・新しい版の値は、空で上書きされる前に控えへ移す（退会で控えも消える）
    func testUnreadableOrFutureValuesAreBackedUpBeforeOverwrite() {
        let d = defaults()
        let store = VisitedPrefectureStore(defaults: d)
        let broken = Data("{\"visits\":".utf8)
        d.set(broken, forKey: VisitedPrefectureStore.key(for: "a"))
        XCTAssertEqual(store.load(for: "a").visitedCount, 0)
        XCTAssertEqual(d.data(forKey: VisitedPrefectureStore.backupKey(for: "a")), broken)
        // 空を保存しても控えは残る。2回目に読めない値を読んでも控えは入れ替えない
        store.save(VisitedPrefectures(), for: "a")
        XCTAssertEqual(d.data(forKey: VisitedPrefectureStore.backupKey(for: "a")), broken)

        let future = Data(#"{"v":2,"visits":{"東京都":["2026-01-01"]},"extra":1}"#.utf8)
        d.set(future, forKey: VisitedPrefectureStore.key(for: "b"))
        XCTAssertEqual(store.load(for: "b").count("東京都"), 1)
        XCTAssertEqual(d.data(forKey: VisitedPrefectureStore.backupKey(for: "b")), future)

        // 今の形なら控えを作らない
        var book = VisitedPrefectures()
        book.add("東京都", day: "2026-01-01")
        store.save(book, for: "c")
        _ = store.load(for: "c")
        XCTAssertNil(d.data(forKey: VisitedPrefectureStore.backupKey(for: "c")))

        store.removeData(for: "a")
        XCTAssertNil(d.data(forKey: VisitedPrefectureStore.backupKey(for: "a")), "退会で控えも消える")
    }

    // MARK: - 報酬・公開と結ばない

    /// 🔴 塗り・回数は硬貨・バッジ・家具・Pro にも、サーバーにも結ばない（不正の誘因を作らない）。
    /// 記録の層（判定・保存）が、これらの型や通信に触れていないことをソースで見る
    func testRecordLayerIsNotTiedToRewardsOrServer() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["Core/Text/VisitedPrefectures.swift", "Core/Storage/VisitedPrefectureStore.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                                  encoding: .utf8)
            let code = text.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
                .joined(separator: "\n")
            for forbidden in ["Camper", "Trunk", "Badge", "Coin", "ProStatus", "URLSession", "APIClient", "environment."] {
                XCTAssertFalse(code.contains(forbidden), "\(path) が \(forbidden) に触れている（報酬・公開と結ばない）")
            }
        }
    }
}
