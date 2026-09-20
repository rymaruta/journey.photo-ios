import XCTest
@testable import JourneyPhoto

final class CollectionFilterTests: XCTestCase {

    private func photo(id: String, location: String? = nil, tags: [String] = []) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let location { fields.append("\"location\":\"\(location)\"") }
        if !tags.isEmpty {
            fields.append("\"tags\":[\(tags.map { "\"\($0)\"" }.joined(separator: ","))]")
        }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// **撮影地はゆるく一致させる。** Web 側の `photosInCollection` が
    /// 「パリ」「パリ, フランス」「オペラ・ガルニエ（パリ）」を寄せている。
    /// 完全一致にすると、同じ語で数えた結果が Web と食い違う。
    func testLocationMatchesLoosely() throws {
        let photos = [
            try photo(id: "a", location: "パリ"),
            try photo(id: "b", location: "パリ, フランス"),
            try photo(id: "c", location: "ロンドン"),
        ]
        let hits = TagPhotosView.filter(photos, by: .location("パリ"))
        XCTAssertEqual(hits.map(\.id), ["a", "b"])
    }

    /// タグは大文字小文字を無視した完全一致（部分一致にすると
    /// "sauna" が "sau" で引っかかる）。
    func testTagMatchesExactlyIgnoringCase() throws {
        let photos = [
            try photo(id: "a", tags: ["Sauna"]),
            try photo(id: "b", tags: ["sau"]),
        ]
        XCTAssertEqual(TagPhotosView.filter(photos, by: .tag("sauna")).map(\.id), ["a"])
    }

    /// 関連写真に自分自身を入れない。
    func testRelatedExcludesSelf() throws {
        let subject = try photo(id: "a", location: "パリ", tags: ["街"])
        let others = [subject, try photo(id: "b", location: "パリ")]
        let related = RelatedPhotosRow.pick(from: others, like: subject)
        XCTAssertEqual(related.map(\.id), ["b"])
    }

    /// 撮影地が同じものを先に出す。
    func testRelatedPrefersSameLocation() throws {
        let subject = try photo(id: "a", location: "パリ", tags: ["街"])
        let photos = [
            subject,
            try photo(id: "tagOnly", tags: ["街"]),
            try photo(id: "sameLocation", location: "パリ"),
        ]
        let related = RelatedPhotosRow.pick(from: photos, like: subject)
        XCTAssertEqual(related.first?.id, "sameLocation")
    }

    /// 検索は題・撮影地・タグ・カテゴリを横断し、大文字小文字と全角半角を
    /// 区別しない。
    func testSearchMatchesAcrossFields() throws {
        let photos = [
            try photo(id: "a", location: "Helsinki"),
            try photo(id: "b", tags: ["ｻｳﾅ"]),
        ]
        XCTAssertEqual(PhotoQuery.match(photos, query: "helsinki").map(\.id), ["a"])
    }
}
