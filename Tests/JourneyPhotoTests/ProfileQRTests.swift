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

    // MARK: - 更新できる QR に備える（2026-11-12 owner の要望・サーバーは承認待ち）

    /// `/qr?t=<合図>` を今から見分ける（引くのは ProfileQRSource）。ほかの家・おかしな合図は見分けない。
    /// 2026-11-12 秘書室の決定: 道は `/qr?t=`（`/q` は Web の今日の一問・`/qr/<合図>` の形は使わない）
    func testRecognizesPassLinks() {
        XCTAssertEqual(ProfileQRLink.parse("https://journey-photo.com/qr?t=Ab3_x-9Zq", base: base), .pass("Ab3_x-9Zq"))
        XCTAssertEqual(ProfileQRLink.parse("https://www.journey-photo.com/qr/?t=abc", base: base), .pass("abc"))
        XCTAssertEqual(ProfileQRLink.parse("https://journey-photo.com/u/\(uid)", base: base), .person(uid))
        for text in ["https://example.com/qr?t=abc",
                     "https://journey-photo.com/qr",
                     "https://journey-photo.com/qr?t=",
                     "https://journey-photo.com/qr?id=abc",
                     "https://journey-photo.com/qr?t=a%2Fb",
                     "https://journey-photo.com/qr/abc",
                     "https://journey-photo.com/q?t=abc"] {
            XCTAssertNil(ProfileQRLink.parse(text, base: base), text)
        }
        // 合図は人の id としては読まない（引かずに人の頁を開かない）
        XCTAssertNil(ProfileQR.userId(from: "https://journey-photo.com/qr?t=abc", base: base))
        XCTAssertEqual(ProfileQRScanResult.of("https://journey-photo.com/qr?t=abc", myUserId: uid, base: base), .pass("abc"))
    }

    /// カメラの使い道の説明に QR の読み取りを書く（審査 5.1.1・アプリの中で QR を読むため）
    func testCameraUsageMentionsQR() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        let line = try XCTUnwrap(yml.components(separatedBy: "\n").first { $0.contains("NSCameraUsageDescription:") })
        XCTAssertTrue(line.contains("プロフィールの QR を読み取る"), line)
        for (lang, word) in [("ja", "プロフィールの QR を読み取る"), ("en", "scan profile QR codes")] {
            let strings = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/\(lang).lproj/InfoPlist.strings"),
                                     encoding: .utf8)
            let entry = try XCTUnwrap(strings.components(separatedBy: "\n").first { $0.hasPrefix("\"NSCameraUsageDescription\"") })
            XCTAssertTrue(entry.contains(word), "\(lang): \(entry)")
        }
    }

    /// 合図を引いた結果も人の id と同じ所で決める。引けない（古い・取り消された）は人を開かない
    func testResolvedPass() {
        XCTAssertEqual(ProfileQRScanResult.resolved("someone", myUserId: uid), .person("someone"))
        XCTAssertEqual(ProfileQRScanResult.resolved(uid, myUserId: uid), .mine)
        XCTAssertEqual(ProfileQRScanResult.resolved(nil, myUserId: uid), .other)
    }

    /// 今の中身は仮の実装: 公開プロフィールの URL・合図は引けない・更新は出さない
    func testCurrentSourceIsPublicProfileURL() async throws {
        let source = PublicProfileQRSource(base: base)
        let url = try await source.code(for: uid)
        XCTAssertEqual(url.absoluteString, "https://journey-photo.com/users?id=\(uid)")
        do {
            _ = try await source.code(for: "a/b")
            XCTFail("URL に入れられない id で中身を作った")
        } catch {
            XCTAssertEqual(error as? ProfileQRSourceError, .cannotMake)
        }
        let resolved = try await source.resolve(pass: "abc")
        XCTAssertNil(resolved)
        XCTAssertFalse(source.canRenew)
        // アプリが使うのは今はこの仮の実装（Linux の試験では AppConfig を読めないので文で見る）
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Core/Text/ProfileQR.swift"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("static let current: any ProfileQRSource = PublicProfileQRSource()"))
    }

    func testWordsAreJapaneseFirstAndNoBannedWords() {
        for text in [ProfileQRText.title, ProfileQRText.showTab, ProfileQRText.scanTab, ProfileQRText.showHint,
                     ProfileQRText.scanHint, ProfileQRText.notOurs, ProfileQRText.yours, ProfileQRText.denied,
                     ProfileQRText.retry, ProfileQRText.loading, ProfileQRText.passNotValid] {
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
        // 中身は ProfileQRSource の1か所だけが作る（あとで更新できる合図に替える・2026-11-12 owner）
        XCTAssertTrue(view.contains("try await source.code(for: profile.userId)"))
        XCTAssertFalse(view.contains("ProfileQR.url("), "画面が中身を直に作っている")
        XCTAssertTrue(view.contains("source: any ProfileQRSource = ProfileQRSources.current"))
        XCTAssertTrue(view.contains("output.metadataObjectTypes = [.qr]"))
        // 読み取りを離れた（取り消された）あとにカメラを点けない・点いたら止める（2026-11-12 確かめ役）
        let start = try XCTUnwrap(view.components(separatedBy: "func start() async {").dropFirst().first)
            .components(separatedBy: "func stop()").first ?? ""
        let beforeRun = try XCTUnwrap(start.range(of: "guard !Task.isCancelled else { return }"), "点ける前に取り消しを見ていない")
        let run = try XCTUnwrap(start.range(of: "let ok = await run()"))
        let after = try XCTUnwrap(start.range(of: "if Task.isCancelled {\n            stop()"), "点けたあとに取り消しを見て止めていない")
        XCTAssertLessThan(beforeRun.lowerBound, run.lowerBound)
        XCTAssertLessThan(run.lowerBound, after.lowerBound)
        // 外のサイトを開かない（読み取った文字で openURL しない）
        XCTAssertFalse(view.contains("openURL(URL(string: code"))
    }
}
