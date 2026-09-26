import XCTest
@testable import JourneyPhoto

/// 探す画面の絞り（板 11）
final class SearchScopeTests: XCTestCase {

    private func photo(_ id: String, title: String? = nil, location: String? = nil,
                       tags: [String] = []) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"/uploads/\(id).jpg\""]
        if let title { fields.append("\"title\":\"\(title)\"") }
        if let location { fields.append("\"location\":\"\(location)\"") }
        if !tags.isEmpty {
            fields.append("\"tags\":[\(tags.map { "\"\($0)\"" }.joined(separator: ","))]")
        }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 板の5つ、この順
    func testBoardOrder() {
        XCTAssertEqual(SearchScope.allCases.map(\.label), ["すべて", "写真", "人", "タグ", "撮影地"])
    }

    /// 人を出すのは「すべて」と「人」だけ。写真を出さないのは「人」だけ
    func testWhichResultsShow() {
        XCTAssertEqual(SearchScope.allCases.filter(\.showsPeople), [.all, .people])
        XCTAssertEqual(SearchScope.allCases.filter { !$0.showsPhotos }, [.people])
    }

    /// **「タグ」はタグだけ、「撮影地」は撮影地だけで当てる**
    func testTagsAndPlacesMatchOnlyTheirField() throws {
        let tagged = try photo("tagged", title: "朝", tags: ["kyoto"])
        let placed = try photo("placed", title: "夜", location: "Kyoto, Japan")
        let titled = try photo("titled", title: "Kyoto station")
        let all = [tagged, placed, titled]
        XCTAssertEqual(SearchScope.tags.match(all, query: "KYOTO").map(\.id), ["tagged"])
        XCTAssertEqual(SearchScope.places.match(all, query: "ｋｙｏｔｏ").map(\.id), ["placed"])
        XCTAssertEqual(Set(SearchScope.all.match(all, query: "kyoto").map(\.id)),
                       ["tagged", "placed", "titled"])
        XCTAssertEqual(Set(SearchScope.photos.match(all, query: "kyoto").map(\.id)),
                       ["tagged", "placed", "titled"])
    }

    /// 「人」では写真を拾わない。空の語では何も拾わない
    func testPeopleAndEmptyQueryReturnNoPhotos() throws {
        let p = try photo("a", location: "パリ", tags: ["パリ"])
        XCTAssertTrue(SearchScope.people.match([p], query: "パリ").isEmpty)
        XCTAssertTrue(SearchScope.tags.match([p], query: "  ").isEmpty)
        XCTAssertTrue(SearchScope.places.match([p], query: "").isEmpty)
    }

    /// **「タグ」は鍵で当てる**——一覧の枚数（日英の別名を畳んで数える）と、押したときに
    /// 出る枚数を揃える。「冬」で `winter` も、`#冬` でも同じ。「山」で `山中湖` は拾わない
    func testTagsMatchByKeyLikeTheCounts() throws {
        let ja = try photo("ja", tags: ["冬"])
        let en = try photo("en", tags: ["winter"])
        let lake = try photo("lake", tags: ["山中湖"])
        let mountain = try photo("mountain", tags: ["山"])
        let all = [ja, en, lake, mountain]
        XCTAssertEqual(Set(SearchScope.tags.match(all, query: "冬").map(\.id)), ["ja", "en"])
        XCTAssertEqual(Set(SearchScope.tags.match(all, query: "#冬").map(\.id)), ["ja", "en"])
        XCTAssertEqual(SearchScope.tags.match(all, query: "山").map(\.id), ["mountain"])
        // 鍵で当たらなければ、打ちかけとして部分一致
        XCTAssertEqual(SearchScope.tags.match(all, query: "中湖").map(\.id), ["lake"])
    }
}
