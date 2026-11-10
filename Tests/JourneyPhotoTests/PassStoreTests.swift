import XCTest
@testable import JourneyPhoto

/// すれちがいの置き場（`PassStore`）と帳の並べ方（`PassBook`）
@MainActor
final class PassStoreTests: XCTestCase {

    private var root: URL!
    private var defaults: UserDefaults!
    private var scheduled: [(day: String, at: Date, count: Int, instant: Bool)] = []

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

    private func recorder() -> (String, Date, Int, Bool) async -> Void {
        { [weak self] day, at, count, instant in
            await MainActor.run { self?.scheduled.append((day, at, count, instant)) }
        }
    }

    private func makeStore(user: String? = "me", delivery: PassExchange.Delivery? = nil) -> PassStore {
        let store = PassStore(root: root, defaults: defaults, calendar: calendar, schedule: recorder())
        store.use(userId: user)
        store.update {
            $0.enabled = true
            $0.cardPhotoId = "mine"
            $0.delivery = delivery
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
        let store = makeStore(delivery: .evening)
        XCTAssertNotNil(store.record(payload("p1"), at: at(16, 10)))
        XCTAssertNil(store.record(payload("p1"), at: at(16, 15)), "同じ日に同じ人を2回綴じた")
        XCTAssertNotNil(store.record(payload("p2"), at: at(16, 15)))
        // 18 時を過ぎた分は次の日の束（別の日）
        XCTAssertNotNil(store.record(payload("p1"), at: at(16, 19)))
        XCTAssertEqual(store.encounters.map(\.number), [1, 2, 3])
    }

    /// 🔴 保存すると電話番号になる字（改行で桁を切ったもの）は、設定に残さない
    func testUpdateDropsContactShapedNote() async {
        let store = makeStore()
        store.update { $0.note = "090\n12345" }
        XCTAssertEqual(store.settings.note, "", "保存後に電話番号へ戻る字を残した")
        store.update {
            $0.setOrigin(.custom, text: "a\u{200B}.jp")
            $0.note = "霧の朝"
        }
        XCTAssertEqual(store.settings.note, "霧の朝")
        XCTAssertNil(store.settings.originLabel, "URL になる発を残した")
        XCTAssertEqual(store.payload?.note, "霧の朝")
        XCTAssertEqual(store.payload?.origin, "")
    }

    func testOwnCardAndOffAreNotRecorded() async {
        let store = makeStore()
        XCTAssertNil(store.record(payload("mine"), at: at(16, 10)), "自分の乗車券を綴じた")
        store.update { $0.enabled = false }
        XCTAssertNil(store.record(payload("p1"), at: at(16, 10)), "オフなのに綴じた")
        XCTAssertNil(store.payload, "オフなのに電波に載せる中身がある")
    }

    func testDailyLimit() async {
        let store = makeStore()
        for i in 0..<PassExchange.dailyLimit { XCTAssertNotNil(store.record(payload("p\(i)"), at: at(16, 10))) }
        XCTAssertNil(store.record(payload("over"), at: at(16, 11)), "上限を超えて綴じた")
    }

    /// 持つのは時の単位の時刻と、0.1 度に丸めた場所だけ。「夕方にまとめて受け取る」なら届くのは夕方
    func testRecordKeepsOnlyCoarseTimeAndPlace() async throws {
        let store = makeStore(delivery: .evening)
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
        XCTAssertEqual(scheduled.last?.instant, false, "夕方の束をすぐ届く形で知らせた")
        store.record(payload("p2"), at: at(16, 16))
        await waitForSchedule(2)
        XCTAssertEqual(scheduled.last?.count, 2, "知らせの枚数が書き換わらない")
    }

    /// 🔴 壊れた帳(JSON として読めない)は、空の状態で次の保存に上書きされない。`.corrupt` に退避して残し、
    /// 新しい帳を始める。`load` の退避を外すと、壊れた中身が消えて落ちる(2026-11-07)
    func testCorruptBookIsSetAsideNotOverwritten() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(OfflineTripStore.hex("me") + ".json")
        let broken = Data("{ not json".utf8)
        try broken.write(to: file)

        let store = makeStore()          // 読み込み → 設定を変えて保存
        XCTAssertTrue(store.encounters.isEmpty)
        let aside = file.appendingPathExtension("corrupt")
        XCTAssertEqual(try? Data(contentsOf: aside), broken, "壊れた帳が退避されていない(上書きで失われた)")
        let rewritten = try Data(contentsOf: file)
        XCTAssertNotEqual(rewritten, broken)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: rewritten), "新しい帳が書かれていない")

        // 退会では退避した帳も消す
        PassStore.removeData(for: "me", root: root, defaults: defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path))
    }

    /// 端末の中に残り、読み直しても同じ。**人ごとに分かれる**
    func testPersistsPerPerson() async {
        let store = makeStore()
        store.record(payload("p1"), at: at(16, 10))
        store.update { $0.note = "霧の朝" }

        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _, _ in }
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
        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _, _ in }
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
        let store = makeStore(delivery: .evening)
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
        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _, _ in }
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
        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _, _ in }
        again.use(userId: "me")
        XCTAssertEqual(again.encounters.first?.noteHidden, true, "伏せた印が残らない")
        again.setNoteHidden(card.id, false)
        XCTAssertEqual(again.encounters.first?.shownNote, "こんにちは")
    }

    /// ひとことを通報できたら印を付けて伏せる（読み直しても残る）
    func testNoteReportedHidesTheNote() async throws {
        let store = makeStore()
        let card = try XCTUnwrap(store.record(payload("p1", note: "なりすまし"), at: at(16, 10)))
        store.markNoteReported(card.id)
        XCTAssertEqual(store.encounters.first?.shownNote, "")
        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _, _ in }
        again.use(userId: "me")
        XCTAssertEqual(again.encounters.first?.noteReported, true)
        XCTAssertEqual(again.encounters.first?.noteHidden, true)
    }

    /// 相手が書いた発・着を綴じる・伏せたら自動に戻る・通報したら一緒に伏せる。自分の発・着は電波の中身に載る
    func testLabelsAreRecordedHiddenAndSent() async throws {
        let store = makeStore()
        var p = payload("p1", note: "霧")
        p.origin = "雪国"
        p.destination = "北陸"
        let card = try XCTUnwrap(store.record(p, at: at(16, 10)))
        XCTAssertEqual(card.shownOrigin, "雪国")
        XCTAssertEqual(card.shownDestination, "北陸")
        store.setLabelsHidden(card.id, true)
        XCTAssertNil(store.encounters.first?.shownOrigin, "伏せても自動に戻らない")
        store.setLabelsHidden(card.id, false)
        store.markNoteReported(card.id)
        XCTAssertNil(store.encounters.first?.shownDestination, "通報したのに区間の字が残る")
        store.update { s in
            s.setOrigin(.custom, text: "雪国\u{202E}です")
            s.destinationLabel = "金沢"
        }
        XCTAssertEqual(store.payload?.origin, "雪国です", "書いた字を整えずに載せた")
        XCTAssertEqual(store.payload?.destination, "金沢")
    }

    /// 連絡先の形の字は電波に載せない（前の版で残った字も）。届いた字に含まれていれば伏せた扱い
    func testContactsAreNeitherSentNorShown() async throws {
        let store = makeStore()
        store.update { s in
            s.note = "電話 090-1234-5678"
            s.destinationLabel = "abc.jp"
        }
        XCTAssertEqual(store.payload?.note, "", "連絡先の形のひとことを電波に載せた")
        XCTAssertEqual(store.payload?.destination, "")
        var p = payload("p1", note: "kiri@example")
        p.origin = "雪国"
        let card = try XCTUnwrap(store.record(p, at: at(16, 10)))
        XCTAssertEqual(card.shownNote, "")
        XCTAssertEqual(card.shownOrigin, "雪国")
    }

    /// 期限切れで止めた後に入り直したら、まだ届いていない束の知らせを予約し直す
    func testNoticesAreRescheduledOnSignIn() async throws {
        let store = makeStore(delivery: .evening)
        store.record(payload("p1"), at: Date().addingTimeInterval(-60))
        await waitForSchedule(1)
        scheduled = []
        store.use(userId: nil)
        store.use(userId: "me")
        await waitForSchedule(1)
        XCTAssertEqual(scheduled.count, 1, "入り直しても夕方の知らせを予約し直さない")
        XCTAssertEqual(scheduled.first?.count, 1)
    }

    // MARK: - すぐ届く（2026-11-10 owner「すれちがったら即時交換されて欲しい」）

    /// 🔴 **既定は「すぐ」**。綴じたその場で帳とホームの束に出る。届く時も時の単位（分は持たない）。
    /// 18 時を待たない（`PassExchange.deliveryDate(for:delivery:)` を夕方に戻すと落ちる）
    func testInstantIsDefaultAndVisibleRightAway() async throws {
        let store = makeStore()
        XCTAssertNil(store.settings.delivery)
        XCTAssertEqual(store.settings.deliveryMode, .instant, "既定が「すぐ」ではない")
        let before = store.arrivals
        let card = try XCTUnwrap(store.record(payload("p1"), at: at(16, 15, 42),
                                              placeName: "京都市", place: Photo.Coords(lat: 34.99487, lng: 135.78503)))
        XCTAssertEqual(card.deliverAt, at(16, 15), "届く時が時の単位になっていない（または夕方のまま）")
        XCTAssertEqual(card.metHour, at(16, 15))
        XCTAssertEqual(try XCTUnwrap(card.placeLat), 35.0, accuracy: 1e-9, "場所の粗さが変わった")
        XCTAssertEqual(store.arrivals, before + 1, "ホームに届いた合図を出していない")
        let now = at(16, 15, 43)
        store.applyResolved(all: [try photo("p1", owner: "a")], now: now)
        XCTAssertEqual(store.book(blocked: [], now: now).map(\.photoId), ["p1"], "綴じた直後に帳に出ない")
        XCTAssertEqual(store.unopened(blocked: [], now: now).map(\.photoId), ["p1"], "綴じた直後にホームの束に出ない")
        XCTAssertTrue(store.hasDelivered(now: now))
        // 18 時を過ぎても同じ日の束（次の日に回さない）・同じ相手は同じ日に1回のまま
        XCTAssertNil(store.record(payload("p1"), at: at(16, 19)), "同じ日に同じ人を2回綴じた")
        XCTAssertEqual(store.record(payload("p2"), at: at(16, 19, 5))?.deliverAt, at(16, 19))
    }

    /// 🔴 **知らせはすれちがうたびに鳴らさない**: 最初の1枚はすぐ、その後 15 分の間の分は間の終わりに1回
    /// （枚数を書き換え）。数はまだ開いていない枚数
    func testInstantNoticesAreGrouped() async {
        let store = makeStore()
        store.record(payload("p1"), at: at(16, 10, 0))
        await waitForSchedule(1)
        XCTAssertEqual(scheduled.last?.at, at(16, 10, 0), "最初の1枚をすぐ知らせない")
        XCTAssertEqual(scheduled.last?.instant, true)
        XCTAssertEqual(scheduled.last?.count, 1)
        store.record(payload("p2"), at: at(16, 10, 5))
        await waitForSchedule(2)
        XCTAssertEqual(scheduled.last?.at, at(16, 10, 15), "15 分の間にもう一度すぐ鳴らした")
        XCTAssertEqual(scheduled.last?.count, 2)
        store.record(payload("p3"), at: at(16, 10, 12))
        await waitForSchedule(3)
        XCTAssertEqual(scheduled.last?.at, at(16, 10, 15), "まだ鳴っていない予約に足さなかった")
        XCTAssertEqual(scheduled.last?.count, 3, "枚数が書き換わらない")
        // 開いた分は数えない
        store.markOpened(store.encounters.map(\.id))
        store.record(payload("p4"), at: at(16, 10, 20))
        await waitForSchedule(4)
        XCTAssertEqual(scheduled.last?.at, at(16, 10, 30))
        XCTAssertEqual(scheduled.last?.count, 1, "開いた分まで数えた")
        // 鳴らした時を覚えている（OS に起こされた起動が終わっても、次の1枚ですぐ鳴らさない）
        let again = PassStore(root: root, defaults: defaults, calendar: calendar, schedule: recorder())
        again.use(userId: "me")
        XCTAssertEqual(again.noticeAt, at(16, 10, 30), "知らせた時を帳に残していない")
        again.record(payload("p5"), at: at(16, 10, 25))
        await waitForSchedule(5)
        XCTAssertEqual(scheduled.last?.at, at(16, 10, 30))
        // 間が空けば、またすぐ
        again.record(payload("p6"), at: at(16, 11, 0))
        await waitForSchedule(6)
        XCTAssertEqual(scheduled.last?.at, at(16, 11, 0))
    }

    /// 🔴 **日をまたいでも、同じ時に鳴る知らせは1本**（確かめ役の指摘・2026-11-10）。23:55 の1枚で 00:05 に予約し、
    /// 00:02 の1枚が同じ 00:05 の予約に足すとき、識別子の日が「いま」の日だと前の日の予約と別の1本になって2回鳴る。
    /// 識別子の日は予約の時から取る（`PassStore.announceInstant`）
    func testInstantNoticeAcrossMidnightIsOneRequest() async {
        let store = makeStore()
        store.record(payload("p1"), at: at(16, 23, 50))
        store.record(payload("p2"), at: at(16, 23, 55))
        store.record(payload("p3"), at: at(17, 0, 2))
        await waitForSchedule(3)
        let late = scheduled.filter { $0.at == at(17, 0, 5) }
        XCTAssertEqual(late.count, 2, "00:05 の予約を入れ直していない")
        XCTAssertEqual(Set(late.map(\.day)).count, 1, "同じ 00:05 に識別子の違う知らせが2本（2回鳴る）")
        XCTAssertEqual(late.map(\.count).max(), 3, "枚数が書き換わらない")
    }

    /// 知らせの枚数は、ホームに出ないカード（通報した写真・ブロックした人・自分で消した写真）を数えない。
    /// 全部が出ないカードなら鳴らさない（確かめ役の指摘・2026-11-10）。持ち主は前に引いた同じ写真のカードから分かる分だけ
    func testInstantNoticeSkipsHiddenCards() async throws {
        let moderation = ModerationStore(defaults: defaults)
        moderation.use(userId: "me")
        moderation.markReported("reported", for: "me")
        moderation.block("b", for: "me")
        let store = makeStore()
        // 前の日に引いた「blocked」の写真の持ち主は b
        store.record(payload("blocked"), at: at(15, 10))
        store.applyResolved(all: [try photo("blocked", owner: "b")], now: at(15, 11))
        store.markOpened(store.encounters.map(\.id))
        await waitForSchedule(1)
        scheduled = []

        store.record(payload("reported"), at: at(16, 10, 0))
        store.record(payload("blocked"), at: at(16, 10, 1))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(scheduled.isEmpty, "ホームに出ないカードだけで知らせた")
        XCTAssertNil(store.noticeAt.flatMap { $0 >= at(16, 10) ? $0 : nil }, "鳴らしていないのに鳴らした時を進めた")
        store.record(payload("p1"), at: at(16, 10, 2))
        await waitForSchedule(1)
        XCTAssertEqual(scheduled.last?.count, 1, "見せないカードまで数えた")
        XCTAssertEqual(scheduled.last?.at, at(16, 10, 2), "見せないカードの分で間を空けた")
    }

    func testNoticeDate() async {
        let base = at(16, 10)
        XCTAssertEqual(PassExchange.noticeInterval, 15 * 60)
        XCTAssertEqual(PassExchange.noticeDate(now: base, last: nil), base)
        XCTAssertEqual(PassExchange.noticeDate(now: base, last: base.addingTimeInterval(-60)),
                       base.addingTimeInterval(14 * 60))
        XCTAssertEqual(PassExchange.noticeDate(now: base, last: base.addingTimeInterval(-15 * 60)), base)
        XCTAssertEqual(PassExchange.noticeDate(now: base, last: base.addingTimeInterval(300)), base.addingTimeInterval(300))
    }

    /// 「夕方にまとめて受け取る」を選べば今までどおり 18 時（それまでは帳にもホームにも出ない）
    func testEveningSettingKeepsTheBundle() async throws {
        let store = makeStore(delivery: .evening)
        let before = store.arrivals
        let card = try XCTUnwrap(store.record(payload("p1"), at: at(16, 15, 42)))
        XCTAssertEqual(card.deliverAt, at(16, 18))
        XCTAssertEqual(store.arrivals, before, "夕方の分でホームに届いた合図を出した")
        store.applyResolved(all: [try photo("p1", owner: "a")], now: at(16, 19))
        XCTAssertTrue(store.unopened(blocked: [], now: at(16, 17)).isEmpty, "夕方より前に出た")
        XCTAssertEqual(store.unopened(blocked: [], now: at(16, 19)).count, 1)
    }

    /// 前の版の設定（届き方の欄が無い）は「すぐ」。上げた時に夕方を待っていたカードは、読んだ時点で届いた扱い
    func testUpgradeDefaultsToInstantAndCatchesUp() async throws {
        let old = try JSONDecoder().decode(PassSettings.self, from: Data(
            #"{"enabled":true,"mode":"always","note":"","showsFrom":true}"#.utf8))
        XCTAssertEqual(old.deliveryMode, .instant, "前の版の設定が「すぐ」にならない")

        let store = makeStore(delivery: .evening)
        let now = Date()
        let card = try XCTUnwrap(store.record(payload("p1"), at: now))
        XCTAssertGreaterThan(card.deliverAt, now)
        // 前の版の帳を作る（設定から届き方の欄を消す）
        let url = root.appendingPathComponent(OfflineTripStore.hex("me") + ".json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings.removeValue(forKey: "delivery")
        json["settings"] = settings
        json.removeValue(forKey: "noticeAt")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        await waitForSchedule(1)
        scheduled = []

        let upgraded = PassStore(root: root, defaults: defaults, calendar: calendar, schedule: recorder())
        upgraded.use(userId: "me")
        XCTAssertEqual(upgraded.settings.deliveryMode, .instant)
        let moved = try XCTUnwrap(upgraded.encounters.first)
        XCTAssertLessThanOrEqual(moved.deliverAt, Date(), "夕方を待っていたカードが届かない")
        XCTAssertEqual(moved.deliverAt, moved.metHour, "届いた時が時の単位でない")
        await waitForSchedule(1)
        XCTAssertEqual(scheduled.filter(\.instant).count, 1, "届いた扱いにしたのに知らせない")
        XCTAssertTrue(scheduled.filter { !$0.instant }.isEmpty, "夕方の束をまだ予約している")
    }

    /// 夕方から「すぐ」に替えたら、待っていた分をその場で届ける
    func testSwitchingToInstantDeliversWaitingCards() async throws {
        let store = makeStore(delivery: .evening)
        let now = Date()
        store.record(payload("p1"), at: now)
        XCTAssertFalse(store.hasDelivered(now: now))
        store.update { $0.delivery = .instant }
        XCTAssertTrue(store.hasDelivered(now: Date()), "「すぐ」に替えても待たせた")
    }

    /// 説明の文: 「夕方にまとめて届く」とだけ書かない・すぐ届くこと、相手に近くにいたと分かることを書く。
    /// 知らせ（ロック画面）に名前・場所を書かない
    func testTextsSayInstantAndKeepLockScreenPlain() async {
        let point = PassPrivacyText.introPoints.map(\.text).joined()
        XCTAssertTrue(point.contains("すれちがうとすぐ届きます"), "オンにする前の説明が「すぐ」になっていない")
        XCTAssertTrue(point.contains("夕方 18 時に束でまとめて受け取ることもできます"))
        XCTAssertFalse(point.contains("その日の夕方 18 時に束でまとめて届きます"), "前の「夕方に届く」が残っている")
        XCTAssertTrue(PassPrivacyText.noteBody.contains("近くにいたことが相手に分かります"),
                      "すぐ届くと相手に分かることを書いていない")
        XCTAssertFalse(PassPrivacyText.noteBody.contains("その日の夕方にまとめて届きます"))
        XCTAssertTrue(PassPrivacyText.eveningDetail.contains("15 分に1回"))
        let body = PassBundleNotifier.instantBody(count: 3)
        XCTAssertTrue(body.contains("3 枚"))
        for word in ["のあたり", "時ごろ", "さん"] { XCTAssertFalse(body.contains(word), "知らせに \(word) が出る") }
        XCTAssertNotEqual(PassBundleNotifier.instantIdentifier(day: "2026-10-16"),
                          PassBundleNotifier.identifier(day: "2026-10-16"), "夕方の束と同じ識別子")
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
        XCTAssertFalse(store.exchangeAllowed(isForeground: true, now: at(17, 10)), "乗車券が無いのに電波を出す")
    }

    func testHomeLocation() async {
        let store = makeStore()
        store.noteHome("京都府京都市")
        XCTAssertEqual(store.homePrefecture, "京都府")
        let again = PassStore(root: root, defaults: defaults, calendar: calendar) { _, _, _, _ in }
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
