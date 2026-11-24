import XCTest

/// 画面の日本語の区切り（2026-11-23）。
///
/// - **「・」「·」で名前と時刻・件数・種類を区切らない**（owner の好み・2026-11-12）。区切りは字の太さ・色・余白か「、」。
///   1.1.84 のまとめで画面の文から消えたので、戻らないことを見る。「理由・補足」のような語の並びの「・」はよい——
///   見るのは「·」（U+00B7）と、差し込み（`\(…)`）の隣・文の頭や終わりに置いた「・」（区切りとして使った形）
/// - **和文の中で半角カンマ「,」を使わない**（2026-11-23・投稿の撮影地の欄の例「高屋神社, 香川」）。並べるときは「、」
/// - **例の書き出しは「例：」**（全角のコロン。「例: 」と混ざっていた）
///
/// 画面は Linux で描けないので、`L("…")` の日本語（1つ目の引数）を書いてあるもので見る（`NoDiscardWordingTests` と同じ形）
final class JapaneseSeparatorWordingTests: XCTestCase {

    /// `L("日本語", …)` の日本語の文と、その場所
    private func japaneseStrings() throws -> [(text: String, at: String)] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        let literal = try NSRegularExpression(pattern: #"L\("((?:[^"\\]|\\.)*)""#)
        let kana = try NSRegularExpression(pattern: "[ぁ-んァ-ヶ一-龥]")
        var out: [(String, String)] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let ns = line as NSString
                for match in literal.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    let text = ns.substring(with: match.range(at: 1))
                    guard kana.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
                    else { continue }
                    out.append((text, "\(file.lastPathComponent):\(i + 1)"))
                }
            }
        }
        return out
    }

    /// 差し込み（`\(…)`）を `{}` にした形（中の式の「,」や「·」を数えない）
    private func withoutInterpolation(_ text: String) -> String {
        var out = ""
        var depth = 0
        var chars = Array(text)[...]
        while let c = chars.first {
            chars = chars.dropFirst()
            if depth == 0, c == "\\", chars.first == "(" {
                chars = chars.dropFirst()
                depth = 1
                out += "{}"
                continue
            }
            if depth > 0 {
                if c == "(" { depth += 1 }
                if c == ")" { depth -= 1 }
                continue
            }
            out.append(c)
        }
        return out
    }

    func testNoMiddleDotSeparatorsInUIStrings() throws {
        let strings = try japaneseStrings()
        XCTAssertFalse(strings.isEmpty)
        let bad = strings.filter { item in
            let t = withoutInterpolation(item.text)
            return t.contains("·") || t.contains("{}・") || t.contains("・{}")
                || t.hasPrefix("・") || t.hasSuffix("・")
        }
        XCTAssertEqual(bad.map(\.at), [], "画面の文が中黒で区切っている: \(bad.map(\.text))")
    }

    func testNoHalfWidthCommaInJapaneseUIStrings() throws {
        let bad = try japaneseStrings().filter { withoutInterpolation($0.text).contains(",") }
        XCTAssertEqual(bad.map(\.at), [], "和文に半角カンマがある: \(bad.map(\.text))")
    }

    func testExamplesUseFullWidthColon() throws {
        let bad = try japaneseStrings().filter { $0.text.contains("例: ") && !$0.text.contains("凡例") }
        XCTAssertEqual(bad.map(\.at), [], "例の書き出しが「例: 」: \(bad.map(\.text))")
    }

    /// 投稿の撮影地の欄の例（ストアの画面写真で「高屋神社, 香川」と半角カンマだった）
    func testPlaceFieldExample() throws {
        let field = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Upload/PlaceSearchField.swift"), encoding: .utf8)
        XCTAssertTrue(field.contains(#"L("撮影地（例：高屋神社、香川）""#))
    }
}
