import XCTest
@testable import JourneyPhoto

/// カテゴリの選択肢。**Web 側（`lib/utils/categoryChoices.ts`）と同じ答えになること**
/// を縛る。ずれると、同じ主題が `/category/建築` と `/category/architecture` に
/// 割れて、どちらも3枚に届かず両方 noindex になる。
final class CategoryChoicesTests: XCTestCase {

    func testChoicesMatchTheWeb() {
        XCTAssertEqual(CategoryChoices.all, ["風景", "建築", "自然", "街", "人物", "動物", "食べ物"])
    }

    /// **既に英語で保存されている写真でもチップが光る。**
    /// 綴りで比べると、英語で保存された写真を開いたときに選択が外れて見え、
    /// 押し直すと日本語で保存し直されて割れ方が増える。
    func testStoredEnglishValueLightsUpTheJapaneseChip() {
        XCTAssertTrue(CategoryChoices.isChosen(current: "architecture", choice: "建築"))
        XCTAssertTrue(CategoryChoices.isChosen(current: "Landscape", choice: "風景"))
        XCTAssertTrue(CategoryChoices.isChosen(current: "  food  ", choice: "食べ物"))
    }

    /// 同じ主題の別綴り（Web の `CATEGORY_ALIASES` と同じ畳み方）。
    func testAliasesFoldTogether() {
        XCTAssertTrue(CategoryChoices.isChosen(current: "建物", choice: "建築"))
        XCTAssertTrue(CategoryChoices.isChosen(current: "ご飯", choice: "食べ物"))
        XCTAssertFalse(CategoryChoices.isChosen(current: "動物", choice: "人物"))
    }

    func testEmptyIsNeverChosen() {
        XCTAssertFalse(CategoryChoices.isChosen(current: "", choice: "風景"))
        XCTAssertFalse(CategoryChoices.isChosen(current: "   ", choice: "風景"))
    }

    /// **押し直すと外れる。** 足すだけだと、一度選んだカテゴリを選び直せない。
    func testTogglingTheSameChoiceClearsIt() {
        XCTAssertEqual(CategoryChoices.toggle(current: "", choice: "風景"), "風景")
        XCTAssertEqual(CategoryChoices.toggle(current: "風景", choice: "風景"), "")
        // 別綴りで保存されていても「同じものを押した」と分かる
        XCTAssertEqual(CategoryChoices.toggle(current: "landscape", choice: "風景"), "")
        XCTAssertEqual(CategoryChoices.toggle(current: "風景", choice: "動物"), "動物")
    }
}
