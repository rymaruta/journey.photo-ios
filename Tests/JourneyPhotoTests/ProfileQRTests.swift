import XCTest
@testable import JourneyPhoto

/// プロフィールの QR（札 #545・段1・2026-11-11）。
///
/// - QR の中身は Web の人の頁 `https://journey-photo.com/users/<id>`
/// - 読んだ中身は Journey Photo の人の頁だけを開く（自分の QR・ほかのサイトは開かない）
/// - 出す・読むは1つの画面（owner 2026-11-11）。開いただけではカメラの許可を聞かない
/// - 入口は設定の「公開範囲とプライバシー」の先頭1つ。マイページの見た目は変えない
final class ProfileQRTests: XCTestCase {

    private let base = URL(string: "https://journey-photo.com")!
    private let staging = URL(string: "https://d15fn3rcaiymu9.cloudfront.net")!
    private let id = "d7e4da78-30f1-7003-a761-6b1238e64ab3"

    // MARK: - QR の中身

    func testURLIsTheWebProfilePage() {
        XCTAssertEqual(ProfileQR.url(userId: id, base: base)?.absoluteString,
                       "https://journey-photo.com/users/\(id)")
        XCTAssertEqual(ProfileQR.url(userId: " \(id)\n", base: base)?.absoluteString,
                       "https://journey-photo.com/users/\(id)", "前後の空白を残している")
        XCTAssertEqual(ProfileQR.url(userId: id, base: staging)?.absoluteString,
                       "https://d15fn3rcaiymu9.cloudfront.net/users/\(id)", "接続先のサイトで組んでいない")
    }

    /// URL を壊す字・空の ID では作らない（`/users/` だけの QR を出さない）
    func testURLRejectsBrokenIds() {
        XCTAssertNil(ProfileQR.url(userId: "", base: base))
        XCTAssertNil(ProfileQR.url(userId: "a/b", base: base))
        XCTAssertNil(ProfileQR.url(userId: "a?b", base: base))
        XCTAssertNil(ProfileQR.url(userId: "../x", base: base))
        XCTAssertNil(ProfileQR.url(userId: String(repeating: "a", count: 129), base: base))
    }

    func testShortLabelShowsOnlyTheSite() {
        let url = ProfileQR.url(userId: id, base: base)!
        XCTAssertEqual(ProfileQR.shortLabel(url), "journey-photo.com/users/…")
    }

    // MARK: - 読む

    func testReadsAProfileLink() {
        XCTAssertEqual(ProfileQR.read("https://journey-photo.com/users/\(id)", base: base, viewerId: "me"),
                       .profile(userId: id))
        // 末尾の / ・問い合わせ・印・www・http・大文字の名前
        for text in ["https://journey-photo.com/users/\(id)/", "https://journey-photo.com/users/\(id)?utm=qr",
                     "https://journey-photo.com/users/\(id)#top", "https://www.journey-photo.com/users/\(id)",
                     "http://journey-photo.com/users/\(id)", "HTTPS://Journey-Photo.com/users/\(id)",
                     "  https://journey-photo.com/users/\(id)\n"] {
            XCTAssertEqual(ProfileQR.read(text, base: base, viewerId: nil), .profile(userId: id), text)
        }
    }

    /// 自分の QR は開かずに「あなたの QR です」
    func testOwnCodeIsNotOpened() {
        XCTAssertEqual(ProfileQR.read("https://journey-photo.com/users/\(id)", base: base, viewerId: id), .mine)
        XCTAssertEqual(ProfileQR.message(for: .mine), L("これはあなたの QR です", "This is your QR code"))
        XCTAssertNil(ProfileQR.message(for: .profile(userId: id)), "人の頁を開くのに一言を出している")
    }

    /// ほかのサイト・写真の頁・招待・文字だけ・別の形の道は開かない
    func testOtherCodesAreNotOpened() {
        for text in ["https://example.com/users/\(id)", "https://journey-photo.com.evil.example/users/\(id)",
                     "https://journey-photo.com/photos/abc", "https://journey-photo.com/j?t=token",
                     "https://journey-photo.com/users/", "https://journey-photo.com/users/\(id)/followers",
                     "https://journey-photo.com/users/a%2Fb", "journey-photo.com/users/\(id)",
                     "ftp://journey-photo.com/users/\(id)", "こんにちは", ""] {
            XCTAssertEqual(ProfileQR.read(text, base: base, viewerId: nil), .other, text)
        }
        XCTAssertNotNil(ProfileQR.message(for: .other))
    }

    /// staging のアプリは staging のサイトの QR も読む（本番の QR も読める）
    func testStagingSiteIsAccepted() {
        XCTAssertEqual(ProfileQR.read("https://d15fn3rcaiymu9.cloudfront.net/users/\(id)", base: staging, viewerId: nil),
                       .profile(userId: id))
        XCTAssertEqual(ProfileQR.read("https://journey-photo.com/users/\(id)", base: staging, viewerId: nil),
                       .profile(userId: id))
        XCTAssertEqual(ProfileQR.read("https://d15fn3rcaiymu9.cloudfront.net/users/\(id)", base: base, viewerId: nil),
                       .other, "本番のアプリが staging の QR を開く")
    }

