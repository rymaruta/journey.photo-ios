import XCTest

/// プロフィールの編集 → 名前の横のバッジ → メダルを回す全画面で戻れなくなった（2026-10-09 owner）。
/// 名前の横の画面のシートを Form の欄（Section）に付けていたのが原因。画面の外側に付ける
final class ProfileEditNameSideTests: XCTestCase {

    func testNameSideSheetIsNotAttachedInsideTheSection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Profile/ProfileEditView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private var nameSideSection: some View {"))
        let rest = source[start.upperBound...]
        let end = try XCTUnwrap(rest.range(of: "\n    }\n"))
        let section = rest[..<end.lowerBound]
        XCTAssertFalse(section.contains(".sheet("), "名前の横の画面のシートを欄の中に付けない")
        // 画面の外側（`.task { await load() }` の並び）に付いている
        XCTAssertTrue(source.contains("NameSideBadgeView(profile: loadedProfile)"))
        XCTAssertTrue(source.contains("        .sheet(isPresented: $showNameSide) {"))
    }
}
