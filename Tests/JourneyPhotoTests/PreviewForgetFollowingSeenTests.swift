import XCTest
@testable import JourneyPhoto

/// 起動のときに「フォロー中をどこまで見たか」を空にする指定（`-JPPreviewForgetFollowingSeen`・2026-11-28・札 #594 の2回目）の試験。
/// 前の UI テストで覚えた印が残ると、`testCapturesHomeHeaderGapAndFollowingEnd` で新しい写真の段が出ず、試験の順番で落ちていた
final class PreviewForgetFollowingSeenTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "preview-forget-following-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 🔴 指定があれば、見本の利用者の印を空にする（戻すと落ちる）
    func testForgetsTheSeenMarkWhenAsked() {
        let store = FollowingSeenStore(defaults: defaults)
        defaults.set("u1", forKey: PreviewSession.defaultsKey)
        store.mark("2026-11-01T00:00:00Z", for: "u1")
        store.mark("2026-11-02T00:00:00Z", for: "u2")
        defaults.set(true, forKey: PreviewSession.forgetFollowingSeenKey)
        PreviewSession.forgetFollowingSeenIfAsked(defaults: defaults)
        XCTAssertNil(store.seen(for: "u1"), "指定したのに前の試験の印が残る")
        XCTAssertEqual(store.seen(for: "u2"), "2026-11-02T00:00:00Z", "見本の利用者でない人の印まで消した")
    }

    /// 指定が無ければ何も消さない（ふだんの起動）
    func testKeepsTheSeenMarkWithoutTheFlag() {
        let store = FollowingSeenStore(defaults: defaults)
        defaults.set("u1", forKey: PreviewSession.defaultsKey)
        store.mark("2026-11-01T00:00:00Z", for: "u1")
        PreviewSession.forgetFollowingSeenIfAsked(defaults: defaults)
        XCTAssertEqual(store.seen(for: "u1"), "2026-11-01T00:00:00Z")
    }

    /// 起動で呼び、UI テストが指定を渡す
    func testWiredAtLaunchAndInTheUITest() throws {
        XCTAssertTrue(try source("Sources/JourneyPhoto/App/JourneyPhotoApp.swift").contains("PreviewSession.forgetFollowingSeenIfAsked()"))
        let shots = try source("UITests/JourneyPhotoUITests/ScreenshotTests.swift")
        guard let range = shots.range(of: "func testCapturesHomeHeaderGapAndFollowingEnd()") else { return XCTFail("UI テストが無い") }
        XCTAssertTrue(shots[range.upperBound...].prefix(1800).contains("\"-JPPreviewForgetFollowingSeen\", \"YES\""),
                      "UI テストが起動のときに印を空にしていない")
    }
}
