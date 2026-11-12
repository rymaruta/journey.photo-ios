import XCTest
@testable import JourneyPhoto

/// ①「フィルムを現像するみたいに」（2026-11-12・札 #543）の決まり（`DevelopTrips`・`DevelopProgressStore`）。
final class DevelopTripsTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    /// 2026-09-12 00:00 JST
    private let base = Date(timeIntervalSince1970: 1_789_138_800)
    private let home = (lat: 35.68, lng: 139.76)
    private let kanazawa = (lat: 36.56, lng: 136.65)

    /// 金沢の3日の旅（1日4枚・9時から2時間おき）。`startDay` は 9/12 からの日数
    private func trip(startDay: Int = 0, prefix: String = "k") -> LibraryTrip {
        var shots: [LibraryShot] = []
        for d in 0..<3 {
            for k in 0..<4 {
                let hours = Double((startDay + d) * 24 + 9 + k * 2)
                shots.append(LibraryShot(id: "\(prefix)\(d)-\(k)", date: base.addingTimeInterval(hours * 3600),
                                         lat: kanazawa.lat, lng: kanazawa.lng))
            }
        }
        return LibraryTrips.find(shots, home: home, timeZone: tokyo)[0]
    }

    /// 旅の最後の日（9/14）から `days` 日後の昼
    private func after(_ trip: LibraryTrip, days: Int) -> Date {
        trip.end.addingTimeInterval(Double(days) * 86_400)
    }

    // MARK: - 札に出す旅

    /// 終わった翌日から7日目まで出す。当日（旅の最中かもしれない）と8日目は出さない
    func testCardShowsFromNextDayForSevenDays() {
        let t = trip()
        XCTAssertNil(DevelopTrips.candidate(books: [t], now: after(t, days: 0), closed: [], timeZone: tokyo),
                     "旅の最後の日のうちに札を出した（まだ旅の最中かもしれない）")
        XCTAssertEqual(DevelopTrips.candidate(books: [t], now: after(t, days: 1), closed: [], timeZone: tokyo)?.id, t.id)
        XCTAssertEqual(DevelopTrips.candidate(books: [t], now: after(t, days: 7), closed: [], timeZone: tokyo)?.id, t.id)
        XCTAssertNil(DevelopTrips.candidate(books: [t], now: after(t, days: 8), closed: [], timeZone: tokyo),
                     "終わって8日目も札を出した（7日まで）")
    }

    /// 閉じた旅（「この旅は出さない」・投稿した）は出さない
    func testClosedTripIsNotShown() {
        let t = trip()
        XCTAssertNil(DevelopTrips.candidate(books: [t], now: after(t, days: 2), closed: [t.id], timeZone: tokyo))
    }

    /// いちばん新しく終わった旅だけを見る（古い旅の札を後から出さない）
    func testOnlyTheLatestTrip() {
        let old = trip(startDay: 0, prefix: "a")
        let new = trip(startDay: 5, prefix: "b")
        XCTAssertEqual(DevelopTrips.candidate(books: [old, new], now: after(new, days: 1), closed: [],
                                              timeZone: tokyo)?.id, new.id)
        // 新しい旅を閉じても、古い旅を代わりに出さない
        XCTAssertNil(DevelopTrips.candidate(books: [old, new], now: after(new, days: 1), closed: [new.id],
                                            timeZone: tokyo))
    }

    /// 投稿した日がある旅は棚（`DeviceTrips.books`）で落ちているので札にも出ない
    func testPostedTripDropsOutViaShelf() {
        let t = trip()
        let posted = [LibraryTrips.PostedShot(key: "2026-09-13", coords: nil)]
        let books = DeviceTrips.books([t], posted: posted, zones: [:], isMine: true)
        XCTAssertNil(DevelopTrips.candidate(books: books, now: after(t, days: 1), closed: [], timeZone: tokyo))
    }

    /// コマは今の自動の選び方の10枚（日ごとにばらける）
    func testFramesAreSpreadPickOfTen() {
        let t = trip()
        XCTAssertEqual(DevelopTrips.frames(of: t), LibraryTrips.spreadPick(t, limit: 10))
        XCTAssertEqual(DevelopTrips.frames(of: t).count, 10)
    }

    // MARK: - 払う判定（章: 110pt 以上、または 30pt 以上を 0.6pt/ms 以上で）

    func testSwipeDecision() {
        XCTAssertEqual(DevelopTrips.decide(dx: 110, velocity: 0), .keep)
        XCTAssertEqual(DevelopTrips.decide(dx: -110, velocity: 0), .skip)
        XCTAssertNil(DevelopTrips.decide(dx: 109, velocity: 0), "足りない払いで決めた")
        XCTAssertEqual(DevelopTrips.decide(dx: 30, velocity: 600), .keep, "勢いの払いが通らない")
        XCTAssertEqual(DevelopTrips.decide(dx: -30, velocity: -600), .skip)
        XCTAssertNil(DevelopTrips.decide(dx: 29, velocity: 2000), "30pt に届かない勢いで決めた")
        XCTAssertNil(DevelopTrips.decide(dx: 60, velocity: 599))
        // 右へ動かして左へ速く戻した（向きの合わない勢い）は決めない
        XCTAssertNil(DevelopTrips.decide(dx: 40, velocity: -900))
    }

    /// 色は右へ払うときだけ戻る（0 → 120pt で 0 → 1）
    func testColorReturnsOnlyToTheRight() {
        XCTAssertEqual(DevelopTrips.colorAmount(dx: 0), 0)
        XCTAssertEqual(DevelopTrips.colorAmount(dx: 60), 0.5, accuracy: 0.0001)
        XCTAssertEqual(DevelopTrips.colorAmount(dx: 200), 1)
        XCTAssertEqual(DevelopTrips.colorAmount(dx: -80), 0)
    }

    // MARK: - 払い終えたあと

    func testNextIndexAndKept() {
        let frames = ["a", "b", "c", "d"]
        let decisions: [String: DevelopTrips.Decision] = ["a": .keep, "b": .skip]
        XCTAssertEqual(DevelopTrips.nextIndex(frames, decisions: decisions), 2, "途中で閉じた続きのコマが違う")
        XCTAssertEqual(DevelopTrips.kept(frames, decisions: decisions), ["a"])
        let all: [String: DevelopTrips.Decision] = ["a": .keep, "b": .skip, "c": .keep, "d": .keep]
        XCTAssertEqual(DevelopTrips.nextIndex(frames, decisions: all), 4)
        XCTAssertEqual(DevelopTrips.kept(frames, decisions: all), ["a", "c", "d"])
    }

    /// 表紙を先頭に、残りは旅の並び。表紙が載せたコマに無ければそのまま
    func testUploadOrderPutsCoverFirst() {
        XCTAssertEqual(DevelopTrips.uploadOrder(kept: ["a", "c", "d"], cover: "c"), ["c", "a", "d"])
        XCTAssertEqual(DevelopTrips.uploadOrder(kept: ["a", "c", "d"], cover: nil), ["a", "c", "d"])
        XCTAssertEqual(DevelopTrips.uploadOrder(kept: ["a", "c"], cover: "z"), ["a", "c"])
    }

    func testTexts() {
        let t = trip()
        XCTAssertEqual(DevelopTrips.coverEyebrow(t), "TRIP · 9.12 – 9.14")
        let day = DevelopTrips.day(of: "k1-0", in: t)
        XCTAssertEqual(day?.number, 2)
        XCTAssertEqual(DevelopTrips.counter(index: 3, total: 10, day: day, place: "金沢市"), "4 / 10 · DAY 2 · 金沢市")
        XCTAssertEqual(DevelopTrips.counter(index: 3, total: 10, day: day, place: nil), "4 / 10 · DAY 2 · 9.13")
    }

    // MARK: - 端末の控え

    func testProgressStoreKeepsAndCloses() {
        let suite = "develop.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DevelopProgressStore(defaults: defaults)
        let now = Date()
        store.save(DevelopProgress(decisions: ["a": .keep], updatedAt: now), trip: "t1", for: "u1", now: now)
        XCTAssertEqual(store.progress("t1", for: "u1")?.decisions["a"], .keep)
        XCTAssertNil(store.progress("t1", for: "u2"), "別の人の控えが見えた")
        XCTAssertTrue(store.closed(for: "u1").isEmpty)
        store.close("t1", for: "u1", now: now)
        XCTAssertEqual(store.closed(for: "u1"), ["t1"])
        XCTAssertEqual(store.progress("t1", for: "u1")?.decisions["a"], .keep, "閉じたら払った結果まで消えた")
        store.reopen("t1", for: "u1", now: now)
        XCTAssertTrue(store.closed(for: "u1").isEmpty)
    }

    /// 30日より古い控えは消す（端末に溜めない）
    func testProgressStorePrunesOldEntries() {
        let suite = "develop.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DevelopProgressStore(defaults: defaults)
        let now = Date()
        store.save(DevelopProgress(updatedAt: now), trip: "old", for: "u1", now: now.addingTimeInterval(-31 * 86_400))
        store.save(DevelopProgress(updatedAt: now), trip: "new", for: "u1", now: now)
        XCTAssertNil(store.progress("old", for: "u1"))
        XCTAssertNotNil(store.progress("new", for: "u1"))
    }

    // MARK: - ホームの札の並び

    /// 現像前の旅は旅の札の並び（今日のテーマより前）。種類を足すだけ
    func testHomeCardsIncludeDevelop() {
        let t = trip()
        let cards = HomeTopCard.cards(now: after(t, days: 1), plans: [], myPhotos: [], openedBookDays: [],
                                      develop: .develop(trip: t, name: "金沢市"), timeZone: tokyo)
        XCTAssertEqual(cards.first?.slot, "develop")
        XCTAssertTrue(cards.contains { $0.slot == "theme" })
        let without = HomeTopCard.cards(now: after(t, days: 1), plans: [], myPhotos: [], openedBookDays: [],
                                        timeZone: tokyo)
        XCTAssertFalse(without.contains { $0.slot == "develop" })
    }
}

