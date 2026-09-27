import XCTest
@testable import JourneyPhoto

/// 探すの種類チップと発見の段（板 11）。
final class SearchScopeTests: XCTestCase {

    private func photo(_ fields: [String: Any]) throws -> Photo {
        var row = fields
        row["src"] = "https://x/\(fields["id"] ?? "").jpg"
        let data = try JSONSerialization.data(withJSONObject: row)
        return try JSONDecoder.api.decode(Photo.self, from: data)
    }

    private func sample() throws -> [Photo] {
        [
            // 撮影地に「冬」を含むが、タグには無い
            try photo(["id": "place", "location": "冬の湖", "tags": ["lake"]]),
            // タグに「冬」
            try photo(["id": "tag", "location": "札幌", "tags": ["冬"]]),
            // 題にだけ「冬」
            try photo(["id": "title", "title": "冬の朝"]),
            // 何も持たない
            try photo(["id": "bare"]),
        ]
    }

    func testAllAndPhotosMatchEveryField() throws {
        let photos = try sample()
        XCTAssertEqual(SearchScope.all.photos(photos, query: "冬").map(\.id), ["place", "tag", "title"])
        XCTAssertEqual(SearchScope.photos.photos(photos, query: "冬").map(\.id), ["place", "tag", "title"])
    }

    /// **タグはタグだけ、撮影地は撮影地だけに当てる**
    func testTagsAndPlacesLookOnlyAtTheirField() throws {
        let photos = try sample()
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "冬").map(\.id), ["tag"])
        XCTAssertEqual(SearchScope.places.photos(photos, query: "冬").map(\.id), ["place"])
    }

    /// 大文字小文字・全角半角は区別しない（`PhotoQuery.match` と同じ）
    func testFoldsCaseAndWidth() throws {
        let photos = [try photo(["id": "a", "location": "Paris", "tags": ["Night"]])]
        XCTAssertEqual(SearchScope.places.photos(photos, query: "ＰＡＲＩＳ").map(\.id), ["a"])
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "night").map(\.id), ["a"])
    }

    /// 打っていないとき: タグ／撮影地は**その欄を持つ写真だけ**、すべて・写真は全部
    func testEmptyQueryKeepsPhotosThatHaveTheField() throws {
        let photos = try sample()
        XCTAssertEqual(SearchScope.all.photos(photos, query: " ").count, 4)
        XCTAssertEqual(SearchScope.photos.photos(photos, query: "").count, 4)
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "").map(\.id), ["place", "tag"])
        XCTAssertEqual(SearchScope.places.photos(photos, query: "").map(\.id), ["place", "tag"])
    }

    /// 人を選んだら写真は出さない。人を出すのは すべて と 人 だけ
    func testPeopleScopeShowsNoPhotos() throws {
        XCTAssertTrue(SearchScope.people.photos(try sample(), query: "冬").isEmpty)
        XCTAssertEqual(SearchScope.allCases.filter(\.showsPeople), [.all, .people])
        XCTAssertEqual(SearchScope.allCases.map(\.label),
                       [L("すべて", "All"), L("写真", "Photos"), L("人", "People"),
                        L("タグ", "Tags"), L("撮影地", "Places")])
    }

    /// **人の種類では写真の結果（と並び替えの札）を出さない**（人の結果は並べ替えが効かない）。
    /// 案内も人向けに
    func testPeopleScopeHidesSortAndAsksForAName() {
        XCTAssertFalse(SearchScope.people.showsPhotos)
        XCTAssertEqual(SearchScope.allCases.filter(\.showsPhotos), [.all, .photos, .tags, .places])
        XCTAssertNotEqual(SearchScope.people.prompt, SearchScope.photos.prompt)
        XCTAssertEqual(SearchScope.people.prompt, L("人を検索（名前）", "Search people"))
        XCTAssertEqual(SearchScope.all.prompt, L("写真を検索（題・説明・タグなど）", "Search photos"))
    }

    /// **撮影地ではタグのチップを出さない。** 押すとタグの語が撮影地に当たり、
    /// チップの枚数と結果の枚数が合わない
    func testTagChipsAreHiddenForPlacesAndPeople() throws {
        XCTAssertEqual(SearchScope.allCases.filter(\.showsTagChips), [.all, .photos, .tags])
        // 食い違いの実例: タグ「冬」の写真は1枚だが、撮影地で「冬」を探すと別の1枚が出る
        let photos = try sample()
        XCTAssertNotEqual(SearchScope.places.photos(photos, query: "冬").map(\.id),
                          SearchScope.tags.photos(photos, query: "冬").map(\.id))
    }

    // MARK: - 段

    /// 板 11 の並び: 注目 → おすすめ → 色 → 季節 → 機材。無い段は飛ばす
    func testDiscoveryOrderFollowsBoard() {
        XCTAssertEqual(SearchDiscovery.sections(present: Set(SearchDiscovery.Section.allCases)),
                       [.spots, .featured, .colors, .seasonal, .gear])
        XCTAssertEqual(SearchDiscovery.sections(present: [.gear, .seasonal, .colors]),
                       [.colors, .seasonal, .gear])
    }

    /// おすすめは**ホームと同じ塊の先頭**（owner が選んだ公開写真が多いカテゴリ）
    func testFeaturedPicksLargestGroup() throws {
        let photos = [
            try photo(["id": "a", "featured": true, "category": "風景"]),
            try photo(["id": "b", "featured": true, "category": "街"]),
            try photo(["id": "c", "featured": true, "category": "街"]),
            try photo(["id": "d", "featured": false, "category": "風景"]),
        ]
        let group = try XCTUnwrap(SearchDiscovery.featured(in: photos))
        XCTAssertEqual(Set(group.photos.map(\.id)), ["b", "c"])
        XCTAssertNil(SearchDiscovery.featured(in: [try photo(["id": "x", "category": "街"])]))
    }
}
