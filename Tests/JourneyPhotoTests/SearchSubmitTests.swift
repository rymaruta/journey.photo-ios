import XCTest
@testable import JourneyPhoto

/// 送信を押すまで結果も AI の答えも出さない（札 #662・2026-11-20 判断）。
/// owner「AIに聞く機能は、送信ボタン押すまで結果でてきて欲しくない」「文字打つだけでAI使われると結構すぐ上限きてしんどい」
final class SearchSubmitTests: XCTestCase {

    /// 探すの画面（`SearchView.apply`）と同じ当て方の模型。送った字と、AI に頼んだ回数を数える
    final class Screen {
        var query = ""
        var searched = ""
        var scope: SearchScope = .all
        var asks: [String] = []
        var reads: [String] = []

        func type(_ text: String) {
            query = text
            apply(SearchSubmit.plan(.typed, text: text, scope: scope, searched: searched))
        }
        func keyboard() { apply(SearchSubmit.plan(.keyboard, text: query, scope: scope, searched: searched)) }
        func sendButton() { apply(SearchSubmit.plan(.sendButton, text: query, scope: scope, searched: searched)) }
        func clear() {
            query = ""
            apply(SearchSubmit.plan(.cleared, text: "", scope: scope, searched: searched))
        }
        func recent(_ word: String, cached: Bool) {
            query = word
            apply(SearchSubmit.plan(.recent(cachedToday: cached), text: word, scope: scope, searched: searched))
        }
        private func apply(_ plan: SearchSubmit.Plan) {
            guard let next = plan.searched else { return }
            searched = next
            if plan.asks { asks.append(next) }
            if plan.readsSentence { reads.append(next) }
        }
    }

    /// 1字ずつ打つ（日本語の変換の途中の字も通る）
    private func typeByChar(_ text: String, on s: Screen) {
        var t = ""
        for ch in text {
            t.append(ch)
            s.type(t)
        }
    }

    // MARK: - 打っても結果の語が変わらない

    func testTypingDoesNotChangeSearchedWordOrAsk() {
        let s = Screen()
        typeByChar("おすすめの観光スポット教えて", on: s)
        XCTAssertEqual(s.searched, "", "打っている間に結果の語が変わった")
        XCTAssertTrue(s.asks.isEmpty, "打っている間に AI を呼んだ: \(s.asks)")
        XCTAssertTrue(s.reads.isEmpty)
        // 前に送った結果があれば、打ち替えてもそのまま
        s.sendButton()
        XCTAssertEqual(s.searched, "おすすめの観光スポット教えて")
        typeByChar("京都 紅葉", on: s)
        XCTAssertEqual(s.searched, "おすすめの観光スポット教えて", "打ち替えたら前の結果（答え）が消えた")
        XCTAssertEqual(s.asks.count, 1, "打ち替えている間に AI を呼んだ")
    }

    /// 欄を空にしたときだけ最初の画面に戻す
    func testClearingReturnsToFirstScreen() {
        let s = Screen()
        s.type("京都")
        s.keyboard()
        XCTAssertEqual(s.searched, "京都")
        s.clear()
        XCTAssertEqual(s.searched, "")
        let plan = SearchSubmit.plan(.typed, text: "", scope: .all, searched: "京都")
        XCTAssertEqual(plan.searched, "", "字を消し切っても前の結果が残る")
        XCTAssertTrue(plan.closesAnswer)
        XCTAssertTrue(SearchSubmit.plan(.cleared, text: "", scope: .all, searched: "京都").closesAnswer)
    }

    // MARK: - キーボードの「検索」では AI を呼ばない

    func testKeyboardSearchNeverAsksAI() {
        for text in ["おすすめの観光スポット教えて", "近くで夕日がきれいな所は？", "京都 紅葉 夜", "金沢に1泊2日の旅行プランを作って"] {
            let s = Screen()
            s.type(text)
            s.keyboard()
            XCTAssertEqual(s.searched, text, "キーボードの検索で結果が変わらない: \(text)")
            XCTAssertTrue(s.asks.isEmpty, "キーボードの検索で AI を呼んだ: \(text)")
            XCTAssertEqual(s.reads, [text], "キーボードの検索で言葉の表で読まない: \(text)")
            XCTAssertTrue(SearchSubmit.plan(.keyboard, text: text, scope: .all, searched: "").closesAnswer)
        }
    }

    // MARK: - 送信のボタンだけで AI を呼ぶ

    func testOnlySendButtonAsksAI() {
        let s = Screen()
        s.type("近くで夕日がきれいな所は？")
        XCTAssertTrue(s.asks.isEmpty)
        s.sendButton()
        XCTAssertEqual(s.asks, ["近くで夕日がきれいな所は？"], "送信のボタンで AI を呼ばない")
        XCTAssertEqual(s.searched, "近くで夕日がきれいな所は？", "送信で結果の語が変わらない")
        // 見本の字はどれもボタンで送れる
        for month in 1...12 {
            for example in AskQuery.examples(month: month) {
                XCTAssertTrue(SearchSubmit.sendEnabled(text: example, scope: .all), "見本が送れない: \(example)")
                XCTAssertTrue(SearchSubmit.showsSendButton(text: example, scope: .all))
            }
        }
    }

