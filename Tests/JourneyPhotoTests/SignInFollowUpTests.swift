import XCTest
@testable import JourneyPhoto

/// ログインしたら押した操作を最後まで済ませる（2026-11-16 判断・使い勝手の見直し A4・`SignInFollowUp`）
@MainActor
final class SignInFollowUpTests: XCTestCase {

    private func step(_ followUp: SignInFollowUp, me: String? = "me", current: String = "p1",
                      ready: String? = "me", liked: Bool = false, saved: Bool = false,
                      owner: String? = "owner", following: Bool? = false,
                      lookupFailed: Bool = false) -> SignInFollowUp.Step {
        SignInFollowUp.step(followUp, me: me, currentPhotoId: current, reactionsReadyFor: ready,
                            liked: liked, saved: saved, ownerId: owner, isFollowing: following,
                            followLookupFailed: lookupFailed)
    }

    /// 🔴 **付けるだけで外さない。** ログインした人が前からいいね・保存済みなら送らない
    /// （送ると入れ替えの操作が外す向きに化ける）。読み終わる前は待つ
    func testLikeAndSaveRunOnlyAfterTheNewUsersStateIsRead() async {
        XCTAssertEqual(step(.like(photoId: "p1")), .run)
        XCTAssertEqual(step(.like(photoId: "p1"), liked: true), .drop, "いいね済みの写真で外す向きに送る")
        XCTAssertEqual(step(.like(photoId: "p1"), ready: nil), .wait, "今の人のハートを読む前に送った")
        XCTAssertEqual(step(.like(photoId: "p1"), ready: "someoneElse"), .wait, "前の人の読みで決めた")
        XCTAssertEqual(step(.save(photoId: "p1")), .run)
        XCTAssertEqual(step(.save(photoId: "p1"), saved: true), .drop, "保存済みの写真で外す向きに送る")
        XCTAssertEqual(step(.save(photoId: "p1"), ready: nil), .wait)
    }

    /// まだログインしていない間は待つ。束の隣の写真へ移ったら、押した写真ではないので忘れる
    func testWaitsUntilSignedInAndDropsWhenThePhotoChanged() async {
        XCTAssertEqual(step(.like(photoId: "p1"), me: nil, ready: nil), .wait)
        XCTAssertEqual(step(.follow(userId: "owner"), me: nil), .wait)
        XCTAssertEqual(step(.like(photoId: "p1"), current: "p2"), .drop, "隣の写真にいいねを付けた")
        XCTAssertEqual(step(.save(photoId: "p1"), current: "p2"), .drop)
    }

    /// フォローは、ログインした人のフォローの状態が分かってから。自分だった・もうフォロー中なら送らない
    func testFollowWaitsForTheLookupAndNeverFollowsYourself() async {
        XCTAssertEqual(step(.follow(userId: "owner")), .run)
        XCTAssertEqual(step(.follow(userId: "owner"), following: true), .drop, "フォロー中の人に送り直した")
        XCTAssertEqual(step(.follow(userId: "owner"), following: nil), .wait, "状態が分かる前に送った")
        XCTAssertEqual(step(.follow(userId: "owner"), following: nil, lookupFailed: true), .run,
                       "取れなかった回は押した側で取り直してから送る（toggleFollow）")
        XCTAssertEqual(step(.follow(userId: "me"), owner: "me"), .drop, "自分をフォローしようとした")
        XCTAssertEqual(step(.follow(userId: "owner"), owner: "another"), .drop, "別の人のページで送った")
    }

    /// 人のページの「フォローする」の続き（`followStep`）
    func testProfileFollowStep() async {
        XCTAssertEqual(SignInFollowUp.followStep(userId: "u", me: "me", shownUserId: "u", isFollowing: false,
                                                 lookupFailed: false), .run)
        XCTAssertEqual(SignInFollowUp.followStep(userId: "u", me: "u", shownUserId: "u", isFollowing: false,
                                                 lookupFailed: false), .drop)
        XCTAssertEqual(SignInFollowUp.followStep(userId: "u", me: "me", shownUserId: "u", isFollowing: true,
                                                 lookupFailed: false), .drop)
    }

    /// 確かめの「新規登録」から開き直しても、続きを持ち越す。登録の側の一言はフォローの文
    func testSignUpRequestKeepsTheFollowUp() async {
        let ask = SignInRequest(reason: SignInPrompt.like, signUpReason: SignInPrompt.likeSignUp,
                                followUp: .like(photoId: "p1"))
        let signUp = SignInPrompt.signUpRequest(from: ask)
        XCTAssertEqual(signUp.followUp, .like(photoId: "p1"))
        XCTAssertEqual(signUp.entry, .signUp)

        let direct = SignInPrompt.direct(signUpReason: SignInPrompt.followSignUp, followUp: .follow(userId: "u"),
                                         userId: nil, isResolving: false)
        XCTAssertEqual(direct?.entry, .signUp, "押したらすぐ登録の側で開く（確かめを挟まない）")
        XCTAssertEqual(direct?.reason, "登録すると、フォローできます")
        XCTAssertEqual(direct?.followUp, .follow(userId: "u"))
        XCTAssertNil(SignInPrompt.direct(signUpReason: SignInPrompt.followSignUp, followUp: .follow(userId: "u"),
                                         userId: nil, isResolving: true), "起動直後の確認中に開いた")
        XCTAssertNil(SignInPrompt.direct(signUpReason: SignInPrompt.followSignUp, followUp: .follow(userId: "u"),
                                         userId: "me", isResolving: false), "ログイン中に開いた")
    }

    /// 人のページ: ログインしていなくても「フォローする」を出す（確認中・ブロック中は出さない）
    func testProfileShowsFollowWhenSignedOut() async {
        XCTAssertTrue(ProfileLine.showsSignedOutFollow(viewerId: nil, resolving: false, userId: "u", blocked: []),
                      "ログインしていない人に人のページのフォローが無い")
        XCTAssertFalse(ProfileLine.showsSignedOutFollow(viewerId: nil, resolving: true, userId: "u", blocked: []))
        XCTAssertFalse(ProfileLine.showsSignedOutFollow(viewerId: "me", resolving: false, userId: "u", blocked: []),
                       "ログイン中は今までどおり canAct の側で出す")
        XCTAssertFalse(ProfileLine.showsSignedOutFollow(viewerId: nil, resolving: false, userId: "u", blocked: ["u"]))
        XCTAssertEqual(ProfileLine.followedNotice(name: "丸田 竜平"), "丸田 竜平 さんをフォローしました")
        XCTAssertEqual(ProfileLine.followedNotice(name: nil), "フォローしました")
    }

    /// ログインできた向き（`userId` が入った）でだけ続きを渡す
    func testHandOverOnlyWhenSignedIn() async {
        XCTAssertEqual(SignInFollowUpHandOver.take(.save(photoId: "p"), userId: "me"), .save(photoId: "p"))
        XCTAssertNil(SignInFollowUpHandOver.take(.save(photoId: "p"), userId: nil))
        XCTAssertNil(SignInFollowUpHandOver.take(nil, userId: "me"))
    }
}
