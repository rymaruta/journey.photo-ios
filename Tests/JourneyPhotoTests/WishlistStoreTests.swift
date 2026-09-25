import XCTest
@testable import JourneyPhoto

@MainActor
final class WishlistStoreTests: XCTestCase {

    private func store() -> (WishlistStore, UserDefaults) {
        let suite = UserDefaults(suiteName: "wishlist-test-\(UUID().uuidString)")!
        return (WishlistStore(defaults: suite), suite)
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

    /// **台帳のスポットの鍵（`SPOT-<slug>`）は撮影地の鍵と混ざらない。**
    /// 同じ綴りの撮影地「takaya-jinja」を押しても、スポットの側は灯らない
    func testOfficialKeysDoNotMixWithLocationKeys() async {
        let (wishlist, defaults) = store()
        wishlist.use(userId: "u1")
        let official = SavedSpotKey.official("takaya-jinja")
        XCTAssertTrue(wishlist.toggle(official))
        XCTAssertTrue(wishlist.contains(official))
        XCTAssertFalse(wishlist.contains("takaya-jinja"), "撮影地の鍵まで灯っている")

        wishlist.set("takaya-jinja", wanted: true)
        XCTAssertEqual(wishlist.spotIds, ["SPOT-takaya-jinja", "takaya-jinja"])
        XCTAssertFalse(wishlist.toggle(official))
        XCTAssertTrue(wishlist.contains("takaya-jinja"), "スポットを外したら撮影地まで外れた")

        let reopened = WishlistStore(defaults: defaults)
        reopened.use(userId: "u1")
        XCTAssertEqual(reopened.spotIds, ["takaya-jinja"])
    }

}
