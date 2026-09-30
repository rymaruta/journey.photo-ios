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

    // MARK: - 名前として含むときだけ（2026-09-30・Web の `locationScope.test.ts` と同じ事例）

    private let zao = "蔵王キツネ村, 南蔵王七ヶ宿線, 福岡八宮, 白石市, 宮城県, 989-0733, 日本"

    /// 🔴 宮城県白石市の大字「福岡八宮」の中の「福岡」で、福岡の撮影地に載っていた
    func testZaoFoxVillageIsNotInFukuoka() {
        XCTAssertFalse(LocationMatch.photoIsIn(zao, "福岡"))
        XCTAssertFalse(LocationMatch.same(zao, "福岡"))
        XCTAssertTrue(LocationMatch.photoIsIn(zao, "宮城県"))
        XCTAssertTrue(LocationMatch.photoIsIn(zao, "白石市"))
        XCTAssertTrue(LocationMatch.photoIsIn(zao, "蔵王キツネ村"))
    }

    /// 行政区分の字（都道府県市区町村郡）の前後は名前の切れ目
    func testAdministrativeSuffixesAreBoundaries() {
        XCTAssertTrue(LocationMatch.photoIsIn("東京都 渋谷区", "東京"))
        XCTAssertTrue(LocationMatch.photoIsIn("兵庫県神戸市", "神戸"))
        XCTAssertTrue(LocationMatch.photoIsIn("兵庫県神戸市", "兵庫県"))
        XCTAssertTrue(LocationMatch.photoIsIn("福岡県福岡市", "福岡"))
        XCTAssertTrue(LocationMatch.photoIsIn("宮崎県西臼杵郡", "宮崎県"))
        XCTAssertTrue(LocationMatch.photoIsIn("北海道札幌市", "札幌"))
        XCTAssertTrue(LocationMatch.photoIsIn("西臼杵郡高千穂町", "高千穂"))
    }

    /// 名前の途中に当たるだけのものは含まない
    func testSubstringInsideANameIsNotAMatch() {
        XCTAssertFalse(LocationMatch.photoIsIn("東京都", "京都"))
        XCTAssertFalse(LocationMatch.photoIsIn("大阪城公園", "大阪"))
    }

    /// 括弧と複数語の見出し。**語は同じ順で続けて**並んでいること
    func testBracketsAndMultiWordLabels() {
        XCTAssertTrue(LocationMatch.photoIsIn("オペラ・ガルニエ（パリ）", "パリ"))
        XCTAssertTrue(LocationMatch.photoIsIn("オペラ座, パリ, フランス", "パリ, フランス"))
        XCTAssertFalse(LocationMatch.photoIsIn("パリ, ドイツ, フランス", "パリ, フランス"))
    }

    /// 英字は大文字小文字を見ない・読点（「、」「，」）も区切り
    func testCaseAndJapaneseCommas() {
        XCTAssertTrue(LocationMatch.photoIsIn("Paris, France", "paris"))
        XCTAssertTrue(LocationMatch.photoIsIn("オペラ座、パリ", "パリ"))
        XCTAssertTrue(LocationMatch.photoIsIn("オペラ座，パリ", "パリ"))
    }

    /// 最初に当たった位置が名前の途中でも、**後ろで名前として当たれば**含む
    func testLaterOccurrenceCounts() {
        XCTAssertTrue(LocationMatch.photoIsIn("福岡八宮町福岡", "福岡"))
        XCTAssertFalse(LocationMatch.photoIsIn("福岡八宮福岡市", "福岡"))
    }

    /// 空白の有無で語の割れ方が変わる同じ名前は同じ
    func testSpacingVariantsOfOneNameMatch() {
        XCTAssertTrue(LocationMatch.photoIsIn("東京渋谷", "東京 渋谷"))
        XCTAssertTrue(LocationMatch.photoIsIn("東京 渋谷", "東京渋谷"))
    }
}
