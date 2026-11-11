import XCTest
@testable import JourneyPhoto

/// プロフィールの QR（札 #545 の第1段・2026-11-12）。中身は公開プロフィールの URL、読み取りは journey-photo.com の
/// 人の URL だけを人の頁で開く。入口はマイページの名前の横（owner の決定）
final class ProfileQRTests: XCTestCase {

    private let base = URL(string: "https://journey-photo.com")!
    private let staging = URL(string: "https://staging.journey-photo.com")!
    private let uid = "a1b2c3d4-0000-4111-8222-333344445555"

    // MARK: - 中身

    /// QR に入れるのは、だれでも開ける `/users?id=<id>`（投稿の無い人の `/users/<id>` は次のビルドまで無い）
    func testURLIsThePublicProfile() {
        XCTAssertEqual(ProfileQR.url(userId: uid, base: base)?.absoluteString,
                       "https://journey-photo.com/users?id=\(uid)")
        // URL に入れられない id は作らない（空の QR を出さない）
        XCTAssertNil(ProfileQR.url(userId: "", base: base))
        XCTAssertNil(ProfileQR.url(userId: "a/b", base: base))
        XCTAssertNil(ProfileQR.url(userId: "a b", base: base))
    }

    /// 作った URL を読むと同じ人に戻る
    func testRoundTrip() throws {
        let url = try XCTUnwrap(ProfileQR.url(userId: uid, base: base))
        XCTAssertEqual(ProfileQR.userId(from: url.absoluteString, base: base), uid)
        let onStaging = try XCTUnwrap(ProfileQR.url(userId: uid, base: staging))
        XCTAssertEqual(ProfileQR.userId(from: onStaging.absoluteString, base: staging), uid)
    }

    // MARK: - 読み取り

    func testReadsEveryPersonURLShape() {
        for text in ["https://journey-photo.com/users?id=\(uid)",
                     "https://www.journey-photo.com/users?id=\(uid)",
                     "https://journey-photo.com/users/\(uid)",
                     "https://journey-photo.com/users/\(uid)/",
                     "https://journey-photo.com/u/\(uid)",
                     "  https://journey-photo.com/users?id=\(uid)\n",
                     "HTTPS://Journey-Photo.com/users?id=\(uid)"] {
            XCTAssertEqual(ProfileQR.userId(from: text, base: base), uid, text)
        }
        // staging の版でも本番の QR を読める
        XCTAssertEqual(ProfileQR.userId(from: "https://journey-photo.com/users?id=\(uid)", base: staging), uid)
        XCTAssertEqual(ProfileQR.userId(from: "https://staging.journey-photo.com/users?id=\(uid)", base: staging), uid)
    }

    /// ほかのサイト・人でない頁・おかしな id は開かない（外のサイトへ連れ出さない）
    func testRejectsOtherCodes() {
        for text in ["https://example.com/users?id=\(uid)",
                     "https://journey-photo.com.evil.example/users?id=\(uid)",
                     "https://evil.example/?u=https://journey-photo.com/users?id=\(uid)",
                     "javascript:alert(1)",
                     "journey-photo.com/users?id=\(uid)",
                     "ftp://journey-photo.com/users?id=\(uid)",
                     "https://journey-photo.com/users/search",
                     "https://journey-photo.com/users/trip",
                     "https://journey-photo.com/users",
                     "https://journey-photo.com/users?id=",
                     "https://journey-photo.com/users?id=a%2Fb",
                     "https://journey-photo.com/photo/\(uid)",
                     "https://journey-photo.com/users/\(uid)/extra",
                     "WIFI:S:home;T:WPA;P:secret;;",
                     ""] {
            XCTAssertNil(ProfileQR.userId(from: text, base: base), text)
        }
    }

    /// 自分の QR は開かず「あなたの QR です」
    func testScanResult() {
        let mine = "https://journey-photo.com/users?id=\(uid)"
        XCTAssertEqual(ProfileQRScanResult.of(mine, myUserId: uid, base: base), .mine)
        XCTAssertEqual(ProfileQRScanResult.of(mine, myUserId: "someone-else", base: base), .person(uid))
        XCTAssertEqual(ProfileQRScanResult.of("https://example.com", myUserId: uid, base: base), .other)
    }

    func testWordsAreJapaneseFirstAndNoBannedWords() {
        for text in [ProfileQRText.title, ProfileQRText.showTab, ProfileQRText.scanTab, ProfileQRText.showHint,
                     ProfileQRText.scanHint, ProfileQRText.notOurs, ProfileQRText.yours, ProfileQRText.denied] {
            XCTAssertFalse(text.isEmpty)
            for banned in ["捨てる", "撮りどき", "この場所"] {
                XCTAssertFalse(text.contains(banned), "\(text) に「\(banned)」")
            }
        }
    }

    // MARK: - 作り

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 入口はマイページの名前のすぐ右（「編集」の左）。押すと1枚の QR の画面（見せる／読み取るを切り替える）
    func testEntryIsNextToTheNameOnMyPage() throws {
        let page = try source("Features/Profile/MyPageView.swift")
        let row = try XCTUnwrap(page.range(of: "HStack(alignment: .center, spacing: MyPageHeaderLayout.nameEditGap)"))
        let rest = String(page[row.upperBound...].prefix(600))
        let name = try XCTUnwrap(rest.range(of: "nameLine(profile)"))
        let qr = try XCTUnwrap(rest.range(of: "qrLink()"), "QR の印が名前の段に無い")
        let edit = try XCTUnwrap(rest.range(of: "editLink()"))
        XCTAssertLessThan(name.lowerBound, qr.lowerBound)
        XCTAssertLessThan(qr.lowerBound, edit.lowerBound, "QR の印が名前の横でない")
        XCTAssertTrue(page.contains("NavigationStack { ProfileQRView(profile: profile) }"))
        XCTAssertTrue(page.contains(#".accessibilityIdentifier("mypage.qr")"#))
        // 人のページには置かない（QR は本人にだけ見える）
        let other = try source("Features/Profile/UserProfileView.swift")
        XCTAssertFalse(other.contains("ProfileQRView("), "人のページに QR の入口がある")
    }

    /// 見せると読み取るは1枚の画面の切り替え。読み取った人は同じ画面の上に開く
    func testOneScreenWithBothModes() throws {
        let view = try source("Features/Profile/ProfileQRView.swift")
        XCTAssertTrue(view.contains("segment(.show, title: ProfileQRText.showTab"))
        XCTAssertTrue(view.contains("segment(.scan, title: ProfileQRText.scanTab"))
        XCTAssertTrue(view.contains("UserProfileView(userId: person.userId)"))
        XCTAssertTrue(view.contains("switch ProfileQRScanResult.of(code, myUserId: myUserId)"))
        XCTAssertTrue(view.contains("ProfileQR.url(userId: profile.userId)"))
        XCTAssertTrue(view.contains("output.metadataObjectTypes = [.qr]"))
        // 外のサイトを開かない（読み取った文字で openURL しない）
        XCTAssertFalse(view.contains("openURL(URL(string: code"))
    }
}
