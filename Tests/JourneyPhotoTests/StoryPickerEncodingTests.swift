import XCTest

/// ストーリーの写真選び（2026-10-09 owner の報告: 選んだ写真に白い丸が出たまま「写真を選んでください」が
/// 灰色のまま）。写真を作り直さず元の形のまま受け取る（`.current`）
final class StoryPickerEncodingTests: XCTestCase {

    func testInlinePickerKeepsOriginalEncoding() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "PhotosPicker(selection: $librarySelection,"))
        let call = source[start.lowerBound...].prefix(400)
        XCTAssertTrue(call.contains("preferredItemEncoding: .current"))
    }
}
