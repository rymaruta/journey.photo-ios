import XCTest
@testable import JourneyPhoto

/// 投稿の知らせの「カードにする」は、持ち主がいまログインしている人のときだけ開く（札 #688・CLAUDE.md「他人の写真は、その人のもの」）
@MainActor
final class PostedCardOfferTests: XCTestCase {

    private func card(_ id: String) throws -> PostedShareCard {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"\#(id)","src":"https://x/\#(id).jpg"}"#.utf8))
        return PostedShareCard(photoData: Data([1, 2, 3]), photo: photo, title: "", description: "", location: "")
    }

    func testOpensOnlyForTheOwner() async throws {
        let offer = PostedCardOffer()
        let a = try card("a")
        offer.offer(a, ownerId: "u1")
        offer.present(a, currentUserId: "u2")
        XCTAssertNil(offer.presented, "別の人がログインしているのに、前の人の写真のカードが開いた")

        offer.offer(a, ownerId: "u1")
        offer.present(a, currentUserId: "u1")
        XCTAssertEqual(offer.presented?.id, a.id)
    }

    func testDropsWhenUserChangesAndDoesNotMixUpCards() async throws {
        let offer = PostedCardOffer()
        let a = try card("a"), b = try card("b")
        offer.offer(a, ownerId: "u1")
        offer.userChanged(to: "u2")
        XCTAssertNil(offer.pending, "人が替わってもカードを持ったまま")

        // 続けて2件上がった: 1件目の知らせのボタンで2件目のカードを開かない
        offer.offer(a, ownerId: "u1")
        offer.offer(b, ownerId: "u1")
        offer.present(a, currentUserId: "u1")
        XCTAssertNil(offer.presented, "1件目の知らせで2件目のカードが開いた")

        // 開いている間に人が替わったら閉じる
        offer.offer(b, ownerId: "u1")
        offer.present(b, currentUserId: "u1")
        offer.userChanged(to: nil)
        XCTAssertNil(offer.presented)
    }
}
