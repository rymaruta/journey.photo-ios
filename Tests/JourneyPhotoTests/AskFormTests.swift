import XCTest
@testable import JourneyPhoto

/// 「AI に頼む」の答えの形の最初の版（札 #675・2026-11-21 判断・Artifact「AI に頼む 独立の案」版3「答えの形 磨いた推奨」）。
/// owner「ブラッシュアップしてから推奨でお願い」
final class AskFormTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func answer(_ engine: AskAnswer.Engine = .device, spots: [String] = [], kind: AskAnswerKind? = nil) -> AskAnswer {
        var a = AskAnswer(engine: engine, text: "秋の京都なら、東山の寺が向いています。")
        a.spotIds = spots
        a.kind = kind
        return a
    }

    // MARK: - 種類は字から先に分かる（押した瞬間から形の骨格）

    func testKindByWords() {
        XCTAssertEqual(AskAnswerKind.byWords("京都で2日の旅行プランにして"), .plan)
        XCTAssertEqual(AskAnswerKind.byWords("金沢に1泊2日の旅行プランを作って"), .plan)
        XCTAssertEqual(AskAnswerKind.byWords("永観堂と東福寺どっちがいい？"), .compare)
        XCTAssertEqual(AskAnswerKind.byWords("永観堂の写真を見せて"), .photos)
        XCTAssertEqual(AskAnswerKind.byWords("ストーリーに曲を付けるには"), .steps)
        XCTAssertEqual(AskAnswerKind.byWords("秋に紅葉がきれいな京都の所は？"), .cards)
        XCTAssertNil(AskAnswerKind.byWords(""))
        XCTAssertEqual(AskAnswerKind.parse(" Cards "), .cards)
        XCTAssertNil(AskAnswerKind.parse("table"), "知らない種類を読めたことにした")
        XCTAssertFalse(AskAnswerKind.deviceChoices.contains("plan"), "端末の AI に旅行プランを選ばせている（旅行プランの AI の仕事）")
    }

    // MARK: - 形の選び方

    func testLayoutPerAnswer() {
        XCTAssertEqual(AskAnswerLayout.layout(for: answer(spots: ["a", "b"])), .spotCarousel)
        XCTAssertEqual(AskAnswerLayout.layout(for: answer(spots: ["a", "b"]), largeText: true), .spotStack, "大きな字で札を縦に積まない")
        XCTAssertEqual(AskAnswerLayout.layout(for: answer(spots: ["a"])), .spotWide, "1か所の答えを広い札にしない")
        XCTAssertEqual(AskAnswerLayout.layout(for: answer(spots: [])), .leadOnly)
        XCTAssertEqual(AskAnswerLayout.layout(for: .refused(care: false)), .leadOnly)
        var unreadable = answer(spots: ["a", "b"])
        unreadable.unreadable = true
        XCTAssertEqual(AskAnswerLayout.layout(for: unreadable), .leadOnly, "形が読めなかった答えに札を出した")
        var plan = answer(spots: ["a", "b"], kind: .plan)
        plan.plan = AskPlanAnswer(title: "京都の旅", planId: "p1", days: [["a"], ["b"]])
        XCTAssertEqual(AskAnswerLayout.layout(for: plan), .planFlow)
        plan.plan?.days = [[]]
        XCTAssertEqual(AskAnswerLayout.layout(for: plan), .spotCarousel, "空の流れを出した")
    }

    /// 形が読めなかった: AI が札と言ったのに台帳に戻る番号が無い。種類を返さない答え（今のサーバー）は読めなかったとしない
    func testUnreadableOnlyWhenDeclaredFormHasNoSpots() {
        XCTAssertTrue(AskFormCheck.unreadable(ai: .cards, spotCount: 0))
        XCTAssertTrue(AskFormCheck.unreadable(ai: .compare, spotCount: 0))
        XCTAssertFalse(AskFormCheck.unreadable(ai: .cards, spotCount: 2))
        XCTAssertFalse(AskFormCheck.unreadable(ai: .text, spotCount: 0))
        XCTAssertFalse(AskFormCheck.unreadable(ai: nil, spotCount: 0))
        XCTAssertEqual(AskFormCheck.kind(ai: nil, words: nil, spotCount: 3), .cards)
        XCTAssertEqual(AskFormCheck.kind(ai: nil, words: nil, spotCount: 0), .text)
        XCTAssertEqual(AskFormCheck.kind(ai: .steps, words: .cards, spotCount: 0), .steps)
    }

    // MARK: - 台帳に無い場所を出さない

    func testLeadWithUnknownPlaceIsReplaced() throws {
        let ledger = try AskSamples.ledger()
        let shown = [ledger[2]]  // 永観堂
        XCTAssertEqual(AskLeadCheck.placeNames(in: "架空寺と永観堂がおすすめです。"), ["架空寺"])
        XCTAssertTrue(AskLeadCheck.hasUnknownPlace("架空寺がおすすめです。", shown: shown, ledger: ledger))
        XCTAssertFalse(AskLeadCheck.hasUnknownPlace("お寺の多い町です。", shown: shown, ledger: ledger), "「お寺」を場所の名前とした")
        XCTAssertFalse(AskLeadCheck.hasUnknownPlace("秋の京都なら、東山の寺が向いています。", shown: shown, ledger: ledger))
        XCTAssertEqual(AskLeadCheck.safeLead("架空滝が見頃です。", shown: shown, ledger: ledger, season: "秋"), "秋に向く所を1つ選びました。")
        XCTAssertEqual(AskLeadCheck.safeLead("池に映る紅葉で知られる寺です。", shown: shown, ledger: ledger, season: "秋"),
                       "池に映る紅葉で知られる寺です。")
        // 2026-11-21 判断（確かめ役の指摘）: 札の無い答え（文だけ、形が読めなかった）も台帳全体と照らす
        XCTAssertEqual(AskLeadCheck.safeLead("架空寺の話です。", shown: [], ledger: ledger, season: nil), AskLeadCheck.unknownPlaceLine)
        XCTAssertEqual(AskLeadCheck.safeLead("永観堂は紅葉の寺です。", shown: [], ledger: ledger, season: nil), "永観堂は紅葉の寺です。",
                       "台帳にある名前の文を替えた")
        XCTAssertEqual(AskLeadCheck.safeLead("太陽は画面の端に置きます。", shown: [], ledger: ledger, season: nil), "太陽は画面の端に置きます。")
    }

    // MARK: - 一手（アプリが決める・押しても AI は呼ばない）

    func testActsPerForm() {
        let cards = answer(spots: ["a", "b"])
        XCTAssertEqual(AskAct.acts(for: cards, layout: .spotCarousel, signedIn: true, offline: false), [.makePlan, .share])
        XCTAssertEqual(AskAct.acts(for: cards, layout: .spotCarousel, signedIn: true, offline: true), [.makePlan], "圏外で仲間に送るを出した")
        XCTAssertEqual(AskAct.acts(for: cards, layout: .spotWide, signedIn: false, offline: false), [.share])
        XCTAssertEqual(AskAct.acts(for: .refused(care: false), layout: .leadOnly, signedIn: true, offline: false), [], "断った答えに一手を出した")
        var plan = answer(spots: ["a"], kind: .plan)
        plan.plan = AskPlanAnswer(title: "京都の旅", planId: "p1", days: [["a"]])
        XCTAssertEqual(AskAct.acts(for: plan, layout: .planFlow, signedIn: true, offline: false), [.sharePlan, .openPlan])
        XCTAssertEqual(AskAct.acts(for: plan, layout: .planFlow, signedIn: true, offline: true), [.openPlan])
        plan.plan?.planId = nil
        XCTAssertEqual(AskAct.acts(for: plan, layout: .planFlow, signedIn: true, offline: false), [])
        var failed = cards
        failed.state = .failed
        XCTAssertEqual(AskAct.acts(for: failed, layout: .spotCarousel, signedIn: true, offline: false), [])
    }

    // MARK: - 次に頼めること（アプリが作る・欄に入るだけ）

    func testNextAsksAreAppMadeSafeAndSendable() throws {
        let ledger = try AskSamples.ledger()
        let kagawa = [ledger[0], ledger[1]]
        let cards = AskNextAsks.make(for: answer(spots: kagawa.map(\.spotId)), layout: .spotCarousel, spots: kagawa)
        XCTAssertEqual(cards.first, "この中で夕方の斜光に向く所は？")
        XCTAssertTrue(cards.contains("香川で2日の旅行プランにして"))
        XCTAssertEqual(AskEntry.route("香川で2日の旅行プランにして"), .tripPlan, "旅行プランの次に頼めることが旅行プランの AI へ行かない")
        let wide = AskNextAsks.make(for: answer(spots: [ledger[2].spotId]), layout: .spotWide, spots: [ledger[2]])
        XCTAssertTrue(wide.contains("永観堂の写真を見せて"))
        XCTAssertEqual(AskNextAsks.make(for: answer(), layout: .leadOnly, spots: []), ["近くの観光スポットは？", "旅行プランを作る", "写真を見る"])
        XCTAssertEqual(AskNextAsks.make(for: .refused(care: false), layout: .leadOnly, spots: []), [], "断った答えに次に頼めることを出した")
        var plan = answer(spots: kagawa.map(\.spotId), kind: .plan)
        plan.plan = AskPlanAnswer(title: "香川の旅", planId: "p1", days: [kagawa.map(\.spotId)])
        let afterPlan = AskNextAsks.make(for: plan, layout: .planFlow, spots: kagawa)
        XCTAssertEqual(afterPlan, ["屋島ってどんな所？", "父母ヶ浜ってどんな所？"])
        // どれも送れて、断られず、台帳に無いこと（宿、混み具合、雨）を言わない
        for chip in cards + wide + afterPlan + AskNextAsks.fixed {
            XCTAssertFalse(AskGuard.declinesBeforeAsking(chip), "次に頼めることが断られる: \(chip)")
            for banned in ["宿", "ホテル", "混み", "雨", "アプリの作り"] {
                XCTAssertFalse(chip.contains(banned), "台帳に無いことを次に頼めることに出した: \(chip)")
            }
        }
        for chip in cards + wide + afterPlan { XCTAssertTrue(AskEntry.sendEnabled(chip), "次に頼めることが送れない: \(chip)") }
    }

    /// 次に頼めることと一手は AI を呼ばない（チップは欄に入れるだけ。一手は送るシート、旅行プランの保存、招待のリンク）
    func testChipsAndActsNeverCallAI() throws {
        let parts = try source("Sources/JourneyPhoto/Features/Search/AskAnswerParts.swift")
        for banned in ["AskEngine", ".start(", "followUp(", "AskDevice.", "env.ask.", "environment.ask."] {
            XCTAssertFalse(parts.contains(banned), "答えの部品が AI を呼んでいる: \(banned)")
        }
        let thread = try source("Sources/JourneyPhoto/Features/Search/AskThreadView.swift")
        XCTAssertTrue(thread.contains("AskNextChips(chips: next, onFill: onFill)"), "次に頼めることが欄に入れる口を通らない")
        let screen = try source("Sources/JourneyPhoto/Features/Search/AskScreen.swift")
        let fill = try XCTUnwrap(screen.range(of: "onFill: { text in"))
        let body = screen[fill.upperBound...].prefix(160)
        XCTAssertTrue(body.contains("draft = text"), "次に頼めることが欄に入らない")
        XCTAssertFalse(body.contains("send("), "次に頼めることを押しただけで送った")
        // 旅行プランにするは AI を使わない（座標で並べて保存するだけ）
        let make = try XCTUnwrap(thread.range(of: "private func makePlan("))
        let makeBody = thread[make.upperBound...].prefix(1200)
        XCTAssertTrue(makeBody.contains("AskQuickPlan.days"))
        XCTAssertFalse(makeBody.contains("TripAIJobs") || makeBody.contains("tripAI"), "旅行プランにするで AI を使った")
    }

    /// 仲間に送るのはリンクだけ（観光スポットの頁。画像のファイルは渡さない）。下書きは送らない。3か所まで
    func testShareSendsLinksOnly() throws {
        let ledger = try AskSamples.ledger()
        let base = URL(string: "https://journey.example")!
        let links = AskShareLinks.links(ledger, siteBase: base)
        XCTAssertEqual(links.count, AskShareLinks.maxLinks)
        XCTAssertFalse(links.contains { $0.name == "下書きの所" }, "下書きのリンクを送る")
        XCTAssertTrue(links.allSatisfy { $0.url.absoluteString.hasPrefix("https://journey.example/") })
        XCTAssertEqual(AskShareLinks.what(["永観堂", "東福寺"]), "観光スポット 2つ（永観堂、東福寺）をリンクで送ります")
        let parts = try source("Sources/JourneyPhoto/Features/Search/AskAnswerParts.swift")
        for banned in ["UIImage", "Image(uiImage", "ImageRenderer", ".otherApps(image", "PHPhotoLibrary", "UIImageWriteToSavedPhotosAlbum"] {
            XCTAssertFalse(parts.contains(banned), "仲間に送るで画像を渡している: \(banned)")
        }
        XCTAssertTrue(parts.contains("DMSpotShare.send("), "DM へリンクで送っていない")
    }

    // MARK: - 前の答えを畳む

    func testFoldSummary() throws {
        // 2026-11-21 判断（確かめ役の指摘）: 「札」は中の言葉。「観光スポット」と言う
        XCTAssertEqual(AskFold.summary(answer(spots: ["a", "b"]), names: ["永観堂", "東福寺"]), "観光スポット2つ（永観堂、東福寺）")
        XCTAssertEqual(AskFold.summary(answer(spots: ["a"]), names: ["永観堂"]), "観光スポット1つ（永観堂）")
        XCTAssertEqual(AskFold.summary(answer(spots: ["a", "b", "c"]), names: ["永観堂", "東福寺", "清水寺"]), "観光スポット3つ（永観堂、東福寺ほか）")
        XCTAssertEqual(AskFold.summary(.refused(care: false), names: []), "お答えできない質問")
        var plan = answer(spots: ["a", "b", "c"], kind: .plan)
        plan.plan = AskPlanAnswer(title: "京都の旅", planId: "p1", days: [["a", "b"], ["c"]])
        XCTAssertEqual(AskFold.summary(plan, names: []), "旅行プラン 2日（3か所）")
        let thread = try source("Sources/JourneyPhoto/Features/Search/AskThreadView.swift")
        XCTAssertTrue(thread.contains("if inScreen, !isLatest, !expanded.contains(exchange.id)"), "前の答えを畳んでいない")
    }

    /// 「2日の旅行プランにして」は行き先と日数がそろい、シートを出さずに流れで作る（回 1658 で日数が読めずシートに倒れた）
    func testTwoDayPlanWordsAreComplete() throws {
        XCTAssertEqual(TripAIDays.parse("京都で2日の旅行プランにして"), 2)
        XCTAssertEqual(TripAIDays.parse("香川で2日の旅行プランにして"), 2)
        XCTAssertNil(TripAIDays.parse("11月3日の旅のおすすめは？"), "日付を日数と読んだ")
        XCTAssertNil(TripAIDays.parse("11月 3日の旅のおすすめは？"), "間に空白のある日付を日数と読んだ")
        XCTAssertNil(TripAIDays.parse("11月3〜4日の旅のおすすめは？"), "日付の幅を日数と読んだ")
        XCTAssertNil(TripAIDays.parse("3日〜4日の旅"), "日付の幅を日数と読んだ")
        let spots = try AskSamples.ledger()
        XCTAssertTrue(TripAIAsk.reading("香川で2日の旅行プランにして", spots: spots).isComplete)
    }

    /// 探すの1行から来た字は AI の画面が受け取る（回 1658: 全画面の中身が古い値で作られ、字が入らなかった）
    func testAskScreenTakesCarriedWords() throws {
        let screen = try source("Sources/JourneyPhoto/Features/Search/AskScreen.swift")
        XCTAssertTrue(screen.contains("TabRouter.shared.takePendingAskText()"), "AI の画面が運ばれた字を受け取らない")
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertFalse(root.contains("tabRouter.takePendingAskText()"), "全画面を開く前に字を受け取って消している")
    }

    // MARK: - 確かめ役の指摘（2026-11-21）

    /// 全画面の AI の画面の上でも知らせが見える（アプリの下の知らせは裏に隠れる）。下の欄の上に1つだけ
    func testAskScreenShowsToasts() throws {
        let screen = try source("Sources/JourneyPhoto/Features/Search/AskScreen.swift")
        XCTAssertEqual(screen.components(separatedBy: "ToastOverlay()").count - 1, 1, "AI の画面に知らせの置き場が無い（か2つある）")
        XCTAssertTrue(screen.contains(".padding(.bottom, AskScreen.toastBottomPadding)"))
        XCTAssertGreaterThanOrEqual(AskScreen.toastBottomPadding, 90, "知らせが下の欄に重なる")
        // 答えの部品は自分で知らせの置き場を持たない（二重に出さない）
        for file in ["Sources/JourneyPhoto/Features/Search/AskThreadView.swift", "Sources/JourneyPhoto/Features/Search/AskAnswerParts.swift"] {
            XCTAssertFalse(try source(file).contains("ToastOverlay()"), "\(file) に知らせの置き場がある（二重に出る）")
        }
    }

    /// ログインしていない人の旅行プランの頼みは、今のログインの画面で案内する（シートの「この内容で作る」で黙って止まらない）
    func testTripPlanSignedOutAsksToSignIn() throws {
        let screen = try source("Sources/JourneyPhoto/Features/Search/AskScreen.swift")
        let send = try XCTUnwrap(screen.range(of: "private func send(_ raw: String) {"))
        let body = String(screen[send.upperBound...].prefix(900))
        let gate = try XCTUnwrap(body.range(of: "SignInPrompt.request(AskEntry.planSignIn"), "旅行プランの頼みでログインを確かめていない")
        let clear = try XCTUnwrap(body.range(of: "draft = \"\""))
        XCTAssertLessThan(gate.lowerBound, clear.lowerBound, "ログインを確かめる前に欄の字を消している")
        XCTAssertTrue(screen.contains("SignInSheet(reason: request.reason, entry: request.entry)"), "ログインの画面を開いていない")
        XCTAssertEqual(AskEntry.planSignIn, "旅行プランを作るにはログインしてください")
        XCTAssertNotNil(SignInPrompt.request(AskEntry.planSignIn, signUpReason: AskEntry.planSignUp, userId: nil, isResolving: false))
        XCTAssertNil(SignInPrompt.request(AskEntry.planSignIn, signUpReason: AskEntry.planSignUp, userId: "u1", isResolving: false))
    }

    /// 帯の「✦ AI に頼む」は白（ガラスの帯の下を写真が流れる。真鍮は黒地の上だけ）。狭い iPhone は ✦ だけ
    func testHeaderAskEntryIsWhiteAndFitsNarrowPhones() throws {
        let header = try source("Sources/JourneyPhoto/Features/Common/AppHeader.swift")
        let button = try XCTUnwrap(header.range(of: "struct AskEntryButton"))
        let body = String(header[button.upperBound...].prefix(4000))
        XCTAssertTrue(body.contains(".foregroundStyle(AskEntryButton.tint)"))
        XCTAssertFalse(body.contains(".foregroundStyle(WebTheme.accent)"), "帯の入口の字が真鍮")
        XCTAssertTrue(AskEntryButton.iconOnly(largeText: false, windowWidth: 375), "iPhone SE（375pt）で字を出すとロゴが押される")
        XCTAssertTrue(AskEntryButton.iconOnly(largeText: false, windowWidth: 390))
        XCTAssertFalse(AskEntryButton.iconOnly(largeText: false, windowWidth: 402))
        XCTAssertFalse(AskEntryButton.iconOnly(largeText: false, windowWidth: 440))
        XCTAssertFalse(AskEntryButton.iconOnly(largeText: false, windowWidth: nil))
        XCTAssertTrue(AskEntryButton.iconOnly(largeText: true, windowWidth: 440))
        // 配置の計算: ✦ だけなら 375pt でもロゴ（縮めて約147）が入る
        let trailing: CGFloat = 44 + 44 * 3
        let margins: CGFloat = 16 * 2 + 16
        XCTAssertGreaterThanOrEqual(375 - trailing - margins, 147)
    }

    // MARK: - 流れ

    func testPlanFlowParts() throws {
        let ledger = try AskSamples.ledger()
        let days = [[ledger[0], ledger[1]], [ledger[2]]]
        XCTAssertEqual(AskPlanTimeline.numbers(days), [[1, 2], [3]], "番号を日ごとに数え直した")
        XCTAssertEqual(AskPlanFlowText.dayTitle(0, spots: days[0]), "1日目\u{3000}高松市")
        let minutes = try XCTUnwrap(AskPlanFlowText.moveMinutes(ledger[0], ledger[1]))
        XCTAssertEqual(minutes % 5, 0)
        XCTAssertGreaterThan(minutes, 60, "屋島から父母ヶ浜（約47km）が1時間かからない見積もり")
        XCTAssertEqual(AskPlanFlowText.moveLine(15), "移動の目安 約15分")
        XCTAssertEqual(AskPlanFlowText.moveLine(90), "移動の目安 約1時間30分")
        XCTAssertEqual(AskPlanFlowText.lead(reason: "", usedAI: false, days: 2), "観光スポットの位置で、2日に並べました。")
        let quick = AskQuickPlan.days([ledger[0], ledger[1], ledger[2]])
        XCTAssertFalse(quick.isEmpty)
        XCTAssertEqual(quick.flatMap { $0 }.count, 3, "旅行プランにするで場所が抜けた")
        XCTAssertFalse(AskQuickPlan.title(quick).isEmpty)
    }

    // MARK: - 手順（AskEngine）

    private final class Counter { var reserves = 0; var deviceAsks = 0; var serverAsks = 0 }

    private func backend(_ c: Counter, rows: [OfficialSpot], device: AskDevice.Result?) -> AskEngine.Backend {
        AskEngine.Backend(
            signedIn: { true }, offline: { false }, deviceAI: { true },
            library: { _ in AskLibrary(spots: rows, photos: []) },
            reserve: { kind, _ in
                c.reserves += 1
                return AskUsage(tier: "free", kind: kind.rawValue, day: .init(used: 1, limit: 3, remaining: 2),
                                month: .init(used: 1, limit: 10, remaining: 9, resetsOn: "2026-12-01"), serverAllowed: false)
            },
            serverAsk: { _, _, _ in c.serverAsks += 1; return AskService.ServerAnswer(answer: "", general: false) },
            deviceAsk: { _, _, _ in c.deviceAsks += 1; return device },
            details: { $0 }, userId: { "u1" })
    }

    @MainActor
    private func engine() -> AskEngine {
        AskEngine(history: AskHistoryStore(defaults: UserDefaults(suiteName: "AskFormTests.\(UUID().uuidString)")!))
    }

    /// 端末の AI が札と言ったのに台帳を引かず、文だけの頼みだった: 形が読めなかった（頭の文だけ）
    @MainActor
    func testDeviceDeclaredCardsWithoutSpotsIsUnreadable() async throws {
        let c = Counter()
        let rows = try AskSamples.ledger()
        let result = AskDevice.Result(text: "太陽は画面の端に置くと、空の色が残ります。", general: true, picks: [], photoIds: [], sources: [], kind: "cards")
        let e = engine()
        await e.start("夕日をきれいに撮るこつは？", backend: backend(c, rows: rows, device: result))
        let a = try XCTUnwrap(e.thread.last?.answer)
        XCTAssertEqual(a.unreadable, true)
        XCTAssertEqual(AskAnswerLayout.layout(for: a), .leadOnly)
        XCTAssertEqual(c.reserves, 1, "回数の数え方が変わった（AI を呼んだら1回）")
    }

    /// 頭の文に台帳に無い場所らしい名前があれば決まり文。種類は AI が返したもの
    @MainActor
    func testDeviceLeadWithUnknownPlaceUsesFixedLine() async throws {
        let c = Counter()
        let rows = try AskSamples.ledger()
        let picks = rows.prefix(2).map { AskLibrary.Pick(spot: $0, distanceKm: nil) }
        let result = AskDevice.Result(text: "架空寺と屋島がおすすめです。", general: false, picks: Array(picks), photoIds: [],
                                      sources: [.init(kind: .spots, label: AskText.spotsSource)], kind: "cards")
        let e = engine()
        await e.start("香川で夕日がきれいな所は？", backend: backend(c, rows: rows, device: result))
        let a = try XCTUnwrap(e.thread.last?.answer)
        XCTAssertEqual(a.kind, .cards)
        XCTAssertFalse(a.text.contains("架空寺"), "台帳に無い場所の名前を頭の文に出した")
        XCTAssertEqual(a.text, "合う所を2つ選びました。")
        XCTAssertEqual(e.freshId, e.thread.last?.id, "届いた答えを少しずつ出す印が付かない")
    }

    /// 字から種類が分かる頼みは、押した瞬間から形の骨格（`pendingKind`）
    @MainActor
    func testPendingKindFromWords() async {
        let e = engine()
        e.prepare("秋に紅葉がきれいな京都の所は？")
        XCTAssertEqual(e.pendingKind, .cards)
        XCTAssertEqual(e.beginPlan("京都で2日の旅行プランにして"), nil, "待っている間に旅行プランを始めた")
        e.reset()
        XCTAssertNil(e.pendingKind)
        XCTAssertEqual(e.beginPlan("京都で2日の旅行プランにして"), "京都で2日の旅行プランにして")
        XCTAssertEqual(e.pendingKind, .plan)
    }

    /// 旅行プランの流れ: 旅行プランの AI の答えを流れにする。**AI に頼むの回数は使わない**（旅行プランの AI の枠）
    @MainActor
    func testFinishPlanMakesFlowWithoutAskCount() async throws {
        let rows = try AskSamples.ledger()
        let e = engine()
        let q = try XCTUnwrap(e.beginPlan("香川で2日の旅行プランにして"))
        let result = TripAIResult(title: "香川の旅", days: [[rows[0]], [rows[1]]], reason: "1日目は高松、2日目は三豊にまとめました。移動は短めです。",
                                  removed: [], mode: .ai, candidates: [])
        e.finishPlan(q, result: result, planId: "plan_1", onDevice: true, userId: "u1")
        let a = try XCTUnwrap(e.thread.last?.answer)
        XCTAssertEqual(a.kind, .plan)
        XCTAssertEqual(a.engine, .device)
        XCTAssertEqual(a.plan?.planId, "plan_1")
        XCTAssertEqual(a.plan?.days, [["sp_yashima"], ["sp_chichibugahama"]])
        XCTAssertEqual(a.text, "1日目は高松、2日目は三豊にまとめました。移動は短めです。")
        XCTAssertEqual(AskAnswerLayout.layout(for: a), .planFlow)
        XCTAssertNil(e.pending)
        XCTAssertNil(e.usage, "旅行プランの流れで AI に頼むの回数を取った")
        XCTAssertNotNil(e.spotsById["sp_yashima"], "流れの観光スポットを覚えていない")
    }

    @MainActor
    func testPlanFailureAndLeak() async throws {
        let rows = try AskSamples.ledger()
        let e = engine()
        let q = try XCTUnwrap(e.beginPlan("香川で2日の旅行プランにして"))
        e.failPlan(q, line: "「香川の旅」を作れませんでした。電波が届いていません", userId: "u1")
        XCTAssertEqual(e.thread.last?.answer.state, .failed)
        XCTAssertEqual(AskFold.summary(try XCTUnwrap(e.thread.last?.answer), names: []), "旅行プランを作れませんでした")
        // 理由の文に作りの話が混じったら断りに替える（見張り）
        let q2 = try XCTUnwrap(e.beginPlan("香川で2日の旅行プランにして"))
        let leak = TripAIResult(title: "香川の旅", days: [[rows[0]]], reason: "TRIP_AI_MODEL_ID を使って並べました。", removed: [], mode: .ai, candidates: [])
        e.finishPlan(q2, result: leak, planId: "plan_2", onDevice: true, userId: "u1")
        XCTAssertEqual(e.thread.last?.answer.engine, .refused, "作りの話が混じった理由を出した")
        // 画面を閉じたら待つのをやめる（仕事は旅行プランの AI が続ける）
        _ = e.beginPlan("香川で2日の旅行プランにして")
        e.cancelPlan()
        XCTAssertNil(e.pending)
    }

    /// 控えから出した答えは少しずつ出さない（もう見た答え）
    @MainActor
    func testSavedAnswersAreNotFresh() async throws {
        let c = Counter()
        let rows = try AskSamples.ledger()
        let e = engine()
        var a = AskAnswer(engine: .device, text: "屋島がおすすめです。")
        a.spotIds = ["sp_yashima"]
        await e.showSaved([AskExchange(question: "香川で夕日は？", answer: a)], backend: backend(c, rows: rows, device: nil))
        XCTAssertNil(e.freshId)
        XCTAssertEqual(c.reserves + c.deviceAsks + c.serverAsks, 0)
    }

    /// サーバーが種類と頭の文を返したら使う（今のサーバーは返さない。返さなくても今のまま動く）
    func testServerAnswerReadsOptionalKindAndLead() throws {
        let old = try JSONDecoder().decode(AskService.ServerAnswer.self, from: Data(#"{"answer":"夕方の案内がある所です。","general":false}"#.utf8))
        XCTAssertNil(old.kind)
        XCTAssertNil(old.lead)
        let new = try JSONDecoder().decode(AskService.ServerAnswer.self,
                                           from: Data(#"{"answer":"","general":false,"kind":"cards","lead":"夕日なら屋島です。"}"#.utf8))
        XCTAssertEqual(new.kind, "cards")
        XCTAssertEqual(new.lead, "夕日なら屋島です。")
    }
}
