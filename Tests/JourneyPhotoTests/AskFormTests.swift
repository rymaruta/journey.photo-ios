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
        XCTAssertTrue(screen.contains(".padding(.bottom, AskScreen.toastBottomPadding(composer: composerHeight))"))
        XCTAssertGreaterThanOrEqual(AskScreen.toastBottomPadding(composer: 0), 90, "測る前に知らせが下の欄に重なる")
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

    /// 2026-11-21（バグ調べ）: 仲間に送るの顔の一覧は、人が替わったら捨てて読み直す（前の人のフォロー中の顔を出さない）
    @MainActor
    func testShareFacesAreDroppedWhenTheUserChanges() async throws {
        XCTAssertFalse(AskActFlow.dropsFaces(owner: nil, me: "u1"), "まだ読んでいない")
        XCTAssertFalse(AskActFlow.dropsFaces(owner: "u1", me: "u1"))
        XCTAssertTrue(AskActFlow.dropsFaces(owner: "u1", me: "u2"), "前の人の顔を持ち続けた")
        XCTAssertTrue(AskActFlow.dropsFaces(owner: "u1", me: nil), "ログアウトしても顔を持ち続けた")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let parts = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Search/AskAnswerParts.swift"), encoding: .utf8)
        XCTAssertTrue(parts.contains("if Self.dropsFaces(owner: facesOwner, me: auth.userId)"), "読む前に人を確かめていない")
        XCTAssertTrue(parts.contains("facesOwner = me"))
    }

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
        // 2026-11-21（バグ調べ）: ちょうどの時間は分を付けない（英語で「About 1h 0m」と出ていた）
        XCTAssertEqual(AskPlanFlowText.moveLine(60, language: "ja"), "移動の目安 約1時間")
        XCTAssertEqual(AskPlanFlowText.moveLine(60, language: "en"), "About 1h to move")
        XCTAssertEqual(AskPlanFlowText.moveLine(120, language: "en"), "About 2h to move")
        XCTAssertEqual(AskPlanFlowText.moveLine(95, language: "en"), "About 1h 35m to move")
        XCTAssertEqual(AskPlanFlowText.moveLine(15, language: "en"), "About 15 min to move")
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
        await e.open(.init(id: "c1", thread: [AskExchange(question: "香川で夕日は？", answer: a)]), backend: backend(c, rows: rows, device: nil))
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

    /// 注意書きは公式の言い方で、確かめ先を添える（2026-11-21 owner）
    func testDisclaimerIsOfficialWording() {
        let text = AskText.disclaimer
        XCTAssertTrue(text.hasPrefix("※"))
        XCTAssertTrue(text.contains("誤りが含まれる場合があります"))
        XCTAssertTrue(text.contains("公式の情報でご確認ください"))
        XCTAssertFalse(text.contains("・"))
        XCTAssertFalse(text.contains("間違う"))
    }

    /// 答えごとの「どこで答えたか」の1行は出さない（2026-11-22 owner「この文章出す意味ある？」）
    func testAnswerShowsNoEngineLine() throws {
        let thread = try source("Sources/JourneyPhoto/Features/Search/AskThreadView.swift")
        let answer = try source("Sources/JourneyPhoto/Core/AI/AskAnswer.swift")
        XCTAssertFalse(thread.contains("search.ask.engine\""), "答えの下の1行が残っている")
        XCTAssertFalse(thread.contains("engineLine"))
        XCTAssertFalse(answer.contains("var engineLine"))
        for old in ["サーバーの AI で答えました", "この iPhone の中で答えました", "この iPhone の中で言葉を読み"] {
            XCTAssertFalse(answer.contains(old), old)
            XCTAssertFalse(thread.contains(old), old)
        }
    }

    private func notice(signedIn: Bool = true, deviceAI: Bool = false, tier: String? = nil, profilePro: Bool? = nil,
                        admin: Bool = false, thread: [AskExchange] = []) -> Bool {
        AskServerNotice.shows(signedIn: signedIn, deviceAI: deviceAI, tier: tier, profilePro: profilePro, admin: admin, thread: thread)
    }

    /// 送信の知らせはサーバーの AI を使う人にだけ出す。**分からない間は出す**（送る前に必ず見える・2026-11-22 確かめ役の指摘）
    func testServerNoticeOnlyOnServerPath() {
        // 端末の AI が使える iPhone: Pro でも管理者でも出さない（打った文はサーバーに送らない）
        XCTAssertFalse(notice(deviceAI: true, tier: "pro", profilePro: true, admin: true))
        // ログインしていない: サーバーに送らない
        XCTAssertFalse(notice(signedIn: false, profilePro: true))
        // 端末の AI が無い iPhone: Pro と分かっていれば出す
        XCTAssertTrue(notice(tier: "pro"))
        XCTAssertTrue(notice(profilePro: true))
        // 無料と分かっていれば出さない
        XCTAssertFalse(notice(tier: "free", profilePro: false))
        XCTAssertFalse(notice(profilePro: false))
        XCTAssertFalse(notice(tier: "free"))
        // サーバーで答えた答え、旅行プランでサーバーへ送った答えが会話にあれば出す
        let served = AskExchange(question: "香川で夕日は？", answer: AskAnswer(engine: .server, text: "x"))
        XCTAssertTrue(notice(signedIn: false, deviceAI: true, thread: [served]))
        var plan = AskAnswer(engine: .table, text: "x")
        plan.kind = .plan
        plan.serverSent = true
        XCTAssertTrue(notice(deviceAI: true, profilePro: false, thread: [AskExchange(question: "香川で2日", answer: plan)]))
        let local = AskExchange(question: "香川で夕日は？", answer: AskAnswer(engine: .device, text: "x"))
        XCTAssertFalse(notice(deviceAI: true, thread: [local]))
    }

    /// 出ないまま送られる4つの場面（2026-11-22 確かめ役の指摘）
    func testServerNoticeShowsBeforeEverySend() {
        // (a) プロフィールの読み込みが遅い、失敗した（nil のまま）
        XCTAssertTrue(notice(tier: nil, profilePro: nil))
        // (b) 管理者（サーバーは許すが、プロフィールの Pro は false）
        XCTAssertTrue(notice(profilePro: false, admin: true))
        XCTAssertTrue(notice(tier: "admin", profilePro: false))
        // (c) 前に読んだ回数（無料・serverAllowed false）が残ったまま Pro を買った
        XCTAssertTrue(notice(tier: "free", profilePro: true))
        // (d) 旅行プランの頼み: AI に頼むの上限に達していても、旅行プランの枠でサーバーへ送る（serverAllowed を見ない）
        XCTAssertTrue(notice(tier: "pro", profilePro: true))
    }

    /// 旅行プランの AI がサーバーへ送った回は、AI なしの答えや断りになっても「送った」を残す
    @MainActor
    func testPlanSentToServerIsKept() async throws {
        let rows = try AskSamples.ledger()
        let e = engine()
        let q = try XCTUnwrap(e.beginPlan("香川で2日の旅行プランにして"))
        let silent = TripAIResult(title: "香川の旅", days: [[rows[0]]], reason: "", removed: [], mode: .silent, candidates: [])
        e.finishPlan(q, result: silent, planId: "plan_1", onDevice: false, userId: "u1", askedServer: true)
        XCTAssertEqual(e.thread.last?.answer.engine, .table)
        XCTAssertTrue(try XCTUnwrap(e.thread.last?.answer).sentToServer, "送ったのに知らせの条件から落ちた")
        let q2 = try XCTUnwrap(e.beginPlan("香川で2日の旅行プランにして"))
        e.failPlan(q2, line: "作れませんでした", userId: "u1", askedServer: true)
        XCTAssertTrue(try XCTUnwrap(e.thread.last?.answer).sentToServer)
        let q3 = try XCTUnwrap(e.beginPlan("香川で2日の旅行プランにして"))
        let leak = TripAIResult(title: "香川の旅", days: [[rows[0]]], reason: "TRIP_AI_MODEL_ID を使って並べました。", removed: [], mode: .ai, candidates: [])
        e.finishPlan(q3, result: leak, planId: "plan_3", onDevice: false, userId: "u1", askedServer: true)
        XCTAssertEqual(e.thread.last?.answer.engine, .refused)
        XCTAssertTrue(try XCTUnwrap(e.thread.last?.answer).sentToServer, "断りに替えた回で送ったことが消えた")
        // 端末の AI で組んだ回は送っていない
        let q4 = try XCTUnwrap(e.beginPlan("香川で2日の旅行プランにして"))
        let ok = TripAIResult(title: "香川の旅", days: [[rows[0]]], reason: "", removed: [], mode: .ai, candidates: [])
        e.finishPlan(q4, result: ok, planId: "plan_4", onDevice: true, userId: "u1")
        XCTAssertFalse(try XCTUnwrap(e.thread.last?.answer).sentToServer)
    }

    /// 画面が正しい値を渡している（端末の AI、ログイン、Pro、管理者、会話）。同じ値を旅行プランのシートにも渡す
    func testScreensPassNoticeInputs() throws {
        let screen = try source("Sources/JourneyPhoto/Features/Search/AskScreen.swift")
        XCTAssertTrue(screen.contains("AskServerNotice.shows(signedIn: auth.userId != nil, deviceAI: noticeDeviceAI, tier: engine.usage?.tier,"))
        XCTAssertTrue(screen.contains("profilePro: profilePro, admin: auth.isAdmin, thread: engine.thread)"))
        XCTAssertTrue(screen.contains("(deviceAIAvailable && TripAIRunner.usesDeviceAI)"), "旅行プランの AI の端末の見方を入れていない")
        XCTAssertTrue(screen.contains("private var deviceAIAvailable: Bool { AskFixture.isOn ? AskFixture.deviceAI : OnDeviceAI.isAvailable }"))
        XCTAssertTrue(screen.contains("Text(AskText.footnote(server: showsServerNotice))"))
        XCTAssertTrue(screen.contains("AskPlanFlow(ask: $planAsk, index: officialSpots, placeChoices: placeChoices, serverNotice: showsServerNotice)"))
        XCTAssertTrue(screen.contains("TripAIAskSheet(ask: ask, placeChoices: placeChoices, serverNotice: serverNotice,"))
        XCTAssertFalse(screen.contains("serverAllowed"), "古いかもしれない serverAllowed で知らせを消している")
        XCTAssertTrue(screen.contains("askedServer: job.runner.askedServer"), "旅行プランでサーバーへ送ったことを会話に残していない")
        // 旅行プランの一覧のシートと、組み直しの「書いて頼む」
        let plans = try source("Sources/JourneyPhoto/Features/Trips/TripPlansView.swift")
        XCTAssertTrue(plans.contains("AskServerNotice.shows(signedIn: auth.userId != nil, deviceAI: TripAIRunner.usesDeviceAI,"))
        XCTAssertTrue(plans.contains("serverNotice: aiServerNotice,"), "自分で頼むのシートに渡していない")
        XCTAssertTrue(plans.contains("serverNotice: aiServerNotice)"), "「AI で作る」の札に渡していない")
        let detail = try source("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(detail.contains("serverNotice: AskServerNotice.shows(signedIn: auth.userId != nil, deviceAI: aiRunner.onDevice,"))
        let sheet = try source("Sources/JourneyPhoto/Features/Trips/AI/TripAIViews.swift")
        XCTAssertTrue(sheet.contains("if serverNotice { AskServerNoticeText(id: \"tripAI.serverNotice\") }"))
        XCTAssertFalse(sheet.contains("journey.photo のサーバー"), "前の「どこで組むか」の1行が残っている")
        let replan = try source("Sources/JourneyPhoto/Features/Trips/AI/TripReplanViews.swift")
        XCTAssertTrue(replan.contains("if serverNotice { AskServerNoticeText(id: \"tripReplan.serverNotice\") }"))
        XCTAssertTrue(sheet.contains("if serverNotice, !suggestions.isEmpty { AskServerNoticeText(id: \"tripAI.entry.serverNotice\") }"))
        // 表示されない道（AI の画面の外の答え）には置かない
        let thread = try source("Sources/JourneyPhoto/Features/Search/AskThreadView.swift")
        XCTAssertFalse(thread.contains("AskServerNotice"))
    }

    /// 送信の知らせは公式の言い方（プライバシーポリシーの「委託先」）で、中の言葉（使っている AI、サービス、地域）を出さない
    func testServerNoticeIsOfficialAndHidesInternals() throws {
        let text = AskText.serverNotice
        XCTAssertEqual(text, "※ 回答の作成のため、入力内容と直前のやりとりをサーバーに送信し、委託先の AI で処理します。")
        XCTAssertFalse(text.contains("当社"), "ポリシーは「当サイト」。「当社」と書かない")
        XCTAssertFalse(text.contains("・"))
        XCTAssertFalse(text.contains("·"))
        let words = ["AWS", "Bedrock", "Amazon", "Claude", "Anthropic", "Nova", "Haiku", "Sonnet", "Lambda",
                     "東京", "Tokyo", "Japan", "日本", "ap-northeast", "抜き書き", "使い方の頁", "観光スポットの行", "往復"]
        for word in words { XCTAssertFalse(text.localizedCaseInsensitiveContains(word), word) }
        // 英語の文も同じ（L の2つ目）
        let src = try source("Sources/JourneyPhoto/Core/AI/AskAnswer.swift")
        let start = try XCTUnwrap(src.range(of: "static var serverNoticeBody: String {"))
        let end = try XCTUnwrap(src.range(of: "}", range: start.upperBound..<src.endIndex))
        let body = String(src[start.upperBound..<end.lowerBound])
        XCTAssertTrue(body.contains("sent to our servers and processed by an AI provider"))
        for word in words { XCTAssertFalse(body.localizedCaseInsensitiveContains(word), word) }
        // 注意書きにつなげるときは1段落、「※」は1つ
        let joined = AskText.footnote(server: true)
        XCTAssertTrue(joined.hasPrefix(AskText.disclaimer))
        XCTAssertTrue(joined.hasSuffix(AskText.serverNoticeBody))
        XCTAssertEqual(joined.components(separatedBy: "※").count - 1, 1)
        XCTAssertFalse(joined.contains("\n"))
        XCTAssertEqual(AskText.footnote(server: false), AskText.disclaimer)
        // 注意書きと同じ大きさと色で、字の大きさに上限を付ける
        let screen = try source("Sources/JourneyPhoto/Features/Search/AskScreen.swift")
        for anchor in ["Text(AskText.footnote(server: showsServerNotice))", "var text: String = AskText.tripServerNotice"] {
            let at = try XCTUnwrap(screen.range(of: anchor), anchor)
            let tail = String(screen[at.upperBound...].prefix(400))
            XCTAssertTrue(tail.contains("JPFont.caption"), anchor)
            XCTAssertTrue(tail.contains("WebTheme.text3"), anchor)
            XCTAssertTrue(tail.contains(".dynamicTypeSize(...AskScreen.footnoteMaxType)"), anchor)
        }
    }

    /// 知らせ（トースト）は下の欄の測った高さの上に出す（決め打ちの 96 で重なった・2026-11-22 確かめ役の指摘）
    func testToastSitsAboveMeasuredComposer() throws {
        XCTAssertEqual(AskScreen.toastBottomPadding(composer: 140), 140 + AskScreen.toastGap)
        XCTAssertGreaterThan(AskScreen.toastBottomPadding(composer: 140), 140, "知らせが下の欄に重なる")
        let screen = try source("Sources/JourneyPhoto/Features/Search/AskScreen.swift")
        XCTAssertTrue(screen.contains(".onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }"))
    }

    /// 旅行プランで日程を送る場面は、旅行プラン用の文で言い分ける（2026-11-22 確かめ役の指摘）。中の言葉は入れない
    func testTripServerNoticeWording() throws {
        let text = AskText.tripServerNotice
        XCTAssertEqual(text, "※ 旅行プランの作成のため、頼みの内容と日程をサーバーに送信し、委託先の AI で処理します。")
        XCTAssertNotEqual(text, AskText.serverNotice)
        let words = ["AWS", "Bedrock", "Amazon", "Claude", "Anthropic", "Nova", "Haiku", "Sonnet", "Lambda",
                     "東京", "Tokyo", "Japan", "日本", "ap-northeast", "当社", "・", "·"]
        let src = try source("Sources/JourneyPhoto/Core/AI/AskAnswer.swift")
        let start = try XCTUnwrap(src.range(of: "static var tripServerNotice: String {"))
        let end = try XCTUnwrap(src.range(of: "}", range: start.upperBound..<src.endIndex))
        let body = String(src[start.upperBound..<end.lowerBound])
        XCTAssertTrue(body.contains("To create trip plans, your request and itinerary are sent to our servers and processed by an AI provider"))
        for word in words {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(word), word)
            XCTAssertFalse(body.localizedCaseInsensitiveContains(word), word)
        }
        // 旅行プランの画面の部品は、既定で旅行プラン用の文
        let screen = try source("Sources/JourneyPhoto/Features/Search/AskScreen.swift")
        XCTAssertTrue(screen.contains("var text: String = AskText.tripServerNotice"))
    }

    /// 組み直し: チップも「書いて頼む」も送るので、知らせは「書いて頼む」の中ではなくチップの下に1回
    func testReplanNoticeIsOutsideWriteField() throws {
        let replan = try source("Sources/JourneyPhoto/Features/Trips/AI/TripReplanViews.swift")
        XCTAssertTrue(replan.contains("            if writing { writeField }\n"), "知らせを「書いて頼む」の中に入れている")
        XCTAssertEqual(replan.components(separatedBy: "AskServerNoticeText(").count - 1, 1, "知らせが1回でない")
        let chips = try XCTUnwrap(replan.range(of: "ForEach(TripAITweak.allCases)"))
        let notice = try XCTUnwrap(replan.range(of: "AskServerNoticeText(id: \"tripReplan.serverNotice\")"))
        let working = try XCTUnwrap(replan.range(of: "if let working {"))
        XCTAssertTrue(chips.upperBound < notice.lowerBound && notice.upperBound < working.lowerBound, "チップの下に置いていない")
        // 「AI で作る」の札の下に1回（札の ForEach のあと、「自分で頼む」の前）
        let entry = try source("Sources/JourneyPhoto/Features/Trips/AI/TripAIViews.swift")
        let cards = try XCTUnwrap(entry.range(of: ".accessibilityIdentifier(\"tripAI.suggestion\")"))
        let entryNotice = try XCTUnwrap(entry.range(of: "AskServerNoticeText(id: \"tripAI.entry.serverNotice\")"))
        let askButton = try XCTUnwrap(entry.range(of: ".accessibilityIdentifier(\"tripAI.ask\")"))
        XCTAssertTrue(cards.upperBound < entryNotice.lowerBound && entryNotice.upperBound < askButton.lowerBound)
    }

    /// 詳細の画面: 端末の AI が無い iPhone だけ、組み直しの列で回数を先に読む（無料の人に知らせを出さない）
    func testDetailLoadsUsageBeforeNotice() throws {
        let detail = try source("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        let bar = try XCTUnwrap(detail.range(of: "TripReplanBar(working: replanWorking"))
        let task = try XCTUnwrap(detail.range(of: ".task(id: auth.userId) {", range: bar.upperBound..<detail.endIndex))
        let block = String(detail[task.upperBound...].prefix(260))
        XCTAssertTrue(block.contains("guard !aiRunner.onDevice, auth.userId != nil, aiRunner.usage == nil else { return }"), block)
        XCTAssertTrue(block.contains("await aiRunner.loadUsage(service: environment.tripAI)"), block)
        // 組み直しの列に付いている（列の中で、次の部品より前）
        let next = try XCTUnwrap(detail.range(of: "autosaveBanner", range: bar.upperBound..<detail.endIndex))
        XCTAssertTrue(task.lowerBound < next.lowerBound, "回数を先に読む .task が組み直しの列に付いていない")
    }
}
