import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 🔴 **自分で消した・非公開にした写真が、公開一覧に出続けていた。**
///
/// 公開一覧は静的な `photos.json` で、サイトの建て直し（数分）まで古い。端末にも
/// 控え（60秒の記憶と `PhotoSnapshotStore`）が残る。絞り込み（`visible`）は
/// ブロックと通報しか落とさなかったので、消した写真がホーム・探す・地図・保存・
/// 近くの写真に残り、押すと もう無い写真が開いて いいね・保存・コメントが 404 になった。
///
/// 直し方は通報と同じ道（`ModerationStore` → `revision` → `setHidden`）。
/// ここでは**公開一覧の出口**と**控えの持ち方（人ごと・期限つき）**を見る
final class GonePhotosTests: XCTestCase {

    private var session: URLSession!
    private let url = URL(string: "https://site.example.test/app/data/photos.json")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
    }

    override func tearDown() {
        StubProtocol.reset()
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    private func service(snapshot: String = UUID().uuidString) -> PublicGalleryService {
        PublicGalleryService(url: url, session: session, snapshot: PhotoSnapshotStore(fileName: snapshot))
    }

    private let twoPhotos = """
    [{"id":"a","src":"https://x/a.jpg","userId":"me"},
     {"id":"b","src":"https://x/b.jpg","userId":"u2"}]
    """

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    /// 消した写真は、**控えを返す回も**公開一覧から落ちる。公開に戻したら（印を外したら）戻る
    @MainActor
    func testGonePhotoLeavesFeedAndReturnsWhenUnmarked() async throws {
        StubProtocol.respond(status: 200, body: twoPhotos)
        let gallery = service()
        let store = ModerationStore(defaults: defaults())
        store.use(userId: "me")
        var photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a", "b"])

        store.markGone("a", for: "me")
        await gallery.setHidden(store.snapshot)
        // 60秒の控えを返す回（通信しない）でも落ちること
        photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["b"], "消した写真が公開一覧の控えから出ている")
        photos = try await gallery.fetchPhotos(force: true)
        XCTAssertEqual(photos.map(\.id), ["b"], "消した写真が、建て直し前の photos.json から出ている")

        store.unmarkGone("a", for: "me")
        await gallery.setHidden(store.snapshot)
        photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a", "b"], "公開に戻した写真が戻らない")
    }

    /// 画面が持っている並び（`hidden.visible`・`snapshot.visible`）からも落ちる。
    /// **自分の非公開の写し（`published: false`）は残す**——マイページが持つ新しい写しまで消さない
    @MainActor
    func testScreensDropStaleCopiesButKeepOwnPrivateCopy() async throws {
        let store = ModerationStore(defaults: defaults())
        store.use(userId: "me")
        let stale = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"a","src":"/uploads/a.jpg","userId":"me"}"#.utf8))
        let fresh = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"a","src":"/uploads/a.jpg","userId":"me","published":false}"#.utf8))
        let other = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"b","src":"/uploads/b.jpg","userId":"u2"}"#.utf8))
        let revision = store.revision
        store.markGone("a", for: "me")
        XCTAssertGreaterThan(store.revision, revision, "数が進まないと、画面が読み直さない")
        XCTAssertEqual(store.visible([stale, other]).map(\.id), ["b"])
        XCTAssertEqual(store.snapshot.visible([stale, other]).map(\.id), ["b"])
        XCTAssertEqual(store.visible([fresh, other]).map(\.id), ["a", "b"],
                       "自分の非公開の写しまで落としている")
    }

    /// **起動し直しても覚えている**（圏外なら円盤の控えが出る）。期限を過ぎたら忘れる
    @MainActor
    func testGoneMarksPersistAndExpire() async throws {
        let shared = defaults()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ModerationStore(defaults: shared, now: { clock })
        first.use(userId: "me")
        first.markGone("a", for: "me")

        // 起動し直し: 新しい控え・圏外で円盤の一覧
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: twoPhotos)
        _ = try await service(snapshot: name).fetchPhotos()
        StubProtocol.fail(with: URLError(.notConnectedToInternet))

        clock = clock.addingTimeInterval(ModerationStore.goneLifetime - 60)
        let relaunched = ModerationStore(defaults: shared, now: { clock })
        relaunched.use(userId: "me")
        XCTAssertEqual(relaunched.gonePhotoIds, ["a"], "起動し直すと消した写真を忘れている")
        let offline = service(snapshot: name)
        await offline.setHidden(relaunched.snapshot)
        let photos = try await offline.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["b"], "圏外の円盤の控えから、消した写真が出ている")

        clock = clock.addingTimeInterval(120)
        let later = ModerationStore(defaults: shared, now: { clock })
        later.use(userId: "me")
        XCTAssertTrue(later.gonePhotoIds.isEmpty, "期限を過ぎた印を持ち続けている")
        XCTAssertNil(shared.object(forKey: "moderation.gone.me"), "期限を過ぎた印を端末に残している")
    }

    /// **サーバーが「公開中」と答えたら印を外す**（Web で公開に戻した写真が、この端末で
    /// だけ最大7日出なかった）。付けたばかりの印は外さない（自分の一覧は索引の写しで、
    /// 非公開にした直後は古い「公開中」を返しうる）
    @MainActor
    func testConfirmedPublishedClearsOnlySettledMarks() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = ModerationStore(defaults: defaults(), now: { clock })
        store.use(userId: "me")
        store.markGone("a", for: "me")
        store.confirmPublished(["a"], for: "me")
        XCTAssertEqual(store.gonePhotoIds, ["a"], "非公開にした直後の古い答えで印を外した")
        clock = clock.addingTimeInterval(600)
        let before = store.revision
        store.confirmPublished(["a"], for: "me")
        XCTAssertTrue(store.gonePhotoIds.isEmpty, "公開中と分かったのに印が残る")
        XCTAssertNotEqual(store.revision, before, "画面に知らせていない")
        // 別の人の答えでは外さない
        store.markGone("b", for: "me")
        clock = clock.addingTimeInterval(600)
        store.confirmPublished(["b"], for: "someone")
        XCTAssertEqual(store.gonePhotoIds, ["b"])
    }

    /// **人ごと。** 前の人が消した写真の印を、次の人に持ち越さない。
    /// 待っている間に人が替わった回は書かない
    @MainActor
    func testGoneMarksArePerUser() async throws {
        StubProtocol.respond(status: 200, body: twoPhotos)
        let gallery = service()
        let store = ModerationStore(defaults: defaults())
        store.use(userId: "me")
        store.markGone("a", for: "me")
        XCTAssertEqual(store.gonePhotoIds, ["a"])

        let revision = store.revision
        store.use(userId: "u2")
        XCTAssertGreaterThan(store.revision, revision)
        XCTAssertTrue(store.gonePhotoIds.isEmpty, "前の人の印が次の人に残っている")
        await gallery.setHidden(store.snapshot)
        let photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a", "b"], "前の人が消した印で、次の人の一覧を絞っている")

        // 送る前の人（me）の答えが、替わった後に返ってきた回
        store.markGone("b", for: "me")
        XCTAssertTrue(store.gonePhotoIds.isEmpty, "前の人の印を次の人の控えに書いた")

        store.use(userId: "me")
        XCTAssertEqual(store.gonePhotoIds, ["a"], "戻ってきた人の印が消えている")
    }

    /// 退会した人の控えから、印も消す（`AccountLocalData`）
    @MainActor
    func testRemoveDataClearsGoneMarks() async {
        let shared = defaults()
        let store = ModerationStore(defaults: shared)
        store.use(userId: "me")
        store.markGone("a", for: "me")
        XCTAssertNotNil(shared.object(forKey: "moderation.gone.me"))
        store.removeData(for: "me")
        XCTAssertNil(shared.object(forKey: "moderation.gone.me"))
    }
}
