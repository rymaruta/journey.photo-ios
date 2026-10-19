import XCTest
@testable import JourneyPhoto

/// 設定の並べ直し（2026-10-18 owner「設定の項目多くなってるのでわかりやすいように整理して」
/// 「キャンピングカーなどの入口は基本的に設定の中に入れたい」）。
///
/// 画面は Linux では描けないので、並びは `SettingsOutline`（値）と元のファイル（作り）の両方で見張る。
/// - 前にあった行が1つも消えていない（場所を移しただけ）
/// - 節の順・節の中の行の順が `SettingsOutline` のとおり
/// - 旅の道具にトランク（口があるときだけ）とキャンピングカーの入口。キャンピングカーは設定から開くと自分で写真を読む
/// - 危ない操作（ログアウト・アカウントの削除）は最後に、別々の札で、危険の色
final class SettingsOutlineTests: XCTestCase {

    // MARK: - 読む道具

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ text: String, from start: String, to end: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let a = text.range(of: start) else {
            XCTFail("「\(start)」が無い", file: file, line: line)
            return ""
        }
        guard let b = text.range(of: end, range: a.upperBound..<text.endIndex) else {
            XCTFail("「\(start)」の後に「\(end)」が無い", file: file, line: line)
            return ""
        }
        return String(text[a.lowerBound..<b.lowerBound])
    }

    private func assertInOrder(_ parts: [String], in text: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: cursor..<text.endIndex) else {
                XCTFail("\(what): 「\(part)」が無いか、順が違う", file: file, line: line)
                return
            }
            cursor = found.upperBound
        }
    }

    private func id(_ name: String) -> String { ".accessibilityIdentifier(\"\(name)\")" }

    /// 行の目印が置かれているファイル（設定の画面と、設定に札を出す部品）
    private func settingsSources() throws -> String {
        try ["Features/Settings/SettingsView.swift", "Features/Settings/TrunkPrivacySection.swift",
             "Features/Pro/ProSettingsSection.swift", "Features/Pro/LightAlertSettingsRows.swift",
             "Features/Trips/OfflineSavedView.swift"].map(source).joined(separator: "\n")
    }

    // MARK: - 並び（値）

    /// いちばん上の節の順（2026-10-18 判断）。危ない操作がいちばん下
    func testOutlineOrder() {
        XCTAssertEqual(SettingsOutline.Part.allCases,
                       [.pro, .tripTools, .notifications, .privacy, .photos, .help, .account, .danger])
        XCTAssertEqual(SettingsOutline.Part.allCases.last, .danger)
        XCTAssertNil(SettingsOutline.Part.danger.title, "危ない操作の札に眉ラベルを付けている")
        XCTAssertEqual(SettingsOutline.Part.tripTools.items,
                       ["settings.trunk", "settings.camper", "settings.pass", "settings.passBook",
                        "settings.albums", "settings.plans"])
        XCTAssertEqual(SettingsOutline.Part.danger.items, ["settings.logout", "settings.deleteAccount"])
        // 目印は重ならない
        let all = SettingsOutline.Part.allCases.flatMap(\.items) + SettingsOutline.subpages.values.flatMap { $0 }
        XCTAssertEqual(Set(all).count, all.count, "同じ目印が2か所にある")
    }

    /// いちばん上は一目で見渡せる長さ: 節は 8 つまで・どの節も 6 行まで（長いものは下の画面へ）
    func testTopLevelStaysShort() {
        XCTAssertLessThanOrEqual(SettingsOutline.Part.allCases.count, 8)
        for part in SettingsOutline.Part.allCases {
            XCTAssertLessThanOrEqual(part.items.count, 6, "\(part) の節が長い")
        }
        // 長かった2つ（トランクの見本・控え）は下の画面
        XCTAssertEqual(SettingsOutline.subpages["settings.trunkPrivacy"],
                       ["settings.showTrunk", "settings.ticketInTrunk", "settings.showTrunk.preview"])
        XCTAssertEqual(SettingsOutline.subpages["settings.storage"], ["settings.cache", "settings.clearCache"])
    }

    /// 入切の値は文字で言う（色だけで状態を伝えない）
    func testOnOffIsSpelledOut() {
        XCTAssertFalse(SettingsOutline.onOff(true).isEmpty)
        XCTAssertNotEqual(SettingsOutline.onOff(true), SettingsOutline.onOff(false))
    }

    // MARK: - 消えていない（作り）

    /// 並べ直す前（origin/main 9672987f）の設定にあった行が、全部どこかに残っている
    func testNoRowWasRemoved() throws {
        let settings = try settingsSources()
        let before = [
            "L(\"プッシュ通知を受け取る\"", "PassTicket.featureName", "TrunkEntryText.title",
            "L(\"ブロックした人\"", "L(\"親しい友達\"", "L(\"トランクを見せる\"", "L(\"わたしの乗車券もトランクに入れる\"",
            "Labels.Navigation.favorites", "Labels.Navigation.albums", "L(\"構図一覧\"", "L(\"写真の控え\"",
            "L(\"控えを空にする\"", "L(\"パスワードを変える\"", "L(\"新しくなったこと\"",
            "L(\"利用規約・プライバシーポリシー\"", "L(\"問い合わせ\"", "L(\"アカウントの削除\"", "Labels.Navigation.logout",
            "TrunkPrivacyPreview(model:", "ProSettingsSection(profile: myProfile)",
        ]
        for row in before {
            XCTAssertTrue(settings.contains(row), "設定から「\(row)」の行が消えた")
        }
        // 行き先の画面も全部つながっている
        let view = try source("Features/Settings/SettingsView.swift")
        for destination in ["PassSettingsView()", "TrunkView(ownerName:", "BlockedUsersView()", "CloseFriendsView()",
                            "FavoritesView()", "AlbumsView()", "CompositionCatalogView()", "ChangePasswordView()",
                            "LegalLinksView()", "DeleteAccountView(profile: myProfile)", "SettingsTrunkPrivacyPage(",
                            "SettingsStoragePage()", "CamperGarageLoader(", "PassBookView()", "TripPlansView()",
                            "showWhatsNew = true", "Link(destination: contact)", "auth.startSigningOut {"] {
            XCTAssertTrue(view.contains(destination), "設定から「\(destination)」へ行けない")
        }
    }

    /// `SettingsOutline` の目印は全部、画面のどこかに置かれている（並びの表と画面がずれない）
    func testEveryOutlineIdIsWired() throws {
        let settings = try settingsSources()
        let all = SettingsOutline.Part.allCases.flatMap(\.items) + SettingsOutline.subpages.values.flatMap { $0 }
        for name in all {
            XCTAssertTrue(settings.contains(id(name)), "「\(name)」の目印が画面に無い")
        }
    }

    // MARK: - 並び（作り）

    /// 画面の節の順が `SettingsOutline` のとおり
    func testScreenFollowsTheOutline() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let list = slice(view, from: "private var list: some View {", to: "Text(versionLine)")
        assertInOrder(["ProSettingsSection(profile: myProfile)", "tripToolsSection", "notificationsSection",
                       "privacySection", "photosSection", "helpSection", "accountSection", "logoutSection",
                       "deleteSection"], in: list, "設定の節の順")
        // 節の中の行の順
        let tools = slice(view, from: "private var tripToolsSection: some View {", to: "private var passRow")
        assertInOrder(["SettingsOutline.Part.tripTools.title", "trunkRow", "camperRow", "passRow",
                       id("settings.passBook"), id("settings.albums"), id("settings.plans")], in: tools, "旅の道具の順")
        let privacy = slice(view, from: "private var privacySection: some View {", to: "private var photosSection")
        assertInOrder(["SettingsOutline.Part.privacy.title", id("settings.blocked"), id("settings.closeFriends"),
                       "if showsTrunkPrivacy {", id("settings.trunkPrivacy")], in: privacy, "プライバシーの順")
        let photos = slice(view, from: "private var photosSection: some View {", to: "private var helpSection")
        assertInOrder(["SettingsOutline.Part.photos.title", id("settings.favorites"), id("settings.compositionCatalog"),
                       id("settings.storage")], in: photos, "写真と撮影の順")
        let help = slice(view, from: "private var helpSection: some View {", to: "private var accountSection")
        assertInOrder(["SettingsOutline.Part.help.title", id("settings.whatsNew"), id("settings.legal"),
                       id("settings.contact")], in: help, "ヘルプと規約の順")
        // ヘルプと規約・構図一覧は未ログインでも出す（審査 1.2 の連絡先）
        let signedOut = slice(list, from: "privacySection\n                }", to: "if auth.userId != nil {")
        assertInOrder(["photosSection", "helpSection"], in: signedOut, "未ログインでも出す節")
        // 長い見本はいちばん上に置かない
        XCTAssertFalse(list.contains("TrunkPrivacyPreview("), "トランクの見本がいちばん上の画面に戻った")
        XCTAssertFalse(list.contains("TrunkShowRow("))
    }

    // MARK: - 旅の道具の入口

    /// トランクは口があるときだけ（今の決まりのまま）。出さないときは区切り線も出さない
    func testTrunkRowOnlyWhenAvailable() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let row = slice(view, from: "private var trunkRow: some View {", to: "private func note(")
        assertInOrder(["if TrunkEntryRule.shows(signedIn: auth.userId != nil, available: trunkAvailability.isAvailable) {",
                       "TrunkView(ownerName: myProfile?.name)", id("settings.trunk"), "JPCardDivider()"],
                      in: row, "旅のトランクの行")
        XCTAssertTrue(TrunkEntryRule.shows(signedIn: true, available: true))
        XCTAssertFalse(TrunkEntryRule.shows(signedIn: true, available: false))
    }

    /// キャンピングカー: 設定からは自分で写真を読む入れ物を通す。マイページの行は残し、読んだ写真を渡す（二重に読まない）
    func testCamperEntryWiring() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let row = slice(view, from: "private var camperRow: some View {", to: "private var trunkRow")
        assertInOrder(["CamperGarageLoader(ownerName: myProfile?.name, userId: auth.userId)",
                       "L(\"写真で作るキャンピングカー\"", "CamperText.carName", id("settings.camper")],
                      in: row, "キャンピングカーの行")
        XCTAssertFalse(row.contains("systemImage:"), "設定の行に絵を出している")
        let loader = try source("Features/Camper/CamperGarageLoader.swift")
        assertInOrder(["CamperGarageView(ownerName: ownerName, userId: userId, photos: photos,",
                       "photosLoaded: CamperLoaderRule.isLoaded(loadedFor: loadedFor, userId: userId))",
                       "ProfileImageFromPhoto.myPhotos(environment: environment)", "photos = fresh",
                       "loadedFor = userId"], in: loader, "設定からのキャンピングカー")
        // マイページの「旅の記録」の行はそのまま（読み終えた写真を渡す）
        let page = try source("Features/Profile/MyPageView.swift")
        let card = slice(page, from: "private var tripToolsCard: some View {", to: "nonisolated static func wishlistPool")
        assertInOrder(["CamperGarageView(ownerName: model.profile?.name, userId: auth.userId, photos: model.photos,",
                       "photosLoaded: model.hasLoadedPhotos)", id("trips.camper")], in: card, "マイページのキャンピングカー")
        XCTAssertFalse(card.contains("CamperGarageLoader("), "マイページで写真を二重に読む")
        for name in ["trips.trunk", "trips.albums", "trips.plans", "trips.passBook"] {
            XCTAssertTrue(card.contains(id(name)), "マイページの「\(name)」の行が消えた")
        }
    }

    /// 読めるまでは「読めた」にしない（「届いた」の判定・保存の守り）。人が替わったら読み直すまで false
    func testCamperLoaderRule() {
        XCTAssertFalse(CamperLoaderRule.isLoaded(loadedFor: nil, userId: "me"), "読む前に読めたことにしている")
        XCTAssertTrue(CamperLoaderRule.isLoaded(loadedFor: "me", userId: "me"))
        XCTAssertFalse(CamperLoaderRule.isLoaded(loadedFor: "me", userId: "other"), "前の人の写真で数える")
        XCTAssertFalse(CamperLoaderRule.isLoaded(loadedFor: nil, userId: nil))
    }

    // MARK: - 危ない操作

    /// ログアウトとアカウントの削除は最後に、別々の札で、名前ごと危険の色
    func testDangerRowsAreLastAndApart() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let logout = slice(view, from: "private var logoutSection: some View {", to: "private var deleteSection")
        assertInOrder(["section(nil) {", "auth.startSigningOut {", "SettingsActionLabel(", "color: WebTheme.danger)",
                       id("settings.logout")], in: logout, "ログアウト")
        XCTAssertFalse(logout.contains("DeleteAccountView"), "ログアウトと削除が同じ札にある")
        let delete = slice(view, from: "private var deleteSection: some View {", to: "enum SettingsOutline")
        assertInOrder(["section(nil) {", "DeleteAccountView(profile: myProfile)", "color: WebTheme.danger",
                       id("settings.deleteAccount")], in: delete, "アカウントの削除")
        XCTAssertFalse(view.contains("role: .destructive"), "系統の赤を画面の行に出している")
    }

    /// 下の画面は設定と同じ形（明朝の大見出し・眉ラベルの節・黒地）。控えを空にするは真鍮の字
    func testSubpagesShareTheSettingsLook() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let page = slice(view, from: "struct SettingsPage<Content: View>: View {", to: "struct SettingsTrunkPrivacyPage")
        assertInOrder(["JPFont.display(SettingsLayout.titleSize, relativeTo: .largeTitle)", ".accessibilityAddTraits(.isHeader)",
                       "content", ".webScreen()", ".navigationTitle(title)"], in: page, "下の画面の形")
        let trunk = slice(view, from: "struct SettingsTrunkPrivacyPage: View {", to: "struct SettingsStoragePage")
        assertInOrder(["TrunkShowRow(model: model, service: environment.trunk)",
                       "TrunkPrivacyPreview(model: model, profile: profile, userId: userId)"], in: trunk, "トランクを見せる")
        let storage = slice(view, from: "struct SettingsStoragePage: View {", to: "enum SettingsLayout")
        assertInOrder(["URLCache.shared.removeAllCachedResponses()",
                       "SettingsActionLabel(title: L(\"控えを空にする\", \"Clear cache\"), color: WebTheme.accent)"],
                      in: storage, "データとストレージ")
    }
}
