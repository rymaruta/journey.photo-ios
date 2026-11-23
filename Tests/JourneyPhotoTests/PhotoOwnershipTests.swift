import XCTest
@testable import JourneyPhoto

/// 持ち主かを決める1か所（`PhotoOwnership`・2026-11-23）。分からないときは「自分のものではない」に倒す
final class PhotoOwnershipTests: XCTestCase {

    private func photo(userId: String? = nil, uploadedBy: String? = nil) throws -> Photo {
        var row: [String: Any] = ["id": "p1", "src": "https://example.com/a.jpg"]
        if let userId { row["userId"] = userId }
        if let uploadedBy { row["uploadedBy"] = uploadedBy }
        return try JSONDecoder().decode(Photo.self, from: JSONSerialization.data(withJSONObject: row))
    }

    func testOwnerIdPrefersUserIdThenUploadedBy() throws {
        XCTAssertEqual(PhotoOwnership.ownerId(of: try photo(userId: "me", uploadedBy: "old")), "me")
        XCTAssertEqual(PhotoOwnership.ownerId(of: try photo(uploadedBy: "me")), "me")
        XCTAssertNil(PhotoOwnership.ownerId(of: try photo()))
        XCTAssertNil(PhotoOwnership.ownerId(of: try photo(userId: "")), "空の id は持ち主が分からない")
    }

    func testIsMineOnlyWhenBothKnownAndEqual() throws {
        XCTAssertTrue(PhotoOwnership.isMine(photo: try photo(userId: "me"), me: "me"))
        XCTAssertTrue(PhotoOwnership.isMine(photo: try photo(uploadedBy: "me"), me: "me"))
        XCTAssertFalse(PhotoOwnership.isMine(photo: try photo(userId: "mika"), me: "me"), "人の写真")
        XCTAssertFalse(PhotoOwnership.isMine(photo: try photo(userId: "me"), me: nil), "ログインしていない")
        XCTAssertFalse(PhotoOwnership.isMine(photo: try photo(), me: "me"), "持ち主が分からない")
        XCTAssertFalse(PhotoOwnership.isMine(ownerId: "", me: ""), "空どうしを同じと見ない")
        XCTAssertFalse(PhotoOwnership.isMine(ownerId: nil, me: nil))
    }

    func testMineDropsOthersAndUnknown() throws {
        let photos = [try photo(userId: "me"), try photo(userId: "mika"), try photo(), try photo(uploadedBy: "me")]
        XCTAssertEqual(PhotoOwnership.mine(photos, me: "me").count, 2)
        XCTAssertEqual(PhotoOwnership.mine(photos, me: nil).count, 0)
    }

    /// 入口の決まりも同じ答えを返す（どれも `PhotoOwnership` を通る）
    func testGatesAgreeWithPhotoOwnership() {
        let cases: [(String?, String?)] = [("me", "me"), ("mika", "me"), ("", ""), ("me", ""), ("", "me"), (nil, "me"), ("me", nil)]
        for (owner, me) in cases {
            let mine = PhotoOwnership.isMine(ownerId: owner, me: me)
            XCTAssertEqual(PhotoLift.allowsStory(ownerId: owner, me: me), mine)
            XCTAssertEqual(SendSheetLayout.canShareToStory(ownerId: owner, me: me, canSendPhoto: true), mine)
            XCTAssertEqual(PhotoDetailRules.showsSocialCard(ownerId: owner, me: me, shareable: true), mine)
            XCTAssertFalse(SendSheetLayout.canShareToStory(ownerId: owner, me: me, canSendPhoto: false))
            XCTAssertFalse(PhotoDetailRules.showsSocialCard(ownerId: owner, me: me, shareable: false))
        }
    }
}
