import XCTest
@testable import JourneyPhoto

/// 写真の編集と投稿の、端末で見つかった穴の直し（2026-10-03）のうち純な部分:
/// 編集画面の読み込みの順番・写真の欄に出すもの・帯のサムネの元・
/// 読めなかった写真の読み直し・投稿したばかりの写真を一覧に合わせる・一時ファイルの守り
final class EditPostDeviceFixesTests: XCTestCase {

    // MARK: - 編集画面の読み込みの順番（`PhotoEditLoadSteps`）

    /// 枠の大きさが 0 の回は始めず、取れたら1回だけ始める
    func testLoadWaitsForANonZeroBox() {
        var steps = PhotoEditLoadSteps()
        XCTAssertNil(steps.sized(box: .zero, scale: 3), "大きさ 0 で読み始めた")
        XCTAssertNil(steps.sized(box: CGSize(width: 390, height: 0), scale: 3))
        XCTAssertEqual(steps.phase, .waitingForSize)
        XCTAssertEqual(steps.sized(box: CGSize(width: 390, height: 500), scale: 3), 1500)
        XCTAssertEqual(steps.phase, .loadingPhoto(pixels: 1500))
        XCTAssertNil(steps.sized(box: CGSize(width: 400, height: 600), scale: 3), "2度目の大きさで読み直さない")
    }

    /// 写真が出てから見本を描く。見本の順は「なし」→ プリセット
    func testPhotoComesBeforeThumbs() {
        var steps = PhotoEditLoadSteps()
        _ = steps.sized(box: CGSize(width: 390, height: 500), scale: 2)
        let run = steps.run
        XCTAssertFalse(steps.acceptsThumb(run: run), "写真より先に見本を入れた")
        XCTAssertTrue(steps.photoLoaded(true, run: run))
        XCTAssertTrue(steps.acceptsThumb(run: run))
        steps.thumbsDrawn(run: run)
        XCTAssertEqual(steps.phase, .done)
        XCTAssertEqual(PhotoEditLoadSteps.thumbOrder.first, PhotoEditPreview.noneKey)
        XCTAssertEqual(PhotoEditLoadSteps.thumbOrder.count, PhotoPresets.all.count + 1)
    }

    func testPhotoFailureStopsThumbs() {
        var steps = PhotoEditLoadSteps()
        _ = steps.sized(box: CGSize(width: 390, height: 500), scale: 2)
        XCTAssertFalse(steps.photoLoaded(false, run: steps.run))
        XCTAssertEqual(steps.phase, .failed)
        XCTAssertFalse(steps.acceptsThumb(run: steps.run))
    }

    /// 閉じたら取り消す。開き直したら始め直し、前の回の結果は入れない
    func testDisappearCancelsAndOldRunsAreDropped() {
        var steps = PhotoEditLoadSteps()
        _ = steps.sized(box: CGSize(width: 390, height: 500), scale: 2)
        let first = steps.run
        XCTAssertTrue(steps.photoLoaded(true, run: first))
        steps.disappeared()
        XCTAssertEqual(steps.phase, .cancelled)
        XCTAssertFalse(steps.acceptsThumb(run: first), "閉じたあとに見本を入れた")

        XCTAssertNotNil(steps.sized(box: CGSize(width: 390, height: 500), scale: 2), "開き直しで始め直さない")
        XCTAssertNotEqual(steps.run, first)
        XCTAssertFalse(steps.photoLoaded(true, run: first), "前の回の写真を入れた")
        XCTAssertTrue(steps.photoLoaded(true, run: steps.run))

        // 描き終えた後に閉じても終わったまま
        steps.thumbsDrawn(run: steps.run)
        steps.disappeared()
        XCTAssertEqual(steps.phase, .done)
    }

    /// 編集画面の読む大きさの境い目
    func testPreviewPixelSizeEdges() {
        XCTAssertNil(PhotoRenderer.previewPixelSize(box: .zero, scale: 3))
        XCTAssertNil(PhotoRenderer.previewPixelSize(box: CGSize(width: 0, height: 500), scale: 3))
        XCTAssertNil(PhotoRenderer.previewPixelSize(box: CGSize(width: -1, height: 500), scale: 3))
        XCTAssertNil(PhotoRenderer.previewPixelSize(box: CGSize(width: 390, height: 500), scale: 0))
        XCTAssertNil(PhotoRenderer.previewPixelSize(box: CGSize(width: 390, height: Double.infinity), scale: 3))
        XCTAssertNil(PhotoRenderer.previewPixelSize(box: CGSize(width: Double.nan, height: 500), scale: 3))
        // ごく小さい枠でも 1px は読む（切り上げ）
        XCTAssertEqual(PhotoRenderer.previewPixelSize(box: CGSize(width: 0.1, height: 0.1), scale: 1), 1)
        // 上限ちょうどは通し、1px でも超えたら読まない
        XCTAssertEqual(PhotoRenderer.previewPixelSize(box: CGSize(width: 50_000, height: 10), scale: 2), 100_000)
        XCTAssertNil(PhotoRenderer.previewPixelSize(box: CGSize(width: 50_000.5, height: 10), scale: 2))
    }

