import XCTest
@testable import JourneyPhoto
// `PhotosPickerItem` は PhotosUI と SwiftUI の重なりにある。**両方要る**（`Tools/check-cross-imports.py`）
import SwiftUI
import PhotosUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿画面と写真の編集（Phase 2・2026-10-02）: 写真ごとのレシピ・送るときの書き出し・
/// 再試行の鍵（staged）の扱い・編集の元の一時ファイルの片付け。
///
/// 書き出しそのもの（Core Image）は模型では描けないので差し替え口（`exportEdited`）で見る。
/// 本物の書き出しは `PhotoRendererExportTests`（Mac）
final class UploadPhotoEditTests: XCTestCase {

    private var session: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        session = URLSession(configuration: config)
        ScriptedProtocol.reset()
    }

    override func tearDown() async throws {
        ScriptedProtocol.reset()
        try await super.tearDown()
    }

    private func api() -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!,
                  tokenProvider: StubTokenProvider(token: "t"), session: session)
    }

    @MainActor
    private func model() -> UploadViewModel {
        let model = UploadViewModel(uploads: UploadService(api: api(), session: session), albums: AlbumService(api: api()),
                                    photos: PhotoService(api: api()), discovery: DiscoveryService(api: api()))
        model.renderStripPreview = { _, _ in nil }
        return model
    }

    private let presignBody = """
    {"presignedUrl":"https://s3.example.test/put?sig=1",
     "key":"uploads/u1/abc.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg",
     "photoId":"p1","contentType":"image/jpeg"}
    """
    private let thumbPresignBody = """
    {"presignedUrl":"https://s3.example.test/put?sig=2",
     "key":"uploads/u1/thumb.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/thumb.jpg",
     "photoId":"p2","contentType":"image/jpeg"}
    """
    private let saved = #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#

    /// 原本から整えた1枚（撮影情報・座標・撮影日・代表色・サムネを持つ）
    private func original(bytes: Int = 16) -> ImagePreparer.Prepared {
        var exif = ExifFields()
        exif.camera = "Apple iPhone 15 Pro"
        exif.iso = 100
        exif.dateTimeOriginal = "2026-09-13T08:21:05"
        return ImagePreparer.Prepared(data: Data(repeating: 0x11, count: bytes), fileName: "photo.jpg",
                                      contentType: "image/jpeg", exif: exif,
                                      coords: Photo.Coords(lat: 35.68, lng: 139.77), takenOn: "2026-09-13",
                                      dominantColor: "#112233", thumbnail: Data(repeating: 0x22, count: 3))
    }

    private func json(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }

    /// 呼ばれた回数と受け取った値（書き出しの差し替え口から）
    private final class ExportLog: @unchecked Sendable {
        var calls: [(source: Data, recipe: PhotoRecipe, base: ImagePreparer.Prepared)] = []
    }

    /// 書き出しの差し替え: 本体 33 バイト・サムネ 5 バイト・代表色 #abcdef（画素だけ差し替え）
    private func fakeExport(_ log: ExportLog) -> @Sendable (Data, PhotoRecipe, ImagePreparer.Prepared) throws -> ImagePreparer.Prepared {
        { source, recipe, base in
            log.calls.append((source, recipe, base))
            return base.replacingPixels(data: Data(repeating: 0xEE, count: 33),
                                        thumbnail: Data(repeating: 0xDD, count: 5), dominantColor: "#abcdef")
        }
    }

    // MARK: - 写真ごと

    @MainActor
    func testEditStaysWithItsPhoto() async {
        let model = model()
        model.items = [PendingPhoto(prepared: original()), PendingPhoto(prepared: original())]
        let first = model.items[0].id
        XCTAssertTrue(model.applyEdit(first, recipe: PhotoRecipe(preset: .init(id: "dusk", strength: 0.8))))
        XCTAssertEqual(model.items[0].recipe.preset?.id, "dusk")
        XCTAssertEqual(model.items[1].recipe, .identity, "別の写真に反映されない")
        XCTAssertEqual(model.items[0].editBadge, "夕凪")
        XCTAssertNil(model.items[1].editBadge)

        model.applyEdit(model.items[1].id, recipe: PhotoRecipe(exposure: 0.4))
        XCTAssertEqual(model.items[0].recipe.preset?.id, "dusk", "あとの写真の編集で前の写真が変わらない")
        XCTAssertEqual(model.items[1].editBadge, "調整")

        // なしに戻せば札も消える（送るのは元の prepared のまま）
        model.applyEdit(first, recipe: .identity)
        XCTAssertNil(model.items[0].editBadge)
        XCTAssertFalse(UploadEditRules.needsExport(model.items[0].recipe))
    }

    // MARK: - 送るとき

    /// 編集した写真は**元から書き出したもの**を置く。サムネも書き出しのもの、代表色は取り直し、
    /// 撮影情報・座標・撮影日は原本のまま
    @MainActor
    func testEditedPhotoSendsTheExportedPicture() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody, once: true),
            .init(match: "/upload/presigned-url", status: 200, body: thumbPresignBody, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: saved),
        ]
        let log = ExportLog()
        let model = model()
        model.exportEdited = fakeExport(log)
        // 編集の元（原本）の一時ファイル
        let source = Data(repeating: 0x77, count: 9)
        let url = try XCTUnwrap(PhotoEditSources.write(source))
        var photo = PendingPhoto(prepared: original())
        photo.editSource = url
        model.items = [photo]
        let recipe = PhotoRecipe(exposure: 0.4, preset: .init(id: "sumi", strength: 0.8))
        model.applyEdit(model.items[0].id, recipe: recipe)

        await model.submit()

        XCTAssertEqual(log.calls.count, 1)
        XCTAssertEqual(log.calls.first?.source, source, "元は一時ファイルの原本（整えた本体ではない）")
        XCTAssertEqual(log.calls.first?.recipe, recipe)
        let presigns = ScriptedProtocol.calls.filter { $0.path == "/upload/presigned-url" }
        XCTAssertEqual(presigns.count, 2)
        XCTAssertEqual(try json(presigns[0].body)["fileSize"] as? Int, 33, "本体は書き出したもの")
        XCTAssertEqual(try json(presigns[1].body)["fileSize"] as? Int, 5, "一覧用のサムネも書き出しから")
        let save = try json(ScriptedProtocol.calls.last?.body)
        XCTAssertEqual(save["dominantColor"] as? String, "#abcdef", "代表色は書き出した絵から")
        XCTAssertEqual(save["date"] as? String, "2026-09-13", "撮影日は原本から")
        let exif = try XCTUnwrap(save["exif"] as? [String: Any])
        XCTAssertEqual(exif["camera"] as? String, "Apple iPhone 15 Pro", "撮影情報は原本から")
        let coords = try XCTUnwrap(save["coords"] as? [String: Any])
        XCTAssertEqual(coords["lat"] as? Double, 35.68)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "投稿したら編集の元を片付ける")
    }

    /// 無編集なら書き出さない（整えた `prepared` をそのまま）
    @MainActor
    func testUneditedPhotoIsSentAsPrepared() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody, once: true),
            .init(match: "/upload/presigned-url", status: 200, body: thumbPresignBody, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: saved),
        ]
        let log = ExportLog()
        let model = model()
        model.exportEdited = fakeExport(log)
        model.items = [PendingPhoto(prepared: original(bytes: 16))]
        await model.submit()
        XCTAssertTrue(log.calls.isEmpty, "無編集で書き出した")
        let presigns = ScriptedProtocol.calls.filter { $0.path == "/upload/presigned-url" }
        XCTAssertEqual(try json(presigns[0].body)["fileSize"] as? Int, 16)
        XCTAssertEqual(try json(ScriptedProtocol.calls.last?.body)["dominantColor"] as? String, "#112233")
    }

    /// 書き出せなかったら、その写真は送らずに残す（元の絵で黙って送らない）
    @MainActor
    func testExportFailureKeepsThePhoto() async throws {
        ScriptedProtocol.script = []
        let model = model()
        model.exportEdited = { _, _, _ in throw ImagePreparer.PrepareError.encodeFailed }
        model.items = [PendingPhoto(prepared: original())]
        model.applyEdit(model.items[0].id, recipe: PhotoRecipe(contrast: 0.3))
        await model.submit()
        XCTAssertEqual(model.items.count, 1)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(ScriptedProtocol.calls.isEmpty, "書き出せないまま何かを送った")
    }

    // MARK: - 再試行の鍵（#136 の二重投稿の守り）

    /// 保存が落ちて鍵を控えている写真は**編集させない**。やり直しは同じ鍵・書き出し直さない
    @MainActor
    func testStagedPhotoCannotBeEditedAndRetryReusesTheKey() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody, once: true),
            .init(match: "/upload/presigned-url", status: 200, body: thumbPresignBody, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"x"}"#),
        ]
        let log = ExportLog()
        let model = model()
        model.exportEdited = fakeExport(log)
        // 共有に載せる設定だと、共有の絵を作るために書き出す（ここは置く絵の書き出しだけを数える）
        if model.shareToThreads { model.shareToThreads = false }
        model.items = [PendingPhoto(prepared: original())]
        let id = model.items[0].id
        XCTAssertNil(model.editLockReason(for: id))
        model.applyEdit(id, recipe: PhotoRecipe(exposure: 0.4))
        await model.submit()
        XCTAssertEqual(model.items.count, 1, "保存が落ちた写真は残る")

        XCTAssertNotNil(model.editLockReason(for: id), "鍵を控えている間は編集を開かせない")
        XCTAssertFalse(model.applyEdit(id, recipe: PhotoRecipe(exposure: -1)), "画面をすり抜けても入れない")
        XCTAssertEqual(model.items[0].recipe, PhotoRecipe(exposure: 0.4))

        ScriptedProtocol.script = [.init(match: "/upload/save", status: 200, body: saved)]
        await model.submit()
        let paths = ScriptedProtocol.calls.map(\.path)
        XCTAssertEqual(paths.filter { $0 == "/upload/presigned-url" }.count, 2, "やり直しは前の鍵で（置き直さない）")
        XCTAssertEqual(log.calls.count, 1, "やり直しで書き出し直さない")
        XCTAssertEqual(try json(ScriptedProtocol.calls.last?.body)["dominantColor"] as? String, "#abcdef",
                       "やり直しの代表色も置いた絵のもの")
        XCTAssertTrue(model.items.isEmpty)
    }

    // MARK: - 編集の元の一時ファイル

    @MainActor
    func testEditSourcesAreRemovedWithTheirPhotos() async throws {
        let a = try XCTUnwrap(PhotoEditSources.write(Data([1])))
        let b = try XCTUnwrap(PhotoEditSources.write(Data([2])))
        var model: UploadViewModel? = model()
        var first = PendingPhoto(prepared: original())
        first.editSource = a
        var second = PendingPhoto(prepared: original())
        second.editSource = b
        model?.items = [first, second]
        model?.remove(first.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path), "外した写真の元を消す")
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        XCTAssertEqual(model?.items.first?.editSourceReader(), Data([2]), "編集の元は一時ファイルから読む")
        weak var gone = model
        model = nil
        XCTAssertNil(gone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path), "画面を閉じたら全部消す")
    }

    /// 一時ファイルが無い（旅の写真から来た・書けなかった）写真は、整えた本体を元にする
    @MainActor
    func testEditSourceFallsBackToPrepared() async {
        let photo = PendingPhoto(prepared: original(bytes: 4))
        XCTAssertEqual(photo.editSourceReader(), Data(repeating: 0x11, count: 4))
        var missing = PendingPhoto(prepared: original(bytes: 4))
        missing.editSource = URL(fileURLWithPath: "/nonexistent/photo-edit-source")
        XCTAssertEqual(missing.editSourceReader(), Data(repeating: 0x11, count: 4))
    }

    /// 選んだ写真を読むとき、**原本**を編集の元として残す（`keepEditSource`。整えた本体ではない）
    @MainActor
    func testLibraryPickKeepsTheOriginalAsEditSource() async throws {
        let model = model()
        let kept = URL(fileURLWithPath: "/tmp/kept-source")
        let received = ExportLog()
        model.loadPickedData = { _ in Data([9, 9, 9]) }
        model.prepareData = { _ in
            ImagePreparer.Prepared(data: Data([1]), fileName: "photo.jpg", contentType: "image/jpeg",
                                   exif: nil, coords: nil, takenOn: nil)
        }
        model.keepEditSource = { data in
            received.calls.append((data, .identity, ImagePreparer.Prepared(data: data, fileName: "", contentType: "",
                                                                           exif: nil, coords: nil, takenOn: nil)))
            return kept
        }
        model.pickerItems = [PhotosPickerItem(itemIdentifier: "a")]
        for _ in 0..<500 where model.items.isEmpty || model.isLoadingPicked {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.items.first?.editSource, kept)
        XCTAssertEqual(received.calls.map(\.source), [Data([9, 9, 9])], "残すのは原本")
    }

    // MARK: - レビューの穴（2026-10-02）

    private var twoPresigns: [ScriptedProtocol.Step] {
        [.init(match: "/upload/presigned-url", status: 200, body: presignBody, once: true),
         .init(match: "/upload/presigned-url", status: 200, body: thumbPresignBody, once: true)]
    }

    private var discardedKeys: [String] {
        ScriptedProtocol.calls.filter { $0.path == "/upload/discard" }.compactMap {
            (try? JSONSerialization.jsonObject(with: $0.body ?? Data())) as? [String: Any]
        }.compactMap { $0["key"] as? String }
    }

    /// 錠をすり抜けて（画面を通らずに）レシピが変わったら、控えた鍵は**使わない**:
    /// 書き出し直して置き直し、前の鍵は片付けに回す（`reusesStaged`）
    @MainActor
    func testStagedKeyIsNotReusedForADifferentEdit() async throws {
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"x"}"#),
        ]
        let log = ExportLog()
        let model = model()
        model.exportEdited = fakeExport(log)
        if model.shareToThreads { model.shareToThreads = false }
        model.items = [PendingPhoto(prepared: original())]
        model.applyEdit(model.items[0].id, recipe: PhotoRecipe(exposure: 0.4))
        await model.submit()

        model.items[0].recipe = PhotoRecipe(exposure: -0.4)
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
            .init(match: "/upload/save", status: 200, body: saved),
        ]
        await model.submit()
        for _ in 0..<500 where discardedKeys.count < 2 { try await Task.sleep(nanoseconds: 10_000_000) }

        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/upload/presigned-url" }.count, 4, "置き直した")
        XCTAssertEqual(log.calls.map(\.recipe), [PhotoRecipe(exposure: 0.4), PhotoRecipe(exposure: -0.4)])
        XCTAssertEqual(Set(discardedKeys), ["uploads/u1/abc.jpg", "uploads/u1/thumb.jpg"], "前の鍵を片付ける")
        XCTAssertTrue(model.items.isEmpty)
    }

    /// カメラで撮った1枚も、撮った JPEG を編集の元に残す
    @MainActor
    func testCameraCaptureKeepsItsJPEGAsEditSource() async throws {
        let model = model()
        let kept = URL(fileURLWithPath: "/tmp/kept-camera-source")
        let received = ExportLog()
        model.prepareData = { _ in
            ImagePreparer.Prepared(data: Data([1]), fileName: "photo.jpg", contentType: "image/jpeg",
                                   exif: nil, coords: nil, takenOn: nil)
        }
        model.keepEditSource = { data in
            received.calls.append((data, .identity, ImagePreparer.Prepared(data: data, fileName: "", contentType: "",
                                                                           exif: nil, coords: nil, takenOn: nil)))
            return kept
        }
        model.accept(capture: CameraCapture(metadata: [:], capturedAt: Date(), encode: { Data([5, 5]) }))
        for _ in 0..<500 where model.items.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.items.first?.editSource, kept)
        XCTAssertEqual(received.calls.map(\.source), [Data([5, 5])])
    }

    /// 選び直しで捨てた回（整えている間に選択が変わった）の一時ファイルは消す
    @MainActor
    func testDiscardedPickRemovesItsEditSource() async throws {
        let model = model()
        let written = ExportLog()
        model.loadPickedData = { _ in Data([3, 3]) }
        model.prepareData = { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return ImagePreparer.Prepared(data: Data([1]), fileName: "photo.jpg", contentType: "image/jpeg",
                                          exif: nil, coords: nil, takenOn: nil)
        }
        let urls = URLBox()
        model.keepEditSource = { data in
            let url = PhotoEditSources.write(data)
            urls.value = url
            written.calls.append((data, .identity, ImagePreparer.Prepared(data: data, fileName: "", contentType: "",
                                                                          exif: nil, coords: nil, takenOn: nil)))
            return url
        }
        model.pickerItems = [PhotosPickerItem(itemIdentifier: "a")]
        try await Task.sleep(nanoseconds: 100_000_000)
        model.pickerItems = []
        for _ in 0..<500 where urls.value == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let url = try XCTUnwrap(urls.value, "整え終わる前に止まった（試験の前提が崩れている）")
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "捨てた回の元が残っている")
    }

    private final class URLBox: @unchecked Sendable { var value: URL? }

    /// 編集しない写真のサムネは元のまま（描き直さない・編集後の絵を出さない）
    @MainActor
    func testUneditedPhotoKeepsItsOriginalThumbnail() async throws {
        let model = model()
        let rendered = ExportLog()
        model.renderStripPreview = { data, recipe in
            rendered.calls.append((data, recipe, ImagePreparer.Prepared(data: data, fileName: "", contentType: "",
                                                                        exif: nil, coords: nil, takenOn: nil)))
            return nil
        }
        model.items = [PendingPhoto(prepared: original()), PendingPhoto(prepared: original())]
        model.applyEdit(model.items[0].id, recipe: PhotoRecipe(exposure: 0.4))
        model.applyEdit(model.items[1].id, recipe: .identity)
        for _ in 0..<200 where rendered.calls.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(rendered.calls.map(\.recipe), [PhotoRecipe(exposure: 0.4)], "編集した1枚だけ描く")

        // 無編集の写真は、編集後の絵が残っていても元の絵を出す
        var photo = PendingPhoto(prepared: original())
        photo.editedPreview = Image(systemName: "photo")
        XCTAssertNil(photo.stripPreview, "元の preview（ここでは無し）を出す")
        photo.recipe = PhotoRecipe(contrast: 0.2)
        XCTAssertNotNil(photo.stripPreview)
    }

    /// SNS（Threads）に渡すのも**編集後**。作れなければ共有に回さず知らせる（編集前を黙って渡さない）
    @MainActor
    func testThreadsGetsTheEditedPictureOrNothing() async throws {
        let log = ExportLog()
        let savedOverrides = AppConfig.testOverrides
        defer { AppConfig.testOverrides = savedOverrides }
        AppConfig.testOverrides = (savedOverrides ?? [:]).merging(["JPSiteBaseURL": "https://site.example.test"]) { $1 }
        let model = model()
        defer { model.shareToThreads = false }
        model.shareToThreads = true
        model.watermark = { $0 }
        model.exportEdited = fakeExport(log)
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: saved),
        ]
        model.items = [PendingPhoto(prepared: original())]
        model.applyEdit(model.items[0].id, recipe: PhotoRecipe(exposure: 0.4))
        await model.submit()
        XCTAssertEqual(model.threadsBundle?.images, [Data(repeating: 0xEE, count: 33)], "共有は編集後の絵")
    }

    @MainActor
    func testThreadsSkipsAnEditedPictureThatCannotBeRebuilt() async throws {
        let log = ExportLog()
        let savedOverrides = AppConfig.testOverrides
        defer { AppConfig.testOverrides = savedOverrides }
        AppConfig.testOverrides = (savedOverrides ?? [:]).merging(["JPSiteBaseURL": "https://site.example.test"]) { $1 }
        let model = model()
        defer { model.shareToThreads = false }
        model.shareToThreads = true
        model.watermark = { $0 }
        model.exportEdited = fakeExport(log)
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"x"}"#),
        ]
        model.items = [PendingPhoto(prepared: original())]
        model.applyEdit(model.items[0].id, recipe: PhotoRecipe(exposure: 0.4))
        await model.submit()
        // やり直しは書き出し直さない。共有の絵を作り直そうとして落ちる
        model.exportEdited = { _, _, _ in throw ImagePreparer.PrepareError.encodeFailed }
        ScriptedProtocol.script = [.init(match: "/upload/save", status: 200, body: saved)]
        await model.submit()
        XCTAssertTrue(model.items.isEmpty, "投稿自体は済んでいる")
        XCTAssertNil(model.threadsBundle, "編集前の絵を渡さない")
        XCTAssertFalse(model.didPostAll, "知らせを見せるため閉じない")
        XCTAssertTrue(model.errorMessage?.contains("SNS への共有は開いていません") ?? false, model.errorMessage ?? "nil")
    }

    /// 書き出しが落ちたときの知らせに、編集を「なし」に戻せば送れることを添える
    @MainActor
    func testExportFailureTellsHowToSendTheOriginal() async throws {
        ScriptedProtocol.script = []
        let model = model()
        model.exportEdited = { _, _, _ in throw ImagePreparer.PrepareError.encodeFailed }
        model.items = [PendingPhoto(prepared: original())]
        model.applyEdit(model.items[0].id, recipe: PhotoRecipe(contrast: 0.3))
        await model.submit()
        XCTAssertTrue(model.errorMessage?.contains("編集を「なし」に戻すと元の写真で送れます") ?? false,
                      model.errorMessage ?? "nil")
    }

    // MARK: - 端末での直し（2026-10-03）

    /// 🔴 **編集した写真の書き出しは、最初の1枚を置く前に全部済ませる**（裏に回ってから
    /// Core Image で書き出して落ちていた）。書き出しは1枚ずつ順に・無編集は書き出さない
    @MainActor
    func testAllEditsAreExportedBeforeTheFirstStage() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: saved),
        ]
        /// 書き出したときに、もう何本の通信が出ていたか
        final class Seen: @unchecked Sendable { var requestsAtExport: [Int] = [] }
        let seen = Seen()
        let log = ExportLog()
        let model = model()
        if model.shareToThreads { model.shareToThreads = false }
        let export = fakeExport(log)
        model.exportEdited = { source, recipe, base in
            seen.requestsAtExport.append(ScriptedProtocol.calls.count)
            return try export(source, recipe, base)
        }
        model.items = [PendingPhoto(prepared: original()), PendingPhoto(prepared: original()),
                       PendingPhoto(prepared: original())]
        model.applyEdit(model.items[0].id, recipe: PhotoRecipe(exposure: 0.4))
        model.applyEdit(model.items[2].id, recipe: PhotoRecipe(contrast: 0.2))

        await model.submit()

        XCTAssertEqual(log.calls.map(\.recipe), [PhotoRecipe(exposure: 0.4), PhotoRecipe(contrast: 0.2)],
                       "編集した2枚だけ、並びの順に書き出す")
        XCTAssertEqual(seen.requestsAtExport, [0, 0], "最初の stage（presign）より前に全部書き出していない")
        XCTAssertFalse(ScriptedProtocol.calls.isEmpty)
        XCTAssertTrue(model.items.isEmpty, model.errorMessage ?? "")
    }

    /// 書き出せなかった写真だけ残し、ほかは送る（先に書き出しても今までと同じ結末）
    @MainActor
    func testExportFailureBeforeStagingKeepsOnlyThatPhoto() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: saved),
        ]
        let model = model()
        model.exportEdited = { _, recipe, base in
            if recipe.exposure != 0 { throw ImagePreparer.PrepareError.encodeFailed }
            return base
        }
        model.items = [PendingPhoto(prepared: original()), PendingPhoto(prepared: original())]
        let failing = model.items[0].id
        model.applyEdit(failing, recipe: PhotoRecipe(exposure: 0.4))
        await model.submit()
        XCTAssertEqual(model.items.map(\.id), [failing])
        XCTAssertTrue(model.errorMessage?.contains("編集を「なし」に戻すと元の写真で送れます") ?? false,
                      model.errorMessage ?? "nil")
    }

    /// 保存が通った行を外へ渡す（マイページ・ホームが先に並べる・`PostedPhotos`）
    @MainActor
    func testSavedPhotoIsHandedOut() async throws {
        ScriptedProtocol.script = twoPresigns + [
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: saved),
        ]
        let model = model()
        if model.shareToThreads { model.shareToThreads = false }
        var handed: [String] = []
        model.onSaved = { handed.append($0.id) }
        model.items = [PendingPhoto(prepared: original())]
        await model.submit()
        XCTAssertEqual(handed, ["p1"])
    }

    /// 帯のサムネは**一覧用のサムネ（512px）から**、画面の処理の外で作る（1920px の本体を UIImage にしない）
    @MainActor
    func testStripThumbIsMadeFromTheSmallThumbnail() async throws {
        let model = model()
        final class Received: @unchecked Sendable { var data: [Data] = [] }
        let received = Received()
        model.makeStripThumb = { data in
            received.data.append(data)
            return UIImage()
        }
        model.append(original())
        for _ in 0..<500 where model.items.first?.preview == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(received.data, [Data(repeating: 0x22, count: 3)], "本体ではなく一覧用のサムネから作る")
        XCTAssertNotNil(model.items.first?.preview)
    }

    /// 🔴 **iCloud の写真が返らなくても、上限時間で「読めなかった」に回し、読めた分だけで投稿できる。**
    /// 「もう一度読み込む」で読み直せる
    @MainActor
    func testPickedPhotoThatNeverLoadsTimesOut() async throws {
        let model = model()
        final class Gate: @unchecked Sendable { var slowLoads = true }
        let gate = Gate()
        model.pickedLoadTimeout = 0.3
        model.loadPickedData = { item in
            if item.itemIdentifier == "slow", gate.slowLoads {
                // 試験が門を開けるまで返らない（取り消しにも応えない）
                while gate.slowLoads { try? await Task.sleep(nanoseconds: 50_000_000) }
            }
            return Data([1])
        }
        model.prepareData = { _ in
            ImagePreparer.Prepared(data: Data([1]), fileName: "photo.jpg", contentType: "image/jpeg",
                                   exif: nil, coords: nil, takenOn: nil)
        }
        model.keepEditSource = { _ in nil }
        model.pickerItems = [PhotosPickerItem(itemIdentifier: "fast"), PhotosPickerItem(itemIdentifier: "slow")]
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<300 where model.isLoadingPicked { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.isLoadingPicked, "返らない1枚のために読み込み中が解けない")
        XCTAssertEqual(model.items.map(\.pickerItem?.itemIdentifier), ["fast"])
        XCTAssertTrue(model.canSubmit, "読めた分だけで投稿できる")
        XCTAssertEqual(model.errorMessage, "1 枚は読み込めませんでした")
        XCTAssertTrue(model.canRetryUnreadable)

        // 「もう一度読み込む」
        gate.slowLoads = false
        model.retryUnreadable()
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<300 where model.isLoadingPicked || model.items.count < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.items.map(\.pickerItem?.itemIdentifier), ["fast", "slow"], "読めた写真は残し、読み直した分を足す")
        XCTAssertFalse(model.canRetryUnreadable)
        XCTAssertNil(model.errorMessage)
    }

    /// 書き出しの間は「書き出し中 n/N」を出す（「0/N」のまま止まって見えない）。終わったら消す
    @MainActor
    func testExportShowsProgress() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: saved),
        ]
        final class Seen: @unchecked Sendable { var progress: [UploadEditRules.ExportProgress?] = [] }
        let seen = Seen()
        let model = model()
        if model.shareToThreads { model.shareToThreads = false }
        let log = ExportLog()
        let export = fakeExport(log)
        model.exportEdited = { source, recipe, base in
            // 書き出しは画面の処理の外。画面の処理の上で今の進みを読む
            seen.progress.append(DispatchQueue.main.sync { MainActor.assumeIsolated { model.exportProgress } })
            return try export(source, recipe, base)
        }
        model.items = [PendingPhoto(prepared: original()), PendingPhoto(prepared: original()),
                       PendingPhoto(prepared: original())]
        model.applyEdit(model.items[0].id, recipe: PhotoRecipe(exposure: 0.4))
        model.applyEdit(model.items[2].id, recipe: PhotoRecipe(contrast: 0.2))
        await model.submit()
        XCTAssertEqual(seen.progress, [.init(index: 1, total: 2), .init(index: 2, total: 2)])
        XCTAssertNil(model.exportProgress)
    }
}
