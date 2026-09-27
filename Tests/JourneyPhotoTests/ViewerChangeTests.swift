import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 人が替わったとき（ログアウト → 別の人でログイン）に、前の人あての
/// 限定写真を残さない（バグ探し 2026-09-27 #1・#10）。
@MainActor
final class ModerationUserChangeTests: XCTestCase {

    private func store() -> ModerationStore {
        ModerationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    /// 🔴 **ブロック・通報が両方0件でも、人が替われば数が進む。** 進まないと
    /// 検索・ホームが読み直さず、前の人あての「フォロワーのみ」が残る
    func testUserChangeBumpsRevisionEvenWhenNothingIsHidden() async {
        let hidden = store()
        hidden.use(userId: "a")
        let revision = hidden.revision
        let userRevision = hidden.userRevision
        hidden.use(userId: nil)
        XCTAssertEqual(hidden.revision, revision + 1, "ログアウトで数が進んでいない")
        XCTAssertEqual(hidden.userRevision, userRevision + 1)
        hidden.use(userId: "b")
        XCTAssertEqual(hidden.revision, revision + 2, "次の人のログインで数が進んでいない")
        XCTAssertEqual(hidden.userRevision, userRevision + 2)
    }

    /// 同じ人で呼び直しただけでは進めない（画面が全件取得をやり直す）
    func testSameUserDoesNotBump() async {
        let hidden = store()
        hidden.use(userId: nil)
        XCTAssertEqual(hidden.revision, 0, "起動直後の未ログインで数が進んでいる")
        hidden.use(userId: "a")
        let revision = hidden.revision
        hidden.use(userId: "a")
        XCTAssertEqual(hidden.revision, revision)
        XCTAssertEqual(hidden.userRevision, 1)
    }

    /// ブロックでは `userRevision` は進まない（地図が絞るだけで済ませる）
    func testBlockDoesNotCountAsUserChange() async {
        let hidden = store()
        hidden.use(userId: "a")
        hidden.block("x")
        XCTAssertEqual(hidden.userRevision, 1)
        XCTAssertEqual(hidden.revision, 2)
    }
}

/// 限定写真の口を差し替える**前に**出た要求が、差し替えた**後に**戻っても
/// 次の人に前の人あての写真を見せない。
final class RestrictedLoaderSwapTests: XCTestCase {

    /// 先に出た要求を止めておく戸。開くまで答えを返さない
    private actor Gate {
        private var started: CheckedContinuation<Void, Never>?
        private var didStart = false
        private var release: CheckedContinuation<Void, Never>?

        func enter() async {
            didStart = true
            started?.resume()
            started = nil
            await withCheckedContinuation { release = $0 }
        }

        func waitUntilStarted() async {
            if didStart { return }
            await withCheckedContinuation { started = $0 }
        }

        func open() {
            release?.resume()
            release = nil
        }
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func photo(_ id: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"\#(id)","src":"https://x/\#(id).jpg","userId":"u9"}"#.utf8))
    }

    func testAnswerFromBeforeTheSwapIsDropped() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: #"[{"id":"p","src":"https://x/p.jpg","userId":"u1"}]"#)
        let gallery = PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: URLSession(configuration: config),
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        )
        let gate = Gate()
        let previous = try photo("for-a")
        await gallery.setRestrictedLoader {
            await gate.enter()
            return [previous]
        }
        let inFlight = Task { try await gallery.fetchPhotos() }
        await gate.waitUntilStarted()

        // ログアウトしてから B でログインした（B あての限定写真は無い）
        await gallery.setRestrictedLoader(nil)
        await gallery.setRestrictedLoader { [] }
        await gate.open()

        let first = try await inFlight.value
        XCTAssertFalse(first.map(\.id).contains("for-a"), "差し替える前の答えをそのまま出している")
        let next = try await gallery.fetchPhotos()
        XCTAssertFalse(next.map(\.id).contains("for-a"), "差し替える前の答えを次の人の控えに書いている")
        XCTAssertTrue(next.map(\.id).contains("p"))
    }
}

/// 地図の札を、人が替わったあとに読み直したピンへ差し替える（0ce69ea のレビュー）。
/// `MapPin ==` は座標しか比べないので、中身が違っても「同じ」に見える
final class MapPinRefreshTests: XCTestCase {

    private func photo(_ id: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"\#(id)","src":"https://x/\#(id).jpg","coords":{"lat":35.0,"lng":139.0}}"#.utf8))
    }

    @MainActor
    func testSamePlaceWithDifferentPhotosIsReplaced() async throws {
        let before = MapPin.group([try photo("public"), try photo("for-a")])
        let after = MapPin.group([try photo("public")])
        XCTAssertEqual(before.count, 1)
        let refreshed = PhotoMapViewModel.refreshed(before.first, in: after)
        XCTAssertEqual(refreshed?.photos.map(\.id), ["public"], "前の人あての写真が札に残っている")
    }

    @MainActor
    func testVanishedPinIsDropped() async throws {
        let before = MapPin.group([try photo("for-a")])
        XCTAssertNil(PhotoMapViewModel.refreshed(before.first, in: []))
    }
}
