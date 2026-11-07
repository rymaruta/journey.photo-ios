import XCTest
@testable import JourneyPhoto

/// 人(プロフィール)の通報(2026-11-07・審査 1.2)。サーバーに人を通報する口は無いので、返信と同じメール方式
final class ProfileReportMailTests: XCTestCase {

    func testProfileReportMailCarriesWhoAndGoesToTheContactAddress() throws {
        let url = try XCTUnwrap(ModerationService.profileReportURL(userId: "u2", displayName: "A&B+C"))
        XCTAssertEqual(url.scheme, "mailto")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.path, LegalConsent.contactEmail)
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(Set(items.keys), ["subject", "body"], "名前の & で欄が割れた")
        XCTAssertTrue(items["subject"]?.hasPrefix(ModerationService.profileReportMarker) == true)
        XCTAssertTrue((items["body"] ?? "").contains("A&B+C (u2)"))
    }

    func testNameIsOptional() {
        let body = ModerationService.profileReportBody(userId: "u2", displayName: "")
        XCTAssertTrue(body.contains("User: u2"))
        XCTAssertFalse(body.contains("()"))
    }

    /// プロフィールの「…」に通報の項目が結んである(外すと審査 1.2 の口が消える)
    func testProfileMenuHasAReportItem() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Profile/UserProfileView.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("Button { reportProfile() }"))
        XCTAssertTrue(source.contains("ModerationService.profileReportURL"))
    }
}
