import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 編集した写真の共有の控え（`PhotoEditLedger`・`PhotoEditOverlay`）。
final class PhotoEditLedgerTests: XCTestCase {

    private func photo(_ id: String, title: String, updatedAt: String? = nil,
                       likes: Int? = nil, published: Bool? = nil, name: String? = nil) throws -> Photo {
        let u = updatedAt.map { ",\"updatedAt\":\"\($0)\"" } ?? ""
        let l = likes.map { ",\"likes\":\($0)" } ?? ""
        let p = published.map { ",\"published\":\($0)" } ?? ""
        let n = name.map { ",\"displayName\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"https://x/\(id).jpg\",\"title\":\"\(title)\"\(u)\(l)\(p)\(n)}".utf8))
    }

    private func gallery(_ ledger: PhotoEditLedger, body: String) -> PublicGalleryService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: body)
        return PublicGalleryService(url: URL(string: "https://site.example.test/app/data/photos.json")!,
                                    session: URLSession(configuration: config),
                                    snapshot: PhotoSnapshotStore(fileName: UUID().uuidString),
                                    edits: ledger)
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    /// 🔴 **重ねた行の表示名は一覧の行のもの。** 静的 JSON は建て直しで今の名前に
    /// 焼き直すが、自分の写真の行は投稿したときの名前のまま——重ねると古い名前に戻った
    func testKeepsTheListedDisplayName() throws {
        var overlay = PhotoEditOverlay()
        overlay.record(try photo("a", title: "新しい題", updatedAt: "2026-10-02T10:00:00Z", name: "古い名前"))
        let stale = try photo("a", title: "古い題", updatedAt: "2026-09-01T00:00:00Z", name: "今の名前")
        let shown = overlay.apply(to: [stale]).first
        XCTAssertEqual(shown?.displayName, "今の名前", "重ねた行で表示名を古い名前に戻している")
        XCTAssertEqual(shown?.displayTitle, "新しい題")
        // 名前だけ違う行は、中身では追いついている（更新日時が無い回）
        var plain = PhotoEditOverlay()
        plain.record(try photo("a", title: "新しい題", name: "古い名前"))
        XCTAssertNil(plain.edited(over: try photo("a", title: "新しい題", name: "今の名前")),
                     "表示名が違うだけで、追いついた行に重ね続けている")
    }

    /// 🔴 **捨てた後に戻った引き直しの答えは書かない**（ログアウトの後に前の人の行を書き戻さない）
    func testRecordAfterClearIsDropped() throws {
        let ledger = PhotoEditLedger()
        let mark = ledger.mark                // 引き直しを始めた
        ledger.clear()                        // 待っている間にログアウト
        ledger.record(try photo("a", title: "前の人の編集", updatedAt: "2026-10-02T10:00:00Z"), since: mark)
        XCTAssertTrue(ledger.isEmpty, "捨てた後に戻った答えで、前の人の行を書き戻している")
        // 捨てる前の回でなければ書く
        ledger.record(try photo("a", title: "今の人の編集", updatedAt: "2026-10-02T10:00:00Z"), since: ledger.mark)
        XCTAssertFalse(ledger.isEmpty)
    }

    /// 🔴 **人が替わったら（限定の口の差し替え）、同じ手番で控えを捨てる。**
    /// 差し替えの後で捨てていた頃は、その間の読み直しで前の人の編集後の姿が重なった
    func testSwitchingTheRestrictedLoaderDropsEdits() async throws {
        let ledger = PhotoEditLedger()
        let gallery = gallery(ledger, body: """
        [{"id":"a","src":"https://x/a.jpg","title":"古い題","updatedAt":"2026-09-01T00:00:00.000Z"}]
        """)
        ledger.record(try photo("a", title: "前の人の編集", updatedAt: "2026-10-02T10:00:00Z"), since: ledger.mark)
        await gallery.setRestrictedLoader(nil)
        let photos = try await gallery.fetchPhotos(force: true)
        XCTAssertEqual(photos.first?.displayTitle, "古い題", "人が替わった後の一覧に、前の人の編集後の姿を重ねている")
        XCTAssertTrue(ledger.isEmpty)
    }

    /// 🔴 **重ねるのは絞り込み（`visible`）より前。** 編集で非公開にした写真を、古い一覧
    /// （まだ公開の行）から落とす。後に重ねると、非公開の行が一覧に出た
    func testEditedToPrivateIsDroppedFromTheList() async throws {
        let ledger = PhotoEditLedger()
        let gallery = gallery(ledger, body: """
        [{"id":"a","src":"https://x/a.jpg","title":"題","updatedAt":"2026-09-01T00:00:00.000Z"},
         {"id":"b","src":"https://x/b.jpg","title":"別"}]
        """)
        ledger.record(try photo("a", title: "題", updatedAt: "2026-10-02T10:00:00Z", published: false),
                      since: ledger.mark)
        let photos = try await gallery.fetchPhotos(force: true)
        XCTAssertEqual(photos.map(\.id), ["b"], "非公開にした写真が一覧に残っている（重ねる順が絞り込みの後）")
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
        ledger.record(try photo("a", title: "新", updatedAt: "2026-10-02T10:00:00Z"), since: ledger.mark)
        ledger.record(try photo("b", title: "新", updatedAt: "2026-10-02T10:00:00Z"), since: ledger.mark)
        let pending = ledger.pending(in: [try photo("a", title: "旧", updatedAt: "2026-09-01T00:00:00Z"),
                                          try photo("b", title: "新", updatedAt: "2026-10-02T10:00:00Z"),
                                          try photo("c", title: "旧")])
        XCTAssertEqual(Set(pending.keys), ["a"])
    }

    /// **ログアウト・退会で捨てる**（次の人に前の人の編集を重ねない）
    func testClearForgetsEverything() throws {
        let ledger = PhotoEditLedger()
        ledger.record(try photo("a", title: "新", updatedAt: "2026-10-02T10:00:00Z"), since: ledger.mark)
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
        ledger.record(try photo("a", title: "新しい題", updatedAt: "2026-10-02T10:00:00.000Z"), since: ledger.mark)
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
