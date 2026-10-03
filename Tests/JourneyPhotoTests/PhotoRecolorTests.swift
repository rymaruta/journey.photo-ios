import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿済みの写真の色を編集し直す（段階1・`PhotoRecolor`・`PhotoService.replace(keepCurrentMetadata:)`）。
///
/// - 本文に**撮影情報（EXIF・撮影日・座標）を載せない**——公開中の画像には無いので、載せると空で上書きする
/// - 代表色は載せる（書き出した画像から取ったもの）
/// - 無編集で「完了」なら何も送らない／差し替えの最中は二重に送らない
/// - 409（ストーリーから残した写真）はサーバーの文言をそのまま出す
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

    /// 🔴 **無編集で「完了」なら何も送らない**（書き出しも送信もしない・差し替えの印も立てない）
    @MainActor
    func testUnchangedRecipeSendsNothing() async throws {
        var exported = 0
        var sent = 0
        var flips: [Bool] = []
        // 強さ 0 のプリセットも無編集（`PhotoRecipe.isIdentity`）
        for recipe in [PhotoRecipe.identity, PhotoRecipe(preset: .init(id: "haze", strength: 0))] {
            let result = try await PhotoRecolor.finish(
                recipe: recipe, isBusy: { false }, setReplacing: { flips.append($0) },
                export: { _ in exported += 1; return PhotoRecolor.base(source: Data([1])) },
                send: { _ in sent += 1 })
            guard case .unchanged = result else { return XCTFail("無編集なのに \(result)") }
        }
        XCTAssertEqual(exported, 0, "無編集なのに書き出した")
        XCTAssertEqual(sent, 0, "無編集なのに送った")
        XCTAssertEqual(flips, [], "無編集なのに差し替えの印を立てた")
    }

    /// 変えていれば書き出して送り、印は送り終わったら下ろす
    @MainActor
    func testChangedRecipeExportsAndSends() async throws {
        var sentColor: String?
        var flips: [Bool] = []
        let recipe = PhotoRecipe(exposure: 0.5)
        let result = try await PhotoRecolor.finish(
            recipe: recipe, isBusy: { false }, setReplacing: { flips.append($0) },
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
    }

    /// 🔴 **差し替えの最中は二重に送らない。** 1回目の書き出しを待たせている間に2回目の「完了」が来ても通さない
    /// （印は書き出しの**前**に立てる）。保存の最中も同じ
    @MainActor
    func testSecondFinishWhileReplacingSendsNothing() async throws {
        var isReplacing = false
        var sent = 0
        var release: CheckedContinuation<Void, Never>?
        let recipe = PhotoRecipe(contrast: 0.3)

        let first = Task { @MainActor in
            try await PhotoRecolor.finish(
                recipe: recipe, isBusy: { isReplacing }, setReplacing: { isReplacing = $0 },
                export: { _ in
                    await withCheckedContinuation { release = $0 }
                    return PhotoRecolor.base(source: Data([1]))
                },
                send: { _ in sent += 1 })
        }
        // 1回目が書き出しで止まるまで待つ（時間で待たない）
        while release == nil { await Task.yield() }
        XCTAssertTrue(isReplacing)

        let second = try await PhotoRecolor.finish(
            recipe: recipe, isBusy: { isReplacing }, setReplacing: { isReplacing = $0 },
            export: { _ in XCTFail("2回目が書き出した"); return PhotoRecolor.base(source: Data([1])) },
            send: { _ in sent += 1 })
        guard case .busy = second else { return XCTFail("2回目が通った: \(second)") }

        release?.resume()
        guard case .replaced = try await first.value else { return XCTFail("1回目が差し替えていない") }
        XCTAssertEqual(sent, 1, "二重に送った")
        XCTAssertFalse(isReplacing, "印が下りていない")

        // 保存の最中も通さない
        let whileSaving = try await PhotoRecolor.finish(
            recipe: recipe, isBusy: { true }, setReplacing: { _ in XCTFail("保存中に印を立てた") },
            export: { _ in XCTFail("保存中に書き出した"); return PhotoRecolor.base(source: Data([1])) },
            send: { _ in sent += 1 })
        guard case .busy = whileSaving else { return XCTFail("保存中に通った") }
        XCTAssertEqual(sent, 1)
    }

    // MARK: - 409

    /// 🔴 **409（ストーリーから残した写真）はサーバーの文言をそのまま出す。** 失敗でも印は下ろす
    @MainActor
    func testConflictShowsServerMessage() async throws {
        let message = "元のストーリーが出ている間（最大25時間）は、公開範囲の変更と写真の差し替えはできません。ストーリーを削除すれば、すぐに変えられます"
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/photos/p1", status: 409, body: #"{"error":"\#(message)"}"#),
        ]
        let photos = PhotoService(api: api())
        let uploads = uploads()
        var isReplacing = false
        do {
            _ = try await PhotoRecolor.finish(
                recipe: PhotoRecipe(saturation: -0.4), isBusy: { isReplacing },
                setReplacing: { isReplacing = $0 },
                export: { _ in self.preparedWithEverything() },
                send: { prepared in
                    _ = try await photos.replace(photoId: "p1", prepared: prepared, uploads: uploads,
                                                 keepCurrentMetadata: true)
                })
            XCTFail("409 なのに通った")
        } catch {
            guard case .server(409, _)? = error as? APIError else { return XCTFail("形が違う: \(error)") }
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, message)
        }
        XCTAssertFalse(isReplacing, "失敗のあと印が下りていない（保存も閉じるも押せなくなる）")
    }
}