    /// 出した QR を読むと、同じ人が返る（出す・読むの往復）
    func testRoundTrip() {
        let url = ProfileQR.url(userId: id, base: base)!
        XCTAssertEqual(ProfileQR.read(url.absoluteString, base: base, viewerId: "someone"), .profile(userId: id))
        XCTAssertEqual(ProfileQR.read(url.absoluteString, base: base, viewerId: id), .mine)
    }

    // MARK: - カメラの小窓

    /// 開いただけでは聞かない: まだ聞いていなければ許可のボタン。許可済みならそのまま読む
    func testCameraStateDoesNotAskOnOpen() {
        XCTAssertEqual(ProfileQR.cameraState(hasCamera: true, permission: .notDetermined), .needsPermission)
        XCTAssertEqual(ProfileQR.cameraState(hasCamera: true, permission: .authorized), .scanning)
        XCTAssertEqual(ProfileQR.cameraState(hasCamera: true, permission: .denied), .denied)
        XCTAssertEqual(ProfileQR.cameraState(hasCamera: true, permission: .restricted), .denied)
        XCTAssertEqual(ProfileQR.cameraState(hasCamera: false, permission: .authorized), .unavailable)
        XCTAssertEqual(ProfileQR.cameraState(hasCamera: false, permission: .notDetermined), .unavailable)
    }

    func testCameraNotesAndActions() {
        XCTAssertEqual(ProfileQR.cameraNote(.needsPermission),
                       L("カメラを使うと相手の QR を読めます", "Use the camera to scan someone's QR code"))
        XCTAssertEqual(ProfileQR.cameraAction(.needsPermission), L("カメラを使う", "Use camera"))
        XCTAssertEqual(ProfileQR.cameraAction(.denied), L("設定を開く", "Open Settings"))
        XCTAssertNil(ProfileQR.cameraNote(.scanning), "映像の上に案内を重ねている")
        XCTAssertNil(ProfileQR.cameraAction(.scanning))
        XCTAssertNil(ProfileQR.cameraAction(.unavailable), "カメラが無いのにボタンを出している")
        XCTAssertNotNil(ProfileQR.cameraNote(.unavailable))
        XCTAssertNotNil(ProfileQR.cameraNote(.denied))
    }

    // MARK: - 明るさ

    func testBrightnessIsRaisedOnceAndRestoredOnce() {
        var b = ProfileQRBrightness()
        XCTAssertEqual(b.raise(current: 0.3), 1.0)
        // 上げている間に（コントロールセンターで）少し下げられても、元の明るさは最初のまま
        XCTAssertNil(b.raise(current: 0.8), "上げたあとにもう一度上げて、元の明るさを上書きした")
        XCTAssertEqual(b.restore(), 0.3)
        XCTAssertNil(b.restore(), "2度戻している")
        // 裏から戻って、また上げる
        XCTAssertEqual(b.raise(current: 0.5), 1.0)
        XCTAssertEqual(b.restore(), 0.5)
    }

    func testBrightnessAlreadyFullIsLeftAlone() {
        var b = ProfileQRBrightness()
        XCTAssertNil(b.raise(current: 1.0))
        XCTAssertNil(b.restore(), "上げていないのに戻している")
    }

    // MARK: - 人のプロフィールの「…」

    func testUserProfileMenu() {
        XCTAssertTrue(UserProfileMenu.showsMenu(viewerId: "me", userId: id, blocked: false))
        XCTAssertTrue(UserProfileMenu.showsMenu(viewerId: nil, userId: id, blocked: false), "未ログインで共有できない")
        XCTAssertFalse(UserProfileMenu.showsMenu(viewerId: id, userId: id, blocked: false), "自分の頁に出している")
        XCTAssertFalse(UserProfileMenu.showsMenu(viewerId: "me", userId: id, blocked: true), "ブロック中に出している")
    }

