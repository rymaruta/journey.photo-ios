import XCTest
@testable import JourneyPhoto

/// 英語の単複(2026-11-07)。件数 1 で「1 medals」と出ない。日本語は変えない
final class PluralTests: XCTestCase {

    func testCountOneAndMany() {
        XCTAssertEqual(Plural.count(1, "medal"), "1 medal")
        XCTAssertEqual(Plural.count(0, "medal"), "0 medals")
        XCTAssertEqual(Plural.count(2, "medal"), "2 medals")
        XCTAssertEqual(Plural.count(1, "person", "people"), "1 person")
        XCTAssertEqual(Plural.count(5, "person", "people"), "5 people")
        XCTAssertEqual(Plural.word(1, " card", " cards"), " card")
        XCTAssertEqual(Plural.word(3, " card", " cards"), " cards")
    }

    /// 画面の英語の文が、数を直に「N medals」の形で書かず `Plural` を通すこと(戻すと落ちる)。
    /// 言語は端末で決まる(試験は日本語側を通る)ので、書いてある形を見る
    func testEnglishCountsGoThroughPlural() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let files = [
            "Core/Text/TrunkInside.swift", "Core/Text/TrunkText.swift", "Features/Trunk/TrunkView.swift",
            "Features/Trunk/TrunkPartsBoxView.swift", "Features/Trunk/TrunkSpinViewer.swift", "Core/Text/PassBook.swift",
            "Features/Pass/PassHomeSlot.swift", "Core/Push/PassBundleNotifier.swift", "Core/Camper/CamperCatalog.swift",
            "Core/Text/TripPicker.swift",
        ]
        let bad = [#"\) (medals|tickets|labels|coins|people|cards|trips|days|night photos|posts)[ ".]"#]
        var hits: [String] = []
        for file in files {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for (i, line) in text.components(separatedBy: "\n").enumerated()
            where line.contains("L(\"") && line.range(of: bad[0], options: .regularExpression) != nil
                && !line.contains("Plural.") {
                hits.append("\(file):\(i + 1)")
            }
        }
        XCTAssertEqual(hits, [], "英語の件数が単複を分けていない")
    }
}
