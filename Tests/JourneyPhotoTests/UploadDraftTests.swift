import XCTest
@testable import JourneyPhoto

final class UploadDraftTests: XCTestCase {

    /// **座標は端末側でも丸めてから送る。** サーバーも丸めるが、
    /// 丸める前の値を電波に乗せる理由が無い。
    func testCoordsAreRoundedToAboutOneKilometer() throws {
        var draft = PhotoDraft()
        draft.coords = Photo.Coords(lat: 34.123456, lng: 133.987654)
        let body = draft.saveBody(key: "uploads/u/1.jpg", publicUrl: "https://x/1.jpg")
        XCTAssertEqual(body.coords?.lat, 34.12)
        XCTAssertEqual(body.coords?.lng, 133.99)
    }

    /// 空の項目は送らない（api-user は「未指定＝触らない」と読む）。
    func testEmptyFieldsAreOmitted() throws {
        let body = PhotoDraft().saveBody(key: "k", publicUrl: "u")
        XCTAssertNil(body.title)
        XCTAssertNil(body.location)
        XCTAssertNil(body.tags)
    }

    /// 区切りは読点・カンマ・空白のどれでもよい。重複は落とす
    /// （同じタグが2つ付くと絞り込みの件数がずれる）。
    func testTagParsing() {
        XCTAssertEqual(TagInput.parse("雲海, sunrise 雲海"), ["雲海", "sunrise"])
        XCTAssertEqual(TagInput.parse("  "), [])
        XCTAssertEqual(TagInput.parse("a、b"), ["a", "b"])
    }
}
