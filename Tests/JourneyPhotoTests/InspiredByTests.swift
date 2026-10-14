import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 「この写真を見て撮影」（`inspiredBy`・2026-10-14）: 投稿で付ける・写真の詳細で出す・編集で外す。
/// サーバーの決まりは photo-gallery の `docs/inspired-by.md` の 6節
@MainActor
final class InspiredByTests: XCTestCase {

    private let sourceId = "aaaaaaaa-1111-4111-8111-111111111111"

    private func photo(_ id: String, location: String? = nil, spotId: String? = nil, inspiredBy: String? = nil,
                       published: Bool? = nil, audience: String? = nil, extra: [String] = []) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://cdn.example.test/\(id).jpg\""]
        if let location { fields.append("\"location\":\"\(location)\"") }
        if let spotId { fields.append("\"spotId\":\"\(spotId)\"") }
        if let inspiredBy { fields.append("\"inspiredBy\":\"\(inspiredBy)\"") }
        if let published { fields.append("\"published\":\(published)") }
        if let audience { fields.append("\"audience\":\"\(audience)\"") }
        fields += extra
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func source(_ json: String) throws -> InspiredBy.Source {
        try XCTUnwrap(try JSONDecoder.api.decode(InspiredBy.Response.self, from: Data(json.utf8)).inspiredBy)
    }

    // MARK: - 形

    func testPhotoRowReadsInspiredBy() async throws {
        XCTAssertEqual(try photo("p", inspiredBy: sourceId).inspiredBy, sourceId)
        XCTAssertNil(try photo("q").inspiredBy)
    }

    /// サーバーが受ける形（英数とハイフン・1〜64文字）だけを送る。合わない値を送ると 400 で投稿ごと止まる
    func testOnlyServerShapedIdsAreSent() async {
        XCTAssertEqual(InspiredBy.normalizedId(" \(sourceId) "), sourceId)
        XCTAssertNil(InspiredBy.normalizedId(nil))
        XCTAssertNil(InspiredBy.normalizedId("  "))
        XCTAssertNil(InspiredBy.normalizedId("notifs#abc"), "# を含む値（文書のキー）")
        XCTAssertNil(InspiredBy.normalizedId("a_b"), "アンダースコアはサーバーが弾く")
        XCTAssertNil(InspiredBy.normalizedId("../user/account"))
        XCTAssertNil(InspiredBy.normalizedId(String(repeating: "a", count: 65)))
        XCTAssertEqual(InspiredBy.normalizedId(String(repeating: "a", count: 64))?.count, 64)
    }

    // MARK: - 投稿

