import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 編集した写真の共有の控え（`PhotoEditLedger`・`PhotoEditOverlay`）。
final class PhotoEditLedgerTests: XCTestCase {

    private func photo(_ id: String, title: String, updatedAt: String? = nil,
                       likes: Int? = nil) throws -> Photo {
        let u = updatedAt.map { ",\"updatedAt\":\"\($0)\"" } ?? ""
        let l = likes.map { ",\"likes\":\($0)" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"https://x/\(id).jpg\",\"title\":\"\(title)\"\(u)\(l)}".utf8))
    }

    // MARK: - 重ねる・捨てる

    /// 🔴 **古い一覧の行に、編集後の行を重ねる。** 以前は詳細の `@State` にしか残らず、
    /// ホーム・探す・地図から開き直すと編集前が出ていた
    func testOverlaysTheEditOnAStaleRow() throws {
        var overlay = PhotoEditOverlay()
        overlay.record(try photo("a", title: "新しい題", updatedAt: "2026-10-02T10:00:00.000Z"))
        let stale = try photo("a", title: "古い題", updatedAt: "2026-09-01T00:00:00.000Z")
        XCTAssertEqual(overlay.edited(over: stale)?.displayTitle, "新しい題")
        let listed = overlay.apply(to: [stale, try photo("b", title: "そのまま")])
        XCTAssertEqual(listed.map(\.displayTitle), ["新しい題", "そのまま"])
        XCTAssertFalse(overlay.isEmpty, "まだ追いついていない控えを捨てている")
    }

    /// **一覧が追いついたら控えを捨てる**（更新日時が編集の時刻以降）
    func testDropsTheEditOnceTheListCatchesUp() throws {
        var overlay = PhotoEditOverlay()
        overlay.record(try photo("a", title: "新しい題", updatedAt: "2026-10-02T10:00:00.000Z"))
        let caughtUp = try photo("a", title: "新しい題", updatedAt: "2026-10-02T10:00:00.000Z")
        XCTAssertNil(overlay.edited(over: caughtUp))
        _ = overlay.apply(to: [caughtUp])
        XCTAssertTrue(overlay.isEmpty, "追いついた後も控えを持ち続けている")
    }

    /// **Web で後から直した行（もっと新しい）を、古い控えで上書きしない**
    func testNewerRowFromElsewhereWins() throws {
        var overlay = PhotoEditOverlay()
        overlay.record(try photo("a", title: "アプリで直した", updatedAt: "2026-10-02T10:00:00Z"))
        let newer = try photo("a", title: "Web で直した", updatedAt: "2026-10-02T11:00:00.000Z")
        let listed = overlay.apply(to: [newer])
        XCTAssertEqual(listed.first?.displayTitle, "Web で直した")
        XCTAssertTrue(overlay.isEmpty)
    }

    /// 更新日時が無い行は中身の一致で決める（いいねの数は比べない）
    func testWithoutTimestampsContentDecides() throws {
        var overlay = PhotoEditOverlay()
        overlay.record(try photo("a", title: "新しい題"))
        XCTAssertNotNil(overlay.edited(over: try photo("a", title: "古い題")))
        XCTAssertNil(overlay.edited(over: try photo("a", title: "新しい題", likes: 9)),
                     "いいねの数が違うだけで、追いついた行に重ねている")
    }

    /// 一覧の行のいいねの数（いまの数に差し替え済み）は残す
    func testKeepsTheListedLikeCount() throws {
        var overlay = PhotoEditOverlay()
        overlay.record(try photo("a", title: "新しい題", updatedAt: "2026-10-02T10:00:00Z", likes: 1))
        let stale = try photo("a", title: "古い題", updatedAt: "2026-09-01T00:00:00Z", likes: 12)
        XCTAssertEqual(overlay.apply(to: [stale]).first?.likes, 12)
    }

    /// 束の写真のうち、まだ追いついていない分だけを返す（詳細の束・大きく見る画面に渡す）
    func testPendingOnlyListsRowsNotCaughtUp() throws {
        let ledger = PhotoEditLedger()
        ledger.record(try photo("a", title: "新", updatedAt: "2026-10-02T10:00:00Z"))
        ledger.record(try photo("b", title: "新", updatedAt: "2026-10-02T10:00:00Z"))
        let pending = ledger.pending(in: [try photo("a", title: "旧", updatedAt: "2026-09-01T00:00:00Z"),
                                          try photo("b", title: "新", updatedAt: "2026-10-02T10:00:00Z"),
                                          try photo("c", title: "旧")])
        XCTAssertEqual(Set(pending.keys), ["a"])
    }

    /// **ログアウト・退会で捨てる**（次の人に前の人の編集を重ねない）
    func testClearForgetsEverything() throws {
        let ledger = PhotoEditLedger()
        ledger.record(try photo("a", title: "新", updatedAt: "2026-10-02T10:00:00Z"))
        ledger.clear()
        XCTAssertTrue(ledger.isEmpty)
        XCTAssertNil(ledger.edited(over: try photo("a", title: "旧", updatedAt: "2026-09-01T00:00:00Z")))
    }

    // MARK: - 公開一覧に効くか

    /// 🔴 **公開一覧（ホーム・探す・地図の出どころ）にも重ねる**
    func testPublicGalleryOverlaysEdits() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        StubProtocol.reset()
        defer { StubProtocol.reset() }
        StubProtocol.respond(status: 200, body: """
        [{"id":"a","src":"https://x/a.jpg","title":"古い題","updatedAt":"2026-09-01T00:00:00.000Z"},
         {"id":"b","src":"https://x/b.jpg","title":"別の写真"}]
        """)
        let ledger = PhotoEditLedger()
        let gallery = PublicGalleryService(url: URL(string: "https://site.example.test/app/data/photos.json")!,
                                           session: session,
                                           snapshot: PhotoSnapshotStore(fileName: UUID().uuidString),
                                           edits: ledger)
        ledger.record(try photo("a", title: "新しい題", updatedAt: "2026-10-02T10:00:00.000Z"))
        let photos = try await gallery.fetchPhotos(force: true)
        XCTAssertEqual(photos.map(\.displayTitle), ["新しい題", "別の写真"],
                       "公開一覧に編集後の姿を重ねていない（開き直すと編集前が出る）")
        XCTAssertFalse(ledger.isEmpty)

        // 建て直しで静的 JSON が追いついたら、控えを捨てる
        StubProtocol.respond(status: 200, body: """
        [{"id":"a","src":"https://x/a.jpg","title":"新しい題","updatedAt":"2026-10-02T10:00:00.000Z"}]
        """)
        _ = try await gallery.fetchPhotos(force: true)
        XCTAssertTrue(ledger.isEmpty, "静的 JSON が追いついた後も控えを持ち続けている")
    }
}
