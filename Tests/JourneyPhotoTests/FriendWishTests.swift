import XCTest
@testable import JourneyPhoto

/// 友達が、あなたの行きたい場所で撮った（札 #710 の案9）。何度も出ない決まり5つを見張る
final class FriendWishTests: XCTestCase {

    /// 2026-11-23 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_795_435_200)
    private let kyoto = LocationSlug.make("嵐山")

    private func photo(_ id: String, owner: String, location: String = "嵐山", daysAgo: Double = 1,
                       audience: String? = nil) throws -> Photo {
        let created = ISO8601DateFormatter().string(from: now.addingTimeInterval(-daysAgo * 86_400))
        var obj: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg", "userId": owner,
                                  "location": location, "createdAt": created, "displayName": owner]
        if let audience { obj["audience"] = audience }
        return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    private func hits(_ photos: [Photo], keys: Set<String>? = nil, muted: Set<String> = []) -> [FriendWish.Hit] {
        FriendWish.hits(photos: photos, following: ["mika", "aoi"], me: "me", keys: keys ?? [kyoto], spots: [],
                        muted: muted, now: now)
    }

    /// フォロー中の人の、7日以内の、全体に公開の写真だけ。自分の写真は出さない（決まり3）
    func testCandidates() throws {
        let photos = [
            try photo("a", owner: "mika", daysAgo: 1),
            try photo("old", owner: "mika", daysAgo: 8),
            try photo("stranger", owner: "someone", daysAgo: 1),
            try photo("mine", owner: "me", daysAgo: 1),
            try photo("closed", owner: "aoi", daysAgo: 1, audience: "followers"),
            try photo("elsewhere", owner: "aoi", location: "白川郷", daysAgo: 1),
        ]
        XCTAssertEqual(hits(photos).map(\.photo.id), ["a"])
        XCTAssertEqual(hits(photos).first?.place, "嵐山")
    }

    /// 行きたい場所から外した場所では出さない（決まり5）
    func testRemovedWishIsNotShown() throws {
        XCTAssertTrue(hits([try photo("a", owner: "mika")], keys: []).isEmpty)
    }

    /// 同じ人と同じ場所の組は1回だけ（決まり1）。1日に1枚まで・同じ日は同じ札（決まり2）
    func testOncePerPairAndOnePerDay() throws {
        let list = hits([try photo("new", owner: "mika", daysAgo: 0.5), try photo("older", owner: "aoi", daysAgo: 2)])
        var state = FriendWish.State()
        let first = try XCTUnwrap(FriendWish.pick(list, state: state, today: "2026-11-23"))
        XCTAssertEqual(first.photo.id, "new", "いちばん新しい写真")
        state = FriendWish.record(first, state: state, today: "2026-11-23")
        XCTAssertEqual(FriendWish.pick(list, state: state, today: "2026-11-23")?.photo.id, "new", "同じ日は同じ札")
        let next = try XCTUnwrap(FriendWish.pick(list, state: state, today: "2026-11-24"))
        XCTAssertEqual(next.photo.id, "older", "出した組（mika と嵐山）は2回出さない")
        state = FriendWish.record(next, state: state, today: "2026-11-24")
        XCTAssertNil(FriendWish.pick(list, state: state, today: "2026-11-25"))
        // 同じ人の同じ場所の別の写真も出さない
        let again = hits([try photo("another", owner: "mika", daysAgo: 0.1)])
        XCTAssertNil(FriendWish.pick(again, state: state, today: "2026-11-25"))
    }

    /// 今日の1枚が当たらなくなったら（外した・消えた）、その日はほかの札を出さない（1日に1枚まで）
    func testTodaysPickGoneMeansNothing() throws {
        let list = hits([try photo("a", owner: "mika"), try photo("b", owner: "aoi")])
        var state = FriendWish.State()
        state = FriendWish.record(list[0], state: state, today: "2026-11-23")
        XCTAssertNil(FriendWish.pick(Array(list.dropFirst()), state: state, today: "2026-11-23"))
    }

    /// 「この知らせは出さない」でその人の分は以後出さない（決まり4）
    func testMutedPerson() throws {
        let state = FriendWish.mute("mika", state: .init())
        XCTAssertTrue(hits([try photo("a", owner: "mika")], muted: Set(state.muted)).isEmpty)
        XCTAssertEqual(hits([try photo("b", owner: "aoi")], muted: Set(state.muted)).count, 1)
    }

    /// 写真の詳細の1行: 人の、全体に公開の写真で、行きたい場所に当たるときだけ（数は増えない）
    func testDetailLine() throws {
        XCTAssertEqual(FriendWish.wishedKey(of: try photo("a", owner: "mika"), keys: [kyoto], spots: [], me: "me"), kyoto)
        XCTAssertNil(FriendWish.wishedKey(of: try photo("m", owner: "me"), keys: [kyoto], spots: [], me: "me"))
        XCTAssertNil(FriendWish.wishedKey(of: try photo("c", owner: "aoi", audience: "closeFriends"), keys: [kyoto],
                                          spots: [], me: "me"))
    }

    /// 言葉の候補は3つで、押すと欄に入るだけ（送る口は1つ・DMPhotoSend）
    func testSuggestions() throws {
        XCTAssertEqual(FriendWish.suggestions.count, 3)
        XCTAssertEqual(FriendWish.suggestionChips.count, 3)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto/Features/Gallery/FriendWishViews.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("Button { text = line }"), "候補を押したら欄に入るだけ")
        XCTAssertEqual(text.components(separatedBy: "DMPhotoSend.send(").count - 1, 1, "送るのは送るボタンの1か所だけ")
        // 保存・書き出しの道を作らない
        for word in ["UIImageWriteToSavedPhotosAlbum", "ShareLink", "PHPhotoLibrary", "fileExporter"] {
            XCTAssertFalse(text.contains(word), "人の写真を持ち出す道: \(word)")
        }
    }

    /// ホームの札の並び: ログインした人だけ。旅の札の後ろ
    func testHomeTopCardSlot() throws {
        let hit = try XCTUnwrap(hits([try photo("a", owner: "mika")]).first)
        XCTAssertEqual(HomeTopCard.Choice.friendWish(hit).slot, "friendWish")
        XCTAssertFalse(HomeTopCard.priority(for: .guest).contains("friendWish"))
        let regular = HomeTopCard.priority(for: .regular)
        XCTAssertLessThan(try XCTUnwrap(regular.firstIndex(of: "friendWish")), try XCTUnwrap(regular.firstIndex(of: "theme")))
        let cards = HomeTopCard.cards(now: now, plans: [], myPhotos: [], openedBookDays: [], friendWish: hit)
        let arranged = HomeTopCard.arrange(cards, audience: .regular)
        XCTAssertTrue(arranged.contains(.friendWish(hit)))
    }

    /// 投稿日を読む読み手は1回だけ作って使い回す（写真ごとに作らない）。小数の秒も読める
    func testDateFormattersAreShared() {
        XCTAssertTrue(FriendWish.plainFormatter === FriendWish.plainFormatter)
        XCTAssertTrue(FriendWish.fractionalFormatter === FriendWish.fractionalFormatter, "使うたびに読み手を作っている")
        XCTAssertNotNil(FriendWish.date("2026-11-23T12:00:00Z"))
        XCTAssertNotNil(FriendWish.date("2026-11-23T12:00:00.123Z"))
        XCTAssertNil(FriendWish.date("きのう"))
    }
}
