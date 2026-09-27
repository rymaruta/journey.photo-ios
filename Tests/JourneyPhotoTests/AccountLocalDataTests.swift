import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 同じ端末で人が替わる瞬間と、退会したあとに端末に残るもの。
@MainActor
final class AccountSwitchTests: XCTestCase {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    /// 🔴 **取りに行った人と、返ってきたときの人が違えば書かない。**
    /// 書くと、前の人のいいね・保存・ブロックが次の人の控えに入る
    /// （起動の同期は `try? await` のあと無条件に入れ替えていた）
    func testLateServerListIsNotWrittenToTheNextPerson() async {
        let store = defaults()
        let likes = FavoritesStore(defaults: store)
        let saves = SavedPhotosStore(defaults: store)
        let hidden = ModerationStore(defaults: store)
        likes.use(userId: "b")
        saves.use(userId: "b")
        hidden.use(userId: "b")

        // a のために取りに行った一覧が、b に替わったあとで返ってきた
        likes.replace(with: ["a のいいね"], for: "a")
        saves.replace(with: ["a の保存"], for: "a")
        hidden.replaceBlocked(with: ["a がブロックした人"], for: "a")

        XCTAssertTrue(likes.ids.isEmpty, "前の人のいいねが次の人に入った")
        XCTAssertTrue(saves.ids.isEmpty, "前の人の保存が次の人に入った")
        XCTAssertTrue(hidden.blockedUserIds.isEmpty, "前の人のブロックが次の人に入った")

        // 読み直しても入っていない（端末の控えにも書いていない）
        likes.use(userId: "b")
        saves.use(userId: "b")
        hidden.use(userId: "b")
        XCTAssertTrue(likes.ids.isEmpty)
        XCTAssertTrue(saves.ids.isEmpty)
        XCTAssertTrue(hidden.blockedUserIds.isEmpty)
    }

    /// 同じ人のままなら入れ替える（今までどおり）
    func testServerListIsWrittenForTheSamePerson() async {
        let likes = FavoritesStore(defaults: defaults())
        likes.use(userId: "a")
        likes.replace(with: ["p1"], for: "a")
        XCTAssertEqual(likes.ids, ["p1"])
    }
}

/// 退会したあとに端末に残るもの。
@MainActor
final class AccountLocalDataTests: XCTestCase {

    private func suite() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 🔴 **退会した人の控えは全部消え、同じ端末の別の人の控えは残る。**
    func testRemovesOnlyThatPersonsData() async throws {
        let defaults = suite()
        let dir = try directory()
        for id in ["gone", "stays"] {
            let likes = FavoritesStore(defaults: defaults); likes.use(userId: id); likes.set("p", favorite: true)
            let saves = SavedPhotosStore(defaults: defaults); saves.use(userId: id); saves.set("p", saved: true)
            let hidden = ModerationStore(defaults: defaults); hidden.use(userId: id)
            hidden.block("x"); hidden.markReported("q")
            let wish = WishlistStore(defaults: defaults); wish.use(userId: id); wish.set("s", wanted: true)
            let albums = JoinedAlbumsStore(defaults: defaults); albums.use(userId: id)
            albums.remember(id: "al", title: "t", token: "tk")
            let seen = SeenStoriesStore(defaults: defaults); seen.use(userId: id); seen.markSeen("st")
            RecentSongsStore(defaults: defaults).remember(Photo.Song(title: "曲", artist: "人", artwork: nil, previewUrl: "https://example.test/\(id).m4a", trackUrl: nil), userId: id)
            let drafts = StoryDraftStore(defaults: defaults, directory: dir); drafts.use(userId: id)
            XCTAssertTrue(drafts.save(imageData: Data([1, 2, 3]), fileName: "a.jpg", contentType: "image/jpeg",
                                      coords: nil, caption: "", location: "", overlays: [], song: nil,
                                      durationSec: 5, savedAt: "2026-09-27T00:00:00Z"))
            defaults.set(true, forKey: "photo-gallery-push-enabled.\(id)")
            defaults.set(true, forKey: "photo-gallery-push-unregister-pending.\(id)")
            PendingVerificationStore(defaults: defaults).remember(email: "\(id)@example.test", username: "uuid-\(id)")
        }

        AccountLocalData.remove(userId: "gone", username: "uuid-gone", defaults: defaults, draftDirectory: dir)

        func check(_ id: String, present: Bool, file: StaticString = #filePath, line: UInt = #line) {
            let says = present ? "消えてはいけない（別の人の控え）" : "退会したのに残っている"
            let likes = FavoritesStore(defaults: defaults); likes.use(userId: id)
            XCTAssertEqual(!likes.ids.isEmpty, present, "いいね: \(says)", file: file, line: line)
            let saves = SavedPhotosStore(defaults: defaults); saves.use(userId: id)
            XCTAssertEqual(!saves.ids.isEmpty, present, "保存: \(says)", file: file, line: line)
            let hidden = ModerationStore(defaults: defaults); hidden.use(userId: id)
            XCTAssertEqual(!hidden.blockedUserIds.isEmpty, present, "ブロック: \(says)", file: file, line: line)
            XCTAssertEqual(!hidden.reportedPhotoIds.isEmpty, present, "通報: \(says)", file: file, line: line)
            let wish = WishlistStore(defaults: defaults); wish.use(userId: id)
            XCTAssertEqual(!wish.spotIds.isEmpty, present, "行きたい場所: \(says)", file: file, line: line)
            let albums = JoinedAlbumsStore(defaults: defaults); albums.use(userId: id)
            XCTAssertEqual(!albums.entries.isEmpty, present, "アルバム: \(says)", file: file, line: line)
            let seen = SeenStoriesStore(defaults: defaults); seen.use(userId: id)
            XCTAssertEqual(!seen.ids.isEmpty, present, "見たストーリー: \(says)", file: file, line: line)
            XCTAssertEqual(!RecentSongsStore(defaults: defaults).songs(userId: id).isEmpty, present,
                           "最近の曲: \(says)", file: file, line: line)
            let drafts = StoryDraftStore(defaults: defaults, directory: dir); drafts.use(userId: id)
            XCTAssertEqual(drafts.draft != nil, present, "ストーリーの書きかけ: \(says)", file: file, line: line)
            XCTAssertEqual(defaults.object(forKey: "photo-gallery-push-enabled.\(id)") != nil, present,
                           "通知の設定: \(says)", file: file, line: line)
            XCTAssertEqual(defaults.object(forKey: "photo-gallery-push-unregister-pending.\(id)") != nil, present,
                           "通知の外し損ねの印: \(says)", file: file, line: line)
            XCTAssertEqual(PendingVerificationStore(defaults: defaults).username(for: "\(id)@example.test") != nil,
                           present, "登録の確認の控え: \(says)", file: file, line: line)
        }
        check("gone", present: false)
        check("stays", present: true)

        // 書きかけの画像も消えている（別の人のぶんは残る）
        let images = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(images.count, 1, "退会した人の書きかけの画像が端末に残っている: \(images)")
    }
}

