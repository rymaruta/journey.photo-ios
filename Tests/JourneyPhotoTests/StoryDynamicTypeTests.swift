import XCTest
@testable import JourneyPhoto

/// 🔴 **ストーリーまわりの文字は Dynamic Type に付いてくる**（2026-10-02 の調査）。
///
/// 以前は `.system(size: 14)` のような固定の大きさで、文字を大きくしている人にも
/// 小さいままだった。文字の種類（`.subheadline` など）に替え、写真の上の飾りは
/// `StoryViewerView.chromeTypeLimit` で上限を切る。
///
/// 画面は Linux で描けないので、**ソースに固定の大きさが戻っていないこと**を見る。
/// 写真に焼き込む文字（`StoryTextLayer`・`TextOverlay`）と `AppLogo` は対象外
/// （見る人と同じ位置・同じ大きさに出すため固定のまま）
final class StoryDynamicTypeTests: XCTestCase {

    /// 固定のままでよい行（中身の一部で当てる）
    private static let allowed: [String: [String]] = [
        // 52pt の升に入れる絵文字のスタンプ（絵として選ぶもの。文字ではない）
        "Stories/StickerTray.swift": [".font(.system(size: 30))"],
    ]

    private static let files = [
        "Stories/StoryViewerView.swift",
        "Stories/StoryInsightsView.swift",
        "Stories/StoryAudienceSheet.swift",
        "Stories/SongStartSheet.swift",
        "Stories/StickerTray.swift",
    ]

    func testStoryScreensDoNotUseFixedTextSizes() throws {
        let features = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features")
        for file in Self.files {
            let source = try String(contentsOf: features.appendingPathComponent(file), encoding: .utf8)
            let fixed = source.components(separatedBy: "\n").enumerated().filter { _, line in
                // 注記（`//`）の中は数えない
                !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                    && line.contains(".system(size:")
                    && !(Self.allowed[file] ?? []).contains { line.contains($0) }
            }
            XCTAssertTrue(fixed.isEmpty,
                          "\(file) に固定の大きさの文字が残っている: "
                          + fixed.map { "\($0.offset + 1)行" }.joined(separator: ", "))
        }
    }

    /// 写真の上の飾りの上限は、読める大きさまで（小さく止めすぎない）
    func testChromeLimitIsAboveDefault() {
        XCTAssertGreaterThanOrEqual(StoryViewerView.chromeTypeLimit, .xxLarge)
    }
}
