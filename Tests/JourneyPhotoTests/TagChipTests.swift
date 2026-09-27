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

    /// **読点・全角カンマで区切っても打ちかけと見る。** `parse` は `、` `，` でも
    /// 切るのに、打ちかけの判定が `,` だけを見ていたので `森、sn` は
    /// 欄全体が1つの欠片になり、候補が消え、チップを押すと `森` まで消えた。
    func testFragmentHonoursTheSameSeparatorsAsParse() {
        XCTAssertEqual(TagInput.typingFragment(TagChoices.all, current: "森、sn"), "sn")
        XCTAssertEqual(TagInput.suggest(TagChoices.all, current: "森，sn"), ["雪"])
        let after = TagInput.toggle(
            TagInput.dropFragment(TagChoices.all, current: "森、sn"), tag: "雪")
        XCTAssertEqual(TagInput.parse(after), ["森", "雪"])
        XCTAssertTrue(TagInput.has("森、雪", tag: "雪"))
    }

    /// **区切り（`,` `，` `、` `､`）は打ち終わりの合図。空白は違う**
    /// （Web の `TAG_SEPARATOR`。空白で切ると `New York` が割れる）。
    /// 区切りのあとは候補が全部戻り、チップを押しても打ち終えたタグは消えない
    func testTrailingSeparatorFinishesTheTag() {
        XCTAssertEqual(TagInput.suggest(TagChoices.all, current: "helsinki, "), TagChoices.all)
        XCTAssertEqual(TagInput.suggest(TagChoices.all, current: "京都、"), TagChoices.all)
        XCTAssertEqual(TagInput.parse(TagInput.toggle(
            TagInput.dropFragment(TagChoices.all, current: "sun, "), tag: "夕焼け")), ["sun", "夕焼け"])
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

/// 写真の詳細のタグの札の字（板 02 の「#夕焼け」）。
///
/// 以前は `tag.hasPrefix("#") ? tag : "#" + tag` で、全角の `＃` を付けて
/// 保存したタグが `#＃旅` と二重になり、`##旅` もそのまま出ていた。
final class TagChipTextTests: XCTestCase {

    func testPlainTagGetsOneHash() {
        XCTAssertEqual(TagInput.chipText("夕焼け"), "#夕焼け")
        XCTAssertEqual(TagInput.chipText("sunset"), "#sunset")
    }

    func testExistingHashIsNotDoubled() {
        XCTAssertEqual(TagInput.chipText("#夕焼け"), "#夕焼け")
        XCTAssertEqual(TagInput.chipText("##旅"), "#旅")
    }

    /// **全角の `＃` は二重にしないが、半角には畳まない。** `＃旅` と `旅` は絞り込み
    /// （`TagChoices.key`・Web の `tagKey`）では別のページなので、札も見分けがつくように
    func testFullWidthHashIsNotDoubledButKeptDistinct() {
        XCTAssertEqual(TagInput.chipText("＃旅"), "＃旅")
        XCTAssertEqual(TagInput.chipText("#＃ 海"), "＃海")
        XCTAssertNotEqual(TagInput.chipText("＃旅"), TagInput.chipText("旅"),
                          "絞り込みでは別のページなのに、札が同じ字になっている")
        XCTAssertNotEqual(TagChoices.key("＃旅"), TagChoices.key("旅"), "前提: 鍵は別")
    }

    /// `#` しか無いタグは元の字のまま（`#` だけの札・空の札を作らない）
    func testHashOnlyTagIsKept() {
        XCTAssertEqual(TagInput.chipText("#"), "#")
        XCTAssertEqual(TagInput.chipText("＃"), "＃")
    }

    /// 途中の `#` は落とさない（先頭だけ）
    func testInnerHashIsKept() {
        XCTAssertEqual(TagInput.chipText("c#"), "#c#")
    }

    /// **同じ字に見える札は1枚**（`旅`・`#旅`・`# 旅` が「#旅」で並んでいた）
    func testChipsLookingTheSameAreShownOnce() {
        XCTAssertEqual(TagInput.uniqueChips(["旅", "#旅", "# 旅", "海"]), ["旅", "海"])
        XCTAssertEqual(TagInput.uniqueChips(["Paris", "paris"]), ["Paris"], "大文字小文字だけ違う札が並ぶ")
    }

    /// **字が同じでも、開くページが違う札は残す**（`# #旅` の鍵は `#旅`、`＃ 旅` の鍵は `＃ 旅`）
    func testChipsOpeningDifferentPagesAreKept() {
        XCTAssertEqual(TagChoices.key("# #旅"), "#旅", "前提: 鍵は先頭の # を1つだけ落とす")
        XCTAssertEqual(TagInput.uniqueChips(["旅", "# #旅"]), ["旅", "# #旅"])
        XCTAssertEqual(TagInput.uniqueChips(["＃旅", "＃ 旅"]), ["＃旅", "＃ 旅"])
    }
}
