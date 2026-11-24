import XCTest
@testable import JourneyPhoto

/// ホームの上の札の、自分の写真から決まる計算を控える直し（2026-11-24・札 #594・owner「アプリ全体的に挙動重い」1.2.1）の試験。
///
/// Mac run 1779（`testUsageSurveyProbe`）で、札の並び（`home.topCard.choices`）は body のたびに 1 回 約 10ms かかっていた
/// （起動 7 回 127ms・写真の詳細の往復 19 回 217ms）。そのうち写真だけで決まる部分（一冊ができた・1年前・投稿した写真の日と位置）を、
/// 材料が変わったときだけ計算する
final class HomeTopCardPhotoMemoTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-09-27 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_790_510_400)

    private func photo(_ id: String, date: String? = nil, created: String? = nil, likes: Int? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"me\""]
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let created { fields.append("\"createdAt\":\"\(created)\"") }
        if let likes { fields.append("\"likes\":\(likes)") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 写真の組（一冊ができた・1年前・どちらも無い）
    private func photoSets() throws -> [[Photo]] {
        [
            [],
            // 2026-09-15〜17 の旅（閉じてから日が浅い → 一冊ができた）
            [try photo("a", date: "2026-09-15"), try photo("b", date: "2026-09-16"), try photo("c", date: "2026-09-17")],
            // 1年前の今ごろ（撮影日と、投稿日だけの写真）
            [try photo("y1", date: "2025-09-26", likes: 3), try photo("y2", created: "2025-09-28T09:00:00Z")],
            // 両方
            [try photo("a", date: "2026-09-15"), try photo("b", date: "2026-09-17"), try photo("y1", date: "2025-09-27")],
        ]
    }

    /// 控えから渡しても、札の並びは前（`cards` が自分で計算する）と同じ
    func testCardsWithMemoizedPhotoCardsMatchBefore() throws {
        let memo = HomeTopCardMemo()
        for photos in try photoSets() {
            for opened: Set<String> in [[], ["2026-09-15"]] {
                let before = HomeTopCard.cards(now: now, plans: [], myPhotos: photos, openedBookDays: opened, timeZone: utc)
                let key = HomeTopCardMemo.PhotoCardsKey(myPhotos: photos, openedBookDays: opened,
                                                        today: HomeTopCard.today(now, in: utc), timeZone: utc)
                let after = HomeTopCard.cards(now: now, plans: [], myPhotos: photos, openedBookDays: opened,
                                              photoCards: memo.photoCards(key), timeZone: utc)
                XCTAssertEqual(after, before, "写真 \(photos.map(\.id)) 開いた \(opened.sorted())")
            }
        }
        // 確かめ: 組の中に一冊ができた・1年前の札が本当に出ている（試験が空振りしていない）
        let all = try photoSets().flatMap { HomeTopCard.cards(now: now, plans: [], myPhotos: $0, openedBookDays: [], timeZone: utc) }
        XCTAssertTrue(all.contains { $0.slot == "bookReady" }, "一冊ができたの札が1度も出ていない")
        XCTAssertTrue(all.contains { $0.slot == "oneYearAgo" }, "1年前の札が1度も出ていない")
    }

    /// 写真・開いた印・今日が同じ間は計算し直さない。どれかが変われば計算し直す
    func testPhotoCardsAreComputedOnlyWhenTheKeyChanges() throws {
        let memo = HomeTopCardMemo()
        let photos = try photoSets()[3]
        let today = HomeTopCard.today(now, in: utc)
        let key = HomeTopCardMemo.PhotoCardsKey(myPhotos: photos, openedBookDays: [], today: today, timeZone: utc)
        for _ in 0..<10 { _ = memo.photoCards(key) }
        XCTAssertEqual(memo.photoCardsComputes, 1, "同じ材料なのに計算し直した（body のたびに一冊の棚を作っている）")
        for changed in [
            HomeTopCardMemo.PhotoCardsKey(myPhotos: Array(photos.dropLast()), openedBookDays: [], today: today, timeZone: utc),
            HomeTopCardMemo.PhotoCardsKey(myPhotos: photos, openedBookDays: ["2026-09-15"], today: today, timeZone: utc),
            HomeTopCardMemo.PhotoCardsKey(myPhotos: photos, openedBookDays: [], today: today?.addingTimeInterval(86_400),
                                          timeZone: utc),
        ] {
            let before = memo.photoCardsComputes
            _ = memo.photoCards(changed)
            XCTAssertEqual(memo.photoCardsComputes, before + 1, "材料が変わったら計算し直す")
        }
        // 今日が決まらない回は控えず nil（`cards` が自分で作る）
        XCTAssertNil(memo.photoCards(.init(myPhotos: photos, openedBookDays: [], today: nil, timeZone: utc)))
    }

    /// 投稿した写真の日と位置（現像前の旅の材料）も、写真が変わったときだけ作る。中身は前と同じ
    func testPostedShotsAreBuiltOncePerPhotos() throws {
        let memo = HomeTopCardMemo()
        let photos = try photoSets()[3]
        for _ in 0..<10 { XCTAssertEqual(memo.postedShots(photos), LibraryTrips.postedShots(of: photos)) }
        XCTAssertEqual(memo.postedShotsComputes, 1, "同じ写真なのに作り直した")
        _ = memo.postedShots(Array(photos.prefix(1)))
        XCTAssertEqual(memo.postedShotsComputes, 2, "写真が変わったら作り直す")
    }

    /// 🔴 札の画面が控えを使う（外すと body のたびに全部の写真で一冊の棚を作る）
    func testHomeTopCardViewUsesThePhotoMemo() throws {
        let view = try source("Sources/JourneyPhoto/Features/Gallery/HomeTopCardView.swift")
        XCTAssertTrue(view.contains("photoCards: memo.photoCards(.init(myPhotos: myPhotos, openedBookDays: openedBooks,"),
                      "一冊ができた・1年前を控えから渡していない")
        XCTAssertTrue(view.contains("deviceTrips.books(posted: memo.postedShots(myPhotos)"),
                      "投稿した写真の日と位置を控えから渡していない")
        XCTAssertFalse(view.contains("LibraryTrips.postedShots(of: myPhotos)"), "body のたびに投稿した写真の日と位置を作っている")
    }
}
