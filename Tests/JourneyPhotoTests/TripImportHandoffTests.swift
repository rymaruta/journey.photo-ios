import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 🔴 前の旅の写真を、次の投稿に混ぜない（`TripImportHandoff`）。
/// 読み込みの途中で旅の流れを閉じたあとに写真が届き、次の「写真を投稿」や
/// 今日のテーマの投稿に並んでいた（しかも非公開で始まる）
final class TripImportHandoffTests: XCTestCase {

    /// 整えた写真（`LibraryTripPickView` が原本を縮めたもの）。見分けは本体で
    private let photos = [Data([1]), Data([2])].map {
        ImagePreparer.Prepared(data: $0, fileName: "photo.jpg", contentType: "image/jpeg",
                               exif: nil, coords: nil, takenOn: nil)
    }

    /// 流れが開いている間に届いた写真は受ける
    func testReceivedWhileOpen() {
        XCTAssertEqual(TripImportHandoff.received(photos, flowOpen: true).map(\.data), photos.map(\.data))
    }

    /// 閉じたあとに届いた写真は捨てる
    func testDroppedAfterClose() {
        XCTAssertTrue(TripImportHandoff.received(photos, flowOpen: false).isEmpty, "閉じたあとの写真を控えた")
    }

    /// 投稿画面へ控えを渡すのは旅の流れから開くときだけ
    func testOnlyTheTripFlowPassesPhotos() {
        XCTAssertEqual(TripImportHandoff.photosForUpload(opener: .tripFlow, pending: photos).map(\.data), photos.map(\.data))
        XCTAssertTrue(TripImportHandoff.photosForUpload(opener: .photo, pending: photos).isEmpty,
                      "ふつうの写真投稿に前の旅の写真が並ぶ")
        XCTAssertTrue(TripImportHandoff.photosForUpload(opener: .theme, pending: photos).isEmpty,
                      "今日のテーマの投稿に前の旅の写真が並ぶ")
    }

    /// 🔴 **投稿画面へは整えたものを渡す**（原本を10枚持ち続けない）。受けた画面は整え直さず、
    /// 渡した順のまま**すぐ**並べ、撮影日・丸めた座標・撮影情報をそのまま使う
    /// （旅の記録の日付と地図は、選ぶ画面で原本から読んだこれらで決まる）
    @MainActor
    func testUploadScreenTakesPreparedPhotosAsIs() async {
        // 座標のある写真は地名を引きに行く。外へは出さない（台本の無い口は 404）
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: URLSession(configuration: config))
        let model = UploadViewModel(uploads: UploadService(api: api), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.prepareData = { _ in
            XCTFail("整えたものをもう一度整えた")
            throw ImagePreparer.PrepareError.unreadable
        }
        var exif = ExifFields()
        exif.camera = "Apple iPhone 15 Pro"
        let shots = [
            ImagePreparer.Prepared(data: Data([1]), fileName: "photo.jpg", contentType: "image/jpeg",
                                   exif: exif, coords: Photo.Coords(lat: 35.01, lng: 135.77), takenOn: "2026-09-12"),
            ImagePreparer.Prepared(data: Data([2]), fileName: "photo.jpg", contentType: "image/jpeg",
                                   exif: nil, coords: nil, takenOn: "2026-09-13"),
        ]
        model.applyInitialPhotos(shots, startPrivate: true)

        XCTAssertEqual(model.items.map(\.prepared.data), [Data([1]), Data([2])], "並びが変わった・すぐ並ばない")
        XCTAssertEqual(model.items.map(\.prepared.takenOn), ["2026-09-12", "2026-09-13"])
        XCTAssertEqual(model.items.first?.prepared.coords, Photo.Coords(lat: 35.01, lng: 135.77))
        XCTAssertEqual(model.items.first?.prepared.exif?.camera, "Apple iPhone 15 Pro")
        XCTAssertTrue(model.canSubmit, "整え終わっているのに投稿させない")
        XCTAssertTrue(model.groupsForSubmit)
        XCTAssertFalse(model.published)
    }
}
