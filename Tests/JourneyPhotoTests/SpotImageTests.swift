import XCTest
@testable import JourneyPhoto

/// 撮影スポットの写真（索引の `image`・2026-09-26〜）。
///
/// **写真はおまけで、場所の情報が本体。** 写真の欄が壊れていても行は落とさない。
/// 作者とライセンスが欠けた写真は出さない（CC BY・CC BY-SA の表示が使う条件）。
final class SpotImageTests: XCTestCase {

    private func decode(_ image: String?) throws -> OfficialSpot {
        let img = image.map { ",\"image\":\($0)" } ?? ""
        let json = "{\"spotId\":\"sp_a\",\"slug\":\"a\",\"name\":\"鍋ヶ滝\",\"stage\":\"published\",\"coords\":{\"lat\":33.08,\"lng\":131.06}\(img)}"
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private let good = """
    {"url":"https://upload.wikimedia.org/a/640px-A.jpg","author":"Big Ben in Japan","license":"CC BY-SA 2.0",
     "licenseUrl":"https://creativecommons.org/licenses/by-sa/2.0","pageUrl":"https://commons.wikimedia.org/wiki/File:A.jpg"}
    """

    func testReadsThePhotoWithCredit() throws {
        let spot = try decode(good)
        XCTAssertEqual(spot.photo?.url.absoluteString, "https://upload.wikimedia.org/a/640px-A.jpg")
        XCTAssertEqual(spot.photo?.author, "Big Ben in Japan")
        XCTAssertEqual(spot.photo?.license, "CC BY-SA 2.0")
        XCTAssertEqual(spot.photo?.pageUrl?.absoluteString, "https://commons.wikimedia.org/wiki/File:A.jpg")
        XCTAssertTrue(spot.photo!.credit.contains("Big Ben in Japan"))
        XCTAssertTrue(spot.photo!.credit.contains("CC BY-SA 2.0"))
    }

    func testNoImageKeyMeansNoPhoto() throws {
        XCTAssertNil(try decode(nil).photo)
    }

    /// 🔴 **壊れた写真の欄で、スポットの行ごと落とさない**
    func testBrokenImageKeepsTheSpot() throws {
        for broken in ["\"just a string\"", "42", "[]", "{\"url\":7}", "null"] {
            let spot = try decode(broken)
            XCTAssertEqual(spot.slug, "a", broken)
            XCTAssertNil(spot.photo, broken)
        }
        let list = try JSONDecoder.api.decode(LenientOfficialSpotList.self, from: Data("""
        [{"spotId":"sp_a","slug":"a","name":"A","stage":"published","image":{"url":7}}]
        """.utf8))
        XCTAssertEqual(list.spots.count, 1)
        XCTAssertEqual(list.dropped, 0)
    }

    /// 🔴 **作者かライセンスが欠けた写真は出さない**（表示が使う条件）
    func testMissingCreditMeansNoPhoto() throws {
        XCTAssertNil(try decode("{\"url\":\"https://upload.wikimedia.org/a.jpg\",\"license\":\"CC BY 2.0\"}").photo)
        XCTAssertNil(try decode("{\"url\":\"https://upload.wikimedia.org/a.jpg\",\"author\":\" \",\"license\":\"CC BY 2.0\"}").photo)
        XCTAssertNil(try decode("{\"url\":\"https://upload.wikimedia.org/a.jpg\",\"author\":\"A\"}").photo)
    }

    /// https でない画像は出さない
    func testRejectsNonHttpsImage() throws {
        XCTAssertNil(try decode("{\"url\":\"http://upload.wikimedia.org/a.jpg\",\"author\":\"A\",\"license\":\"CC0\"}").photo)
    }

    /// 地図のピンが写真を運ぶ（地図の印と札の出典に使う）
    func testPinCarriesThePhoto() throws {
        let spot = try decode(good)
        let frame = MapFraming.Frame(latitude: 33.08, longitude: 131.06, latitudeSpan: 0.1, longitudeSpan: 0.1)
        let pins = OfficialPins.visible([spot], frame: frame)
        XCTAssertEqual(pins.first?.photo?.author, "Big Ben in Japan")
        let bare = try decode(nil)
        XCTAssertNil(OfficialPins.visible([bare], frame: frame).first?.photo)
    }
}