    /// 🔴 **付けないときはキーごと送らない**（null・"" はサーバーで「付けない」だが、送る理由が無い）
    func testSaveBodySendsInspiredByOnlyWhenChosen() async throws {
        var draft = PhotoDraft()
        draft.inspiredBy = sourceId
        let with = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.saveBody(key: "k", publicUrl: "u")))
            as? [String: Any]
        XCTAssertEqual(with?["inspiredBy"] as? String, sourceId)

        draft.inspiredBy = nil
        let without = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.saveBody(key: "k", publicUrl: "u")))
            as? [String: Any]
        XCTAssertFalse(without?.keys.contains("inspiredBy") ?? true, "付けないのにキーを送った")

        draft.inspiredBy = "bad#id"
        let bad = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.saveBody(key: "k", publicUrl: "u")))
            as? [String: Any]
        XCTAssertFalse(bad?.keys.contains("inspiredBy") ?? true, "形の違う値を送った（400 で投稿ごと止まる）")
    }

    /// 付いたかは応答の `photo.inspiredBy` で見る。応答に写真が無い回は「付かなかった」と言わない
    func testDroppedIsReadFromTheSavedPhoto() async throws {
        XCTAssertFalse(InspiredBy.wasDropped(sent: sourceId, saved: try photo("p", inspiredBy: sourceId)))
        XCTAssertTrue(InspiredBy.wasDropped(sent: sourceId, saved: try photo("p")), "見られない元の写真は黙って付かない")
        XCTAssertFalse(InspiredBy.wasDropped(sent: sourceId, saved: nil), "応答に写真が無い＝分からない")
        XCTAssertFalse(InspiredBy.wasDropped(sent: nil, saved: try photo("p")), "送っていない")
    }

    func testDroppedNoteIsAddedToTheSummary() async {
        XCTAssertNil(UploadSummary.withInspiredDropped(nil, dropped: false))
        XCTAssertEqual(UploadSummary.withInspiredDropped("曲", dropped: false), "曲")
        XCTAssertEqual(UploadSummary.withInspiredDropped(nil, dropped: true), InspiredBy.droppedNote)
        let both = UploadSummary.withInspiredDropped("前の知らせ", dropped: true)
        XCTAssertTrue(both?.hasPrefix("前の知らせ") ?? false)
        XCTAssertTrue(both?.contains(L("元の写真は付けられませんでした", "original photo couldn't be attached")) ?? false)
    }

    // MARK: - 投稿の画面（送る流れ）

    private func model() -> UploadViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: config)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        return UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                               photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
    }

    private func shot(_ byte: UInt8) -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: Data(repeating: byte, count: 16), fileName: "photo\(byte).jpg",
                               contentType: "image/jpeg", exif: nil, coords: nil, takenOn: nil)
    }

    private let presign = """
    {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
    """

    private func saveBodies() -> [[String: Any]] {
        ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.compactMap { call in
            call.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    private func pick() -> InspiredBy.Pick {
        InspiredBy.Pick(id: sourceId, title: "夕焼け", thumbURL: "https://cdn.example.test/s.jpg",
                        authorName: "あき", location: "観音寺市")
    }

    /// 🔴 **投稿の先頭の1枚だけに付ける**——全部に付けると、元の作者に同じ通知が枚数ぶん届く
    func testOnlyTheFirstPhotoOfThePostCarriesInspiredBy() async {
        ScriptedProtocol.reset()
        defer { ScriptedProtocol.reset() }
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presign),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200,
                  body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg","inspiredBy":"\#(sourceId)"}}"#),
        ]
        let m = model()
        m.items = [PendingPhoto(prepared: shot(1)), PendingPhoto(prepared: shot(2))]
        m.inspired = pick()
        await m.submit()
        let bodies = saveBodies()
        XCTAssertEqual(bodies.count, 2, "前提: 2枚とも保存した")
        XCTAssertEqual(bodies.first?["inspiredBy"] as? String, sourceId, "先頭の1枚に付いていない")
        XCTAssertNil(bodies.last?["inspiredBy"], "2枚目にも付けた（通知が2回届く）")
        XCTAssertTrue(m.didPostAll, "付いた回は閉じてよい")
        XCTAssertNil(m.inspired, "全部上がったら選んだ元の写真も片づける")
    }

    /// 🔴 **付かなかった（非公開になった等）ら閉じずに短く知らせる**。投稿自体は成功
    func testDroppedInspiredByKeepsTheScreenOpenWithANote() async {
        ScriptedProtocol.reset()
        defer { ScriptedProtocol.reset() }
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presign),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        let m = model()
        m.items = [PendingPhoto(prepared: shot(1))]
        m.inspired = pick()
        await m.submit()
        XCTAssertTrue(m.items.isEmpty, "投稿は成功（写真は並びから外れる）")
        XCTAssertFalse(m.didPostAll, "閉じると、付かなかったことが伝わらない")
        XCTAssertEqual(m.errorMessage, InspiredBy.droppedNote)
    }

    /// 🔴 **1枚目に付いたあと2枚目が落ちてやり直しても、2枚目には付けない**（通知を二重にしない）
    func testRetryDoesNotAttachAgain() async {
        ScriptedProtocol.reset()
        defer { ScriptedProtocol.reset() }
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presign),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200,
                  body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg","inspiredBy":"\#(sourceId)"}}"#,
                  once: true),
            .init(match: "/upload/save", status: 500, body: #"{"error":"だめでした"}"#, once: true),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p2","src":"https://x/p2.jpg"}}"#),
        ]
        let m = model()
        m.items = [PendingPhoto(prepared: shot(1)), PendingPhoto(prepared: shot(2))]
        m.inspired = pick()
        await m.submit()
        XCTAssertEqual(m.items.count, 1, "前提: 2枚目が残った")
        await m.submit()
        let bodies = saveBodies()
        XCTAssertEqual(bodies.count, 3)
        XCTAssertEqual(bodies[0]["inspiredBy"] as? String, sourceId)
        XCTAssertNil(bodies[1]["inspiredBy"])
        XCTAssertNil(bodies[2]["inspiredBy"], "やり直しで2枚目に付けた")
        XCTAssertNil(m.errorMessage, "2枚目に付けていないので「付かなかった」とは言わない")
    }

    /// 🔴 **1枚目の保存の答えが来ない（時間切れ・500＝届いたか分からない）間は、2枚目に載せない。
    /// やり直した1枚目に載せる**——2枚目に載せると、1枚目が実は通っていたとき通知が2回届く
    func testUnsureFirstSaveKeepsItAndTheRetryCarriesIt() async {
        ScriptedProtocol.reset()
        defer { ScriptedProtocol.reset() }
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presign),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"時間切れ"}"#, once: true),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p2","src":"https://x/p2.jpg"}}"#,
                  once: true),
            .init(match: "/upload/save", status: 200,
                  body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg","inspiredBy":"\#(sourceId)"}}"#),
        ]
        let m = model()
        m.items = [PendingPhoto(prepared: shot(1)), PendingPhoto(prepared: shot(2))]
        m.inspired = pick()
        await m.submit()
        XCTAssertEqual(m.items.count, 1, "前提: 1枚目が届いたか分からないまま残った")
        await m.submit()
        let bodies = saveBodies()
        XCTAssertEqual(bodies.count, 3)
        XCTAssertEqual(bodies[0]["inspiredBy"] as? String, sourceId, "1枚目に載せていない")
        XCTAssertNil(bodies[1]["inspiredBy"], "届いたか分からない1枚目のあと、2枚目にも載せた（通知が2回届きうる）")
        XCTAssertEqual(bodies[2]["inspiredBy"] as? String, sourceId, "やり直した1枚目に載せていない")
    }

    /// 1枚目が**確実に届いていない**（鍵を取れない）なら、次の写真に引き継ぐ
    func testUndeliveredFirstPhotoHandsItToTheNext() async {
        ScriptedProtocol.reset()
        defer { ScriptedProtocol.reset() }
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 500, body: #"{"error":"だめ"}"#, once: true),
            .init(match: "/upload/presigned-url", status: 200, body: presign),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200,
                  body: #"{"success":true,"photo":{"id":"p2","src":"https://x/p2.jpg","inspiredBy":"\#(sourceId)"}}"#),
        ]
        let m = model()
        m.items = [PendingPhoto(prepared: shot(1)), PendingPhoto(prepared: shot(2))]
        m.inspired = pick()
        await m.submit()
        let bodies = saveBodies()
        XCTAssertEqual(bodies.count, 1, "前提: 1枚目は保存まで行かない")
        XCTAssertEqual(bodies[0]["inspiredBy"] as? String, sourceId, "届いていない1枚目から引き継いでいない")
    }

    /// 載せる1枚を帯から外したら次の写真に引き継ぐ。付け終えたら、下書きに残さない
    func testCarrierRules() async {
        var c = InspiredBy.Carrier<Int>()
        let p = pick()
        XCTAssertEqual(c.idToSend(for: 1, pick: p), sourceId)
        XCTAssertNil(c.idToSend(for: 2, pick: p), "載せる1枚は1枚目に決まっている")
        XCTAssertTrue(c.keepsInDraft(unsure: []))
        XCTAssertFalse(c.keepsInDraft(unsure: [1]), "届いたか分からない1枚がある間は下書きに残さない")
        c.removed(1)
        XCTAssertEqual(c.idToSend(for: 2, pick: p), sourceId, "外したのに引き継がない")
        c.saved(2)
        XCTAssertNil(c.idToSend(for: 3, pick: p))
        XCTAssertNil(c.idToSend(for: 2, pick: p), "付け終えた")
        XCTAssertFalse(c.keepsInDraft(unsure: []), "付け終えたのに下書きに残す")
        c.notDelivered(2)
        XCTAssertNil(c.idToSend(for: 3, pick: p), "付け終えた後は引き継がない")
        var empty = InspiredBy.Carrier<Int>()
        XCTAssertNil(empty.idToSend(for: 1, pick: nil), "選んでいなければ載せない")
    }

    /// 🔴 **下書きから続けても二重に付かない**: 1枚目に付いて2枚目が落ちる → 下書きに保存 →
    /// 開き直してやり直す → 2枚目の本文に inspiredBy が無い
    func testDraftAfterAttachingDoesNotAttachAgain() async throws {
        ScriptedProtocol.reset()
        defer { ScriptedProtocol.reset() }
        let defaults = UserDefaults(suiteName: "InspiredByTests.\(UUID().uuidString)")!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("InspiredByTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        func drafted() -> UploadViewModel {
            let m = model()
            m.drafts = UploadDraftStore(defaults: defaults, directory: directory)
            m.draftOwner = "a"
            m.makeDraftThumbnail = { _ in nil }
            return m
        }
        // 1枚目は付いて上がる。2枚目は鍵を取れずに落ちる（届いていない＝下書きに保存できる）
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presign, once: true),
            .init(match: "/upload/presigned-url", status: 500, body: #"{"error":"だめ"}"#, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200,
                  body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg","inspiredBy":"\#(sourceId)"}}"#),
        ]
        let first = drafted()
        first.items = [PendingPhoto(prepared: shot(1)), PendingPhoto(prepared: shot(2))]
        first.inspired = pick()
        await first.submit()
        XCTAssertEqual(first.items.count, 1, "前提: 2枚目が残った")
        XCTAssertTrue(first.saveDraft(), "前提: 下書きに保存できる")

        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presign),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p2","src":"https://x/p2.jpg"}}"#),
        ]
        let next = drafted()
        let restored = await next.restoreDraft()
        XCTAssertTrue(restored)
        XCTAssertNil(next.inspired, "付け終えた元の写真が下書きから戻った")
        await next.submit()
        XCTAssertNil(saveBodies().last?["inspiredBy"], "下書きから続けた2枚目にも付けた（通知が2回届く）")
    }

    /// 🔴 **開き直した下書きで付ける1枚が上がったら、記録にある下書きの元の写真も消す**
    /// （残りの写真が落ちたあと閉じて開き直すと、別の写真に付け直していた）
    func testPostingTheCarrierClearsInspiredFromTheStoredDraft() async throws {
        ScriptedProtocol.reset()
        defer { ScriptedProtocol.reset() }
        let defaults = UserDefaults(suiteName: "InspiredByTests.\(UUID().uuidString)")!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("InspiredByTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UploadDraftStore(defaults: defaults, directory: directory)
        let first = model()
        first.drafts = store
        first.draftOwner = "a"
        first.items = [PendingPhoto(prepared: shot(1)), PendingPhoto(prepared: shot(2))]
        first.inspired = pick()
        XCTAssertTrue(first.saveDraft())

        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presign, once: true),
            .init(match: "/upload/presigned-url", status: 500, body: #"{"error":"だめ"}"#),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200,
                  body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg","inspiredBy":"\#(sourceId)"}}"#),
        ]
        let next = model()
        next.drafts = store
        next.draftOwner = "a"
        next.makeDraftThumbnail = { _ in nil }
        let restored = await next.restoreDraft()
        XCTAssertTrue(restored)
        await next.submit()
        XCTAssertEqual(store.draft(for: "a")?.items.count, 1, "前提: 2枚目が下書きに残った")
        XCTAssertNil(store.draft(for: "a")?.inspired, "付け終えたのに記録の下書きに元の写真が残った")
    }

    /// 選んだ元の写真は書きかけに数え、下書きに残り、開き直すと戻る
    func testInspiredIsPartOfTheDraft() async throws {
        let defaults = UserDefaults(suiteName: "InspiredByTests.\(UUID().uuidString)")!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("InspiredByTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = model()
        XCTAssertFalse(first.hasDraft)
        first.inspired = pick()
        XCTAssertTrue(first.hasDraft, "元の写真を選んだだけの画面を黙って閉じさせない")
        first.items = [PendingPhoto(prepared: shot(1))]
        first.drafts = UploadDraftStore(defaults: defaults, directory: directory)
        first.draftOwner = "a"
        XCTAssertTrue(first.saveDraft())

        let next = model()
        next.drafts = UploadDraftStore(defaults: defaults, directory: directory)
        next.draftOwner = "a"
        next.makeDraftThumbnail = { _ in nil }
        let restored = await next.restoreDraft()
        XCTAssertTrue(restored)
        XCTAssertEqual(next.inspired, pick(), "下書きから元の写真が戻らない")
    }

    /// 前の版の下書き（`inspired` の無い記録）もそのまま読める
    func testOldDraftWithoutInspiredStillDecodes() async throws {
        let json = #"{"items":[],"tagsText":"","category":"","published":true,"audience":"everyone","groupsAsOnePost":false,"savedAt":"2026-10-11T00:00:00Z"}"#
        let draft = try JSONDecoder().decode(UploadDraftStore.Draft.self, from: Data(json.utf8))
        XCTAssertNil(draft.inspired)
    }

    func testPickFromPhotoUsesTheLightestImageAndTitle() async throws {
        let p = try photo("s", location: "観音寺市", extra: [#""title":{"ja":"雲海","en":"Sea of clouds"}"#,
                                                          #""thumbSm":"https://cdn.example.test/s-256.webp""#,
                                                          #""displayName":"あき""#])
        let pick = InspiredBy.Pick(photo: p)
        XCTAssertEqual(pick.id, "s")
        XCTAssertEqual(pick.thumbURL, "https://cdn.example.test/s-256.webp")
        XCTAssertEqual(pick.authorName, "あき")
        XCTAssertFalse(pick.label.isEmpty)
        let untitled = InspiredBy.Pick(photo: try photo("u", location: "観音寺市"))
        XCTAssertEqual(untitled.thumbURL, "https://cdn.example.test/u.jpg", "軽い版が無ければ本体")
        XCTAssertEqual(untitled.label, LocationMatch.display("観音寺市"), "題が無ければ撮影地")
    }

    // MARK: - 元の写真を選ぶ

    /// 付けられるのは公開で全員に見せている写真だけ（サーバーが黙って付けないものを選ばせない）。自分の写真も可
    func testSavedCandidatesAreOnlyPublicPhotos() async throws {
        let feed = [try photo("pub"), try photo("other")]
        let mine = [try photo("mineDraft", published: false), try photo("mineFollowers", audience: "followers"),
                    try photo("minePublic", published: true)]
        let found = InspiredBy.savedCandidates(ids: ["pub", "mineDraft", "mineFollowers", "minePublic", "gone"],
                                               feed: feed, mine: mine)
        XCTAssertEqual(Set(found.map(\.id)), ["pub", "minePublic"])
        XCTAssertTrue(InspiredBy.savedCandidates(ids: ["pub"], feed: nil, mine: nil).isEmpty)
    }

    /// 行きたい場所の写真: 撮影地のスラッグか台帳のスポット（`SPOT-<slug>`）が「行きたい」に入っている写真。
    /// いま書いている撮影地と同じ場所の写真を先に
    func testWishCandidatesMatchPlaceAndSpotKeysAndPutTheCurrentPlaceFirst() async throws {
        let index = [try JSONDecoder().decode(OfficialSpot.self, from: Data(
            #"{"spotId":"sp_0123456789ab","slug":"takaya-shrine","name":"高屋神社","stage":"published"}"#.utf8))]
        let feed = [
            try photo("kyoto", location: "京都", extra: [#""createdAt":"2026-10-03T00:00:00Z""#]),
            try photo("spot", location: "どこか", spotId: "sp_0123456789ab", extra: [#""createdAt":"2026-10-02T00:00:00Z""#]),
            try photo("here", location: "観音寺市", extra: [#""createdAt":"2026-10-01T00:00:00Z""#]),
            try photo("none", location: "大阪", extra: [#""createdAt":"2026-10-04T00:00:00Z""#]),
            try photo("private", location: "京都", published: false),
        ]
        let keys: Set<String> = [LocationSlug.make("京都"), LocationSlug.make("観音寺市"), SavedSpotKey.official("takaya-shrine")]
        let found = InspiredBy.wishCandidates(keys: keys, feed: feed, index: index, currentLocation: "観音寺市")
        XCTAssertEqual(found.map(\.id), ["here", "kyoto", "spot"])
        XCTAssertEqual(InspiredBy.wishCandidates(keys: keys, feed: feed, index: nil).map(\.id), ["kyoto", "here"],
                       "索引が無ければスポットの鍵では当てない（落とすだけ）")
        XCTAssertTrue(InspiredBy.wishCandidates(keys: [], feed: feed, index: index).isEmpty)
    }

    // MARK: - 写真の詳細

    func testSourceDecodesBothTitleShapesAndFallbacks() async throws {
        let plain = try source(#"{"inspiredBy":{"id":"s","title":"雲海","src":"https://x/s.jpg","userId":"u","displayName":"あき","username":"aki"}}"#)
        XCTAssertEqual(plain.displayTitle, "雲海")
        XCTAssertEqual(plain.thumbURL?.absoluteString, "https://x/s.jpg", "軽い版が無ければ本体")
        XCTAssertEqual(plain.authorName, "あき")
        let localized = try source(#"{"inspiredBy":{"id":"s","title":{"ja":"雲海","en":"Clouds"},"src":"https://x/s.jpg","thumbSrc":"https://x/s-512.webp","userId":"u","username":"aki"}}"#)
        XCTAssertFalse(localized.displayTitle.isEmpty)
        XCTAssertEqual(localized.thumbURL?.absoluteString, "https://x/s-512.webp")
        XCTAssertEqual(localized.authorName, "@aki", "表示名が無ければ @名")
        let nameless = try source(#"{"inspiredBy":{"id":"s","src":"https://x/s.jpg","userId":"u","thumbSrc":""}}"#)
        XCTAssertNil(nameless.authorName, "名前を作らない")
        XCTAssertEqual(nameless.thumbURL?.absoluteString, "https://x/s.jpg", "空の thumbSrc は無いのと同じ")
        XCTAssertNil(try JSONDecoder.api.decode(InspiredBy.Response.self, from: Data(#"{"inspiredBy":null}"#.utf8)).inspiredBy)
    }

    /// 🔴 **送った先の写真で前の写真の行を出さない**（`Loaded` が写真と元の写真を持つ）
    func testStageOnlyUsesTheResultForThisPhotoAndSource() async throws {
        let src = try source(#"{"inspiredBy":{"id":"s","src":"https://x/s.jpg"}}"#)
        let loaded = InspiredBy.Loaded(userId: "u1", photoId: "a", sourceId: sourceId, source: src)
        XCTAssertEqual(InspiredBy.stage(photoId: "a", inspiredBy: sourceId, userId: "u1", loaded: loaded).source, src)
        XCTAssertEqual(InspiredBy.stage(photoId: "b", inspiredBy: sourceId, userId: "u1", loaded: loaded), .loading,
                       "前の写真の分を使った")
        XCTAssertEqual(InspiredBy.stage(photoId: "a", inspiredBy: "other-id", userId: "u1", loaded: loaded), .loading,
                       "付け替えた元の写真で前の分を使った")
        XCTAssertNil(InspiredBy.stage(photoId: "b", inspiredBy: sourceId, userId: "u1", loaded: loaded).source)
        XCTAssertEqual(InspiredBy.stage(photoId: "a", inspiredBy: nil, userId: "u1", loaded: loaded), .none)
        XCTAssertEqual(InspiredBy.stage(photoId: "a", inspiredBy: sourceId, userId: nil, loaded: loaded), .none,
                       "口は認証が要る（ログアウト中は出さない）")
        XCTAssertEqual(InspiredBy.stage(photoId: "a", inspiredBy: sourceId, userId: "u2", loaded: loaded), .loading,
                       "人が替わったのに前の人の読み取りを使った（ブロックの関係は人ごとに違う）")
        let gone = InspiredBy.Loaded(userId: "u1", photoId: "a", sourceId: sourceId, source: nil)
        XCTAssertNil(InspiredBy.stage(photoId: "a", inspiredBy: sourceId, userId: "u1", loaded: gone).source,
                     "null・404 は何も出さない")
        XCTAssertEqual(InspiredBy.loadKey(photoId: "a", inspiredBy: sourceId, userId: "u1"), "u1|a>\(sourceId)")
        XCTAssertNotEqual(InspiredBy.loadKey(photoId: "a", inspiredBy: sourceId, userId: "u2"),
                          InspiredBy.loadKey(photoId: "a", inspiredBy: sourceId, userId: "u1"), "人が替わっても読み直さない")
        XCTAssertEqual(InspiredBy.loadKey(photoId: "a", inspiredBy: nil, userId: "u1"), "")
        XCTAssertEqual(InspiredBy.loadKey(photoId: "a", inspiredBy: sourceId, userId: nil), "")
    }

    /// 元の写真を開く1枚: 公開一覧に居ればその行（説明まで揃う）、居なければ要約から作る
    func testPhotoToOpenPrefersTheFeedRow() async throws {
        let src = try source(#"{"inspiredBy":{"id":"s","title":{"ja":"雲海","en":"Clouds"},"src":"https://x/s.jpg","location":"観音寺市","userId":"u","displayName":"あき"}}"#)
        let listed = try photo("s", extra: [#""description":"朝5時""#])
        let fromFeed = try XCTUnwrap(InspiredBy.photoToOpen(src, feed: [listed]))
        XCTAssertTrue(fromFeed.fromPublicFeed)
        XCTAssertEqual(fromFeed.photo, listed)
        let built = try XCTUnwrap(InspiredBy.photoToOpen(src, feed: []))
        XCTAssertFalse(built.fromPublicFeed, "一覧に居ない写真は個別ページがまだ無いかもしれない")
        XCTAssertEqual(built.photo.id, "s")
        XCTAssertEqual(built.photo.src, "https://x/s.jpg")
        XCTAssertEqual(built.photo.location, "観音寺市")
        XCTAssertEqual(built.photo.userId, "u")
        XCTAssertEqual(built.photo.title, .byLocale(["ja": "雲海", "en": "Clouds"]))
        XCTAssertTrue(InspiredBy.spokenLabel(src).contains("あき"))
    }

    // MARK: - 口（GET /user/inspired/{id}）

    private func photoService() -> PhotoService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: config)
        return PhotoService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                           tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    func testInspiredSourceReadsTheAppEndpoint() async throws {
        ScriptedProtocol.reset()
        defer { ScriptedProtocol.reset() }
        ScriptedProtocol.script = [.init(match: "/user/inspired/p1", status: 200,
                                         body: #"{"inspiredBy":{"id":"s","src":"https://x/s.jpg","userId":"u"}}"#)]
        let found = try await photoService().inspiredSource(photoId: "p1")
        XCTAssertEqual(found?.id, "s")
        XCTAssertEqual(ScriptedProtocol.calls.first?.method, "GET")
        XCTAssertEqual(ScriptedProtocol.calls.first?.path, "/user/inspired/p1")
    }

    /// null と 404 は「出すものが無い」（nil）。500 は投げる（画面は何も出さず、覚えない）
    func testInspiredSourceNullAnd404AreNilAnd500Throws() async throws {
        ScriptedProtocol.reset()
        defer { ScriptedProtocol.reset() }
        ScriptedProtocol.script = [.init(match: "/user/inspired/p1", status: 200, body: #"{"inspiredBy":null}"#),
                                   .init(match: "/user/inspired/p2", status: 404, body: #"{"error":"写真が見つかりません"}"#),
                                   .init(match: "/user/inspired/p3", status: 500, body: #"{"error":"取得に失敗しました"}"#)]
        let service = photoService()
        let none = try await service.inspiredSource(photoId: "p1")
        XCTAssertNil(none)
        let missing = try await service.inspiredSource(photoId: "p2")
        XCTAssertNil(missing)
        do {
            _ = try await service.inspiredSource(photoId: "p3")
            XCTFail("500 を「無い」にした")
        } catch {}
    }

    // MARK: - 編集で外す

    func testPatchClearsInspiredByWithNull() async throws {
        var patch = PhotoPatch()
        XCTAssertTrue(patch.isEmpty)
        patch.clearInspiredBy = true
        XCTAssertFalse(patch.isEmpty, "外すだけの保存が「更新項目がありません」にならない")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(patch), encoding: .utf8))
        XCTAssertTrue(json.contains(#""inspiredBy":null"#), json)
        let untouched = try XCTUnwrap(String(data: JSONEncoder().encode(PhotoPatch()), encoding: .utf8))
        XCTAssertFalse(untouched.contains("inspiredBy"), "触らないのに外した")
    }

    func testEditRemovesOnlyWhenAttachedAndChosen() async throws {
        let attached = try photo("p", inspiredBy: sourceId)
        var fields = EditPhotoChanges.Fields(opening: attached)
        XCTAssertFalse(fields.removeInspired, "開いたときは外さない")
        XCTAssertFalse(EditPhotoChanges.hasChanges(photo: attached, openedAudience: .everyone, fields: fields))
        fields.removeInspired = true
        XCTAssertTrue(EditPhotoChanges.patch(photo: attached, openedAudience: .everyone, fields: fields).clearInspiredBy)
        XCTAssertTrue(EditPhotoChanges.hasChanges(photo: attached, openedAudience: .everyone, fields: fields),
                      "外すを選んだまま閉じると黙って捨てる")

        let plain = try photo("q")
        var plainFields = EditPhotoChanges.Fields(opening: plain)
        plainFields.removeInspired = true
        XCTAssertFalse(EditPhotoChanges.patch(photo: plain, openedAudience: .everyone, fields: plainFields).clearInspiredBy,
                       "付いていない写真に null を送った")
        XCTAssertTrue(InspiredBy.isAttached(attached))
        XCTAssertFalse(InspiredBy.isAttached(plain))
    }

    // MARK: - 画面写真の見本（Debug の鍵）

    /// 見本の鍵は**見本の利用者で入っているときだけ**効く（Release では `#if DEBUG` の外＝必ず false）
    func testPreviewKeysOnlyForThePreviewUser() async {
        let defaults = UserDefaults.standard
        let keys = [PreviewSession.defaultsKey, PreviewSession.uploadSampleKey, PreviewSession.inspiredSampleKey]
        defer { for key in keys { defaults.removeObject(forKey: key) } }
        for key in keys { defaults.removeObject(forKey: key) }
        XCTAssertFalse(PreviewSession.opensUploadSample)
        XCTAssertFalse(PreviewSession.showsInspiredSample)
        XCTAssertNil(PreviewUploadSample.capture(), "鍵の無いときは見本を入れない")
        defaults.set(true, forKey: PreviewSession.uploadSampleKey)
        defaults.set(true, forKey: PreviewSession.inspiredSampleKey)
        XCTAssertFalse(PreviewSession.opensUploadSample, "見本の利用者で入っていなければ効かない")
        XCTAssertFalse(PreviewSession.showsInspiredSample)
        defaults.set("me", forKey: PreviewSession.defaultsKey)
        XCTAssertTrue(PreviewSession.opensUploadSample)
        XCTAssertTrue(PreviewSession.showsInspiredSample)
        XCTAssertNotNil(PreviewUploadSample.capture())
        XCTAssertEqual(PreviewSession.uploadSampleKey, "JPPreviewUploadSample")
        XCTAssertEqual(PreviewSession.inspiredSampleKey, "JPPreviewInspired")
    }

    /// 鍵は Debug の中だけで読む（綴りを1か所に持つ）
    func testPreviewKeysAreDebugOnly() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let session = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Core/Auth/PreviewSession.swift"),
                                 encoding: .utf8)
        XCTAssertTrue(session.contains("static var opensUploadSample: Bool {\n        #if DEBUG"))
        XCTAssertTrue(session.contains("static var showsInspiredSample: Bool {\n        #if DEBUG"))
    }

    /// 見本の元の写真は、付けられる写真で、いま開いている写真でない1枚。要約の形にして出す
    func testPreviewSamplePicksAnotherPublicPhoto() async throws {
        let feed = [try photo("open"), try photo("draft", published: false),
                    try photo("other", location: "観音寺市", extra: [#""displayName":"あき""#])]
        XCTAssertEqual(InspiredBy.previewSample(feed: feed, excluding: "open")?.id, "other")
        XCTAssertEqual(InspiredBy.previewSample(feed: feed, excluding: nil)?.id, "open")
        XCTAssertNil(InspiredBy.previewSample(feed: nil, excluding: nil))
        let src = InspiredBy.previewSource(try XCTUnwrap(InspiredBy.previewSample(feed: feed, excluding: "open")))
        XCTAssertEqual(src.id, "other")
        XCTAssertEqual(src.authorName, "あき")
        XCTAssertEqual(src.location, "観音寺市")
        XCTAssertNotNil(InspiredBy.normalizedId(InspiredBy.previewSourceId), "見本の印も本物と同じ段階の道を通る")
    }
}
