import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ホームは**人が替わったら一覧を読み直す**（`GalleryViewModel.switchViewer`）。
///
/// 限定公開の取り口（`setRestrictedLoader`）を、呼ばれたら止まって待つものにして
/// 読み直しの途中の状態を確かめる（StubProtocol の遅延は Linux で落ちるので使わない）
@MainActor
final class HomeViewerSwitchTests: XCTestCase {

    @MainActor
    private final class Pending {
        private var waiting: CheckedContinuation<[Photo], Never>?
        private(set) var calls = 0
        func fetch() async -> [Photo] {
            calls += 1
            return await withCheckedContinuation { waiting = $0 }
        }
        var isWaiting: Bool { waiting != nil }
        func release(_ photos: [Photo]) {
            let c = waiting
            waiting = nil
            c?.resume(returning: photos)
        }
    }

    private func gallery() -> PublicGalleryService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: """
        [{"id":"pub","src":"https://x/p.jpg","createdAt":"2026-01-02T00:00:00Z","userId":"u1"}]
        """)
        return PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: URLSession(configuration: config),
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        )
    }

    private func restricted(_ id: String) throws -> [Photo] {
        try JSONDecoder.api.decode([Photo].self, from: Data("""
        [{"id":"\(id)","src":"https://x/\(id).jpg","createdAt":"2026-02-02T00:00:00Z","userId":"u2","visibility":"followers"}]
        """.utf8))
    }

    private func ids(_ state: GalleryViewModel.State) -> [String]? {
        if case .loaded(let photos) = state { return photos.map(\.id).sorted() }
        return nil
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("待っても立たなかった", file: file, line: line)
    }

    /// 🔴 **A → B で前の人の限定公開を捨て、読み込み中に戻してから読み直す。**
    func testSwitchingPeopleDropsThePreviousList() async throws {
        let service = gallery()
        let forA = try restricted("forA")
        await service.setRestrictedLoader { forA }
        let model = GalleryViewModel(gallery: service)
        await model.load()
        XCTAssertEqual(ids(model.state), ["forA", "pub"], "前提: A の限定公開が入っていない")
        model.use(viewerId: "A", following: ["u2"])

        let pending = Pending()
        await service.setRestrictedLoader { await pending.fetch() }
        let switching = Task { await model.switchViewer(from: "A", to: "B") }
        await waitUntil { pending.isWaiting }
        XCTAssertEqual(model.state, .loading, "読み直しの間も前の人の一覧（限定公開を含む）が出ている")
        XCTAssertTrue(model.followingIds.isEmpty, "読み直しの間、前の人のフォロー中で絞っている")
        pending.release([])
        await switching.value
        XCTAssertEqual(ids(model.state), ["pub"], "B に替わっても A の限定公開が残っている")
    }

    /// 🔴 **読み出し口がまだ前の人のままなら読まない。** 先に読むと、前の人の
    /// 限定公開が次の人の画面に出る。入れ替わったら（画面の `restrictedChanges`）読む
    func testSwitchWaitsForTheLoaderSwap() async throws {
        let service = gallery()
        let forA = try restricted("forA")
        await service.setRestrictedLoader { forA }
        let model = GalleryViewModel(gallery: service)
        await model.load()
        XCTAssertEqual(ids(model.state), ["forA", "pub"])

        // 人は替わったが、読み出し口はまだ A のまま
        await model.switchViewer(from: "A", to: "B")
        XCTAssertEqual(model.state, .loading, "前の人の読み出し口で読み直した（A の限定公開が B に出る）")

        // 入れ替わった後の読み直し（画面では `restrictedChanges` が呼ぶ）
        await service.setRestrictedLoader { [] }
        await model.load()
        XCTAssertEqual(ids(model.state), ["pub"])
    }

    /// **未ログイン → ログインでは一覧を消さない**（出ていたのは公開ぶんだけ）。
    func testSigningInKeepsThePublicListWhileReloading() async throws {
        let service = gallery()
        let model = GalleryViewModel(gallery: service)
        await model.load()
        XCTAssertEqual(ids(model.state), ["pub"])

        let pending = Pending()
        await service.setRestrictedLoader { await pending.fetch() }
        let switching = Task { await model.switchViewer(from: nil, to: "A") }
        await waitUntil { pending.isWaiting }
        XCTAssertEqual(ids(model.state), ["pub"], "ログインしただけで一覧を消して読み込み中に戻した")
        pending.release(try restricted("forA"))
        await switching.value
        XCTAssertEqual(ids(model.state), ["forA", "pub"], "ログインしても限定公開を読み直していない")
    }
}
