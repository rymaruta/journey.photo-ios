import XCTest
@testable import JourneyPhoto

/// 旅のトランクの応答の読み方・手持ちの表示・端末の中の移り変わり・届いた画面の待ち（2026-10-17）
final class TrunkModelTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }

    private let fullJSON = """
    {
      "model": "urushi", "effectiveModel": "leather",
      "pocket": [
        {"id": "p-1", "photoId": "p-1", "kind": "season", "place": {"name": "京都", "latin": "Kyoto", "country": "日本"},
         "season": "spring", "seed": 41207, "at": "2026-04-03T09:00:00Z", "foil": true},
        {"id": "p-2", "photoId": "p-2", "kind": "milestone", "place": {"name": ""}, "milestone": "posts10",
         "seed": 10010, "at": "2025-05-05T10:00:00Z"}
      ],
      "stuck": [
        {"id": "s-1", "photoId": "s-1", "kind": "timeslot", "place": {"name": "函館"}, "timeslot": "night",
         "seed": 1, "at": "2019-02-08T21:30:00Z"}
      ],
      "limit": 30, "isPro": false,
      "rerolls": {"left": 0, "month": "2026-10"},
      "pendingReroll": {"labelId": "p-1", "seeds": [11, 22, 33], "at": "2026-10-17T00:00:00Z"},
      "posts": 42, "receiveLabels": false
    }
    """

    func testDecodesFullResponse() throws {
        let s = try decode(TrunkState.self, fullJSON)
        XCTAssertEqual(s.model, .urushi)
        XCTAssertEqual(s.effectiveModel, .leather, "Pro をやめた人はサーバーが決めた無料の型で描く")
        XCTAssertEqual(s.pocket.map(\.id), ["p-1", "p-2"])
        XCTAssertEqual(s.pocket[0].season, .spring)
        XCTAssertTrue(s.pocket[0].foil)
        XCTAssertEqual(s.pocket[1].milestone, .posts10)
        XCTAssertEqual(s.stuck.first?.timeslot, .night)
        XCTAssertEqual(s.limit, 30)
        XCTAssertFalse(s.isPro)
        XCTAssertEqual(s.rerollsLeft, 0)
        XCTAssertEqual(s.pendingReroll, TrunkPendingReroll(labelId: "p-1", seeds: [11, 22, 33]))
        XCTAssertEqual(s.posts, 42)
        XCTAssertFalse(s.receiveLabels)
    }

    /// 新しい項目は全部欠けても読める（古いサーバー・書き込みの応答の `posts` 無し）
    func testMissingFieldsFallBack() throws {
        let s = try decode(TrunkState.self, #"{"pocket": []}"#)
        XCTAssertEqual(s.model, .leather)
        XCTAssertEqual(s.effectiveModel, .leather)
        XCTAssertEqual(s.stuck, [])
        XCTAssertEqual(s.limit, TrunkState.freeLimit)
        XCTAssertEqual(s.rerollsLeft, 0)
        XCTAssertNil(s.pendingReroll)
        XCTAssertNil(s.posts)
        XCTAssertTrue(s.receiveLabels, "受け取りは既定でオン（サーバーと同じ）")
        let pro = try decode(TrunkState.self, #"{"stuck": [], "isPro": true}"#)
        XCTAssertEqual(pro.limit, TrunkState.proLimit)
        // 知らない型・Pro の型だけ（effectiveModel 無し）は無料の型で描く
        let unknown = try decode(TrunkState.self, #"{"pocket": [], "model": "spaceship"}"#)
        XCTAssertEqual(unknown.model, .leather)
        let proOnly = try decode(TrunkState.self, #"{"pocket": [], "model": "captain"}"#)
        XCTAssertEqual(proOnly.effectiveModel, .leather)
    }

    /// 形の違う応答（手持ちも貼った一覧も無い）は「空のトランク」と混ぜずに投げる
    func testRejectsNonTrunkShape() {
        XCTAssertThrowsError(try decode(TrunkState.self, #"{"error": "見つかりません"}"#))
        XCTAssertThrowsError(try decode(TrunkState.self, #"[]"#))
    }

    /// 1枚の型違いで全体を落とさない。id・種の読めないラベルだけ落とす
    func testBadLabelsAreDroppedNotFatal() throws {
        let json = """
        {"pocket": [
          {"id": "ok-1", "kind": "place", "place": {"name": "パリ"}, "seed": 5, "at": "2026-01-01T00:00:00Z"},
          {"id": "../user/account", "kind": "place", "place": {"name": "x"}, "seed": 5, "at": ""},
          {"id": "no-seed", "kind": "place", "place": {"name": "x"}, "at": ""},
          {"id": "neg", "kind": "place", "place": {"name": "x"}, "seed": -1, "at": ""},
          "not an object",
          {"id": "odd", "kind": "dragon", "place": "not an object", "seed": "77", "foil": "yes", "season": 3}
        ], "limit": "40", "rerolls": {"left": "2"}, "posts": 12.0}
        """
        let s = try decode(TrunkState.self, json)
        XCTAssertEqual(s.pocket.map(\.id), ["ok-1", "odd"], "道に入れられない id・種の無いラベルは押せる札にしない")
        let odd = s.pocket[1]
        XCTAssertEqual(odd.kind, .place, "知らない系統は土地のラベルとして描く")
        XCTAssertEqual(odd.place.name, "")
        XCTAssertEqual(odd.seed, 77, "数の文字列も種として読む")
        XCTAssertFalse(odd.foil)
        XCTAssertNil(odd.season)
        XCTAssertEqual(odd.photoId, "odd")
        XCTAssertEqual(s.limit, 40)
        XCTAssertEqual(s.rerollsLeft, 2)
        XCTAssertEqual(s.posts, 12)
    }

    /// 書き込みの応答には `posts` が無いので、前に読んだ数を引き継ぐ（古び方が新品に戻らない）
    func testKeepingPosts() throws {
        let before = try decode(TrunkState.self, fullJSON)
        let after = try decode(TrunkState.self, #"{"pocket": [], "stuck": []}"#)
        XCTAssertEqual(after.keepingPosts(from: before).posts, 42)
        XCTAssertEqual(before.keepingPosts(from: after).posts, 42)
        XCTAssertNil(after.keepingPosts(from: nil).posts)
    }

    /// 投稿の保存の応答（`label`・`labelSkipped`）。無くても・壊れていても投稿は成功のまま
    func testSaveResponseCarriesLabel() throws {
        let dealt = try decode(UploadService.SaveResponse.self, """
        {"success": true,
         "label": {"id": "ph-1", "photoId": "ph-1", "kind": "season", "place": {"name": "京都"}, "season": "spring",
                   "seed": 9, "at": "2026-10-17T00:00:00Z"}}
        """)
        XCTAssertEqual(dealt.label?.id, "ph-1")
        XCTAssertNil(dealt.labelSkipped)
        let full = try decode(UploadService.SaveResponse.self, #"{"success": true, "label": null, "labelSkipped": "full"}"#)
        XCTAssertNil(full.label)
        XCTAssertEqual(full.labelSkipped, .full)
        let old = try decode(UploadService.SaveResponse.self, #"{"success": true}"#)
        XCTAssertNil(old.label)
        XCTAssertNil(old.labelSkipped)
        let broken = try decode(UploadService.SaveResponse.self, #"{"success": true, "label": {"id": 3}, "labelSkipped": 5}"#)
        XCTAssertNil(broken.label, "壊れたラベルは読まない（投稿は成功のまま）")
        XCTAssertNil(broken.labelSkipped)
        XCTAssertEqual(TrunkLabelSkip("timeout"), .other("timeout"))
        XCTAssertEqual(TrunkLabelSkip("daily"), .daily)
    }

    // MARK: 手持ちの上限の表示（モック Pocket・LabelArrived）

    func testPocketLimitDisplay() {
        XCTAssertEqual(TrunkText.pocketCounter(count: 28, limit: 30), "28 / 30")
        XCTAssertEqual(TrunkText.pocketFraction(count: 28, limit: 30), 28.0 / 30, accuracy: 1e-12)
        XCTAssertEqual(TrunkText.pocketFraction(count: 45, limit: 30), 1, "Pro をやめて上限を越えていても棒は満杯で止める")
        XCTAssertEqual(TrunkText.pocketFraction(count: 3, limit: 0), 1, "上限 0 でも割り算で落ちない")
        XCTAssertEqual(TrunkText.remaining(count: 28, limit: 30), L("あと2枚", "2 left"))
        XCTAssertEqual(TrunkText.remaining(count: 30, limit: 30), L("いっぱいです", "Full"))
        XCTAssertTrue(TrunkText.isFull(count: 30, limit: 30))
        XCTAssertFalse(TrunkText.isFull(count: 29, limit: 30))
        XCTAssertEqual(TrunkText.rerollsLeft(2), L("あと 2 回", "2 left"))
        XCTAssertEqual(TrunkText.rerollsLeft(-1), L("あと 0 回", "0 left"))
    }

    /// 数え札（貼ったラベル・か国・地域・年から）
    func testStats() {
        let s = TrunkSample.state(isPro: false)
        let stats = TrunkText.stats(s)
        XCTAssertEqual(stats.stuck, TrunkSample.stuck.count)
        // 日本・フィンランド・フランス・スペイン・ギリシャ
        XCTAssertEqual(stats.countries, 5)
        XCTAssertEqual(stats.sinceYear, 2019)
        let empty = TrunkText.stats(TrunkSample.state(isPro: false, empty: true))
        XCTAssertEqual(empty, .init(stuck: 0, countries: 0, sinceYear: nil))
    }

    /// サーバーの断りの印を画面の言葉に（知らない印はサーバーの言い分のまま）
    func testRefusalWording() {
        let refused = TrunkService.Refused(message: "今月の作り直しは使い切りました", code: "noRerollsLeft")
        XCTAssertEqual(refused.errorDescription, TrunkText.refusal(code: "noRerollsLeft", fallback: ""))
        XCTAssertEqual(TrunkService.Refused(message: "何か", code: "mystery").errorDescription, "何か")
        XCTAssertEqual(TrunkService.Refused(message: "何か", code: nil).errorDescription, "何か")
    }

    // MARK: 端末の中だけの移り変わり（画面写真の見本・サーバーと同じ決まり）

    func testLocalTransitionsFollowServerRules() {
        let free = TrunkSample.state(isPro: false)
        let first = free.pocket[0].id
        let stuck = TrunkLocal.stick(free, id: first)
        XCTAssertFalse(stuck.pocket.contains { $0.id == first })
        XCTAssertEqual(stuck.stuck.first?.id, first, "貼ったものは新しい順の先頭")
        XCTAssertEqual(TrunkLocal.stick(free, id: "nope"), free)
        XCTAssertEqual(TrunkLocal.remove(free, id: first).pocket.count, free.pocket.count - 1)
        // 作り直しは Pro だけ・回数が残っているときだけ
        XCTAssertNil(TrunkLocal.reroll(free, id: first, seeds: [1, 2, 3]).pendingReroll)
        let pro = TrunkSample.state(isPro: true)
        let rolled = TrunkLocal.reroll(pro, id: first, seeds: [1, 2, 3])
        XCTAssertEqual(rolled.pendingReroll, TrunkPendingReroll(labelId: first, seeds: [1, 2, 3]))
        XCTAssertEqual(rolled.rerollsLeft, pro.rerollsLeft - 1)
        XCTAssertEqual(TrunkLocal.reroll(rolled, id: first, seeds: [4, 5, 6]), rolled, "選びかけがあれば回数を使わない")
        // 候補にない種は選べない・候補か、いまの種なら選べる
        let bogus = TrunkLocal.choose(rolled, id: first, seed: 999)
        XCTAssertEqual(bogus.pocket.first { $0.id == first }?.seed, pro.pocket[0].seed)
        let chosen = TrunkLocal.choose(rolled, id: first, seed: 2)
        XCTAssertEqual(chosen.pocket.first { $0.id == first }?.seed, 2)
        XCTAssertNil(chosen.pendingReroll)
        // 貼ったら選びかけは消える
        XCTAssertNil(TrunkLocal.stick(rolled, id: first).pendingReroll)
        // Pro の型は Pro だけ
        XCTAssertEqual(TrunkLocal.setModel(free, .captain).model, .leather)
        XCTAssertEqual(TrunkLocal.setModel(pro, .captain).effectiveModel, .captain)
        XCTAssertEqual(TrunkLocal.setModel(free, .canvas).model, .canvas)
        XCTAssertFalse(TrunkLocal.setReceive(free, false).receiveLabels)
    }

    // MARK: 届いた画面の待ち

    @MainActor
    func testArrivalsQueue() async {
        let arrivals = TrunkArrivals()
        XCTAssertNil(arrivals.consume())
        arrivals.deliver([], pocketWasFull: false)
        XCTAssertEqual(arrivals.requests, 0, "何も無い投稿では合図しない")
        arrivals.deliver([.init(label: TrunkSample.arrived, photoTitle: "朝")], pocketWasFull: false)
        XCTAssertEqual(arrivals.requests, 1)
        arrivals.deliver([.init(label: TrunkSample.pocket[0], photoTitle: "")], pocketWasFull: true)
        let batch = arrivals.consume()
        XCTAssertEqual(batch?.arrivals.count, 2, "続けて届いた分は1つの束で出す")
        XCTAssertEqual(batch?.first.label.id, TrunkSample.arrived.id)
        XCTAssertEqual(batch?.othersCount, 1)
        XCTAssertNil(arrivals.consume())
        XCTAssertFalse(arrivals.consumeFullNotice(), "ラベルが届いた回は「いっぱい」を言わない")
        arrivals.deliver([], pocketWasFull: true)
        XCTAssertTrue(arrivals.consumeFullNotice())
        XCTAssertFalse(arrivals.consumeFullNotice(), "一言は1回だけ")
    }

    /// 見本は Linux でも読める形（id は道に入れられる・種は 0 以上）
    func testSampleIsValid() {
        for label in TrunkSample.stuck + TrunkSample.pocket + [TrunkSample.arrived] {
            XCTAssertTrue(PathID.isSafe(label.id), label.id)
            XCTAssertGreaterThanOrEqual(label.seed, 0)
            XCTAssertNotNil(label.day)
        }
        XCTAssertEqual(TrunkSample.state(isPro: true).limit, 150)
        XCTAssertEqual(TrunkSample.state(isPro: false).limit, 30)
    }
}
