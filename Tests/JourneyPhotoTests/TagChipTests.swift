import XCTest
@testable import JourneyPhoto

/// タグの候補チップ。**Web 側（`lib/utils/ownValues.ts`）と同じ答えを出すこと。**
///
/// Web はここで4回踏んでいる（押しても外れない／押した直後に打つと繋がる／
/// 打ちかけの欠片がタグとして保存される／英語で保存済みのチップが光らない）。
/// 同じ穴をアプリで踏み直さないために、答えを固定する。
final class TagChipTests: XCTestCase {

    func testChoicesMatchTheWeb() {
        XCTAssertEqual(TagChoices.all.count, 20)
        XCTAssertEqual(TagChoices.all.first, "春")
        XCTAssertEqual(TagChoices.all.last, "公園")
    }

    /// **英語で保存済みの写真でもチップが光る**（実データで `winter` 12枚）。
    func testStoredEnglishTagLightsUpTheJapaneseChip() {
        XCTAssertTrue(TagInput.has("winter, hokkaido", tag: "冬"))
        XCTAssertTrue(TagInput.has("#Sunset", tag: "夕焼け"))
        XCTAssertFalse(TagInput.has("winter", tag: "夏"))
    }

    /// **押し直すと外れる。** 足すだけだと、付いているタグのチップは無反応。
    func testChipTogglesOff() {
        XCTAssertEqual(TagInput.toggle("", tag: "桜"), "桜, ")
        XCTAssertEqual(TagInput.toggle("桜, ", tag: "桜"), "")
        // 別の綴りで入っていても「同じものを押した」と分かる
        XCTAssertEqual(TagInput.toggle("cherry, ", tag: "桜"), "")
    }

    /// **末尾に区切りを残す。** 残さないと、押した直後に打つと前のタグに繋がる
    /// （`桜` を押して `京都` と打つと `"桜京都"` という1つの嘘のタグ）。
    func testTrailingSeparatorIsKept() {
        XCTAssertTrue(TagInput.toggle("", tag: "桜").hasSuffix(", "))
    }

    /// 同じタグが2つ並ばない（`fuji` の欄に `Fuji` を押す）。
    func testSameTagIsNotAddedTwice() {
        XCTAssertEqual(TagInput.append("fuji, ", tag: "Fuji"), "fuji, ")
    }

    /// **打ちかけの文字で候補が絞れる。**
    func testTypingFiltersTheChips() {
        XCTAssertEqual(TagInput.suggest(TagChoices.all, current: ""), TagChoices.all)
        XCTAssertEqual(TagInput.suggest(TagChoices.all, current: "さ"), [])
        XCTAssertEqual(TagInput.suggest(TagChoices.all, current: "sn"), ["雪"])
    }

    /// **打ち終わったら絞りを解く。** 解かないと、1つ選んだ瞬間に他が消える。
    func testAChosenTagIsNotTreatedAsAFragment() {
        XCTAssertEqual(TagInput.typingFragment(TagChoices.all, current: "桜"), "")
        XCTAssertEqual(TagInput.suggest(TagChoices.all, current: "桜, "), TagChoices.all)
    }

    /// **チップを押すときは打ちかけの欠片を落とす。**
    /// 落とさないと `sn` と打って `雪` を押したときに `"sn, 雪"` になり、
    /// **`sn` が写真のタグとして保存される**（絞りの目的と逆）。
    func testFragmentIsDroppedWhenAChipIsTapped() {
        let after = TagInput.toggle(
            TagInput.dropFragment(TagChoices.all, current: "森, sn"), tag: "雪")
        XCTAssertEqual(after, "森, 雪, ")
    }
}

/// プロフィールの色。**保存の形は `#rrggbb` に限る**——Web の
/// `themeRingGradient` は他の形を無視するので、別の形で保存すると
/// アプリでだけ色が付く（見え方が割れる）。
final class ThemeColorTests: XCTestCase {

    func testPresetsMatchTheWeb() {
        XCTAssertEqual(ThemeColor.presets.count, 8)
        XCTAssertEqual(ThemeColor.presets.first, "#38bdf8")
    }

    func testOnlySixDigitHexIsAccepted() {
        XCTAssertTrue(ThemeColor.isValid("#38bdf8"))
        XCTAssertTrue(ThemeColor.isValid("#FFFFFF"))
        XCTAssertFalse(ThemeColor.isValid("#fff"), "3桁は Web 側が無視する")
        XCTAssertFalse(ThemeColor.isValid("38bdf8"), "# が要る")
        XCTAssertFalse(ThemeColor.isValid("red"))
        XCTAssertFalse(ThemeColor.isValid(""))
        XCTAssertFalse(ThemeColor.isValid("#gggggg"))
    }

    func testChannelsAreReadInRgbOrder() throws {
        let rgb = try XCTUnwrap(ThemeColor.rgb("#ff8000"))
        XCTAssertEqual(rgb.red, 1, accuracy: 0.001)
        XCTAssertEqual(rgb.green, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(rgb.blue, 0, accuracy: 0.001)
    }
}
