import XCTest
@testable import JourneyPhoto

/// ホームの「自分の写真」（今日のテーマの参加判定）の読み直し。
///
/// 投稿を閉じた・引き下げたときの読み直しは取り消されないので、
/// 待っている間に人が替わると前の人の答えを書いていた。
@MainActor
final class GalleryMyPhotosTests: XCTestCase {

    @MainActor
    private final class Pending {
        private var waiting: CheckedContinuation<[Photo], Never>?
        func fetch() async -> [Photo] { await withCheckedContinuation { waiting = $0 } }
        var isWaiting: Bool { waiting != nil }
        func release(_ photos: [Photo]) {
            let c = waiting
            waiting = nil
            c?.resume(returning: photos)
        }
    }

    private func mine(_ id: String) throws -> [Photo] {
        try JSONDecoder.api.decode([Photo].self, from: Data(
            "[{\"id\":\"\(id)\",\"src\":\"https://x/\(id).jpg\",\"userId\":\"A\"}]".utf8))
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("待っても立たなかった")
    }

    /// 🔴 A の読みを待っている間にログアウトしたら、遅れて着いた A の写真を書かない
    func testLateAnswerForPreviousPersonIsDropped() async throws {
        let model = GalleryViewModel(gallery: PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)))
        let pending = Pending()
        let loading = Task { await model.loadMyPhotos(viewerId: "A") { await pending.fetch() } }
        await waitUntil { pending.isWaiting }
        await model.loadMyPhotos(viewerId: nil) { [] }
        pending.release(try mine("a1"))
        await loading.value
        XCTAssertTrue(model.myPhotos.isEmpty, "ログアウトした後に前の人の写真が残った")
    }

    /// A → B に替わった後に着いた A の答えも書かない
    func testLateAnswerAfterSwitchingPeopleIsDropped() async throws {
        let model = GalleryViewModel(gallery: PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)))
        let pending = Pending()
        let loading = Task { await model.loadMyPhotos(viewerId: "A") { await pending.fetch() } }
        await waitUntil { pending.isWaiting }
        let b = try mine("b1")
        await model.loadMyPhotos(viewerId: "B") { b }
        pending.release(try mine("a1"))
        await loading.value
        XCTAssertEqual(model.myPhotos.map(\.id), ["b1"])
    }

    /// 同じ人の読みは書く（前提）
    func testAnswerForTheSamePersonIsWritten() async throws {
        let model = GalleryViewModel(gallery: PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)))
        let a = try mine("a1")
        await model.loadMyPhotos(viewerId: "A") { a }
        XCTAssertEqual(model.myPhotos.map(\.id), ["a1"])
    }
}
