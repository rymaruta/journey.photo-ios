import XCTest
@testable import JourneyPhoto

/// 行きたい場所に行けた（札 #710 の案1）。「行った」は保存せず、自分の写真と鍵を毎回突き合わせて導く
final class WishVisitTests: XCTestCase {

    private func photo(_ id: String, location: String? = nil, spotId: String? = nil,
                       date: String? = nil, createdAt: String? = nil) throws -> Photo {
        var obj: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg"]
        if let location { obj["location"] = location }
        if let spotId { obj["spotId"] = spotId }
        if let date { obj["date"] = date }
        if let createdAt { obj["createdAt"] = createdAt }
        return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    private func spot(_ slug: String, name: String) throws -> OfficialSpot {
        try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name)\",\"stage\":\"published\"}".utf8))
    }

    /// 撮影地の鍵も、観光スポットの鍵（`SPOT-<slug>`）も「行った」になる。行っていない鍵は入らない
    func testVisitsMatchBothKindsOfKeys() throws {
        let index = [try spot("hogonin", name: "宝厳院")]
        let mine = [
            try photo("a", location: "嵐山", createdAt: "2026-11-20T00:00:00Z"),
            try photo("b", location: "嵐山", createdAt: "2026-11-23T00:00:00Z"),
            try photo("c", spotId: "sp_hogonin", createdAt: "2026-11-22T00:00:00Z"),
        ]
        let keys: Set<String> = [LocationSlug.make("嵐山"), "SPOT-hogonin", "SPOT-fushimi", "shirakawago"]
        let visits = WishVisit.visits(keys: keys, mine: mine, spots: index)
        XCTAssertEqual(Set(visits.keys), [LocationSlug.make("嵐山"), "SPOT-hogonin"])
        XCTAssertEqual(visits[LocationSlug.make("嵐山")]?.id, "b", "いちばん新しい自分の写真を出す")
        XCTAssertEqual(visits["SPOT-hogonin"]?.id, "c")
    }

    /// 行きたい場所に入れていない場所の写真では「行った」にしない（鍵が無ければ空）
    func testNoKeysNoVisits() throws {
        XCTAssertTrue(WishVisit.visits(keys: [], mine: [try photo("a", location: "嵐山")], spots: []).isEmpty)
        XCTAssertTrue(WishVisit.visits(keys: ["kyoto"], mine: [], spots: []).isEmpty)
    }

    /// 見出しの横の進み具合。0 は出さない
    func testProgressText() {
        XCTAssertNil(WishVisit.progress(visited: 0, total: 3))
        XCTAssertEqual(WishVisit.progress(visited: 1, total: 3), L("1 / 3 行った", "1 / 3 visited"))
    }

    /// 行の2行目は撮影日で言う。中黒で区切らない
    func testRowLineUsesTakenDay() throws {
        let line = WishVisit.rowLine(try photo("a", date: "2026-11-23"))
        XCTAssertEqual(line, L("行った\u{3000}11月23日、あなたの1枚", "Visited\u{2002}11/23, your photo"))
        XCTAssertFalse(line.contains("・") || line.contains("·"))
    }

    /// 投稿の知らせ: 行きたい場所の写真なら「行きたい場所に行けました」と場所の名前。
    /// 同じ場所の2枚目から（もう知らせた鍵）は通常の知らせ（nil）
    func testNoticeOnlyOncePerPlace() throws {
        let index = [try spot("hogonin", name: "宝厳院")]
        let posted = [try photo("p", spotId: "sp_hogonin")]
        let first = PostedPlaceNotice.make(posted: posted, wishKeys: ["SPOT-hogonin"], spots: index, announced: [])
        XCTAssertEqual(first?.notice.title, WishVisit.noticeTitle)
        XCTAssertEqual(first?.notice.detail, "宝厳院")
        XCTAssertEqual(first?.wishKey, "SPOT-hogonin")
        XCTAssertNil(PostedPlaceNotice.make(posted: posted, wishKeys: ["SPOT-hogonin"], spots: index,
                                            announced: ["SPOT-hogonin"]),
                     "同じ場所の2枚目からは通常の「投稿しました」に戻す")
        XCTAssertNil(PostedPlaceNotice.make(posted: posted, wishKeys: [], spots: index, announced: []))
    }

    /// 🔴 「投稿しました」を待たせない（2026-11-23 確かめ役の指摘）: 行きたい場所の鍵が無く、最初の1枚でもない回は
    /// 索引を読まずにすぐ nil。観光スポットの鍵が無ければ索引は読まない。読むときも短い上限まで
    @MainActor
    func testResolveReadsTheIndexOnlyWhenNeeded() async throws {
        final class Count: @unchecked Sendable { var n = 0 }
        let memory = WishVisitMemory(defaults: UserDefaults(suiteName: "WishVisitTests.\(UUID().uuidString)")!)
        let calls = Count()
        let index = [try spot("hogonin", name: "宝厳院")]
        let fetch: @Sendable () async -> [OfficialSpot]? = { calls.n += 1; return index }
        let onSpot = [try photo("p", spotId: "sp_hogonin")]
        // 鍵も最初の1枚も無い: 読まずに nil
        let none = await PostedPlaceNotice.resolve(posted: onSpot, wishKeys: [], spot: nil, postedToSpot: 0,
                                                   ownerId: "a", known: [], memory: memory, fetch: fetch)
        XCTAssertNil(none)
        XCTAssertEqual(calls.n, 0, "言い替えが起こりえないのに索引を読んだ")
        // 起こりえない回は索引の判断にも入らずすぐ返す（`mayApply` の早道）
        XCTAssertFalse(PostedPlaceNotice.mayApply(wishKeys: [], spot: nil, postedToSpot: 0))
        XCTAssertTrue(PostedPlaceNotice.mayApply(wishKeys: ["SPOT-hogonin"], spot: nil, postedToSpot: 0))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let center = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Core/Storage/PostUploadCenter.swift"),
                                encoding: .utf8)
        XCTAssertTrue(center.contains("guard mayApply(wishKeys: wishKeys, spot: spot, postedToSpot: postedToSpot) else { return nil }"),
                      "言い替えが起こりえない回の早道が無い")
        // 撮影地の鍵だけ: 索引は読まない
        let located = await PostedPlaceNotice.resolve(posted: [try photo("q", location: "白川郷")],
                                                      wishKeys: [LocationSlug.make("白川郷")], spot: nil, postedToSpot: 0,
                                                      ownerId: "a", known: [], memory: memory, fetch: fetch)
        XCTAssertEqual(located?.detail, "白川郷")
        XCTAssertEqual(calls.n, 0, "撮影地の鍵だけなのに索引を読んだ")
        // 最初の1枚: 索引は読まない
        var target = UploadSpotTarget(spotId: "sp_hogonin", name: "宝厳院", coords: nil)
        target.announcesFirst = true
        let first = await PostedPlaceNotice.resolve(posted: onSpot, wishKeys: [], spot: target, postedToSpot: 1,
                                                    ownerId: "a", known: [], memory: memory, fetch: fetch)
        XCTAssertEqual(first?.title, FirstPhoto.postedTitle("宝厳院"))
        XCTAssertEqual(calls.n, 0)
        // 投稿の画面が読んでいた索引があれば、それを使う
        let fromKnown = await PostedPlaceNotice.resolve(posted: onSpot, wishKeys: ["SPOT-hogonin"], spot: nil, postedToSpot: 0,
                                                        ownerId: "b", known: index, memory: memory, fetch: fetch)
        XCTAssertEqual(fromKnown?.detail, "宝厳院")
        XCTAssertEqual(calls.n, 0, "手元の索引があるのに読み直した")
        // 観光スポットの鍵と観光スポットの写真: 読む
        let fetched = await PostedPlaceNotice.resolve(posted: onSpot, wishKeys: ["SPOT-hogonin"], spot: nil, postedToSpot: 0,
                                                      ownerId: "c", known: [], memory: memory, fetch: fetch)
        XCTAssertEqual(fetched?.title, WishVisit.noticeTitle)
        XCTAssertEqual(calls.n, 1)
    }

    /// 索引が返ってこなくても、上限で通常の知らせに倒れる（長く待たない）
    @MainActor
    func testResolveGivesUpOnASlowIndex() async throws {
        let memory = WishVisitMemory(defaults: UserDefaults(suiteName: "WishVisitTests.\(UUID().uuidString)")!)
        let onSpot = [try photo("p", spotId: "sp_hogonin")]
        let started = Date()
        let made = await PostedPlaceNotice.resolve(posted: onSpot, wishKeys: ["SPOT-hogonin"], spot: nil, postedToSpot: 0,
                                                   ownerId: "a", known: [], memory: memory, wait: .milliseconds(100),
                                                   fetch: { try? await Task.sleep(nanoseconds: 5_000_000_000); return nil })
        XCTAssertNil(made)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "索引の待ちに上限が効いていない")
        XCTAssertLessThanOrEqual(PostedPlaceNotice.indexWait, .seconds(2), "知らせを待たせる上限が長い")
    }

    /// 撮影地の鍵の名前は撮影地の表示
    func testNoticeNamesLocation() throws {
        let posted = [try photo("p", location: "白川郷")]
        let made = PostedPlaceNotice.make(posted: posted, wishKeys: [LocationSlug.make("白川郷")], spots: [], announced: [])
        XCTAssertEqual(made?.notice.detail, "白川郷")
    }

    /// 知らせた鍵の控え（人ごと・同じ鍵は重ねない）
    func testMemoryIsPerUser() {
        let defaults = UserDefaults(suiteName: "WishVisitTests.\(UUID().uuidString)")!
        let memory = WishVisitMemory(defaults: defaults)
        memory.note(["a", "b", "a"], for: "u1")
        XCTAssertEqual(memory.announced(for: "u1"), ["a", "b"])
        XCTAssertTrue(memory.announced(for: "u2").isEmpty)
        XCTAssertTrue(memory.announced(for: nil).isEmpty)
        memory.removeAll(for: "u1")
        XCTAssertTrue(memory.announced(for: "u1").isEmpty)
    }

    /// 2行の知らせ: 2行目を持ち、空の2行目は付けない
    @MainActor
    func testToastDetailLine() async {
        let toasts = ToastCenter()
        toasts.show("行きたい場所に行けました", detail: "宝厳院")
        XCTAssertEqual(toasts.current?.detail, "宝厳院")
        toasts.show("投稿しました", detail: "  ")
        XCTAssertNil(toasts.current?.detail)
    }
}
