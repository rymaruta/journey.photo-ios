import XCTest

/// 英語の「1 photos」を出さない（2026-10-07）。
///
/// Linux の試験は表示がいつも日本語なので、英語の側は書いてあることを見る。
/// 件数を差し込んだ「\(…) photos」の行は、同じ行で1枚のときを分けているか、
/// 1枚にならない数（上限・2枚以上のときだけ出す行）であること。
///
/// 2026-10-09: 写真のほかに撮影地（places・旅の一冊の画像の「1 places」）、
/// アルバムの人数（members）、ストーリー・一覧の読み上げ（viewers・likes）も見る
final class EnglishPluralTests: XCTestCase {

    /// 見る名詞（複数形）。件数を差し込んだすぐ後に来るもの
    private let nouns = ["photos", "places", "members", "viewers", "likes"]

    /// 1枚にならない数。上限の定数と、`count > 1` の枝の中だけで出す文
    private let neverOne = [
        "\\(limit) photos",                    // 一度に入れられる上限
        "\\(StoryQueue.maxShots) photos",      // ストーリーの上限
        "Post \\(model.items.count) photos",   // 2枚以上のときだけ
        "\\(savedEarlier) photos were",        // 1枚のときは別の文
        "\\(cap) places a day",                // 1日の上限（`TripPlanService.itemsPerDayMax`）
        "\\(SavedSpotsTrip.selectMax) places", // 選べる上限
        "\\(TripPicker.pickMax) places",       // 選べる上限
    ]

    func testCountedNounsAreSingularWhenOne() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        let pattern = #"\\\([^)]*\)+ ("# + nouns.joined(separator: "|") + #")\b"#
        var bad: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.range(of: pattern, options: .regularExpression) != nil {
                if line.contains("== 1") || neverOne.contains(where: line.contains) { continue }
                bad.append("\(file.lastPathComponent):\(i + 1)")
            }
        }
        XCTAssertEqual(bad, [], "1つのときも複数形になる英語の文がある")
    }
}
