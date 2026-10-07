import XCTest
@testable import JourneyPhoto

/// 保存した写真・いいねした写真の画面（`LikedPhotosScreen`・H-2）。
/// バグそのもの（消した自分の写真が戻っても残る）と、前回の直し（4a0bb0b）が出した
/// 2つの回帰（圏外で戻るとほかの端末のいいねが消える・読み直しの途中に開いた詳細が閉じる）
final class LikedPhotosScreenTests: XCTestCase {

    private func photo(_ id: String, createdAt: String = "2026-01-01") throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"createdAt\":\"\(createdAt)\"}".utf8))
    }

    private func ids(_ photos: [Photo]) -> Set<String> { Set(photos.map(\.id)) }

    /// 最初に開いて、読み込みが返ったところまで
    private func opened(user: String? = "me", feed: [Photo] = [], mine: [Photo],
                        serverIds: [String]? = nil) -> LikedPhotosScreen {
        var screen = LikedPhotosScreen()
        screen.appear()
        XCTAssertEqual(screen.returns, 0, "初回は `.task(id:)` が読む（二重に読まない）")
        XCTAssertTrue(screen.receive(.init(user: user, feed: feed, mine: mine, serverIds: serverIds)))
        return screen
    }

    // MARK: - バグそのもの

    /// 🔴 **自分の写真を消して戻ったら、一覧から落ちる。** 戻ってきたら読み直し
    /// （`returns` が進む＝`.task(id:)` が走る）、届いた自分の写真で引き当て直す
    func testDeletedOwnPhotoDropsAfterComingBack() throws {
        let kept = try photo("kept"), deleted = try photo("deleted")
        var screen = opened(mine: [kept, deleted])
        let saved: Set<String> = ["kept", "deleted"]
        XCTAssertEqual(ids(screen.shown.resolve(saved) { $0 }), saved)

        // 詳細を開いて、その写真を消して戻る
        screen.disappear()
        let before = screen.returns
        screen.appear()
        XCTAssertEqual(screen.returns, before + 1, "戻ってきたら読み直す")

        // 読み直しの答え（サーバーの自分の写真からは消えている）
        XCTAssertTrue(screen.receive(.init(user: "me", feed: [], mine: [kept])))
        XCTAssertEqual(ids(screen.shown.resolve(saved) { $0 }), ["kept"])
    }

    // MARK: - 回帰1: 圏外で戻る

    /// 🔴 **圏外で戻っても、ほかの端末でいいねした写真を消さない。** サーバーの一覧が
    /// 取れなかった回は、同じ人なら前の一覧を残す（4a0bb0b は nil にして控えだけになった）
    func testOfflineReturnKeepsServerLikesFromOtherDevices() throws {
        let other = try photo("liked-on-other-device")
        var screen = opened(feed: [other], mine: [], serverIds: ["liked-on-other-device"])
        screen.disappear()
        screen.appear()
        // 圏外: 何も取れない
        XCTAssertTrue(screen.receive(.init(user: "me", feed: nil, mine: nil, serverIds: nil, serverFailed: true)))
        XCTAssertEqual(screen.shown.serverIds, ["liked-on-other-device"])
        XCTAssertEqual(ids(screen.shown.resolve(Set(screen.shown.serverIds ?? [])) { $0 }),
                       ["liked-on-other-device"], "引き当て先も前のまま")
        XCTAssertFalse(screen.shown.partial, "前の一覧を出しているので「端末のぶんだけ」とは言わない")
    }

    /// 人が替わった直後に取れなかった回は、前の人の一覧も写真も残さない
    func testFailedLoadForAnotherUserDropsThePreviousUsersLikes() throws {
        var screen = opened(user: "a", mine: [try photo("a-private")], serverIds: ["x"])
        XCTAssertTrue(screen.receive(.init(user: "b", feed: nil, mine: nil, serverIds: nil, serverFailed: true)))
        XCTAssertNil(screen.shown.serverIds)
        XCTAssertTrue(screen.shown.mine.isEmpty)
        XCTAssertTrue(screen.shown.partial, "端末の控えだけで出している")
    }

    /// ログアウトしたら、前の人の一覧・写真を残さない
    func testSignedOutDropsServerLikesAndOwnPhotos() throws {
        var screen = opened(mine: [try photo("mine")], serverIds: ["x"])
        XCTAssertTrue(screen.receive(.init(user: nil, feed: [], mine: nil)))
        XCTAssertNil(screen.shown.serverIds)
        XCTAssertTrue(screen.shown.mine.isEmpty)
    }

    // MARK: - 回帰2: 読み直しの途中に開いた詳細

    /// 🔴 **画面に出ていない間に届いた答えは入れない**（入れると一覧が差し替わり、
    /// 押した元が消えて開いた詳細が閉じる）。戻ったときに入れる
    func testAnswerArrivingWhileDetailIsOpenWaitsUntilReturn() throws {
        let a = try photo("a"), b = try photo("b")
        var screen = opened(mine: [a, b])
        // 戻って読み直しが始まる → その途中で詳細を開く
        screen.disappear()
        screen.appear()
        screen.disappear()
        // 詳細を開いている間に答えが届く
        XCTAssertFalse(screen.receive(.init(user: "me", feed: [], mine: [b])), "絞り直さない")
        XCTAssertEqual(ids(screen.shown.mine), ["a", "b"], "開いている間は前のまま")
        XCTAssertNotNil(screen.staged)
        // 戻ったら入れる
        screen.appear()
        XCTAssertEqual(ids(screen.shown.mine), ["b"])
        XCTAssertNil(screen.staged)
    }

    /// 取っておいた答えの上に、後の失敗を重ねる（前の答えで取れた一覧を消さない）
    func testLaterFailureStacksOnTheStagedAnswer() throws {
        var screen = opened(mine: [], serverIds: ["old"])
        screen.disappear()
        XCTAssertFalse(screen.receive(.init(user: "me", feed: [], mine: [], serverIds: ["new"])))
        XCTAssertFalse(screen.receive(.init(user: "me", feed: nil, mine: nil, serverIds: nil, serverFailed: true)))
        screen.appear()
        XCTAssertEqual(screen.shown.serverIds, ["new"])
    }

    /// 最初の答えが画面が出る前に届いても、出たときに入る（「読み込み中」のままにしない）
    func testAnswerBeforeFirstAppearIsAppliedOnAppear() throws {
        var screen = LikedPhotosScreen()
        XCTAssertFalse(screen.receive(.init(user: "me", feed: [], mine: [try photo("a")])))
        XCTAssertFalse(screen.shown.loaded)
        screen.appear()
        XCTAssertTrue(screen.shown.loaded)
        XCTAssertEqual(screen.returns, 0)
    }
}
