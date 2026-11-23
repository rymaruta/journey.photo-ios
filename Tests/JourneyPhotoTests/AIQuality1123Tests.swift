import XCTest
@testable import JourneyPhoto

/// 2026-11-23 owner の画面写真で見つかった AI まわりの不具合（AI に頼む・旅行プラン）。
/// 「11月下旬のおすすめの観光スポット5選教えて」で見出しは5つなのに札が8枚、本土寺の説明が「…アジサイ…」だった
final class AIQuality1123Tests: XCTestCase {

    static let question = "11月下旬のおすすめの観光スポット5選教えて"

    /// 季節の案内の文まで持つ行（詳細を重ねた行）
    static func spot(_ slug: String, name: String, prefecture: String = "千葉県", city: String = "松戸市",
                     lat: Double = 35.8, lng: Double = 139.9, seasons: [(String, String)] = [],
                     times: [(String, String)] = [], summary: String? = nil) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"sp_\(slug)\"", "\"slug\":\"\(slug)\"", "\"name\":\"\(name)\"", "\"stage\":\"published\"",
                      "\"category\":\"寺社\"", "\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}",
                      "\"region\":{\"prefecture\":\"\(prefecture)\",\"city\":\"\(city)\"}"]
        if !seasons.isEmpty {
            fields.append("\"seasonalGuide\":[" + seasons.map { "{\"season\":\"\($0.0)\",\"text\":\"\($0.1)\"}" }.joined(separator: ",") + "]")
        }
        if !times.isEmpty {
            fields.append("\"timeOfDayGuide\":[" + times.map { "{\"time\":\"\($0.0)\",\"text\":\"\($0.1)\"}" }.joined(separator: ",") + "]")
        }
        if let summary { fields.append("\"summary\":\"\(summary)\"") }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 秋の案内がある所が10か所（頼んだ5より多い）。本土寺は概要がアジサイ、秋の案内が紅葉
    static func autumnLedger() throws -> [OfficialSpot] {
        var rows = [try spot("hondoji", name: "本土寺",
                             seasons: [("summer", "6月は約5万株のアジサイが咲きます。"), ("autumn", "11月下旬は紅葉が見頃です。参道が赤く染まります。")],
                             summary: "秋の時期に10000株のアジサイが知られる寺です。")]
        for i in 1...9 {
            rows.append(try spot("aki\(i)", name: "秋の所\(i)", seasons: [("autumn", "紅葉の名所です。")]))
        }
        rows.append(try spot("haru", name: "春の所", seasons: [("spring", "桜の名所です。")]))
        return rows
    }

    // MARK: - 1. 頼みの数

    func testReadsRequestedCount() {
        let cases: [(String, Int?)] = [
            (Self.question, 5), ("京都の紅葉3つ教えて", 3), ("金沢で4か所おすすめ", 4), ("沖縄 6件", 6),
            ("箱根のおすすめ２ヶ所", 2), ("三つ選んで", 3), ("日本の滝100選", 100), ("京都の紅葉", nil),
            ("1日目のおすすめ", nil), ("2泊3日で金沢", nil),
        ]
        for (text, want) in cases {
            XCTAssertEqual(SearchSentence.readByTable(text).count, want, text)
        }
    }

    func testCountLimitsCardsAndIsCappedAtEight() throws {
        let lib = AskLibrary(spots: try Self.autumnLedger(), photos: [])
        let reading = SearchSentence.readByTable(Self.question)
        let q = AskLibrary.query(reading: reading, intent: AskQuery.intent(Self.question, reading: reading),
                                 sentence: Self.question, spots: lib.spots)
        XCTAssertEqual(q.count, 5)
        XCTAssertEqual(lib.pickSpots(q).count, 5, "見出しの5と札の数をそろえる")
        let many = SearchSentence.readByTable("秋の観光スポット20選")
        let q2 = AskLibrary.query(reading: many, intent: AskQuery.intent("秋の観光スポット20選", reading: many),
                                  sentence: "秋の観光スポット20選", spots: lib.spots)
        XCTAssertEqual(q2.limit, AskLibrary.maxSpots, "上限は8のまま")
        XCTAssertEqual(lib.pickSpots(q2).count, AskLibrary.maxSpots)
    }

    /// 端末の AI の道具が何度引いても、札は頼んだ数まで
    func testDeviceCollectorAndToolQueryUseRequestedCount() throws {
        let rows = try Self.autumnLedger()
        let collector = AskCollector(limit: 5)
        collector.add(picks: rows.map { AskLibrary.Pick(spot: $0) }, source: .init(kind: .spots, label: AskText.spotsSource))
        XCTAssertEqual(collector.snapshot().picks.count, 5)
        let asked = AskLibrary.requested(Self.question)
        XCTAssertEqual(asked.count, 5)
        XCTAssertEqual(asked.month, 11)
        let box = AskLibraryBox(AskLibrary(spots: rows, photos: []), count: asked.count, month: asked.month)
        // AI が季節を「春」と読み違えても、文の「11月」の季節（秋）で引く
        let q = box.query(place: nil, season: .spring, dayPart: nil, keyword: nil, near: false)
        XCTAssertEqual(q.season, .autumn)
        let picks = box.library.pickSpots(q)
        XCTAssertEqual(picks.count, 5)
        XCTAssertFalse(picks.contains { $0.spot.spotId == "sp_haru" })
    }

    /// 端末の AI が8か所引いて答えても、札は頼んだ5か所（AskEngine の aiAnswer）
    @MainActor
    func testEngineShowsRequestedCountFromDevicePicks() async throws {
        let rows = try Self.autumnLedger()
        let eight = rows.prefix(8).map { AskLibrary.Pick(spot: $0) }
        let d = UserDefaults(suiteName: "AIQuality1123Tests.\(UUID().uuidString)")!
        let engine = AskEngine(history: AskHistoryStore(defaults: d))
        let usage = AskUsage(tier: "free", kind: "ask", day: .init(used: 1, limit: 3, remaining: 2),
                             month: .init(used: 1, limit: 10, remaining: 9, resetsOn: "2026-12-01"), serverAllowed: false)
        let backend = AskEngine.Backend(
            signedIn: { true }, offline: { false }, deviceAI: { true },
            library: { _ in AskLibrary(spots: rows, photos: []) },
            reserve: { _, _ in usage },
            serverAsk: { _, _, _ in .init(answer: "", general: false) },
            deviceAsk: { _, _, _ in
                AskDevice.Result(text: "11月下旬に向く5か所です。", general: false, picks: Array(eight), photoIds: [],
                                 sources: [.init(kind: .spots, label: AskText.spotsSource)], kind: "cards")
            },
            details: { $0 }, userId: { "u1" })
        await engine.start(Self.question, backend: backend)
        let a = try XCTUnwrap(engine.thread.first?.answer)
        XCTAssertEqual(a.spotIds.count, 5)
        XCTAssertTrue(a.chips.contains("秋"), "月から季節を読んで札に出す")
    }

    /// 数として読みすぎない（2026-11-23 確かめ役の指摘）
    func testDoesNotReadNonCountNumbers() {
        let cases: [(String, Int?)] = [
            ("3年坂", nil), ("三つ星", nil), ("三つ星のレストラン", nil), ("5つ星ホテル", nil), ("もう一つ教えて", nil),
            ("もう1つ", nil), ("四つ葉", nil), ("2つ目の滝", nil),
            // 数のまま
            ("京都の紅葉3つ教えて", 3), ("三つ選んで", 3), ("3つの滝", 3), ("おすすめを3つ", 3), ("5選", 5),
        ]
        for (text, want) in cases {
            XCTAssertEqual(SearchSentence.readByTable(text).count, want, text)
        }
        XCTAssertEqual(SearchSentence.readByTable("3年坂").text, "3年坂", "数の字を使い切らずに語に残す")
    }

    /// 写真の検索では、月を季節の札にしつつ字の語にも残す（題に「11月」と書いた写真に当たる）。AI に頼むは今の形
    func testPhotoSearchKeepsMonthAsText() {
        let photo = SearchSentence.readByTable("11月下旬の紅葉", monthAsText: true)
        XCTAssertEqual(photo.season, .autumn)
        XCTAssertEqual(photo.month, 11)
        XCTAssertEqual(photo.text, "11月")
        XCTAssertEqual(SearchSentence.readByTable("十一月の京都", monthAsText: true).text, "京都", "都道府県を先に")
        XCTAssertEqual(SearchSentence.readByTable("十一月の京都", monthAsText: true).unused, ["十一月"])
        XCTAssertNil(SearchSentence.readByTable("11月下旬の紅葉").text, "AI に頼むでは月は語にしない")
        // 探すの画面は写真の検索の形で読む
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Search/SearchView.swift")
        let src = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        XCTAssertTrue(src.contains("SearchSentence.readByTable(sentence, monthAsText: true)"))
    }

    // MARK: - 2. 月と旬を季節として読む

    func testMonthBecomesSeasonAndIsNotAKeyword() {
        let r = SearchSentence.readByTable(Self.question)
        XCTAssertEqual(r.month, 11)
        XCTAssertEqual(r.season, .autumn)
        XCTAssertNil(r.text, "「11月下旬」「観光スポット5選」を字の語にしない（当たらずに語を捨てて台帳の先頭から出していた）")
        XCTAssertTrue(r.unused.isEmpty, "\(r.unused)")
        let cases: [(String, Int?, ShootingTime.Season?)] = [
            ("2月末の雪景色", 2, .winter), ("４月上旬の京都", 4, .spring), ("十一月の金沢", 11, .autumn),
            ("7月中旬", 7, .summer), ("12月初旬", 12, .winter), ("8月", 8, .summer), ("111月", nil, nil),
            ("13月", nil, nil), ("1ヶ月後", nil, nil), ("満月の夜", nil, nil),
        ]
        for (text, month, season) in cases {
            let rr = SearchSentence.readByTable(text)
            XCTAssertEqual(rr.month, month, text)
            if month != nil { XCTAssertEqual(rr.season, season, text) }
        }
        // 先に書いた方（月が先なら月の季節）
        XCTAssertEqual(SearchSentence.readByTable("11月の桜").season, .autumn)
        XCTAssertEqual(SearchSentence.readByTable("紅葉の京都").month, nil)
    }

    func testMonthFiltersBySeasonAndPutsMonthMentionFirst() throws {
        let rows = try Self.autumnLedger()
        // 本土寺を後ろに置いても、案内の文に「11月」がある所を先に並べる
        let lib = AskLibrary(spots: Array(rows.dropFirst()) + [rows[0]], photos: [])
        let reading = SearchSentence.readByTable(Self.question)
        let q = AskLibrary.query(reading: reading, intent: AskQuery.intent(Self.question, reading: reading),
                                 sentence: Self.question, spots: lib.spots)
        let picks = lib.pickSpots(q)
        XCTAssertEqual(picks.first?.spot.spotId, "sp_hondoji")
        XCTAssertNil(q.keyword, "月は語にしない")
        // 月だけで並べる（語で当てた結果ではない）
        let byMonth = lib.pickSpots(AskLibrary.Query(season: .autumn, month: 11))
        XCTAssertEqual(byMonth.first?.spot.spotId, "sp_hondoji")
        XCTAssertEqual(byMonth.count, AskLibrary.maxSpots)
        XCTAssertFalse(picks.contains { $0.spot.spotId == "sp_haru" }, "秋に絞る")
        XCTAssertTrue(AskLibrary.mentions(rows[0], month: 11, season: .autumn))
        XCTAssertFalse(AskLibrary.mentions(rows[0], month: 1, season: nil), "「11月」は1月ではない")
        XCTAssertFalse(AskLibrary.mentions(rows[1], month: 11, season: .autumn))
    }

    // MARK: - 3. その回の季節の案内を渡す

    func testGuideUsesTheSeasonOfTheTurn() throws {
        let hondoji = try Self.autumnLedger()[0]
        XCTAssertEqual(AskLibrary.guide(for: hondoji, season: .autumn), "11月下旬は紅葉が見頃です。参道が赤く染まります。")
        XCTAssertEqual(AskLibrary.season(fromChips: ["千葉", "秋"]), .autumn)
        XCTAssertNil(AskLibrary.season(fromChips: ["千葉"]))
        // サーバーの AI に渡す行も、文の月の季節の案内
        let sources = AskService.sources(text: Self.question, spots: [hondoji])
        let notes = sources.compactMap { src -> String?? in
            if case .spot(_, _, _, _, _, let note) = src { return note }
            return nil
        }
        guard let note = notes.first else { return XCTFail("観光スポットの行が無い") }
        XCTAssertEqual(note, "11月下旬は紅葉が見頃です。参道が赤く染まります。")
        XCTAssertFalse(note?.contains("アジサイ") ?? true)
    }

    // MARK: - 4. 旅行プランに `sp_…` を出さない

    func testTripLabelNeverShowsSpotId() throws {
        let item = TripItem.spot(spotId: "sp_hondoji", note: nil)
        XCTAssertEqual(TripPlanText.label(for: item, index: [], places: []), TripPlanText.unresolvedSpot)
        XCTAssertFalse(TripPlanText.label(for: item, index: [], places: []).contains("sp_"))
        // 読み込み中は骨組み、読み終えたら言葉
        XCTAssertTrue(TripPlanText.isPending(item, index: [], loading: true))
        XCTAssertFalse(TripPlanText.isPending(item, index: [], loading: false))
        // AI で作った直後: 候補で名前を引く
        let cands = try Self.autumnLedger()
        let names = TripPlanText.nameIndex(loaded: [], candidates: cands)
        XCTAssertEqual(TripPlanText.label(for: item, index: names, places: []), "本土寺")
        XCTAssertFalse(TripPlanText.isPending(item, index: names, loading: true))
        // 画面に出す名前: 読み込み中は「読み込み中」（「読み込めませんでした」と言わない）、読み終えたら言葉
        XCTAssertEqual(TripPlanText.displayName(for: item, index: [], places: [], loading: true), TripPlanText.loadingSpot)
        XCTAssertEqual(TripPlanText.displayName(for: item, index: [], places: [], loading: false), TripPlanText.unresolvedSpot)
        XCTAssertEqual(TripPlanText.displayName(for: item, index: names, places: [], loading: true), "本土寺")
        // 組み直しの案も同じ
        XCTAssertEqual(TripDraft.place(for: item, index: [], places: [], loading: true).name, TripPlanText.loadingSpot)
        // 読み込んだ索引があればそちら
        XCTAssertEqual(TripPlanText.nameIndex(loaded: [cands[1]], candidates: cands).map(\.spotId), ["sp_aki1"])
        // 地図と下書きも同じ
        let stops = TripDayMap.stops(of: TripDay(items: [item]), index: [], places: [])
        XCTAssertEqual(stops.first?.name, TripPlanText.unresolvedSpot)
        XCTAssertEqual(TripDraft.place(for: item, index: [], places: []).name, TripPlanText.unresolvedSpot)
    }

    /// 写真の一覧と索引を同時に聞き、AI の流れでは候補を最初の索引にする（画面のコードの形で確かめる）
    func testDetailViewLoadsTogetherAndSeedsCandidates() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(src.contains("async let photosCall"))
        XCTAssertTrue(src.contains("async let indexCall"))
        XCTAssertTrue(src.contains("TripPlanText.nameIndex(loaded: loadedIndex, candidates: aiNotes.note(planId)?.candidates ?? [])"))
        XCTAssertTrue(src.contains("TripStopSkeleton(number: number)"))
    }

    /// 骨組みの間は「…」と ≡ を出さず、行・会話・組み直しの案は読み込み中の名前で引く（画面のコードの形で確かめる）
    func testPendingRowHidesMenuAndUsesLoadingName() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(src.contains("""
                    TripStopSkeleton(number: number)
                } else {
                    itemLink(item, name: name, number: number, season: season, chips: chips, time: time, thumb: thumb)
                    TripStopPhotoSlot(invites: invites, name: name) { invitePost(item) }
                    itemMenu(di, ii, item, name: name)
                    dragHandle(di, ii, item, name: name)
                }
            }
            if !pending {
                TripStopPhotoLine(photo: mine, invites: invites)
"""), "骨組みの間は「…」と ≡ を出さない（行の写真の欄・点線の＋・写真の一行も出さない・札 #710 と合わせた形）")
        // 骨組みの枠は行の写真（`TripStopThumbView`）と同じ寸法
        XCTAssertEqual(TripStopSkeleton.photoSide, TripStopThumbView.side)
        XCTAssertTrue(src.contains("let name = TripPlanText.displayName(for: item, index: index, places: places, loading: !indexTried)"))
        XCTAssertTrue(src.contains("resolveName: { TripPlanText.displayName(for: $0, index: index, places: places, loading: !indexTried) }"))
        XCTAssertTrue(src.contains("resolve: { TripDraft.place(for: $0, index: index, places: places, loading: !indexTried) }"))
        // 骨組みに写真の欄と同じ枠（44pt・角10）
        XCTAssertEqual(TripStopSkeleton.photoSide, 44)
        XCTAssertEqual(TripStopSkeleton.photoCorner, 10)
        XCTAssertTrue(src.contains(".frame(width: Self.photoSide, height: Self.photoSide)"))
    }

    // MARK: - 5. 題と理由の見張り

    static let leakyReasons = [
        "3と7は近いので同じ日にしました。", "候補5を朝に回しました。", "候補の2は夕方が向きます。", "2、5、8を1日目にまとめました。",
        "番号の若い順に並べました。", "4番は朝が向きます。", "(3) と (6) は近い所です。", "No.2 から回ります。",
        "#4 は夜景です。", "１と４を並べました。", "1\u{30FB}4を先に回ります。",
        "DynamoDB の行から選びました。", "arn:aws:lambda:ap-northeast-1:123 で組みました。", "api-user の候補から選びました。",
    ]
    static let fineReasons = [
        "東山を朝に、嵐山を夕方に回します。", "1日目と2日目で地域を分けました。", "9時と15時に着くように並べました。",
        "2泊3日でゆっくり回れる所です。", "紅葉の名所を3か所選びました。",
    ]

    func testFirstBuildScreensTitleAndReason() {
        for r in Self.leakyReasons {
            let plan = TripAIPlan(title: "京都の秋", days: 1, stops: [.init(n: 1, day: 1)], reason: r)
            XCTAssertEqual(plan.screenedTitleAndReason().reason, "", r)
            XCTAssertEqual(plan.screenedTitleAndReason().title, "京都の秋", r)
        }
        for r in Self.fineReasons {
            let plan = TripAIPlan(title: "京都の秋", days: 1, stops: [.init(n: 1, day: 1)], reason: r)
            XCTAssertEqual(plan.screenedTitleAndReason().reason, r, r)
        }
        let leakyTitle = TripAIPlan(title: "cognito の旅", days: 1, stops: [.init(n: 1, day: 1)], reason: "東山を朝に回します。")
        XCTAssertEqual(leakyTitle.screenedTitleAndReason().title, "")
        XCTAssertEqual(leakyTitle.screenedTitleAndReason().reason, "東山を朝に回します。")
    }

    /// 最初に作る回（サーバーの道＝差し替えの planner）で、候補の番号の理由は出ない
    @MainActor
    func testRunnerDropsNumberReasonOnFirstBuild() async throws {
        let rows = try Self.kyotoLedger()
        let runner = TripAIRunner(onDevice: false, planner: { _, cands, _, _ in
            TripAIPlan(title: "京都の秋", days: 1, stops: cands.indices.map { .init(n: $0 + 1, day: 1) }, reason: "3と7は近いので同じ日にしました。")
        })
        let ask = TripAIAsk.reading("京都で日帰り", spots: rows)
        let built = await runner.build(ask, index: rows, wishlist: [], offline: false,
                                       service: TripAIService(api: APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken()))) { _, _ in 10 }
        let result = try XCTUnwrap(built)
        XCTAssertEqual(result.mode, .ai)
        XCTAssertEqual(result.reason, "")
        XCTAssertFalse(result.refused)
    }

    // MARK: - 6. 日の中の並びをアプリが決める

    static func kyotoLedger() throws -> [OfficialSpot] {
        [
            try spot("kiyomizu", name: "清水寺", prefecture: "京都府", city: "京都市", lat: 34.995, lng: 135.785),
            try spot("arashiyama", name: "嵐山", prefecture: "京都府", city: "京都市", lat: 35.009, lng: 135.667),
            try spot("yasaka", name: "八坂の塔", prefecture: "京都府", city: "京都市", lat: 34.998, lng: 135.779),
            try spot("tenryuji", name: "天龍寺", prefecture: "京都府", city: "京都市", lat: 35.016, lng: 135.674),
        ]
    }

    func testOrderedDayAvoidsGoingBackAndForth() throws {
        let rows = try Self.kyotoLedger()
        // AI の並び: 東山 → 嵐山 → 東山 → 嵐山
        let ordered = TripAIDayOrder.ordered([rows])
        XCTAssertEqual(ordered.count, 1)
        XCTAssertEqual(Set(ordered[0].map(\.spotId)), Set(rows.map(\.spotId)), "場所は変えない")
        let area: (OfficialSpot) -> String = { $0.coords?.lng ?? 0 < 135.7 ? "west" : "east" }
        let areas = ordered[0].map(area)
        var switches = 0
        for i in 1..<areas.count where areas[i] != areas[i - 1] { switches += 1 }
        XCTAssertEqual(switches, 1, "東山と嵐山を行ったり来たりしない: \(ordered[0].map(\.name))")
    }

    @MainActor
    func testRunnerOrdersFirstBuildButKeepsReplanOrder() async throws {
        let rows = try Self.kyotoLedger()
        // AI の並び: 東山 → 嵐山 → 東山 → 嵐山（渡された候補の番号で組む）
        let runner = TripAIRunner(onDevice: false, planner: { _, cands, _, _ in
            let east = cands.indices.filter { (cands[$0].coords?.lng ?? 0) >= 135.7 }
            let west = cands.indices.filter { (cands[$0].coords?.lng ?? 0) < 135.7 }
            var order: [Int] = []
            for i in 0..<max(east.count, west.count) {
                if i < east.count { order.append(east[i]) }
                if i < west.count { order.append(west[i]) }
            }
            return TripAIPlan(title: "京都", days: 1, stops: order.map { .init(n: $0 + 1, day: 1) }, reason: "")
        })
        let ask = TripAIAsk.reading("京都で日帰り", spots: rows)
        let built = await runner.build(ask, index: rows, wishlist: [], offline: false,
                                       service: TripAIService(api: APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken()))) { _, _ in 10 }
        let names = try XCTUnwrap(built).days.flatMap { $0 }.map(\.name)
        let west: Set<String> = ["嵐山", "天龍寺"]
        var switches = 0
        for i in 1..<names.count where west.contains(names[i]) != west.contains(names[i - 1]) { switches += 1 }
        XCTAssertEqual(switches, 1, "\(names)")

        // 組み直し（今の日程がある）は、AI の並び（＝利用者の並び）のまま。東山 → 嵐山 → 東山 → 嵐山 を並べ直さない
        let eastRows = rows.filter { ($0.coords?.lng ?? 0) >= 135.7 }
        let westRows = rows.filter { ($0.coords?.lng ?? 0) < 135.7 }
        let current = [[eastRows[0], westRows[0], eastRows[1], westRows[1]]]
        let revised = await runner.revise(request: "ゆっくり", current: current, candidates: rows, index: rows, offline: false,
                                          service: TripAIService(api: APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())),
                                          title: "京都") { _, _ in 10 }
        XCTAssertEqual(try XCTUnwrap(revised).days.flatMap { $0 }.map(\.spotId), current[0].map(\.spotId),
                       "組み直しは利用者の並びを壊さない")
    }

    /// 日をまたいでは動かさない（各日の中身の集合は変わらない）
    func testOrderedKeepsEachDaysSpots() throws {
        let rows = try Self.kyotoLedger()
        let days = [[rows[0], rows[1], rows[2]], [rows[3], try Self.spot("nanzenji", name: "南禅寺", prefecture: "京都府", city: "京都市",
                                                                          lat: 35.011, lng: 135.794)]]
        let ordered = TripAIDayOrder.ordered(days)
        XCTAssertEqual(ordered.count, 2)
        for (d, day) in days.enumerated() {
            XCTAssertEqual(Set(ordered[d].map(\.spotId)), Set(day.map(\.spotId)), "\(d + 1)日目")
            XCTAssertEqual(ordered[d].count, day.count)
        }
    }

    // MARK: - 7. 時間帯の札を分ける

    func testTimeChipsAreSeparateAndHighlightArrival() {
        let none = TripDraft.timeChips(["morning", "goldenHour"])
        XCTAssertEqual(none.map(\.text), ["朝", "夕方の斜光"])
        XCTAssertEqual(none.map(\.emphasis), [.plain, .plain])
        // 17時に着く: 夕方の斜光だけ明るい
        let evening = TripDraft.timeChips(["morning", "goldenHour"], arrive: 17 * 60)
        XCTAssertEqual(evening.map(\.emphasis), [.other, .match])
        XCTAssertEqual(evening.last?.spoken, "夕方の斜光、着く時間帯")
        // 8時に着く: 朝だけ明るい
        XCTAssertEqual(TripDraft.timeChips(["morning", "goldenHour"], arrive: 8 * 60).map(\.emphasis), [.match, .other])
        // 3つあっても2枚まで。着く時間帯の札は必ず入れる
        let three = TripDraft.timeChips(["dawn", "morning", "night"], arrive: 20 * 60)
        XCTAssertEqual(three.map(\.text), ["夜明け", "夜"])
        XCTAssertTrue(TripDraft.timeChips([]).isEmpty)
    }

    // MARK: - 8. 季節の一文は最初の1文

    func testSeasonLineIsFirstSentenceOnly() throws {
        let hondoji = try Self.autumnLedger()[0]
        XCTAssertEqual(TripDraft.seasonLine(hondoji, ymd: "2026-11-25"), "秋（11月）\u{2002}11月下旬は紅葉が見頃です。")
        XCTAssertEqual(TripDraft.firstSentence("区切りの無い文"), "区切りの無い文")
        // 括弧の中の「。」では切らない
        XCTAssertEqual(TripDraft.firstSentence("「もみじ。」と呼ばれる道です。秋は混みます。"), "「もみじ。」と呼ばれる道です。")
        XCTAssertEqual(TripDraft.firstSentence("紅葉（11月。見頃）が続きます。次。"), "紅葉（11月。見頃）が続きます。")
    }
}

/// 通信しない口（差し替えの planner で組むので、サーバーへは送らない）
private struct NoToken: TokenProviding {
    func idToken() async throws -> String? { nil }
    func accountGone(idToken: String) async {}
}
