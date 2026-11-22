import XCTest
@testable import JourneyPhoto

/// 眉ラベルは大きな字の設定（AX）で折り返す（札 #680: AX XL で旅行プランの日の見出しが1行のまま幅を固定し、
/// 地図・「…」と並んで画面全体が画面の幅より広くなった）
final class EyebrowLineWrapTests: XCTestCase {

    func testWrapsOnlyAtAccessibilitySizes() {
        XCTAssertFalse(JPEyebrowLine.wraps(.large), "標準の大きさでは今までどおり1行")
        XCTAssertFalse(JPEyebrowLine.wraps(.xxxLarge))
        XCTAssertTrue(JPEyebrowLine.wraps(.accessibility1))
        XCTAssertTrue(JPEyebrowLine.wraps(.accessibility3), "AX XL で1行に固定すると旅行プランの画面がはみ出す")
    }

    func testTextIsNotPinnedToOneLineAtAccessibilitySizes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Core/Design/EyebrowLine.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains(".lineLimit(Self.wraps(typeSize) ? nil : 1)"), "大きな字でも1行に固定している")
        XCTAssertTrue(source.contains(".fixedSize(horizontal: !Self.wraps(typeSize), vertical: true)"),
                      "大きな字でも横の幅を固定している（画面の幅を押し広げる）")
        XCTAssertFalse(source.contains("                .fixedSize()\n"), "字に .fixedSize() が残っている")
    }
}