    /// 見本は読んだ写真を縮めて作る（倍率の境い目）
    func testThumbDownscaleFactor() {
        XCTAssertEqual(PhotoRenderer.downscaleFactor(width: 1500, height: 1000, maxPixelSize: 384), 384.0 / 1500)
        XCTAssertNil(PhotoRenderer.downscaleFactor(width: 384, height: 200, maxPixelSize: 384), "もう小さければ縮めない")
        XCTAssertNil(PhotoRenderer.downscaleFactor(width: 0, height: 0, maxPixelSize: 384))
        XCTAssertNil(PhotoRenderer.downscaleFactor(width: 1500, height: 1000, maxPixelSize: 0))
        XCTAssertNil(PhotoRenderer.downscaleFactor(width: .infinity, height: 1000, maxPixelSize: 384))
    }

    // MARK: - 写真の欄に出すもの（`PhotoEditScreen.photoShown`）

    /// 🔴 編集済みの写真で開き直したとき、編集後の絵が届くまで元の写真を札なしで出さない
    func testReopenedEditShowsPlaceholderUntilFirstRender() {
        let screen = PhotoEditScreen(original: PhotoRecipe(exposure: 0.4))
        XCTAssertEqual(screen.photoShown(hasEdited: false, hasBefore: true, hasPlaceholder: true, failed: false),
                       .placeholder, "元の写真を札なしで出した")
        XCTAssertEqual(screen.photoShown(hasEdited: false, hasBefore: true, hasPlaceholder: false, failed: false),
                       .spinner)
        XCTAssertEqual(screen.photoShown(hasEdited: true, hasBefore: true, hasPlaceholder: true, failed: false),
                       .edited)
        XCTAssertEqual(screen.photoShown(hasEdited: false, hasBefore: false, hasPlaceholder: true, failed: true),
                       .failed)
    }

    func testUneditedPhotoShowsTheOriginal() {
        let screen = PhotoEditScreen(original: .identity)
        XCTAssertEqual(screen.photoShown(hasEdited: false, hasBefore: true, hasPlaceholder: false, failed: false),
                       .before)
        XCTAssertEqual(screen.photoShown(hasEdited: false, hasBefore: false, hasPlaceholder: false, failed: false),
                       .spinner)
    }

    /// 長押しの間は元の写真（届いていなければスピナー）
    func testComparingShowsTheOriginal() {
        var screen = PhotoEditScreen(original: PhotoRecipe(exposure: 0.4))
        let t0 = Date(timeIntervalSince1970: 0)
        screen.press(.began(at: t0))
        screen.press(.tick(now: t0.addingTimeInterval(1)))
        XCTAssertEqual(screen.photoShown(hasEdited: true, hasBefore: true, hasPlaceholder: true, failed: false),
                       .before)
        XCTAssertEqual(screen.photoShown(hasEdited: true, hasBefore: false, hasPlaceholder: true, failed: false),
                       .spinner)
    }

    // MARK: - 帯のサムネの元（`StripThumb`）

    func testStripThumbPrefersTheListThumbnail() {
        let withThumb = ImagePreparer.Prepared(data: Data(repeating: 1, count: 100), fileName: "photo.jpg",
                                               contentType: "image/jpeg", exif: nil, coords: nil, takenOn: nil,
                                               thumbnail: Data([2, 2]))
        XCTAssertEqual(StripThumb.source(for: withThumb), Data([2, 2]), "1920px の本体から作った")
        let noThumb = ImagePreparer.Prepared(data: Data([1]), fileName: "photo.jpg", contentType: "image/jpeg",
                                             exif: nil, coords: nil, takenOn: nil)
        XCTAssertEqual(StripThumb.source(for: noThumb), Data([1]))
        XCTAssertEqual(StripThumb.maxPixelSize, 360, "編集後のサムネと同じ大きさ")
    }

