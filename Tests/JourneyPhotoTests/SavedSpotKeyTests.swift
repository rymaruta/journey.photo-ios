import XCTest
@testable import JourneyPhoto

/// 「行きたい」の鍵の形。**Web の `lib/utils/savedSpotKey.ts` と同じ約束**:
///
///   - 撮影スポットは `SPOT-<slug>`、撮影地の集まりは今までどおりスラッグそのまま
///   - 接頭辞は `slugify`（小文字にする）の出力に現れない＝撮影地の名前が
///     偶然この形になることは無い
///   - 記号を含まないので URL のパス片にそのまま置ける・`#` を含まない
///   - 知らない形は「撮影地」に倒す（既存の保存を消したように見せない）
final class SavedSpotKeyTests: XCTestCase {

    func testOfficialKeyHasThePrefix() {
        XCTAssertEqual(SavedSpotKey.official("takaya-jinja"), "SPOT-takaya-jinja")
        XCTAssertEqual(SavedSpotKey.officialPrefix, "SPOT-")
        XCTAssertTrue(SavedSpotKey.isOfficial("SPOT-takaya-jinja"))
    }

    /// 二重に付けない（既に鍵の形になっているものを渡されても）
    func testDoesNotDoubleThePrefix() {
        XCTAssertEqual(SavedSpotKey.official("SPOT-takaya-jinja"), "SPOT-takaya-jinja")
        XCTAssertEqual(SavedSpotKey.official("  takaya-jinja  "), "SPOT-takaya-jinja")
    }

    /// **これまでの保存は頭が無い＝撮影地。** 読み方を変えない
    func testLocationSlugsAreNotOfficial() {
        for raw in ["paris", "パリ", "yamanakako", "フランス-ヴェルサイユ", "spot-takaya", "Spot-Takaya", "ＳＰＯＴ-x", ""] {
            XCTAssertFalse(SavedSpotKey.isOfficial(raw), "\(raw) を公式の鍵と読んでいる")
            XCTAssertNil(SavedSpotKey.slug(fromOfficial: raw))
        }
    }

    /// 撮影地のスラッグ（`LocationSlug.make`＝Web の `slugify`）は小文字になるので、
    /// **原理的に接頭辞の形にならない**。思い込みではなく実際に通す
    func testLocationSlugNeverLooksLikeThePrefix() {
        for raw in ["SPOT-takaya", "Spot-Takaya", "SPOT/takaya", "SPOT ABC", "SPOT-", "東京 / 渋谷", "パリ", "#旅"] {
            let slug = LocationSlug.make(raw)
            XCTAssertFalse(SavedSpotKey.isOfficial(slug), "\(raw) → \(slug) が接頭辞の形になっている")
        }
        // 自己確認: 小文字にした同じ形なら見張りは効かない（空回りしていない）
        XCTAssertTrue(LocationSlug.make("SPOT-takaya").hasPrefix("spot-"))
    }

    func testSlugComesBackOut() {
        XCTAssertEqual(SavedSpotKey.slug(fromOfficial: "SPOT-takaya-jinja"), "takaya-jinja")
        XCTAssertEqual(SavedSpotKey.slug(fromOfficial: " SPOT-takaya-jinja "), "takaya-jinja")
        XCTAssertEqual(SavedSpotKey.slug(fromOfficial: "SPOT-"), "", "壊れた鍵も落とさない（本人が外せる道を残す）")
    }

    /// 接頭辞は URL のパスにそのまま置けて（記号なし）、サーバーの受け付ける形（`#` なし）に収まる
    func testPrefixIsPathSafeAndServerSafe() {
        let key = SavedSpotKey.official("takaya-jinja")
        XCTAssertEqual(SavedSpotKey.officialPrefix.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                       SavedSpotKey.officialPrefix)
        XCTAssertFalse(key.contains("#"))
        XCTAssertFalse(key.isEmpty)
    }
}
