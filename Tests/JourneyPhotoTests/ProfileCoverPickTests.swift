import XCTest
import UIKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// アイコンとカバーを設定したくなる仕組み（#304・2026-10-18）。
/// 候補の選び方・差し出しの決まりと覚え・お礼の呼び方と知らせ・出す順・切り抜きの計算・お礼の口
@MainActor
final class ProfileCoverPickTests: XCTestCase {

    private lazy var suite = "ProfileCoverPickTests.\(UUID().uuidString)"
    private lazy var defaults: UserDefaults = {
        let d = UserDefaults(suiteName: suite)!
        let name = suite
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return d
    }()
    private lazy var center = NotificationCenter()
    private lazy var session: URLSession = {
        ScriptedProtocol.reset()
        addTeardownBlock { ScriptedProtocol.reset() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        return URLSession(configuration: config)
    }()

    private struct Boom: Error {}

    private func photo(_ id: String, likes: Int = 0, at createdAt: String = "2026-10-01T00:00:00Z",
                       published: Bool? = nil, audience: String? = nil, src: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"\(src ?? "https://x/\(id).jpg")\"", "\"likes\":\(likes)",
                      "\"createdAt\":\"\(createdAt)\""]
        if let published { fields.append("\"published\":\(published)") }
        if let audience { fields.append("\"audience\":\"\(audience)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    // MARK: 候補（板 50・50b）

    func testCoverCandidatesAreLikesOrRecentAndOnlyPublic() async throws {
        let photos = [
            try photo("a", likes: 3, at: "2026-10-01T00:00:00Z"),
            try photo("b", likes: 10, at: "2026-09-01T00:00:00Z"),
            try photo("c", likes: 10, at: "2026-10-05T00:00:00Z"),
            try photo("d", likes: 0, at: "2026-10-10T00:00:00Z"),
            try photo("e", likes: 1, at: "2026-10-12T00:00:00Z"),
            try photo("f", likes: 50, at: "2026-10-13T00:00:00Z", published: false),
            try photo("g", likes: 50, at: "2026-10-14T00:00:00Z", audience: "followers"),
            try photo("h", likes: 50, at: "2026-10-15T00:00:00Z", src: " "),
        ]
        XCTAssertEqual(CoverCandidates.cover(photos, sort: .likes).map(\.id), ["c", "b", "a", "e"],
                       "いいねの多い順（同じ数なら新しい順）の4枚")
        XCTAssertEqual(CoverCandidates.cover(photos, sort: .recent).map(\.id), ["e", "d", "c", "a"], "最近の4枚")
        for id in ["f", "g", "h"] {
            XCTAssertFalse(CoverCandidates.isCandidate(photos.first { $0.id == id }!), "\(id) は全体に公開していない")
        }
        XCTAssertEqual(CoverCandidates.avatar(photos).map(\.id), ["e", "d", "c", "a", "b"], "アイコンは最近の順")
        XCTAssertEqual(CoverCandidates.coverCount, 4)
        XCTAssertEqual(CoverCandidates.avatarCount, 10)
    }

    // MARK: 差し出しの決まり（板 51・51b）

    func testFirstPostMeansNoOtherPhotos() async throws {
        let p1 = try photo("p1"), p2 = try photo("p2"), old = try photo("old")
        XCTAssertTrue(CoverOfferRules.isFirstPost(myPhotos: [p1, p2], posted: ["p1", "p2"]))
        XCTAssertTrue(CoverOfferRules.isFirstPost(myPhotos: [], posted: ["p1"]), "一覧に載る前（索引の遅れ）も初めて")
        XCTAssertFalse(CoverOfferRules.isFirstPost(myPhotos: [p1, old], posted: ["p1"]), "前の写真がある")
        XCTAssertFalse(CoverOfferRules.isFirstPost(myPhotos: [p1], posted: []), "何も上がっていない")
    }

    func testLikedCandidateSkipsAskedCurrentCoverAndBelowThreshold() async throws {
        XCTAssertEqual(CoverOfferRules.likedThreshold, 10, "2026-10-18 判断の件数")
        let photos = [
            try photo("low", likes: 9),
            try photo("ten", likes: 10),
            try photo("many", likes: 30),
            try photo("hidden", likes: 99, audience: "closeFriends"),
        ]
        XCTAssertEqual(CoverOfferRules.likedCandidate(photos, asked: [], currentCover: nil)?.id, "many")
        XCTAssertEqual(CoverOfferRules.likedCandidate(photos, asked: ["many"], currentCover: nil)?.id, "ten",
                       "聞いた写真は二度と聞かない")
        XCTAssertEqual(CoverOfferRules.likedCandidate(photos, asked: [], currentCover: "many")?.id, "ten",
                       "いまのカバーと同じ写真は出さない")
        XCTAssertNil(CoverOfferRules.likedCandidate(photos, asked: ["many", "ten"], currentCover: nil),
                     "件数に届いていない・公開範囲を絞った写真は出さない")
    }

    // MARK: 差し出しの覚え（CoverOfferStore）

    private func offers() -> CoverOfferStore { CoverOfferStore(defaults: defaults, isPreview: { false }) }

    private func offer(_ kind: CoverOfferStore.Offer.Kind, _ id: String = "p1") -> CoverOfferStore.Offer {
        .init(kind: kind, photoId: id, imageURL: nil, title: "", hasCover: false, showsCoins: true)
    }

    func testFirstPostSignalIsOnlyUntilChecked() async {
        let store = offers()
        store.notePosted(userId: "u1", photoIds: ["p1"])
        XCTAssertTrue(store.isDeciding, "通知の説明を待たせる印が立たない")
        XCTAssertEqual(store.postRequests, 1)
        store.finishFirstPost(userId: "u1", offer: offer(.firstPost), checked: true)
        XCTAssertFalse(store.isDeciding)
        XCTAssertTrue(store.firstDone("u1"))
        XCTAssertEqual(store.consume()?.kind, .firstPost)
        // 確かめたら、次の投稿では合図しない
        store.notePosted(userId: "u1", photoIds: ["p2"])
        XCTAssertFalse(store.isDeciding)
        XCTAssertEqual(store.postRequests, 1)
        // 確かめられなかった（圏外）回は、次の投稿でもう一度
        let other = offers()
        other.notePosted(userId: "u2", photoIds: ["p9"])
        other.finishFirstPost(userId: "u2", offer: nil, checked: false)
        XCTAssertFalse(other.firstDone("u2"))
        other.notePosted(userId: "u2", photoIds: ["p10"])
        XCTAssertTrue(other.isDeciding)
    }

    func testNeverStopsBothOffersAndPreviewDoesNotCount() async {
        let store = offers()
        store.chooseNever(userId: "u1")
        store.notePosted(userId: "u1", photoIds: ["p1"])
        XCTAssertFalse(store.isDeciding, "「もう聞かないで」のあとに初めての投稿で聞いた")
        store.offerLiked(offer(.liked(12)), userId: "u1")
        XCTAssertFalse(store.hasPending, "「もう聞かないで」のあとにいいねで聞いた")
        let preview = CoverOfferStore(defaults: defaults, isPreview: { true })
        preview.notePosted(userId: "u3", photoIds: ["p1"])
        XCTAssertFalse(preview.isDeciding, "絵を撮る入り方で投稿を数えた")
    }

    /// 人が替わったら、前の人の差し出し・合図・決めている途中を下ろす（2026-10-18 見直し）
    func testUserSwitchDropsOffersAndDeciding() async {
        let store = offers()
        store.notePosted(userId: "u1", photoIds: ["p1"])
        XCTAssertTrue(store.isDeciding)
        store.noteUser("u2")
        XCTAssertFalse(store.isDeciding, "人が替わっても決めている途中が残る（通知の説明などが止まる）")
        XCTAssertTrue(store.postedIds.isEmpty)
        // 決める間に替わった回の差し出しは、いまの人に出さない
        store.finishFirstPost(userId: "u1", offer: offer(.firstPost), checked: true)
        XCTAssertFalse(store.hasPending)
        store.offerLiked(offer(.liked(12)), userId: "u2")
        XCTAssertTrue(store.hasPending)
        store.noteUser(nil)
        XCTAssertFalse(store.hasPending, "ログアウトしても差し出しが残る")
        var s = PostModalSnapshot()
        s.coverOfferBusy = store.isDeciding || store.pending?.kind == .firstPost
        XCTAssertTrue(PostModalGate.pushPrimerWaitIsOver(s))
    }

    /// 前の人の決め終わりで、今の人の「決めている途中」を下ろさない（2026-10-18 再見直し）
    func testPreviousUsersFinishDoesNotClearCurrentDeciding() async {
        let store = offers()
        store.notePosted(userId: "u1", photoIds: ["p1"])
        store.noteUser("u2")
        store.notePosted(userId: "u2", photoIds: ["p2"])
        XCTAssertTrue(store.isDeciding)
        store.finishFirstPost(userId: "u1", offer: nil, checked: false)
        XCTAssertTrue(store.isDeciding, "前の人の決め終わりで今の人の途中を下ろした")
        store.finishFirstPost(userId: "u2", offer: nil, checked: false)
        XCTAssertFalse(store.isDeciding)
    }

    func testCoverFrameOnlyWhenConfirmedMissing() async {
        XCTAssertTrue(CoverFrameRule.shows(exists: false))
        XCTAssertFalse(CoverFrameRule.shows(exists: nil), "分からない（圏外）のに額縁を出す")
        XCTAssertFalse(CoverFrameRule.shows(exists: true))
    }

    func testLikedOfferRemembersPhotoOnlyWhenShown() async {
        let store = offers()
        let liked = offer(.liked(12), "pL")
        store.offerLiked(liked, userId: "u1")
        XCTAssertEqual(store.consume(), liked)
        XCTAssertFalse(store.asked("u1").contains("pL"), "出す前に聞いたことにした")
        store.noteShown(liked, userId: "u1")
        XCTAssertEqual(store.asked("u1"), ["pL"])
        store.noteShown(offer(.firstPost, "pF"), userId: "u1")
        XCTAssertFalse(store.asked("u1").contains("pF"), "初めての投稿の写真をいいねの聞いた写真に数えた")
        store.noteCoverSet(photoId: "pC", userId: "u1")
        XCTAssertEqual(store.currentCover("u1"), "pC")
        store.noteCoverSet(photoId: nil, userId: "u1")
        XCTAssertNil(store.currentCover("u1"), "端末から選んだのに前の写真を覚えたまま")
        CoverOfferStore.removeData(for: "u1", defaults: defaults)
        XCTAssertTrue(store.asked("u1").isEmpty)
    }

    // MARK: お礼（ProfileReward）

    private var today = Date(timeIntervalSince1970: 1_792_300_000)

    private func reward(retry: @escaping () async -> Void = {}) -> ProfileReward {
        let day = today
        return ProfileReward(defaults: defaults, center: center, retryWait: retry, now: { day })
    }

    func testClaimNotifiesOnlyWhenCoinsWereAdded() async {
        let r = reward()
        var notes: [[AnyHashable: Any]] = []
        let token = center.addObserver(forName: .trunkCoinsChanged, object: nil, queue: nil) { notes.append($0.userInfo ?? [:]) }
        defer { center.removeObserver(token) }
        // もらい済み（added 0）: 知らせない・数の知らせも流さない
        let none = await r.claim([.avatar], userId: "u1", available: true) { _ in TrunkWelcomeResult(granted: false, added: 0, coins: 7) }
        XCTAssertNil(none)
        XCTAssertFalse(r.hasPending)
        XCTAssertTrue(notes.isEmpty)
        // 足せた: 知らせと trunkCoinsChanged（coins・userId）
        let got = await r.claim([.cover], userId: "u1", available: true) { _ in TrunkWelcomeResult(granted: true, added: 3, coins: 10) }
        XCTAssertEqual(got, ProfileReward.Grant(kinds: [.cover], added: 3, coins: 10))
        XCTAssertEqual(notes.last?["coins"] as? Int, 10)
        XCTAssertEqual(notes.last?["userId"] as? String, "u1")
        // トランクが使えない・入っていないときは呼ばない
        var calls = 0
        _ = await r.claim([.avatar], userId: "u1", available: false) { _ in calls += 1; return TrunkWelcomeResult(granted: true, added: 3, coins: 3) }
        _ = await r.claim([.avatar], userId: nil, available: true) { _ in calls += 1; return TrunkWelcomeResult(granted: true, added: 3, coins: 3) }
        XCTAssertEqual(calls, 0)
    }

    func testExistingClaimCallsBothOnceAndMergesIntoOneNotice() async {
        let r = reward()
        var kinds: [ProfileReward.Kind] = []
        let grant = await r.claimExisting(userId: "u1", available: true) { kind in
            kinds.append(kind)
            return TrunkWelcomeResult(granted: true, added: 3, coins: kind == .avatar ? 3 : 6, rewarded: true)
        }
        XCTAssertEqual(kinds, [.avatar, .cover])
        XCTAssertEqual(grant, ProfileReward.Grant(kinds: [.avatar, .cover], added: 6, coins: 6, existing: true),
                       "両方そろっていれば1枚の知らせで +6")
        XCTAssertFalse(r.shouldClaimExisting(userId: "u1", available: true), "答えをもらったのに次も呼ぶ")
        XCTAssertFalse(reward().shouldClaimExisting(userId: "u1", available: true), "次の起動でも呼ぶ")
    }

    /// まだ設定していない種類がある（rewarded false）間は、次の起動でも確かめ直す（2026-10-18 見直し）
    func testExistingClaimKeepsCheckingUntilBothAreRewarded() async {
        let r = reward()
        _ = await r.claimExisting(userId: "u1", available: true) { kind in
            TrunkWelcomeResult(granted: kind == .avatar, added: kind == .avatar ? 3 : 0, coins: 3, rewarded: kind == .avatar)
        }
        XCTAssertFalse(reward().shouldClaimExisting(userId: "u1", available: true), "同じ日に何度も確かめ直す（費用が増える）")
        today = today.addingTimeInterval(86_400)
        XCTAssertTrue(reward().shouldClaimExisting(userId: "u1", available: true), "カバーがまだなのに以後呼ばない印を立てた")
        let next = reward()
        _ = await next.claimExisting(userId: "u1", available: true) { _ in
            TrunkWelcomeResult(granted: false, added: 0, coins: 3, rewarded: true)
        }
        today = today.addingTimeInterval(86_400)
        XCTAssertFalse(reward().shouldClaimExisting(userId: "u1", available: true), "2つともお礼が済んだのにまだ呼ぶ")
    }

    /// 待つ間に人が替わった: 頼み直さない（2026-10-18 再見直し）
    func testRetryIsSkippedWhenUserChangedWhileWaiting() async {
        var r: ProfileReward!
        r = reward(retry: { r.noteUser("u2") })
        var calls = 0
        let got = await r.claim([.cover], userId: "u1", available: true) { _ in
            calls += 1
            return TrunkWelcomeResult(granted: false, added: 0, coins: 2, rewarded: false)
        }
        XCTAssertNil(got)
        XCTAssertEqual(calls, 1, "人が替わったのに前の人の分を頼み直した")
    }

    /// 起動のときに読めなかった（圏外）回は、その日のうちにまた確かめてよい
    func testExistingCheckFailureDoesNotUseUpTheDay() async {
        _ = await reward().claimExisting(userId: "u1", available: true) { _ in throw Boom() }
        XCTAssertTrue(reward().shouldClaimExisting(userId: "u1", available: true))
    }

    func testHeadStatusReading() async {
        XCTAssertEqual(ProfileImageFromPhoto.existence(status: 200), true)
        XCTAssertEqual(ProfileImageFromPhoto.existence(status: 404), false)
        XCTAssertNil(ProfileImageFromPhoto.existence(status: 403), "403 を「無い」と読んだ（分からない扱い）")
        XCTAssertNil(ProfileImageFromPhoto.existence(status: 500))
    }

    /// 置いた直後は CDN がまだ「無い」と答えることがある: 足せず印も無ければ、待って1回だけ頼み直す
    func testClaimRetriesOnceWhenNotYetVisible() async {
        var waits = 0
        let r = reward(retry: { waits += 1 })
        var answers = [TrunkWelcomeResult(granted: false, added: 0, coins: 2, rewarded: false),
                       TrunkWelcomeResult(granted: true, added: 3, coins: 5, rewarded: true)]
        let got = await r.claim([.cover], userId: "u1", available: true) { _ in answers.removeFirst() }
        XCTAssertEqual(got?.added, 3)
        XCTAssertEqual(waits, 1)
        // 2回目もだめなら、それ以上は頼まない
        var calls = 0
        _ = await r.claim([.avatar], userId: "u1", available: true) { _ in
            calls += 1
            return TrunkWelcomeResult(granted: false, added: 0, coins: 5, rewarded: false)
        }
        XCTAssertEqual(calls, 2)
        // もらい済み（rewarded true）は頼み直さない
        calls = 0
        _ = await r.claim([.avatar], userId: "u1", available: true) { _ in
            calls += 1
            return TrunkWelcomeResult(granted: false, added: 0, coins: 5, rewarded: true)
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(waits, 2)
    }

    /// 頼んでいる間に人が替わった: いまの人には知らせず、数の知らせも流さない。控えは前の人が次に開いたときに出る
    func testClaimForPreviousUserIsNotShownToNewUser() async {
        let r = reward()
        var notes = 0
        let token = center.addObserver(forName: .trunkCoinsChanged, object: nil, queue: nil) { _ in notes += 1 }
        defer { center.removeObserver(token) }
        let got = await r.claim([.avatar], userId: "u1", available: true) { _ in
            r.noteUser("u2")
            return TrunkWelcomeResult(granted: true, added: 3, coins: 3, rewarded: true)
        }
        XCTAssertNil(got)
        XCTAssertFalse(r.hasPending, "替わった人の画面に前の人のお礼を出す")
        XCTAssertEqual(notes, 0)
        XCTAssertTrue(reward().restore(userId: "u1"), "前の人の控えが残っていない")
    }

    func testExistingClaimKeepsTryingWhenOneCallFailed() async {
        let r = reward()
        _ = await r.claimExisting(userId: "u1", available: true) { kind in
            if kind == .cover { throw Boom() }
            return TrunkWelcomeResult(granted: false, added: 0, coins: 2)
        }
        XCTAssertFalse(r.shouldClaimExisting(userId: "u1", available: true), "同じ起動で二度呼ぶ")
        XCTAssertTrue(reward().shouldClaimExisting(userId: "u1", available: true), "読めなかった回に印を残した（日付も含む）")
    }

    func testNoticeWaitsForEditorAndSkipsLaunchWithWelcome() async {
        let r = reward()
        _ = await r.claimExisting(userId: "u1", available: true) { _ in TrunkWelcomeResult(granted: true, added: 3, coins: 9) }
        XCTAssertFalse(r.mayShowNow(welcomeShownThisLaunch: true), "はじめての硬貨の案内に続けて出す")
        XCTAssertTrue(r.mayShowNow(welcomeShownThisLaunch: false))
        r.editorOpen = true
        XCTAssertFalse(r.mayShowNow(welcomeShownThisLaunch: false), "編集の上に重ねる")
        r.editorOpen = false
        // 出す前に終わっても、次の起動で戻る（控え）
        XCTAssertNotNil(r.consume())
        let next = reward()
        XCTAssertTrue(next.restore(userId: "u1"))
        XCTAssertEqual(next.consume()?.added, 6)
        next.noteShown(userId: "u1")
        XCTAssertFalse(reward().restore(userId: "u1"), "出したのに次の起動でまた出す")
        // 保存のあとのお礼は、はじめての硬貨の案内を出した起動でも出す
        let saved = reward()
        _ = await saved.claim([.avatar], userId: "u2", available: true) { _ in TrunkWelcomeResult(granted: true, added: 3, coins: 3) }
        XCTAssertTrue(saved.mayShowNow(welcomeShownThisLaunch: true))
    }

    func testRewardTexts() async {
        let both = ProfileReward.Grant(kinds: [.avatar, .cover], added: 6, coins: 8, existing: true)
        XCTAssertEqual(ProfileRewardText.breakdown(both), L("アイコン +3 · カバー +3", "Avatar +3 · Cover +3"))
        XCTAssertNil(ProfileRewardText.breakdown(.init(kinds: [.avatar], added: 3, coins: 3)))
        XCTAssertNil(ProfileRewardText.cappedNote(.init(kinds: [.cover], added: 3, coins: 99)))
        XCTAssertNotNil(ProfileRewardText.cappedNote(.init(kinds: [.cover], added: 1, coins: 99)), "上限に当たった回の一言が無い")
        let copy = TrunkCoinNoticeCopy.reward(both)
        XCTAssertEqual(copy.id, "coinReward")
        XCTAssertEqual(TrunkCoinNoticeCopy.welcome(.init(added: 10, coins: 12)).id, "trunk.welcome",
                       "はじめての硬貨の目印が変わった（UI テストが探す）")
    }

    // MARK: 出す順（PostModalGate）

    func testFirstPostOfferComesBeforePushPrimerAndBlocksOthers() async {
        var s = PostModalSnapshot()
        s.coverOfferBusy = true
        XCTAssertFalse(PostModalGate.pushPrimerWaitIsOver(s), "差し出しを決めている間に通知の説明を出す")
        XCTAssertFalse(PostModalGate.reviewMayAsk(s))
        XCTAssertFalse(PostModalGate.trunkMayShow(s))
        XCTAssertFalse(PostModalGate.welcomeMayShow(s))
        s.coverOfferBusy = false
        XCTAssertTrue(PostModalGate.pushPrimerWaitIsOver(s))
    }

    func testRewardAndLikedOfferComeAfterWelcome() async {
        var s = PostModalSnapshot()
        s.launchNoticesDeciding = false
        XCTAssertTrue(PostModalGate.rewardMayShow(s))
        s.welcomePending = true
        XCTAssertFalse(PostModalGate.rewardMayShow(s), "はじめての硬貨の案内より先に出す")
        XCTAssertFalse(PostModalGate.likedOfferMayShow(s))
        s.welcomePending = false
        s.welcomeShowing = true
        XCTAssertFalse(PostModalGate.rewardMayShow(s))
        s.welcomeShowing = false
        s.extrasShowing = true
        XCTAssertFalse(PostModalGate.likedOfferMayShow(s), "お礼の上にいいねの差し出しを重ねる")
        XCTAssertFalse(PostModalGate.trunkMayShow(s))
    }

    // MARK: 切り抜き（板 50b）

    func testCropRectStaysInsideThePhoto() async {
        let image = CGSize(width: 2000, height: 1000)
        // 丸 280 を埋める最小の倍率: 高さが 280 に合う（幅 560）
        let fill = AvatarCropMath.fillSize(image: image, side: 280)
        XCTAssertEqual(fill.width, 560, accuracy: 0.001)
        XCTAssertEqual(fill.height, 280, accuracy: 0.001)
        // 真ん中・等倍: 写真の真ん中の 1000×1000
        let center = AvatarCropMath.cropRect(image: image, side: 280, zoom: 1, offset: .zero)
        XCTAssertEqual(center.minX, 500, accuracy: 0.001)
        XCTAssertEqual(center.minY, 0, accuracy: 0.001)
        XCTAssertEqual(center.width, 1000, accuracy: 0.001)
        XCTAssertEqual(center.height, 1000, accuracy: 0.001)
        // 右へ動かしすぎても、写真の左端で止まる（丸に空きを作らない）
        let left = AvatarCropMath.cropRect(image: image, side: 280, zoom: 1, offset: CGSize(width: 9999, height: 9999))
        XCTAssertEqual(left.minX, 0, accuracy: 0.001)
        XCTAssertEqual(left.minY, 0, accuracy: 0.001)
        // 2倍: 範囲は半分の 500×500
        XCTAssertEqual(AvatarCropMath.cropRect(image: image, side: 280, zoom: 2, offset: .zero).width, 500, accuracy: 0.001)
        // 倍率は 1〜4 に収める
        XCTAssertEqual(AvatarCropMath.cropRect(image: image, side: 280, zoom: 0.2, offset: .zero).width, 1000, accuracy: 0.001)
        XCTAssertEqual(AvatarCropMath.cropRect(image: image, side: 280, zoom: 40, offset: .zero).width, 250, accuracy: 0.001)
    }

    // MARK: お礼の口

    func testServicePostsKindToReward() async throws {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let service = TrunkService(api: api)
        ScriptedProtocol.script = [.init(match: "/user/trunk/reward", status: 200,
                                         body: #"{"granted":true,"added":3,"coins":8}"#, once: true)]
        let result = try await service.reward(.cover)
        XCTAssertEqual(result, TrunkWelcomeResult(granted: true, added: 3, coins: 8))
        XCTAssertNil(result.rewarded, "古いサーバー（rewarded を返さない）は nil")
        let decoded = try JSONDecoder().decode(TrunkWelcomeResult.self,
                                               from: Data(#"{"granted":false,"added":0,"coins":2,"rewarded":false}"#.utf8))
        XCTAssertEqual(decoded.rewarded, false)
        XCTAssertEqual(ScriptedProtocol.calls.last?.method, "POST")
        XCTAssertEqual(ScriptedProtocol.calls.last?.path, "/user/trunk/reward")
        let body = try XCTUnwrap(ScriptedProtocol.calls.last?.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["kind": "cover"])
    }
}