    // MARK: - 画面のつなぎ（画面は Linux で描けないので、元のファイルで縛る）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
    }

    /// 出す（QR）と読む（小窓）が同じ画面にある（2026-11-11 owner）
    func testShowAndScanLiveOnOneScreen() throws {
        let view = try source("Features/Profile/ProfileQRView.swift")
        let body = try XCTUnwrap(view.components(separatedBy: "var body: some View {").dropFirst().first)
        let top = try XCTUnwrap(body.components(separatedBy: "// MARK:").first)
        XCTAssertTrue(top.contains("mine\n            reader"), "自分の QR と読む小窓が同じ画面に並んでいない")
        for id in ["profileQR.code", "profileQR.scanner", "profileQR.share", "profileQR.save"] {
            XCTAssertTrue(view.contains(".accessibilityIdentifier(\"\(id)\")"), "\(id) が無い")
        }
        XCTAssertTrue(view.contains("ProfileQRCode.image(for: link.absoluteString)"), "QR の中身が人の頁の URL でない")
        XCTAssertTrue(view.contains(".interpolation(.none)"), "QR をぼかして広げている")
        XCTAssertTrue(view.contains("UserProfileView(userId: id)"), "読んだ相手のプロフィールを開いていない")
    }

    /// 開いただけでは許可を聞かない。聞くのは「カメラを使う」を押したときだけ
    func testCameraPermissionIsAskedOnlyOnTap() throws {
        let scanner = try source("Features/Profile/ProfileQRScanner.swift")
        let prepare = try XCTUnwrap(scanner.components(separatedBy: "func prepare(").dropFirst().first?
            .components(separatedBy: "func requestAccess()").first)
        XCTAssertFalse(prepare.contains("requestAccess"), "開いただけで許可を聞いている")
        XCTAssertEqual(scanner.components(separatedBy: "AVCaptureDevice.requestAccess(for: .video)").count, 2,
                       "許可を聞く所が「カメラを使う」の1か所でない")
        let view = try source("Features/Profile/ProfileQRView.swift")
        XCTAssertEqual(view.components(separatedBy: "scanner.requestAccess()").count, 2)
        let action = try XCTUnwrap(view.components(separatedBy: "private func cameraAction()").dropFirst().first)
        XCTAssertTrue(action.contains("case .needsPermission:\n            Task { @MainActor in await scanner.requestAccess() }"))
        // 読むのは QR だけ・1回読んだら止める
        XCTAssertTrue(scanner.contains("output.metadataObjectTypes = [.qr]"))
        XCTAssertTrue(scanner.contains("guard !delivered, state == .scanning else { return }"))
    }

    /// 明るさは開いている間だけ（離れる・裏に回ると戻す）
    func testBrightnessFollowsTheScreen() throws {
        let view = try source("Features/Profile/ProfileQRView.swift")
        XCTAssertTrue(view.contains(".onAppear { raiseBrightness() }"))
        let disappear = try XCTUnwrap(view.components(separatedBy: ".onDisappear {").dropFirst().first)
        XCTAssertTrue(disappear.hasPrefix("\n            restoreBrightness()\n            scanner.stop()"),
                      "離れても明るさ・カメラを戻していない")
        XCTAssertTrue(view.contains("if phase == .active { raiseBrightness() } else { restoreBrightness() }"))
    }

    /// 入口は設定の「公開範囲とプライバシー」の先頭1つ。マイページには置かない（見た目を変えない決まり）
    func testEntryIsInSettingsOnly() throws {
        XCTAssertEqual(SettingsOutline.Part.privacy.items.first, "settings.profileQR")
        let settings = try source("Features/Settings/SettingsView.swift")
        let privacy = try XCTUnwrap(settings.components(separatedBy: "private var privacySection: some View {")
            .dropFirst().first?.components(separatedBy: "private var photosSection").first)
        let qr = try XCTUnwrap(privacy.range(of: "ProfileQRView(profile: myProfile)"))
        let blocked = try XCTUnwrap(privacy.range(of: "BlockedUsersView()"))
        XCTAssertLessThan(qr.lowerBound, blocked.lowerBound, "プロフィールの QR が札の先頭でない")
        XCTAssertTrue(privacy.contains(".accessibilityIdentifier(\"settings.profileQR\")"))
        let myPage = try source("Features/Profile/MyPageView.swift")
        XCTAssertFalse(myPage.contains("ProfileQRView"), "マイページに入口を置いた（見た目を変えない決まり）")
        // 入口は1つ（どこから来ても同じ画面）
        var count = 0
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            count += text.components(separatedBy: "ProfileQRView(profile:").count - 1
        }
        XCTAssertEqual(count, 1, "プロフィールの QR の入口が1つでない")
    }

    /// 人のプロフィールの「…」に共有。通報・ブロックはログインして操作できるときだけ
    func testUserProfileShare() throws {
        let view = try source("Features/Profile/UserProfileView.swift")
        let toolbar = try XCTUnwrap(view.components(separatedBy: "private var toolbarItems: some ToolbarContent {")
            .dropFirst().first?.components(separatedBy: "private var shownPhotos").first)
        XCTAssertTrue(toolbar.contains("if showsMenu {"))
        let share = try XCTUnwrap(toolbar.range(of: "ProfileQR.url(userId: userId, base: AppConfig.siteBaseURL)"))
        let gate = try XCTUnwrap(toolbar.range(of: "if canAct {"))
        let report = try XCTUnwrap(toolbar.range(of: "reportProfile()"))
        XCTAssertLessThan(share.lowerBound, gate.lowerBound, "共有が通報・ブロックの出し分けの中にある")
        XCTAssertLessThan(gate.lowerBound, report.lowerBound, "通報が未ログインでも出る")
        XCTAssertTrue(toolbar.contains(".accessibilityIdentifier(\"profile.share\")"))
    }
}
