import XCTest
@testable import JourneyPhoto

/// 投稿の書きかけを黙って捨てない（2026-09-30）。
/// 写真を選び始めたら「書きかけ」——閉じる前に確かめ、下へ払っても閉じない
@MainActor
final class UploadDiscardTests: XCTestCase {

    private func model() -> UploadViewModel {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"))
        return UploadViewModel(uploads: UploadService(api: api),
                               albums: AlbumService(api: api),
                               photos: PhotoService(api: api),
                               discovery: DiscoveryService(api: api))
    }

    private func pending() -> PendingPhoto {
        PendingPhoto(prepared: ImagePreparer.Prepared(data: Data(), fileName: "p.jpg", contentType: "image/jpeg",
                                                      exif: nil, coords: nil, takenOn: nil))
    }

    /// 何も選んでいなければ、そのまま閉じてよい（最初から入っているタグは本人の書きかけではない）
    func testNothingPickedIsNotADraft() async {
        let model = model()
        model.tagsText = "夕焼け"
        model.published = false
        XCTAssertFalse(model.hasDraft)
    }

    /// 写真を1枚でも選んだら書きかけ。外し切ったら書きかけではない
    func testPickedPhotoIsADraft() async {
        let model = model()
        model.items = [pending()]
        XCTAssertTrue(model.hasDraft)
        model.items = []
        XCTAssertFalse(model.hasDraft)
    }
}
