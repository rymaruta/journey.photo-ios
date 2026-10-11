import XCTest
@testable import JourneyPhoto

/// 画面に出す撮影地（`LocationMatch.display`・2026-10-11）。
/// 保存された撮影地は場所の検索の住所そのまま（郵便番号・通り・国まで）なので、出すときだけ縮める
final class LocationDisplayTests: XCTestCase {

    /// 画面写真 20 に出ていた実物。名前＋県＋市、郵便番号・通り・大字・国は落とす
    func testJapaneseGeocodedAddress() {
        XCTAssertEqual(LocationMatch.display("蔵王キツネ村, 南蔵王七ヶ宿線, 福岡八宮, 白石市, 宮城県, 989-0733, 日本"),
                       "蔵王キツネ村（宮城県白石市）")
    }

    /// 東京の区・政令市（区ではなく市を出す）・郡は飛ばして村
    func testJapaneseWardCityAndDistrict() {
        XCTAssertEqual(LocationMatch.display("東京タワー, 4, 芝公園4丁目, 芝公園, 港区, 東京都, 105-0011, 日本"),
                       "東京タワー（東京都港区）")
        XCTAssertEqual(LocationMatch.display("清水寺, 清水, 東山区, 京都市, 京都府, 605-0862, 日本"),
                       "清水寺（京都府京都市）")
        XCTAssertEqual(LocationMatch.display("白川郷, 荻町, 白川村, 大野郡, 岐阜県, 501-5627, 日本"),
                       "白川郷（岐阜県白川村）")
    }

    /// 名前が市や県そのものなら二度出さない
    func testJapaneseNameIsTheMunicipality() {
        XCTAssertEqual(LocationMatch.display("白石市, 宮城県, 989-0733, 日本"), "白石市（宮城県）")
        XCTAssertEqual(LocationMatch.display("宮城県, 日本"), "宮城県")
        XCTAssertEqual(LocationMatch.display("富士山, 日本"), "富士山")
    }

    /// 英語で引いた日本の住所
    func testJapanInEnglish() {
        XCTAssertEqual(LocationMatch.display("Zao Fox Village, Minamizao Shichikashuku Line, Fukuoka Hachimiya, Shiroishi, Miyagi Prefecture, 989-0733, Japan"),
                       "Zao Fox Village (Shiroishi, Miyagi)")
        XCTAssertEqual(LocationMatch.display("Tokyo Tower, 4, Shibakoen 4-chome, Shibakoen, Minato, Tokyo, 105-0011, Japan"),
                       "Tokyo Tower (Minato, Tokyo)")
    }

    /// 海外: 名前・街・国の3つなら街も、長い住所は名前と国（州や通りを街として出さない）
    func testForeign() {
        XCTAssertEqual(LocationMatch.display("Louvre, Paris, France"), "Louvre (Paris, France)")
        XCTAssertEqual(LocationMatch.display("ルーブル美術館, パリ, フランス"), "ルーブル美術館（パリ、フランス）")
        XCTAssertEqual(LocationMatch.display("Eiffel Tower, 5, Avenue Anatole France, Quartier du Gros-Caillou, Paris, Île-de-France, Metropolitan France, 75007, France"),
                       "Eiffel Tower (France)")
        XCTAssertEqual(LocationMatch.display("エッフェル塔, 5, アナトール・フランス通り, グロ・カイユ地区, パリ, イル＝ド＝フランス, フランス本土, 75007, フランス"),
                       "エッフェル塔（フランス）")
    }

    /// 既に短い・人が打った地名は触らない
    func testShortStaysAsTyped() {
        XCTAssertEqual(LocationMatch.display("金沢"), "金沢")
        XCTAssertEqual(LocationMatch.display(" 鍋ヶ滝 "), "鍋ヶ滝")
        XCTAssertEqual(LocationMatch.display("パリ, フランス"), "パリ, フランス")
        XCTAssertEqual(LocationMatch.display("金沢、石川"), "金沢、石川")
        XCTAssertEqual(LocationMatch.display(nil), "")
        XCTAssertEqual(LocationMatch.display("  "), "")
    }

    /// 突き合わせは元の文字のまま（縮めた名前で別の場所に当てない）
    func testMatchingStillUsesRawText() {
        let raw = "蔵王キツネ村, 南蔵王七ヶ宿線, 福岡八宮, 白石市, 宮城県, 989-0733, 日本"
        XCTAssertTrue(LocationMatch.photoIsIn(raw, "宮城県"))
        XCTAssertFalse(LocationMatch.photoIsIn(raw, "福岡"))
        // 行き先の題（撮影地の写真の一覧）は縮めた名前
        XCTAssertEqual(PhotoQuery.Collection.location(raw).title, "蔵王キツネ村（宮城県白石市）")
    }
}
