import XCTest
@testable import JourneyPhoto

/// トップの「自分 / フォロー中 / すべて」（Web の `?scope=`）。
final class GalleryScopeTests: XCTestCase {

    private func photo(_ id: String, owner: String?, published: Bool = true) -> Photo {
        let ownerPart = owner.map { ",\"userId\":\"\($0)\"" } ?? ""
        let json = #"{"id":"\#(id)","src":"https://x.test/\#(id).jpg"\#(ownerPart),"published":\#(published)}"#
        return try! JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    private var sample: [Photo] {
        [photo("a", owner: "me"), photo("b", owner: "friend"),
         photo("c", owner: "stranger"), photo("d", owner: nil)]
    }

    func testMineKeepsOnlyYourPhotos() {
        let out = GalleryScope.mine.photos(sample, viewerId: "me", followingIds: ["friend"])
        XCTAssertEqual(out.map { $0.id }, ["a"])
    }

    /// **自分の写真は「フォロー中」に入らない**（自分はフォローできない。
    /// 自分の投稿はマイページが持ち場——Web の `timelinePhotos` と同じ）。
    func testFollowingExcludesYourOwnPhotos() {
        let out = GalleryScope.following.photos(sample, viewerId: "me", followingIds: ["friend"])
        XCTAssertEqual(out.map { $0.id }, ["b"])
    }

    /// 誰もフォローしていなければ空（「すべて」に化けない）。
    func testFollowingNobodyShowsNothing() {
        let out = GalleryScope.following.photos(sample, viewerId: "me", followingIds: [])
        XCTAssertTrue(out.isEmpty)
    }

    /// **未ログインでは絞らない**（絞れないので絞らない）。
    func testSignedOutFallsBackToEverything() {
        XCTAssertEqual(GalleryScope.mine.photos(sample, viewerId: nil, followingIds: []).count, 4)
        XCTAssertEqual(GalleryScope.following.photos(sample, viewerId: nil, followingIds: []).count, 4)
    }

    /// 下書きはどの範囲にも出さない。
    func testDraftsAreNeverShown() {
        let photos = [photo("a", owner: "me"), photo("draft", owner: "me", published: false)]
        XCTAssertEqual(GalleryScope.mine.photos(photos, viewerId: "me", followingIds: []).map { $0.id }, ["a"])
        XCTAssertEqual(GalleryScope.all.photos(photos, viewerId: "me", followingIds: []).map { $0.id }, ["a"])
    }
}

/// ストーリーの表示秒数。**既定（5秒）なら送らない**——サーバーも
/// 既定は保存しない（`stories.ts` の `STORY_DEFAULT_DURATION_SEC`）。
final class StoryDurationTests: XCTestCase {

    func testDefaultIsNotSent() {
        XCTAssertNil(StoryService.storedDuration(5))
        XCTAssertNil(StoryService.storedDuration(nil))
    }

    func testOutOfRangeIsClamped() {
        XCTAssertEqual(StoryService.storedDuration(1), 3, "3秒未満は読み切れない")
        XCTAssertEqual(StoryService.storedDuration(60), 15, "15秒を超えると見る側が飽きる")
    }

    func testOtherValuesAreSentAsIs() {
        XCTAssertEqual(StoryService.storedDuration(3), 3)
        XCTAssertEqual(StoryService.storedDuration(10), 10)
    }
}

/// まとめて投稿したときの結果の伝え方。
///
/// **何枚上がって、何枚残ったかを必ず出す。** Web の反省——落ちた枚数が
/// 伝わらないと、利用者は「なぜか1枚少ない」まま公開する。
final class UploadSummaryTests: XCTestCase {

    func testAllDoneSaysNothing() {
        XCTAssertNil(UploadSummary.message(done: 3, failures: [], cancelled: false))
    }

    func testStoppedSaysHowManyMadeIt() throws {
        let stopped = try XCTUnwrap(UploadSummary.message(done: 2, failures: [], cancelled: true))
        XCTAssertTrue(stopped.contains("2"), "上がった枚数が出る: \(stopped)")
        XCTAssertNotNil(UploadSummary.message(done: 0, failures: [], cancelled: true))
    }

