import XCTest
@testable import JourneyPhoto

/// 探すの「自然な文で探す」（札 #623 の案2・2026-11-15 判断・`SearchSentence`）。
/// 言葉の表で読む側と、端末の AI の答えをそろえる側（`normalized`）を、AI 無しで確かめる
final class SearchSentenceTests: XCTestCase {

    // MARK: - 20件の文（言葉の表）

    /// 文の例 20件を言葉の表で読み、合った数を `measured [search-sentence]` の行に書く。
    /// 表で読めるはずの18件（表に無い言い方の2件を除く）は1件ずつ縛る
    func testTableReadsTheTwentyExamples() {
        var ok = 0
        for c in SearchSentenceFixture.cases {
            let r = SearchSentence.readByTable(c.sentence)
            let good = c.matches(r)
            if good { ok += 1 }
            print("measured [search-sentence] engine=table ok=\(good) sentence=\(c.sentence) text=\(r.text ?? "-")"
                  + " season=\(r.season?.rawValue ?? "-") dayPart=\(r.dayPart?.rawValue ?? "-")"
                  + " unsupported=\(r.unsupported.map(\.rawValue)) unused=\(r.unused)")
            if c.table {
                XCTAssertTrue(good, "表で読めるはずの文を読み違えた: \(c.sentence) → \(r)")
            }
            // 文の例はどれも文として読む（AI に聞く・表で読む）
            XCTAssertTrue(SearchSentence.looksLikeSentence(c.sentence), "文として読まない: \(c.sentence)")
        }
        print("measured [search-sentence] summary engine=table ok=\(ok)/\(SearchSentenceFixture.cases.count)")
        XCTAssertEqual(ok, SearchSentenceFixture.cases.filter(\.table).count)
    }

    // MARK: - 1語の語は今の検索のまま

    func testSingleWordsAreNotReadAsSentences() {
        for word in ["京都", "富士山", "高屋神社", "@ka_trip", "kyoto", "zzzz-no-photo-result", "Recent12345", "寺"] {
            XCTAssertFalse(SearchSentence.looksLikeSentence(word), "1語を文として読んだ: \(word)")
        }
        // 地名だけは読み取りの段を出さない（字の検索と同じ）
        XCTAssertFalse(SearchSentence.readByTable("京都").changesSearch)
        // 季節の言葉1つは読む（「紅葉」→ 秋のチップ）
        XCTAssertTrue(SearchSentence.looksLikeSentence("紅葉"))
        XCTAssertEqual(SearchSentence.readByTable("紅葉").season, .autumn)
    }

    // MARK: - 長い言葉から当てる

    func testLongerWordsWin() {
        // 「夜明け」は夜ではなく朝。「夜桜」は春の夜。「花火」は夏の夜
        XCTAssertEqual(SearchSentence.readByTable("夜明けの湖").dayPart, .morning)
        let sakura = SearchSentence.readByTable("夜桜 京都")
        XCTAssertEqual(sakura.season, .spring)
        XCTAssertEqual(sakura.dayPart, .night)
        XCTAssertEqual(sakura.text, "京都")
        // 全角の空白・英字の幅をそろえる
        XCTAssertEqual(SearchSentence.readByTable("京都　紅葉").text, "京都")
    }

    /// 字の語は1つ（字の検索は1語で当てる）。都道府県を先に、残りは使わなかった語として1行で言う
    func testPicksPrefectureFirstAndReportsUnusedWords() {
        let r = SearchSentence.readByTable("海 静岡 夕日")
        XCTAssertEqual(r.text, "静岡")
        XCTAssertEqual(r.unused, ["海"])
        XCTAssertEqual(r.note, L("「海」は字では探していません。1語ずつ探せます", "\"海\" wasn't searched. Try one word at a time"))
    }

    // MARK: - 欄の無い条件

