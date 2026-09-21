import XCTest
@testable import JourneyPhoto

/// 変異試験で「壊しても誰も気づかない」と分かったところを見張る。
///
/// どれも小さい規則だが、壊れ方は画面に直接出る
/// ——撮影情報の段が消える・人の名前が ID になる・空の応答で落ちる。

/// 撮影情報を持っているか。**空なら送らない**（`UploadViewModel` が
/// `exif.isEmpty ? nil : exif` で判断している）。
final class ExifFieldsTests: XCTestCase {

    func testNothingSetIsEmpty() {
        XCTAssertTrue(ExifFields().isEmpty)
    }

    /// **1つでも入っていれば空ではない。** `==` を `!=` に変えても
    /// 気づかれなかった＝**撮影情報の段が丸ごと出なくなる**壊れ方が
    /// 見張られていなかった。
    func testAnySingleFieldMakesItNonEmpty() {
        var camera = ExifFields(); camera.camera = "Apple iPhone 15 Pro"
        XCTAssertFalse(camera.isEmpty, "機材名を入れたのに空と言っている")

        var iso = ExifFields(); iso.iso = 400
        XCTAssertFalse(iso.isEmpty, "ISO を入れたのに空と言っている")

        var day = ExifFields(); day.dateTimeOriginal = "2026:09:13 08:21:05"
        XCTAssertFalse(day.isEmpty, "撮影日時を入れたのに空と言っている")
    }
}

/// 画面に出す名前。**ID の頭8文字は最後の手段**
/// （CLAUDE.md: 名前を入れないと「しばらく ID の頭8文字で呼ばれる」）。
final class UserProfileNameTests: XCTestCase {

    private func profile(_ json: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
    }

    func testDisplayNameWins() throws {
        let p = try profile(#"{"userId":"abcdefgh1234","displayName":"りょう","username":"ryo"}"#)
        XCTAssertEqual(p.name, "りょう")
    }

    /// **空文字は「無い」と同じ。** `!isEmpty` を外しても気づかれなかった
    /// ＝**空の表示名がそのまま名前として出る**（誰の投稿か分からない）。
    func testEmptyDisplayNameFallsBackToUsername() throws {
        let p = try profile(#"{"userId":"abcdefgh1234","displayName":"","username":"ryo"}"#)
        XCTAssertEqual(p.name, "ryo", "空の表示名を名前として出している")
    }

    func testEmptyUsernameFallsBackToTheIdHead() throws {
        let p = try profile(#"{"userId":"abcdefgh1234","displayName":"","username":""}"#)
        XCTAssertEqual(p.name, "abcdefgh")
    }
}

/// 確認コードの控えが生きているか。
///
/// **境目を見張る。** 切れていない控えを捨てると、登録の途中で詰んだ人は
/// アカウントを作り直すしかなくなる（CLAUDE.md の「行き止まりを作らない」）。
final class PendingVerificationFreshnessTests: XCTestCase {

    private let ttl: TimeInterval = 24 * 60 * 60

    func testJustSavedIsFresh() {
        let now = Date()
        XCTAssertTrue(PendingVerification.isFresh(savedAt: now, now: now))
    }

    /// **切れる手前は生きている。**
    func testJustBeforeTheDeadlineIsFresh() {
        let saved = Date()
        XCTAssertTrue(PendingVerification.isFresh(savedAt: saved, now: saved.addingTimeInterval(ttl - 1)))
    }

    /// **切れたら捨てる。** `<` を `<=` に変えても気づかれなかった。
    func testAtTheDeadlineIsStale() {
        let saved = Date()
        XCTAssertFalse(PendingVerification.isFresh(savedAt: saved, now: saved.addingTimeInterval(ttl)),
                       "切れた控えを生きていると言っている")
    }

    /// **端末の時計が巻き戻った回も捨てる。**
    /// 未来に保存された控えを信じると、いつまでも切れない。
    func testSavedInTheFutureIsStale() {
        let saved = Date()
        XCTAssertFalse(PendingVerification.isFresh(savedAt: saved, now: saved.addingTimeInterval(-ttl - 1)))
    }
}

/// 起動直後の「まだ分かっていない」。
///
/// **`userId == nil` だけで判断しない。** 確認が終わる前に
/// 「ログインしてください」を出すと、ログイン済みの人にも一瞬それが見える。
@MainActor
final class AuthResolvingTests: XCTestCase {

    func testFreshStoreIsStillResolving() async {
        XCTAssertTrue(AuthStore().isResolving,
                      "確かめる前から「ログインしていない」と決めている")
    }
}

/// フォロワー／フォロー中の数字を押せるか。
///
/// 一覧の口は**認証必須**なので、未ログインで押せると
/// 「ログインしてください」の赤字だけの行き止まりに着く。
final class FollowCountsTests: XCTestCase {

    func testSignedOutCannotOpenTheList() {
        XCTAssertFalse(FollowCounts.isTappable(signedIn: false, count: 5))
    }

    func testSignedInWithSomeoneCanOpenTheList() {
        XCTAssertTrue(FollowCounts.isTappable(signedIn: true, count: 1))
    }

    /// 0人なら開いても「まだいません」しか無い
    func testZeroIsNotTappableEvenWhenSignedIn() {
        XCTAssertFalse(FollowCounts.isTappable(signedIn: true, count: 0))
    }
}
