import XCTest
@testable import JourneyPhoto

/// 自分の手で貼る（2026-10-17 次の版）: 置き場の範囲・並べ方・おまかせ・画面の座標・端末の中の移り変わり
final class TrunkStickTests: XCTestCase {

    private func label(_ id: String, seed: Int = 1, pos: TrunkPos? = nil) -> TrunkLabel {
        TrunkLabel(id: id, photoId: id, kind: .place, place: .init(name: id, latin: nil, country: nil), seed: seed,
                   at: "2026-01-01T00:00:00Z", pos: pos)
    }

    // MARK: 置き場の範囲

    func testClampKeepsTheServerRange() {
        XCTAssertEqual(TrunkPlacement.clamp(TrunkPos(x: -0.2, y: 1.7, rot: 44)), TrunkPos(x: 0, y: 1, rot: 30))
        XCTAssertEqual(TrunkPlacement.clamp(TrunkPos(x: 0.12345, y: 0.98765, rot: -12.34)), TrunkPos(x: 0.123, y: 0.988, rot: -12.3),
                       "サーバーの細かさ（小数3桁・1桁）に丸めていない")
        XCTAssertEqual(TrunkPlacement.clamp(TrunkPos(x: .nan, y: .infinity, rot: .nan)), TrunkPos(x: 0.5, y: 0.5, rot: 0))
        XCTAssertEqual(TrunkPlacement.rotated(TrunkPos(x: 0.5, y: 0.5, rot: 28), by: 8).rot, 30, "30° で止まらない")
        XCTAssertEqual(TrunkPlacement.rotated(TrunkPos(x: 0.5, y: 0.5, rot: -26), by: -8).rot, -30)
    }

    func testPointRoundTrip() {
        let p = TrunkPlacement.pos(x: 90, y: 134, rot: -6)
        XCTAssertEqual(p, TrunkPos(x: 0.25, y: 0.5, rot: -6))
        let back = TrunkPlacement.point(p)
        XCTAssertEqual(back.x, 90, accuracy: 0.001)
        XCTAssertEqual(back.y, 134, accuracy: 0.001)
    }

    func testDropArea() {
        // モックの `over`（360×300 の絵で ox 10〜350・oy 40〜290）を胴の座標に
        XCTAssertTrue(TrunkPlacement.canDrop(x: 180, y: 134))
        XCTAssertFalse(TrunkPlacement.canDrop(x: 9, y: 134))
        XCTAssertFalse(TrunkPlacement.canDrop(x: 351, y: 134))
        XCTAssertFalse(TrunkPlacement.canDrop(x: 180, y: 7), "持ち手の上で離して貼れた")
        XCTAssertFalse(TrunkPlacement.canDrop(x: 180, y: 259))
    }

    // MARK: 並べ方

