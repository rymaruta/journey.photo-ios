import XCTest
@testable import JourneyPhoto

/// おすすめに新しい投稿を混ぜる（`HomeFreshMix`・札 #537 案1・2026-11-11）。
///
/// 🔴 **入力と答えは Web の `lib/utils/__tests__/homeFeed.freshMix.test.ts` と同じ。** 片方だけ決まりを変えると、
/// アプリと Web でおすすめの並びが割れる。変えるときは両方の試験を一緒に直す
final class HomeFreshMixTests: XCTestCase {

    /// 試験の「今」（2026-11-11 12:00 UTC）
    private let now = NotificationGroups.parse("2026-11-11T12:00:00.000Z")!

    /// 「おすすめ」の並びに新しい投稿を混ぜたもの（Web の `recommendedOrder` と同じ入力と答え）
    private func mixed(_ photos: [Photo]) -> [String] {
        HomeFreshMix.mix(HomeFeed.recommended.arrange(photos), now: now).map(\.id)
    }

    private func photo(_ id: String, likes: Int = 0, at createdAt: String, user: String,
                       group: String? = nil, featured: Bool = false) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"createdAt\":\"\(createdAt)\"",
                      "\"likes\":\(likes)", "\"userId\":\"\(user)\""]
        if let group { fields.append("\"groupId\":\"\(group)\"") }
        if featured { fields.append("\"featured\":true") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 例1（Web と同じ）: 古い写真がいいね順に並ぶ中に、72 時間以内の投稿が4つ
    private func caseOne() throws -> [Photo] {
        [
            try photo("A", likes: 5, at: "2026-01-20T00:00:00.000Z", user: "u1"),
            try photo("B", likes: 4, at: "2026-02-01T00:00:00.000Z", user: "u1"),
            try photo("C", likes: 3, at: "2026-03-01T00:00:00.000Z", user: "u1"),
            try photo("D", likes: 2, at: "2026-04-01T00:00:00.000Z", user: "u2"),
            try photo("E", likes: 1, at: "2026-05-01T00:00:00.000Z", user: "u2"),
            try photo("F", likes: 1, at: "2026-06-01T00:00:00.000Z", user: "u2"),
            try photo("G", likes: 1, at: "2026-07-01T00:00:00.000Z", user: "u1"),
            try photo("H", likes: 0, at: "2026-08-01T00:00:00.000Z", user: "u1"),
            // 72 時間以内（6・12・36・60 時間前）
            try photo("N1", likes: 0, at: "2026-11-11T06:00:00.000Z", user: "u3"),
            try photo("N4", likes: 0, at: "2026-11-11T00:00:00.000Z", user: "u4"),
            try photo("N2", likes: 0, at: "2026-11-10T00:00:00.000Z", user: "u2"),
            try photo("N3", likes: 1, at: "2026-11-09T00:00:00.000Z", user: "u1"),
            // 73 時間前（新しい投稿ではない）
            try photo("O", likes: 0, at: "2026-11-08T11:00:00.000Z", user: "u2"),
        ]
    }

    /// **先頭 10 枠の 2・5・8 番目に新しい投稿が入る。** N3 はいいね1で今までの並びでも7番目に来るので、
    /// 枠を使わずそこに出る。4つ目の新しい投稿（N2）が8番目に入る
    func testMixesFreshPostsIntoSlotsTwoFiveEight() throws {
        let arranged = mixed(try caseOne())
        XCTAssertEqual(arranged, ["A", "N1", "B", "C", "N4", "D", "N3", "N2", "G", "F", "E", "O", "H"])
    }

    /// 混ぜる前（今までの並び）では、いいね0の新しい投稿は9番目より後ろに沈んでいた
    func testWithoutMixFreshPostsSink() throws {
        let base = HomeFeed.recommended.arrange(try caseOne()).map(\.id)
        XCTAssertEqual(base, ["A", "B", "C", "D", "N3", "G", "F", "E", "N1", "N4", "N2", "O", "H"])
    }

    /// 例2（Web と同じ）: 選ばれた写真は先頭のまま。**同じ投稿の2枚は1つの枠**（束ねて1枚の札になる）。
    /// 新しい投稿が足りない枠（5番目）は今までの並び
    func testFeaturedStaysFirstAndPostsCountOnce() throws {
        let photos = [
            try photo("Q", likes: 2, at: "2026-03-01T00:00:00.000Z", user: "u1"),
            try photo("X", likes: 0, at: "2026-01-01T00:00:00.000Z", user: "u2", featured: true),
            try photo("R", likes: 1, at: "2026-04-01T00:00:00.000Z", user: "u1"),
            try photo("S", likes: 0, at: "2026-05-01T00:00:00.000Z", user: "u2"),
            try photo("p1", likes: 0, at: "2026-11-11T10:00:00.000Z", user: "u5", group: "g"),
            try photo("p2", likes: 0, at: "2026-11-11T10:00:01.000Z", user: "u5", group: "g"),
        ]
        XCTAssertEqual(mixed(photos), ["X", "p2", "p1", "Q", "R", "S"])
    }

    /// 日付だけ（時刻・ゾーンの無い）`createdAt` は新しい投稿にしない（Web と読み方をそろえる）。新しい投稿が無ければ並びは今までどおり
    func testDateOnlyIsNotFreshAndNothingMoves() throws {
        let photos = [
            try photo("A", likes: 3, at: "2026-01-01T00:00:00.000Z", user: "u1"),
            try photo("B", likes: 2, at: "2026-02-01T00:00:00.000Z", user: "u1"),
            try photo("today", likes: 0, at: "2026-11-11", user: "u2"),
        ]
        XCTAssertEqual(mixed(photos), ["A", "B", "today"])
    }

    /// 「新着」「フォロー中」は混ぜない（新しい順のまま）
    func testOnlyRecommendedMixes() throws {
        XCTAssertTrue(HomeFeed.recommended.mixesFresh)
        XCTAssertFalse(HomeFeed.latest.mixesFresh)
        XCTAssertFalse(HomeFeed.following.mixesFresh)
        let rows = HomeFeedPageMemo.make(.latest, photos: HomeFeed.latest.arrange(try caseOne()),
                                         hidden: ModerationSnapshot(), now: now)
        XCTAssertEqual(rows.groups.map(\.cover.id), ["N1", "N4", "N2", "N3", "O", "H", "G", "F", "E", "D", "C", "B", "A"])
    }

    /// 🔴 **混ぜるのは絞り込みとブロックの後**（札 #537 の確かめ役・2026-11-11・Web の `useGallery` と同じ順）。
    /// カテゴリで絞った・ブロックした後の一覧でも、新しい投稿が 2・5・8 番目に来る。
    /// 並び（`arrange`）の段で混ぜると、落ちた写真の分だけ枠がずれる（N1 が 3 番目になる）
    func testMixesAfterFilteringAndBlocking() throws {
        func p(_ id: String, _ likes: Int, _ at: String, _ user: String, _ category: String = "y") throws -> Photo {
            try JSONDecoder.api.decode(Photo.self, from: Data(
                "{\"id\":\"\(id)\",\"src\":\"https://x/\(id).jpg\",\"createdAt\":\"\(at)\",\"likes\":\(likes),\"userId\":\"\(user)\",\"category\":\"\(category)\"}".utf8))
        }
        let all = [
            try p("A", 5, "2026-01-20T00:00:00.000Z", "u1", "x"),
            try p("B", 4, "2026-02-01T00:00:00.000Z", "u1"),
            try p("C", 3, "2026-03-01T00:00:00.000Z", "u1"),
            try p("D", 2, "2026-04-01T00:00:00.000Z", "bad"),
            try p("E", 1, "2026-05-01T00:00:00.000Z", "u2"),
            try p("F", 1, "2026-06-01T00:00:00.000Z", "u2"),
            try p("G", 1, "2026-07-01T00:00:00.000Z", "u1"),
            try p("H", 0, "2026-08-01T00:00:00.000Z", "u1"),
            try p("Z", 0, "2026-11-11T11:00:00.000Z", "bad"),
            try p("N1", 0, "2026-11-11T06:00:00.000Z", "u3"),
            try p("N2", 0, "2026-11-11T00:00:00.000Z", "u4"),
            try p("N3", 0, "2026-11-10T00:00:00.000Z", "u5"),
        ]
        // 画面と同じ順: 並べる → 絞る（カテゴリ y）→ 控えがブロックを落として混ぜる
        let filtered = HomeFeed.recommended.arrange(all).filter { $0.category == "y" }
        let rows = HomeFeedPageMemo.make(.recommended, photos: filtered,
                                         hidden: ModerationSnapshot(blocked: ["bad"], reported: []), now: now)
        XCTAssertEqual(rows.groups.map(\.cover.id), ["B", "N1", "C", "G", "N2", "F", "E", "N3", "H"])
        // 並べる段では混ぜない（混ぜると、絞る前の枠で新しい投稿の場所が決まる）
        XCTAssertEqual(HomeFeed.recommended.arrange(all).map(\.id).prefix(2), ["A", "B"])
    }

    /// **はじめての投稿**: 持ち主のいちばん古い公開の投稿が 72 時間以内なら、その投稿の写真全部（例1・例2 と同じ人）
    func testFirstPostIds() throws {
        let photos = try caseOne() + [
            try photo("p1", likes: 0, at: "2026-11-11T10:00:00.000Z", user: "u5", group: "g"),
            try photo("p2", likes: 0, at: "2026-11-11T10:00:01.000Z", user: "u5", group: "g"),
        ]
        // u3・u4・u5 は初めて。u1・u2 は前から載せている（N2・N3 は2枚目以降）
        XCTAssertEqual(HomeFreshMix.firstPostPhotoIds(photos, now: now), ["N1", "N4", "p1", "p2"])
        // 72 時間を過ぎたら印は消える
        let later = now.addingTimeInterval(72 * 60 * 60)
        XCTAssertEqual(HomeFreshMix.firstPostPhotoIds(photos, now: later), [])
    }

    /// 🔴 **持ち主に `createdAt` の読めない写真が1枚でもあれば、印を付けない**（安全側・札 #537 の確かめ役・Web と同じ）。
    /// 読めない写真のほうが古いかもしれない
    func testFirstPostSkipsOwnersWithUnreadableDates() throws {
        let photos = [
            try photo("new", at: "2026-11-11T06:00:00.000Z", user: "u9"),
            try photo("undated", at: "2026-11-11", user: "u9"),
            try photo("other", at: "2026-11-11T07:00:00.000Z", user: "u8"),
        ]
        XCTAssertEqual(HomeFreshMix.firstPostPhotoIds(photos, now: now), ["other"])
    }

    /// 印は札の読み上げにも入る（色・形だけで伝えない）
    func testFirstPostIsReadAloud() {
        let text = HomeTileText.readout(base: "写真", place: "", byline: "名前", multiple: nil,
                                        firstPost: HomeTileText.firstPost)
        XCTAssertTrue(text.contains(HomeTileText.firstPost))
    }

    /// UI テストの見本（`PreviewSNSLoopSample`）: 新しい3枚が新しい投稿になり、1枚目ははじめての投稿、
    /// 2枚が今週のお題の参加になる（Mac の絵 10n・10o が撮れる状態）
    func testPreviewSampleMakesEveryStateVisible() throws {
        let photos = try caseOne()
        let stamped = PreviewSNSLoopSample.stamp(photos, now: now)
        XCTAssertEqual(stamped.count, photos.count)
        let fresh = stamped.filter { HomeFreshMix.isFresh($0, now: now) }.map(\.id)
        XCTAssertEqual(Set(fresh), ["N1", "N4", "N2", "N3"], "見本の後も新しい投稿が4つ（新しい3枚＋もとから新しい1枚）")
        XCTAssertTrue(HomeFreshMix.firstPostPhotoIds(stamped, now: now).contains("N1"))
        let theme = WeeklyTheme.current(now)
        XCTAssertEqual(WeeklyTheme.participants(theme, photos: stamped, now: now).map(\.id), ["N1", "N4"])
    }
}
