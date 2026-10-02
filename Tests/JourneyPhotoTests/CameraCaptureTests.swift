import XCTest
import ImageIO
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// カメラで撮った1枚（`CameraCapture` → 投稿の画面のモデルの `accept(capture:)`）。
///
/// 🔴 以前は撮影の画面の知らせ（主スレッド）の上で `jpegData(1.0)` をしていて、撮った写真の
/// 撮影日（`takenOn`）がいつも空だった（`UIImage` を経由すると EXIF が残らない）
final class CameraCaptureTests: XCTestCase {

    private func prepared(takenOn: String? = nil) -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg",
                               contentType: "image/jpeg", exif: nil, coords: nil, takenOn: takenOn)
    }

    private let cameraMetadata: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:13 08:21:05"] as [CFString: Any],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple",
                                         kCGImagePropertyTIFFModel: "iPhone 15 Pro"] as [CFString: Any],
    ]

    /// カメラが付けた撮影情報から、撮影日・撮影日時・機種を付ける
    func testCaptureInfoComesFromTheCameraMetadata() {
        let out = ImagePreparer.applyingCaptureInfo(prepared(), metadata: cameraMetadata,
                                                    capturedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(out.takenOn, "2026-09-13")
        XCTAssertEqual(out.exif?.dateTimeOriginal, "2026-09-13T08:21:05")
        XCTAssertEqual(out.exif?.camera, "Apple iPhone 15 Pro")
        XCTAssertNil(out.coords, "カメラの写真に座標を作った")
    }

    /// 撮影情報に撮影日時が無ければ、撮った時刻を**端末の時間帯の壁時計で**撮影日にする（2026-10-02 判断）
    func testFallsBackToTheCaptureTimeInTheLocalTimeZone() throws {
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        // 2026-10-01T20:30:00Z = 東京の 10/2 05:30（UTC で書くと日付が1日ずれる）
        let at = Date(timeIntervalSince1970: 1_790_886_600)
        let out = ImagePreparer.applyingCaptureInfo(prepared(), metadata: [:], capturedAt: at, timeZone: tokyo)
        XCTAssertEqual(out.takenOn, "2026-10-02")
        XCTAssertEqual(out.exif?.dateTimeOriginal, "2026-10-02T05:30:00")
        XCTAssertNil(out.exif?.camera)
    }

    /// 🔴 **画面の流れの配線まで見る。** JPEG にする・整えるのは主スレッドの外で、
    /// 待ち行列に入った1枚に撮影日と機種が付いている
    @MainActor
    func testModelEncodesOffTheMainThreadAndKeepsTheDate() async throws {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"))
        let model = UploadViewModel(uploads: UploadService(api: api), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        let seen = ThreadLog()
        let base = prepared()
        model.prepareData = { _ in
            seen.note("prepare")
            return base
        }
        model.accept(capture: CameraCapture(metadata: cameraMetadata, capturedAt: Date(), encode: {
            seen.note("encode")
            return Data([1])
        }))
        for _ in 0..<500 where model.items.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let item = try XCTUnwrap(model.items.first)
        XCTAssertEqual(item.prepared.takenOn, "2026-09-13", "カメラの1枚の撮影日が落ちた")
        XCTAssertEqual(item.prepared.exif?.camera, "Apple iPhone 15 Pro")
        XCTAssertEqual(seen.onMain, [], "主スレッドで画像を変換した")
        XCTAssertEqual(Set(seen.all), ["encode", "prepare"])
    }
}

/// どの仕事がどのスレッドで走ったかの控え（別スレッドから書く）
final class ThreadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(name: String, main: Bool)] = []

    func note(_ name: String) {
        let main = Thread.isMainThread
        lock.lock(); defer { lock.unlock() }
        entries.append((name, main))
    }

    var all: [String] { lock.lock(); defer { lock.unlock() }; return entries.map(\.name) }
    var onMain: [String] { lock.lock(); defer { lock.unlock() }; return entries.filter(\.main).map(\.name) }
}