/// 待ってから実行する1件（取り消しの札の中身・`CountdownUndo`）
@MainActor
final class CountdownUndoTests: XCTestCase {

    /// 取り消したら実行しない
    func testUndoCancels() async {
        let undo = CountdownUndo()
        var fired = 0
        undo.schedule("x", seconds: 0.05) { fired += 1 }
        XCTAssertEqual(undo.message, "x")
        undo.undo()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(fired, 0, "取り消したのに実行した")
        XCTAssertNil(undo.message)
    }

    /// 時間が来たら1回だけ実行する（取り消せる間は実行しない）
    func testFiresOnceAfterDelay() async {
        let undo = CountdownUndo()
        var fired = 0
        undo.schedule("x", seconds: 0.05) { fired += 1 }
        XCTAssertEqual(fired, 0, "取り消せる間に実行した")
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(fired, 1)
        undo.finishNow()
        XCTAssertEqual(fired, 1, "二度実行した")
    }

    /// 次を始めたら前はいま済ませる（積まない）
    func testNextScheduleFinishesPrevious() async {
        let undo = CountdownUndo()
        var log: [String] = []
        undo.schedule("a", seconds: 10) { log.append("a") }
        undo.schedule("b", seconds: 10) { log.append("b") }
        XCTAssertEqual(log, ["a"])
        XCTAssertEqual(undo.message, "b")
        undo.undo()
        XCTAssertEqual(log, ["a"])
    }
}
