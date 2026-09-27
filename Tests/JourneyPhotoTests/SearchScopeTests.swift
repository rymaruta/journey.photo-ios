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

    /// **「タグ」は鍵で当てる**——一覧の枚数（日英の別名を畳んで数える）と、押したときに
    /// 出る枚数を揃える。「冬」で `winter` も、`#冬`・`＃冬` でも同じ。「山」で `山中湖` は拾わない
    func testTagsMatchByKeyLikeTheCounts() throws {
        let photos = [
            try photo(["id": "ja", "tags": ["冬"]]),
            try photo(["id": "en", "tags": ["Winter"]]),
            try photo(["id": "lake", "tags": ["山中湖"]]),
            try photo(["id": "mountain", "tags": ["山"]]),
        ]
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "冬").map(\.id), ["ja", "en"])
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "#冬").map(\.id), ["ja", "en"])
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "＃冬").map(\.id), ["ja", "en"])
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "山").map(\.id), ["mountain"])
    }

    /// 鍵で1枚も当たらなければ、打ちかけの語として部分一致で拾う
    func testTagsFallBackToPartialMatch() throws {
        let photos = [
            try photo(["id": "lake", "tags": ["山中湖"]]),
            try photo(["id": "sauna", "tags": ["Sauna"]]),
        ]
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "中湖").map(\.id), ["lake"])
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "#sau").map(\.id), ["sauna"])
        XCTAssertTrue(SearchScope.tags.photos(photos, query: "#").isEmpty)
    }

    /// 人を選んだら写真は出さない。人を出すのは すべて と 人 だけ
    func testPeopleScopeShowsNoPhotos() throws {
        XCTAssertTrue(SearchScope.people.photos(try sample(), query: "冬").isEmpty)
        XCTAssertEqual(SearchScope.allCases.filter(\.showsPeople), [.all, .people])
        XCTAssertEqual(SearchScope.allCases.map(\.label),
                       [L("すべて", "All"), L("写真", "Photos"), L("人", "People"),
                        L("タグ", "Tags"), L("撮影地", "Places")])
    }

    /// 人を探しているときは案内も人向けに
    func testPeopleScopeAsksForAName() {
        XCTAssertNotEqual(SearchScope.people.prompt, SearchScope.photos.prompt)
        XCTAssertEqual(SearchScope.people.prompt, L("人を検索（名前）", "Search people"))
        XCTAssertEqual(SearchScope.all.prompt, L("写真を検索（題・説明・タグなど）", "Search photos"))
    }

    /// 何も打っていないときの入口: すべて＝発見・写真＝格子・人＝案内・タグ／撮影地＝行
    func testEntryPerScope() {
        XCTAssertEqual(SearchScope.allCases.map(\.entry),
                       [.discovery, .photoGrid, .peopleHint, .tagRows, .placeRows])
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

/// 探すの読み込み（`SearchViewModel.apply(photos:)`）
@MainActor
final class SearchLoadTests: XCTestCase {

    private func photo(_ id: String, focal: String? = nil, color: String? = nil) throws -> Photo {
        var row: [String: Any] = ["id": id, "src": "https://x/\(id).jpg"]
        if let focal { row["exif"] = ["focalLength": focal] }
        if let color { row["dominantColor"] = color }
        return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: row))
    }

    /// **機材・色の枚数を12で切らない。** 行の「N枚」と押した先の一覧は
    /// section の写真そのものなので、切ると13枚目から先が数えられず出てこない
    func testGearAndColourSectionsKeepEveryPhoto() async throws {
        let photos = try (0..<15).map { try photo("p\($0)", focal: "24mm", color: "#2f6fd0") }
        let model = SearchViewModel()
        model.apply(photos: photos)
        XCTAssertEqual(model.gear.first?.group, .wide)
        XCTAssertEqual(model.gear.first?.count, 15, "機材の枚数が頭打ちになっている")
        XCTAssertEqual(model.colors.first?.family, .blue)
        XCTAssertEqual(model.colors.first?.count, 15, "色の枚数が頭打ちになっている")
    }

    /// 「タグ」「撮影地」の入口の行。**枚数は押した先と同じ数え方**
    /// （タグは鍵で畳む・撮影地は集約と同じゆるい一致）。多い順
    func testTagAndPlaceRowsAreCountedAndSorted() async throws {
        func make(_ id: String, tags: [String], place: String?) throws -> Photo {
            var row: [String: Any] = ["id": id, "src": "https://x/\(id).jpg", "tags": tags]
            if let place { row["location"] = place }
            return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: row))
        }
        let photos = [
            try make("a", tags: ["冬"], place: "札幌"),
            try make("b", tags: ["winter"], place: "札幌"),
            try make("c", tags: ["海"], place: "那覇"),
        ]
        let model = SearchViewModel()
        model.apply(photos: photos)
        XCTAssertEqual(model.tagCounts.map(\.tag), ["冬", "海"])
        XCTAssertEqual(model.tagCounts.map(\.count), [2, 1])
        XCTAssertEqual(model.places.map(\.id), ["札幌", "那覇"])
        XCTAssertEqual(model.places.map(\.count), [2, 1])
        // 行を押したときに出る枚数と揃っている
        XCTAssertEqual(SearchScope.tags.photos(photos, query: "冬").count, 2)
    }

    /// **読み込み前に「写真」を選んでも、読み終えたら格子が埋まる**
    /// （`shown` を控えにせず、`allPhotos` と打った語から毎回導く）
    func testPhotoGridFillsAfterLoadingEvenIfScopeWasChosenFirst() async throws {
        let model = SearchViewModel()
        model.select(scope: .photos)
        await model.search("", debounce: .zero) { _ in [] }
        XCTAssertTrue(model.shown.isEmpty)
        model.apply(photos: [try photo("x"), try photo("y")])
        XCTAssertEqual(Set(model.shown.map(\.id)), ["x", "y"])
    }

    /// 板 11: いまの季節の写真は**3列×1段**。「すべて →」の先には全部
    func testSeasonalPreviewIsOneRowOfThree() async throws {
        let tag = try XCTUnwrap(DiscoverySections.seasonalTags().first)
        let photos = try (0..<5).map { index -> Photo in
            var row: [String: Any] = ["id": "s\(index)", "src": "https://x/s\(index).jpg"]
            row["tags"] = [tag]
            return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: row))
        }
        let model = SearchViewModel()
        model.apply(photos: photos)
        XCTAssertEqual(model.seasonal.count, 3, "格子が1段（3枚）になっていない")
        XCTAssertEqual(model.seasonalAll.count, 5)
        XCTAssertEqual(SearchDiscovery.featuredPreview, 3)
    }
}
