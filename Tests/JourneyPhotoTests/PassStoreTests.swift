import XCTest
@testable import JourneyPhoto

/// すれちがいの置き場（`PassStore`）と帳の並べ方（`PassBook`）
@MainActor
final class PassStoreTests: XCTestCase {

    private var root: URL!
    private var defaults: UserDefaults!
    private var scheduled: [(day: String, at: Date, count: Int)] = []

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pass-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: "pass-\(UUID().uuidString)")!
        scheduled = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore(user: String? = "me") -> PassStore {
        let store = PassStore(root: root, defaults: defaults, calendar: calendar) { [weak self] day, at, count in
            await MainActor.run { self?.scheduled.append((day, at, count)) }
        }
        store.use(userId: user)
        store.update {
            $0.enabled = true
            $0.cardPhotoId = "mine"
        }
        return store
    }

    private func payload(_ id: String, note: String = "", showsFrom: Bool = true) -> PassExchange.Payload {
        PassExchange.Payload(photoId: id, showsFrom: showsFrom, note: note)
    }

    private func photo(_ id: String, owner: String, audience: String? = nil) throws -> Photo {
        let a = audience.map { ",\"audience\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"userId\":\"\(owner)\"\(a)}".utf8))
    }

    private func waitForSchedule(_ count: Int) async {
        for _ in 0..<500 where scheduled.count < count { try? await Task.sleep(nanoseconds: 1_000_000) }
    }

    // MARK: - 受け取る

    /// 🔴 **同じ相手（同じ写真）は1日1回まで**。次の日（次の束）ならまた受け取る
    func testSamePeerOncePerDay() async {
        let store = makeStore()
        XCTAssertNotNil(store.record(payload("p1"), at: at(16, 10)))
        XCTAssertNil(store.record(payload("p1"), at: at(16, 15)), "同じ日に同じ人を2回綴じた")
        XCTAssertNotNil(store.record(payload("p2"), at: at(16, 15)))
        // 18 時を過ぎた分は次の日の束（別の日）
        XCTAssertNotNil(store.record(payload("p1"), at: at(16, 19)))
        XCTAssertEqual(store.encounters.map(\.number), [1, 2, 3])
    }

    func testOwnCardAndOffAreNotRecorded() async {
        let store = makeStore()
        XCTAssertNil(store.record(payload("mine"), at: at(16, 10)), "自分の名刺を綴じた")
        store.update { $0.enabled = false }
        XCTAssertNil(store.record(payload("p1"), at: at(16, 10)), "オフなのに綴じた")
        XCTAssertNil(store.payload, "オフなのに電波に載せる中身がある")
    }

    func testDailyLimit() async {
        let store = makeStore()
        for i in 0..<PassExchange.dailyLimit { XCTAssertNotNil(store.record(payload("p\(i)"), at: at(16, 10))) }
        XCTAssertNil(store.record(payload("over"), at: at(16, 11)), "上限を超えて綴じた")
    }

    /// 持つのは時の単位の時刻と、0.1 度に丸めた場所だけ。届くのは夕方
    func testRecordKeepsOnlyCoarseTimeAndPlace() async throws {
        let store = makeStore()
        let card = try XCTUnwrap(store.record(payload("p1", note: "こんにちは"), at: at(16, 15, 42),
                                              placeName: "京都市", place: Photo.Coords(lat: 34.99487, lng: 135.78503)))
        XCTAssertEqual(card.metHour, at(16, 15))
        XCTAssertEqual(card.deliverAt, at(16, 18))
        XCTAssertEqual(try XCTUnwrap(card.placeLat), 35.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(card.placeLng), 135.8, accuracy: 1e-9)
        XCTAssertEqual(card.note, "こんにちは")
        await waitForSchedule(1)
        XCTAssertEqual(scheduled.last?.day, "2026-10-16")
        XCTAssertEqual(scheduled.last?.at, at(16, 18))
        XCTAssertEqual(scheduled.last?.count, 1)
        store.record(payload("p2"), at: at(16, 16))
        await waitForSchedule(2)
        XCTAssertEqual(scheduled.last?.count, 2, "知らせの枚数が書き換わらない")
    }

    /// 端末の中に残り、読み直しても同じ。**人ごとに分かれる**
    func testPersistsPerPerson() async {
        let store = makeStore()
        store.record(payload("p1"), at: at(16, 10))
        store.update { $0.note = "霧の朝" }

        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _ in }
        again.use(userId: "me")
        XCTAssertEqual(again.encounters.map(\.photoId), ["p1"])
        XCTAssertEqual(again.settings.note, "霧の朝")
        XCTAssertTrue(again.settings.enabled)

        again.use(userId: "other")
        XCTAssertTrue(again.encounters.isEmpty, "別の人に前の人の帳が見えた")
        XCTAssertFalse(again.settings.enabled, "別の人の既定がオンになった")
        again.use(userId: nil)
        XCTAssertNil(again.payload)
    }

    func testRemoveDataDeletesTheBook() async {
        let store = makeStore()
        store.record(payload("p1"), at: at(16, 10))
        // 退会の片づけ（`AccountLocalData`）から消える
        AccountLocalData.remove(userId: "me", username: nil, defaults: defaults,
                                draftDirectory: root.appendingPathComponent("drafts"),
                                offlineTripsRoot: root.appendingPathComponent("trips"), passRoot: root)
        XCTAssertNil(defaults.string(forKey: PassStore.lastUserKey))
        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _ in }
        again.use(userId: "me")
        XCTAssertTrue(again.encounters.isEmpty)
        XCTAssertFalse(again.settings.enabled)
    }

    /// 既定はオフ（オンにする時に説明を出す）
    func testDefaultIsOff() async {
        XCTAssertFalse(PassSettings().enabled)
        XCTAssertEqual(PassSettings().mode, .traveling)
    }

    // MARK: - 見せる

    /// 🔴 **届く前は見せない・公開一覧に無い写真（非公開・削除）は見せない・ブロックした人は見せない**
    func testVisibility() async throws {
        let store = makeStore()
        store.record(payload("p1"), at: at(16, 10))
        store.record(payload("p2"), at: at(16, 11))
        store.record(payload("p3"), at: at(16, 12))
        store.record(payload("p4"), at: at(16, 13))
        store.record(payload("late"), at: at(16, 19))
        let evening = at(16, 18, 30)
        let all = [try photo("p1", owner: "a"), try photo("p2", owner: "b"),
                   try photo("p4", owner: "c", audience: "followers"), try photo("late", owner: "d")]
        store.applyResolved(all: all, now: evening)

        XCTAssertEqual(store.book(blocked: [], now: at(16, 17)).count, 0, "夕方より前に見えた")
        XCTAssertEqual(store.book(blocked: [], now: evening).map(\.photoId), ["p1", "p2"],
                       "一覧に無い写真・絞った写真・まだ届かない分が見えた")
        XCTAssertEqual(store.book(blocked: ["b"], now: evening).map(\.photoId), ["p1"], "ブロックした人が見えた")
        XCTAssertEqual(store.encounters.first?.ownerId, "a")

        // 公開に戻った写真は、次に引いたときにまた見える
        store.applyResolved(all: all + [try photo("p3", owner: "e")], now: evening)
        XCTAssertEqual(store.book(blocked: [], now: evening).map(\.photoId), ["p1", "p2", "p3"])

        XCTAssertEqual(store.unopened(blocked: [], now: evening).count, 3)
        store.markOpened(store.unopened(blocked: [], now: evening).map(\.id))
        XCTAssertTrue(store.unopened(blocked: [], now: evening).isEmpty)
        XCTAssertEqual(store.book(blocked: [], now: evening).count, 3, "開いたら帳から消えた")
    }

    /// 通報した写真のカードは見せない・帳から外したカードは記録ごと消える（カードの「…」・審査 1.2）
    func testReportedAndRemovedCardsAreGone() async throws {
        let store = makeStore()
        store.record(payload("p1"), at: at(16, 10))
        store.record(payload("p2"), at: at(16, 11))
        let evening = at(16, 19)
        store.applyResolved(all: [try photo("p1", owner: "a"), try photo("p2", owner: "b")], now: evening)
        var hiding = ModerationSnapshot()
        hiding.reported = ["p1"]
        XCTAssertEqual(store.book(hiding: hiding, now: evening).map(\.photoId), ["p2"], "通報した写真のカードが見えた")
        XCTAssertEqual(store.unopened(hiding: hiding, now: evening).map(\.photoId), ["p2"])
        let id = try XCTUnwrap(store.encounters.first { $0.photoId == "p2" }?.id)
        store.remove(id)
        XCTAssertTrue(store.book(hiding: hiding, now: evening).isEmpty)
        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _ in }
        again.use(userId: "me")
        XCTAssertEqual(again.encounters.map(\.photoId), ["p1"], "外したカードが読み直すと戻った")
    }

    /// ひとことを伏せる（この端末だけ・読み直しても伏せたまま・出し直せる）
    func testNoteCanBeHidden() async throws {
        let store = makeStore()
        let card = try XCTUnwrap(store.record(payload("p1", note: "こんにちは"), at: at(16, 10)))
        XCTAssertEqual(card.shownNote, "こんにちは")
        store.setNoteHidden(card.id, true)
        XCTAssertEqual(store.encounters.first?.shownNote, "")
        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _ in }
        again.use(userId: "me")
        XCTAssertEqual(again.encounters.first?.noteHidden, true, "伏せた印が残らない")
        again.setNoteHidden(card.id, false)
        XCTAssertEqual(again.encounters.first?.shownNote, "こんにちは")
    }

    /// 期限切れで止めた後に入り直したら、まだ届いていない束の知らせを予約し直す
    func testNoticesAreRescheduledOnSignIn() async throws {
        let store = makeStore()
        store.record(payload("p1"), at: Date().addingTimeInterval(-60))
        await waitForSchedule(1)
        scheduled = []
        store.use(userId: nil)
        store.use(userId: "me")
        await waitForSchedule(1)
        XCTAssertEqual(scheduled.count, 1, "入り直しても夕方の知らせを予約し直さない")
        XCTAssertEqual(scheduled.first?.count, 1)
    }

    /// 自分の写真（別の端末の自分）は見せない
    func testOwnPhotoFromAnotherDeviceIsHidden() async throws {
        let store = makeStore()
        store.record(payload("p1"), at: at(16, 10))
        store.applyResolved(all: [try photo("p1", owner: "me")], now: at(16, 19))
        XCTAssertTrue(store.book(blocked: [], now: at(16, 19)).isEmpty)
    }

    /// 「旅のあいだ」: 今日の分を覚えていなければ交換しない。覚えた日だけ
    func testTravelingNeedsTodaysAwayMark() async {
        let store = makeStore()
        XCTAssertEqual(store.settings.mode, .traveling)
        XCTAssertFalse(store.exchangeAllowed(isForeground: true, now: at(16, 10)))
        store.noteAway(true, now: at(16, 9))
        XCTAssertTrue(store.exchangeAllowed(isForeground: false, now: at(16, 10)))
        XCTAssertFalse(store.exchangeAllowed(isForeground: false, now: at(17, 10)), "前の日の印で交換した")
        store.update { $0.mode = .always }
        XCTAssertTrue(store.exchangeAllowed(isForeground: false, now: at(17, 10)))
        store.update { $0.cardPhotoId = nil }
        XCTAssertFalse(store.exchangeAllowed(isForeground: true, now: at(17, 10)), "名刺が無いのに電波を出す")
    }

    func testHomeLocation() async {
        let store = makeStore()
        store.noteHome("京都府京都市")
        XCTAssertEqual(store.homePrefecture, "京都府")
        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _ in }
        again.use(userId: "me")
        XCTAssertEqual(again.homePrefecture, "京都府", "背景の起動で家が分からない")
    }

    // MARK: - 帳

    private func card(_ n: Int, day: Int, owner: String?, place: String?, showsFrom: Bool = true,
                      lat: Double? = nil, lng: Double? = nil) -> PassEncounter {
        PassEncounter(id: "c\(n)", photoId: "p\(n)", note: "", showsFrom: showsFrom, metHour: at(day, 10 + n % 5),
                      deliverAt: at(day, 18), placeName: place, placeLat: lat, placeLng: lng,
                      number: n, opened: false, ownerId: owner)
    }

    func testEmptySlotsFillThePage() async {
        XCTAssertEqual(PassBook.emptySlots(for: 0), 9)
        XCTAssertEqual(PassBook.emptySlots(for: 6), 3)
        XCTAssertEqual(PassBook.emptySlots(for: 9), 0)
        XCTAssertEqual(PassBook.emptySlots(for: 10), 8)
    }

    func testSectionsByDayPlaceAndPerson() async {
        let cards = [card(1, day: 15, owner: "a", place: "金沢市"),
                     card(2, day: 16, owner: "b", place: "京都市"),
                     card(3, day: 16, owner: "a", place: "京都市"),
                     card(4, day: 16, owner: "a", place: nil)]
        let bound = PassBook.sections(cards, order: .bound, names: [:], calendar: calendar)
        XCTAssertEqual(bound.map(\.title), ["2026.10.16 · 京都市", "2026.10.15 · 金沢市"])
        XCTAssertEqual(bound[0].cards.map(\.number), [2, 3, 4])

        let place = PassBook.sections(cards, order: .place, names: [:], calendar: calendar)
        XCTAssertEqual(place.map(\.id), ["place-京都市", "place-金沢市", "place-unknown"])

        let person = PassBook.sections(cards, order: .person, names: ["a": "mio.k"], calendar: calendar)
        XCTAssertEqual(person.first?.id, "person-a", "よく会う人が先頭に来ない")
        XCTAssertEqual(person.first?.cards.count, 3)
        XCTAssertTrue(person.first?.title.contains("mio.k") ?? false)

        XCTAssertEqual(PassBook.meetingCount(of: cards[2], in: cards), 2)
        XCTAssertEqual(PassBook.meetingCount(of: cards[1], in: cards), 1)
    }

    /// 都道府県は**相手が出すと決めたものだけ**数える
    func testStatsCountOnlySharedPrefectures() async {
        let cards = [card(1, day: 16, owner: "a", place: "京都市", lat: 35.0, lng: 135.8),
                     card(2, day: 16, owner: "b", place: "京都市", showsFrom: false, lat: 35.0, lng: 135.8),
                     card(3, day: 16, owner: "c", place: "京都市", lat: 35.0, lng: 135.8)]
        let stats = PassBook.stats(cards, prefectures: ["a": "北海道", "b": "沖縄県", "c": "京都府"])
        XCTAssertEqual(stats.cards, 3)
        XCTAssertEqual(stats.prefectures, 2, "出さないと決めた人の都道府県を数えた")
        XCTAssertTrue((1000...1100).contains(stats.farthestKm ?? 0), "\(String(describing: stats.farthestKm))")
    }

    func testBundleLine() async {
        let two = [card(1, day: 16, owner: "a", place: "京都市"), card(2, day: 16, owner: "b", place: "宇治市"),
                   card(3, day: 16, owner: "c", place: "大津市")]
        let line = PassBook.bundleLine(two)
        XCTAssertTrue(line.contains("京都市") && line.contains("宇治市"), line)
        XCTAssertFalse(line.contains("大津市"), "場所を3つ以上並べた: \(line)")
        XCTAssertTrue(PassBook.bundleLine([card(1, day: 16, owner: "a", place: nil)]).contains("1"))
    }
}