    /// 頼みの形でない字には送信のボタンを出さない（言葉の検索はキーボードの「検索」）
    func testSendButtonOnlyForAskForm() {
        XCTAssertFalse(SearchSubmit.showsSendButton(text: "京都", scope: .all))
        XCTAssertFalse(SearchSubmit.showsSendButton(text: "京都 紅葉 夜", scope: .all))
        XCTAssertFalse(SearchSubmit.showsSendButton(text: "", scope: .all))
        XCTAssertFalse(SearchSubmit.showsSendButton(text: "おすすめの観光スポット教えて", scope: .people))
        let s = Screen()
        s.type("京都 紅葉 夜")
        s.sendButton()
        XCTAssertEqual(s.searched, "", "頼みの形でない字をボタンで送った")
        XCTAssertTrue(s.asks.isEmpty)
        XCTAssertEqual(SearchSubmit.sendLabel, "AI に送る")
    }

    // MARK: - 途中の字では呼ばない

    func testUnfinishedTextIsNotSent() {
        // 1.1.107 の実機: 「おすすめの」が「おすすめ」を印に頼みと読まれ、途中の字で1回使っていた
        for text in ["おすすめの", "京都で", "近くで", "おすすめは", "京都の紅葉を", "金沢に"] {
            XCTAssertTrue(AskQuery.isUnfinished(text), "途中の字と読まない: \(text)")
            XCTAssertFalse(AskQuery.sendsToAI(text), "途中の字を AI に送る: \(text)")
            XCTAssertFalse(SearchSubmit.sendEnabled(text: text, scope: .all))
            let s = Screen()
            s.type(text)
            s.sendButton()
            XCTAssertTrue(s.asks.isEmpty, "途中の字でボタンを押したら AI を呼んだ: \(text)")
            XCTAssertEqual(s.searched, "", "途中の字でボタンを押したら結果が変わった: \(text)")
        }
        XCTAssertTrue(SearchSubmit.showsKeepTyping(text: "おすすめの", scope: .all), "「続けて打つと AI に聞けます」が出ない")
        XCTAssertEqual(AskQuery.keepTypingLine, "続けて打つと AI に聞けます")
        for text in ["おすすめの観光スポット教えて", "どこがいいの", "金沢で雨の日に行ける所は", "夕日の撮り方は",
                     "桜の名所は", "ストーリーに曲を付けるには", "近くで夕日がきれいな所は？"] {
            XCTAssertFalse(AskQuery.isUnfinished(text), "言い切った頼みを途中の字と読んだ: \(text)")
            XCTAssertFalse(SearchSubmit.showsKeepTyping(text: text, scope: .all), text)
        }
    }

    // MARK: - 人の切り替えでは打つたびに探す

    func testPeopleScopeSearchesOnEveryKeystroke() {
        let s = Screen()
        s.scope = .people
        s.type("k")
        XCTAssertEqual(s.searched, "k")
        s.type("ka")
        XCTAssertEqual(s.searched, "ka", "人の切り替えで打つたびに探さない")
        XCTAssertTrue(s.asks.isEmpty)
        // 打ちかけの字があるまま「人」に切り替えたら、その字ですぐ探す
        XCTAssertEqual(SearchSubmit.plan(.peopleScope, text: "taro", scope: .people, searched: "").searched, "taro")
    }

    // MARK: - 最近の語は押すだけで回数を減らさない

    func testRecentWordAsksOnlyFromTodaysCache() {
        let s = Screen()
        s.recent("おすすめの観光スポット教えて", cached: false)
        XCTAssertTrue(s.asks.isEmpty, "控えの無い頼みの語を押しただけで AI を呼んだ")
        XCTAssertEqual(s.searched, "おすすめの観光スポット教えて", "最近の語ですぐ結果にならない")
        XCTAssertEqual(s.reads, ["おすすめの観光スポット教えて"])
        let t = Screen()
        t.recent("おすすめの観光スポット教えて", cached: true)
        XCTAssertEqual(t.asks, ["おすすめの観光スポット教えて"], "今日の控えがあるのに答えを出さない")
        let u = Screen()
        u.recent("京都", cached: true)
        XCTAssertTrue(u.asks.isEmpty)
        XCTAssertEqual(u.searched, "京都")
    }

    // MARK: - 手順（AskEngine）まで通して、打つだけでは回数を使わない

    @MainActor
    func testTypingThenSendUsesExactlyOneCount() async throws {
        let s = Screen()
        final class Counter { var reserves = 0; var deviceAsks = 0 }
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
            serverAsk: { _, _, _ in AskService.ServerAnswer(answer: "", general: false) },
            deviceAsk: { _, _, _ in
                c.deviceAsks += 1
                return AskDevice.Result(text: "屋島がおすすめです。", general: false, picks: [], photoIds: [], sources: [])
            },
            details: { $0 }, userId: { "u1" })
        let engine = AskEngine(history: AskHistoryStore(defaults: UserDefaults(suiteName: "SearchSubmitTests.\(UUID().uuidString)")!))
        func run() async {
            for q in s.asks.dropFirst(engine.thread.count) { await engine.start(q, backend: backend) }
        }
        typeByChar("香川でおすすめの観光スポット教えて", on: s)
        s.keyboard()
        await run()
        XCTAssertEqual(c.deviceAsks, 0, "打つ、キーボードの検索だけで端末の AI を呼んだ")
        XCTAssertEqual(c.reserves, 0, "打つ、キーボードの検索だけで回数を使った")
        s.sendButton()
        await run()
        XCTAssertEqual(c.deviceAsks, 1)
        XCTAssertEqual(c.reserves, 1, "送信のボタンで1回だけ使う")
    }
}
