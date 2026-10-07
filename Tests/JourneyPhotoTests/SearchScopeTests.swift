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

    /// 2026-10-07: 検索欄の案内は「題・説明・タグなど」なのに、説明を探していなかった
    func testAllAndPhotosMatchTheDescription() throws {
        let photos = try sample() + [
            try photo(["id": "desc", "title": "朝", "description": ["ja": "雪の残る冬の湖畔で"]]),
            try photo(["id": "desc2", "description": "ＴＡＫＡＹＡ shrine"]),
        ]
        XCTAssertEqual(SearchScope.all.photos(photos, query: "湖畔").map(\.id), ["desc"])
        XCTAssertEqual(SearchScope.photos.photos(photos, query: "湖畔").map(\.id), ["desc"])
        XCTAssertEqual(PhotoQuery.match(photos, query: "takaya").map(\.id), ["desc2"])
        // タグ・撮影地で絞っているときは説明を見ない
        XCTAssertTrue(SearchScope.tags.photos(photos, query: "湖畔").isEmpty)
        XCTAssertTrue(SearchScope.places.photos(photos, query: "湖畔").isEmpty)
    }

    /// 🔴 **チップの枚数と結果を合わせる。** 枚数は日英の別名をまとめて数える
    /// （冬＝winter）ので、「冬」で探したら winter の写真も出す
    func testTagAliasesMatchLikeTheChipCount() throws {
        let photos = try sample() + [try photo(["id": "en", "tags": ["Winter"]])]
        XCTAssertEqual(SearchScope.all.photos(photos, query: "冬").map(\.id), ["place", "tag", "title", "en"])
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "冬").map(\.id), ["tag", "en"])
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "winter").map(\.id), ["tag", "en"])
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

    /// 板 11 の並び: 注目 → おすすめ → 色 → 季節 → 機材。無い段は飛ばす。
    /// 「季節・時間帯から探す」（板に無い段・2026-10-03）は季節の次
    func testDiscoveryOrderFollowsBoard() {
        XCTAssertEqual(SearchDiscovery.sections(present: Set(SearchDiscovery.Section.allCases)),
                       [.spots, .featured, .colors, .seasonal, .shootingTime, .gear])
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

    /// 0件の出口から地図へ持っていく語。**タグで探していた語は渡さない**（地図は撮影地とスポット名で当てる）
    func testMapQueryDropsTagSearches() {
        XCTAssertEqual(SearchScope.tags.mapQuery(for: "winter"), "")
        XCTAssertEqual(SearchScope.all.mapQuery(for: "京都"), "京都")
        XCTAssertEqual(SearchScope.photos.mapQuery(for: "京都"), "京都")
        XCTAssertEqual(SearchScope.places.mapQuery(for: "京都"), "京都")
    }
}
