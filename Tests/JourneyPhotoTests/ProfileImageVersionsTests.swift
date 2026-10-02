import XCTest
@testable import JourneyPhoto

/// アイコン・カバーの `?v=` を**本人が変えたとき（と開き直したとき）だけ**替える。
///
/// 前はマイページ・人のページを読み直すたびに今の時刻を `?v=` にしていて、戻るたびに
/// 出ていた絵まで捨てて取り直していた（2026-10-02 の調査）
final class ProfileImageVersionsTests: XCTestCase {

    func testSameTokenAcrossReloads() {
        let versions = ProfileImageVersions(launch: "L1")
        XCTAssertEqual(versions.token(for: "me"), "L1")
        XCTAssertEqual(versions.token(for: "me"), versions.token(for: "me"), "読み直しで URL が変わらない")
    }

    func testBumpChangesOnlyThatPerson() {
        var versions = ProfileImageVersions(launch: "L1")
        versions.bump("me", token: "T1")
        XCTAssertEqual(versions.token(for: "me"), "T1", "変えた本人の絵は取り直す")
        XCTAssertEqual(versions.token(for: "other"), "L1", "他の人の URL は変えない")
        versions.bump("me", token: "T2")
        XCTAssertEqual(versions.token(for: "me"), "T2", "もう一度変えたらまた取り直す")
    }

    func testDefaultBumpIsFresh() {
        var versions = ProfileImageVersions(launch: "L1")
        versions.bump("me")
        let first = versions.token(for: "me")
        versions.bump("me")
        XCTAssertNotEqual(first, versions.token(for: "me"))
        XCTAssertNotEqual(first, "L1")
    }

    /// 🔴 **画面が読み込みのたびに時刻で `?v=` を作っていないこと**（戻すと毎回取り直す）
    func testProfileScreensDoNotBustOnEveryLoad() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["MyPageView.swift", "UserProfileView.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(
                "Sources/JourneyPhoto/Features/Profile/\(file)"), encoding: .utf8)
            XCTAssertFalse(source.contains("Bust = String(Int(Date().timeIntervalSince1970))"),
                           "\(file) が読み込みのたびに ?v= を替えている")
            XCTAssertTrue(source.contains("ProfileImageVersions.shared.token(for:"), "\(file) が版の印を使っていない")
        }
    }
}
