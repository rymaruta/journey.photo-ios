import XCTest
@testable import JourneyPhoto

/// 撮影地の突き合わせ。**Web と同じ向き**（`lib/utils/related.ts`）。
final class LocationMatchTests: XCTestCase {

    /// **狭い写真は広いページに載る。** 逆は載らない
    func testDirectionMatters() {
        XCTAssertTrue(LocationMatch.photoIsIn("ヘルシンキ, フィンランド", "フィンランド"))
        XCTAssertFalse(LocationMatch.photoIsIn("フィンランド", "ヘルシンキ, フィンランド"))
    }

    /// 🔴 run 55 の実機の絵に出ていた形そのもの
    func testFranceIsNotInVersailles() {
        XCTAssertFalse(LocationMatch.photoIsIn("フランス", "フランス ヴェルサイユ"))
        XCTAssertTrue(LocationMatch.photoIsIn("フランス ヴェルサイユ", "フランス"))
    }

    /// **空白は見ない**（Web の `normalizeLocation` と同じ）
    func testSpacesAreIgnored() {
        XCTAssertTrue(LocationMatch.photoIsIn("フランス  ヴェルサイユ", "フランスヴェルサイユ"))
        XCTAssertEqual(LocationMatch.normalized("  Paris, France "), "paris,france")
    }

    /// 1文字は通さない（欠片が全部の地名に当たる）
    func testSingleCharacterIsNotAMatch() {
        XCTAssertFalse(LocationMatch.photoIsIn("東京都", "都"))
        XCTAssertFalse(LocationMatch.photoIsIn("都", "東京都"))
    }

    /// 空は通さない
    func testEmptyIsNeverAMatch() {
        XCTAssertFalse(LocationMatch.photoIsIn(nil, "パリ"))
        XCTAssertFalse(LocationMatch.photoIsIn("パリ", nil))
        XCTAssertFalse(LocationMatch.photoIsIn("", ""))
    }

    /// **回遊用は向きを見ない**（Web の `sameLocation` と同じ住み分け）
    func testSameIsSymmetric() {
        XCTAssertTrue(LocationMatch.same("フランス", "フランス ヴェルサイユ"))
        XCTAssertTrue(LocationMatch.same("フランス ヴェルサイユ", "フランス"))
        XCTAssertFalse(LocationMatch.same("パリ", "東京"))
    }
}
