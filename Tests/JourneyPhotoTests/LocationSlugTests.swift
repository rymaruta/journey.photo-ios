import XCTest
@testable import JourneyPhoto

/// 撮影地のスラッグが、Web の `slugify(_, "location")` と同じ値になるか。
///
/// 🔴 **この表は Web の実装を実際に動かして作った**
/// （`lib/utils/collections.ts` の `slugify` に、実データの撮影地14種と
/// 端の値を通した結果）。**推測で書いていない。**
///
/// ずれると、アプリで入れた「行きたい」がサーバーの一覧
/// （`spots#<uid>` に入るのはこの文字列）に**別の行として並ぶ**。
final class LocationSlugTests: XCTestCase {

    /// 実データの撮影地（`app/data/photos.json` の14種）
    private let real: [String: String] = [
        "山中湖": "山中湖",
        "バルセロナ": "バルセロナ",
        "パリ": "パリ",
        "大阪": "大阪",
        "東京": "東京",
        "フィンランド": "フィンランド",
        "福岡": "福岡",
        "フランス": "フランス",
        "フランス ヴェルサイユ": "フランス-ヴェルサイユ",
        "パリ, フランス": "パリ,-フランス",
        "北海道": "北海道",
        "オペラ・ガルニエ（パリ）": "オペラ・ガルニエ（パリ）",
        "香川県 観音寺市 高屋神社": "香川県-観音寺市-高屋神社",
        "茨城県 ひたちなか市 国営ひたち海浜公園": "茨城県-ひたちなか市-国営ひたち海浜公園",
    ]

    /// 端の値（パスに置けない文字・空白・大文字・全角）
    private let edges: [String: String] = [
        "東京 / 渋谷": "東京-渋谷",
        "白/黒": "白-黒",
        "  前後に空白  ": "前後に空白",
        "A?B#C%D": "a-b-c-d",
        "…": "…",
        "..": "",
        "Ｆｕｌｌ Ｗｉｄｔｈ": "ｆｕｌｌ-ｗｉｄｔｈ",
        "MiXeD Case": "mixed-case",
    ]

    func testMatchesTheWebOnRealData() {
        for (input, expected) in real {
            XCTAssertEqual(LocationSlug.make(input), expected, "「\(input)」でずれた")
        }
    }

    func testMatchesTheWebOnEdgeCases() {
        for (input, expected) in edges {
            XCTAssertEqual(LocationSlug.make(input), expected, "「\(input)」でずれた")
        }
    }

    /// **パスに置けない文字を残さない**（残すと開けないリンクになる）
    func testNeverKeepsPathBreakingCharacters() {
        for input in ["a/b", "a\\b", "a?b", "a#b", "a%b", "a\u{0000}b"] {
            let slug = LocationSlug.make(input)
            for bad in ["/", "\\", "?", "#", "%", "\u{0000}"] {
                XCTAssertFalse(slug.contains(bad), "「\(input)」に \(bad) が残った")
            }
        }
    }

    /// **バイトで切る**（文字数で切ると日本語が3倍通る）。
    /// 切った先が文字の途中にならないこと
    func testClampsByBytesWithoutBreakingCharacters() {
        let long = String(repeating: "あ", count: 200)   // 600バイト
        let slug = LocationSlug.make(long)
        XCTAssertLessThanOrEqual(slug.utf8.count, LocationSlug.maxBytes)
        XCTAssertEqual(slug, String(repeating: "あ", count: LocationSlug.maxBytes / 3))
    }

    func testEmptyAndNil() {
        XCTAssertEqual(LocationSlug.make(nil), "")
        XCTAssertEqual(LocationSlug.make(""), "")
        XCTAssertEqual(LocationSlug.make("   "), "")
        XCTAssertEqual(LocationSlug.make("---"), "")
    }
}
