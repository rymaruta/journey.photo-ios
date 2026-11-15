import XCTest
@testable import JourneyPhoto

/// ホームの並びに新しい投稿を混ぜる（`HomeFreshMix`・札 #537 案1・2026-11-11。2026-11-15 に1本の並び（札 #595）へ載せ替えた）。
///
/// 🔴 **入力と答えは Web の `lib/utils/__tests__/homeFeed.freshMix.test.ts` と同じ。** 片方だけ決まりを変えると、
/// アプリと Web でおすすめの並びが割れる。変えるときは両方の試験を一緒に直す
final class HomeFreshMixTests: XCTestCase {

    /// 試験の「今」（2026-11-11 12:00 UTC）
    private let now = NotificationGroups.parse("2026-11-11T12:00:00.000Z")!

    /// 「おすすめ」の並びに新しい投稿を混ぜたもの（Web の `recommendedOrder` と同じ入力と答え）
    private func mixed(_ photos: [Photo]) -> [String] {
        HomeFreshMix.mix(HomeFeed.recommended(photos), now: now).map(\.id)
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
        let base = HomeFeed.recommended(try caseOne()).map(\.id)
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

    /// 1本の並び（札 #595）の控え（`HomeFeedPageMemo.make`）が、並べた後に混ぜる。**先頭 10 枠の 2・5・8 番目は
    /// 72 時間以内の投稿**（新しい順）。新着の「4つめごとに1つ」だけでは、載せる人が少ない今は新着の枠にも
    /// 古い写真が来て、新しい投稿が1画面目に届かない
    func testSingleFeedPutsFreshPostsIntoSlotsTwoFiveEight() throws {
        let all = try caseOne()
        let latest = GallerySort.new.apply(all)
        let input = HomeFeedPageMemo.Input(following: [], recommended: HomeFeed.recommended(all), latest: latest,
                                           latestHasMore: false, excluding: [], now: now)
        let rows = HomeFeedPageMemo.make(input, hidden: ModerationSnapshot())
        let ids = (rows.lead + rows.rest).map(\.cover.id)
        XCTAssertEqual(ids.count, all.count, "混ぜても写真の数は変わらない")
        XCTAssertEqual(Set(ids), Set(all.map(\.id)))
        XCTAssertEqual([ids[1], ids[4], ids[7]], ["N1", "N4", "N2"], "2・5・8 番目が新しい投稿（新しい順）でない: \(ids)")
        let fresh = Set(all.filter { HomeFreshMix.isFresh($0, now: now) }.map(\.id))
        XCTAssertTrue(fresh.isSubset(of: Set(ids.prefix(HomeFreshMix.span))), "72 時間以内の投稿が1画面目（先頭 10）に無い: \(ids)")
        // 混ぜる前（並べただけ）は、2 番目に古い写真が来ていた（＝この決まりが無いと落ちる）
        let plain = HomeFeedPageMemo.make(HomeFeedPageMemo.Input(following: [], recommended: HomeFeed.recommended(all),
                                                                 latest: latest, latestHasMore: false, excluding: []),
                                          hidden: ModerationSnapshot())
        XCTAssertNotEqual((plain.lead + plain.rest).map(\.cover.id)[1], "N1", "混ぜない入力でも混ざった")
    }

    /// 🔴 **混ぜるのはブロック・通報を落とした後**（札 #537 の確かめ役・2026-11-11・Web の `useGallery` と同じ順）。
    /// ブロックした人の写真が先頭にあっても、新しい投稿は 2・5・8 番目に来る（落ちた分だけ枠がずれない）。
    /// 上の段（フォロー中の人の新しい写真）は混ぜない
    func testSingleFeedMixesAfterBlockingAndLeavesFollowingAlone() throws {
        func p(_ id: String, _ likes: Int, _ at: String, _ user: String) throws -> Photo {
            try photo(id, likes: likes, at: at, user: user)
        }
        let all = [
            try p("Z", 9, "2026-11-11T11:00:00.000Z", "bad"),
            try p("A", 5, "2026-01-20T00:00:00.000Z", "u1"),
            try p("B", 4, "2026-02-01T00:00:00.000Z", "u1"),
            try p("C", 3, "2026-03-01T00:00:00.000Z", "u1"),
            try p("D", 2, "2026-04-01T00:00:00.000Z", "u2"),
            try p("E", 1, "2026-05-01T00:00:00.000Z", "u2"),
            try p("F", 1, "2026-06-01T00:00:00.000Z", "u2"),
            try p("G", 1, "2026-07-01T00:00:00.000Z", "u1"),
            try p("H", 0, "2026-08-01T00:00:00.000Z", "u1"),
            try p("N1", 0, "2026-11-11T06:00:00.000Z", "u3"),
            try p("N2", 0, "2026-11-11T00:00:00.000Z", "u4"),
            try p("N3", 0, "2026-11-10T00:00:00.000Z", "u5"),
            try p("F1", 0, "2026-11-11T09:00:00.000Z", "friend"),
        ]
        let friend = all.filter { $0.userId == "friend" }
        let input = HomeFeedPageMemo.Input(following: friend, recommended: HomeFeed.recommended(all),
                                           latest: GallerySort.new.apply(all), latestHasMore: false, excluding: [], now: now)
        let rows = HomeFeedPageMemo.make(input, hidden: ModerationSnapshot(blocked: ["bad"], reported: []))
        XCTAssertEqual(rows.following.map(\.cover.id), ["F1"], "上の段が変わった")
        let ids = (rows.lead + rows.rest).map(\.cover.id)
        XCTAssertFalse(ids.contains("Z"), "ブロックした人の写真が並んだ")
        XCTAssertFalse(ids.contains("F1"), "上の段の写真が並びにも出た")
        XCTAssertEqual([ids[1], ids[4], ids[7]], ["N1", "N2", "N3"], "ブロックの後で枠がずれた: \(ids)")
    }

    /// 画面は全件を読んだ時刻を「今」として渡す（描くたびの時刻にすると、見ている間に並びが動く）
    func testGalleryPassesTheLoadClock() throws {
        let gallery = try String(contentsOf: sourceURL("Features/Gallery/GalleryView.swift"), encoding: .utf8)
        XCTAssertTrue(gallery.contains("now: model.freshClock),"), "並びに「今」を渡していない（既定は混ぜない）")
        XCTAssertTrue(gallery.contains("HomeFreshMix.mix(arranged.main, now: $0)"), "並べた後に混ぜていない")
        XCTAssertTrue(gallery.contains("let firstPosts = model.firstPostIds()"), "はじめての投稿を数えていない")
        XCTAssertEqual(gallery.components(separatedBy: "firstPostIds: firstPosts)").count - 1, 3,
                       "はじめての投稿の印を、上の段・ひと回り・その後ろの3つの並びに渡していない")
    }

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto").appendingPathComponent(path)
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
