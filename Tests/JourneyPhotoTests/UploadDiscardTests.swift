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
        XCTAssertFalse(model.hasDraft)
    }

    /// 写真の前でも入れられる欄を変えたら書きかけ（最初から入れたタグと同じ間は違う）
    func testFieldsBeforePhotosCountAsDraft() async {
        let model = model()
        model.tagsText = "夕焼け"
        model.initialTagsText = "夕焼け"
        XCTAssertFalse(model.hasDraft)
        model.tagsText = "夕焼け 海"
        XCTAssertTrue(model.hasDraft)
        model.tagsText = "夕焼け"
        model.published = false
        XCTAssertTrue(model.hasDraft)
        model.published = true
        model.category = "風景"
        XCTAssertTrue(model.hasDraft)
        model.category = ""
        model.selectedAlbumId = "a1"
        XCTAssertTrue(model.hasDraft)
        model.selectedAlbumId = nil
        model.audience = .closeFriends
        XCTAssertTrue(model.hasDraft)
    }

    /// タグは中身で比べる（候補を足して外したあとの「, 」の残りで書きかけにしない）
    func testTagsAreComparedByContent() async {
        let model = model()
        model.initialTagsText = "夕焼け"
        model.tagsText = "夕焼け, "
        XCTAssertFalse(model.hasDraft)
        model.tagsText = ""
        model.initialTagsText = ""
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

    // MARK: - 旅の写真からまとめて（非公開で始める・最初の写真）

    /// 非公開で始めた画面は、非公開のままなら書きかけではない（公開に変えたら書きかけ）
    func testStartingPrivateIsNotADraft() async {
        let model = model()
        model.applyInitialPhotos([], startPrivate: true)
        XCTAssertFalse(model.published, "非公開で始まっていない")
        XCTAssertFalse(model.hasDraft, "非公開で始めただけで、閉じるときに確かめている")
        model.published = true
        XCTAssertTrue(model.hasDraft)
    }

    /// 最初の写真は一度だけ入れる。2枚以上ならまとめる。並んだら書きかけ。
    /// 写真は選ぶ画面が整えて渡す（読めなかった写真はそこで外して知らせる・`LibraryTripPickView`）
    func testInitialPhotosAreAppliedOnce() async throws {
        let model = model()
        func shot(_ byte: UInt8) -> ImagePreparer.Prepared {
            ImagePreparer.Prepared(data: Data([byte]), fileName: "p.jpg", contentType: "image/jpeg",
                                   exif: nil, coords: nil, takenOn: nil)
        }
        model.applyInitialPhotos([shot(1), shot(2)], startPrivate: true)
        XCTAssertTrue(model.groupsAsOnePost, "同じ旅の写真なのに別々の投稿になる")
        XCTAssertTrue(model.hasDraft, "並んだ写真を閉じると黙って消える")
        XCTAssertEqual(model.items.count, 2)
        // 選択画面などから戻ってきた（onAppear がまた呼ばれる）
        model.applyInitialPhotos([shot(3)], startPrivate: false)
        XCTAssertFalse(model.published, "2回目の呼び出しで初期値が変わった")
        XCTAssertEqual(model.items.map(\.prepared.data), [Data([1]), Data([2])], "同じ写真をもう一度足した")
    }
}
