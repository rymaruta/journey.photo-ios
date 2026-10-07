import XCTest
@testable import JourneyPhoto

/// 板 12（タグ・色・機材の写真）の画面を持たない部分。
final class CollectionScreenTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
    }

    override func tearDown() {
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    private func photo(_ fields: [String: Any]) throws -> Photo {
        var row = fields
        row["src"] = "https://x/\(fields["id"] ?? "").jpg"
        let data = try JSONSerialization.data(withJSONObject: row)
        return try JSONDecoder.api.decode(Photo.self, from: data)
    }

    // MARK: - 撮影日の並び

    /// 撮った日の新しい順。`date` を先に見て、無ければ EXIF。
    /// **EXIF はアプリ（`2026:09:19 …`）と Web（`2026-09-19T…`）で綴りが違う**
    func testTakenSortsByShootingDayAcrossBothExifSpellings() throws {
        let photos = [
            try photo(["id": "date", "date": "2025-03-01"]),
            try photo(["id": "appExif", "exif": ["dateTimeOriginal": "2026:09:19 08:21:05"]]),
            try photo(["id": "webExif", "exif": ["dateTimeOriginal": "2026-01-02T10:00:00"]]),
        ]
        XCTAssertEqual(GallerySort.taken.apply(photos).map(\.id), ["appExif", "webExif", "date"])
    }

    /// **撮影日を持たない写真は末尾。** 投稿が新しくても前に出さない
    func testTakenPutsUndatedLastEvenIfNewlyPosted() throws {
        let photos = [
            try photo(["id": "none", "createdAt": "2026-09-20T00:00:00Z"]),
            try photo(["id": "old", "date": "2019-05-05", "createdAt": "2020-01-01T00:00:00Z"]),
        ]
        XCTAssertEqual(GallerySort.taken.apply(photos).map(\.id), ["old", "none"])
    }

    /// `date` が EXIF より優先（owner が直した日を信じる）
    func testTakenPrefersEditedDateOverExif() throws {
        let photos = [
            try photo(["id": "edited", "date": "2020-01-01",
                       "exif": ["dateTimeOriginal": "2026:09:19 08:21:05"]]),
            try photo(["id": "other", "date": "2024-01-01"]),
        ]
        XCTAssertEqual(GallerySort.taken.apply(photos).map(\.id), ["other", "edited"])
    }

    /// ホーム・検索のメニューは Web の `FilterBar` と同じ3つのまま。
    /// 集約の一覧のチップは板 12 の3つ
    func testChoicesPerScreen() {
        XCTAssertEqual(GallerySort.feedChoices, [.new, .old, .popular])
        XCTAssertEqual(GallerySort.collectionChoices, [.popular, .new, .taken])
    }

    // MARK: - 見出しと先頭の1枚

    func testSubtitleCountsAndAddsNote() {
        XCTAssertEqual(CollectionScreen.subtitle(count: 12, note: L("いまの季節", "This season")),
                       "\(L("12枚", "12 photos")) · \(L("いまの季節", "This season"))")
        XCTAssertEqual(CollectionScreen.subtitle(count: 3, note: "  "), L("3枚", "3 photos"))
        XCTAssertEqual(CollectionScreen.subtitle(count: 3, note: nil), L("3枚", "3 photos"))
    }

    /// **読み込み中は枚数を出さない**（まだ数えていないのに「0枚」と言わない）
    func testSubtitleHidesCountWhileLoading() {
        XCTAssertEqual(CollectionScreen.subtitle(count: 0, note: nil, isLoading: true), "")
        XCTAssertEqual(CollectionScreen.subtitle(count: 0, note: L("焦点距離 〜35mm", "〜35mm"), isLoading: true),
                       L("焦点距離 〜35mm", "〜35mm"))
        XCTAssertEqual(CollectionScreen.subtitle(count: 0, note: nil, isLoading: false), L("0枚", "0 photos"))
    }

    /// 大きい字は撮影地、無ければ題、どちらも無ければ出さない
    func testLeadHeadlinePrefersPlaceThenTitle() throws {
        XCTAssertEqual(CollectionScreen.leadHeadline(try photo(["id": "a", "location": " 山中湖 ",
                                                                "title": "朝"])), "山中湖")
        XCTAssertEqual(CollectionScreen.leadHeadline(try photo(["id": "b", "title": "朝"])), "朝")
        XCTAssertNil(CollectionScreen.leadHeadline(try photo(["id": "c"])))
    }

    /// **名前が無い写真に「@ユーザー」を出さない**
    func testLeadAuthorOnlyWithRealName() throws {
        XCTAssertEqual(CollectionScreen.leadAuthor(try photo(["id": "a", "displayName": "luzhj"])), "@luzhj")
        XCTAssertNil(CollectionScreen.leadAuthor(try photo(["id": "b", "displayName": " "])))
        XCTAssertNil(CollectionScreen.leadAuthor(try photo(["id": "c"])))
    }

    // MARK: - シェア

    /// 撮影地は Web の集約ページを指す（`LocationSlug` の綴り）
    func testShareOfLocationPointsToItsPage() throws {
        let lead = try photo(["id": "p1"])
        let text = CollectionScreen.shareText(title: "パリ", count: 3, kind: .location("パリ, フランス"),
                                              lead: lead, photos: [lead])
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "パリ · \(L("3枚", "3 photos"))")
        XCTAssertEqual(lines.last.flatMap { URL(string: $0) }?.path, "/location/パリ,-フランス")
    }

    /// **タグは綴りを当て推量しない**（Web には別名の表がある）。先頭の写真のページを添える
    func testShareOfTagFallsBackToLeadPhoto() throws {
        let lead = try photo(["id": "p1"])
        let text = CollectionScreen.shareText(title: "#秋", count: 2, kind: .tag("秋"),
                                              lead: lead, photos: [lead])
        XCTAssertTrue(text.hasSuffix("https://site.example.test/photo/p1"), text)
        XCTAssertNil(CollectionScreen.pageURL(.tag("秋"), photos: [lead]))
        XCTAssertNil(CollectionScreen.pageURL(nil, photos: [lead]))
    }

    func testShareWithoutPhotosHasNoLink() {
        let text = CollectionScreen.shareText(title: L("青", "Blue"), count: 0, kind: nil, lead: nil, photos: [])
        XCTAssertFalse(text.contains("http"))
    }

    /// 🔴 **下書き・限定写真だけの撮影地に `/location/<スラッグ>` を付けない**（Web に建たない・2026-10-07）。
    /// `SpotScreen.locationPageURL` と同じ決まり。公開の写真が1枚あれば付ける
    func testLocationPageOnlyWithPublicPhotos() throws {
        let draft = try photo(["id": "d", "location": "パリ", "published": false])
        let limited = try photo(["id": "r", "location": "パリ", "audience": "followers"])
        let open = try photo(["id": "o", "location": "パリ"])
        XCTAssertNil(CollectionScreen.pageURL(.location("パリ"), photos: [draft, limited]))
        XCTAssertNil(CollectionScreen.pageURL(.location("パリ"), photos: []))
        XCTAssertEqual(CollectionScreen.pageURL(.location("パリ"), photos: [draft, open])?.path, "/location/パリ")
        let text = CollectionScreen.shareText(title: "パリ", count: 1, kind: .location("パリ"),
                                              lead: CollectionScreen.shareLead([draft]), photos: [draft])
        XCTAssertFalse(text.contains("http"), "開けないリンクを配っている: \(text)")
    }

    /// 🔴 **下書き・限定写真の詳細から撮影地を押すと、その写真自身が並ぶ**（空の一覧にしない・2026-10-07）。
    /// 公開の写真は足さない（公開の一覧から来る）・もう並んでいれば重ねない・撮影地が当たらなければ足さない
    func testOpenedPrivatePhotoJoinsItsLocationList() throws {
        let draft = try photo(["id": "d", "location": "パリ", "published": false])
        let limited = try photo(["id": "r", "location": "パリ", "audience": "followers"])
        let open = try photo(["id": "o", "location": "パリ"])
        let kind = PhotoQuery.Collection.location("パリ")
        XCTAssertEqual(CollectionScreen.withOpened([], opened: draft, kind: kind).map(\.id), ["d"])
        XCTAssertEqual(CollectionScreen.withOpened([open], opened: limited, kind: kind).map(\.id), ["r", "o"])
        XCTAssertEqual(CollectionScreen.withOpened([open], opened: draft, kind: kind).map(\.id), ["d", "o"])
        XCTAssertEqual(CollectionScreen.withOpened([draft], opened: draft, kind: kind).map(\.id), ["d"])
        XCTAssertEqual(CollectionScreen.withOpened([], opened: open, kind: kind).map(\.id), [],
                       "公開の写真は一覧から来る（消された写真を残さない）")
        XCTAssertEqual(CollectionScreen.withOpened([], opened: draft, kind: .location("京都")).map(\.id), [])
        XCTAssertEqual(CollectionScreen.withOpened([open], opened: nil, kind: kind).map(\.id), ["o"])
    }
}
