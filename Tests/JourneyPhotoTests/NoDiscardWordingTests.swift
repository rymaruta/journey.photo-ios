import XCTest

/// 画面の言葉に「捨てる」を使わない（owner の好み・2026-10-09）。
///
/// 閉じる確認は「保存せずに閉じる」「保存せずに戻る」、投稿は「投稿をやめる」、
/// 下書きは「下書きを削除」と、**何が起きるか**で言う。画面は Linux で描けないので、
/// `L("…")` の日本語に「捨て」が入っていないことを書いてあるもので見る
final class NoDiscardWordingTests: XCTestCase {

    func testUIStringsDoNotSayDiscard() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var bad: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated()
            where line.range(of: #"L\("[^"]*捨て"#, options: .regularExpression) != nil {
                bad.append("\(file.lastPathComponent):\(i + 1)")
            }
        }
        XCTAssertEqual(bad, [], "画面の言葉に「捨てる」がある")
    }
}
