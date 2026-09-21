import XCTest
@testable import JourneyPhoto

/// 一覧のリズム。**写真を1枚も落とさず、順番も変えない**のが最低条件。
final class EditorialLayoutTests: XCTestCase {

    private func photos(_ count: Int) throws -> [Photo] {
        try (0..<count).map { i in
            let json = #"{"id":"p\#(i)","src":"https://x/\#(i).jpg"}"#
            return try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
        }
    }

    private func ids(_ rows: [EditorialLayout.Row]) -> [String] {
        rows.flatMap { row -> [String] in
            switch row {
            case .hero(let p): return [p.id]
            case .pair(let a, let b): return [a.id, b?.id].compactMap { $0 }
            }
        }
    }

    /// **1枚も落とさない。** 組み方を変えるときに真っ先に壊れるところ
    func testKeepsEveryPhotoInOrder() throws {
        let input = try photos(13)
        XCTAssertEqual(ids(EditorialLayout.rows(input)), input.map(\.id))
    }

    /// 先頭は必ず大きい1枚
    func testStartsWithHero() throws {
        guard case .hero(let first)? = EditorialLayout.rows(try photos(5)).first else {
            return XCTFail("先頭が大きい1枚になっていない")
        }
        XCTAssertEqual(first.id, "p0")
    }

    /// 5枚でひと回り（大きい1枚 → 2枚 → 2枚 → 次の大きい1枚）
    func testRhythmRepeatsEveryFivePhotos() throws {
        let rows = EditorialLayout.rows(try photos(10))
        XCTAssertEqual(rows.count, 6)
        guard case .hero = rows[0], case .pair = rows[1], case .pair = rows[2],
              case .hero = rows[3], case .pair = rows[4], case .pair = rows[5] else {
            return XCTFail("リズムが 大・2枚・2枚 の繰り返しになっていない")
        }
    }

    /// **端数で崩さない。** 残り1枚の段は、その1枚で横いっぱい
    func testOddTailKeepsOnePhotoWide() throws {
        let rows = EditorialLayout.rows(try photos(4))
        guard case .pair(let a, let b) = rows.last else { return XCTFail("最後が2枚の段でない") }
        XCTAssertEqual(a.id, "p3")
        XCTAssertNil(b, "相方が無い段は1枚で横いっぱいにする")
    }

    func testEmptyStaysEmpty() {
        XCTAssertTrue(EditorialLayout.rows([]).isEmpty)
    }

    /// 1枚だけなら大きい1枚
    func testSinglePhotoIsHero() throws {
        guard case .hero? = EditorialLayout.rows(try photos(1)).first else {
            return XCTFail("1枚のときに大きい段になっていない")
        }
    }
}
