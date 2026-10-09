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
        XCTAssertTrue(source.contains(".sheet(isPresented: $showNameSide, onDismiss: { Task { await reloadBadgeState() } }) {"))
        // 🔴 閉じたらバッジの値を読み直す（バグ調査 高-2: 決める前の選択で開き直していた）。入力中の欄は触らない
        let reload = try XCTUnwrap(source.range(of: "private func reloadBadgeState() async {"))
        let body = source[reload.upperBound...].prefix(200)
        XCTAssertTrue(body.contains("loadedProfile = fresh"))
        XCTAssertFalse(body.contains("displayName ="))
    }
}
