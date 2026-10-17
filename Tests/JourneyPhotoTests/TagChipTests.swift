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

    // MARK: パレットから自由に選ぶ（2026-10-16）

    /// 🔴 **0〜1 の値は 255 段に丸める**（切り捨てない）。0.5 段の上下で割れる
    func testPickedColorIsRoundedTo255Steps() {
        XCTAssertEqual(ThemeColor.hex(red: 0.2, green: 0.5, blue: 1), "#3380ff")
        XCTAssertEqual(ThemeColor.hex(red: 127.6 / 255, green: 127.4 / 255, blue: 0.5 / 255), "#807f01")
        XCTAssertEqual(ThemeColor.hex(red: 0, green: 0, blue: 0), "#000000", "先頭の 0 を落とさない")
        XCTAssertEqual(ThemeColor.hex(red: 0, green: 0, blue: 1.0 / 255), "#000001")
    }

    /// 🔴 **保存は小文字。** 見本（小文字）との比べが割れない・Web の `toLowerCase()` と同じ
    func testPickedColorIsLowercase() {
        let hex = ThemeColor.hex(red: 0.98, green: 0.75, blue: 0.14)
        XCTAssertEqual(hex, hex.lowercased())
        XCTAssertEqual(ThemeColor.hex(0xABCDEF), "#abcdef")
        XCTAssertTrue(ThemeColor.isValid(hex))
    }

    /// 🔴 **Display P3 の色は拡張 sRGB で 0 未満・1 超えが来る。sRGB に詰めて保存の形に収める**
    /// （詰めないと 7 桁を超えたり負の桁になり、Web とサーバーが受け付けない）
    func testOutOfRangeChannelsAreClampedIntoSRGB() {
        XCTAssertEqual(ThemeColor.hex(red: 1.09, green: -0.23, blue: 0.5), "#ff0080")
        XCTAssertEqual(ThemeColor.hex(red: .infinity, green: .nan, blue: -.infinity), "#000000")
        XCTAssertEqual(ThemeColor.hex(0x1FFFFFF), "#ffffff", "上の桁は捨てる")
        for hex in [ThemeColor.hex(red: 2, green: 2, blue: 2), ThemeColor.hex(red: -1, green: -1, blue: -1)] {
            XCTAssertTrue(ThemeColor.isValid(hex), hex)
        }
    }

    /// 保存した色を読み直して変換し直すと同じ色（見本8色と、段ごとの色）
    func testHexRoundTrips() throws {
        var samples = ThemeColor.presets
        for v in stride(from: 0, through: 255, by: 17) {
            samples.append(ThemeColor.hex(UInt32(v) << 16 | UInt32(255 - v) << 8 | UInt32(v / 2)))
        }
        for hex in samples {
            let rgb = try XCTUnwrap(ThemeColor.rgb(hex))
            XCTAssertEqual(ThemeColor.hex(red: rgb.red, green: rgb.green, blue: rgb.blue), hex)
        }
        // 大文字で入っていた値も、往復すると小文字の同じ色
        let upper = try XCTUnwrap(ThemeColor.rgb("#A78BFA"))
        XCTAssertEqual(ThemeColor.hex(red: upper.red, green: upper.green, blue: upper.blue), "#a78bfa")
    }

    /// 🔴 **見本に無い色（Web で選んだ色も）は「自由に選ぶ」の丸が選ばれている。**
    /// 以前はどの丸にも印が付かず、何も選んでいないように見えた
    func testColorsOutsideThePresetsAreCustom() {
        XCTAssertTrue(ThemeColor.isCustom("#123456"))
        XCTAssertTrue(ThemeColor.isCustom("#ABCDEF"))
        XCTAssertFalse(ThemeColor.isCustom("#38bdf8"), "見本の色は見本の丸")
        XCTAssertFalse(ThemeColor.isCustom("#38BDF8"), "大文字でも見本の色")
        XCTAssertFalse(ThemeColor.isCustom(""), "なし")
        XCTAssertFalse(ThemeColor.isCustom("red"), "読めない値は塗らない")
        for preset in ThemeColor.presets { XCTAssertFalse(ThemeColor.isCustom(preset), preset) }
    }

    /// 🔴 **2026-10-16 判断: 黒い地で見えにくい色（3:1 未満）だけ知らせる。** 見本8色と「なし」には出さない
    func testOnlyColorsTooDarkForBlackAreFlagged() {
        XCTAssertTrue(ThemeColor.isHardToSeeOnBlack("#000000"))
        XCTAssertTrue(ThemeColor.isHardToSeeOnBlack("#202040"))
        XCTAssertTrue(ThemeColor.isHardToSeeOnBlack("#5A0000"))
        XCTAssertFalse(ThemeColor.isHardToSeeOnBlack("#C9A66B"), "真鍮は黒の上 9:1")
        XCTAssertFalse(ThemeColor.isHardToSeeOnBlack("#ffffff"))
        XCTAssertFalse(ThemeColor.isHardToSeeOnBlack(""))
        XCTAssertFalse(ThemeColor.isHardToSeeOnBlack("garbage"))
        for preset in ThemeColor.presets { XCTAssertFalse(ThemeColor.isHardToSeeOnBlack(preset), preset) }
    }

    /// 🔴 **色選びから同じ色が返ってきたら書かない**（開いて閉じただけで「編集した」にならない）。
    /// 大文字・小文字の違いだけも同じ色。違う色は小文字で書く
    func testPickerWritesOnlyADifferentColor() {
        XCTAssertNil(ThemeColor.nextValue(picked: "#38bdf8", current: "#38bdf8"), "同じ色")
        XCTAssertNil(ThemeColor.nextValue(picked: "#38bdf8", current: "#38BDF8"), "大文字の違いだけ")
        XCTAssertNil(ThemeColor.nextValue(picked: "#ABCDEF", current: "#abcdef"), "大文字の違いだけ（逆）")
        XCTAssertEqual(ThemeColor.nextValue(picked: "#123456", current: "#38bdf8"), "#123456", "違う色")
        XCTAssertEqual(ThemeColor.nextValue(picked: "#ABCDEF", current: ""), "#abcdef", "なしから・小文字で")
        XCTAssertNil(ThemeColor.nextValue(picked: "red", current: ""), "読めない値は書かない")
    }

    /// 暗い色の注意書きは**新しく出たときだけ**読み上げる（出たままの色替えでは繰り返さない）
    func testHardToSeeIsAnnouncedOnlyWhenItAppears() {
        XCTAssertTrue(ThemeColor.shouldAnnounceHardToSee(old: "#38bdf8", new: "#101010", picking: true))
        XCTAssertTrue(ThemeColor.shouldAnnounceHardToSee(old: "", new: "#000000", picking: true))
        XCTAssertFalse(ThemeColor.shouldAnnounceHardToSee(old: "#101010", new: "#000000", picking: true), "出たまま")
        XCTAssertFalse(ThemeColor.shouldAnnounceHardToSee(old: "#000000", new: "#38bdf8", picking: true), "消えた")
        XCTAssertFalse(ThemeColor.shouldAnnounceHardToSee(old: "", new: "#38bdf8", picking: true))
    }

    /// 🔴 **読み込み（色選びを開いていない）で暗い色が入っても読み上げない**
    func testHardToSeeIsNotAnnouncedWhileLoading() {
        XCTAssertFalse(ThemeColor.shouldAnnounceHardToSee(old: "", new: "#000000", picking: false))
    }
}

