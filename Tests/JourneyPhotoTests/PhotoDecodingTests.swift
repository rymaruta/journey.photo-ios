import XCTest
@testable import JourneyPhoto

/// 写真の復号。**題と説明が2つの形で保存されている**のがこのデータの癖で、
/// 片方しか読めないと画面が空になる。
final class PhotoDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    func testDecodesPlainTitle() throws {
        let photo = try decode(#"{"id":"a","src":"https://x/1.jpg","title":"高屋神社"}"#)
        XCTAssertEqual(photo.displayTitle, "高屋神社")
    }

    func testDecodesLocalizedTitle() throws {
        let photo = try decode(#"{"id":"a","src":"https://x/1.jpg","title":{"ja":"高屋神社","en":"Takaya"}}"#)
        XCTAssertEqual(photo.title?.resolved(locale: "en"), "Takaya")
        XCTAssertEqual(photo.title?.resolved(locale: "ja"), "高屋神社")
    }

    /// 空文字でも次の言語に落とす。`??` で書くとここが空になる
    /// （Web 側で実際に英語ページが空になった）。
    func testEmptyLocaleFallsThrough() throws {
        let photo = try decode(#"{"id":"a","src":"https://x/1.jpg","title":{"en":"","ja":"雲海"}}"#)
        XCTAssertEqual(photo.title?.resolved(locale: "en"), "雲海")
    }

    /// 説明はエントリの中の改行も段落として割る（実データに4枚ある形）。
    func testDescriptionSplitsEmbeddedNewlines() throws {
        let photo = try decode(#"{"id":"a","src":"https://x/1.jpg","description":{"ja":["一行目\n二行目"]}}"#)
        XCTAssertEqual(photo.paragraphs, ["一行目", "二行目"])
    }

    func testUnknownFieldsDoNotBreakDecoding() throws {
        let photo = try decode(#"{"id":"a","src":"https://x/1.jpg","somethingNew":42}"#)
        XCTAssertEqual(photo.id, "a")
    }

    /// 一覧では軽い方を使う。無ければ落としていく。
    func testGridImageFallsBackToSrc() throws {
        let photo = try decode(#"{"id":"a","src":"https://x/full.jpg"}"#)
        XCTAssertEqual(photo.gridImageURL?.absoluteString, "https://x/full.jpg")

        let withThumb = try decode(#"{"id":"a","src":"https://x/full.jpg","thumbSrc":"https://x/t.webp"}"#)
        XCTAssertEqual(withThumb.gridImageURL?.absoluteString, "https://x/t.webp")
    }
}