    func testUnsupportedConditionsAreNotFilteredButSaidInOneLine() {
        let r = SearchSentence.readByTable("雨でも撮れる所")
        XCTAssertEqual(r.unsupported, [.rain])
        XCTAssertNil(r.season)
        XCTAssertNil(r.dayPart)
        XCTAssertNil(r.text)
        XCTAssertTrue(r.changesSearch)
        XCTAssertEqual(r.note, L("雨の日に向くかは観光スポットの情報に無いので、絞らずに探しました",
                                 "Whether it suits rainy days isn't in the spot information, so it wasn't used to narrow the search"))
        // 季節・時間帯の絞り込みは何も変えない
        let current = ShootingTime.Filter(season: .summer, dayPart: nil)
        XCTAssertEqual(SearchSentence.filter(applying: r, to: current), current)
    }

    /// 画面の文の決まり（中黒で区切らない・観光スポットの呼び名・捨てる／撮りどきを使わない）
    func testWordingRules() {
        var lines = SearchSentence.Unsupported.allCases.map {
            SearchSentence.Reading(sentence: "x", unsupported: [$0]).note ?? ""
        }
        lines.append(SearchSentence.Reading(sentence: "x", unsupported: [.rain, .crowd]).note ?? "")
        lines.append(SearchSentence.Reading(sentence: "x", unused: ["海", "滝"]).note ?? "")
        for line in lines {
            for bad in ["・", "·", "撮影スポット", "撮りどき", "捨て", "台帳"] {
                XCTAssertFalse(line.contains(bad), "\(line) に「\(bad)」")
            }
        }
    }

    // MARK: - 端末の AI の答えをそろえる

    /// 選択肢に無い値・文に無い地名は使わない（**新しい条件を作らせない**）
    func testNormalizedDropsValuesOutsideTheChoicesAndTheSentence() {
        let draft = SearchSentence.Draft(season: "梅雨", dayPart: "真夜中", place: "嵐山", keyword: "竹林",
                                         unsupported: ["ペット", "雨"])
        let r = SearchSentence.normalized(draft, sentence: "京都でゆっくり")
        XCTAssertNil(r.season, "選択肢に無い季節を使った")
        XCTAssertNil(r.dayPart, "選択肢に無い時間帯を使った")
        XCTAssertEqual(r.text, "京都", "文に無い地名（嵐山）を字の語にした")
        XCTAssertEqual(r.unsupported, [.rain], "選択肢に無い条件（ペット）を使った")
    }

    /// AI は表に無い言い方を埋める。表で読める言葉と食い違えば表
    func testNormalizedFillsParaphrasesButTheTableWins() {
        let paraphrase = SearchSentence.normalized(
            SearchSentence.Draft(dayPart: "夕方", keyword: "海"), sentence: "日が沈む頃の海")
        XCTAssertEqual(paraphrase.dayPart, .evening)
        XCTAssertEqual(paraphrase.text, "海")

        let conflict = SearchSentence.normalized(
            SearchSentence.Draft(season: "夏", dayPart: "朝", place: "京都"), sentence: "京都 紅葉 夜")
        XCTAssertEqual(conflict.season, .autumn, "「紅葉」を表どおり秋に読まなかった")
        XCTAssertEqual(conflict.dayPart, .night)
        XCTAssertEqual(conflict.text, "京都")
        XCTAssertTrue(conflict.unused.isEmpty, "同じ地名を2回数えた: \(conflict.unused)")

        // AI が季節の言葉を地名として返しても、字の語にしない
        let season = SearchSentence.normalized(SearchSentence.Draft(place: "紅葉"), sentence: "紅葉 滝")
        XCTAssertEqual(season.text, "滝")
        XCTAssertEqual(season.season, .autumn)
    }

    // MARK: - 「こう読みました」の札

