import XCTest
@testable import JourneyPhoto

/// 設定の並べ直し（2026-10-18 owner「設定の項目多くなってるのでわかりやすいように整理して」
/// 「キャンピングカーなどの入口は基本的に設定の中に入れたい」）。
///
/// 画面は Linux では描けないので、並びは `SettingsOutline`（値）と元のファイル（作り）の両方で見張る。
/// - 前にあった行が1つも消えていない（場所を移しただけ）
/// - 節の順・節の中の行の順が `SettingsOutline` のとおり
/// - 2026-11-12（案 第10章）: 旅の道具（トランク・キャンピングカー・すれちがい帳・アルバム・旅行プラン）は ≡ メニューへ移した。
///   トランクは口があるときだけ（`SiteMenuView`）。キャンピングカーは 2026-11-23 に消した（札 #709）。
///   すれちがい乗車券の入り切りは「公開範囲とプライバシー」
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
        try ["Features/Settings/SettingsView.swift", "Features/Settings/NotificationSettings.swift",
             "Features/Settings/TrunkPrivacySection.swift",
             "Features/Pro/ProSettingsSection.swift", "Features/Pro/LightAlertSettingsRows.swift",
             "Features/Trips/OfflineSavedView.swift",
             "Features/Settings/SearchHiddenSettingRow.swift"].map(source).joined(separator: "\n")
    }

    /// 設定と、設定から移した道具の置き場（≡ メニュー・2026-11-12）
    private func settingsAndMenuSources() throws -> String {
        try settingsSources() + "\n" + source("Features/Common/SiteMenuView.swift")
    }

    // MARK: - 並び（値）

    /// いちばん上の節の順（2026-10-18 判断）。危ない操作がいちばん下
    func testOutlineOrder() {
        // 2026-11-12: 「旅の道具」の節は ≡ メニューへ（設定はオン・オフと決まりだけ）
        XCTAssertEqual(SettingsOutline.Part.allCases,
                       [.notifications, .pro, .privacy, .photos, .help, .account, .danger])
        // 2026-11-18 判断（案 B7）: お知らせがいちばん上
        XCTAssertEqual(SettingsOutline.Part.allCases.first, .notifications)
        XCTAssertEqual(SettingsOutline.Part.allCases.last, .danger)
        XCTAssertNil(SettingsOutline.Part.danger.title, "危ない操作の札に眉ラベルを付けている")
        XCTAssertEqual(SettingsOutline.Part.privacy.items,
                       ["settings.blocked", "settings.closeFriends", "settings.pass", "settings.trunkPrivacy",
                        "settings.searchHidden"])
        XCTAssertEqual(SettingsOutline.Part.photos.items, ["settings.compositionCatalog", "settings.storage"])
        // 道具の行は設定に無い（≡ にある）
        let topLevel = SettingsOutline.Part.allCases.flatMap(\.items)
        for moved in ["settings.trunk", "settings.camper", "settings.passBook", "settings.albums", "settings.plans",
                      "settings.favorites"] {
            XCTAssertFalse(topLevel.contains(moved), "\(moved) が設定に残っている（≡ へ移した）")
        }
        XCTAssertEqual(SettingsOutline.Part.danger.items, ["settings.logout", "settings.deleteAccount"])
        // 目印は重ならない
        let all = SettingsOutline.Part.allCases.flatMap(\.items) + SettingsOutline.subpages.values.flatMap { $0 }
        XCTAssertEqual(Set(all).count, all.count, "同じ目印が2か所にある")
    }

    /// いちばん上は一目で見渡せる長さ: 節は 8 つまで・どの節も 6 行まで（長いものは下の画面へ）。
    /// 旅の道具はキャンプ場を外したので 6 行（#339・2026-10-20）
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
        XCTAssertEqual(SettingsOutline.onOff(true), L("オン", "On"))
        XCTAssertEqual(SettingsOutline.onOff(false), L("オフ", "Off"))
    }

    /// 「トランクを見せる」の行の値はいまの入切（設定が読んだ同じ model）。下の画面には同じ model を渡す
    func testTrunkPrivacyRowShowsTheCurrentValue() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let privacy = slice(view, from: "private var privacySection: some View {", to: "private var photosSection")
        assertInOrder(["SettingsTrunkPrivacyPage(model: trunkPrivacy, profile: myProfile, userId: auth.userId)",
                       "value: SettingsOutline.onOff(trunkPrivacy.showTrunk))", id("settings.trunkPrivacy")],
                      in: privacy, "トランクを見せるの行")
        // 設定が持つ model は1つ（下の画面で作り直さない）
        let page = slice(view, from: "struct SettingsTrunkPrivacyPage: View {", to: "struct SettingsStoragePage")
        XCTAssertTrue(page.contains("@ObservedObject var model: TrunkPrivacyModel"))
        XCTAssertFalse(page.contains("TrunkPrivacyModel()"), "下の画面が別の model を作る")
    }

    /// 下の画面（データとストレージ）で控えを空にして戻ったら、いちばん上の行の値を読み直す
    func testCacheSizeIsReadAgainOnReturn() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let list = slice(view, from: "private var list: some View {", to: "private func section<")
        XCTAssertTrue(list.contains(".onAppear { cacheSize = Self.formattedCacheSize() }"),
                      "下の画面から戻っても控えの大きさが古いまま")
        let photos = slice(view, from: "private var photosSection: some View {", to: "private var helpSection")
        XCTAssertTrue(photos.contains("detail: L(\"写真の控え\", \"Cached photos\"), value: cacheSize)"))
    }

    /// いいねした写真は ≡ メニューだけ（2026-11-12・ログインしているときだけ）。構図一覧・データとストレージは設定にいつも
    func testFavoritesOnlyInTheMenu() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let photos = slice(view, from: "private var photosSection: some View {", to: "private var helpSection")
        XCTAssertFalse(photos.contains("FavoritesView()"), "いいねした写真が設定にも残っている（≡ と重なる）")
        XCTAssertFalse(photos.contains("if auth.userId != nil {"), "データとストレージ・構図一覧を未ログインで隠している")
        assertInOrder(["CompositionCatalogView()", id("settings.compositionCatalog"), "SettingsStoragePage()",
                       id("settings.storage")], in: photos, "写真と撮影")
        let menu = try source("Features/Common/SiteMenuView.swift")
        assertInOrder(["if auth.userId != nil {", "FavoritesView()", "\"menu.favorites\""], in: menu, "≡ のいいねした写真")
    }

    // MARK: - 消えていない（作り）

    /// 並べ直す前（origin/main 9672987f）の設定にあった行が、全部どこかに残っている
    func testNoRowWasRemoved() throws {
        // 2026-11-12: 道具の行は ≡ メニューへ移した（消していない）ので、設定と ≡ を合わせて見る
        let settings = try settingsAndMenuSources()
        let before = [
            "L(\"プッシュ通知を受け取る\"", "PassTicket.featureName", "TrunkEntryText.title",
            "L(\"ブロックした人\"", "L(\"親しい友達\"", "L(\"トランクを見せる\"", "L(\"わたしの乗車券もトランクに入れる\"",
            "Labels.Navigation.favorites", "Labels.Navigation.albums", "L(\"構図一覧\"", "L(\"写真の控え\"",
            "L(\"控えを空にする\"", "L(\"パスワードを変える\"", "L(\"新しくなったこと\"",
            "L(\"利用規約、プライバシーポリシー\"", "L(\"問い合わせ\"", "L(\"アカウントの削除\"", "Labels.Navigation.logout",
            "TrunkPrivacyPreview(model:", "ProSettingsSection(profile: myProfile)",
        ]
        for row in before {
            XCTAssertTrue(settings.contains(row), "設定から「\(row)」の行が消えた")
        }
        // 行き先の画面も全部つながっている（設定か ≡ のどちらか）
        let view = try settingsAndMenuSources()
        for destination in ["PassSettingsView()", "TrunkView(ownerName:", "BlockedUsersView()", "CloseFriendsView()",
                            "FavoritesView()", "AlbumsView()", "CompositionCatalogView()", "ChangePasswordView()",
                            "LegalLinksView()", "DeleteAccountView(profile: myProfile)", "SettingsTrunkPrivacyPage(",
                            "SettingsStoragePage()", "PassBookView()", "TripPlansView()",
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
        assertInOrder(["PushSettingsGroup(title: SettingsOutline.Part.notifications.title)",
                       "ProSettingsSection(profile: myProfile)",
                       "privacySection", "photosSection", "helpSection", "accountSection", "logoutSection",
                       "deleteSection"], in: list, "設定の節の順")
        XCTAssertFalse(list.contains("tripToolsSection"), "「旅の道具」の節が設定に戻った（≡ へ移した）")
        // 節の中の行の順
        let privacy = slice(view, from: "private var privacySection: some View {", to: "private var photosSection")
        assertInOrder(["SettingsOutline.Part.privacy.title", id("settings.blocked"), id("settings.closeFriends"),
                       "passRow", "if showsTrunkPrivacy {", id("settings.trunkPrivacy"),
                       // 2026-11-11 owner 承認（#526）: トランクを見せるの下
                       "SearchHiddenSettingRow(profile: myProfile)"], in: privacy, "プライバシーの順")
        let photos = slice(view, from: "private var photosSection: some View {", to: "private var helpSection")
        assertInOrder(["SettingsOutline.Part.photos.title", id("settings.compositionCatalog"),
                       id("settings.storage")], in: photos, "写真と撮影の順")
        let help = slice(view, from: "private var helpSection: some View {", to: "private var accountSection")
        assertInOrder(["SettingsOutline.Part.help.title", id("settings.help"), id("settings.whatsNew"), id("settings.legal"),
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
        // 2026-11-12: 行は ≡ メニュー（`SiteMenuView.trunkRow`）
        let view = try source("Features/Common/SiteMenuView.swift")
        let row = slice(view, from: "private var trunkRow: some View {", to: "private var footer")
        // 2026-11-23（札 #709）: 説明の行で「いま何があるか」、右に貼っていないラベルの件数バッジ
        assertInOrder(["if TrunkEntryRule.shows(signedIn: auth.userId != nil, available: trunkAvailability.isAvailable) {",
                       "TrunkView(ownerName: name)", ".onDisappear { trunkEntry.markStale() }",
                       "note: TrunkEntryText.stock(trunkEntry.summary)", "badge: TrunkEntryText.badge(trunkEntry.summary)",
                       "\"menu.trunk\""],
                      in: row, "旅のトランクの行")
        XCTAssertTrue(TrunkEntryRule.shows(signedIn: true, available: true))
        XCTAssertFalse(TrunkEntryRule.shows(signedIn: true, available: false))
    }

    /// キャンピングカー（とおまわり号）の入口は 2026-11-23 に消した（札 #709）。メニュー・マイページ・ほかの人のページの
    /// どこにも戻っていない。マイページの旅の記録のほかの行は残っている
    func testCamperEntriesAreGone() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let menu = try source("Features/Common/SiteMenuView.swift")
        XCTAssertFalse(menu.contains("camperRow"), "メニューにとおまわり号の行が戻った")
        XCTAssertFalse(menu.contains(#""menu.camper""#))
        let page = try source("Features/Profile/MyPageView.swift")
        let card = slice(page, from: "private var tripToolsCard: some View {", to: "nonisolated static func wishlistPool")
        XCTAssertFalse(card.contains(#""trips.camper""#), "マイページにとおまわり号の行が戻った")
        XCTAssertFalse(page.contains("Camper"), "マイページにとおまわり号の部品が残っている")
        XCTAssertTrue(card.contains("MyPageTrunkRow(ownerName: model.profile?.name)"), "マイページの旅のトランクの行が消えた")
        XCTAssertTrue(page.contains(id("trips.trunk")), "マイページの「trips.trunk」の行が消えた")
        for name in ["trips.albums", "trips.plans", "trips.passBook"] {
            XCTAssertTrue(card.contains(id(name)), "マイページの「\(name)」の行が消えた")
        }
        let profile = try source("Features/Profile/UserProfileView.swift")
        XCTAssertFalse(profile.contains(#""profile.camper""#), "ほかの人のページに「とおまわり号を訪ねる」が戻った")
        // キャンプ場は #339 で外した（`trips.camper` に `trips.camp` が含まれるので識別子は引用ごと見る）
        XCTAssertFalse(card.contains(#""trips.camp""#), "マイページにキャンプ場の行が残っている")
        XCTAssertFalse(card.contains("CampHomeView"), "マイページにキャンプ場の行き先が残っている")
        XCTAssertFalse(view.contains(#""settings.camp""#), "設定にキャンプ場の行が残っている")
        XCTAssertFalse(view.contains("CampHomeView"), "設定にキャンプ場の行き先が残っている")
    }

    // MARK: - 危ない操作

    /// ログアウトとアカウントの削除は最後に、別々の札で。危険の色は削除だけ（板: danger は削除・通報・エラー文）。
    /// ログアウトは白い行（メニューと同じく控えめ）
    func testDangerRowsAreLastAndApart() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let logout = slice(view, from: "private var logoutSection: some View {", to: "private var deleteSection")
        assertInOrder(["section(nil) {", "auth.startSigningOut {", "JPRowLabel(title: isSigningOut", "chevron: false)",
                       id("settings.logout")], in: logout, "ログアウト")
        XCTAssertFalse(logout.contains("WebTheme.danger"), "ログアウトを危険の色にしている")
        XCTAssertFalse(logout.contains("SettingsActionLabel("), "ログアウトが色の行になっている")
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

    // MARK: - お知らせ（2026-11-18 判断・案 B7）

    /// お知らせ（ベル）の画面の歯車は、設定のいちばん上ではなくお知らせの入切だけの画面を開く
    func testBellGearOpensNotificationSettings() throws {
        let bell = try source("Features/Notifications/NotificationsView.swift")
        XCTAssertTrue(bell.contains("NavigationLink { NotificationSettingsPage() } label: {"),
                      "ベルの歯車がお知らせの入切の画面を開かない")
        XCTAssertFalse(bell.contains("SettingsView()"), "ベルの歯車が設定のいちばん上を開いている")
        // 入切の札は設定と同じもの（写しを作らない）。お知らせだけの画面では題と重なるので眉ラベルなし
        let page = try source("Features/Settings/NotificationSettings.swift")
        let body = slice(page, from: "struct NotificationSettingsPage: View {", to: "\n}")
        XCTAssertTrue(body.contains("PushSettingsGroup(title: nil)"))
        XCTAssertTrue(body.contains("SettingsPage("), "設定の下の画面と同じ入れ物でない")
        let view = try source("Features/Settings/SettingsView.swift")
        XCTAssertFalse(view.contains("JPToggleRow(title: L(\"プッシュ通知を受け取る\""), "設定に入切の写しがある")
        XCTAssertEqual(page.components(separatedBy: "JPToggleRow(title: L(\"プッシュ通知を受け取る\"").count, 2)
    }

    /// Pro でない人には「前の晩に知らせる」をオンに見せない（既定は受け取るでも、届かない）
    func testLightAlertLooksOffWhenNotPro() throws {
        XCTAssertFalse(LightAlertToggleRule.shownOn(wants: true, knownNotPro: true), "Pro でない人にオンに見える")
        XCTAssertTrue(LightAlertToggleRule.shownOn(wants: true, knownNotPro: false))
        XCTAssertFalse(LightAlertToggleRule.shownOn(wants: false, knownNotPro: false))
        XCTAssertFalse(LightAlertToggleRule.shownOn(wants: false, knownNotPro: true))
        let rows = try source("Features/Pro/LightAlertSettingsRows.swift")
        let binding = slice(rows, from: "private var binding: Binding<Bool> {", to: "private func openPaywall()")
        XCTAssertTrue(binding.contains("get: { LightAlertToggleRule.shownOn(wants: wants, knownNotPro: knownNotPro) }"),
                      "入切がプロフィールの値をそのまま映している")
        // 押したら今までどおり Pro の案内（値は送らない）
        assertInOrder(["guard !knownNotPro else {", "openPaywall()", "return"], in: binding, "Pro でない人が押した")
    }
}
