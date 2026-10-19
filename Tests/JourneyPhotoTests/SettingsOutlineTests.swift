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
                       ["settings.trunk", "settings.camper", "settings.camp", "settings.pass", "settings.passBook",
                        "settings.albums", "settings.plans"])
        XCTAssertEqual(SettingsOutline.Part.danger.items, ["settings.logout", "settings.deleteAccount"])
        // 目印は重ならない
        let all = SettingsOutline.Part.allCases.flatMap(\.items) + SettingsOutline.subpages.values.flatMap { $0 }
        XCTAssertEqual(Set(all).count, all.count, "同じ目印が2か所にある")
    }

    /// いちばん上は一目で見渡せる長さ: 節は 8 つまで・どの節も 6 行まで（長いものは下の画面へ）。
    /// 旅の道具だけ 7 行まで（2026-10-18 判断: キャンプ場が入った。owner の「入口は設定の中に」を優先し、道具は下の画面に隠さない）
    func testTopLevelStaysShort() {
        XCTAssertLessThanOrEqual(SettingsOutline.Part.allCases.count, 8)
        for part in SettingsOutline.Part.allCases {
            XCTAssertLessThanOrEqual(part.items.count, part == .tripTools ? 7 : 6, "\(part) の節が長い")
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

    /// いいねした写真はログインしているときだけ（未ログインには出さない）。構図一覧・データとストレージはいつも
    func testFavoritesOnlyWhenSignedIn() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let photos = slice(view, from: "private var photosSection: some View {", to: "private var helpSection")
        assertInOrder(["if auth.userId != nil {", "FavoritesView()", id("settings.favorites"), "JPCardDivider()",
                       "}\n            NavigationLink { CompositionCatalogView() }"], in: photos, "いいねした写真の出し分け")
        let gated = slice(photos, from: "if auth.userId != nil {", to: "NavigationLink { CompositionCatalogView() }")
        XCTAssertFalse(gated.contains("SettingsStoragePage"), "データとストレージを未ログインで隠している")
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
                            "SettingsStoragePage()", "CamperGarageLoader(", "CampHomeView(ownerName: myProfile?.name)", "PassBookView()", "TripPlansView()",
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
        assertInOrder(["SettingsOutline.Part.tripTools.title", "trunkRow", "camperRow", "campRow", "passRow",
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
        // 車の画面は読めたときだけ。読み込み中・失敗は数の行を出さない
        let body = slice(loader, from: "switch loader.phase {", to: "private func load()")
        assertInOrder(["case .loaded:",
                       "CamperGarageView(ownerName: ownerName, userId: userId, photos: loader.photos, photosLoaded: true)",
                       "case .loading:", "ProgressView()", "L(\"写真を読み込んでいます…\"",
                       "\"camper.loading\"", "case .failed:", "ErrorBanner(", "Task { await load() }",
                       "\"camper.loadFailed\""], in: body, "設定からのキャンピングカー")
        XCTAssertEqual(body.components(separatedBy: "CamperGarageView(").count - 1, 1, "読めていないのに車の画面を出す")
        XCTAssertTrue(loader.contains(".task(id: userId) { await load() }"))
        XCTAssertTrue(loader.contains("ProfileImageFromPhoto.myPhotos(environment: environment)"))
        // マイページの「旅の記録」の行はそのまま（読み終えた写真を渡す）
        let page = try source("Features/Profile/MyPageView.swift")
        let card = slice(page, from: "private var tripToolsCard: some View {", to: "nonisolated static func wishlistPool")
        assertInOrder(["CamperGarageView(ownerName: model.profile?.name, userId: auth.userId, photos: model.photos,",
                       "photosLoaded: model.hasLoadedPhotos)", id("trips.camper")], in: card, "マイページのキャンピングカー")
        XCTAssertFalse(card.contains("CamperGarageLoader("), "マイページで写真を二重に読む")
        for name in ["trips.trunk", "trips.camp", "trips.albums", "trips.plans", "trips.passBook"] {
            XCTAssertTrue(card.contains(id(name)), "マイページの「\(name)」の行が消えた")
        }
    }

    /// キャンプ場: キャンピングカーの下。題・説明はマイページの行と同じ文言。中身は端末の中だけなので、
    /// マイページと同じ形（`CampHomeView(ownerName:)`）で開く
    func testCampEntryWiring() throws {
        let view = try source("Features/Settings/SettingsView.swift")
        let row = slice(view, from: "private var campRow: some View {", to: "private var trunkRow")
        assertInOrder(["NavigationLink { CampHomeView(ownerName: myProfile?.name) } label: {",
                       "L(\"キャンプ場\", \"Campsite\")", "L(\"撮った森や空を切り絵にして、浮かぶ島に立てる\"",
                       id("settings.camp")], in: row, "キャンプ場の行")
        XCTAssertFalse(row.contains("systemImage:"), "設定の行に絵を出している")
        let page = try source("Features/Profile/MyPageView.swift")
        let card = slice(page, from: "private var tripToolsCard: some View {", to: "nonisolated static func wishlistPool")
        for words in ["L(\"キャンプ場\", \"Campsite\")",
                      "L(\"撮った森や空を切り絵にして、浮かぶ島に立てる\",\n                                     \"Turn the woods and skies you shoot into paper cutouts on a floating island\")"] {
            XCTAssertTrue(card.contains(words), "マイページのキャンプ場の行と文言がずれた: \(words)")
            XCTAssertTrue(row.contains(words.replacingOccurrences(of: "\n                                     ", with: "\n                                 ")),
                          "設定のキャンプ場の行と文言がずれた: \(words)")
        }
        assertInOrder(["CampHomeView(ownerName: model.profile?.name)", id("trips.camp")], in: card, "マイページのキャンプ場")
    }

    /// 読み終えるまで止めておける読み方（`CamperPhotoLoader.load` に渡す）
    @MainActor
    private final class Gate {
        var calls = 0
        /// 待っている読み（二本目が出ても止まったままにしない＝全部まとめて返す）
        private var waiting: [CheckedContinuation<[Photo]?, Never>] = []
        func fetch() async -> [Photo]? {
            calls += 1
            return await withCheckedContinuation { waiting.append($0) }
        }
        func open(_ photos: [Photo]?) {
            let all = waiting
            waiting = []
            all.forEach { $0.resume(returning: photos) }
        }
        /// 読み始めるまで待つ（上限つき）
        func untilCalled(_ n: Int) async {
            var tries = 0
            while calls < n, tries < 1000 {
                await Task.yield()
                tries += 1
            }
        }
    }

    /// 読めるまでは「読み込み中」。読めたら切り替え、もう読まない（画面に戻るたびに読み直さない）
    @MainActor
    func testCamperLoaderLoadsOnce() async {
        let loader = CamperPhotoLoader()
        XCTAssertEqual(loader.phase, .loading, "読む前に車の画面を出す")
        var calls = 0
        await loader.load(userId: "me") { calls += 1; return [] }
        XCTAssertEqual(loader.phase, .loaded)
        XCTAssertEqual(loader.loadedFor, "me")
        await loader.load(userId: "me") { calls += 1; return [] }
        XCTAssertEqual(calls, 1, "読めたのにもう一度読む")
        // 人が替わったら読み直す
        await loader.load(userId: "other") { calls += 1; return nil }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(loader.phase, .failed)
        XCTAssertNil(loader.loadedFor, "前の人の写真で数える")
    }

    /// 読めなければ「もう一度」の状態。もう一度で読めたら切り替える。入っていなければ読まない
    @MainActor
    func testCamperLoaderFailureThenRetry() async {
        let loader = CamperPhotoLoader()
        await loader.load(userId: "me") { nil }
        XCTAssertEqual(loader.phase, .failed)
        XCTAssertTrue(loader.photos.isEmpty)
        await loader.load(userId: "me") { [] }
        XCTAssertEqual(loader.phase, .loaded)
        let signedOut = CamperPhotoLoader()
        var called = false
        await signedOut.load(userId: nil) { called = true; return [] }
        XCTAssertFalse(called)
        XCTAssertEqual(signedOut.phase, .failed)
    }

    /// 読んでいる最中にもう一度呼ばれても、二本目を出さない
    @MainActor
    func testCamperLoaderDoesNotReadTwiceInFlight() async {
        let loader = CamperPhotoLoader()
        let gate = Gate()
        let first = Task { await loader.load(userId: "me") { await gate.fetch() } }
        await gate.untilCalled(1)
        XCTAssertEqual(gate.calls, 1)
        let second = Task { await loader.load(userId: "me") { await gate.fetch() } }
        await gate.untilCalled(2)
        XCTAssertEqual(gate.calls, 1, "読んでいる最中に二本目を出した")
        gate.open([])
        await first.value
        gate.open([])
        await second.value
        XCTAssertEqual(loader.phase, .loaded)
    }

    /// 取り消された（画面を離れた）読み込みの結果は入れない。次に開いたら読み直す
    @MainActor
    func testCamperLoaderIgnoresCancelledRead() async {
        let loader = CamperPhotoLoader()
        let gate = Gate()
        let first = Task { await loader.load(userId: "me") { await gate.fetch() } }
        await gate.untilCalled(1)
        first.cancel()
        gate.open([])
        await first.value
        XCTAssertEqual(loader.phase, .loading, "取り消した読み込みの結果を入れた")
        XCTAssertNil(loader.loadedFor)
        var calls = 0
        await loader.load(userId: "me") { calls += 1; return [] }
        XCTAssertEqual(calls, 1, "取り消しのあとに読み直さない")
        XCTAssertEqual(loader.phase, .loaded)
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
}