    // MARK: - 読めなかった写真の読み直し（`PickerReconcile.toLoad`）

    func testRetryReloadsUnreadableWithoutNewPicks() {
        let plain = PickerReconcile.toLoad(added: ["a"], picked: ["a", "b"], unreadable: ["a"])
        XCTAssertEqual(plain.load, [], "選び足していないのに読み直した（今までどおり）")
        let retry = PickerReconcile.toLoad(added: ["a"], picked: ["a", "b"], unreadable: ["a"], retry: true)
        XCTAssertEqual(retry.load, ["a"])
        XCTAssertEqual(retry.unreadable, [], "読む分は控えから外す")
    }

    // MARK: - 投稿したばかりの写真（`PostedPhotos`）

    private func photo(_ id: String, at: String, src: String? = nil, owner: String = "me") throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"\#(id)","src":"\#(src ?? "/uploads/\(id).jpg")","createdAt":"\#(at)","userId":"\#(owner)"}"#.utf8))
    }

    /// 読み直しにまだ無い写真は先頭（新しい順）に足し、同じ id は読み直した行を採る
    func testPostedPhotosMergeWithTheReload() throws {
        let loaded = [try photo("b", at: "2026-10-02T00:00:00Z"), try photo("a", at: "2026-10-01T00:00:00Z",
                                                                             src: "https://cdn/signed-a.jpg")]
        let posted = [try photo("new", at: "2026-10-03T00:00:00Z"), try photo("a", at: "2026-10-01T00:00:00Z")]
        let merged = PostedPhotos.merge(loaded: loaded, posted: posted, owner: "me")
        XCTAssertEqual(merged.map(\.id), ["new", "b", "a"], "重複を除いて新しい順")
        XCTAssertEqual(merged.last?.src, "https://cdn/signed-a.jpg", "同じ id は読み直した行")
    }

    func testPostedPhotosOfAnotherPersonAreNotAdded() throws {
        // 足すものが無ければ並びに触らない（サーバーの順のまま）
        let loaded = [try photo("a", at: "2026-10-01T00:00:00Z"), try photo("b", at: "2026-10-02T00:00:00Z")]
        let other = [try photo("x", at: "2026-10-03T00:00:00Z", owner: "someone")]
        XCTAssertEqual(PostedPhotos.merge(loaded: loaded, posted: other, owner: "me").map(\.id), ["a", "b"])
        XCTAssertEqual(PostedPhotos.merge(loaded: loaded, posted: [], owner: "me").map(\.id), ["a", "b"])
        XCTAssertEqual(PostedPhotos.merge(loaded: loaded, posted: other, owner: nil).map(\.id), ["a", "b"])
    }

    /// ホームの自分の写真: 閉じた直後に足し、読み直しが返さなくても残す
    @MainActor
    func testGalleryKeepsPostedPhotoThroughALaggingReload() async throws {
        let model = GalleryViewModel(gallery: PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)))
        let old = try photo("old", at: "2026-10-01T00:00:00Z")
        await model.loadMyPhotos(viewerId: "me") { [old] }
        let posted = try photo("new", at: "2026-10-03T00:00:00Z")
        model.showPosted([posted], viewerId: "me")
        XCTAssertEqual(model.myPhotos.map(\.id), ["new", "old"], "読み直しの前に足していない")
        // 索引が遅れて、読み直しにまだ無い
        await model.loadMyPhotos(viewerId: "me") { [old] }
        XCTAssertEqual(model.myPhotos.map(\.id), ["new", "old"], "読み直しで消えた")
        // 次の読み直しはサーバーの答えだけ
        await model.loadMyPhotos(viewerId: "me") { [posted, old] }
        XCTAssertEqual(model.myPhotos.map(\.id), ["new", "old"])
    }

    // MARK: - 編集の元の一時ファイル（`PhotoEditSources.fileProtection`）

    /// 起動後に一度ロックを解けば読める守り（`.complete` だとロック中・裏で読めない）
    func testEditSourceProtectionIsUntilFirstUnlock() {
        let mask = Data.WritingOptions.fileProtectionMask.rawValue
        XCTAssertEqual(PhotoEditSources.fileProtection.rawValue & mask,
                       Data.WritingOptions.completeFileProtectionUntilFirstUserAuthentication.rawValue)
        XCTAssertTrue(PhotoEditSources.fileProtection.contains(.atomic))
    }
}
