import XCTest

/// UI テストのアプリの閉じ方（2026-11-21・札 #681「UI テストが前のアプリの終わりに気づかず Failed to terminate で落ちる」）。
/// run 1696: 前のアプリは閉じろと言われて 5 秒以内に消えていたのに、次の試験の `launch()` が気づかず約 60 秒待って落とした。
/// UI テストは Linux で組めないので、決まりの形を字で確かめる
final class UITestCloseRulesTests: XCTestCase {

    private let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("UITests/JourneyPhotoUITests")

    private func read(_ name: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    /// どの UI テストの組も共通の基に乗る（自分で起動したアプリを自分の終わりに閉じる・閉じられない失敗の扱い）
    func testEveryUITestClassUsesTheCommonBase() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }
        var classes = 0
        for name in files where name != "JPUITestCase.swift" {
            let text = try read(name)
            XCTAssertFalse(text.contains(": XCTestCase {"), "\(name) が共通の基（JPUITestCase）に乗っていない")
            classes += text.components(separatedBy: ": JPUITestCase {").count - 1
        }
        XCTAssertGreaterThanOrEqual(classes, 15, "UI テストの組が見つからない")
    }

    /// `jp()` で作ったアプリは試験の終わりに閉じ、止まったことを確かめる。次の launch に閉じる仕事を残さない
    func testAppsMadeByJpAreClosedAtTheEndOfTheirTest() throws {
        let jp = try read("XCUIApplication+JP.swift")
        XCTAssertTrue(jp.contains("JPUITestCase.running?.closeAtEnd(app)"), "jp() が後始末を付けていない")
        let base = try read("JPUITestCase.swift")
        XCTAssertTrue(base.contains("addTeardownBlock { JPAppClose.close(app) }"))
        XCTAssertTrue(base.contains("app.terminate()"))
        XCTAssertTrue(base.contains("app.wait(for: .notRunning, timeout: goneTimeout)"), "止まったことを確かめていない")
        XCTAssertTrue(base.contains("override func invokeTest()"), "いまの試験を覚えていない")
        // `.notRunning` のあと、pid が消えるまで待ってから次へ（run 1700。pid が分からなければ今の形のまま）
        XCTAssertTrue(base.contains("let pid = processID(of: app)"), "閉じる前に pid を覚えていない")
        XCTAssertTrue(base.contains("let gone = waitGone(pid: pid, timeout: goneTimeout)"), "pid が消えるのを待っていない")
        XCTAssertTrue(base.contains("app.responds(to: NSSelectorFromString(\"processID\"))"), "KVC の前に確かめていない（無いと落ちる）")
    }

    /// 「閉じられない」で落ちたら、本当に残っているかを見て決める（XCTExpectFailure にしない・残っていれば失敗のまま）
    func testStaleTerminateIsJudgedByWhetherThePidIsGone() throws {
        let base = try read("JPUITestCase.swift")
        XCTAssertTrue(base.contains("override func record(_ issue: XCTIssue)"))
        XCTAssertTrue(base.contains("kill(pid, 0) != 0 && errno == ESRCH"), "pid が無いことを ESRCH で確かめていない")
        XCTAssertTrue(base.contains("super.record(issue)"), "残っているときに失敗にしていない")
        XCTAssertFalse(base.contains("XCTExpectFailure"), "閉じられない失敗を XCTExpectFailure で隠している")
    }
}
