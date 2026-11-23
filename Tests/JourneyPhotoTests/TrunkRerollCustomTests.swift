import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// ラベルごとの作り直し3回と、好きなデザインで作る（札 #706・2026-11-23 owner 承認「推奨でお願い」）。
///
/// サーバー（photo-gallery `api-user/src/trunk.ts`）の決まりと同じことを、アプリの読み方・端末の中の移り変わり・
/// 画面の言葉・送る本文で見張る
final class TrunkRerollCustomTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        session = URLSession(configuration: config)
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }

    private func trunkService() -> TrunkService {
        TrunkService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                    tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    private func label(_ id: String, seed: Int = 42, extra: String = "") -> String {
        #"{"id":"\#(id)","kind":"place","place":{"name":"京都"},"seed":\#(seed),"at":"2026-10-17T00:00:00Z"\#(extra)}"#
    }

    private func state(pocket: [TrunkLabel], custom: TrunkCustomProgress? = TrunkCustomProgress(posts: 1, tickets: 0, every: 3),
                       stuck: [TrunkLabel] = []) -> TrunkState {
        TrunkState(model: .leather, pocket: pocket, stuck: stuck, limit: 30, isPro: false, rerollsLeft: 0, posts: 0,
                   receiveLabels: true, custom: custom)
    }

    private func plain(_ id: String, seed: Int = 42) -> TrunkLabel {
        TrunkLabel(id: id, photoId: id, kind: .place, place: .init(name: "京都", latin: nil, country: "日本"), seed: seed,
                   at: "2026-10-17T00:00:00Z")
    }

    // MARK: 読み方

    func testDecodesRerollCandidatesAndCustom() throws {
        let s = try decode(TrunkState.self, """
        {"pocket":[\(label("a", extra: #","rr":2,"cs":[42,7,8],"cu":{"shape":9,"palette":11,"art":0}"#))],
         "stuck":[], "custom":{"n":1,"t":2,"every":2,"rerolls":3}}
        """)
        let a = try XCTUnwrap(s.pocket.first)
        XCTAssertEqual(a.rerolls, 2)
        XCTAssertEqual(a.candidates, [42, 7, 8])
        XCTAssertEqual(a.custom, TrunkLabelCustom(shape: 9, palette: 11, art: 0))
        XCTAssertEqual(a.rerollsLeft, 1)
        XCTAssertEqual(s.custom, TrunkCustomProgress(posts: 1, tickets: 2, every: 2))
        XCTAssertTrue(s.supportsLabelReroll)
    }

    /// 古いサーバー（`custom` の欄が無い）は作り直しの口を出さない。壊れた値は無いものとして読む
    func testOldServerAndBadValues() throws {
        let old = try decode(TrunkState.self, #"{"pocket":[\#(label("a"))],"rerolls":{"left":3},"isPro":true}"#)
        XCTAssertNil(old.custom)
        XCTAssertFalse(old.supportsLabelReroll)
        XCTAssertEqual(TrunkText.redoStep(old, label: old.pocket[0]), .hidden, "古いサーバーに n を送る作り直しを出した")
        let bad = try decode(TrunkState.self, """
        {"pocket":[\(label("a", extra: #","rr":9,"cs":[1,2,3,4,5],"cu":{"shape":10,"palette":0,"art":0}"#)),
                   \(label("b", extra: #","rr":"x","cs":"no","cu":[1,2,3]"#))], "custom":{"n":7,"t":99,"every":3}}
        """)
        XCTAssertEqual(bad.pocket.map(\.id), ["a", "b"], "壊れた欄でラベルごと落とした")
        XCTAssertEqual(bad.pocket[0].rerolls, TrunkLabel.rerollMax, "回数は上限で止める")
        XCTAssertEqual(bad.pocket[0].candidates, [], "候補が多すぎるものは読まない")
        XCTAssertNil(bad.pocket[0].custom, "範囲の外の形を読んだ")
        XCTAssertEqual(bad.pocket[1].rerolls, 0)
        XCTAssertNil(bad.pocket[1].custom)
        XCTAssertEqual(bad.custom, TrunkCustomProgress(posts: 2, tickets: 3, every: 3))
    }

    /// 選べる数はサーバー（`CUSTOM_SHAPES` 10・`CUSTOM_PALETTES` 12・`CUSTOM_ARTS` 12）と同じ
    func testCustomListsMatchServer() {
        XCTAssertEqual(TrunkLabelDesign.customShapes.count, 10)
        XCTAssertEqual(Set(TrunkLabelDesign.customShapes).count, 10)
        XCTAssertEqual(TrunkLabelDesign.customPalettes.count, 12)
        XCTAssertEqual(Set(TrunkLabelDesign.customPalettes.map(\.bg)).count, 12, "地の色が重なる組がある")
        XCTAssertEqual(TrunkLabelDesign.customArts.count, 12)
        XCTAssertEqual(Set(TrunkLabelDesign.customArts).count, 12)
        XCTAssertEqual(TrunkLabel.rerollMax, 3)
    }

    // MARK: 図柄

    /// 好きなデザインは形・色・絵だけを替える（字・傾き・刷りのずれ・箔は種と中身のまま）
    func testSpecUsesCustomOnlyForShapeColorArt() {
        let base = plain("a", seed: 41_207)
        let custom = TrunkLabelCustom(shape: 9, palette: 7, art: 3)
        let before = TrunkLabelDesign.spec(for: base)
        let after = TrunkLabelDesign.spec(for: base.withCustom(custom))
        XCTAssertEqual(after.shape, .burst)
        XCTAssertEqual(after.bg, TrunkRGBA(TrunkLabelDesign.customPalettes[7].bg))
        XCTAssertEqual(after.art, .sakura)
        XCTAssertEqual(after.t2, before.t2)
        XCTAssertEqual(after.rot, before.rot)
        XCTAssertEqual(after.misreg, before.misreg)
        XCTAssertEqual(after.foil, before.foil)
        // 範囲の外の番号（`init` で作った物）は種のまま描く
        XCTAssertEqual(TrunkLabelDesign.spec(for: base.withCustom(TrunkLabelCustom(shape: 99, palette: 0, art: 0))), before)
        // 開いたときの「おまかせ」は今の図柄の形
        XCTAssertEqual(TrunkLabelDesign.customShapes[TrunkLabelDesign.customStart(for: base).shape], before.shape)
        XCTAssertEqual(TrunkLabelDesign.customStart(for: base.withCustom(custom)), custom)
        XCTAssertTrue(TrunkLabelDesign.customShuffle(seed: 5).isValid)
    }

    // MARK: 端末の中の移り変わり（サーバーと同じ決まり）

    func testLocalRerollFollowsServerRules() {
        let s = state(pocket: [plain("a"), plain("b")])
        let once = TrunkLocal.reroll(s, id: "a", seed: 100)
        let a = once.pocket[0]
        XCTAssertEqual(a.seed, 100, "新しい図柄が選ばれた状態になっていない")
        XCTAssertEqual(a.candidates, [42, 100], "候補の先頭が最初の1枚でない")
        XCTAssertEqual(a.rerolls, 1)
        let three = TrunkLocal.reroll(TrunkLocal.reroll(once, id: "a", seed: 200), id: "a", seed: 300)
        XCTAssertEqual(three.pocket[0].candidates, [42, 100, 200, 300])
        XCTAssertEqual(TrunkLocal.reroll(three, id: "a", seed: 400), three, "4回目を作った")
        XCTAssertEqual(TrunkText.redoStep(three, label: three.pocket[0]), .usedUp)
        XCTAssertEqual(TrunkText.redoStep(s, label: s.pocket[0]), .ready(left: 3))
        // 候補から選ぶ（最初の1枚に戻せる）・候補にない種は選べない
        XCTAssertEqual(TrunkLocal.choose(three, id: "a", seed: 42).pocket[0].seed, 42)
        XCTAssertEqual(TrunkLocal.choose(three, id: "a", seed: 999), three)
        // 貼ったら候補は消え、回数は残る
        let stuck = TrunkLocal.stick(three, id: "a")
        XCTAssertEqual(stuck.stuck[0].candidates, [])
        XCTAssertEqual(stuck.stuck[0].rerolls, 3)
        XCTAssertEqual(TrunkText.redoStep(stuck, label: stuck.stuck[0]), .hidden, "貼ったラベルに作り直しを出した")
        // 好きなデザインのラベルは作り直さない
        let made = state(pocket: [plain("c").withCustom(TrunkLabelCustom(shape: 0, palette: 0, art: 0))])
        XCTAssertEqual(TrunkLocal.reroll(made, id: "c", seed: 5), made)
        XCTAssertEqual(TrunkText.redoStep(made, label: made.pocket[0]), .hidden)
    }

    func testLocalCustomUsesOneTicket() {
        let c = TrunkLabelCustom(shape: 3, palette: 4, art: 5)
        let none = state(pocket: [plain("a")])
        XCTAssertEqual(TrunkLocal.custom(none, id: "a", custom: c), none, "回数が無いのに作った")
        let one = state(pocket: [plain("a")], custom: TrunkCustomProgress(posts: 0, tickets: 1, every: 3))
        let made = TrunkLocal.custom(one, id: "a", custom: c)
        XCTAssertEqual(made.pocket[0].custom, c)
        XCTAssertEqual(made.custom?.tickets, 0)
        XCTAssertEqual(TrunkLocal.custom(made, id: "a", custom: c), made, "同じデザインで回数を二度使った")
        XCTAssertEqual(TrunkLocal.custom(one, id: "a", custom: TrunkLabelCustom(shape: 10, palette: 0, art: 0)), one)
    }

    /// 進み具合（2行目の「あと N 回の投稿」・作れるようになった投稿）
    func testProgress() {
        XCTAssertEqual(TrunkCustomProgress(posts: 1, tickets: 0, every: 3).postsLeft, 2)
        XCTAssertEqual(TrunkCustomProgress(posts: 0, tickets: 0, every: 2).postsLeft, 2)
        XCTAssertTrue(TrunkCustomProgress(posts: 0, tickets: 1, every: 3).canMake)
        // 使わずに次を投稿した（進み 1・回数 1）: 回数があるので作れる（確かめ役の指摘・前は「あと2回の投稿」と出た）
        let kept = TrunkCustomProgress(posts: 1, tickets: 1, every: 3)
        XCTAssertTrue(kept.canMake)
        XCTAssertEqual(TrunkText.customProgressAccessibility(kept), TrunkText.customReady(tickets: 1))
        XCTAssertFalse(TrunkCustomProgress(posts: 0, tickets: 0, every: 3).canMake)
        XCTAssertEqual(TrunkText.customProgressAccessibility(TrunkCustomProgress(posts: 1, tickets: 0, every: 3)),
                       L("好きなデザインで作れるまで、あと 2 回の投稿", "2 more posts until you can make your own design"))
        XCTAssertEqual(TrunkText.customPostsLeft(2), L("あと 2 回の投稿", "2 more posts"))
        XCTAssertEqual(TrunkText.customProgressTitle, L("好きなデザインで作れるまで", "Until you can make your own design"))
    }

    // MARK: 送る本文

    /// 作り直しは何回目かを添えて送る（同じ回の送り直しをサーバーが二度数えないように）。新しい種は応答から映す
    @MainActor
    func testRerollSendsCountAndReflectsResponse() async throws {
        let model = TrunkViewModel(preview: nil)
        model.bind(trunkService())
        let rolled = label("a", seed: 777, extra: #","rr":1,"cs":[42,777]"#)
        ScriptedProtocol.script = [
            .init(match: "/reroll", status: 200,
                  body: #"{"pocket":[\#(rolled)],"stuck":[],"custom":{"n":1,"t":0,"every":3}}"#),
            .init(match: "/user/trunk", status: 200,
                  body: #"{"pocket":[\#(label("a"))],"stuck":[],"custom":{"n":1,"t":0,"every":3}}"#),
        ]
        await model.load(offline: false)
        let ok = await model.reroll("a")
        XCTAssertTrue(ok)
        let call = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path.hasSuffix("/user/trunk/labels/a/reroll") })
        XCTAssertEqual(call.method, "POST")
        let body = try XCTUnwrap(call.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["n"] as? Int, 1, "何回目かを送っていない")
        XCTAssertEqual(model.state?.pocket.first?.seed, 777)
        XCTAssertEqual(model.state?.pocket.first?.candidates, [42, 777])
    }

    /// 古いサーバーには作り直しを送らない（Pro の月の数え方のサーバーは n を読まない）
    @MainActor
    func testRerollIsNotSentToOldServer() async {
        let model = TrunkViewModel(preview: nil)
        model.bind(trunkService())
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[\#(label("a"))],"stuck":[],"isPro":true,"rerolls":{"left":3}}"#)]
        await model.load(offline: false)
        let ok = await model.reroll("a")
        XCTAssertFalse(ok)
        XCTAssertFalse(ScriptedProtocol.calls.contains { $0.path.hasSuffix("/reroll") })
    }

    /// 好きなデザインは形・色・絵の番号を送る
    @MainActor
    func testCustomSendsIndexes() async throws {
        let model = TrunkViewModel(preview: nil)
        model.bind(trunkService())
        let made = label("a", extra: #","cu":{"shape":1,"palette":2,"art":3}"#)
        ScriptedProtocol.script = [
            .init(match: "/custom", status: 200,
                  body: #"{"pocket":[\#(made)],"stuck":[],"custom":{"n":0,"t":0,"every":3}}"#),
            .init(match: "/user/trunk", status: 200,
                  body: #"{"pocket":[\#(label("a"))],"stuck":[],"custom":{"n":0,"t":1,"every":3}}"#),
        ]
        await model.load(offline: false)
        let ok = await model.makeCustom("a", TrunkLabelCustom(shape: 1, palette: 2, art: 3))
        XCTAssertTrue(ok)
        let call = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path.hasSuffix("/user/trunk/labels/a/custom") })
        let body = try XCTUnwrap(call.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["shape"] as? Int, 1)
        XCTAssertEqual(body["palette"] as? Int, 2)
        XCTAssertEqual(body["art"] as? Int, 3)
        XCTAssertEqual(model.state?.custom?.tickets, 0)
    }

    /// 作り直しが届かなかった（503）あと、もう一度押すと**同じ n** を送る（サーバーは二度数えない）
    @MainActor
    func testRerollRetrySendsSameCount() async throws {
        let model = TrunkViewModel(preview: nil)
        model.bind(trunkService())
        let rolled = label("a", seed: 777, extra: #","rr":1,"cs":[42,777]"#)
        ScriptedProtocol.script = [
            .init(match: "/reroll", status: 503, body: #"{"error":"x"}"#, once: true),
            .init(match: "/reroll", status: 200, body: #"{"pocket":[\#(rolled)],"stuck":[],"custom":{"n":1,"t":0,"every":3}}"#),
            .init(match: "/user/trunk", status: 200, body: #"{"pocket":[\#(label("a"))],"stuck":[],"custom":{"n":1,"t":0,"every":3}}"#),
        ]
        await model.load(offline: false)
        let first = await model.reroll("a")
        XCTAssertFalse(first)
        XCTAssertFalse(model.lastWriteRefused, "届かなかったのを断りと数えた（「回数は減っていません」が出ない）")
        XCTAssertEqual(model.state?.pocket.first?.seed, 42, "届かなかったのに図柄が替わった")
        let second = await model.reroll("a")
        XCTAssertTrue(second)
        let bodies = try ScriptedProtocol.calls.filter { $0.path.hasSuffix("/reroll") }.map {
            try XCTUnwrap($0.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })["n"] as? Int
        }
        XCTAssertEqual(bodies, [1, 1], "送り直しで回数を進めた")
    }

    /// 断られた（回数が合わない）ら、サーバーの今を読み直す。一言は残す
    @MainActor
    func testRerollRefusalReloads() async {
        let model = TrunkViewModel(preview: nil)
        model.bind(trunkService())
        let fresh = label("a", seed: 9, extra: #","rr":2,"cs":[42,8,9]"#)
        ScriptedProtocol.script = [
            .init(match: "/reroll", status: 409, body: #"{"error":"x","code":"rerollOrder"}"#),
            .init(match: "/user/trunk", status: 200, body: #"{"pocket":[\#(label("a"))],"stuck":[],"custom":{"n":1,"t":0,"every":3}}"#, once: true),
            .init(match: "/user/trunk", status: 200,
                  body: #"{"pocket":[\#(fresh)],"stuck":[],"custom":{"n":1,"t":0,"every":3}}"#),
        ]
        await model.load(offline: false)
        let ok = await model.reroll("a")
        XCTAssertFalse(ok)
        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.method == "GET" }.count, 2, "断られたのに読み直していない")
        XCTAssertEqual(model.state?.pocket.first?.rerolls, 2)
        XCTAssertEqual(model.actionError, TrunkText.refusal(code: "rerollOrder", fallback: ""))
    }

    /// 候補を押して届かなかった: 図柄は替えず、一言（`actionError`）を出す
    @MainActor
    func testChooseFailureKeepsDesignAndSays() async {
        let model = TrunkViewModel(preview: nil)
        model.bind(trunkService())
        let rolled = label("a", seed: 8, extra: #","rr":1,"cs":[42,8]"#)
        ScriptedProtocol.script = [
            .init(match: "/choose", status: 503, body: #"{"error":"x"}"#),
            .init(match: "/user/trunk", status: 200,
                  body: #"{"pocket":[\#(rolled)],"stuck":[],"custom":{"n":1,"t":0,"every":3}}"#),
        ]
        await model.load(offline: false)
        let ok = await model.choose("a", seed: 42)
        XCTAssertFalse(ok)
        XCTAssertEqual(model.state?.pocket.first?.seed, 8, "届かなかったのに図柄を替えた")
        XCTAssertNotNil(model.actionError, "届かなかったことを言っていない")
    }

    /// 何枚も届いたとき: 好きなデザインで1枚貼ったら次の1枚へ。最後なら閉じる
    func testArrivalCursorMovesToNext() {
        XCTAssertEqual(TrunkArrivalCursor.next(after: 0, count: 3), 1)
        XCTAssertEqual(TrunkArrivalCursor.next(after: 1, count: 3), 2)
        XCTAssertNil(TrunkArrivalCursor.next(after: 2, count: 3))
        XCTAssertNil(TrunkArrivalCursor.next(after: 0, count: 1))
        // 2枚目から先も、手持ちで作り直せる（届いた画面と同じ段）
        let s = state(pocket: [plain("a"), plain("b")])
        XCTAssertEqual(TrunkText.redoStep(s, label: s.pocket[1]), .ready(left: 3))
    }

    /// 読み上げは番号でなく名前（「形：切符」）。並びの全部に名前がある
    func testOptionNamesAreSpoken() {
        XCTAssertEqual(TrunkText.customOptionAccessibility(tab: TrunkText.customShapeTab, name: TrunkText.shapeName(.ticket)),
                       L("形：切符", "Shape: Ticket"))
        XCTAssertEqual(TrunkText.artName(.maple), L("もみじ", "Maple leaf"))
        for art in TrunkLabelDesign.customArts { XCTAssertNotEqual(TrunkText.artName(art), art.rawValue, "\(art) に名前が無い") }
        let palettes = (0..<TrunkLabelDesign.customPalettes.count).map(TrunkText.paletteName)
        XCTAssertEqual(Set(palettes).count, TrunkLabelDesign.customPalettes.count, "色の名前が重なる")
        XCTAssertEqual(Set(TrunkLabelDesign.customShapes.map(TrunkText.shapeName)).count, 10)
        XCTAssertEqual(TrunkText.candidatesHint(rerolls: 0), L("作り直すと、ここに候補が並びます", "Redo and your options line up here"))
        XCTAssertEqual(TrunkText.candidatesHint(rerolls: 2), L("押すと、前の図柄に戻せます", "Tap one to go back to an earlier design"))
    }

    // MARK: 画面の言葉

    func testRefusalsSayWhatHappened() {
        XCTAssertEqual(TrunkText.refusal(code: "noRerollsLeft", fallback: ""),
                       L("このラベルの作り直しは使い切りました（1枚につき3回まで）。", "You\u{2019}ve used all redos for this label (3 per label)."))
        for code in ["rerollOrder", "custom", "noCustom", "badCustom", "notInPocket"] {
            XCTAssertNotEqual(TrunkText.refusal(code: code, fallback: "x"), "x", "\(code) の言葉が無い")
        }
        XCTAssertFalse(TrunkText.refusal(code: "noRerollsLeft", fallback: "").contains("来月"), "月の数え方の言葉が残っている")
    }

    func testRedoWording() {
        XCTAssertEqual(TrunkText.redoTitle(left: 3), L("作り直す\u{2002}あと 3 回", "Redo\u{2002}3 left"))
        XCTAssertEqual(TrunkText.redoTitle(left: 1, again: true), L("もう一度作り直す\u{2002}あと 1 回", "Try again\u{2002}1 left"))
        XCTAssertEqual(TrunkText.candidateCaption(0), L("最初", "First"))
        XCTAssertEqual(TrunkText.candidateCaption(2), L("2回目", "Redo 2"))
    }

    // MARK: 見張り（画面の文に「カスタム」を出さない・「・」で区切らない）

    private static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.sources.appendingPathComponent(path), encoding: .utf8)
    }

    /// 画面の文（`L("…"` の日本語）だけを取り出す。注記・識別子は見ない
    private func screenStrings(_ text: String) -> [String] {
        let pattern = #"L\("((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private let screens = ["Core/Text/TrunkText.swift", "Features/Trunk/LabelArrivedView.swift",
                           "Features/Trunk/TrunkCustomView.swift", "Features/Trunk/TrunkPocketView.swift",
                           "Features/Pro/PaywallView.swift"]

    /// 2026-11-23 owner: 画面では「カスタム」と言わない（「好きなデザインで作る」）
    func testNoKatakanaCustomOnScreens() throws {
        for path in screens {
            for s in screenStrings(try source(path)) {
                XCTAssertFalse(s.contains("カスタム"), "\(path) の画面の文に「カスタム」: \(s)")
            }
        }
        for s in [TrunkText.customTitle, TrunkText.customThanks, TrunkText.customProgressTitle, TrunkText.customPocketTitle,
                  TrunkText.customDoneTitle(sticks: true), TrunkText.customDoneTitle(sticks: false), TrunkText.customShuffleTitle,
                  TrunkText.customReady(tickets: 2), TrunkText.customFixedNote, TrunkText.customLaterNote, ProBenefit.trunk.body] {
            XCTAssertFalse(s.contains("カスタム"), "「カスタム」: \(s)")
            XCTAssertFalse(s.lowercased().contains("custom"), "custom: \(s)")
        }
    }

    /// 2026-11-12 owner: 「・」「·」で区切らない。この札（#706）で足した文と、作り直し・好きなデザインの画面の文で見る
    func testNoMiddleDotSeparators() throws {
        let added = [TrunkText.redoTitle(left: 2), TrunkText.redoTitle(left: 2, again: true), TrunkText.redoUsedUp,
                     TrunkText.redoOffline, TrunkText.redoFailed, TrunkText.redoAccessibility(left: 1),
                     TrunkText.candidateCaption(0), TrunkText.candidateCaption(3), TrunkText.candidateAccessibility(1),
                     TrunkText.candidateEmptyAccessibility(2), TrunkText.customProgressTitle, TrunkText.customPostsLeft(2),
                     TrunkText.candidatesHint(rerolls: 0), TrunkText.candidatesHint(rerolls: 1),
                     TrunkText.customOptionAccessibility(tab: "形", name: "切符"),
                     TrunkText.customReady(tickets: 1), TrunkText.customReady(tickets: 3), TrunkText.customTitle,
                     TrunkText.customThanks, TrunkText.customKeepTitle, TrunkText.customLaterNote, TrunkText.customFixedNote,
                     TrunkText.customFoilNote, TrunkText.customDoneTitle(sticks: true), TrunkText.customDoneTitle(sticks: false),
                     TrunkText.customShuffleTitle, TrunkText.customMade, TrunkText.customPocketTitle,
                     TrunkText.customProgressAccessibility(TrunkCustomProgress(posts: 1, tickets: 0, every: 3)),
                     ProBenefit.trunk.body]
            + ["noRerollsLeft", "rerollOrder", "custom", "noCustom", "badCustom", "notInPocket"].map { TrunkText.refusal(code: $0, fallback: "") }
        for s in added {
            XCTAssertFalse(s.contains("・") || s.contains("·") || s.contains("\u{30FB}") || s.contains("\u{00B7}"), "中黒で区切っている: \(s)")
        }
        for path in ["Features/Trunk/TrunkCustomView.swift", "Features/Trunk/LabelArrivedView.swift"] {
            for s in screenStrings(try source(path)) where !s.isEmpty {
                XCTAssertFalse(s.contains("·"), "\(path) の画面の文に「·」: \(s)")
            }
        }
        for s in screenStrings(try source("Features/Trunk/TrunkCustomView.swift")) {
            XCTAssertFalse(s.contains("・"), "TrunkCustomView の画面の文に「・」: \(s)")
        }
    }

    /// Pro の月3回の作り直しはやめた（画面と案内に残さない）
    func testProMonthlyRerollIsGone() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.sources.appendingPathComponent("Features/Trunk/TrunkRerollView.swift").path),
                       "Pro の作り直しの画面が残っている")
        XCTAssertFalse(ProBenefit.trunk.body.contains("作り直し"), "Pro の案内に作り直しが残っている")
        XCTAssertTrue(ProBenefit.trunk.body.contains("好きなデザイン"))
        for path in ["Features/Trunk/LabelArrivedView.swift", "Features/Trunk/TrunkPocketView.swift"] {
            let text = try source(path)
            XCTAssertFalse(text.contains("TrunkRerollView("), "\(path) が古い作り直しの画面を開く")
            XCTAssertFalse(text.contains("rerollsLeft"), "\(path) が月の回数を読む")
        }
        let arrived = try source("Features/Trunk/LabelArrivedView.swift")
        XCTAssertFalse(arrived.contains("TrunkProTag()"), "届いた画面の作り直しに PRO の印が残っている")
        XCTAssertTrue(arrived.contains("TrunkCustomView(model: model, labelId: arrival.label.id, sticks: true)"))
    }
}
