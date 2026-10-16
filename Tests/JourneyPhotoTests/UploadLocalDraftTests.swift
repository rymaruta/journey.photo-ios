import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 写真の投稿の端末の下書き（`UploadDraftStore`・`UploadViewModel.saveDraft/restoreDraft`・2026-10-11）。
///
/// 🔴 投稿の画面を閉じると、選んだ写真と書いた題・説明が全部消えていた（「投稿をやめる」「書き続ける」の2択）
@MainActor
final class UploadLocalDraftTests: XCTestCase {

    /// 試験ごとに別の控えと置き場（端末の控えを汚さない・`PushPrimerTests` と同じ形）
    private let defaults = UserDefaults(suiteName: "UploadLocalDraftTests.\(UUID().uuidString)")!
    nonisolated private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("UploadLocalDraftTests-\(UUID().uuidString)")

    override func setUp() {
        super.setUp()
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func store() -> UploadDraftStore { UploadDraftStore(defaults: defaults, directory: directory) }

    private func model(owner: String?, session: URLSession? = nil) -> UploadViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = session ?? URLSession(configuration: config)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.drafts = store()
        model.draftOwner = owner
        // 縮小画像は作らない（Linux の模型では作れない。作り直すことは別の試験で見る）
        model.makeDraftThumbnail = { _ in nil }
        return model
    }

    private func shot(_ byte: UInt8, coords: Photo.Coords? = nil) -> ImagePreparer.Prepared {
        var exif = ExifFields()
        exif.camera = "Apple iPhone 15 Pro"
        return ImagePreparer.Prepared(data: Data(repeating: byte, count: 16), fileName: "photo\(byte).jpg",
                                      contentType: "image/jpeg", exif: exif, coords: coords,
                                      takenOn: "2026-09-12", dominantColor: "#334455")
    }