/// プロフィールの色の欄の書き方の見張り（画面は Linux で動かせないので、字で守る）
final class ThemeColorFieldSourceTests: XCTestCase {

    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Common/ThemeColorField.swift"), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 🔴 **2026-10-16 判断: 選んでいる印は真鍮で、既にある `WebTheme` の定数を使う**。
    /// 輪を `.primary`（白）に戻す・「なし」を白の塗りに戻すと落ちる
    func testSelectionMarksUseTheBrassTokens() throws {
        let code = try source()
        XCTAssertTrue(code.contains(".strokeBorder(WebTheme.accent, lineWidth: ThemeColorLayout.ringWidth)"),
                      "見本の丸の輪が真鍮でない")
        XCTAssertTrue(code.contains(".strokeBorder(isCustom ? WebTheme.accent : Color.white.opacity(0.3),"),
                      "「自由に選ぶ」丸の輪が真鍮でない")
        XCTAssertTrue(code.contains("themeColor.isEmpty ? WebTheme.accentText : WebTheme.muted"), "「なし」の字が墨でない")
        XCTAssertTrue(code.contains("themeColor.isEmpty ? WebTheme.accentFill : WebTheme.surface"), "「なし」の塗りが真鍮でない")
        XCTAssertFalse(code.contains(".primary"), "白（.primary）の選択の印が残っている")
        XCTAssertFalse(code.contains("accentBackground"), "「なし」が白の塗りのまま")
    }

