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

    /// 🔴 **名前が1つも無いとき、利用者 ID を出さない。**
    /// 以前はここが「ID の頭8文字」で、実機の絵（run 51）に
    /// **`d7e4da78`** と人の名前の場所に出ていた。内部の値が漏れて
    /// いるうえ、壊れているようにも見える。Web 版も ID は出さない
    func testNoNamesShowsAWordNotTheId() throws {
        let p = try profile(#"{"userId":"abcdefgh1234","displayName":"","username":""}"#)
        XCTAssertEqual(p.name, Labels.Common.unnamedUser)
        XCTAssertFalse(p.name.contains("abcdefgh"), "ID が名前として出ている")
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

/// 画面の言語。
///
/// **Web は言語切替を廃止して日本語のみ**（`app/i18n/context.tsx` の
/// `locale` は常に `"ja"`）。アプリだけ端末の言語で英語に切り替わると、
/// 同じ人が同じ写真を別の言葉で見ることになる（題も説明も言語ごとに
/// 保存されているので中身まで変わる）。
final class AppLanguageTests: XCTestCase {

    func testAlwaysJapanese() {
        XCTAssertEqual(Locale.preferredAppLanguage, "ja")
    }

    /// `L()` も日本語を返す（英語の端末でも）
    func testLabelsAreJapanese() {
        XCTAssertEqual(L("ギャラリー", "Gallery"), "ギャラリー")
    }

    /// 写真の中身も日本語側を選ぶ
    func testPhotoTextPrefersJapanese() throws {
        let json = #"{"id":"a","src":"https://x/a.jpg","title":{"ja":"雲海","en":"Sea of clouds"}}"#
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
        XCTAssertEqual(photo.displayTitle, "雲海")
    }
}

/// 写真を2回叩いたとき。Web のモーダル（`GalleryModal/index.tsx` の
/// `handleImageTap`）と同じ約束にする。
final class DoubleTapLikeTests: XCTestCase {

    /// **いいね済みなら解除しない。** うっかり2回叩いて消えても、
    /// 押した本人は気づけない（数は他人のぶんも含むので 1 減っても
    /// おかしく見えない）
    func testDoesNotUnlike() {
        XCTAssertEqual(DoubleTapLike.action(isZoomed: false, alreadyLiked: true, signedIn: true),
                       .burstOnly)
    }

    func testLikesWhenNotLikedYet() {
        XCTAssertEqual(DoubleTapLike.action(isZoomed: false, alreadyLiked: false, signedIn: true),
                       .like)
    }

    /// **拡大中は倍率を戻す側。** 拡大したまま迷子になる出口を潰さない
    func testZoomWins() {
        XCTAssertEqual(DoubleTapLike.action(isZoomed: true, alreadyLiked: false, signedIn: true),
                       .resetZoom)
    }

    /// 未ログインでは何も送らない（断り書きで写真の邪魔をしない）
    func testSignedOutSendsNothing() {
        XCTAssertEqual(DoubleTapLike.action(isZoomed: false, alreadyLiked: false, signedIn: false),
                       .burstOnly)
    }

    /// 🔴 **いいねの行き先は、いま見ている1枚。** 隣へ送ってから叩くと
    /// 開いたときの1枚に付いていた
    func testTargetsThePhotoOnScreen() throws {
        let photos = try ["a", "b", "c"].map { id in
            try JSONDecoder.api.decode(
                Photo.self, from: Data(#"{"id":"\#(id)","src":"https://x/\#(id).jpg"}"#.utf8))
        }
        XCTAssertEqual(DoubleTapLike.shown(photos, at: 2)?.id, "c")
        XCTAssertEqual(DoubleTapLike.shown(photos, at: 0)?.id, "a")
        // 並びの外（読み直しで減った直後など）には送らない
        XCTAssertNil(DoubleTapLike.shown(photos, at: 3))
        XCTAssertNil(DoubleTapLike.shown(photos, at: -1))
    }
}

/// 表示名を決めてもらう案内を出すか（Web の `ProfileSetupBanner`）。
final class ProfileSetupTests: XCTestCase {

    func testAsksWhenBothAreEmpty() {
        XCTAssertTrue(ProfileSetup.needsName(displayName: nil, username: nil))
        XCTAssertTrue(ProfileSetup.needsName(displayName: "  ", username: ""))
    }

    /// **username があれば出さない。** 検索も表示もそちらで代用できる
    func testUsernameIsEnough() {
        XCTAssertFalse(ProfileSetup.needsName(displayName: nil, username: "luzhj"))
    }

    func testDisplayNameIsEnough() {
        XCTAssertFalse(ProfileSetup.needsName(displayName: "たろう", username: nil))
    }
}

/// 短い知らせ（Web の `useToast`）。
@MainActor
final class ToastCenterTests: XCTestCase {

    func testShowsTheMessage() async {
        let center = ToastCenter()
        center.show("ブロックしました")
        XCTAssertEqual(center.current?.text, "ブロックしました")
        XCTAssertEqual(center.current?.kind, .success)
    }

    /// **空の知らせは出さない**（何も伝えない帯が画面を覆う）
    func testBlankIsIgnored() async {
        let center = ToastCenter()
        center.show("   \n ")
        XCTAssertNil(center.current)
    }

    /// **積まない。** iPhone の幅では読み切る前に次が来るので、最後の1つだけ
    func testLatestReplacesThePrevious() async {
        let center = ToastCenter()
        center.show("1つ目")
        center.show("2つ目", kind: .failure)
        XCTAssertEqual(center.current?.text, "2つ目")
        XCTAssertEqual(center.current?.kind, .failure)
    }

    /// 押したら消せる（読み終わった人を待たせない）
    func testDismiss() async {
        let center = ToastCenter()
        center.show("あ")
        center.dismiss()
        XCTAssertNil(center.current)
    }
}

/// お知らせの絞り込み（提案の絵・モック10）。
final class NotificationFilterTests: XCTestCase {

    func testAllKeepsEverything() {
        for kind in [AppNotification.Kind.like, .comment, .follow, .storyreply] {
            XCTAssertTrue(NotificationFilter.all.matches(kind))
        }
    }

    /// **ストーリーの返信は「コメント」に入れる。**
    /// どちらも「言葉が届いた」で、分けても探しやすくならない
    func testStoryRepliesCountAsComments() {
        XCTAssertTrue(NotificationFilter.comment.matches(.storyreply))
        XCTAssertTrue(NotificationFilter.comment.matches(.comment))
        XCTAssertFalse(NotificationFilter.comment.matches(.like))
    }

    func testLikeAndFollowAreSeparate() {
        XCTAssertTrue(NotificationFilter.like.matches(.like))
        XCTAssertFalse(NotificationFilter.like.matches(.follow))
        XCTAssertTrue(NotificationFilter.follow.matches(.follow))
    }

    /// **サーバーが知らない種類を作らない**（4つだけ）
    func testOnlyFourFilters() {
        XCTAssertEqual(NotificationFilter.allCases.count, 4)
    }
}

/// 投稿の長さの上限。**サーバーの値を写しているか**を見張る。
final class PostLimitsTests: XCTestCase {

    /// `api-user/src/sanitize.ts` の実際の値
    func testMatchesTheServer() {
        XCTAssertEqual(PostLimits.title, 200)
        XCTAssertEqual(PostLimits.description, 2_000)
        XCTAssertEqual(PostLimits.location, 200)
        XCTAssertEqual(PostLimits.storyCaption, 200)
    }

    /// **いつも数を出さない**（数字が気になって書けなくなる）。
    /// 2割を切ってから
    func testCountAppearsOnlyNearTheLimit() {
        XCTAssertFalse(PostLimits.shouldShowCount(String(repeating: "あ", count: 10), limit: 200))
        XCTAssertTrue(PostLimits.shouldShowCount(String(repeating: "あ", count: 160), limit: 200))
    }

    /// 画面側で止める（サーバーに黙って切らせない）
    func testClamp() {
        let long = String(repeating: "あ", count: 300)
        XCTAssertEqual(PostLimits.clamp(long, limit: PostLimits.title).count, 200)
        XCTAssertEqual(PostLimits.clamp("短い", limit: 200), "短い")
    }
}
