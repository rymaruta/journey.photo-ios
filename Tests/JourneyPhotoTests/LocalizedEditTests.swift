import XCTest
@testable import JourneyPhoto

/// 写真の編集で、`{ja, en}` の題・説明の英語側を消さない。
///
/// 🔴 以前は表示用の1言語（`displayTitle` / `paragraphs`）を欄に出し、
/// 保存で**平文のまま毎回**送っていた——英語の題と説明が保存のたびに消えていた。
final class LocalizedEditTests: XCTestCase {

    private func json(_ value: LocalizedPatchValue?) throws -> String {
        var patch = PhotoPatch()
        patch.title = value
        let data = try JSONEncoder().encode(patch)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let title = try XCTUnwrap(object["title"])
        let out = try JSONSerialization.data(withJSONObject: ["v": title], options: [.sortedKeys])
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: - 触っていない欄は送らない

    func testUntouchedTitleIsNotSent() {
        let original = LocalizedText.byLocale(["ja": "朝の海", "en": "Morning Sea"])
        XCTAssertNil(LocalizedEdit.title(original: original, field: LocalizedEdit.titleField(original)))
    }

    /// サーバーが入れていた「無題」は欄に出さない。**開いて保存しただけで
    /// 「無題」を空に書き換えない**
    func testUntouchedPlaceholderTitleIsNotSent() {
        let original = LocalizedText.byLocale(["ja": "無題"])
        XCTAssertEqual(LocalizedEdit.titleField(original), "")
        XCTAssertNil(LocalizedEdit.title(original: original, field: ""))
    }

    /// 説明は段落に割って欄に出す。**改行が1エントリに埋まった写真**でも、
    /// 触らなければ送らない
    func testUntouchedDescriptionIsNotSent() {
        let original = LocalizedParagraphs.byLocale(["ja": ["一行目\n二行目"], "en": ["Line"]])
        let field = LocalizedEdit.descriptionField(original)
        XCTAssertEqual(field, "一行目\n二行目")
        XCTAssertNil(LocalizedEdit.description(original: original, field: field))
    }

    // MARK: - 直した欄は英語を残す

    func testEditedTitleKeepsEnglish() throws {
        let original = LocalizedText.byLocale(["ja": "朝の海", "en": "Morning Sea"])
        let sent = LocalizedEdit.title(original: original, field: "夕方の海")
        XCTAssertEqual(sent, .texts(["ja": "夕方の海", "en": "Morning Sea"]))
        XCTAssertEqual(try json(sent), #"{"v":{"en":"Morning Sea","ja":"夕方の海"}}"#)
    }

    func testEditedDescriptionKeepsEnglish() {
        let original = LocalizedParagraphs.byLocale(["ja": ["朝"], "en": ["Morning", "Sea"]])
        let sent = LocalizedEdit.description(original: original, field: "夕方\n\n 海 ")
        XCTAssertEqual(sent, .paragraphs(["ja": ["夕方", "海"], "en": ["Morning", "Sea"]]))
    }

    /// 英語を持たない写真（大半）は平文のまま送る
    func testPlainPhotoIsSentAsPlainText() {
        XCTAssertEqual(LocalizedEdit.title(original: .plain("朝"), field: "夕方"), .plain("夕方"))
        XCTAssertEqual(LocalizedEdit.description(original: nil, field: "夕方\n海"), .plain("夕方\n海"))
    }

    /// **空にしたら英語ごと消す。** 英語だけ残すと表示が英語に落ち、
    /// 消したはずの題が出続ける（Web の `mergeLocalizedTitle` と同じ判断）
    func testClearingRemovesEnglishToo() {
        let title = LocalizedText.byLocale(["ja": "朝の海", "en": "Morning Sea"])
        XCTAssertEqual(LocalizedEdit.title(original: title, field: "  "), .plain(""))
        let desc = LocalizedParagraphs.byLocale(["ja": ["朝"], "en": ["Morning"]])
        XCTAssertEqual(LocalizedEdit.description(original: desc, field: "\n"), .plain(""))
    }
}
