import XCTest
@testable import JourneyPhoto

/// 招待の画面（`InviteView`）で、ブロックした人の写真を落とせること（既知 H-1・2026-10-07）。
///
/// サーバーの `GET /invites/{token}` が写真ごとに持ち主（`userId`）を返すようになったので、
/// 招待の中身を読んだ写真に持ち主が入り、`dropped.visible` がブロックした相手の写真を落とす
final class InviteBlockedOwnerTests: XCTestCase {

    private let body = #"""
    {"album":{"id":"a1","title":"旅","memberCount":2},
     "photos":[{"id":"p1","src":"https://cdn/1.jpg","userId":"blocked-user"},
               {"id":"p2","src":"https://cdn/2.jpg","userId":"friend"}]}
    """#

    func testInvitePhotosCarryOwner() throws {
        let preview = try JSONDecoder().decode(AlbumService.InvitePreview.self, from: Data(body.utf8))
        XCTAssertEqual(preview.photos.map { $0.userId }, ["blocked-user", "friend"], "招待の写真に持ち主が入っていない")
    }

    func testBlockedOwnersPhotoIsDropped() throws {
        let preview = try JSONDecoder().decode(AlbumService.InvitePreview.self, from: Data(body.utf8))
        let snapshot = ModerationSnapshot(blocked: ["blocked-user"])
        XCTAssertEqual(snapshot.visible(preview.photos).map(\.id), ["p2"], "ブロックした人の写真が招待の画面に残る")
    }
}
