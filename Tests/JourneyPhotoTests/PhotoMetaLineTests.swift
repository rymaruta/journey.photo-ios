import XCTest
@testable import JourneyPhoto

/// 写真の詳細（板 02）とビューア（板 14）の小さい1行。
final class PhotoMetaLineTests: XCTestCase {

    private func exif(_ json: String) throws -> Photo.Exif {
        try JSONDecoder.api.decode(Photo.Exif.self, from: Data(json.utf8))
    }

    // MARK: - 撮影日時

    /// 板の形「2026.09.12 · 17:42」。時刻は EXIF から
    func testStampJoinsDayAndExifTime() {
        XCTAssertEqual(PhotoMetaLine.stamp(date: "2026-09-12", exifDateTime: "2026-09-12T17:42:05"),
                       "2026.09.12 · 17:42")
    }

    /// アプリは EXIF の生の書式（`2026:09:12 17:42:05`）で送っている
    func testStampReadsRawExifFormat() {
        XCTAssertEqual(PhotoMetaLine.stamp(date: nil, exifDateTime: "2026:09:12 07:05:00"),
                       "2026.09.12 · 07:05")
    }

    /// 🔴 **`date` に付いている時刻は出さない**（撮った時刻とは限らない・`TakenDay`）
    func testTimeFromDateFieldIsNotShown() {
        XCTAssertEqual(PhotoMetaLine.stamp(date: "2026-09-19T17:46:27", exifDateTime: nil),
                       "2026.09.19")
    }

    /// 持ち主が撮影日を直した写真に、別の日の時刻を添えない
    func testExifTimeFromAnotherDayIsDropped() {
        XCTAssertEqual(PhotoMetaLine.stamp(date: "2024-10-11", exifDateTime: "2024-10-12T09:00:00"),
                       "2024.10.11")
    }

    /// 読めない値は出さない（生のまま描かない）
    func testUnreadableStampIsNil() {
        XCTAssertNil(PhotoMetaLine.stamp(date: "昨日", exifDateTime: "2026-13-40T99:99"))
        XCTAssertNil(PhotoMetaLine.stamp(date: nil, exifDateTime: nil))
    }

    // MARK: - 枚数

    /// 「1/1枚」は出さない。束のときだけ
    func testGroupPositionOnlyForGroups() {
        XCTAssertNil(PhotoMetaLine.groupPosition(1, of: 1))
        XCTAssertEqual(PhotoMetaLine.groupPosition(2, of: 3), L("2/3枚", "2 of 3"))
    }

    /// 日時が無くても枚数だけで行になる。どちらも無ければ行ごと出さない
    func testHeadlineKeepsOnlyWhatExists() {
        XCTAssertEqual(PhotoMetaLine.headline(date: nil, exifDateTime: nil, position: 1, of: 4),
                       L("1/4枚", "1 of 4"))
        XCTAssertEqual(PhotoMetaLine.headline(date: "2026-09-12", exifDateTime: "2026-09-12T17:42",
                                              position: 1, of: 3),
                       "2026.09.12 · 17:42 · " + L("1/3枚", "1 of 3"))
        XCTAssertNil(PhotoMetaLine.headline(date: nil, exifDateTime: nil, position: 1, of: 1))
    }

    /// ビューアの「1枚目 / N」（0 始まりの添字から）
    func testViewerPosition() {
        XCTAssertEqual(PhotoMetaLine.viewerPosition(0, of: 5), L("1枚目 / 5", "1 of 5"))
        XCTAssertNil(PhotoMetaLine.viewerPosition(0, of: 1))
    }

    // MARK: - 撮影情報の1行

    /// 板 14 の順（機種 · レンズ · f · s · ISO）。機種の二重のメーカー名は落とす
    func testExifLineOrderAndCameraDedup() throws {
        let e = try exif(#"{"camera":"Hasselblad Hasselblad X2D II 100C","lens":"XCD 35-100E@75","aperture":"f/4","exposure":"1/100s","iso":50,"focalLength":"75mm"}"#)
        XCTAssertEqual(PhotoMetaLine.exifLine(e),
                       "Hasselblad X2D II 100C · XCD 35-100E@75 · f/4 · 1/100s · ISO 50")
    }

    /// アプリが保存したシャッター（`1/400`）にも「s」を付けて揃える
    func testExifLineNormalisesShutter() throws {
        let e = try exif(#"{"aperture":"1.8","exposure":"1/400"}"#)
        XCTAssertEqual(PhotoMetaLine.exifLine(e), "f/1.8 · 1/400s")
    }

    /// 何も無ければ行ごと出さない
    func testExifLineEmpty() throws {
        XCTAssertNil(PhotoMetaLine.exifLine(nil))
        XCTAssertNil(PhotoMetaLine.exifLine(try exif(#"{"camera":"  ","iso":0}"#)))
    }
}
