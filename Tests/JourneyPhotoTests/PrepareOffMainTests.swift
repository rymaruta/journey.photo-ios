import XCTest

/// 🔴 **画像を整える（`ImagePreparer.prepare`）のは画面の処理の外で。**
///
/// 縮小・JPEG への焼き直し・読み直しての確認・代表色で、1枚に数百ミリ秒かかる。
/// プロフィールのアイコン・カバー（`ProfileEditView`）とストーリー（`StoryComposerView`）は
/// 画面の処理の上で呼んでいて、選ぶたびに画面が止まっていた。
///
/// 画面のコードは Linux では走らせられないので、**呼び出しの形**を見る:
/// 呼び出しを**囲むブロック**のどれかが `Task.detached { … }`（`operation:` の形も）であること。
/// 例外は投稿のモデルの差し替え口（`var prepareData … = { … }`・呼ぶのは `Task.detached` の中）だけ。
///
/// **限界:** 括弧は文字列・注記の中のものも数える（`//` から行末は外すが、`/* */` と文字列の中の
/// `{` `}` は外さない）。囲むブロックが detached でも、その中でさらに `MainActor.run` などに
/// 戻していれば見抜けない。呼び出しを関数に包んで外から呼ぶ形（呼び手が detached の中か）も追わない
final class PrepareOffMainTests: XCTestCase {

    func testEveryPrepareCallRunsInADetachedTask() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/JourneyPhoto")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "ImagePreparer.swift" }
        var calls = 0
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for call in Self.prepareCalls(in: source) {
                calls += 1
                XCTAssertTrue(call.offMain, "\(file.lastPathComponent):\(call.line) が画面の処理の上で画像を整えている")
            }
        }
        XCTAssertGreaterThanOrEqual(calls, 5, "呼び出しを見つけられていない（探し方が古い）")
    }

    /// 探し方そのものの確かめ（改行・離れた detached・囲んでいない detached）
    func testCheckerSeesTheEnclosingBlock() {
        let wrapped = """
        let p = try await Task.detached(priority: .userInitiated) {
            // 注記 { の中の括弧は数えない
            let a = 1
            let b = 2
            let c = 3
            return try ImagePreparer.prepare(
                data: data, fileName: "x")
        }.value
        """
        XCTAssertEqual(Self.prepareCalls(in: wrapped).map(\.offMain), [true], "3行より上の detached・改行した呼び出し")

        let operation = """
        let p = await Task.detached(priority: .userInitiated, operation: { try? ImagePreparer.prepare(data: d, fileName: "x") }).value
        """
        XCTAssertEqual(Self.prepareCalls(in: operation).map(\.offMain), [true])

        let besideNotAround = """
        Task.detached { warm() }
        let p = try ImagePreparer.prepare(data: data, fileName: "x")
        """
        XCTAssertEqual(Self.prepareCalls(in: besideNotAround).map(\.offMain), [false], "囲んでいない detached で通した")

        let onMain = """
        func f() {
            Task {
                let p = try ImagePreparer.prepare(data: data, fileName: "x")
            }
        }
        """
        XCTAssertEqual(Self.prepareCalls(in: onMain).map(\.offMain), [false], "ただの Task（画面の処理の上）で通した")
    }

    /// `ImagePreparer.prepare(` の呼び出しごとに、行と「detached のブロックの中か」
    static func prepareCalls(in source: String) -> [(line: Int, offMain: Bool)] {
        // `//` から行末を外す（行頭か空白の後ろの `//` だけ。URL の `https://` は残す）
        let code = source.components(separatedBy: "\n").map { line -> String in
            var cut = line.endIndex
            var search = line.startIndex
            while let range = line.range(of: "//", range: search..<line.endIndex) {
                if range.lowerBound == line.startIndex || line[line.index(before: range.lowerBound)].isWhitespace {
                    cut = range.lowerBound
                    break
                }
                search = range.upperBound
            }
            return String(line[..<cut])
        }.joined(separator: "\n")
        let chars = Array(code)
        let needle = Array("ImagePreparer.prepare(")
        var result: [(Int, Bool)] = []
        var i = 0
        while i + needle.count <= chars.count {
            guard Array(chars[i..<i + needle.count]) == needle else { i += 1; continue }
            let line = chars[..<i].filter { $0 == "\n" }.count + 1
            // 囲むブロックの開き括弧を内から外へたどる
            var depth = 0
            var offMain = false
            var j = i - 1
            while j >= 0 {
                if chars[j] == "}" { depth += 1 }
                if chars[j] == "{" {
                    if depth == 0 {
                        let head = String(chars[max(0, j - 160)..<j])
                        if Self.opensDetached(head) || head.contains("var prepareData") { offMain = true; break }
                    } else {
                        depth -= 1
                    }
                }
                j -= 1
            }
            result.append((line, offMain))
            i += needle.count
        }
        return result
    }

    /// 開き括弧の手前が `Task.detached { ` / `Task.detached(…) { ` / `Task.detached(…, operation: { ` か
    private static func opensDetached(_ head: String) -> Bool {
        guard let range = head.range(of: "Task.detached", options: .backwards) else { return false }
        let between = head[range.upperBound...]
        // 間に別のブロック・文が挟まっていない（`{` `}` `;` と空行が無い）
        guard !between.contains(where: { "{};".contains($0) }), !between.contains("\n\n") else { return false }
        let trimmed = between.trimmingCharacters(in: .whitespacesAndNewlines)
        // 呼び出しの括弧が閉じきっている（末尾の閉じ括弧の後ろの尾を持つ）か、`operation:` で終わる
        if trimmed.isEmpty { return true }
        if trimmed.hasSuffix("operation:") { return true }
        return trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
            && trimmed.filter({ $0 == "(" }).count == trimmed.filter({ $0 == ")" }).count
    }
}
