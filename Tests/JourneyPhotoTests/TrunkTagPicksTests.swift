import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 手荷物タグを自分で選ぶ（2026-11-08 owner 承認・札 #501・デザイナーのモック案A）:
/// 選びの線の上の形・タグの並べ方（おまかせと選んだ枠・外した枠・はがした枠）・選ぶ一覧・送り方・
/// サーバーが対応していない間の扱い・人のトランクへの反映
final class TrunkTagPicksTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func service() -> TrunkService {
        TrunkService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                    tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }

    private func label(_ id: String, _ name: String, latin: String? = nil, at: String = "2025-06-20T10:00:00Z") -> TrunkLabel {
        TrunkLabel(id: id, photoId: id, kind: .place, place: .init(name: name, latin: latin, country: nil), seed: 1, at: at)
    }

    /// 新しい順: 京都・京都（同じ地名）・高屋神社・パリ
    private var stuck: [TrunkLabel] {
        [label("a", "京都", latin: "Kyoto", at: "2026-04-03T09:00:00Z"),
         label("b", "京都", latin: "Kyoto", at: "2026-03-01T09:00:00Z"),
         label("c", "高屋神社", at: "2024-10-30T06:00:00Z"),
         label("d", "パリ", latin: "Paris", at: "2024-02-11T10:00:00Z")]
    }

    private func codes(_ picks: [TrunkTagPick], posts: Int = 120) -> [String] {
        TrunkLooks.tags(stuck: stuck, posts: posts, picks: picks).map(\.code)
    }

    // MARK: 線の上の形

    func testPickWireRoundTrip() {
        XCTAssertEqual(TrunkTagPick(wire: ""), .auto)
        XCTAssertEqual(TrunkTagPick(wire: "_"), .removed)
        XCTAssertEqual(TrunkTagPick(wire: "abc-1"), .label("abc-1"))
        XCTAssertEqual([TrunkTagPick.auto, .removed, .label("x")].map(\.wire), ["", "_", "x"])
        // 末尾のおまかせは持たない・枠は3つまで
        XCTAssertEqual(TrunkTagPick.normalized([.label("a"), .auto, .auto]), [.label("a")])
        XCTAssertEqual(TrunkTagPick.normalized([.auto, .auto]), [])
        XCTAssertEqual(TrunkTagPick.normalized([.removed, .auto, .label("c"), .label("d")]), [.removed, .auto, .label("c")])
        XCTAssertEqual(TrunkTagPick.list(wire: ["k", "", "_", "z"]), [.label("k"), .auto, .removed])
    }

    func testStateReadsTagPicksAndNoticesOldServers() throws {
        let s = try decode(TrunkState.self, #"{"pocket":[],"stuck":[],"tagPicks":["k","","_"]}"#)
        XCTAssertEqual(s.tagPicks, [.label("k"), .auto, .removed])
        XCTAssertTrue(s.supportsTagPicks)
        // 対応したサーバーは選びが無くても `[]` を返す
        let empty = try decode(TrunkState.self, #"{"pocket":[],"stuck":[],"tagPicks":[]}"#)
        XCTAssertEqual(empty.tagPicks, [])
        XCTAssertTrue(empty.supportsTagPicks)
        // 欄の無い応答（旧サーバー）は全部おまかせ・対応していない
        let old = try decode(TrunkState.self, #"{"pocket":[],"stuck":[]}"#)
        XCTAssertEqual(old.tagPicks, [])
        XCTAssertFalse(old.supportsTagPicks, "欄の無いサーバーに設定を送る")
        // 形の違う要素はおまかせ（投げない）
        let odd = try decode(TrunkState.self, #"{"pocket":[],"stuck":[],"tagPicks":["k",5,null]}"#)
        XCTAssertEqual(odd.tagPicks, [.label("k")])
        // 読み直しても落ちない（keepingPosts は選びを引き継ぐ）
        XCTAssertEqual(s.keepingPosts(from: nil).tagPicks, s.tagPicks)
        XCTAssertEqual(s.copy(posts: .some(9)).tagPicks, s.tagPicks)
        XCTAssertEqual(s.copy(tagPicks: [.removed]).tagPicks, [.removed])
        XCTAssertTrue(s.copy(posts: .some(9)).supportsTagPicks)
    }

    func testTheirTrunkReadsTagPicks() throws {
        let json = #"""
        {"stuck":[{"id":"s1","kind":"place","seed":2,"place":{"name":"パリ","latin":"Paris"},"at":"2024-02-11","where":{"location":"パリ"}},
                  {"id":"s0","kind":"place","seed":3,"place":{"name":"京都"},"at":"2025-02-11","where":{"location":"京都"}}],
         "posts":120,"tagPicks":["s0","_"]}
        """#
        let trunk = try decode(TheirTrunk.self, json)
        XCTAssertEqual(trunk.tagPicks, [.label("s0"), .removed])
        // 1枠目は選んだ京都・2枠目は外した・3枠目はおまかせ（残りのパリ）
        let drawn = TrunkLooks.tagSlotResults(stuck: trunk.stuck, posts: trunk.agingPosts, picks: trunk.tagPicks)
        XCTAssertEqual(drawn.map(\.source), [.chosen, .removed, .auto])
        XCTAssertEqual(drawn.compactMap(\.tag).map(\.code), ["京都", "PARIS"], "人のトランクに選びが映らない")
        // 欄の無い応答は全部おまかせ
        let old = try decode(TheirTrunk.self, #"{"stuck":[],"posts":1}"#)
        XCTAssertEqual(old.tagPicks, [])
    }

    // MARK: 並べ方

    /// 選びが無ければ今までと同じ（おまかせ）
    func testNoPicksIsTheOldBehavior() {
        XCTAssertEqual(codes([]), ["KYOTO", "高屋神社", "PARIS"])
        XCTAssertEqual(TrunkLooks.tags(stuck: stuck, posts: 120, picks: []), TrunkLooks.tags(stuck: stuck, posts: 120))
        XCTAssertEqual(codes([.auto, .auto, .auto]), ["KYOTO", "高屋神社", "PARIS"])
    }

    /// 選んだ枠はそのラベル、残りはおまかせが埋める（選んだ地名は重ねない）
    func testChosenSlotKeepsItsLabelAndAutoFillsTheRest() {
        // 1枠目をパリに: 2枠目は列の2番目（高屋神社）のまま、3枠目は列の3番目（パリ）が取られたので先頭の未使用（京都）
        XCTAssertEqual(codes([.label("d")]), ["PARIS", "高屋神社", "KYOTO"])
        // 2枠目を高屋神社に（おまかせの並びと同じ）: 変わらない
        XCTAssertEqual(codes([.auto, .label("c")]), ["KYOTO", "高屋神社", "PARIS"])
        // 3枠目を京都のもう一方（b）に: 同じ地名なのでおまかせは京都を重ねない（1枠目 a は京都を取り置かれ、おまかせは高屋神社から）
        XCTAssertEqual(codes([.auto, .auto, .label("b")]), ["高屋神社", "PARIS", "KYOTO"])
        // 選んだ枠は枠の場所・色のまま
        let tags = TrunkLooks.tags(stuck: stuck, posts: 120, picks: [.label("d")])
        XCTAssertEqual(tags.map(\.x), TrunkLooks.tagSlots.map(\.x))
        XCTAssertEqual(tags.first?.printedDay, "2024.02.11")
    }

    /// 「タグを外す」: その枠には吊るさない。ほかの枠は動かない
    func testRemovedSlotHangsNothing() {
        let tags = TrunkLooks.tags(stuck: stuck, posts: 120, picks: [.auto, .removed])
        XCTAssertEqual(tags.map(\.code), ["KYOTO", "PARIS"], "外した枠のほかの枠が動いた")
        XCTAssertEqual(tags.map(\.x), [TrunkLooks.tagSlots[0].x, TrunkLooks.tagSlots[2].x], "外した枠の場所に別のタグが入った")
        let results = TrunkLooks.tagSlotResults(stuck: stuck, posts: 120, picks: [.auto, .removed])
        XCTAssertEqual(results.map(\.source), [.auto, .removed, .auto])
        XCTAssertNil(results[1].tag)
        XCTAssertNil(results[1].label)
        // 全部外せば1枚も出ない
        XCTAssertTrue(TrunkLooks.tags(stuck: stuck, posts: 120, picks: [.removed, .removed, .removed]).isEmpty)
    }

    /// 触っていない枠は動かない（外す・別の枠を選ぶとき）
    func testUntouchedSlotsStay() {
        let four = stuck + [label("e", "札幌", latin: "Sapporo", at: "2023-01-01T00:00:00Z")]
        func codes4(_ picks: [TrunkTagPick]) -> [String] { TrunkLooks.tags(stuck: four, posts: 120, picks: picks).map(\.code) }
        XCTAssertEqual(codes4([]), ["KYOTO", "高屋神社", "PARIS"])
        // 1枠目を外しても、2・3枠目は同じ
        let removedFirst = TrunkLooks.tagSlotResults(stuck: four, posts: 120, picks: [.removed])
        XCTAssertEqual(removedFirst.compactMap(\.tag).map(\.code), ["高屋神社", "PARIS"])
        XCTAssertEqual(removedFirst.map(\.source), [.removed, .auto, .auto])
        // 2枠目を札幌にしても、1・3枠目は同じ
        XCTAssertEqual(codes4([.auto, .label("e")]), ["KYOTO", "SAPPORO", "PARIS"])
        // 3枠目を外しても、1・2枠目は同じ
        XCTAssertEqual(codes4([.auto, .auto, .removed]), ["KYOTO", "高屋神社"])
    }

    /// 選んだラベルがはがされた（`stuck` に無い）・地名が無い・前の枠と同じ地名の枠は、おまかせに戻す
    func testInvalidPicksFallBackToAuto() {
        XCTAssertEqual(codes([.label("gone")]), ["KYOTO", "高屋神社", "PARIS"], "はがしたラベルの枠が空いたまま")
        let sealed = stuck + [label("n", "")]
        XCTAssertEqual(TrunkLooks.tags(stuck: sealed, posts: 120, picks: [.label("n")]).map(\.code),
                       ["KYOTO", "高屋神社", "PARIS"], "地名の無いラベルをタグに載せた")
        // a と b は同じ地名: 2枠目の b は使えず、おまかせ（高屋神社）
        let results = TrunkLooks.tagSlotResults(stuck: stuck, posts: 120, picks: [.label("a"), .label("b")])
        XCTAssertEqual(results.map(\.source), [.chosen, .auto, .auto])
        XCTAssertEqual(results.compactMap(\.tag).map(\.code), ["KYOTO", "高屋神社", "PARIS"])
    }

    /// 投稿の数で増える枠より後ろの選びは使わない（吊るせない枠）
    func testPicksBeyondOpenSlotsAreIgnored() {
        let results = TrunkLooks.tagSlotResults(stuck: stuck, posts: 20, picks: [.auto, .label("d"), .removed])
        XCTAssertEqual(results.map(\.source), [.auto, .locked, .locked])
        XCTAssertEqual(results.compactMap(\.tag).map(\.code), ["KYOTO"])
        XCTAssertEqual(TrunkLooks.tags(stuck: stuck, posts: 19, picks: [.label("d")]).count, 0, "投稿 20 より前にタグを出す")
        XCTAssertEqual(TrunkAging.tagThresholds, [20, 50, 80])
        for (slot, need) in TrunkAging.tagThresholds.enumerated() {
            XCTAssertEqual(TrunkAging.tagCount(posts: need), slot + 1)
            XCTAssertEqual(TrunkAging.tagCount(posts: need - 1), slot)
        }
    }

    /// 地名が足りなければ空き（偽の行き先で埋めない）
    func testNotEnoughPlacesLeavesAnEmptySlot() {
        let one = [label("k", "札幌", latin: "Sapporo")]
        let results = TrunkLooks.tagSlotResults(stuck: one, posts: 120, picks: [.auto, .auto, .auto])
        XCTAssertEqual(results.map(\.source), [.auto, .auto, .auto])
        XCTAssertEqual(results.map { $0.tag?.code }, ["SAPPORO", nil, nil])
    }

    // MARK: 選ぶ一覧

    func testCandidatesMarkCurrentUsedAndNoPlace() {
        let all = stuck + [label("n", "")]
        // 1枠目=京都(a)・2枠目=高屋神社(c)・3枠目=パリ(d)
        let list = TrunkTagText.candidates(stuck: all, posts: 120, picks: [], slot: 1)
        XCTAssertEqual(list.map(\.id), ["a", "b", "c", "d", "n"], "地名のあるものを先に・地名の無いものを最後に")
        XCTAssertEqual(list.first { $0.id == "c" }?.availability, .current)
        XCTAssertEqual(list.first { $0.id == "a" }?.availability, .usedInSlot(0))
        XCTAssertEqual(list.first { $0.id == "b" }?.availability, .usedInSlot(0), "同じ地名の別のラベルが選べてしまう")
        XCTAssertEqual(list.first { $0.id == "d" }?.availability, .usedInSlot(2))
        XCTAssertEqual(list.first { $0.id == "n" }?.availability, .noPlace)
        XCTAssertEqual(list.filter(\.isEnabled).map(\.id), ["a", "b", "c", "d"], "別の枠の地名が選べない（地名なしだけ押せない）")
        // 外した枠では、どれも押せる（載っていない地名）
        let freed = TrunkTagText.candidates(stuck: all, posts: 120, picks: [.auto, .removed], slot: 1)
        XCTAssertEqual(freed.first { $0.id == "c" }?.availability, .available, "外した枠の地名は他の枠に載らない")
        XCTAssertEqual(freed.first { $0.id == "b" }?.availability, .usedInSlot(0))
        XCTAssertEqual(freed.first { $0.id == "d" }?.availability, .usedInSlot(2))
        // 読み上げは印と理由を文字で言う
        let note = TrunkTagText.candidateAccessibility(list[0], selected: false)
        XCTAssertTrue(note.contains("京都"))
        XCTAssertTrue(note.contains(L("1枚目の枠が、おまかせに戻ります", "Tag 1 goes back to auto")), "選ぶと何が起きるかが読み上げに無い")
        XCTAssertTrue(TrunkTagText.candidateAccessibility(list[2], selected: true).contains(TrunkTagText.onTag))
        XCTAssertEqual(TrunkTagText.candidateTitle(list[4]), TrunkTagText.noPlaceTitle)
    }

    func testPicksReplacingASlot() {
        XCTAssertEqual(TrunkTagText.picks(replacing: 1, with: .label("c"), in: []), [.auto, .label("c")])
        XCTAssertEqual(TrunkTagText.picks(replacing: 0, with: .auto, in: [.label("a"), .removed]), [.auto, .removed])
        XCTAssertEqual(TrunkTagText.picks(replacing: 0, with: .auto, in: [.label("a")]), [], "全部おまかせに戻したら空")
        XCTAssertEqual(TrunkTagText.picks(replacing: 2, with: .removed, in: [.label("a")]), [.label("a"), .auto, .removed])
    }

    /// 別の枠に出ている地名を選ぶ: 同じ地名を選んでいた元の枠は、送る選びでおまかせに戻る
    func testChoosingAShownPlaceResetsTheOtherSlot() {
        // 1枠目=京都(a)を選んでいる。3枠目に同じ地名の別ラベル b を選ぶ → 1枠目は ""
        XCTAssertEqual(TrunkTagText.picks(replacing: 2, with: .label("b"), in: [.label("a")], stuck: stuck),
                       [.auto, .auto, .label("b")])
        // 違う地名の枠は触らない
        XCTAssertEqual(TrunkTagText.picks(replacing: 2, with: .label("d"), in: [.label("c")], stuck: stuck),
                       [.label("c"), .auto, .label("d")])
        // 外した枠は触らない
        XCTAssertEqual(TrunkTagText.picks(replacing: 1, with: .label("a"), in: [.removed], stuck: stuck), [.removed, .label("a")])
    }

    func testRowTextsAndWording() {
        XCTAssertEqual(TrunkTagText.rowValue(shown: 2, open: 3), L("2 / 3 枚", "2 / 3 tags"))
        XCTAssertTrue(TrunkTagText.rowValue(shown: 0, open: 0).contains("20"), "まだ吊るせない人にいつ吊るせるかを言わない")
        let locked = TrunkLooks.tagSlotResults(stuck: stuck, posts: 68, picks: [])[2]
        XCTAssertEqual(locked.source, .locked)
        XCTAssertEqual(TrunkTagText.slotNote(2, locked, posts: 68), L("あと 12 件の投稿で、3枚目が吊るせます", "12 more posts to hang tag 3"))
        // 「捨てる」を画面に出さない（owner の好み・2026-10-09）
        let all = [TrunkTagText.title, TrunkTagText.candidateNote(
                       TrunkTagText.Candidate(label: stuck[0], availability: .usedInSlot(0)), selected: false), TrunkTagText.intro, TrunkTagText.footer, TrunkTagText.sheetNote, TrunkTagText.backToAuto,
                   TrunkTagText.removeTag, TrunkTagText.closeWithoutSaving, TrunkTagText.saveFailedTitle, TrunkTagText.saveFailedMessage,
                   TrunkTagText.offlineMessage, TrunkTagText.pickResetNotice, TrunkTagText.emptyMessage, TrunkTagText.sameNameNote]
        for text in all { XCTAssertFalse(text.contains("捨て"), text) }
        // 「撮りどき」を画面に出さない（owner の好み・2026-10-22）
        for text in all { XCTAssertFalse(text.contains("撮りどき"), text) }
    }

    // MARK: 端末の中の移り変わり（見本）・はがしたとき

    private func state(picks: [TrunkTagPick] = []) -> TrunkState {
        TrunkState(model: .leather, pocket: [], stuck: stuck + [label("n", "")], limit: 30, isPro: false, rerollsLeft: 0,
                   posts: 120, receiveLabels: true, tagPicks: picks)
    }

    func testLocalSetTagPicksFollowsTheServerRules() {
        // 貼っていない・地名の無い・同じ地名の枠はおまかせ
        let s = TrunkLocal.setTagPicks(state(), [.label("a"), .label("b"), .label("gone")])
        XCTAssertEqual(s.tagPicks, [.label("a")])
        XCTAssertEqual(TrunkLocal.setTagPicks(state(), [.label("n")]).tagPicks, [])
        XCTAssertEqual(TrunkLocal.setTagPicks(state(), [.removed, .auto, .label("d")]).tagPicks, [.removed, .auto, .label("d")])
        XCTAssertEqual(TrunkLocal.setTagPicks(state(picks: [.label("a")]), []).tagPicks, [], "全部おまかせに戻せない")
    }

    func testUnstickResetsTheTagSlot() {
        let s = state(picks: [.label("d"), .removed, .label("c")])
        // 手持ちに戻せるように、貼ったラベルがある状態
        let after = TrunkLocal.unstick(s, id: "d")
        XCTAssertEqual(after.tagPicks, [.auto, .removed, .label("c")], "はがしたラベルの枠がおまかせに戻らない")
        XCTAssertFalse(after.stuck.contains { $0.id == "d" })
        XCTAssertEqual(TrunkLocal.unstick(s, id: "a").tagPicks, s.tagPicks, "選んでいないラベルをはがして選びが変わった")
    }

    // MARK: 送り方

    private func json(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func testSetTagPicksSendsOnlyThatKey() async throws {
        StubProtocol.respond(status: 200, body: #"{"pocket":[],"stuck":[],"tagPicks":["a","","_"]}"#)
        let state = try await service().setTagPicks([.label("a"), .auto, .removed, .auto])
        XCTAssertEqual(state.tagPicks, [.label("a"), .auto, .removed])
        XCTAssertEqual(StubProtocol.requests, ["PUT /user/trunk/settings"])
        let body = try XCTUnwrap(json(StubProtocol.lastBody))
        XCTAssertEqual(Array(body.keys), ["tagPicks"], "ほかの設定を一緒に送っている")
        XCTAssertEqual(body["tagPicks"] as? [String], ["a", "", "_"])
        // 全部おまかせは空の配列（項目を落とすと「変えない」になる）
        _ = try await service().setTagPicks([])
        XCTAssertEqual(json(StubProtocol.lastBody)?["tagPicks"] as? [String], [])
    }

    func testRefusalWordsForTagPicks() {
        for code in ["tagPickNotStuck", "tagPickNoPlace", "tagPickDuplicate"] {
            let text = TrunkText.refusal(code: code, fallback: "fallback")
            XCTAssertNotEqual(text, "fallback", code)
            XCTAssertFalse(text.contains("捨て"))
        }
    }

    /// サーバーが選びに対応していない間は送らない（黙って捨てられる設定を「保存した」と言わない）
    @MainActor
    func testViewModelDoesNotSendToAnOldServer() async {
        StubProtocol.respond(status: 200, body: #"{"pocket":[],"stuck":[],"posts":50}"#)
        let model = TrunkViewModel(preview: nil)
        model.bind(service())
        await model.load(offline: false)
        XCTAssertEqual(model.state?.supportsTagPicks, false)
        StubProtocol.respond(status: 200, body: #"{"pocket":[],"stuck":[],"tagPicks":["a"]}"#)
        let saved = await model.setTagPicks([.label("a")])
        XCTAssertFalse(saved)
        XCTAssertEqual(StubProtocol.requests, ["GET /user/trunk"], "対応していないサーバーに設定を送った")
    }

    /// 保存に失敗したら状態を変えず false（画面が選びを残して「もう一度」を出す）。成功したら応答の選びを映す
    @MainActor
    func testViewModelKeepsStateWhenSaveFails() async {
        StubProtocol.respond(status: 200, body: #"{"pocket":[],"stuck":[],"posts":50,"tagPicks":[]}"#)
        let model = TrunkViewModel(preview: nil)
        model.bind(service())
        await model.load(offline: false)
        StubProtocol.respond(status: 500, body: #"{"error":"x"}"#)
        let failed = await model.setTagPicks([.removed])
        XCTAssertFalse(failed)
        XCTAssertEqual(model.state?.tagPicks, [], "失敗したのに選びが変わった")
        XCTAssertNotNil(model.actionError)
        StubProtocol.respond(status: 200, body: #"{"pocket":[],"stuck":[],"tagPicks":["_"]}"#)
        let saved = await model.setTagPicks([.removed])
        XCTAssertTrue(saved)
        XCTAssertEqual(model.state?.tagPicks, [.removed])
        XCTAssertEqual(model.state?.posts, 50, "書き込みの応答で投稿の数が消えた")
        // 同じ選びは送らない
        let before = StubProtocol.requests.count
        _ = await model.setTagPicks([.removed])
        XCTAssertEqual(StubProtocol.requests.count, before)
    }

    // MARK: 画面の配線

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 選びは、トランクを描くどの画面にも同じく渡す（画面ごとに見た目を割らない）。
    /// プロフィールの小さな札（`TrunkEntryThumb`）は胴だけの絵（タグを描かない）なので渡す先が無い
    func testPicksReachEveryTrunkThatDrawsTags() throws {
        let want: [(String, String)] = [
            ("Features/Trunk/TrunkView.swift", "tagPicks: state.tagPicks"),
            ("Features/Trunk/TrunkStickView.swift", "tagPicks: s.tagPicks"),
            ("Features/Trunk/TrunkModelsView.swift", "tagPicks: state.tagPicks"),
            ("Features/Trunk/TrunkPartsBoxView.swift", "tagPicks: state.tagPicks"),
            ("Features/Trunk/TheirTrunkView.swift", "tagPicks: trunk.tagPicks"),
            ("Features/Settings/TrunkPrivacySection.swift", "tagPicks: figure.tagPicks"),
            ("Features/Trunk/TrunkOpenView.swift", "tagPicks: tagPicks"),
            ("Features/Trunk/TrunkSpinViewer.swift", "picks: tagPicks"),
            ("Features/Trunk/TrunkBoxView.swift", "picks: tagPicks"),
        ]
        for (path, needle) in want {
            XCTAssertTrue(try source(path).contains(needle), "\(path) が手荷物タグの選びを渡していない")
        }
        // 人の口の見え方（設定の見本）は、読めたときの選びをそのまま描く
        let seen = TheirTrunkText.seenFigure(seen: TheirTrunk(userId: "u", model: .leather, stuck: stuck, posts: 120,
                                                              tagPicks: [.label("d")]), own: state())
        XCTAssertEqual(seen.tagPicks, [.label("d")])
        let fallback = TheirTrunkText.seenFigure(seen: nil, own: state(picks: [.label("d")]))
        XCTAssertEqual(fallback.tagPicks, [], "地名を伏せた形に、選んだラベルのタグが出る")
        // プロフィールの小さな札は胴だけ（タグを描かない）
        XCTAssertTrue(try source("Features/Profile/TrunkProfileChip.swift").contains("bodyOnly: true"))
    }

    /// トランクの画面から選ぶ画面へ入れる（対応したサーバーのときだけ）
    func testTagsRowIsWired() throws {
        let main = try source("Features/Trunk/TrunkView.swift")
        XCTAssertTrue(main.contains("if state.supportsTagPicks {"), "対応していないサーバーでも行を出す")
        XCTAssertTrue(main.contains("TrunkTagsView(model: model"))
        XCTAssertTrue(main.contains(#".accessibilityIdentifier("trunk.tags.open")"#))
        XCTAssertTrue(main.contains("TrunkTagText.pickResetNotice"), "はがして枠が戻ったことを知らせない")
        let view = try source("Features/Trunk/TrunkTagsView.swift")
        for id in ["trunk.tags.screen", "trunk.tags.sheet", "trunk.tags.done", "trunk.tags.retry", "trunk.tags.discard",
                   "trunk.tags.auto", "trunk.tags.remove", "trunk.tags.stick", "trunk.tags.loading"] {
            XCTAssertTrue(view.contains("\"\(id)\""), id)
        }
        // 押せるものは 44pt 以上: シートのボタンは全部 minTapTarget から作った高さを使い、足元はつぶされない
        XCTAssertTrue(view.contains("private static let buttonHeight: Double = Double(WebTheme.minTapTarget) + 4"))
        XCTAssertFalse(view.contains("height: 44"), "シートのボタンに 44 ちょうどの固定が残っている")
        XCTAssertFalse(view.contains("height: 50"))
        XCTAssertEqual(view.components(separatedBy: "TrunkButtonFace(").count - 1,
                       view.components(separatedBy: "height: Self.buttonHeight").count - 1, "高さを共通の値にしていないボタンがある")
        XCTAssertTrue(view.contains(".fixedSize(horizontal: false, vertical: true)\n        .layoutPriority(1)"), "足元がつぶされうる")
        XCTAssertTrue(view.contains("minHeight: 56"), "ラベルの行が 56 未満")
        // 失敗しても選びを捨てない: 失敗したら選びを残し、「もう一度」で同じ選びを送り直す
        XCTAssertTrue(view.contains("failed = pick"))
        // 書き込み中・未対応の false を「通信に失敗しました」にしない
        XCTAssertTrue(view.contains("guard !model.busy else { return }"))
        XCTAssertTrue(view.contains("} else if model.actionError != nil {"))
        XCTAssertTrue(view.contains("commit(failedPick)"))
    }
}
