import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 2026-10-18（札 #294）: 期限切れで割れた署名つき画像の**取り直しは、限定公開の控えだけ**。
/// ページ・位置・全件（`photos.json`）はそのまま、読み出し口の回（人の切り替えの印）も進めない。
/// 関係ない画面（その写真を出していない画面）は読み直さない。
@MainActor
final class SignedImageRefetchWiringTests: XCTestCase {

    private let expiredURL = "https://cdn.example.test/private/u2/r.jpg?Expires=1&Signature=a&Key-Pair-Id=K"

    @MainActor
    private final class Calls {
        var count = 0
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

    private func restricted(src: String) throws -> [Photo] {
        try JSONDecoder.api.decode([Photo].self, from: Data("""
        [{"id":"r","src":"\(src)","createdAt":"2026-02-02T00:00:00Z","userId":"u2","audience":"followers"}]
        """.utf8))
    }

    func testExpiringOnlyRefetchesTheRestrictedFeedAndKeepsTheEpoch() async throws {
        let service = gallery()
        let calls = Calls()
        let first = try restricted(src: expiredURL)
        await service.setRestrictedLoader { @MainActor in
            calls.count += 1
            return first
        }
        let model = GalleryViewModel(gallery: service)
        await model.load()
        XCTAssertEqual(calls.count, 1)
        let epoch = await service.restrictedEpoch
        XCTAssertTrue(model.showsImage(URL(string: expiredURL)!))
        XCTAssertFalse(model.showsImage(URL(string: "https://cdn.example.test/private/u9/other.jpg?Expires=1&Signature=a&Key-Pair-Id=K")!))

        // 控えの寿命の中では、読み直しても限定公開は読みに行かない（控えの URL のまま）
        await model.load()
        XCTAssertEqual(calls.count, 1)

        // 関係ない URL では控えを捨てない
        let other = await service.expireRestricted(containing: URL(string: "https://x/unrelated.jpg")!)
        XCTAssertFalse(other)
        await model.load()
        XCTAssertEqual(calls.count, 1)

        // 割れた URL を持つ控えだけ捨てる → 次の読み直し（force なし）で限定公開だけ取り直す
        let expired = await service.expireRestricted(containing: URL(string: expiredURL)!)
        XCTAssertTrue(expired)
        await model.load()
        XCTAssertEqual(calls.count, 2, "控えを捨てても限定公開を取り直していない（期限切れの URL のまま）")
        let after = await service.restrictedEpoch
        XCTAssertEqual(after, epoch, "人は替わっていないのに回を進めた（探すの選択が外れる）")
        if case .loaded(let photos) = model.state {
            XCTAssertEqual(Set(photos.map(\.id)), ["pub", "r"])
        } else {
            XCTFail("一覧が出ていない")
        }
    }

}

/// 画面の配線（SwiftUI は Linux で動かせないので、ソースを照らす）
final class SignedImageRefetchSourceTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// `SignedImageExpiry.signals()` を受ける `.task` の中身（次の `.task` / 修飾子まで）
    private func signalBlock(_ text: String) -> String? {
        guard let start = text.range(of: "SignedImageExpiry.signals()") else { return nil }
        let rest = text[start.lowerBound...]
        let end = rest.range(of: "\n        }\n")?.upperBound ?? rest.endIndex
        return String(rest[..<end])
    }

    func testImageViewsReportFailures() throws {
        XCTAssertTrue(try source("Sources/JourneyPhoto/Features/Common/RemoteImage.swift")
            .contains("SignedImageExpiry.report(url)"), "RemoteImage が割れた画像を報告していない")
        XCTAssertTrue(try source("Sources/JourneyPhoto/Features/Common/DownsampledRemoteImage.swift")
            .contains("SignedImageExpiry.report(url)"), "DownsampledRemoteImage が割れた画像を報告していない")
    }

    func testScreensReloadOnlyTheirOwnPhotosWithoutResettingPages() throws {
        let screens: [(String, String)] = [
            ("Sources/JourneyPhoto/Features/Gallery/GalleryView.swift", "model.showsImage(url)"),
            ("Sources/JourneyPhoto/Features/Search/SearchView.swift", "model.everything.containsImageURL(url)"),
            ("Sources/JourneyPhoto/Features/Profile/MyPageView.swift", "model.photos.containsImageURL(url)"),
        ]
        for (path, ownCheck) in screens {
            guard let block = signalBlock(try source(path)) else {
                XCTFail("\(path) が合図を受けていない"); continue
            }
            XCTAssertTrue(block.contains(ownCheck), "\(path): 自分の写真か確かめずに読み直す")
            XCTAssertTrue(block.contains("gate.shouldRefetch(after: url"), "\(path): 間を置かずに読み直す")
            XCTAssertFalse(block.contains("force: true"), "\(path): ページ・全件まで取り直す（新着が1ページ目に戻る）")
        }
        for path in ["Sources/JourneyPhoto/Features/Gallery/GalleryView.swift",
                     "Sources/JourneyPhoto/Features/Search/SearchView.swift"] {
            XCTAssertTrue(signalBlock(try source(path))?.contains("expireRestricted(containing: url)") ?? false,
                          "\(path): 限定公開の控えを捨てずに読み直す（控えの期限切れ URL のまま）")
        }
    }
}
