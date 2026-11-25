import XCTest
@testable import JourneyPhoto

/// JPField を並べる `Form` の画面が、節の角で欄を欠けさせないこと（2026-11-25・owner の実機の画面写真）。
///
/// `Form` の既定（角の丸い札の形）は、節の最初の行の上の角と最後の行の下の角を丸く切り抜く。
/// 行の左右の余白を 0 にして欄を節の端まで出していたので、「いまのパスワード」の「い」の左の画と、
/// 「新しいパスワード」の欄の下の縁の両端が欠けていた。直しは `jpForm()`（角の無い形）と、
/// 行の左右の余白を画面の端 16 にすること（`JPFormLayout.sideInset`）
final class FormRowCornerTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
    }

    /// 行の左右の余白は画面の端（板 16）。0 だと欄が節の端に付く
    func testFormRowKeepsSideInset() {
        XCTAssertEqual(JPFormLayout.sideInset, JPSpace.gutter)
        XCTAssertGreaterThan(JPFormLayout.sideInset, 0, "行の左右の余白が 0（欄が節の端に付く）")
        XCTAssertGreaterThanOrEqual(JPFormLayout.rowGap, 0, "行の上下の余白が負")
    }

    /// 共通の部品: `jpForm()` は角の無い形、`jpFormRow` は左右に `sideInset` を取る
    func testSharedModifiers() throws {
        let parts = try source("Core/Design/FormParts.swift")
        XCTAssertTrue(parts.contains(".listStyle(.grouped)"), "jpForm() が角の無い形になっていない")
        XCTAssertTrue(parts.contains(".contentMargins(.horizontal, 0, for: .scrollContent)"),
                      "jpForm() が一覧の左右の余白を消していない（行の 16 に端末の余白が足される）")
        XCTAssertTrue(parts.contains("leading: JPFormLayout.sideInset"), "jpFormRow の左の余白が sideInset でない")
        XCTAssertTrue(parts.contains("trailing: JPFormLayout.sideInset"), "jpFormRow の右の余白が sideInset でない")
        XCTAssertFalse(parts.contains("leading: 0, bottom: 8, trailing: 0"), "jpFormRow が左右 0 に戻っている")
    }

    /// `jpFormRow` を使う画面は、どれも `Form` に `jpForm()` を付け、行の余白を 0 にしない
    func testScreensUsingFormRowUseCornerlessForm() throws {
        let screens = ["Features/Settings/ChangePasswordView.swift", "Features/Settings/DeleteAccountView.swift"]
        for path in screens {
            let view = try source(path)
            XCTAssertTrue(view.contains("Form {"), "\(path) が Form でなくなった（このテストを見直す）")
            XCTAssertTrue(view.contains(".jpForm()"), "\(path) の Form が角の丸い札の形のまま（欄が角で欠ける）")
            XCTAssertFalse(view.contains("listRowInsets(EdgeInsets())"), "\(path) に左右 0 の行がある")
            XCTAssertFalse(view.contains("leading: 0"), "\(path) に左 0 の行がある")
        }
        // ほかに `jpFormRow` を使う画面が増えたら、ここに足す
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let users = try files.filter { try String(contentsOf: $0, encoding: .utf8).contains(".jpFormRow(") }
            .map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
        XCTAssertEqual(Set(users), Set(screens), "jpFormRow を使う画面が増えた・減った（jpForm() を付けたか見る）")
    }

    /// パスワードの決まりの文は節の footer でなく行に置く（footer の端は端末の余白で、行の端 16 と揃わない）
    func testChangePasswordRuleIsARow() throws {
        let view = try source("Features/Settings/ChangePasswordView.swift")
        XCTAssertFalse(view.contains("} footer: {"), "決まりの文が footer に戻っている")
        XCTAssertTrue(view.contains("Text(AuthMessage.passwordRule)"))
    }
}
