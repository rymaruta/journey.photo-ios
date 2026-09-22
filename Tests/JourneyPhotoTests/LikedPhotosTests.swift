import XCTest
@testable import JourneyPhoto

final class LikedPhotosTests: XCTestCase {

    private func photo(_ id: String, createdAt: String? = nil) throws -> Photo {
        let created = createdAt.map { ",\"createdAt\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(created)}".utf8))
    }

    /// **和を取る。** サーバーは別の端末のぶん、端末は未ログイン中のぶん
    func testUnionOfServerAndDevice() {
        XCTAssertEqual(LikedPhotos.ids(serverIds: ["a", "b"], deviceIds: ["b", "c"]),
                       ["a", "b", "c"])
    }

    /// サーバーに聞けなかった回でも**端末の控えは消さない**
    func testKeepsDeviceIdsWhenServerIsUnreachable() {
        XCTAssertEqual(LikedPhotos.ids(serverIds: nil, deviceIds: ["c"]), ["c"])
    }

    /// **他人の写真が出る。** 自分の写真だけを探していたのが元のバグ
    func testFindsOtherPeoplesPhotosFromThePublicFeed() throws {
        let feed = [try photo("other", createdAt: "2026-01-02")]
        let mine = [try photo("mine", createdAt: "2026-01-01")]
        let found = LikedPhotos.resolve(["other", "mine"], in: [feed, mine])
        XCTAssertEqual(found.map(\.id), ["other", "mine"])
    }

    /// 同じ写真が両方にあっても1回だけ
    func testNoDuplicates() throws {
        let same = try photo("x", createdAt: "2026-01-01")
        XCTAssertEqual(LikedPhotos.resolve(["x"], in: [[same], [same]]).map(\.id), ["x"])
    }

    /// 引き当てられない ID は落とす（空の枠を置かない）
    func testDropsIdsThatHaveNoPhoto() throws {
        let feed = [try photo("a", createdAt: "2026-01-01")]
        XCTAssertEqual(LikedPhotos.resolve(["a", "gone"], in: [feed]).map(\.id), ["a"])
    }

    func testNewestFirst() throws {
        let feed = [
            try photo("old", createdAt: "2026-01-01"),
            try photo("new", createdAt: "2026-05-01"),
        ]
        XCTAssertEqual(LikedPhotos.resolve(["old", "new"], in: [feed]).map(\.id), ["new", "old"])
    }
}
