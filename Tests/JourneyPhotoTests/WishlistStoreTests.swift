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

    /// 🔴 **ログインしていない間に押した「行きたい」は、ログインしても消えない。**
    /// 以前はログインした人の鍵へ切り替わるだけで、押したぶんが見えなくなった
    func testSignedOutWishesCarryOverWhenSigningIn() async {
        let (wishlist, defaults) = store()
        wishlist.use(userId: "u1")
        wishlist.set("mine-before", wanted: true)
        wishlist.use(userId: nil)
        wishlist.set("anon", wanted: true)

        wishlist.use(userId: "u1")
        XCTAssertEqual(wishlist.spotIds, ["mine-before", "anon"], "未ログインで押したぶんが消えた")
        // 端末に残る（開き直しても在る）
        let reopened = WishlistStore(defaults: defaults)
        reopened.use(userId: "u1")
        XCTAssertTrue(reopened.contains("anon"))
        // 共有の鍵は空にする——次にログインした別の人へ同じぶんを入れない
        wishlist.use(userId: nil)
        XCTAssertTrue(wishlist.spotIds.isEmpty, "引き継いだぶんが未ログインの側に残っている")
        wishlist.use(userId: "u2")
        XCTAssertFalse(wishlist.contains("anon"), "別の人にも引き継いだ")
    }

    /// 🔴 **ログイン中の人から別の人へ替わる回は混ぜない**
    func testSwitchingBetweenSignedInUsersDoesNotMerge() async {
        let (wishlist, _) = store()
        wishlist.use(userId: "u1")
        wishlist.set("u1-only", wanted: true)
        wishlist.use(userId: "u2")
        XCTAssertFalse(wishlist.contains("u1-only"))
        wishlist.use(userId: "u1")
        XCTAssertEqual(wishlist.spotIds, ["u1-only"])
    }

    /// 🔴 **空の鍵を押しても「入った」と返さない。** `set` は空の鍵を捨てるので、
    /// true を返すと画面は「追加しました」と知らせて何も残らない
    func testToggleWithEmptyIdReportsNothingAdded() async {
        let (wishlist, _) = store()
        wishlist.use(userId: "u1")
        XCTAssertFalse(wishlist.toggle(""), "空の鍵で「追加した」と返している")
        XCTAssertTrue(wishlist.spotIds.isEmpty)
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
