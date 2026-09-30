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

    /// **`uploadedBy` だけの写真も同じ投稿としてまとめる**（E14）
    func testUploadedByOnlyPhotosGroup() throws {
        func legacy(_ id: String) throws -> Photo {
            try JSONDecoder.api.decode(Photo.self, from: Data(
                "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"groupId\":\"g1\",\"uploadedBy\":\"A\"}".utf8))
        }
        let groups = PhotoGroups.group([try legacy("a"), try legacy("b")])
        XCTAssertEqual(groups.count, 1, "uploadedBy だけの写真が束ねられていない")
        XCTAssertEqual(groups.first?.photos.map(\.id), ["a", "b"])
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

    /// 🔴 **束の中は選んだ順（`createdAt` の古い順）。** 人気順などで並べた一覧のまま
    /// 束ねると、表紙と「1/n」の順が並べ替えのたびに変わった。束の置き場所は一覧の並びのまま
    func testMembersFollowPostOrderRegardlessOfFeedSort() throws {
        func dated(_ id: String, _ at: String?, group: String? = "g1") throws -> Photo {
            let g = group.map { ",\"groupId\":\"\($0)\"" } ?? ""
            let c = at.map { ",\"createdAt\":\"\($0)\"" } ?? ""
            return try JSONDecoder.api.decode(Photo.self, from: Data(
                "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"userId\":\"me\"\(g)\(c)}".utf8))
        }
        // 一覧は人気順: 3枚目 → 別の写真 → 1枚目 → 2枚目
        let feed = [
            try dated("third", "2026-09-01T10:00:02.000Z"),
            try dated("other", "2026-09-02T00:00:00.000Z", group: nil),
            try dated("first", "2026-09-01T10:00:00.000Z"),
            try dated("second", "2026-09-01T10:00:01.000Z"),
        ]
        let groups = PhotoGroups.group(feed)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].photos.map(\.id), ["first", "second", "third"])
        XCTAssertEqual(groups[0].cover.id, "first")
        XCTAssertEqual(groups[1].id, "other", "束の置き場所が変わった")
        XCTAssertEqual(PhotoGroups.siblings(of: feed[0], in: feed).map(\.id), ["first", "second", "third"])
    }
}

/// 格子の「複数枚」の印（モック2-7）。
final class MultiPhotoMarkTests: XCTestCase {

    private func photo(_ id: String, group: String? = nil, user: String? = "me") throws -> Photo {
        let g = group.map { ",\"groupId\":\"\($0)\"" } ?? ""
        let u = user.map { ",\"userId\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(g)\(u)}".utf8))
    }

    /// 束ねた写真が2枚以上あれば、その全部に印
    func testBothSiblingsAreMarked() throws {
        let ids = PhotoGroups.multiPhotoIds([
            try photo("a", group: "g1"), try photo("b", group: "g1"), try photo("c"),
        ])
        XCTAssertEqual(ids, ["a", "b"])
    }

    /// 🔴 **兄弟が並びに居ないなら印を出さない。** 押しても1枚しか
    /// 出てこないものに「複数枚」と出さない（絞り込みで片方が消えた画面）
    func testLoneMemberOfAGroupIsNotMarked() throws {
        XCTAssertTrue(PhotoGroups.multiPhotoIds([try photo("a", group: "g1")]).isEmpty)
    }

    /// 別の人の同じ印は別の束（`groupKey` が持ち主を含む）
    func testGroupsDoNotCrossOwners() throws {
        let ids = PhotoGroups.multiPhotoIds([
            try photo("a", group: "g1", user: "me"),
            try photo("b", group: "g1", user: "you"),
        ])
        XCTAssertTrue(ids.isEmpty)
    }
}
