import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 撮影スポットの写真の縮小版（索引の `image.thumbUrl`・2026-10-08〜）。
///
/// **40pt の丸に元の画像（平均 約148KB）を読まない。** 縮小版（短い辺 約240px）が
/// 索引にあればそれを、無ければ元の画像を出す（`SpotImage.smallURL`）。
/// 縮小版の欄が壊れていても、写真も行も落とさない。
final class SpotThumbTests: XCTestCase {

    private func decode(_ image: String) throws -> OfficialSpot {
        let json = "{\"spotId\":\"sp_a\",\"slug\":\"a\",\"name\":\"鍋ヶ滝\",\"stage\":\"published\",\"image\":\(image)}"
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private func image(thumb: String?) -> String {
        let t = thumb.map { ",\"thumbUrl\":\($0)" } ?? ""
        return "{\"url\":\"https://journey-photo.com/images/spots/a.jpg\",\"author\":\"A\",\"license\":\"CC0\"\(t)}"
    }

    private let full = "https://journey-photo.com/images/spots/a.jpg"
    private let thumb = "https://journey-photo.com/images/spots/thumbs/a.jpg"

    func testReadsThumbUrl() throws {
        let photo = try XCTUnwrap(try decode(image(thumb: "\"\(thumb)\"")).photo)
        XCTAssertEqual(photo.thumbUrl?.absoluteString, thumb)
        XCTAssertEqual(photo.url.absoluteString, full, "元の画像は大きな枠のためにそのまま残す")
        XCTAssertEqual(photo.smallURL.absoluteString, thumb)
    }

    /// まだ縮小版の無い索引（2026-10-08 時点の本番）・縮小版を作れなかった行
    func testMissingThumbFallsBackToTheFullImage() throws {
        let photo = try XCTUnwrap(try decode(image(thumb: nil)).photo)
        XCTAssertNil(photo.thumbUrl)
        XCTAssertEqual(photo.smallURL.absoluteString, full)
    }

    /// 🔴 **壊れた縮小版の欄で、写真も行も落とさない**（元の画像に落ちる）
    func testInvalidThumbKeepsThePhotoAndTheRow() throws {
        for bad in ["42", "null", "\"\"", "\"  \"", "[]", "{}", "true",
                    "\"http://journey-photo.com/images/spots/thumbs/a.jpg\"",
                    "\"/images/spots/thumbs/a.jpg\"", "\"javascript:alert(1)\""] {
            let spot = try decode(image(thumb: bad))
            XCTAssertEqual(spot.slug, "a", bad)
            let photo = try XCTUnwrap(spot.photo, bad)
            XCTAssertNil(photo.thumbUrl, bad)
            XCTAssertEqual(photo.smallURL.absoluteString, full, bad)
        }
        let list = try JSONDecoder.api.decode(LenientOfficialSpotList.self, from: Data("""
        [{"spotId":"sp_a","slug":"a","name":"A","stage":"published","image":\(image(thumb: "7"))}]
        """.utf8))
        XCTAssertEqual(list.spots.count, 1)
        XCTAssertEqual(list.dropped, 0)
        XCTAssertNotNil(list.spots.first?.photo)
    }

    /// 索引の行に詳細（区分）を重ねても縮小版が残る（`OfficialSpot.merged(with:)`）
    func testMergedRowKeepsThumbUrl() throws {
        var index = try decode("null")
        index.isIndexOnly = true
        XCTAssertNil(index.photo)
        let detail = try decode(image(thumb: "\"\(thumb)\""))
        let merged = index.merged(with: detail)
        XCTAssertEqual(merged.photo?.thumbUrl?.absoluteString, thumb)
        XCTAssertEqual(merged.photo?.smallURL.absoluteString, thumb)
    }

    /// 端末の控え（`SpotSnapshotStore`）から読み戻しても縮小版が残る
    func testSnapshotKeepsThumbUrl() throws {
        let store = SpotSnapshotStore(fileName: "spot-thumb-test-\(UUID().uuidString).json")
        defer { store.clear() }
        store.save(Data("""
        [{"spotId":"sp_a","slug":"a","name":"A","stage":"published","image":\(image(thumb: "\"\(thumb)\""))}]
        """.utf8))
        XCTAssertEqual(store.load()?.first?.photo?.thumbUrl?.absoluteString, thumb)
    }

    /// 地図のピンが縮小版を運ぶ（`OfficialPins.Pin.photo`）
    func testPinCarriesThumbUrl() throws {
        let json = "{\"spotId\":\"sp_a\",\"slug\":\"a\",\"name\":\"A\",\"stage\":\"published\",\"coords\":{\"lat\":33.08,\"lng\":131.06},\"image\":\(image(thumb: "\"\(thumb)\""))}"
        let spot = try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
        let frame = MapFraming.Frame(latitude: 33.08, longitude: 131.06, latitudeSpan: 0.1, longitudeSpan: 0.1)
        XCTAssertEqual(OfficialPins.visible([spot], frame: frame).first?.photo?.smallURL.absoluteString, thumb)
    }

    /// 「行きたい場所」の地図のピン（40pt の丸）は縮小版
    func testSavedSpotsMapPinUsesTheSmallImage() throws {
        let spot = try decode(image(thumb: "\"\(thumb)\""))
        let row = OfficialWishlist.Row(key: SavedSpotKey.official(spot.slug), slug: spot.slug, name: spot.name,
                                       regionLabel: nil, spot: spot)
        XCTAssertEqual(SavedSpotsMap.item(row).imageURL?.absoluteString, thumb)
        XCTAssertEqual(SavedSpotsMap.item(row).imageFallbackURL?.absoluteString, full, "読めなければ元の画像")
    }

    // MARK: - 呼ぶ所（画面は Linux で描けないので文で見る）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 🔴 **小さな枠は縮小版（読めなければ元の画像）。** 地図の一覧の丸（地域ごとの一覧も同じ `spotRow`）・
    /// 地図のピン・旅の下書きの行・マイページの「行きたい」の行・「行きたい場所」の地図のピン
    func testSmallThumbnailsUseSmallURL() throws {
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertTrue(map.contains("SpotMapMarker(photoURL: pin.photo?.smallURL, fallbackURL: pin.photo?.smallFallbackURL)"),
                      "地図のピン")
        XCTAssertTrue(map.contains("SpotThumbImage(image: photo)"), "地図の一覧の丸（spotRow）")
        XCTAssertTrue(try source("Features/Trips/TripPickerDraftView.swift")
            .contains(".overlay(SpotThumbImage(image: photo))"), "旅の下書きの行")
        XCTAssertTrue(try source("Features/Profile/MyPageView.swift")
            .contains("SpotThumbImage(image: photo, assumedRatioLimit: 2)"), "マイページの「行きたい」の行")
        let saved = try source("Core/Text/SavedSpotsMap.swift")
        XCTAssertTrue(saved.contains("imageURL: row.spot?.photo?.smallURL"), "「行きたい場所」の地図のピン")
        XCTAssertTrue(saved.contains("imageFallbackURL: row.spot?.photo?.smallFallbackURL"), "「行きたい場所」の地図のピン")
        XCTAssertTrue(try source("Features/Profile/SavedSpotsMapView.swift")
            .contains("SpotMapMarker(photoURL: photoURL, fallbackURL: fallbackURL)"), "「行きたい場所」のピンが切り替え先を渡す")
        XCTAssertTrue(try source("Features/Map/SpotMapMarker.swift")
            .contains("SpotThumbImage(url: photoURL, fallbackURL: fallbackURL)"), "ピンの丸が切り替える")
    }

    /// 小さな枠のある5つのファイルで、**元の画像（`photo.url`）を直に読むのは地図の札の頭の1か所だけ**。
    /// 小さな枠を足したときに縮小版を使い忘れたら、ここで気づく
    func testSmallSiteFilesDoNotReadTheFullURLDirectly() throws {
        let files = ["Features/Map/PhotoMapView.swift": 1,  // 札の頭（高さ 150pt）
                     "Core/Text/SavedSpotsMap.swift": 0,
                     "Features/Trips/TripPickerDraftView.swift": 0,
                     "Features/Profile/MyPageView.swift": 0,
                     "Features/Map/SpotMapMarker.swift": 0]
        for (file, allowed) in files {
            let text = try source(file)
            let count = text.components(separatedBy: "photo.url").count - 1
                + text.components(separatedBy: "photo?.url").count - 1
            XCTAssertEqual(count, allowed, "\(file) が元の画像を直に読んでいる（小さな枠は SpotThumbImage / smallURL）")
        }
    }

    // MARK: - 縮小版が読めなかったとき（`SpotThumbFallback`）

    private func spotImage(thumb: String?) throws -> SpotImage {
        try XCTUnwrap(try decode(image(thumb: thumb.map { "\"\($0)\"" })).photo)
    }

    /// 🔴 **縮小版が読めなければ、一度だけ元の画像に切り替える**（CDN に届く前・1枚だけ 404）
    func testFailedThumbSwitchesToTheFullImageOnce() throws {
        var state = SpotThumbFallback(try spotImage(thumb: thumb))
        XCTAssertEqual(state.current.absoluteString, thumb, "先に縮小版")
        XCTAssertTrue(state.failed(), "縮小版が読めなければ切り替える")
        XCTAssertEqual(state.current.absoluteString, full)
        XCTAssertFalse(state.failed(), "元の画像も読めなければそのまま（行き来しない）")
        XCTAssertEqual(state.current.absoluteString, full)
        XCTAssertFalse(state.failed())
        XCTAssertEqual(state.current.absoluteString, full)
    }

    /// 縮小版の無い行は元の画像だけ。**二度読まない**
    func testNoThumbMeansNoSecondAttempt() throws {
        let photo = try spotImage(thumb: nil)
        XCTAssertNil(photo.smallFallbackURL)
        var state = SpotThumbFallback(photo)
        XCTAssertEqual(state.current.absoluteString, full)
        XCTAssertFalse(state.failed())
        XCTAssertEqual(state.current.absoluteString, full)
    }

    /// 縮小版が元の画像と同じ URL なら、同じものを二度読まない
    func testSameURLDoesNotRetry() throws {
        let photo = try spotImage(thumb: full)
        XCTAssertNil(photo.smallFallbackURL)
        var state = SpotThumbFallback(primary: photo.smallURL, fallback: photo.url)
        XCTAssertFalse(state.failed())
    }

    /// 撮影地の写真のピン（切り替え先なし）は今までどおり1つだけ読む
    func testMarkerWithoutFallbackKeepsItsURL() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/pin.jpg"))
        var state = SpotThumbFallback(primary: url, fallback: nil)
        XCTAssertFalse(state.failed())
        XCTAssertEqual(state.current, url)
    }

    /// 大きな枠（スポットの画面の頭・地図の札の頭・旅を選ぶ札）は元の画像のまま。縮小版を伸ばさない
    func testLargeImagesKeepTheFullURL() throws {
        XCTAssertTrue(try source("Features/Spots/OfficialSpotView.swift").contains(".overlay(RemoteImage(url: photo.url))"))
        XCTAssertTrue(try source("Features/Map/PhotoMapView.swift").contains(".overlay(RemoteImage(url: photo.url))"))
        XCTAssertTrue(try source("Features/Trips/TripPickerView.swift").contains("photoFrame(photo.url)"))
        XCTAssertTrue(try source("Features/Gallery/HomeTopCardView.swift").contains("backdropURL: spot.photo?.url"))
    }

    // MARK: - 画像の控え

    /// 🔴 **起動で画像の控え（`URLCache.shared`）を広げる。** 既定の小さな控えでは、一覧を
    /// 開き直すたびに丸い写真を読み直す（`AsyncImage` は `URLSession.shared` を使う）
    @MainActor
    func testAppLaunchEnlargesTheSharedURLCache() async {
        let savedCache = URLCache.shared
        let savedConfig = AppConfig.testOverrides
        defer {
            URLCache.shared = savedCache
            AppConfig.testOverrides = savedConfig
        }
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPApiBaseURL": "https://api.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
        URLCache.shared = URLCache(memoryCapacity: 1024, diskCapacity: 1024, diskPath: nil)
        _ = JourneyPhotoApp()
        XCTAssertGreaterThanOrEqual(URLCache.shared.memoryCapacity, 32 * 1024 * 1024)
        XCTAssertGreaterThanOrEqual(URLCache.shared.diskCapacity, 200 * 1024 * 1024)
        XCTAssertEqual(URLCache.shared.memoryCapacity, JourneyPhotoApp.imageCacheMemoryBytes)
        XCTAssertEqual(URLCache.shared.diskCapacity, JourneyPhotoApp.imageCacheDiskBytes)
    }
}
