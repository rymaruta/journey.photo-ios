import XCTest

/// ログイン・登録・パスワードの再設定の欄の種類（`textContentType`）を見張る（札 #661・2026-11-24）。
///
/// iPhone に保存した journey-photo.com のパスワードをキーボードの上に候補として出すには、
/// アカウントの欄が `.username`、パスワードの欄が `.password`（ログイン）か `.newPassword`（登録・再設定・変更）であること。
/// 欄の種類を取り違えても画面もビルドも壊れず、候補が黙って出なくなるだけなので、元のコードを読んで確かめる。
final class PasswordAutoFillTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func count(_ part: String, in text: String) -> Int {
        text.components(separatedBy: part).count - 1
    }

    /// メールの欄（ログイン・登録の1つと、再設定のコードを送る前の1つ）は `.username`。`.emailAddress` は使わない
    func testSignInEmailFieldsAreUsername() throws {
        let view = try source("Features/Auth/SignInView.swift")
        XCTAssertEqual(count(".textContentType(.username)", in: view), 2,
                       "ログインと再設定のメールの欄が `.username` でない（保存したアカウントが候補に出ない）")
        XCTAssertEqual(count(".textContentType(.emailAddress)", in: view), 0,
                       "メールの欄に `.emailAddress` が残っている（候補に出るのは連絡先の自分のメールだけになる）")
    }

    /// パスワードの欄: ログインは `.password`、登録と再設定は `.newPassword`（強いパスワードの案と保存）
    func testSignInPasswordFields() throws {
        let view = try source("Features/Auth/SignInView.swift")
        XCTAssertTrue(view.contains(".textContentType(mode == .signUp ? .newPassword : .password)"),
                      "ログインと登録のパスワードの欄の種類が違う")
        XCTAssertEqual(count(".textContentType(.newPassword)", in: view), 1, "再設定の新しいパスワードの欄が `.newPassword` でない")
    }

    /// ログインしたままの変更: 今のパスワードは `.password`、新しいパスワードは `.newPassword`
    func testChangePasswordFields() throws {
        let view = try source("Features/Settings/ChangePasswordView.swift")
        XCTAssertEqual(count(".textContentType(.password)", in: view), 1)
        XCTAssertEqual(count(".textContentType(.newPassword)", in: view), 1)
    }
}