    func testChipsShowOnlyWhatIsStillApplied() {
        let r = SearchSentence.readByTable("京都 紅葉 夜")
        let filter = SearchSentence.filter(applying: r, to: ShootingTime.Filter())
        XCTAssertEqual(filter, ShootingTime.Filter(season: .autumn, dayPart: .night))
        XCTAssertEqual(SearchSentence.chips(for: r, query: "京都", filter: filter).map(\.kind), [.text, .season, .dayPart])
        XCTAssertEqual(SearchSentence.chips(for: r, query: "京都", filter: filter).map(\.label),
                       ["京都", ShootingTime.Season.autumn.label, ShootingTime.DayPart.night.label])

        // 季節を外した → 季節の札は出さない。手で「春」に替えても「秋」の札は出さない
        XCTAssertEqual(SearchSentence.chips(for: r, query: "京都", filter: .init(season: nil, dayPart: .night)).map(\.kind),
                       [.text, .dayPart])
        XCTAssertEqual(SearchSentence.chips(for: r, query: "京都", filter: .init(season: .spring, dayPart: .night)).map(\.kind),
                       [.text, .dayPart])
        // 欄を打ち替えた → 読み取りを捨てる
        XCTAssertFalse(SearchSentence.keepsReading(r, afterQueryChange: "大阪"))
        XCTAssertTrue(SearchSentence.keepsReading(r, afterQueryChange: "京都 "))

        // すべて外したら段を出さない
        XCTAssertFalse(SearchSentence.showsReading(r, query: "", filter: .init()))
        XCTAssertTrue(SearchSentence.showsReading(r, query: "京都", filter: .init()))
        // 雨だけの文は札が無くても1行を出す（欄が空のまま）
        let rain = SearchSentence.readByTable("雨でも撮れる所")
        XCTAssertTrue(SearchSentence.showsReading(rain, query: "", filter: .init()))
        XCTAssertFalse(SearchSentence.showsReading(rain, query: "大阪", filter: .init()))
    }

    func testFilterKeepsAxesTheSentenceDidNotMention() {
        let r = SearchSentence.readByTable("京都の夜景")
        XCTAssertEqual(SearchSentence.filter(applying: r, to: .init(season: .autumn, dayPart: .morning)),
                       .init(season: .autumn, dayPart: .night))
    }

    // MARK: - 重ねて0件のとき（2026-11-15 判断）

    /// 写真と観光スポットの見本（撮影地、季節、時間帯）。京都に「秋の夜」は無い
    private struct Item { let place: String; let seasons: Set<ShootingTime.Season>; let parts: Set<ShootingTime.DayPart> }
    private static let items: [Item] = [
        Item(place: "京都", seasons: [.autumn], parts: [.day]),
        Item(place: "京都", seasons: [.spring], parts: [.night]),
        Item(place: "京都", seasons: [], parts: [.night]),
        Item(place: "大阪", seasons: [.autumn], parts: [.night]),
    ]

    private static func count(_ items: [Item]) -> (String, ShootingTime.Filter) -> Int {
        { q, f in
            items.filter { item in
                (q.isEmpty || item.place.contains(q))
                    && (f.season.map { item.seasons.contains($0) } ?? true)
                    && (f.dayPart.map { item.parts.contains($0) } ?? true)
            }.count
        }
    }