/// ログアウトの前に通知の宛先を外せなかった回（ログインの期限切れ・圏外）。
@MainActor
final class PushReleaseTests: XCTestCase {

    private func center(_ defaults: UserDefaults, released: @escaping () -> Void) -> PushCenter {
        PushCenter(service: { PushService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                                            tokenProvider: StubTokenProvider(token: nil))) },
                   defaults: defaults, releaseDevice: released)
    }

    private func suite() -> UserDefaults {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(String(repeating: "a", count: 64), forKey: "photo-gallery-apns-token")
        return defaults
    }

    /// 🔴 **前の人の宛先が残ったままログアウトした端末は、端末ごと APNs から外す。**
    /// 前の人の認証はもう無いのでサーバーからは外せず、放っておくと前の人あての
    /// 通知が届き続ける（期限切れでログアウトに倒す経路は何も外していなかった）
    func testLeftoverRegistrationIsReleasedWhenNobodyTakesOver() async {
        let defaults = suite()
        defaults.set("a", forKey: "photo-gallery-push-registered-owner")
        var released = 0
        let push = center(defaults) { released += 1 }
        await push.use(userId: nil)
        XCTAssertEqual(released, 1, "前の人の宛先を残したまま")
        XCTAssertNil(defaults.string(forKey: "photo-gallery-push-registered-owner"))

        // 一度外したら、次の起動で外し直さない
        await push.use(userId: nil)
        XCTAssertEqual(released, 1)
    }

    /// 同じ人がまた開いたときは外さない（起動のたびに外して付け直さない）
    func testSamePersonIsNotReleased() async {
        let defaults = suite()
        defaults.set("a", forKey: "photo-gallery-push-registered-owner")
        var released = 0
        let push = center(defaults) { released += 1 }
        await push.use(userId: "a")
        XCTAssertEqual(released, 0)
        XCTAssertEqual(defaults.string(forKey: "photo-gallery-push-registered-owner"), "a")
    }

    /// 🔴 **ふつうのログアウト（先にサーバーから外せた＝印が無い）では、端末ごと
    /// 外さない。** 外すと、ログアウトのたびに APNs から外して付け直すことになる
    func testOrdinarySignOutDoesNotReleaseTheDevice() async {
        let defaults = suite()
        var released = 0
        let push = center(defaults) { released += 1 }
        await push.use(userId: "a")
        await push.use(userId: nil)
        XCTAssertEqual(released, 0, "外し損ねていないのに端末ごと外している")
    }

    /// 🔴 **ふつうのログアウトが、前の人の印を消さない。** 次の人（b）の認証で
    /// 外せるのは b の宛先だけ——前の人（a）の宛先はサーバーに残っているので、
    /// 印を残してログアウトのあとの `use` に端末ごと外させる
    func testSignOutKeepsSomeoneElsesMark() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        let defaults = suite()
        var released = 0
        let push = PushCenter(service: { PushService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                                                    tokenProvider: StubTokenProvider(token: "t"),
                                                                    session: session)) },
                              defaults: defaults, releaseDevice: { released += 1 })
        await push.use(userId: "b")
        // b の預け直しが落ちて、a の印が残っている
        defaults.set("a", forKey: "photo-gallery-push-registered-owner")
        await push.signingOut()
        XCTAssertNotNil(StubProtocol.lastRequest, "外す要求を出していない（試験の前提が崩れている）")
        XCTAssertEqual(defaults.string(forKey: "photo-gallery-push-registered-owner"), "a",
                       "b のログアウトで a の印を消した（a あての通知が届き続ける）")
        await push.use(userId: nil)
        XCTAssertEqual(released, 1)
    }

    /// ログアウトの前に外せなかったら（ここでは未ログインで 401 相当）、印は残る
    /// ——ログアウトのあとの `use` が端末ごと外す
    func testFailedSignOutUnregisterLeavesTheMark() async {
        let defaults = suite()
        defaults.set("a", forKey: "photo-gallery-push-registered-owner")
        var released = 0
        let push = center(defaults) { released += 1 }
        await push.use(userId: "a")
        await push.signingOut()
        XCTAssertEqual(defaults.string(forKey: "photo-gallery-push-registered-owner"), "a")
        await push.use(userId: nil)
        XCTAssertEqual(released, 1, "外し損ねた宛先がログアウトのあとも残っている")
    }
}
