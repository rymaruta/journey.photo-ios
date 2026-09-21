import XCTest
@testable import JourneyPhoto

@MainActor
final class WishlistStoreTests: XCTestCase {

    private func store() -> (WishlistStore, UserDefaults) {
        let suite = UserDefaults(suiteName: "wishlist-test-\(UUID().uuidString)")!
        return (WishlistStore(defaults: suite), suite)
    }

    private func spot(_ id: String, name: String) throws -> Spot {
        try JSONDecoder.api.decode(Spot.self, from: Data(
            "{\"spotId\":\"\(id)\",\"slug\":\"\(id)\",\"name\":\"\(name)\"}".utf8))
    }

    func testTogglesAndPersists() async {
        let (wishlist, defaults) = store()
        wishlist.use(userId: "u1")
        XCTAssertTrue(wishlist.toggle("sp_1"))
        XCTAssertTrue(wishlist.contains("sp_1"))

        let reopened = WishlistStore(defaults: defaults)
        reopened.use(userId: "u1")
        XCTAssertTrue(reopened.contains("sp_1"))

        XCTAssertFalse(wishlist.toggle("sp_1"))
        XCTAssertFalse(wishlist.contains("sp_1"))
    }

    /// 同じ端末で人が変わったら**持ち越さない**（お気に入りで踏んだ事故と同じ形）
    func testDoesNotLeakBetweenAccounts() async {
        let (wishlist, _) = store()
        wishlist.use(userId: "u1")
        wishlist.set("sp_1", wanted: true)
        wishlist.use(userId: "u2")
        XCTAssertFalse(wishlist.contains("sp_1"))
        wishlist.use(userId: "u1")
        XCTAssertTrue(wishlist.contains("sp_1"))
    }

    func testIgnoresEmptyId() async {
        let (wishlist, _) = store()
        wishlist.use(userId: nil)
        wishlist.set("", wanted: true)
        XCTAssertTrue(wishlist.spotIds.isEmpty)
    }

    func testListsOnlySpotsStillInTheLedger() async throws {
        let (wishlist, _) = store()
        wishlist.use(userId: "u1")
        wishlist.set("sp_1", wanted: true)
        wishlist.set("sp_gone", wanted: true)
        let ledger = [try spot("sp_1", name: "高屋神社"), try spot("sp_2", name: "山中湖")]
        XCTAssertEqual(wishlist.spots(in: ledger).map(\.spotId), ["sp_1"])
    }
}