    /// 「京都 紅葉 夜」は3つ重ねると0件。1つずつ外して、いちばん多く残る「秋を外す」（京都の夜 2件）を選ぶ。
    /// 戻すと元の3つに戻る
    func testZeroHitDropsTheConditionThatLeavesTheMostAndCanBeRestored() throws {
        let count = Self.count(Self.items)
        var r = SearchSentence.readByTable("京都 紅葉 夜")
        let query = try XCTUnwrap(r.text)
        let filter = SearchSentence.filter(applying: r, to: .init())
        XCTAssertEqual(count(query, filter), 0, "見本が0件になっていない")

        let kind = try XCTUnwrap(SearchSentence.relaxation(for: r, query: query, filter: filter, count: count),
                                 "0件のまま外し方を選ばなかった")
        XCTAssertEqual(kind, .season)
        let relaxed = SearchSentence.removing(kind, query: query, filter: filter)
        XCTAssertGreaterThanOrEqual(count(relaxed.query, relaxed.filter), 1, "外しても0件")
        XCTAssertEqual(relaxed.query, "京都")
        XCTAssertEqual(relaxed.filter, .init(season: nil, dayPart: .night))

        // 外した札は薄く残り（`isDropped`）、1行で言う
        r.relaxTried = true
        r.dropped = kind
        XCTAssertTrue(SearchSentence.keepsReading(r, afterQueryChange: relaxed.query))
        let chips = SearchSentence.chips(for: r, query: relaxed.query, filter: relaxed.filter)
        XCTAssertEqual(chips.map(\.kind), [.text, .season, .dayPart])
        XCTAssertEqual(chips.map(\.isDropped), [false, true, false])
        XCTAssertEqual(SearchSentence.note(for: r, chips: chips),
                       L("京都、秋、夜のすべてに当てはまる所は無いので、京都と夜で探しました",
                         "Nothing matches all of 京都, 秋, 夜, so this shows 京都 and 夜"))

        // 戻すと元の条件（京都、秋、夜）に戻る。もう一度は自動で外さない
        let back = SearchSentence.restoring(kind, reading: r, query: relaxed.query, filter: relaxed.filter)
        XCTAssertEqual(back.query, query)
        XCTAssertEqual(back.filter, filter)
        r.dropped = nil
        XCTAssertEqual(SearchSentence.chips(for: r, query: back.query, filter: back.filter).map(\.isDropped), [false, false, false])
        XCTAssertNil(SearchSentence.relaxation(for: r, query: back.query, filter: back.filter, count: count),
                     "戻したあとにまた外した")
    }

    /// 画面が呼ぶ口（`relax`）で、「京都 紅葉 夜」が1件以上になる外し方を選び、印を立てる。2回目は外さない。
    /// 回 1384 の記録: 印を先に立ててから選んでいて、数（季節 5、時間帯 36、地名 55）があっても外さなかった
    func testRelaxPicksBeforeMarkingTried() throws {
        let count = Self.count(Self.items)
        let r = SearchSentence.readByTable("京都 紅葉 夜")
        let filter = SearchSentence.filter(applying: r, to: .init())
        let (relaxed, kind) = SearchSentence.relax(r, query: "京都", filter: filter, count: count)
        XCTAssertEqual(kind, .season, "0件のまま外さなかった")
        XCTAssertEqual(relaxed.dropped, .season)
        XCTAssertTrue(relaxed.relaxTried)
        let next = SearchSentence.removing(try XCTUnwrap(kind), query: "京都", filter: filter)
        XCTAssertGreaterThanOrEqual(count(next.query, next.filter), 1)
        // 2回目（戻した後など）は外さない
        var back = relaxed
        back.dropped = nil
        XCTAssertNil(SearchSentence.relax(back, query: "京都", filter: filter, count: count).1)
    }

    /// 2つのときは「両方」。時間帯は「夕」ではなく「夕方」と言う
    func testTwoConditionNoteSaysBoth() {
        var r = SearchSentence.readByTable("秋の夕日")
        r.dropped = .season
        let chips = SearchSentence.chips(for: r, query: "", filter: .init(season: nil, dayPart: .evening))
        XCTAssertEqual(SearchSentence.note(for: r, chips: chips),
                       L("秋と夕方の両方に当てはまる所は無いので、夕方で探しました",
                         "Nothing matches both 秋 and 夕方, so this shows 夕方"))
    }

    /// 地名は外す候補の最後: 地名を外すほうが多く残っても、季節か時間帯を外して1件以上なら地名は外さない。
    /// 季節も時間帯も外して0件のときだけ地名を外す
    func testPlaceIsDroppedLast() {
        let r = SearchSentence.readByTable("京都 紅葉 夜")
        let filter = SearchSentence.filter(applying: r, to: .init())
        var many = Self.items
        for _ in 0..<5 { many.append(Item(place: "奈良", seasons: [.autumn], parts: [.night])) }
        XCTAssertEqual(SearchSentence.relaxation(for: r, query: "京都", filter: filter, count: Self.count(many)), .season)

        let onlyOtherPlaces = [Item(place: "大阪", seasons: [.autumn], parts: [.night])]
        XCTAssertEqual(SearchSentence.relaxation(for: r, query: "京都", filter: filter, count: Self.count(onlyOtherPlaces)), .text)
        // どれを外しても0件なら外さない
        XCTAssertNil(SearchSentence.relaxation(for: r, query: "京都", filter: filter, count: { _, _ in 0 }))
    }

