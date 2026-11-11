import XCTest
@testable import JourneyPhoto

/// おすすめに新しい投稿を混ぜる（`HomeFreshMix`・札 #537 案1・2026-11-11）。
///
/// 🔴 **入力と答えは Web の `lib/utils/__tests__/homeFeed.freshMix.test.ts` と同じ。** 片方だけ決まりを変えると、
/// アプリと Web でおすすめの並びが割れる。変えるときは両方の試験を一緒に直す
final class HomeFreshMixTests: XCTestCase {

    /// 試験の「今」（2026-11-11 12:00 UTC）
    private let now = NotificationGroups.parse("2026-11-11T12:00:00.000Z")!

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
        let arranged = HomeFeed.recommended.arrange(try caseOne(), now: now).map(\.id)
        XCTAssertEqual(arranged, ["A", "N1", "B", "C", "N4", "D", "N3", "N2", "G", "F", "E", "O", "H"])
    }

    /// 混ぜる前（今までの並び）では、いいね0の新しい投稿は9番目より後ろに沈んでいた
    func testWithoutMixFreshPostsSink() throws {
        let base = GallerySort.popular.apply(try caseOne()).map(\.id)
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
        XCTAssertEqual(HomeFeed.recommended.arrange(photos, now: now).map(\.id), ["X", "p2", "p1", "Q", "R", "S"])
    }

    /// 日付だけ（時刻・ゾーンの無い）`createdAt` は新しい投稿にしない（Web と読み方をそろえる）。新しい投稿が無ければ並びは今までどおり
    func testDateOnlyIsNotFreshAndNothingMoves() throws {
        let photos = [
            try photo("A", likes: 3, at: "2026-01-01T00:00:00.000Z", user: "u1"),
            try photo("B", likes: 2, at: "2026-02-01T00:00:00.000Z", user: "u1"),
            try photo("today", likes: 0, at: "2026-11-11", user: "u2"),
        ]
        XCTAssertEqual(HomeFeed.recommended.arrange(photos, now: now).map(\.id), ["A", "B", "today"])
    }

    /// 「新着」「フォロー中」は混ぜない（新しい順のまま）
    func testOnlyRecommendedMixes() throws {
        let arranged = HomeFeed.latest.arrange(try caseOne(), now: now).map(\.id)
        XCTAssertEqual(arranged, ["N1", "N4", "N2", "N3", "O", "H", "G", "F", "E", "D", "C", "B", "A"])
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

    /// 印は札の読み上げにも入る（色・形だけで伝えない）
    func testFirstPostIsReadAloud() {
        let text = HomeTileText.readout(base: "写真", place: "", byline: "名前", multiple: nil,
                                        firstPost: HomeTileText.firstPost)
        XCTAssertTrue(text.contains(HomeTileText.firstPost))
    }

    /// UI テストの見本（`PreviewSNSLoopSample`）: 新しい3枚が新しい投稿になり、1枚目ははじめての投稿、
    /// 2枚が今週のお題の参加になる（Mac の絵 10n・10o が撮れる状態）
    func testPreviewSampleMakesEveryStateVisible() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let photos = try caseOne()
        let stamped = PreviewSNSLoopSample.stamp(photos, now: now, calendar: calendar)
        XCTAssertEqual(stamped.count, photos.count)
        let fresh = stamped.filter { HomeFreshMix.isFresh($0, now: now) }.map(\.id)
        XCTAssertEqual(Set(fresh), ["N1", "N4", "N2", "N3"], "見本の後も新しい投稿が4つ（新しい3枚＋もとから新しい1枚）")
        XCTAssertTrue(HomeFreshMix.firstPostPhotoIds(stamped, now: now).contains("N1"))
        let theme = WeeklyTheme.current(now, calendar: calendar)
        XCTAssertEqual(WeeklyTheme.participants(theme, photos: stamped, now: now, calendar: calendar).map(\.id), ["N1", "N4"])
    }
}