    func testLayoutUsesPositionsAndSlots() {
        let placed = label("a", pos: TrunkPos(x: 0.5, y: 0.5, rot: 12))
        let loose1 = label("b"), loose2 = label("c")
        // 新しい順: a（置き場つき）・b・c
        let out = TrunkPlacement.layout([placed, loose1, loose2], stage: 0)
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out.map(\.label.id), ["c", "b", "a"], "古いものが下になっていない")
        let a = out.last!
        let size = TrunkPlacement.size(placed)
        XCTAssertEqual(a.x + a.w / 2, 180, accuracy: 0.001, "置き場の真ん中に置いていない")
        XCTAssertEqual(a.y + a.h / 2, 134, accuracy: 0.001)
        XCTAssertEqual(a.w, size.w)
        XCTAssertEqual(a.rot, 12)
        // 置き場なしは前の版と同じおまかせの置き場（古いものから order の順）
        let old = TrunkSlots.place([loose1, loose2], stage: 0)
        XCTAssertEqual(out[0].x, old[0].x)
        XCTAssertEqual(out[1].x, old[1].x)
    }

    func testLayoutWithoutPositionsMatchesTheFirstVersion() {
        let labels = (0..<14).map { label("l\($0)", seed: $0) }
        let mine = TrunkPlacement.layout(labels, stage: 0.6)
        let first = TrunkSlots.place(labels, stage: 0.6)
        XCTAssertEqual(mine, first, "置き場の無いトランクの見た目が前の版と変わった")
    }

    func testOverridesAndCap() {
        let a = label("a", pos: TrunkPos(x: 0.1, y: 0.1, rot: 0))
        let moved = TrunkPlacement.layout([a], stage: 0, overrides: ["a": TrunkPos(x: 0.9, y: 0.9, rot: -20)])
        XCTAssertEqual(moved[0].x + moved[0].w / 2, 324, accuracy: 0.01, "画面の上で動かしている置き場が出ない")
        XCTAssertEqual(moved[0].rot, -20)
        let many = (0..<80).map { label("p\($0)", pos: TrunkPos(x: 0.5, y: 0.5, rot: 0)) }
        XCTAssertEqual(TrunkPlacement.layout(many, stage: 0).count, TrunkPlacement.maxPlaced)
        XCTAssertTrue(TrunkPlacement.layout(many, stage: 0).contains { $0.label.id == "p0" }, "新しいものを落とした")
    }

    func testHitPicksTheTopLabel() {
        let under = label("under", pos: TrunkPos(x: 0.5, y: 0.5, rot: 0))
        let over = label("over", pos: TrunkPos(x: 0.52, y: 0.5, rot: 0))
        let placed = TrunkPlacement.layout([over, under], stage: 0)
        XCTAssertEqual(TrunkPlacement.hit(placed, x: 185, y: 134)?.id, "over")
        XCTAssertNil(TrunkPlacement.hit(placed, x: 10, y: 10))
    }

    // MARK: おまかせで並べる

    func testAutoArrangeFillsOnlyFreeSlots() {
        let pocket = (0..<15).map { label("p\($0)") }
        let empty = TrunkPlacement.autoArrange(pocket: pocket, stuck: [])
        XCTAssertEqual(empty.count, TrunkSlots.capacity, "空のトランクに 11 か所より多く貼った")
        XCTAssertEqual(empty.map(\.id), pocket.prefix(11).map(\.id), "手持ちの新しいものから順でない")
        let firstSlot = TrunkSlots.slots[TrunkSlots.order[0]]
        XCTAssertEqual(empty[0].pos, TrunkPlacement.pos(x: firstSlot.x + firstSlot.w / 2, y: firstSlot.y + firstSlot.h / 2,
                                                       rot: firstSlot.rot))
        // 置き場なしの 4 枚が 4 か所を使っている → 残り 7
        let loose = (0..<4).map { label("s\($0)") }
        XCTAssertEqual(TrunkPlacement.autoArrange(pocket: pocket, stuck: loose).count, 7)
        // 全部埋まっていれば空
        let full = (0..<11).map { label("f\($0)") }
        XCTAssertTrue(TrunkPlacement.autoArrange(pocket: pocket, stuck: full).isEmpty)
        // 置き場つきのラベルが置き場の上にあれば、そこは使わない
        let onSlot = label("x", pos: empty[0].pos)
        XCTAssertFalse(TrunkPlacement.autoArrange(pocket: pocket, stuck: [onSlot]).contains { $0.pos == empty[0].pos })
        XCTAssertTrue(TrunkPlacement.autoArrange(pocket: [], stuck: []).isEmpty)
    }

    // MARK: 画面の座標

    func testStickLayoutConvertsPoints() {
        let l = TrunkStickLayout(width: 390, top: 84)
        XCTAssertEqual(l.scale, 1)
        XCTAssertEqual(l.originX, 15)
        let screen = l.screenPoint(bodyX: 100, bodyY: 50)
        let body = l.bodyPoint(screenX: screen.x, screenY: screen.y, lifted: false)
        XCTAssertEqual(body.x, 100, accuracy: 0.001)
        XCTAssertEqual(body.y, 50, accuracy: 0.001)
        // 持ち上げたラベルは指の 18 上に出ている → 離した点は指より 18 上
        let lifted = l.bodyPoint(screenX: screen.x, screenY: screen.y, lifted: true)
        XCTAssertEqual(lifted.y, 50 - 18, accuracy: 0.001)
        let small = TrunkStickLayout(width: 320, top: 84)
        XCTAssertEqual(small.scale, (320 - 30) / 360, accuracy: 0.0001, "狭い画面で縮めていない")
        XCTAssertEqual(TrunkStickLayout(width: 390, top: 84, maxHeight: 150).scale, 0.5, "縮めすぎ（下限 0.5）")
    }

    // MARK: よれ

    func testWrinkleIsDeterministic() {
        XCTAssertEqual(TrunkPlacement.wrinkle(moves: 0), 0)
        XCTAssertEqual(TrunkPlacement.wrinkle(moves: 5), 1)
        XCTAssertTrue(TrunkPlacement.creases(seed: 7, wrinkle: 0).isEmpty)
        let a = TrunkPlacement.creases(seed: 41_207, wrinkle: 1)
        XCTAssertEqual(a.count, 3)
        XCTAssertEqual(a.map(\.x0), TrunkPlacement.creases(seed: 41_207, wrinkle: 1).map(\.x0), "同じ種で線が変わる")
        XCTAssertNotEqual(a.map(\.x0), TrunkPlacement.creases(seed: 3, wrinkle: 1).map(\.x0))
        XCTAssertEqual(TrunkPlacement.creases(seed: 1, wrinkle: 0.34).count, 1)
        XCTAssertTrue(a.allSatisfy { (0...1).contains($0.x0) && (0...1).contains($0.x1) })
    }

    func testWrinkleStore() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "trunk.wrinkles.test"))
        defaults.removePersistentDomain(forName: "trunk.wrinkles.test")
        let store = TrunkWrinkles(userId: "u1", defaults: defaults)
        store.noteMoved("a")
        store.noteMoved("a")
        XCTAssertEqual(store.moves["a"], 2)
        XCTAssertEqual(store.strengths["a"] ?? 0, 2.0 / 3, accuracy: 0.001)
        XCTAssertTrue(TrunkWrinkles(userId: "u2", defaults: defaults).moves.isEmpty, "別の人によれが移った")
        TrunkWrinkles(userId: nil, defaults: defaults).noteMoved("b")
        XCTAssertNil(store.moves["b"])
    }

    // MARK: 端末の中の移り変わり（見本）

    func testLocalStickPlaceUnstick() {
        let s = TrunkSample.state(isPro: false)
        let id = s.pocket[0].id
        let stuck = TrunkLocal.stick(s, id: id, pos: TrunkPos(x: 0.4, y: 0.6, rot: -6))
        XCTAssertEqual(stuck.stuck.first?.id, id)
        XCTAssertEqual(stuck.stuck.first?.pos, TrunkPos(x: 0.4, y: 0.6, rot: -6))
        XCTAssertFalse(stuck.pocket.contains { $0.id == id })
        let placed = TrunkLocal.place(stuck, id: id, pos: TrunkPos(x: 0.1, y: 0.2, rot: 50))
        XCTAssertEqual(placed.stuck.first?.pos, TrunkPos(x: 0.1, y: 0.2, rot: 30))
        let peeled = TrunkLocal.unstick(placed, id: id)
        XCTAssertEqual(peeled.pocket.first?.id, id, "はがしたラベルが手持ちのいちばん上に戻らない")
        XCTAssertNil(peeled.pocket.first?.pos, "はがしたのに置き場が残った")
        XCTAssertEqual(peeled.coins, s.coins, "貼るだけで硬貨が変わった")
        // 手持ちがいっぱいならはがさない（サーバーは 409 full）
        let full = TrunkState(model: .leather, pocket: (0..<30).map { label("q\($0)") }, stuck: [label("z")], limit: 30,
                              isPro: false, rerollsLeft: 0, posts: 0, receiveLabels: true)
        XCTAssertEqual(TrunkLocal.unstick(full, id: "z"), full)
    }

    func testRefusalWordingForPeelingWhenFull() {
        XCTAssertTrue(TrunkText.unstickFull.hasPrefix("手持ちがいっぱいのため、はがせません"))
        XCTAssertFalse(TrunkText.unstickFull.contains("捨て"))
        XCTAssertEqual(TrunkText.refusal(code: "badPlace", fallback: "x"), "その場所には貼れませんでした。トランクの上で離してください。")
    }

    @MainActor
    func testPreviewAutoArrangeRecordsIds() async {
        let model = TrunkViewModel(preview: .sample, previewPro: false)
        await model.load(offline: false)
        let before = model.state!
        let done = await model.autoArrange()
        let expected = TrunkPlacement.autoArrange(pocket: before.pocket, stuck: before.stuck).map(\.id)
        XCTAssertEqual(done, expected)
        XCTAssertEqual(model.state?.pocket.count, before.pocket.count - done.count)
        let again = await model.autoArrange()
        XCTAssertTrue(again.isEmpty || model.state?.pocket.isEmpty == true)
    }
}
