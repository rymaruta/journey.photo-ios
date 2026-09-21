import XCTest
@testable import JourneyPhoto

final class GearGroupsTests: XCTestCase {

    private func photo(_ id: String, focal: String?, likes: Int? = nil) throws -> Photo {
        var exif = ""
        if let focal { exif = ",\"exif\":{\"focalLength\":\"\(focal)\"}" }
        let likesJSON = likes.map { ",\"likes\":\($0)" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(exif)\(likesJSON)}".utf8))
    }

    func testReadsMillimetersFromEXIFText() {
        XCTAssertEqual(GearGroups.millimeters("35mm"), 35)
        XCTAssertEqual(GearGroups.millimeters("24.5 mm"), 24.5)
        XCTAssertEqual(GearGroups.millimeters("f=200mm"), 200)
        XCTAssertNil(GearGroups.millimeters("unknown"))
        XCTAssertNil(GearGroups.millimeters(nil))
        // 0mm は機材の値として意味が無い（読めなかった扱い）
        XCTAssertNil(GearGroups.millimeters("0mm"))
    }

    func testBoundariesGoToTheExpectedGroup() throws {
        XCTAssertEqual(GearGroups.group(of: try photo("a", focal: "35mm")), .wide)
        XCTAssertEqual(GearGroups.group(of: try photo("b", focal: "36mm")), .standard)
        XCTAssertEqual(GearGroups.group(of: try photo("c", focal: "70mm")), .standard)
        XCTAssertEqual(GearGroups.group(of: try photo("d", focal: "71mm")), .telephoto)
    }

    func testPhotosWithoutFocalLengthAreNotPlaced() throws {
        XCTAssertNil(GearGroups.group(of: try photo("x", focal: nil)))
    }

    func testEmptyGroupsAreNotShown() throws {
        let photos = [try photo("a", focal: "24mm"), try photo("b", focal: "28mm")]
        let sections = GearGroups.sections(in: photos)
        XCTAssertEqual(sections.map(\.group), [.wide])
        XCTAssertEqual(sections.first?.count, 2)
    }

    func testSectionsAreOrderedWideToTelephotoAndSortedByPopularity() throws {
        let photos = [
            try photo("tele", focal: "200mm"),
            try photo("wide1", focal: "24mm", likes: 1),
            try photo("wide2", focal: "24mm", likes: 9),
        ]
        let sections = GearGroups.sections(in: photos)
        XCTAssertEqual(sections.map(\.group), [.wide, .telephoto])
        XCTAssertEqual(sections[0].photos.map(\.id), ["wide2", "wide1"])
    }
}