    /// 札が1つだけなら外さない（外すと何も絞らない）。外し方を見たあとは外さない
    func testNoRelaxationWithOneConditionOrAfterTrying() {
        let one = SearchSentence.readByTable("紅葉 滝")
        XCTAssertNil(SearchSentence.relaxation(for: SearchSentence.readByTable("紅葉"), query: "",
                                               filter: .init(season: .autumn, dayPart: nil), count: { _, _ in 9 }))
        var tried = one
        tried.relaxTried = true
        XCTAssertNil(SearchSentence.relaxation(for: tried, query: "滝", filter: .init(season: .autumn, dayPart: nil),
                                               count: { _, _ in 9 }))
        XCTAssertEqual(SearchSentence.relaxation(for: one, query: "滝", filter: .init(season: .autumn, dayPart: nil),
                                                 count: { q, _ in q.isEmpty ? 0 : 3 }), .season)
    }

    // MARK: - 画面につないであるか

    private func searchViewSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Search/SearchView.swift"), encoding: .utf8)
    }

    /// 「検索」で文を読む（押す回数 0 回で季節と時間帯に入る）。最近の検索から選んだ文も読む。
    /// 2026-11-20（札 #652）: 送った字は `submit` が分ける。頼みと質問の形は AI の答え（`startAsk`）、
    /// それ以外は今までどおり文を読む（`readSentence`）。語を並べた文は**言葉の表だけ**で読む（回数を数えずに AI を使わない）
    func testSearchViewReadsTheSentenceOnSubmitAndOnRecentPick() throws {
        let source = try searchViewSource()
        let submit = try XCTUnwrap(source.range(of: ".onSubmit {"))
        let after = source[submit.upperBound...].prefix(200)
        XCTAssertTrue(after.contains("submit(query)"), "「検索」で文を読んでいない")
        let pick = try XCTUnwrap(source.range(of: "private func pickRecent(_ word: String) {"))
        XCTAssertTrue(source[pick.upperBound...].prefix(300).contains("submit(word)"), "最近の検索から選んだ文を読んでいない")
        let route = try XCTUnwrap(source.range(of: "private func submit(_ raw: String) {"))
        let body = source[route.upperBound...].prefix(300)
        XCTAssertTrue(body.contains("AskQuery.form(raw, scope: model.scope) == .ask"))
        XCTAssertTrue(body.contains("startAsk(raw)"))
        XCTAssertTrue(body.contains("readSentence(raw)"))
        // 0件と決まったら1つ外す。外した札は押すと戻る
        XCTAssertTrue(source.contains(".onChange(of: needsRelaxing)"), "0件のときに外し方を見ていない")
        XCTAssertTrue(source.contains("restoreReading(chip)"), "外した札を押しても戻らない")
        // 読むのは端末の中だけ、言葉の表だけ（端末の AI で読むと回数を数えずに AI を使う）
        XCTAssertTrue(source.contains("let result = SearchSentence.readByTable(sentence)"))
        XCTAssertFalse(source.contains("SearchSentenceReader.live("), "語の文を端末の AI で読んでいる（回数を数えていない）")
    }

    /// 端末の AI は投稿の候補（#622）と同じ判定を通す（写しを作らない）
    func testReaderUsesTheSharedOnDeviceAICheck() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let reader = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Services/SearchSentenceReader.swift"), encoding: .utf8)
        XCTAssertTrue(reader.contains("OnDeviceAI.isAvailable"))
        XCTAssertFalse(reader.contains("SystemLanguageModel.default.availability"), "使えるかの判定を写している")
        // 外へ送る口を持たない
        for bad in ["URLSession", "http", "environment."] {
            XCTAssertFalse(reader.contains(bad), "読み取りの部品に「\(bad)」")
        }
    }
}
