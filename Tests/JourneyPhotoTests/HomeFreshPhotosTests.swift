import XCTest
@testable import JourneyPhoto

/// ホームの「みんなの新しい写真」の段（2026-10-21・全画面の点検）。
///
/// 🔴 点検で、ホームの最初の画面に**利用者が投稿した写真が1枚も無い**と分かった（出典付きの作例だけ）。
/// 公開一覧から、フォロー中の人 → 新着 → 自分の順に、投稿（束）ごとに1つ並べる。下書きは出さない。
/// 1巡目は1人2つまで・溢れた分は後ろで埋める。ブロック・通報は呼ぶ側が先に落とす。
/// 段はストーリーの列のすぐ下・上の札と作例の棚より上に置く
final class HomeFreshPhotosTests: XCTestCase {

    private func photo(_ id: String, owner: String?, at date: String, group: String? = nil,
                       published: Bool? = nil, name: String? = nil, location: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"createdAt\":\"\(date)\""]
        if let owner { fields.append("\"userId\":\"\(owner)\"") }
        if let group { fields.append("\"groupId\":\"\(group)\"") }
        if let published { fields.append("\"published\":\(published)") }
        if let name { fields.append("\"displayName\":\"\(name)\"") }
        if let location { fields.append("\"location\":\"\(location)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func ids(_ photos: [Photo], viewerId: String? = nil, following: Set<String> = []) -> [String] {
        HomeFreshPhotos.groups(photos, viewerId: viewerId, followingIds: following).map(\.cover.id)
    }

    /// 未ログインでも公開の写真が新しい順に並ぶ（初めて入れた人にも見える）。下書きは出さない
    func testSignedOutSeesPublicPhotosNewestFirst() throws {
        let photos = [
            try photo("old", owner: "a", at: "2026-01-01"),
            try photo("draft", owner: "b", at: "2026-09-01", published: false),
            try photo("new", owner: "b", at: "2026-05-01"),
        ]
        XCTAssertEqual(ids(photos), ["new", "old"])
    }

    /// 🔴 ログインしていれば、フォロー中の人の写真が先（古くても）。自分の写真は最後
    func testFollowingFirstThenOthersThenMine() throws {
        let photos = [
            try photo("mine", owner: "me", at: "2026-10-01"),
            try photo("stranger", owner: "x", at: "2026-09-01"),
            try photo("friend", owner: "f", at: "2026-01-01"),
        ]
        XCTAssertEqual(ids(photos, viewerId: "me", following: ["f"]), ["friend", "stranger", "mine"])
        // 未ログインならフォローの並べ替えはしない（ただの新しい順）
        XCTAssertEqual(ids(photos, viewerId: nil, following: ["f"]), ["mine", "stranger", "friend"])
    }

    /// 🔴 同じ投稿は1つの束（段には表紙）。**束ごと渡す**——開いた詳細で同じ投稿の残りへ送れる
    func testOneGroupPerPostKeepsTheWholePost() throws {
        let photos = [
            try photo("p1", owner: "a", at: "2026-05-01T00:00:01Z", group: "g"),
            try photo("p2", owner: "a", at: "2026-05-01T00:00:02Z", group: "g"),
            try photo("p3", owner: "a", at: "2026-05-01T00:00:03Z", group: "g"),
            try photo("solo", owner: "b", at: "2026-04-01"),
        ]
        let groups = HomeFreshPhotos.groups(photos, viewerId: nil, followingIds: [])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups[0].photos.map(\.id)), ["p1", "p2", "p3"], "同じ投稿の残りが束に無い")
        XCTAssertTrue(groups[0].isMultiple)
        XCTAssertEqual(groups[1].cover.id, "solo")
        XCTAssertFalse(groups[1].isMultiple)
    }

    /// 🔴 1巡目は1人2つまで（順は保つ）。溢れた分は同じ順で後ろへ足し、**枚数は減らさない**
    func testFourFromOnePersonAndOneOther() throws {
        let photos = [
            try photo("a1", owner: "a", at: "2026-05-05"),
            try photo("a2", owner: "a", at: "2026-05-04"),
            try photo("a3", owner: "a", at: "2026-05-03"),
            try photo("a4", owner: "a", at: "2026-05-02"),
            try photo("b1", owner: "b", at: "2026-05-01"),
        ]
        XCTAssertEqual(ids(photos), ["a1", "a2", "b1", "a3", "a4"])
    }

    /// 上限は1巡目と溢れた分を合わせて数える（1人だけでも上限まで埋まる）
    func testLimitCountsOverflowAndEmptyIsEmpty() throws {
        let photos = try (0..<30).map { try photo("p\($0)", owner: "a", at: String(format: "2026-01-%02d", $0 % 28 + 1)) }
        XCTAssertEqual(ids(photos).count, HomeFreshPhotos.limit)
        XCTAssertTrue(ids([], viewerId: "me", following: ["f"]).isEmpty)
    }

    /// ブロックした人の写真は、**数を切る前に**落とせば段に残らない（表と同じ写しを使う）
    func testBlockedPhotosAreDroppedBeforeTheLimit() throws {
        var photos = try (0..<HomeFreshPhotos.limit).map { try photo("bad\($0)", owner: "blocked", at: "2026-09-01") }
        photos.append(try photo("ok", owner: "a", at: "2026-01-01"))
        let snapshot = ModerationSnapshot(blocked: ["blocked"])
        XCTAssertEqual(ids(snapshot.visible(photos)), ["ok"])
    }

    /// 写真の下の字は作者 → 撮影地 → 無し
    func testByline() throws {
        XCTAssertEqual(HomeFreshPhotos.byline(try photo("a", owner: "a", at: "2026-01-01", name: "ゆき", location: "京都")), "ゆき")
        XCTAssertEqual(HomeFreshPhotos.byline(try photo("b", owner: "a", at: "2026-01-01", name: " ", location: "京都")), "京都")
        XCTAssertNil(HomeFreshPhotos.byline(try photo("c", owner: "a", at: "2026-01-01")))
    }

    // MARK: - ホームの並び

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 🔴 段はストーリーの列のすぐ下・上の札（作例の棚を含む）より上。ブロックの写しで落とし、0件なら出さない
    func testStripSitsAboveTheSpotCardsOnHome() throws {
        let view = try source("Sources/JourneyPhoto/Features/Gallery/GalleryView.swift")
        let stories = try XCTUnwrap(view.range(of: "StoriesRow(reloadToken:"))
        let strip = try XCTUnwrap(view.range(of: "HomeFreshStrip(groups:", range: stories.upperBound..<view.endIndex),
                                  "ストーリーの下に「みんなの新しい写真」の段が無い")
        let cards = try XCTUnwrap(view.range(of: "HomeTopCardView(", range: stories.upperBound..<view.endIndex))
        XCTAssertLessThan(strip.lowerBound, cards.lowerBound, "段が上の札・作例の棚より下にある")
        let between = String(view[stories.upperBound..<strip.lowerBound])
        XCTAssertTrue(between.contains("model.freshGroups(viewerId: auth.userId, hiding: dropped)"),
                      "ブロック・通報の写しで落としていない（か、描くたびに作っている）")
        XCTAssertTrue(between.contains("if !fresh.isEmpty"), "0件でも段を出している")
    }

    /// 🔴 段から開いた詳細の前後は同じ投稿の写真・2枚以上なら印（`HomeMosaic` と同じ形）
    func testStripOpensTheWholePost() throws {
        let strip = try source("Sources/JourneyPhoto/Features/Gallery/HomeFreshStrip.swift")
        XCTAssertTrue(strip.contains("PhotoDetailView(photo: group.cover, context: group.photos)"),
                      "開いた詳細で同じ投稿の残りへ行けない")
        XCTAssertTrue(strip.contains("isMultiple: group.isMultiple"), "複数枚の投稿の印が無い")
    }
}
