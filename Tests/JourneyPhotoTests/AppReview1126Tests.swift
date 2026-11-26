import XCTest
@testable import JourneyPhoto

/// 🔴 **App Store の審査の前の見直し（2026-11-26・1.2.9 で申請し直す前）の直しを守る。**
///
/// - 5.1.1(iv) と 2.5.4: すれちがいの説明は「続ける」だけ。裏でも交換することを説明と Bluetooth の確認の文に書く
/// - 5.2.5: iTunes の試聴を流す所に「Apple Music で聴く」のリンク。天気の字の印にロゴの字を使わない
/// - 1.2 と 4.7: AI の答えと AI の旅行プランに「この答えを報告」。報告した答えは隠す
/// - 3.1.2 と 2.1: 配る仕組みの無い章を約束しない。英語の「2 months free」を使わない
/// - 4.8: Google のボタンは Apple のボタンを出せるときだけ
/// - 2.3.7: 「インスタ」と書かない
/// - 5.2: 地名の候補に OpenStreetMap の出典
///
/// 画面は Linux で描けないので、言葉と決まりは値で、画面のつなぎはソースで見る（消したら落ちるのが目的）
@MainActor
final class AppReview1126Tests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 注記（`//`）を除いたソース
    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func app(_ path: String) throws -> String { try source("Sources/JourneyPhoto/" + path) }

    /// `from` から `to` までの切り出し
    private func slice(_ text: String, from: String, to: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: from), "\(from) が無い")
        let end = try XCTUnwrap(text.range(of: to, range: start.upperBound..<text.endIndex), "\(to) が無い")
        return String(text[start.lowerBound..<end.lowerBound])
    }

    // MARK: - 5.1.1(iv) すれちがいの説明

    func testPassIntroOnlyContinues() throws {
        XCTAssertEqual(PassPrivacyText.introProceed, "続ける")
        let view = try app("Features/Pass/PassSettingsView.swift")
        let sheet = try slice(view, from: "struct PassIntroSheet: View {", to: "private func point(")
        XCTAssertTrue(sheet.contains("Text(PassPrivacyText.introProceed)"))
        XCTAssertTrue(sheet.contains(".accessibilityIdentifier(\"pass.intro.confirm\")"))
        XCTAssertTrue(sheet.contains(".sheetSwipeGuard(.hold)"), "すれちがいの説明を下に引いて閉じられる")
        XCTAssertTrue(sheet.contains(".presentationDragIndicator(.hidden)"))
        for word in ["pass.intro.cancel", "L(\"やめる\"", "\"Not now\"", "L(\"オンにする\"", "dismiss()"] {
            XCTAssertFalse(sheet.contains(word), "すれちがいの説明に \(word) が残っている（審査 5.1.1(iv)）")
        }
        // 注記は「続ける」を押すと何が起きるかと、やめたい人の戻り方を言う
        XCTAssertTrue(PassPrivacyText.introNote.contains("「続ける」を押すと"))
        XCTAssertTrue(PassPrivacyText.introNote.contains("オフにできます"))
    }

    /// 2.5.4: 裏でも Bluetooth を使うことを、説明の点と Bluetooth の確認の文（日本語、英語、project.yml）に書く
    func testPassSaysItRunsInTheBackground() throws {
        XCTAssertTrue(PassPrivacyText.backgroundUse.ja.contains("アプリを閉じていても"))
        XCTAssertTrue(PassPrivacyText.backgroundUse.en.contains("even when the app is closed"))
        XCTAssertTrue(PassPrivacyText.introPoints.map(\.text).contains(L(PassPrivacyText.backgroundUse.ja,
                                                                         PassPrivacyText.backgroundUse.en)))
        let ja = try source("Sources/JourneyPhoto/Resources/ja.lproj/InfoPlist.strings")
        let en = try source("Sources/JourneyPhoto/Resources/en.lproj/InfoPlist.strings")
        let yml = try source("project.yml")
        let jaLine = try XCTUnwrap(ja.components(separatedBy: "\n").first { $0.hasPrefix("\"NSBluetoothAlwaysUsageDescription\"") })
        let enLine = try XCTUnwrap(en.components(separatedBy: "\n").first { $0.hasPrefix("\"NSBluetoothAlwaysUsageDescription\"") })
        let ymlLine = try XCTUnwrap(yml.components(separatedBy: "\n").first { $0.contains("NSBluetoothAlwaysUsageDescription:") })
        XCTAssertTrue(jaLine.contains("アプリを閉じていても近くの人と交換します"))
        XCTAssertTrue(enLine.contains("even when the app is closed"))
        XCTAssertTrue(ymlLine.contains("アプリを閉じていても近くの人と交換します"))
        // 中黒で区切らない（CLAUDE.md）
        for text in [PassPrivacyText.backgroundUse.ja, PassPrivacyText.introNote] {
            XCTAssertFalse(text.contains("・") || text.contains("·"), text)
        }
    }

    /// 初めての投稿のあとの通知の行も「続ける」（押すと iOS の確認が出る）
    func testPostedSummaryPushRowContinues() {
        XCTAssertEqual(PostedSummaryText.pushAction, PushPrimerText.proceed)
        XCTAssertNotEqual(PostedSummaryText.pushAction, L("オンにする", "Turn on"))
    }

    // MARK: - 5.2.5 Apple Music のリンク

    private func song(trackUrl: String?, title: String = "Lemon", artist: String? = "米津玄師") -> Photo.Song {
        Photo.Song(title: title, artist: artist, artwork: nil,
                   previewUrl: "https://audio-ssl.itunes.apple.com/p.m4a", trackUrl: trackUrl)
    }

    func testAppleMusicURLUsesTheTrackPage() {
        let url = "https://music.apple.com/jp/album/lemon/1350305653?i=1350305658&uo=4"
        XCTAssertEqual(SongPickerText.appleMusicURL(for: song(trackUrl: url))?.absoluteString, url)
        XCTAssertEqual(SongPickerText.appleMusicURL(for: song(trackUrl: "https://itunes.apple.com/jp/x"))?.host, "itunes.apple.com")
        XCTAssertEqual(SongPickerText.appleMusicURL(for: song(trackUrl: "https://geo.music.apple.com/x"))?.host, "geo.music.apple.com")
    }

    /// 曲の頁が無い、Apple の外、http のときは Apple Music の検索へ（ほかの所は開かない）
    func testAppleMusicURLFallsBackToSearch() throws {
        for bad in [nil, "", "http://music.apple.com/x", "https://example.com/music.apple.com", "https://evilmusic.apple.com.example.com/x",
                    "javascript:alert(1)"] as [String?] {
            let url = try XCTUnwrap(SongPickerText.appleMusicURL(for: song(trackUrl: bad)), bad ?? "nil")
            XCTAssertEqual(url.host, "music.apple.com", bad ?? "nil")
            XCTAssertEqual(url.path, "/search", bad ?? "nil")
            let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "term" }?.value
            XCTAssertEqual(term, "Lemon 米津玄師")
        }
        XCTAssertNil(SongPickerText.appleMusicURL(for: song(trackUrl: nil, title: " ", artist: nil)))
    }

    func testAppleMusicLabels() {
        XCTAssertEqual(SongPickerText.appleMusicLabel, "Apple Music で聴く")
        XCTAssertEqual(SongPickerText.appleMusicShortLabel, "Apple Music")
        XCTAssertFalse(SongPickerText.appleMusicLabel.contains("\u{F8FF}"))
    }

    /// 曲が出る所にリンクを置く（選ぶ画面の再生バー、写真の曲の行、マイページの BGM、ストーリーの見出し）
    func testAppleMusicLinkIsWired() throws {
        let link = try app("Features/Common/AppleMusicLink.swift")
        XCTAssertTrue(link.contains("SongPickerText.appleMusicURL(for: song)"))
        XCTAssertTrue(link.contains("openURL(url)"))
        XCTAssertTrue(link.contains(".frame(minWidth: WebTheme.minTapTarget)"), "リンクの当たりが 44pt に満たない")
        XCTAssertTrue(link.contains(".contentShape(Rectangle().inset(by: -Self.verticalSlack))"))
        XCTAssertFalse(link.contains("padding(.vertical, -"), "負の余白で張り出している")
        XCTAssertGreaterThanOrEqual(16 + AppleMusicLink.verticalSlack * 2, WebTheme.minTapTarget, "縦の当たりが 44pt に満たない")
        // 黒い地の上は真鍮、写真の上は白
        XCTAssertTrue(link.contains("ground == .photo ? WebTheme.foreground : WebTheme.accent"))

        XCTAssertTrue(try app("Features/Common/MiniPlayerBar.swift")
            .contains("AppleMusicLink(song: song, ground: inSongPicker ? .dark : .photo, compact: true)"))
        XCTAssertTrue(try app("Features/Common/SongRow.swift").contains("AppleMusicLink(song: song)"))
        let myPage = try slice(try app("Features/Profile/MyPageView.swift"), from: "private func bgmLine(", to: "private var highlightsRow")
        XCTAssertTrue(myPage.contains("ProfileBgmCard(song: song)\n                AppleMusicLink(song: song)"))
        let viewer = try app("Features/Stories/StoryViewerView.swift")
        let header = try slice(viewer, from: "private func header(for story: Story)", to: "private func highlightLabel(")
        XCTAssertTrue(header.contains("AppleMusicLink(song: song, ground: .photo, compact: true)"), "ストーリーの曲にリンクが無い")
    }

    // MARK: - 1.2 と 4.7 AI の答えの報告

    func testReportTextHasOnlyTheQuestionAndTheAnswer() {
        let text = AIAnswerReport.text(source: .ask, reason: .wrong, question: " 秋の京都でおすすめは？ ", answer: "嵐山がおすすめです")
        XCTAssertEqual(text, "[AI answer report] ask reason=wrong\nQ: 秋の京都でおすすめは？\nA: 嵐山がおすすめです")
        let trip = AIAnswerReport.text(source: .tripPlan, reason: .harmful, question: nil, answer: "朝に向く所を先に")
        XCTAssertEqual(trip, "[AI answer report] tripPlan reason=harmful\nA: 朝に向く所を先に")
    }

    /// 本文は意見の口の上限（1000 字・UTF-16）に収める。長い頼みの文でも答えが入る
    func testReportTextFitsTheFeedbackLimit() {
        let long = AIAnswerReport.text(source: .ask, reason: .other, question: String(repeating: "あ", count: 2000),
                                       answer: String(repeating: "い", count: 2000))
        XCTAssertLessThanOrEqual(long.utf16.count, FeedbackService.textMax)
        XCTAssertTrue(long.contains("\nA: い"), "答えが入っていない")
        // 絵文字（UTF-16 で2つ）を途中で切らない
        let emoji = AIAnswerReport.text(source: .ask, reason: .other, question: nil, answer: String(repeating: "😀", count: 900))
        XCTAssertLessThanOrEqual(emoji.utf16.count, FeedbackService.textMax)
        XCTAssertTrue(emoji.hasSuffix("😀"))
    }

    func testReportDraftGoesToTheFeedbackBox() {
        let draft = AIAnswerReport.draft(source: .ask, reason: .offensive, question: "q", answer: "a", userId: "u1")
        XCTAssertEqual(draft.screen, "ai-ask-report")
        XCTAssertEqual(AIAnswerReport.Source.tripPlan.screen, "ai-trip-report")
        XCTAssertFalse(draft.wantsReply)
        XCTAssertEqual(draft.userId, "u1")
        // サーバーの `cleanToken` が受ける字だけ（英数字と - ）・40 字まで
        for source in [AIAnswerReport.Source.ask, .tripPlan] {
            XCTAssertTrue(source.screen.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            XCTAssertLessThanOrEqual(source.screen.count, 40)
        }
    }

    /// AI が書いた答えだけに出す（言葉の表、断り、読めなかった答えには出さない）
    func testReportIsOfferedOnlyForAIAnswers() {
        XCTAssertTrue(AIAnswerReport.offersReport(AskAnswer(engine: .device)))
        XCTAssertTrue(AIAnswerReport.offersReport(AskAnswer(engine: .server)))
        XCTAssertFalse(AIAnswerReport.offersReport(AskAnswer(engine: .table)))
        XCTAssertFalse(AIAnswerReport.offersReport(AskAnswer(engine: .refused)))
        XCTAssertFalse(AIAnswerReport.offersReport(AskAnswer(engine: .device, state: .failed)))
        XCTAssertFalse(AIAnswerReport.offersReport(AskAnswer(engine: .device, state: .empty)))
    }

    func testAskAnswerTextCarriesTheReasons() {
        var answer = AskAnswer(engine: .device)
        answer.text = "秋なら嵐山"
        answer.spotIds = ["s1", "s2"]
        answer.reasons = ["s1": "紅葉が見頃"]
        XCTAssertEqual(AIAnswerReport.askAnswerText(answer) { $0 == "s1" ? "嵐山" : nil }, "秋なら嵐山\n嵐山: 紅葉が見頃")
    }

    func testReportedAnswersAreHidden() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = AIAnswerReports(defaults: defaults)
        XCTAssertFalse(store.isHidden("a1"))
        store.hide("a1")
        store.hide("a1")
        XCTAssertTrue(store.isHidden("a1"))
        XCTAssertEqual(store.hidden, ["a1"])
        // 開き直しても隠したまま
        XCTAssertTrue(AIAnswerReports(defaults: defaults).isHidden("a1"))
        for i in 0..<(AIAnswerReports.limit + 5) { store.hide("x\(i)") }
        XCTAssertEqual(store.hidden.count, AIAnswerReports.limit)
        XCTAssertFalse(store.isHidden("a1"), "古い分から落とす")
    }

    /// 旅行プランの理由は、理由の文ごとに覚える（組み直して替わった理由は出す）。印は起動をまたいで同じ
    func testTripKeyFollowsTheReason() {
        let a = AIAnswerReports.tripKey("p1", reason: "朝に向く所を先に")
        XCTAssertEqual(a, AIAnswerReports.tripKey("p1", reason: "朝に向く所を先に"))
        XCTAssertNotEqual(a, AIAnswerReports.tripKey("p1", reason: "雨でも行ける所を先に"))
        XCTAssertNotEqual(a, AIAnswerReports.tripKey("p2", reason: "朝に向く所を先に"))
        XCTAssertTrue(a.hasPrefix("trip:p1:"))
        XCTAssertEqual(AIAnswerReports.tripKey("p", reason: ""), "trip:p:cbf29ce484222325")
    }

    func testTripCardOffersReportOnlyForAIReasons() {
        let ai = TripAINote(reason: "朝に向く所を先に", mode: .ai, removed: [], candidates: [])
        XCTAssertTrue(TripAICard.offersReport(ai))
        XCTAssertFalse(TripAICard.offersReport(TripAINote(reason: "朝", mode: .offline, removed: [], candidates: [])))
        XCTAssertFalse(TripAICard.offersReport(TripAINote(reason: " ", mode: .ai, removed: [], candidates: [])))
        // 隠すと理由は外れ、AI なしで組んだ帯は残る
        XCTAssertEqual(TripAICard.withoutReason(ai).reason, "")
        XCTAssertFalse(TripAICard.hasContent(TripAICard.withoutReason(ai)))
        XCTAssertTrue(TripAICard.hasContent(TripAICard.withoutReason(TripAINote(reason: "x", mode: .silent, removed: [], candidates: []))))
    }

    func testReportIsWiredIntoTheAnswers() throws {
        let thread = try app("Features/Search/AskThreadView.swift")
        XCTAssertTrue(thread.contains(".aiAnswerReport($reportTarget)"))
        XCTAssertTrue(thread.contains("if reports.isHidden(exchange.id) {\n                AIAnswerHiddenLine()"), "報告した答えを隠していない")
        XCTAssertTrue(thread.contains("if AIAnswerReport.offersReport(a) {\n                    AIAnswerReportButton {"))
        XCTAssertTrue(thread.contains("id: exchange.id, source: .ask, question: exchange.question,"))

        let card = try app("Features/Trips/AI/TripAICard.swift")
        XCTAssertTrue(card.contains("Button(action: report) { Label(AIAnswerReport.action, systemImage: \"flag\") }"))
        XCTAssertTrue(card.contains(".accessibilityIdentifier(\"tripAI.menu\")"), "開いた札に「…」が無い")
        XCTAssertTrue(card.contains(".contextMenu {"), "畳んだ札から報告できない")
        let detail = try app("Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(detail.contains(".aiAnswerReport($aiReportTarget)"))
        XCTAssertTrue(detail.contains("if hidden { AIAnswerHiddenLine() }"))
        XCTAssertTrue(detail.contains("question: nil, answer: note.reason)"), "旅行プランの報告に AI の理由のほかを送っている")

        let flow = try app("Features/Common/AIAnswerReportFlow.swift")
        XCTAssertTrue(flow.contains("reports.hide(target.id)"), "報告した答えをその場で隠していない")
        XCTAssertTrue(flow.contains("try await service.send(draft, photo: photo, signedIn: signedIn)"), "意見の口で送っていない")
        XCTAssertTrue(flow.contains("try? outbox.save(draft, photo: nil)"), "圏外のとき報告が消える")
        XCTAssertTrue(flow.contains(".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget"))
    }

    func testReportWording() {
        XCTAssertEqual(AIAnswerReport.action, "この答えを報告")
        XCTAssertEqual(AIAnswerReport.Reason.allCases.count, 4)
        for text in [AIAnswerReport.action, AIAnswerReport.dialogTitle, AIAnswerReport.dialogMessage, AIAnswerReport.hiddenLine,
                     AIAnswerReport.thanks, AIAnswerReport.later] + AIAnswerReport.Reason.allCases.map(\.label) {
            XCTAssertFalse(text.contains("・") || text.contains("·"), text)
            XCTAssertFalse(text.contains("捨て"), text)
        }
    }

    // MARK: - 3.1.2 と 2.1 Pro の約束

    func testPaywallDoesNotPromiseToolChapters() throws {
        let paywall = try app("Features/Pro/PaywallView.swift")
        XCTAssertFalse(paywall.contains("道具を使い込んだ"), "配る仕組みの無い章を課金の画面で約束している")
        XCTAssertFalse(paywall.contains("chapters for using the tools"))
        XCTAssertFalse(paywall.contains("2 months free"), "英語の「2 months free」は無料の試用と読まれる")
        XCTAssertTrue(paywall.contains("L(\"2か月ぶんお得\", \"Save 2 months\")"))
        let chapters = try app("Features/Profile/ProChapters.swift")
        XCTAssertFalse(chapters.contains("これから配ります"), "「これから配ります」がアプリに出る")
        XCTAssertFalse(chapters.contains("Coming later"))
    }

    // MARK: - 4.8 ログインの入口

    func testGoogleNeedsApple() throws {
        XCTAssertTrue(ExternalSignInMemory.showsGoogle(google: true, apple: true))
        XCTAssertFalse(ExternalSignInMemory.showsGoogle(google: true, apple: false), "Apple が無いのに Google だけが出る")
        XCTAssertFalse(ExternalSignInMemory.showsGoogle(google: false, apple: true))
        let view = try app("Features/Auth/SignInView.swift")
        XCTAssertTrue(view.contains("if googleShown {\n            googleButton"))
        XCTAssertTrue(view.contains("externalCount: (appleAvailable ? 1 : 0) + (googleShown ? 1 : 0)"))
        XCTAssertFalse(view.contains("if googleAvailable {"), "Google のボタンを Apple と別に出している")
    }

    // MARK: - 2.3.7 ほかの会社の呼び名

    /// 画面の文に「インスタ」と書かない（正しい名前の「Instagram」）
    func testNoInstaNickname() throws {
        let sources = root.appendingPathComponent("Sources/JourneyPhoto")
        let files = (FileManager.default.enumerator(atPath: sources.path)?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix(".swift") }
        var found: [String] = []
        for file in files {
            let text = try source("Sources/JourneyPhoto/" + file)
            for line in text.components(separatedBy: "\n") where line.contains("L(\"") && line.contains("インスタ") {
                found.append("\(file): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(found, [], "画面の文に「インスタ」がある")
        XCTAssertTrue(try app("Features/Common/TravelStorySheet.swift").contains("L(\"コピーしました。Instagram のストーリーで貼り付けられます\""))
    }

    // MARK: - 5.2 OpenStreetMap の出典

    func testPlaceSearchShowsOSMCredit() throws {
        XCTAssertEqual(PlaceSearchCredit.text, "© OpenStreetMap contributors")
        let field = try app("Features/Upload/PlaceSearchField.swift")
        XCTAssertTrue(field.contains("if !suggestions.isEmpty {\n                Text(PlaceSearchCredit.text)"),
                      "地名の候補に OpenStreetMap の出典が無い")
        XCTAssertTrue(field.contains(".accessibilityIdentifier(\"place.osmCredit\")"))
    }
}
