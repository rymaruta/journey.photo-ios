import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 🔴 **送っている最中に直した題・説明・撮影地を、黙って捨てない**（2026-10-03 の品質点検）。
///
/// 下書き（`PhotoDraft`）は送り始めに作っていたので、画像を書き出して置き場へ送るまで
/// （数秒）の間に直した欄は**古い値のまま保存され、保存のあと行ごと消えて失われた**。
/// 送信中も欄は触れる（`UploadView` は送信中の行を閉じない）。
/// 下書きは保存の直前に、いまの行から作り直す（`UploadViewModel.makeDraft`）
final class UploadEditWhileSendingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    @MainActor
    private func model(gate: Gate) -> UploadViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: config)
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
            """),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        // 置き場の鍵を取りに行く通信で止める（＝画像を置いている最中）
        let gates = PathGates(["/upload/presigned-url": gate])
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session,
                            beforeRequest: { request in await gates.wait(for: request) })
        let model = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        var item = PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))
        item.title = "古い題"
        item.caption = "古い説明"
        item.location = "古い場所"
        model.items = [item]
        return model
    }

    /// 保存の口に送った本文（JSON）
    private func savedBody() throws -> [String: Any] {
        let save = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path == "/upload/save" }, "保存を送っていない")
        let data = try XCTUnwrap(save.body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    func testFieldsEditedWhilePlacingTheImageAreSaved() async throws {
        let gate = Gate()
        let model = model(gate: gate)

        let sending = Task { await model.submit() }
        await gate.untilWaiting()
        // 画像を置いている最中に、欄を直す
        model.items[0].title = "直した題"
        model.items[0].caption = "直した説明"
        model.items[0].location = "直した場所"
        await gate.open()
        await sending.value

        let body = try savedBody()
        XCTAssertEqual(body["title"] as? String, "直した題", "送信中に直した題が古い値で保存された")
        XCTAssertEqual(body["description"] as? String, "直した説明")
        XCTAssertEqual(body["location"] as? String, "直した場所")
        XCTAssertTrue(model.didPostAll)
    }

    /// 直さなければ、今までどおり始めたときの値で保存する（対照）
    @MainActor
    func testUneditedFieldsAreSavedAsTheyWere() async throws {
        let gate = Gate()
        let model = model(gate: gate)

        let sending = Task { await model.submit() }
        await gate.untilWaiting()
        await gate.open()
        await sending.value

        let body = try savedBody()
        XCTAssertEqual(body["title"] as? String, "古い題")
        XCTAssertEqual(body["description"] as? String, "古い説明")
        XCTAssertEqual(body["location"] as? String, "古い場所")
    }
}
