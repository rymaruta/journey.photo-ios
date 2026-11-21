import XCTest
@testable import JourneyPhoto

/// 探すの欄は探すだけ、AI に頼むは別の画面（札 #675・2026-11-21 判断・Artifact「AI に頼む 独立の案」の案1）。
/// owner「検索窓は基本的に、観光スポットやユーザが投稿した写真に機能したら嬉しくて、AIに頼むは完全に独立して」「AIに頼むを押して別画面になるのはどう？」
final class SearchSubmitTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 探すは打つたびに探し、AI を呼ばない

    /// 1字ずつ打つたびに探す字が変わる（前の「送信を押すまで結果を出さない」はやめた）
    func testSearchFollowsEveryKeystroke() {
        var searched = ""
        var t = ""
        for ch in "おすすめの観光スポット教えて" {
            t.append(ch)
            let plan = SearchSubmit.plan(.typed, text: t, scope: .all, searched: searched)
            if let next = plan.searched { searched = next }
            XCTAssertEqual(searched, t, "打っても探す字が変わらない: \(t)")
            XCTAssertFalse(plan.readsSentence, "打つたびに言葉の表で読んだ（欄の字を書き換えてしまう）")
        }
        XCTAssertEqual(SearchSubmit.plan(.cleared, text: "", scope: .all, searched: "京都").searched, "")
        XCTAssertEqual(SearchSubmit.plan(.typed, text: "k", scope: .people, searched: "").searched, "k")
        // キーボードの「検索」と最近の語は、語を並べた文を言葉の表で読む（AI は使わない）
        XCTAssertTrue(SearchSubmit.plan(.keyboard, text: "京都 紅葉 夜", scope: .all, searched: "京都 紅葉 夜").readsSentence)
        XCTAssertTrue(SearchSubmit.plan(.recent, text: "京都 紅葉 夜", scope: .all, searched: "").readsSentence)
        XCTAssertFalse(SearchSubmit.plan(.keyboard, text: "taro", scope: .people, searched: "taro").readsSentence)
    }

    /// 探すの画面は AI の仕組み（`AskEngine`、答えの画面、送信のボタン）を持たない
    func testSearchViewNeverCallsAI() throws {
        let view = try source("Sources/JourneyPhoto/Features/Search/SearchView.swift")
        for banned in ["AskEngine(", "AskThreadView(", "AskSendButton(", ".start(", "AskDevice.", "env.ask.", "AskRotatingPrompt"] {
            XCTAssertFalse(view.contains(banned), "探すの画面に AI を呼ぶ所が残っている: \(banned)")
        }
        XCTAssertTrue(view.contains("TabRouter.shared.openAsk(text: query)"), "頼みの形の1行から AI の画面へ移らない")
    }

    // MARK: - 頼みの形で「AI に頼む」の1行が出る

    func testAskRowForAskForm() {
        for text in ["おすすめの観光スポット教えて", "近くで夕日がきれいな所は？", "金沢に1泊2日の旅行プランを作って"] {
            XCTAssertTrue(SearchSubmit.showsAskRow(text: text, scope: .all), "頼みの形で1行が出ない: \(text)")
        }
        for text in ["京都", "京都 紅葉 夜", "", "@mika"] {
            XCTAssertFalse(SearchSubmit.showsAskRow(text: text, scope: .all), "頼みの形でない字で1行が出た: \(text)")
        }
        XCTAssertFalse(SearchSubmit.showsAskRow(text: "おすすめの観光スポット教えて", scope: .people), "人を探すときに1行が出た")
        XCTAssertEqual(AskEntry.askRowDetail("近くで夕日"), "「近くで夕日」")
    }

    // MARK: - AI の画面は送信のボタンだけで呼ぶ

    func testAskScreenSendsOnlyByButton() throws {
        let screen = try source("Sources/JourneyPhoto/Features/Search/AskScreen.swift")
        // キーボードのキーは「完了」で閉じるだけ
        let submit = try XCTUnwrap(screen.range(of: ".submitLabel(.done)"), "欄のキーが「完了」でない")
        let after = screen[submit.upperBound...].prefix(120)
        XCTAssertTrue(after.contains(".onSubmit { focused = false }"), "キーボードのキーで送っている")
        XCTAssertFalse(after.contains("send("), "キーボードのキーで送っている")
        XCTAssertTrue(screen.contains("AskSendButton(enabled: AskEntry.sendEnabled(draft)"), "送信のボタンが無い")
        // 例の札は欄に入れるだけ（押すまで AI は呼ばない）
        let starter = try XCTUnwrap(screen.range(of: "draft = s.text"))
        XCTAssertFalse(screen[starter.upperBound...].prefix(80).contains("send("), "例の札を押しただけで送った")
        // 途中の字では送らない
        for text in ["おすすめの", "京都で", "近くで", ""] {
            XCTAssertFalse(AskEntry.sendEnabled(text), "途中の字で送れる: \(text)")
        }
        for text in ["おすすめの観光スポット教えて", "京都", "金沢に1泊2日の旅行プランを作って"] {
            XCTAssertTrue(AskEntry.sendEnabled(text), "送れるはずの字で送れない: \(text)")
        }
        XCTAssertTrue(AskEntry.showsKeepTyping("おすすめの"))
        XCTAssertFalse(AskEntry.showsKeepTyping("おすすめの観光スポット教えて"))
        XCTAssertEqual(AskEntry.sendLabel, "AI に送る")
    }

    /// 旅行プランを作る頼みは旅行プランの AI へ、それ以外は AI に頼む
    func testRouteTripPlanToTripAI() {
        XCTAssertEqual(AskEntry.route("金沢に1泊2日の旅行プランを作って"), .tripPlan)
        XCTAssertEqual(AskEntry.route("京都で2泊3日の旅程を組んで"), .tripPlan)
        XCTAssertEqual(AskEntry.route("今週末、紅葉が見頃の所は？"), .ask)
        XCTAssertEqual(AskEntry.route("ストーリーに曲を付けるには"), .ask)
    }

    /// 例の札は観光スポット、近くで、旅行プラン、使い方の4つ。どれも送れて、アプリの作りに触れない
    func testStartersAreSafeAndSendable() {
        for month in 1...12 {
            let starters = AskEntry.starters(month: month)
            XCTAssertEqual(starters.count, 4)
            for s in starters {
                XCTAssertTrue(AskEntry.sendEnabled(s.text), "例が送れない: \(s.text)")
                XCTAssertFalse(AskGuard.declinesBeforeAsking(s.text), "例が断られる: \(s.text)")
            }
            XCTAssertEqual(starters.filter { AskEntry.route($0.text) == .tripPlan }.count, 1, "旅行プランの例が1つでない")
        }
    }

    // MARK: - 帯の入口がどの画面にもある

    func testHeaderEntryOnEveryTab() throws {
        let header = try source("Sources/JourneyPhoto/Features/Common/AppHeader.swift")
        XCTAssertTrue(header.contains("AskEntryButton()"), "上の帯に AI に頼むの入口が無い")
        XCTAssertTrue(header.contains("TabRouter.shared.openAsk()"))
        XCTAssertTrue(header.contains(".accessibilityLabel(AskEntry.buttonLabel)"))
        for file in ["Sources/JourneyPhoto/Features/Gallery/GalleryView.swift",
                     "Sources/JourneyPhoto/Features/Search/SearchView.swift",
                     "Sources/JourneyPhoto/Features/Map/PhotoMapView.swift"] {
            XCTAssertTrue(try source(file).contains("AppHeaderItems("), "\(file) に上の帯が無い")
        }
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains("AskScreen(prefill: askPrefill"), "AI の画面を全画面で開いていない")
        XCTAssertEqual(AskEntry.buttonLabel, "AI に頼む")
        XCTAssertTrue(AskEntryButton.iconOnly(largeText: true))
        XCTAssertFalse(AskEntryButton.iconOnly(largeText: false))
    }

    @MainActor
    func testRouterCarriesTheTypedWords() async {
        let router = TabRouter.shared
        let before = router.askRequests
        router.openAsk(text: "近くで夕日がきれいな所は？")
        XCTAssertEqual(router.askRequests, before + 1)
        XCTAssertEqual(router.takePendingAskText(), "近くで夕日がきれいな所は？")
        XCTAssertNil(router.takePendingAskText(), "字を2回渡した")
    }

    // MARK: - 前に頼んだことは控えから見せる（AI を呼ばない）

    func testHistoryRowsNewestFirst() {
        let a = AskExchange(question: "金沢のおすすめは？", answer: AskAnswer(engine: .device, text: "兼六園です。"))
        let b = AskExchange(question: "京都で紅葉は？", answer: AskAnswer(engine: .device, text: "永観堂です。"))
        let rows = AskHistoryRow.rows(["a": .init(day: "2026-11-19", thread: [a]), "b": .init(day: "2026-11-21", thread: [b]),
                                       "c": .init(day: "2026-11-20", thread: [])])
        XCTAssertEqual(rows.map(\.question), ["京都で紅葉は？", "金沢のおすすめは？"])
    }

    @MainActor
    func testShowSavedUsesNoAIAndNoCount() async throws {
        final class Counter { var reserves = 0; var deviceAsks = 0; var serverAsks = 0 }
        let c = Counter()
        let rows = try AskSamples.ledger()
        let backend = AskEngine.Backend(
            signedIn: { true }, offline: { false }, deviceAI: { true },
            library: { _ in AskLibrary(spots: rows, photos: []) },
            reserve: { kind, _ in
                c.reserves += 1
                return AskUsage(tier: "free", kind: kind.rawValue, day: .init(used: 1, limit: 3, remaining: 2),
                                month: .init(used: 1, limit: 10, remaining: 9, resetsOn: "2026-12-01"), serverAllowed: false)
            },
            serverAsk: { _, _, _ in c.serverAsks += 1; return AskService.ServerAnswer(answer: "", general: false) },
            deviceAsk: { _, _, _ in c.deviceAsks += 1; return nil },
            details: { $0 }, userId: { "u1" })
        let engine = AskEngine(history: AskHistoryStore(defaults: UserDefaults(suiteName: "SearchSubmitTests.\(UUID().uuidString)")!))
        var answer = AskAnswer(engine: .device, text: "屋島がおすすめです。")
        answer.spotIds = ["sp_yashima"]
        await engine.showSaved([AskExchange(question: "香川で夕日は？", answer: answer)], backend: backend)
        XCTAssertEqual(engine.thread.first?.question, "香川で夕日は？")
        XCTAssertNotNil(engine.spotsById["sp_yashima"], "控えの札の中身を読み直していない")
        XCTAssertEqual(c.reserves + c.deviceAsks + c.serverAsks, 0, "控えを見るだけで AI か回数を使った")
    }
}
