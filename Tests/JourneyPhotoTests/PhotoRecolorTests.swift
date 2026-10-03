import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿済みの写真の色を編集し直す（段階1・`PhotoRecolor`・`PhotoService.replace(keepCurrentMetadata:)`）。
///
/// - 本文に**撮影情報（EXIF・撮影日・座標）を載せない**——公開中の画像には無いので、載せると空で上書きする
/// - 代表色は載せる（書き出した画像から取ったもの）
/// - 無編集で「完了」なら何も送らない／差し替えの最中は二重に送らない（一言出し、調整内容を残す）
/// - 409（ストーリーから残した写真）はサーバーの文言をそのまま出す。失敗しても調整内容を残す
/// - 読み込み: 画像でない応答・上限超えは断る。403 は写真を取り直して1回だけ読み直す。読み込み中も閉じられる
final class PhotoRecolorTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        session = URLSession(configuration: config)
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func api() -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!,
                  tokenProvider: StubTokenProvider(token: "t"), session: session)
    }

    private func uploads() -> UploadService {
        UploadService(api: api(), session: session)
    }

    private let presignBody = """
    {"presignedUrl":"https://s3.example.test/put?sig=1",
     "key":"uploads/u1/abc.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg",
     "photoId":"p1","contentType":"image/jpeg"}
    """

    /// 撮影情報も代表色も持つ1枚（どれが本文に載るかを見分けるため、全部入れる）
    private func preparedWithEverything() -> ImagePreparer.Prepared {
        var exif = ExifFields()
        exif.camera = "Canon EOS R6"
        exif.dateTimeOriginal = "2024-05-12T18:24:00"
        return ImagePreparer.Prepared(data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg",
                                      contentType: "image/jpeg", exif: exif,
                                      coords: Photo.Coords(lat: 35.6812, lng: 139.7671),
                                      takenOn: "2024-05-12", dominantColor: "#aabbcc")
    }

    private func replaceBody() throws -> [String: Any] {
        let put = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path == "/photos/p1" })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(put.body)) as? [String: Any])
        return try XCTUnwrap(json["replace"] as? [String: Any])
    }

    // MARK: - 本文

    /// 🔴 **色の編集し直しは撮影情報を載せない。** サーバーは送られなかった項目を今の値のまま残す
    /// （`photoReplace.ts` の `buildReplace`）。載せると、公開中の画像から読んだ空の値・別の値で上書きする。
    /// 代表色は載せる（送らないとサーバーが消して、建て直しまで地の色が無くなる）
    func testRecolorReplaceLeavesMetadataOutAndSendsDominantColor() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/photos/p1", status: 200, body: "{}"),
        ]
        let keptOldDate = try await PhotoService(api: api())
            .replace(photoId: "p1", prepared: preparedWithEverything(), uploads: uploads(),
                     keepCurrentMetadata: true)
        let replace = try replaceBody()
        XCTAssertNil(replace["exif"], "EXIF を載せている（今の撮影情報を上書きする）")
        XCTAssertNil(replace["date"], "撮影日を載せている")
        XCTAssertNil(replace["coords"], "座標を載せている（外したピンが戻る・別の位置になる）")
        XCTAssertEqual(replace["dominantColor"] as? String, "#aabbcc", "代表色を載せていない")
        XCTAssertEqual(replace["key"] as? String, "uploads/u1/abc.jpg")
        XCTAssertFalse(keptOldDate, "撮影日を触らない回に「前のまま」と知らせる")
    }

    /// 写真そのものの差し替え（既定）は今までどおり、新しい写真の撮影情報を載せる（代表色は載せない）
    func testPlainReplaceStillSendsMetadata() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/photos/p1", status: 200, body: "{}"),
        ]
        _ = try await PhotoService(api: api())
            .replace(photoId: "p1", prepared: preparedWithEverything(), uploads: uploads())
        let replace = try replaceBody()
        XCTAssertNotNil(replace["exif"])
        XCTAssertEqual(replace["date"] as? String, "2024-05-12")
        XCTAssertNotNil(replace["coords"])
        XCTAssertNil(replace["dominantColor"])
    }

    // MARK: - 「完了」

    private let source = Data([9, 9, 9])

    /// 🔴 **無編集で「完了」なら何も送らない**（書き出しも送信もしない・差し替えの印も立てない）
    @MainActor
    func testUnchangedRecipeSendsNothing() async {
        var exported = 0
        var sent = 0
        var flips: [Bool] = []
        // 強さ 0 のプリセットも無編集（`PhotoRecipe.isIdentity`）
        for recipe in [PhotoRecipe.identity, PhotoRecipe(preset: .init(id: "haze", strength: 0))] {
            let result = await PhotoRecolor.finish(
                recipe: recipe, source: source, isBusy: { false }, setReplacing: { flips.append($0) },
                export: { _ in exported += 1; return PhotoRecolor.base(source: Data([1])) },
                send: { _ in sent += 1 })
            guard case .unchanged = result else { return XCTFail("無編集なのに \(result)") }
            XCTAssertNil(PhotoRecolor.notice(for: result), "無編集なのに知らせを出す")
        }
        XCTAssertEqual(exported, 0, "無編集なのに書き出した")
        XCTAssertEqual(sent, 0, "無編集なのに送った")
        XCTAssertEqual(flips, [], "無編集なのに差し替えの印を立てた")
    }

    /// 変えていれば書き出して送り、印は送り終わったら下ろす
    @MainActor
    func testChangedRecipeExportsAndSends() async {
        var sentColor: String?
        var flips: [Bool] = []
        let recipe = PhotoRecipe(exposure: 0.5)
        let result = await PhotoRecolor.finish(
            recipe: recipe, source: source, isBusy: { false }, setReplacing: { flips.append($0) },
            export: { got in
                XCTAssertEqual(got, recipe)
                return PhotoRecolor.base(source: Data([1])).replacingPixels(data: Data([2]), thumbnail: nil,
                                                                            dominantColor: "#102030")
            },
            send: { prepared in sentColor = prepared.dominantColor })
        guard case .replaced(let prepared) = result else { return XCTFail("差し替えていない: \(result)") }
        XCTAssertEqual(prepared.data, Data([2]))
        XCTAssertEqual(sentColor, "#102030")
        XCTAssertEqual(flips, [true, false])
        XCTAssertEqual(PhotoRecolor.notice(for: result)?.isError, false, "成功を赤で出す")
    }

    /// 🔴 **差し替えの最中は二重に送らない。** 1回目の書き出しを待たせている間に2回目の「完了」が来ても通さない
    /// （印は書き出しの**前**に立てる）。止まった回は**一言出し、調整内容を残す**（「もう一度」）
    @MainActor
    func testSecondFinishWhileReplacingSendsNothing() async {
        var isReplacing = false
        var sent = 0
        var release: CheckedContinuation<Void, Never>?
        let recipe = PhotoRecipe(contrast: 0.3)
        let source = self.source

        let first = Task { @MainActor in
            await PhotoRecolor.finish(
                recipe: recipe, source: source, isBusy: { isReplacing }, setReplacing: { isReplacing = $0 },
                export: { _ in
                    await withCheckedContinuation { release = $0 }
                    return PhotoRecolor.base(source: Data([1]))
                },
                send: { _ in sent += 1 })
        }
        // 1回目が書き出しで止まるまで待つ（時間で待たない）
        while release == nil { await Task.yield() }
        XCTAssertTrue(isReplacing)

        let second = await PhotoRecolor.finish(
            recipe: recipe, source: source, isBusy: { isReplacing }, setReplacing: { isReplacing = $0 },
            export: { _ in XCTFail("2回目が書き出した"); return PhotoRecolor.base(source: Data([1])) },
            send: { _ in sent += 1 })
        guard case .busy(let retry) = second else { return XCTFail("2回目が通った: \(second)") }
        XCTAssertEqual(retry, PhotoRecolor.Retry(source: source, recipe: recipe), "止まった回に調整内容を残していない")
        let notice = PhotoRecolor.notice(for: second)
        XCTAssertNotNil(notice, "止まった回に何も言わない")
        XCTAssertEqual(notice?.isError, true)

        release?.resume()
        guard case .replaced = await first.value else { return XCTFail("1回目が差し替えていない") }
        XCTAssertEqual(sent, 1, "二重に送った")
        XCTAssertFalse(isReplacing, "印が下りていない")

        // 保存の最中も通さない
        let whileSaving = await PhotoRecolor.finish(
            recipe: recipe, source: source, isBusy: { true }, setReplacing: { _ in XCTFail("保存中に印を立てた") },
            export: { _ in XCTFail("保存中に書き出した"); return PhotoRecolor.base(source: Data([1])) },
            send: { _ in sent += 1 })
        guard case .busy = whileSaving else { return XCTFail("保存中に通った") }
        XCTAssertEqual(sent, 1)
    }

    // MARK: - 失敗（409・書き出し）

    /// 🔴 **409（ストーリーから残した写真）はサーバーの文言をそのまま出す。** 失敗でも印は下ろし、
    /// **最後の調整内容を残す**（「もう一度」でその内容から開き直す）
    @MainActor
    func testConflictShowsServerMessageAndKeepsRecipe() async {
        let message = "元のストーリーが出ている間（最大25時間）は、公開範囲の変更と写真の差し替えはできません。ストーリーを削除すれば、すぐに変えられます"
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/photos/p1", status: 409, body: #"{"error":"\#(message)"}"#),
        ]
        let photos = PhotoService(api: api())
        let uploads = uploads()
        var isReplacing = false
        let recipe = PhotoRecipe(saturation: -0.4, preset: .init(id: "dusk", strength: 0.6))
        let result = await PhotoRecolor.finish(
            recipe: recipe, source: source, isBusy: { isReplacing },
            setReplacing: { isReplacing = $0 },
            export: { _ in self.preparedWithEverything() },
            send: { prepared in
                _ = try await photos.replace(photoId: "p1", prepared: prepared, uploads: uploads,
                                             keepCurrentMetadata: true)
            })
        guard case .failed(let shown, let retry) = result else { return XCTFail("409 なのに通った: \(result)") }
        XCTAssertEqual(shown, message)
        XCTAssertEqual(PhotoRecolor.notice(for: result)?.text, message)
        XCTAssertEqual(retry.recipe, recipe, "失敗のあと調整内容を捨てた")
        XCTAssertEqual(retry.source, source)
        XCTAssertFalse(isReplacing, "失敗のあと印が下りていない（保存も閉じるも押せなくなる）")
    }

    /// 書き出しの失敗も調整内容を残す（送信はしない）
    @MainActor
    func testExportFailureKeepsRecipe() async {
        var sent = 0
        let recipe = PhotoRecipe(temperature: 0.2)
        let result = await PhotoRecolor.finish(
            recipe: recipe, source: source, isBusy: { false }, setReplacing: { _ in },
            export: { _ in throw ImagePreparer.PrepareError.unreadable },
            send: { _ in sent += 1 })
        guard case .failed(_, let retry) = result else { return XCTFail("失敗にならない: \(result)") }
        XCTAssertEqual(retry.recipe, recipe)
        XCTAssertEqual(sent, 0)
    }

    // MARK: - 閉じる

    /// 🔴 **色の編集の元を読んでいる間も「閉じる」で抜けられる**（止めるのは保存・差し替えの最中だけ）
    func testLoadingDoesNotBlockClosing() {
        XCTAssertFalse(PhotoRecolor.blocksClosing(isSaving: false, isReplacing: false, isLoadingRecolor: true),
                       "読み込み中に閉じられない（遅い回線で画面に閉じ込める）")
        XCTAssertFalse(PhotoRecolor.blocksClosing(isSaving: false, isReplacing: false, isLoadingRecolor: false))
        XCTAssertTrue(PhotoRecolor.blocksClosing(isSaving: true, isReplacing: false, isLoadingRecolor: false))
        XCTAssertTrue(PhotoRecolor.blocksClosing(isSaving: false, isReplacing: true, isLoadingRecolor: false))
    }

    // MARK: - 読み込み（fetchSource・loadSource）

    private func fetch(_ path: String, maxBytes: Int = PhotoRecolor.maxSourceBytes) async throws -> Data {
        try await PhotoRecolor.fetchSource(from: URL(string: "https://cdn.example.test\(path)"),
                                           session: session, maxBytes: maxBytes, isImage: { _ in true })
    }

    private func expectLoadError(_ expected: PhotoRecolor.LoadError,
                                 line: UInt = #line, _ body: () async throws -> Data) async {
        do {
            _ = try await body()
            XCTFail("読めてしまった", line: line)
        } catch {
            XCTAssertEqual(error as? PhotoRecolor.LoadError, expected, "\(error)", line: line)
        }
    }

    /// 読めた画像はそのまま返す
    func testFetchSourceReturnsImageData() async throws {
        ScriptedProtocol.script = [.init(match: "/img/a.jpg", status: 200, body: "JPEGDATA")]
        let data = try await fetch("/img/a.jpg")
        XCTAssertEqual(data, Data("JPEGDATA".utf8))
    }

    /// 🔴 **画像として読めない応答は断る**（Wi-Fi のログイン画面の HTML など）。判定は ImageIO（既定の `decodable`）
    func testFetchSourceRejectsNonImage() async {
        let html = "<!doctype html><html><body>Wi-Fi login</body></html>"
        ScriptedProtocol.script = [.init(match: "/img/a.jpg", status: 200, body: html)]
        XCTAssertFalse(PhotoRecolor.decodable(Data(html.utf8)), "HTML を画像と読んだ")
        let session = self.session!
        await expectLoadError(.notImage) {
            try await PhotoRecolor.fetchSource(from: URL(string: "https://cdn.example.test/img/a.jpg"),
                                               session: session)
        }
        // 判定は渡した読み手で決まる（Content-Type を見ていない）
        await expectLoadError(.notImage) {
            try await PhotoRecolor.fetchSource(from: URL(string: "https://cdn.example.test/img/a.jpg"),
                                               session: session, isImage: { _ in false })
        }
    }

    /// 403 は `.forbidden`（期限切れの見込み・呼ぶ側が取り直す）
    func testFetchSourceMapsForbidden() async {
        ScriptedProtocol.script = [.init(match: "/img/a.jpg", status: 403, body: "<Error>AccessDenied</Error>")]
        await expectLoadError(.forbidden) { try await self.fetch("/img/a.jpg") }
    }

    /// 🔴 **上限を超えたら断る**（大きすぎる応答を画像として読み始めない）
    func testFetchSourceRejectsTooLarge() async {
        ScriptedProtocol.script = [.init(match: "/img/a.jpg", status: 200, body: String(repeating: "x", count: 16))]
        await expectLoadError(.tooLarge) { try await self.fetch("/img/a.jpg", maxBytes: 8) }
    }

    /// 上限は時間 30 秒（つながってから読み終わるまで全体）・大きさ 30MB
    func testSourceLimits() {
        XCTAssertEqual(PhotoRecolor.maxSourceBytes, 30 * 1024 * 1024)
        XCTAssertEqual(PhotoRecolor.sourceSession.configuration.timeoutIntervalForResource, 30)
        XCTAssertEqual(PhotoRecolor.sourceSession.configuration.timeoutIntervalForRequest, 30)
    }

    /// 🔴 **403 なら写真を取り直して、新しい URL で1回だけ読み直す**
    func testLoadSourceRefreshesOnceOnForbidden() async throws {
        let old = URL(string: "https://cdn.example.test/old.jpg")!
        let fresh = URL(string: "https://cdn.example.test/new.jpg")!
        var asked: [URL?] = []
        var refreshes = 0
        let data = try await PhotoRecolor.loadSource(
            url: old,
            refreshURL: { refreshes += 1; return fresh },
            fetch: { url in
                asked.append(url)
                if url == old { throw PhotoRecolor.LoadError.forbidden }
                return Data([7])
            })
        XCTAssertEqual(data, Data([7]))
        XCTAssertEqual(asked, [old, fresh])
        XCTAssertEqual(refreshes, 1)
    }

    /// 取り直しても 403・取り直せない回は「開き直して」の案内（`.expired`）。読み直しは1回だけ
    func testLoadSourceGivesUpAfterOneRetry() async {
        let old = URL(string: "https://cdn.example.test/old.jpg")!
        var fetches = 0
        await expectLoadError(.expired) {
            try await PhotoRecolor.loadSource(
                url: old, refreshURL: { URL(string: "https://cdn.example.test/new.jpg") },
                fetch: { _ in fetches += 1; throw PhotoRecolor.LoadError.forbidden })
        }
        XCTAssertEqual(fetches, 2, "読み直しが1回ではない")
        await expectLoadError(.expired) {
            try await PhotoRecolor.loadSource(
                url: old, refreshURL: { nil },
                fetch: { _ in throw PhotoRecolor.LoadError.forbidden })
        }
        XCTAssertNotEqual(PhotoRecolor.LoadError.expired.errorDescription,
                          PhotoRecolor.LoadError.unreadable.errorDescription,
                          "開き直すしかない回を「時間をおいて」と案内している")
    }

    /// 403 以外の失敗では取り直さない
    func testLoadSourceDoesNotRefreshOnOtherErrors() async {
        var refreshes = 0
        await expectLoadError(.notImage) {
            try await PhotoRecolor.loadSource(
                url: URL(string: "https://cdn.example.test/a.jpg"),
                refreshURL: { refreshes += 1; return nil },
                fetch: { _ in throw PhotoRecolor.LoadError.notImage })
        }
        XCTAssertEqual(refreshes, 0)
    }
}
