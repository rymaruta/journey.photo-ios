import XCTest
@testable import JourneyPhoto

/// フォロー一覧を未ログインで開いたとき（2026-10-11）。
///
/// 以前は赤い「ログインが必要です」だけで、先へ進む口が無かった（画面写真 21b）。
/// エラーではないので赤にせず、ふつうの色の1行と「ログイン」（`SignInView`）を出す
final class FollowListSignInTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 「ログインしていない」だけを案内にする。圏外・サーバーの失敗はログインしても直らないので混ぜない
    func testOnlyNotAuthenticatedAsksToSignIn() {
        XCTAssertTrue(FollowListView.needsSignIn(APIError.notAuthenticated))
        XCTAssertFalse(FollowListView.needsSignIn(APIError.unreachable))
        XCTAssertFalse(FollowListView.needsSignIn(APIError.server(status: 500, message: "x")))
        XCTAssertFalse(FollowListView.needsSignIn(CancellationError()))
    }

    func testSignInLine() {
        XCTAssertEqual(FollowListView.signInLine(.followers), "ログインするとフォロワーを見られます")
        XCTAssertEqual(FollowListView.signInLine(.following), "ログインするとフォロー中の人を見られます")
    }

    /// 画面がこの見分けを通る・赤にしない・「ログイン」が既存の `SignInView` を開く
    func testFollowListWiresSignInPrompt() throws {
        let view = try source("Features/Profile/FollowListView.swift")
        XCTAssertTrue(view.contains("} catch where Self.needsSignIn(error) {\n            needsSignIn = true"),
                      "未ログインの失敗を赤い文（errorMessage）に流している")
        XCTAssertTrue(view.contains("if needsSignIn {\n                signInPrompt"),
                      "案内が一覧に出ていない（赤い文より先に見る）")
        XCTAssertTrue(view.contains("SignInView(reason: Self.signInLine(current))"))
        XCTAssertTrue(view.contains("showSignIn = true"))
        let prompt = view.components(separatedBy: "private var signInPrompt: some View {").last?
            .components(separatedBy: "/// 「フォロワー N").first ?? ""
        XCTAssertTrue(prompt.contains(#"Text(L("ログイン", "Sign in"))"#))
        XCTAssertTrue(prompt.contains(".foregroundStyle(WebTheme.muted2)"))
        XCTAssertFalse(prompt.contains("danger"), "エラーではないので赤にしない")
    }
}
