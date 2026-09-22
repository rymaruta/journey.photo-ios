import XCTest
@testable import JourneyPhoto

final class CategoryCoversTests: XCTestCase {

    private func photo(_ id: String, category: String, likes: Int? = nil) throws -> Photo {
        let l = likes.map { ",\"likes\":\($0)" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"category\":\"\(category)\"\(l)}".utf8))
    }

    /// **いちばん人気の1枚**が札の顔になる
    func testCoverIsTheMostLiked() throws {
        let items = CategoryCovers.items(in: [
            try photo("a", category: "風景", likes: 2),
            try photo("b", category: "風景", likes: 9),
        ])
        XCTAssertEqual(items.first?.cover.id, "b")
        XCTAssertEqual(items.first?.count, 2)
    }

    /// 1枚も無い分類は札にしない（押しても空になるチップを置かない）
    func testSkipsEmptyCategories() throws {
        let items = CategoryCovers.items(in: [try photo("a", category: "風景")])
        XCTAssertEqual(items.map(\.category), ["風景"])
    }

    /// 日英の表記ゆれは同じ札にまとまる（`landscape` も「風景」）
    func testFoldsSpellings() throws {
        let items = CategoryCovers.items(in: [
            try photo("a", category: "風景", likes: 1),
            try photo("b", category: "landscape", likes: 5),
        ])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.count, 2)
        XCTAssertEqual(items.first?.cover.id, "b")
    }

    /// 並びは決まった選択肢の順（押すたびに位置が変わらない）
    func testOrderFollowsTheChoiceList() throws {
        let photos = try CategoryChoices.all.enumerated().map { try photo("p\($0.offset)", category: $0.element) }
        XCTAssertEqual(CategoryCovers.items(in: photos).map(\.category), CategoryChoices.all)
    }
}
