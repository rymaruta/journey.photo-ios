import XCTest
@testable import JourneyPhoto

/// 「旅の写真から」で選んだ、撮影日時（EXIF）の無い写真にも撮影日を付ける（2026-10-07）。
///
/// ほかのアプリで保存した画像は EXIF の撮影日時が無く、撮影日が空のまま上がって
/// 一冊（撮影日のある写真だけ）から落ちていた。写真ライブラリの撮った時刻
/// （`LibraryShot.date`）を、カメラの1枚と同じ形で撮影日にする
final class LibraryShotTakenDateTests: XCTestCase {

    private func prepared(takenOn: String? = nil, exif: ExifFields? = nil) -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg",
                               contentType: "image/jpeg", exif: exif, coords: nil, takenOn: takenOn)
    }

    /// ニューヨークの 9/12 21:30（UTC では 9/13）は、旅の時間帯で 9/12 になる
    func testMissingDateIsFilledFromTheLibraryInTheTripTimeZone() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let takenAt = Date(timeIntervalSince1970: 1_789_263_000)  // 2026-09-13 01:30 UTC
        var exif = ExifFields()
        exif.camera = "Apple iPhone 15 Pro"
        let out = ImagePreparer.fillingTakenDate(prepared(exif: exif), takenAt: takenAt, timeZone: zone)
        XCTAssertEqual(out.takenOn, "2026-09-12", "撮影日時の無い写真に撮影日が付かない")
        XCTAssertEqual(out.exif?.dateTimeOriginal, "2026-09-12T21:30:00")
        XCTAssertEqual(out.exif?.camera, "Apple iPhone 15 Pro", "ほかの撮影情報を落とした")

        // 上げた写真は一冊に入る（撮影日のある写真だけが入る）
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"p\",\"src\":\"https://x/p.jpg\",\"date\":\"\(out.takenOn ?? "")\"}".utf8))
        XCTAssertTrue(TripBook.hasTakenDay(photo))
    }

    /// EXIF の撮影日がある写真はそのまま（撮った土地の壁時計が正）
    func testExistingDateIsKept() {
        var exif = ExifFields()
        exif.dateTimeOriginal = "2026-09-10T08:00:00"
        let input = prepared(takenOn: "2026-09-10", exif: exif)
        let out = ImagePreparer.fillingTakenDate(input, takenAt: Date(timeIntervalSince1970: 1_789_263_000),
                                                 timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(out.takenOn, "2026-09-10")
        XCTAssertEqual(out.exif, exif)
    }

    /// 選ぶ画面の読み込みが、旅の時間帯で撮影日を付けている
    func testPickViewFillsTheDate() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let view = try String(contentsOf: root.appendingPathComponent("Features/Trips/LibraryTripPickView.swift"),
                              encoding: .utf8)
        XCTAssertTrue(view.contains("ImagePreparer.fillingTakenDate("), "選んだ写真に撮影日を付けていない")
        XCTAssertTrue(view.contains("takenAt: shot.date, timeZone: zone"), "写真ライブラリの時刻・旅の時間帯で付けていない")
    }
}
