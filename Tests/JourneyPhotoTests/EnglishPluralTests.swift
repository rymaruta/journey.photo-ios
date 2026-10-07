import XCTest

/// 英語の「1 photos」を出さない（2026-10-07）。
///
/// Linux の試験は表示がいつも日本語なので、英語の側は書いてあることを見る。
/// 件数を差し込んだ「\(…) photos」の行は、同じ行で1枚のときを分けているか、
/// 1枚にならない数（上限・2枚以上のときだけ出す行）であること
final class EnglishPluralTests: XCTestCase {

    /// 1枚にならない数。上限の定数と、`count > 1` の枝の中だけで出す文
    private let neverOne = [
        "\\(limit) photos",                    // 一度に入れられる上限
        "\\(StoryQueue.maxShots) photos",      // ストーリーの上限
        "Post \\(model.items.count) photos",   // 2枚以上のときだけ
        "\\(savedEarlier) photos were",        // 1枚のときは別の文
    ]

    func testCountedPhotosAreSingularWhenOne() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var bad: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.range(of: #"\\\([^)]*\)+ photos"#, options: .regularExpression) != nil {
                if line.contains("== 1") || neverOne.contains(where: line.contains) { continue }
                bad.append("\(file.lastPathComponent):\(i + 1)")
            }
        }
        XCTAssertEqual(bad, [], "1枚のときも「photos」になる英語の文がある")
    }
}