    private func imageFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix("upload-draft-") }
    }

    // MARK: - 保存して開き直す

    /// 🔴 **閉じる前の写真・題・説明・まとめて付く欄が、開き直すとそのまま戻る**
    func testSavedDraftRestoresPhotosTextAndFields() async {
        let first = model(owner: "a")
        var one = PendingPhoto(prepared: shot(1, coords: Photo.Coords(lat: 34.12, lng: 133.66)))
        one.title = "高屋神社の雲海"
        one.caption = "朝5時"
        one.fillAutomatically("観音寺市")
        var two = PendingPhoto(prepared: shot(2))
        two.location = "どこか"
        two.pickedCoords = Photo.Coords(lat: 35.0, lng: 135.0)
        first.items = [one, two]
        first.tagsText = "雲海, 香川"
        first.category = "風景"
        first.chooseVisibility(published: true, audience: .followers)
        first.groupsAsOnePost = true
        first.selectedAlbumId = "album1"
        XCTAssertTrue(first.saveDraft(), "書けなかった")

        // 次に開いた画面（別のモデル）
        let next = model(owner: "a")
        XCTAssertNotNil(next.storedDraft, "開いたときに下書きが見つからない")
        let restored1 = await next.restoreDraft()
        XCTAssertTrue(restored1)
        XCTAssertEqual(next.items.map(\.prepared.data), [Data(repeating: 1, count: 16), Data(repeating: 2, count: 16)],
                       "写真の並びが変わった・戻らない")
        XCTAssertEqual(next.items.map(\.title), ["高屋神社の雲海", ""])
        XCTAssertEqual(next.items.map(\.caption), ["朝5時", ""])
        XCTAssertEqual(next.items.map(\.location), ["観音寺市", "どこか"])
        XCTAssertEqual(next.items[0].prepared.exif?.camera, "Apple iPhone 15 Pro")
        XCTAssertEqual(next.items[0].prepared.takenOn, "2026-09-12")
        XCTAssertEqual(next.items[1].pickedCoords, Photo.Coords(lat: 35.0, lng: 135.0))
        XCTAssertEqual(next.tagsText, "雲海, 香川")
        XCTAssertEqual(next.category, "風景")
        XCTAssertEqual(next.audience, .followers)
        XCTAssertTrue(next.published)
        XCTAssertTrue(next.groupsAsOnePost)
        XCTAssertEqual(next.selectedAlbumId, "album1")
        XCTAssertTrue(next.canSubmit, "戻した写真で投稿できない")
    }

    /// 🔴 **自動で入れた地名は、戻しても「自動の地名」のまま**（座標を送る）。空にした写真は戻しても送らない
    /// ——欄の文字だけ戻すと、自動の地名が「人が書いた地名」になってピンが消える（`PlaceCoordsRule`）
    func testRestoredPlaceKeepsTheCoordsRule() async {
        let first = model(owner: "a")
        var auto = PendingPhoto(prepared: shot(1, coords: Photo.Coords(lat: 34.12, lng: 133.66)))
        auto.fillAutomatically("観音寺市")
        var cleared = PendingPhoto(prepared: shot(2, coords: Photo.Coords(lat: 34.12, lng: 133.66)))
        cleared.fillAutomatically("観音寺市")
        cleared.location = ""
        first.items = [auto, cleared]
        XCTAssertNotNil(first.items[0].coordsToSend(spots: []), "前提")
        XCTAssertNil(first.items[1].coordsToSend(spots: []), "前提")
        XCTAssertTrue(first.saveDraft())

        let next = model(owner: "a")
        let restored2 = await next.restoreDraft()
        XCTAssertTrue(restored2)
        XCTAssertNotNil(next.items[0].coordsToSend(spots: []), "戻した自動の地名で座標が落ちた")
        XCTAssertNil(next.items[1].coordsToSend(spots: []), "空にした撮影地の座標が、戻したら送られる")
    }

    /// 編集のレシピも戻る（元の写真に掛け直す——編集し直せる）
    func testRestoredDraftKeepsTheEditRecipe() async {
        let first = model(owner: "a")
        first.items = [PendingPhoto(prepared: shot(1))]
        let recipe = PhotoRecipe(exposure: 0.4, contrast: 0.3)
        XCTAssertTrue(first.applyEdit(first.items[0].id, recipe: recipe))
        XCTAssertTrue(first.saveDraft())

        let next = model(owner: "a")
        let restored3 = await next.restoreDraft()
        XCTAssertTrue(restored3)
        XCTAssertEqual(next.items[0].recipe, recipe.sanitized, "編集が消えた")
        XCTAssertEqual(next.items[0].prepared.data, Data(repeating: 1, count: 16), "書き出した絵ではなく元を残す")
    }

    // MARK: - 人ごと

    /// 🔴 **同じ端末で別の人がログインしても、前の人の下書きは見えない・戻らない**
    func testDraftIsPerUser() async {
        let a = model(owner: "a")
        a.items = [PendingPhoto(prepared: shot(1))]
        XCTAssertTrue(a.saveDraft())

        let b = model(owner: "b")
        XCTAssertNil(b.storedDraft, "別の人に前の人の下書きが見えた")
        let restored4 = await b.restoreDraft()
        XCTAssertFalse(restored4)
        XCTAssertTrue(b.items.isEmpty)

        // b が保存しても a の下書きは置き換わらない
        b.items = [PendingPhoto(prepared: shot(9))]
        XCTAssertTrue(b.saveDraft())
        let again = model(owner: "a")
        let restored5 = await again.restoreDraft()
        XCTAssertTrue(restored5)
        XCTAssertEqual(again.items.map(\.prepared.data), [Data(repeating: 1, count: 16)])
    }

    /// ログインしていない（持ち主が決まらない）なら保存しない
    func testNoOwnerSavesNothing() async {
        let model = model(owner: nil)
        model.items = [PendingPhoto(prepared: shot(1))]
        XCTAssertEqual(model.draftSaveBlock, .signedOut)
        XCTAssertFalse(model.saveDraft())
        XCTAssertTrue(imageFiles().isEmpty)
        XCTAssertNil(UploadDraftStore.key(for: ""), "空の userId の鍵を作った（人の区別が無くなる）")
    }

    // MARK: - 消す

    /// 「下書きを削除」で、記録も画像のファイルも消える。保存し直すと前の画像は残らない
    func testDiscardRemovesRecordAndImages() async {
        let first = model(owner: "a")
        first.items = [PendingPhoto(prepared: shot(1)), PendingPhoto(prepared: shot(2))]
        XCTAssertTrue(first.saveDraft())
        XCTAssertEqual(imageFiles().count, 2)
        // 1枚にして保存し直す → 前の2枚は消え、新しい1枚だけ
        first.items = [PendingPhoto(prepared: shot(3))]
        XCTAssertTrue(first.saveDraft())
        XCTAssertEqual(imageFiles().count, 1, "保存し直した前の画像が残っている")

        let next = model(owner: "a")
        next.discardDraft()
        XCTAssertNil(next.storedDraft)
        XCTAssertTrue(imageFiles().isEmpty, "画像のファイルが端末に残った")
    }

    /// 画像が消えていたら（端末の掃除）下書きは無いものとして片づける（欠けたまま戻さない）
    func testMissingImageDropsTheDraft() async throws {
        let first = model(owner: "a")
        first.items = [PendingPhoto(prepared: shot(1)), PendingPhoto(prepared: shot(2))]
        XCTAssertTrue(first.saveDraft())
        let one = try XCTUnwrap(imageFiles().first)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(one))
        XCTAssertNil(store().draft(for: "a"), "欠けた下書きを出した（題が別の写真に付く）")
        XCTAssertTrue(imageFiles().isEmpty, "残りの画像が片づいていない")
    }

    /// 書けなかった（容量不足など）ときは前の下書きに触らない
    func testFailedSaveKeepsThePreviousDraft() async throws {
        let first = model(owner: "a")
        first.items = [PendingPhoto(prepared: shot(1))]
        XCTAssertTrue(first.saveDraft())
        // 置き場をファイルで塞いで、書けない形にする
        let blocked = UploadDraftStore(defaults: defaults, directory: directory.appendingPathComponent("blocked"))
        try Data().write(to: directory.appendingPathComponent("blocked"))
        XCTAssertFalse(blocked.save([.init(imageData: Data([1]), item: store().draft(for: "a")!.items[0])],
                                    fields: store().draft(for: "a")!, for: "a"))
        XCTAssertEqual(store().draft(for: "a")?.items.count, 1, "書けなかったのに前の下書きが消えた")
    }

    /// 🔴 **開き直した下書きは、投稿が上がったら消える**（残すと、開き直して同じ写真を二重に上げる）
    func testRestoredDraftIsClearedAfterASuccessfulPost() async {
        let first = model(owner: "a")
        first.items = [PendingPhoto(prepared: shot(1))]
        XCTAssertTrue(first.saveDraft())

        scriptOneSuccessfulUpload()
        let next = model(owner: "a")
        let restored6 = await next.restoreDraft()
        XCTAssertTrue(restored6)
        await next.submit()
        XCTAssertTrue(next.didPostAll, "前提: 上がった")
        XCTAssertNil(store().draft(for: "a"), "投稿したのに下書きが残った")
        XCTAssertTrue(imageFiles().isEmpty)
    }

    /// 開き直していない下書き（旅の写真から来た回など・尋ねていない）は、別の投稿が上がっても消さない
    func testUnrelatedDraftSurvivesAnotherPost() async {
        let first = model(owner: "a")
        first.items = [PendingPhoto(prepared: shot(1))]
        XCTAssertTrue(first.saveDraft())

        scriptOneSuccessfulUpload()
        let other = model(owner: "a")
        other.items = [PendingPhoto(prepared: shot(5))]
        await other.submit()
        XCTAssertTrue(other.didPostAll, "前提: 上がった")
        XCTAssertNotNil(store().draft(for: "a"), "尋ねてもいない下書きを、別の投稿で消した")
    }

    /// 🔴 **上がった写真は1枚ずつすぐ下書きから外れ、送っている最中の写真には「送り始めた」印が立つ**
    /// ——束の終わりまで待つと、途中でアプリが落ちたときに上がった写真が下書きに残り、開き直して
    /// 二重に投稿した。届いていないと分かった写真は印を下ろして残す（開き直せる）
    func testPostedPhotoLeavesTheDraftRightAwayAndUndeliveredStays() async {
        let first = model(owner: "a")
        var one = PendingPhoto(prepared: shot(1))
        one.title = "上がる"
        var two = PendingPhoto(prepared: shot(2))
        two.title = "届かない"
        first.items = [one, two]
        XCTAssertTrue(first.saveDraft())

        // 1枚目は上がる。2枚目は鍵を取れずに落ちる（本体を置いていない＝届いていないと分かる）
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
            """, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        let next = model(owner: "a")
        let restored7 = await next.restoreDraft()
        XCTAssertTrue(restored7)
        var inFlightWhileSaving: Bool?
        let peek = store()
        next.onSaved = { _ in
            // 保存が通った瞬間（ここで落ちても）、下書きの1枚目には「送り始めた」印が立っている
            inFlightWhileSaving = peek.draft(for: "a")?.items.first?.inFlight
        }
        await next.submit()
        XCTAssertEqual(inFlightWhileSaving, true, "送っている写真に印が無い（落ちたら開き直して二重に上げる）")
        let left = store().draft(for: "a")
        XCTAssertEqual(left?.items.map(\.title), ["届かない"], "上がった写真が下書きに残った・届かない写真まで消えた")
        XCTAssertNil(left?.items.first?.inFlight, "届いていないと分かった写真の印が下りていない")
        XCTAssertEqual(imageFiles().count, 1, "外した写真の画像が残った")

        let again = model(owner: "a")
        let restored8 = await again.restoreDraft()
        XCTAssertTrue(restored8)
        XCTAssertEqual(again.items.map(\.title), ["届かない"])
    }

    /// 🔴 **届いたか分からない写真**（本体は置けたが保存の答えが来ない）は、閉じたあと開き直しても戻さない
    func testUnsurePhotoIsNotRestored() async {
        let first = model(owner: "a")
        var one = PendingPhoto(prepared: shot(1))
        one.title = "上がる"
        var two = PendingPhoto(prepared: shot(2))
        two.title = "分からない"
        first.items = [one, two]
        XCTAssertTrue(first.saveDraft())

        // 1枚目の保存は通る。2枚目は本体を置いたあと保存が 500（届いたか分からない）
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
            """),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#,
                  once: true),
            .init(match: "/upload/save", status: 500, body: #"{"error":"だめでした"}"#),
        ]
        let next = model(owner: "a")
        let restored9 = await next.restoreDraft()
        XCTAssertTrue(restored9)
        await next.submit()
        XCTAssertTrue(next.hasUnsureDraftPhotos, "前提: 2枚目は届いたか分からない")
        XCTAssertTrue(UploadDraftRules.closeDialog(block: next.draftSaveBlock, replacesOther: false, restored: true,
                                                   unsure: next.hasUnsureDraftPhotos)
                        .message.contains(L("二重に投稿しない", "posted twice")), "閉じる確認で言っていない")
        XCTAssertEqual(store().draft(for: "a")?.items.map(\.title), ["分からない"])
        XCTAssertEqual(store().draft(for: "a")?.items.first?.inFlight, true)

        // 「投稿をやめる」で閉じる（閉じた時点で外す・閉じる確認の文言どおり）
        next.dropUnsureDraftPhotos()
        XCTAssertNil(store().draft(for: "a"), "閉じても届いたか分からない写真が下書きに残った")
        XCTAssertTrue(imageFiles().isEmpty)

        let later = model(owner: "a")
        let restored10 = await later.restoreDraft()
        XCTAssertFalse(restored10, "届いたか分からない写真を戻した（二重に投稿される）")
        XCTAssertTrue(later.items.isEmpty)
    }

    /// 🔴 **帯の × で外した下書きの写真は端末からも消える**（残すと次に蘇る）
    func testRemovedRestoredPhotoLeavesTheDraftOnDisk() async {
        let first = model(owner: "a")
        var keep = PendingPhoto(prepared: shot(1))
        keep.title = "残す"
        var drop = PendingPhoto(prepared: shot(2))
        drop.title = "外す"
        first.items = [keep, drop]
        XCTAssertTrue(first.saveDraft())

        let next = model(owner: "a")
        let restoredDrop = await next.restoreDraft()
        XCTAssertTrue(restoredDrop)
        let dropId = next.items.first { $0.title == "外す" }!.id
        next.remove(dropId)
        XCTAssertEqual(next.items.map(\.title), ["残す"])
        XCTAssertEqual(store().draft(for: "a")?.items.map(\.title), ["残す"],
                       "帯で外した写真が端末の下書きに残った")
        XCTAssertEqual(imageFiles().count, 1)

        let again = model(owner: "a")
        let restoredAgain = await again.restoreDraft()
        XCTAssertTrue(restoredAgain)
        XCTAssertEqual(again.items.map(\.title), ["残す"], "外した写真が蘇った")
    }

    /// 復元中は投稿できない（`draftSaveBlock` の loading と同じ門）
    func testCanSubmitBlocksWhileRestoringDraft() async throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Upload/UploadViewModel.swift"),
                                 encoding: .utf8)
        XCTAssertTrue(source.contains("&& !isRestoringDraft"), "canSubmit が復元中を止めていない")
        // 印は縮小画像の await より前に立つ（復元中に「追加」されると下書きが消える）
        let restoreStart = try XCTUnwrap(source.range(of: "func restoreDraft(from slot: UploadDraftStore.Slot = .saved) async -> Bool"), "restoreDraft が無い")
        let restoreEnd = source.range(of: "\n    func discardDraft()")?.lowerBound
            ?? source.index(restoreStart.upperBound, offsetBy: 3500, limitedBy: source.endIndex)
            ?? source.endIndex
        let restoreBody = String(source[restoreStart.upperBound..<restoreEnd])
        let flag = try XCTUnwrap(restoreBody.range(of: "isRestoringDraft = true"), "復元の印が無い")
        let awaitThumb = try XCTUnwrap(restoreBody.range(of: "await Task.detached"), "縮小画像の待ちが無い")
        XCTAssertLessThan(flag.lowerBound, awaitThumb.lowerBound,
                          "縮小画像の待ちよりあとに印を立てている（その間に追加できる）")
    }

    /// 戻した写真には一覧用の縮小画像（512px）を作り直して付ける（無いと一覧がサムネ無しになる）
    func testRestoredPhotosGetThumbnailsAgain() async {
        let first = model(owner: "a")
        first.items = [PendingPhoto(prepared: shot(1)), PendingPhoto(prepared: shot(2))]
        XCTAssertTrue(first.saveDraft())
        let next = model(owner: "a")
        next.makeDraftThumbnail = { data in Data([0x7E]) + data.prefix(1) }
        let restored11 = await next.restoreDraft()
        XCTAssertTrue(restored11)
        XCTAssertEqual(next.items.map(\.prepared.thumbnail), [Data([0x7E, 1]), Data([0x7E, 2])])
    }

    /// スポットの紐付けも戻る
    func testRestoredDraftKeepsTheSpot() async {
        let first = model(owner: "a")
        first.spot = UploadSpotTarget(spotId: "s1", name: "高屋神社", coords: Photo.Coords(lat: 34.1, lng: 133.6))
        first.items = [PendingPhoto(prepared: shot(1))]
        XCTAssertTrue(first.saveDraft())
        let next = model(owner: "a")
        let restored12 = await next.restoreDraft()
        XCTAssertTrue(restored12)
        XCTAssertEqual(next.spot, UploadSpotTarget(spotId: "s1", name: "高屋神社",
                                                   coords: Photo.Coords(lat: 34.1, lng: 133.6)))
    }

    /// 起動のときの掃除: どの下書きからも指されない画像だけ消す（下書きの画像は残す）
    func testSweepRemovesOnlyOrphans() async throws {
        let a = model(owner: "a")
        a.items = [PendingPhoto(prepared: shot(1))]
        XCTAssertTrue(a.saveDraft())
        let orphan = UploadDraftStore.imageFileName(forKey: UploadDraftStore.key(for: "b")!, token: "dead", index: 0)
        try Data([1]).write(to: directory.appendingPathComponent(orphan))
        XCTAssertEqual(imageFiles().count, 2)
        store().sweepOrphans()
        XCTAssertEqual(imageFiles().count, 1, "持ち主のいない画像が残った")
        XCTAssertNotNil(store().draft(for: "a"), "下書きの画像まで消した")
    }

    /// 退会: 記録から外れて残った画像も、その人の前置きで消す（"a" と "ab" を取り違えない）
    func testAccountRemovalSweepsThatPersonsStrayImages() async throws {
        let ab = model(owner: "ab")
        ab.items = [PendingPhoto(prepared: shot(3))]
        XCTAssertTrue(ab.saveDraft())
        let stray = UploadDraftStore.imageFileName(forKey: UploadDraftStore.key(for: "a")!, token: "dead", index: 0)
        try Data([1]).write(to: directory.appendingPathComponent(stray))
        store().removeData(for: "a")
        XCTAssertFalse(imageFiles().contains(stray), "退会した人の取りこぼしの画像が残った")
        XCTAssertNotNil(store().draft(for: "ab"), "前置きが似た別の人の下書きを消した")
    }

    private func scriptOneSuccessfulUpload() {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
            """),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
    }

    /// 退会したら、写真の投稿の下書きも端末から消える（別の人の分は残る）
    func testAccountRemovalDeletesUploadDraft() async {
        let a = model(owner: "a")
        a.items = [PendingPhoto(prepared: shot(1))]
        XCTAssertTrue(a.saveDraft())
        let b = model(owner: "b")
        b.items = [PendingPhoto(prepared: shot(2))]
        XCTAssertTrue(b.saveDraft())

        AccountLocalData.remove(userId: "a", username: nil, defaults: defaults, draftDirectory: directory,
                                offlineTripsRoot: directory.appendingPathComponent("offline"))
        XCTAssertNil(store().draft(for: "a"), "退会した人の下書きが残った")
        XCTAssertNotNil(store().draft(for: "b"), "別の人の下書きまで消した")
        XCTAssertEqual(imageFiles().count, 1)
    }

    // MARK: - 決まり（`UploadDraftRules`）

    /// 閉じる確認: 保存できるときだけ「下書きに保存」を出す。読み込み中・送りかけは理由を言う
    func testCloseDialogOffersSaveOnlyWhenPossible() async {
        XCTAssertTrue(UploadDraftRules.closeDialog(block: nil, replacesOther: false, restored: false).canSave)
        for block: UploadDraftRules.SaveBlock in [.noPhotos, .loading, .sending, .signedOut] {
            XCTAssertFalse(UploadDraftRules.closeDialog(block: block, replacesOther: false, restored: false).canSave,
                           "\(block) なのに保存を出した")
        }
        XCTAssertEqual(UploadDraftRules.saveBlock(hasPhotos: true, loading: false, sending: false, signedIn: true), nil)
        XCTAssertEqual(UploadDraftRules.saveBlock(hasPhotos: false, loading: false, sending: false, signedIn: true), .noPhotos)
        XCTAssertEqual(UploadDraftRules.saveBlock(hasPhotos: true, loading: true, sending: false, signedIn: true), .loading)
        XCTAssertEqual(UploadDraftRules.saveBlock(hasPhotos: true, loading: false, sending: true, signedIn: true), .sending)
        XCTAssertEqual(UploadDraftRules.saveBlock(hasPhotos: true, loading: false, sending: false, signedIn: false), .signedOut)
    }

    /// 写真の無い画面からは保存しない（モデルも止める・ボタンの `.disabled` だけに頼らない）
    func testModelBlocksSavingWithoutPhotos() async {
        let model = model(owner: "a")
        XCTAssertEqual(model.draftSaveBlock, .noPhotos)
        XCTAssertFalse(model.saveDraft())
        XCTAssertTrue(imageFiles().isEmpty)
    }

    /// 開いたときの問い: 写真を持って開いた回・もう尋ねた回は出さない
    func testAsksRestoreOnlyOnPlainOpen() async {
        XCTAssertTrue(UploadDraftRules.asksRestore(hasStoredDraft: true, opensWithContent: false, alreadyAsked: false))
        XCTAssertFalse(UploadDraftRules.asksRestore(hasStoredDraft: false, opensWithContent: false, alreadyAsked: false))
        XCTAssertFalse(UploadDraftRules.asksRestore(hasStoredDraft: true, opensWithContent: true, alreadyAsked: false),
                       "旅の写真・テーマ・スポットから来た人に前の下書きを尋ねた")
        XCTAssertFalse(UploadDraftRules.asksRestore(hasStoredDraft: true, opensWithContent: false, alreadyAsked: true),
                       "選ぶ画面から戻るたびに尋ねる")
    }

    /// 画面の配線: × の確認に「下書きに保存」・開いたときの問い・人が替わったら持ち主を外す
    func testUploadViewIsWired() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Upload/UploadView.swift"),
                              encoding: .utf8)
        XCTAssertTrue(view.contains(#"Button(L("下書きに保存", "Save draft")) { saveDraftAndClose() }"#),
                      "閉じる確認に「下書きに保存」が無い")
        XCTAssertTrue(view.contains(#".alert(L("下書きを続けますか？", "Continue your draft?"), isPresented: $showRestore)"#))
        XCTAssertTrue(view.contains(#"Button(L("続ける", "Continue")) { restoreDraft() }"#))
        XCTAssertTrue(view.contains("model.discardDraft()"))
        XCTAssertTrue(view.contains("if model.draftOwner != id { model.draftOwner = nil }"),
                      "人が替わっても前の人の書きかけを次の人の下書きに保存できる")
        XCTAssertTrue(view.contains("guard !showRestore, !showRestoreAuto, !model.isRestoringDraft else { return }"),
                      "問いの最中に写真を選ぶ画面を重ねて開く")
        XCTAssertTrue(view.contains("|| initialTag != nil || initialSpot != nil"),
                      "テーマ・スポットから開いた回にも下書きを尋ねる（タグ・紐付けを上書きする）")
        XCTAssertTrue(view.contains("model.isWorking || model.isRestoringDraft"),
                      "下書き復元中に「追加」が押せる（下書きが消える）")
        XCTAssertTrue(view.contains("model.dropUnsureDraftPhotos()"),
                      "「投稿をやめる」で届いたか分からない写真を外していない")
    }
}

/// お知らせの一覧の上の「通知をオンにする」（`ActivityPushBanner`・2026-10-11）
final class ActivityPushBannerTests: XCTestCase {

    /// まだ聞いていない → 許可を求める。断られた → 設定アプリ。許可済み・読めていない → 出さない
    func testBannerFollowsSystemPermission() {
        XCTAssertEqual(ActivityPushBanner.state(permission: .notDetermined), .turnOn)
        XCTAssertEqual(ActivityPushBanner.state(permission: .denied), .openSettings)
        XCTAssertNil(ActivityPushBanner.state(permission: .allowed), "許可済みの人に帯を出した")
        XCTAssertNil(ActivityPushBanner.state(permission: .unknown), "読めていないうちに出す（ちらつく）")
        XCTAssertEqual(ActivityPushBanner.openSettings.action, L("設定を開く", "Open Settings"))
        XCTAssertEqual(ActivityPushBanner.turnOn.action, L("オンにする", "Turn on"))
    }

    /// 帯の配線: 設定と同じ道（`push.enable()`）で許可を求め、断られていたら設定アプリの通知を開く
    func testNotificationsViewIsWired() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Notifications/NotificationsView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("if let banner = ActivityPushBanner.state(permission: push.permission)"),
                      "一覧の上に帯が無い")
        XCTAssertTrue(view.contains("await push.enable()"), "「オンにする」が設定と同じ許可の道を通らない")
        XCTAssertTrue(view.contains("UIApplication.openNotificationSettingsURLString"),
                      "断られた人を設定アプリの通知へ案内していない")
        XCTAssertTrue(view.contains(".background(WebTheme.accentFill, in: Capsule())"),
                      "写真の無い画面の主ボタンが真鍮の塗りでない")
        XCTAssertTrue(view.contains(".foregroundStyle(WebTheme.accentText)"), "真鍮の塗りに墨の字でない")
        XCTAssertTrue(view.contains(".accessibilityLabel(banner.action)"), "読み上げが押す所の文字でない")
    }

    /// 初めての投稿のあとの説明: 承認された言い方（「オンにする」「あとで」）
    func testPrimerUsesApprovedCopy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let primer = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Settings/PushPrimerView.swift"), encoding: .utf8)
        XCTAssertTrue(primer.contains("いいね・コメントが届いたらお知らせしますか？"))
        XCTAssertTrue(primer.contains(#"Text(L("オンにする", "Turn on"))"#))
        XCTAssertTrue(primer.contains(#"Text(L("あとで", "Not now"))"#))
    }
}
