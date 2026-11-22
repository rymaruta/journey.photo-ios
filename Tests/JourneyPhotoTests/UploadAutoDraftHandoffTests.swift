import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 裏で送っている投稿が、次に開いた投稿の画面の書きかけ（アプリが落ちたときの控え）を消さない（札 #687）。
/// 「投稿する」で画面を閉じて裏で送る（案 B2・`PostUploadCenter`）ので、送っている間に次の画面が同じ書きかけの枠を持つ
@MainActor
final class UploadAutoDraftHandoffTests: XCTestCase {

    private let defaults = UserDefaults(suiteName: "UploadAutoDraftHandoffTests.\(UUID().uuidString)")!
    nonisolated private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("UploadAutoDraftHandoffTests-\(UUID().uuidString)")

    override func tearDown() {
        ScriptedProtocol.reset()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func store(_ slot: UploadDraftStore.Slot) -> UploadDraftStore {
        UploadDraftStore(defaults: defaults, directory: directory, slot: slot)
    }

    private func model() -> UploadViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: config)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let m = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        m.locationPreference = UploadLocationPreference(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        m.drafts = store(.entry(UUID().uuidString))
        m.autoDrafts = store(.auto)
        m.draftOwner = "u1"
        m.makeDraftThumbnail = { _ in nil }
        return m
    }

    private func photo(_ byte: UInt8) -> PendingPhoto {
        PendingPhoto(prepared: ImagePreparer.Prepared(data: Data(repeating: byte, count: 16), fileName: "p\(byte).jpg",
                                                      contentType: "image/jpeg", exif: nil, coords: nil, takenOn: nil))
    }

    func testSentPostDoesNotClearTheNextScreensAutoDraft() async {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
            """),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        // A: 投稿する（書きかけは送信の控えに移る）
        let a = model()
        a.items = [photo(1)]
        a.items[0].title = "A の写真"
        await a.submit()
        XCTAssertTrue(a.didPostAll)

        // B: 送っている間に開いた次の画面。裏に回って書きかけを書く
        let b = model()
        b.items = [photo(2)]
        b.items[0].title = "B の書きかけ"
        await b.autoSaveDraft(now: Date())
        XCTAssertEqual(store(.auto).draft(for: "u1")?.items.first?.title, "B の書きかけ")

        // A が送り終える・やり直す（どちらも書きかけを片づける）
        a.discardAutoDraft()
        XCTAssertEqual(store(.auto).draft(for: "u1")?.items.first?.title, "B の書きかけ",
                       "裏で送っていた投稿が、次の画面の書きかけを消した")
    }
}