    /// 🔴 **色選びを閉じるときは書かない。** `selectedColor` は開いたときの初期色のままなので、
    /// 「なし」のまま開いて触らずに閉じると見本の先頭（#38bdf8）に化けていた。色は `didSelect` で届く
    func testDidFinishOnlyDismisses() throws {
        let code = try source()
        let start = try XCTUnwrap(code.range(of: "func colorPickerViewControllerDidFinish("), "閉じる知らせが無い")
        let rest = code[start.upperBound...]
        let body = String(rest[..<(rest.range(of: "\n        }")?.lowerBound ?? rest.endIndex)])
        XCTAssertFalse(body.contains("pick("), "閉じるときに書いている")
        XCTAssertFalse(body.contains("write("), "閉じるときに書いている")
        XCTAssertFalse(body.contains("selectedColor"), "閉じるときに初期色を読んでいる")
        XCTAssertTrue(body.contains("viewController.dismiss(animated: true)"), "閉じていない")
        XCTAssertTrue(body.contains("reset()"), "閉じた後に「出していない」へ戻していない（二度目が開かない）")
        XCTAssertTrue(code.contains("didSelect color: UIKit.UIColor, continuously: Bool) {\n            write(color)"),
                      "選んだ色を書いていない")
    }

    /// 🔴 **色選びは SwiftUI の `.sheet` に埋め込まず、UIKit の `present` で直接 modal に出す。**
    /// 埋め込むとスポイトを押したときに落ちた（owner の実機・TestFlight 1.1.5/1.1.6・2026-10-16）
    func testPickerIsPresentedModallyNotEmbeddedInASheet() throws {
        let code = try source()
        XCTAssertFalse(code.contains(".sheet("), "色選びを .sheet に入れている")
        XCTAssertFalse(code.contains("ThemeColorPickerSheet"), "シートに埋め込む包みが残っている")
        XCTAssertFalse(code.contains("UIViewControllerRepresentable {\n\n    @Binding var themeColor: String\n    @Environment"),
                       "色選びそのものを SwiftUI に埋め込んでいる")
        XCTAssertTrue(code.contains("func makeUIViewController(context: Context) -> UIViewController {"),
                      "SwiftUI に置くのは見えない空の元だけ（色選びそのものを置かない）")
        XCTAssertTrue(code.contains("top.present(picker, animated: true)"), "present で出していない")
        XCTAssertTrue(code.contains("while let next = top.presentedViewController { top = next }"),
                      "いちばん上の画面から出していない")
        XCTAssertTrue(code.contains("picker.modalPresentationStyle = .popover"))
        XCTAssertTrue(code.contains("picker.popoverPresentationController?.sourceView = host.view"),
                      "iPad の吹き出しの元が無い（元が無いと落ちる）")
    }

    /// 🔴 **二度押しで2つ出さない**（ボタンの側と、出す元の側の両方で止める）
    func testPickerIsNotPresentedTwice() throws {
        let code = try source()
        XCTAssertTrue(code.contains("guard !showsPicker else { return }"), "ボタンの二度押しを止めていない")
        XCTAssertTrue(code.contains("guard isPresented, !coordinator.isShowing else { return }"),
                      "出している間に出し直してしまう")
        XCTAssertTrue(code.contains("coordinator.isShowing = true"))
        XCTAssertTrue(code.contains("func presentationControllerDidDismiss("), "払って閉じたあと二度目が開かない")
    }

    /// 🔴 **「自由に選ぶ」はふつうの Button（枠 44）で、端末の色選びをシートで出す。**
    /// 透明に近い `ColorPicker` を下に敷く作りは当たりが 28 のままの恐れがある
    func testCustomSwatchIsAButtonThatOpensTheSystemPicker() throws {
        let code = try source()
        XCTAssertFalse(code.contains("ColorPicker("), "SwiftUI の ColorPicker を敷く作りに戻っている")
        XCTAssertFalse(code.contains(".opacity(0.0"), "透明に近くして当たりを取る作りに戻っている")
        XCTAssertTrue(code.contains("showsPicker = true"), "丸のボタンが色選びを開いていない")
        XCTAssertTrue(code.contains("ThemeColorPickerPresenter(isPresented: $showsPicker, themeColor: $themeColor)"),
                      "色選びを出す元を置いていない")
        XCTAssertTrue(code.contains("UIColorPickerViewController()"))
        XCTAssertTrue(code.contains("picker.supportsAlpha = false"), "透明度を選べてしまう")
        XCTAssertTrue(code.contains("ThemeColor.nextValue(picked: picked, current: themeColor)"),
                      "同じ色でも書いてしまう")
        XCTAssertTrue(code.contains("UIAccessibility.post(notification: .announcement"), "暗い色の注意を読み上げない")
        XCTAssertTrue(code.contains("shouldAnnounceHardToSee(old: old, new: new, picking: showsPicker)"),
                      "読み込みでも読み上げてしまう")
        // 丸の枠は 44（ボタンの label の中で）
        XCTAssertTrue(code.contains(".frame(width: ThemeColorLayout.target, height: ThemeColorLayout.target)"))
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
