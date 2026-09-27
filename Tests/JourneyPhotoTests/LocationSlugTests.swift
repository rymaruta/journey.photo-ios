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

    /// 🔴 **Web とずれていた3つ**（2026-09-27・Web の `slugify` を node で実際に動かした値）。
    /// 「行きたい場所」をサーバーに繋いだので、ずれるとアプリで入れた場所が
    /// Web の一覧で**別の行**になる（開けない `/location/<スラッグ>` を指す）
    ///
    ///  - BOM（`U+FEFF`）… JS の `trim` と `\s` は空白に数えるが、ICU の `\s` と
    ///    `.whitespacesAndNewlines` は数えない
    ///  - 語末のシグマ … JS の `toLowerCase` は `ς` にするが、Swift の `lowercased` は `σ`
    ///  - 200 バイトの切り詰め … Web はコードポイントで切るが、以前は書記素のまとまりで切っていた
    ///    （結合文字・ZWJ の絵文字が境目にあると Web は途中まで入れる）
    func testMatchesTheWebWhereItUsedToDrift() {
        let a196 = String(repeating: "a", count: 196)
        let a199 = String(repeating: "a", count: 199)
        let cases: [(String, String)] = [
            ("\u{FEFF}パリ\u{FEFF}", "パリ"),
            ("a\u{FEFF}b", "a-b"),
            ("ΟΔΟΣ", "οδος"),
            ("ΣΑΣ ΣΟΣ", "σας-σος"),
            (a196 + "👨\u{200D}👩\u{200D}👧", a196 + "👨"),
            (a199 + "e\u{0301}x", a199 + "e"),
            // Web と同じく残す側（ずれていないことの見張り）
            ("a\u{200B}b", "a\u{200B}b"),
            ("\u{3000}東京\u{3000}", "東京"),
            ("a\u{00A0}b", "a-b"),
            ("a\u{2028}b", "a-b"),
            ("a\u{0085}b", "a-b"),
            ("İstanbul", "i\u{0307}stanbul"),
            (String(repeating: "あ", count: 66) + "-い", String(repeating: "あ", count: 66)),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(LocationSlug.make(input), expected, "「\(input.debugDescription)」でずれた")
        }
    }

    func testEmptyAndNil() {
        XCTAssertEqual(LocationSlug.make(nil), "")
        XCTAssertEqual(LocationSlug.make(""), "")
        XCTAssertEqual(LocationSlug.make("   "), "")
        XCTAssertEqual(LocationSlug.make("---"), "")
    }
}