    func testPartialFailureSaysHowManyMadeItAndWhy() throws {
        let message = try XCTUnwrap(
            UploadSummary.message(done: 1, failures: ["通信できませんでした"], cancelled: false))
        XCTAssertTrue(message.contains("1"), "上がった枚数が出る: \(message)")
        XCTAssertTrue(message.contains("通信できませんでした"), "理由も出る: \(message)")
    }

    func testTotalFailureDoesNotClaimAnyWereposted() throws {
        let message = try XCTUnwrap(
            UploadSummary.message(done: 0, failures: ["だめでした"], cancelled: false))
        XCTAssertFalse(message.contains("0 枚は投稿しました"))
    }

    /// **曲が付かなかったのに「何も言うことは無い」を返さない。**
    /// nil を返すと `UploadViewModel` が「全部成功」と見なし、
    /// `didPostAll` で画面が閉じて警告が一度も描かれなかった。
    func testSongFailureIsReportedEvenWhenEveryPhotoWentUp() throws {
        let message = try XCTUnwrap(
            UploadSummary.message(done: 2, failures: [], cancelled: false, songFailures: 1),
            "曲が付かなかった回は黙らない")
        XCTAssertTrue(message.contains("2"), "上がった枚数は出る: \(message)")
        // **言語を決め打ちしない。** `L()` は実行環境の言語で返すので、
        // 日本語だけを見ると英語のランナー（CI）で落ちる
        XCTAssertTrue(message.contains("曲") || message.lowercased().contains("song"),
                      "曲のことだと分かる: \(message)")
    }

    /// 曲が絡まない回まで喋らせない（既存の静かさを壊さない）。
    func testNoSongFailureStillSaysNothing() {
        XCTAssertNil(UploadSummary.message(done: 2, failures: [], cancelled: false, songFailures: 0))
    }

    /// **途中でやめた回にも曲のことを言う。** 先頭の分岐でしか見ていなかった
    /// 頃は、やめた回・他の写真が失敗した回に一度も伝わらなかった。
    func testSongFailureIsReportedWhenStopped() throws {
        let message = try XCTUnwrap(
            UploadSummary.message(done: 1, failures: [], cancelled: true, songFailures: 1))
        XCTAssertTrue(message.contains("曲") || message.lowercased().contains("song"),
                      "やめた回に曲のことを言っていない: \(message)")
    }

    /// 他の写真が落ちた回も同じ。
    func testSongFailureIsReportedAlongsideOtherFailures() throws {
        let message = try XCTUnwrap(
            UploadSummary.message(done: 1, failures: ["通信できませんでした"],
                                  cancelled: false, songFailures: 1))
        XCTAssertTrue(message.contains("曲") || message.lowercased().contains("song"),
                      "他が落ちた回に曲のことを言っていない: \(message)")
    }
}

/// 「見せない」が変わったことを、画面が1回で受け取れるか。
///
/// 2つの集合を別々に見ると、通報してブロックもする回に全件取得が2回走る。
@MainActor
final class ModerationRevisionTests: XCTestCase {

    private func store() -> ModerationStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ModerationStore(defaults: defaults)
        store.use(userId: "u1")
        return store
    }

    /// **人が変わったときも数える。** 数えないと、画面は読み直さず、
    /// 前の人の絞り込みで読んだ一覧が新しい人に見えたままになる。
    func testSwitchingAccountsBumpsTheRevision() async {
        let store = self.store()
        let before = store.revision
        store.use(userId: "u2")
        XCTAssertGreaterThan(store.revision, before, "人が変わったのに数が増えていない")
    }

    func testEveryChangeBumpsTheRevision() async {
        let store = self.store()
        let start = store.revision
        store.block("a")
        store.markReported("p")
        store.unblock("a")
        store.replaceBlocked(with: ["b"])
        XCTAssertEqual(store.revision, start + 4, "変わったのに数が増えていない")
    }
}
