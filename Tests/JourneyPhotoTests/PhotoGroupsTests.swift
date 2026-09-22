import XCTest
@testable import JourneyPhoto

final class PhotoGroupsTests: XCTestCase {

    private func photo(_ id: String, group: String? = nil, user: String? = "me") throws -> Photo {
        let g = group.map { ",\"groupId\":\"\($0)\"" } ?? ""
        let u = user.map { ",\"userId\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(g)\(u)}".utf8))
    }

    /// 印の無い写真は**1枚ずつの束**（呼ぶ側で場合分けしない）
    func testUngroupedPhotosBecomeSingles() throws {
        let groups = PhotoGroups.group([try photo("a"), try photo("b")])
        XCTAssertEqual(groups.map(\.id), ["a", "b"])
        XCTAssertFalse(groups[0].isMultiple)
    }

    func testSameGroupBecomesOneCard() throws {
        let groups = PhotoGroups.group([
            try photo("a", group: "g1"),
            try photo("b", group: "g1"),
            try photo("c"),
        ])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].photos.map(\.id), ["a", "b"])
        XCTAssertTrue(groups[0].isMultiple)
        XCTAssertEqual(groups[0].count, 2)
    }

    /// **並びを壊さない。** 束はその先頭が出てきた場所に置く
    func testKeepsTheOriginalOrder() throws {
        let groups = PhotoGroups.group([
            try photo("first"),
            try photo("a", group: "g1"),
            try photo("mid"),
            try photo("b", group: "g1"),
        ])
        XCTAssertEqual(groups.map(\.id), ["first", "a", "mid"])
        XCTAssertEqual(groups[1].photos.map(\.id), ["a", "b"])
    }

    /// **持ち主の違う写真は同じ束にしない。**
    /// `groupId` は画面が作る値で、同じ値を送れば他人の写真が混ざりうる
    func testDoesNotMixOwners() throws {
        let groups = PhotoGroups.group([
            try photo("mine", group: "g1", user: "me"),
            try photo("theirs", group: "g1", user: "other"),
        ])
        XCTAssertEqual(groups.count, 2)
    }

    /// 持ち主の分からない写真も束ねない
    func testUnknownOwnerIsNeverGrouped() throws {
        let groups = PhotoGroups.group([
            try photo("a", group: "g1", user: nil),
            try photo("b", group: "g1", user: nil),
        ])
        XCTAssertEqual(groups.count, 2)
    }

    func testSiblings() throws {
        let all = [try photo("a", group: "g1"), try photo("b", group: "g1"), try photo("c")]
        XCTAssertEqual(PhotoGroups.siblings(of: all[0], in: all).map(\.id), ["a", "b"])
        XCTAssertEqual(PhotoGroups.siblings(of: all[2], in: all).map(\.id), ["c"])
    }

    /// 一覧に居ない写真でも、**その1枚だけ**は必ず返す（空にしない）
    func testSiblingsOfAPhotoOutsideTheList() throws {
        let lonely = try photo("z", group: "g9")
        XCTAssertEqual(PhotoGroups.siblings(of: lonely, in: []).map(\.id), ["z"])
    }
}
