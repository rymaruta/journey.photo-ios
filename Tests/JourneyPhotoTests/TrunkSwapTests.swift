import XCTest
@testable import JourneyPhoto

/// トランクのラベルをはがす・貼り替える（2026-10-19 の直し・owner「取って付け替えたときに、空洞のところが空洞に
/// なっていない」）。置き場なしのラベルは並びの番号でおまかせの置き場が決まるので、1枚はがすとほかがずれて、
/// はがした所にほかのラベルが入り、別の所が空いていた。
///
/// 直し方（確かめ役の見直しのあと）: はがすときに、ずれるラベルの**おまかせの置き場の番号**（`slot`）を添えて
/// サーバーが同じ1回で覚える。描く元の値（`TrunkPlacement.layout`）で確かめる
final class TrunkSwapTests: XCTestCase {

    private func label(_ id: String, pos: TrunkPos? = nil, slot: Int? = nil) -> TrunkLabel {
        TrunkLabel(id: id, photoId: id, kind: .place, place: .init(name: id, latin: nil, country: nil), seed: 1,
                   at: "2026-01-01T00:00:00Z", pos: pos, slot: slot)
    }

    /// 描いている枠（位置・大きさ・傾き。**大きさも比べる**＝置き場の枠のまま描く）
    private struct Spot: Equatable {
        let x: Double, y: Double, w: Double, h: Double, rot: Double
    }

    private func spots(_ stuck: [TrunkLabel]) -> [String: Spot] {
        var out: [String: Spot] = [:]
        for p in TrunkPlacement.layout(stuck, stage: 0) { out[p.label.id] = Spot(x: p.x, y: p.y, w: p.w, h: p.h, rot: p.rot) }
        return out
    }

    /// 番号を添えたあとの貼ったラベル（サーバーと同じ: 置き場の無いラベルに番号を書き、はがした1枚を除く）
    private func applying(_ slots: [String: Int], to stuck: [TrunkLabel], removing id: String) -> [TrunkLabel] {
        stuck.filter { $0.id != id }.map { l in l.pos == nil ? (slots[l.id].map { l.withSlot($0) } ?? l) : l }
    }

    /// 描いていたラベルは同じ枠のまま・はがした所は空く（`newcomers`: 窓の外の古いラベルは空いた所に出てよい）
    private func assertStayed(_ before: [String: Spot], _ after: [String: Spot], except removed: String,
                              newcomers: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        for (id, spot) in before where id != removed {
            XCTAssertEqual(after[id], spot, "\(id) がずれた・大きさが変わった", file: file, line: line)
        }
        if let hole = before[removed] {
            for (id, s) in after where s == hole && (!newcomers || before[id] != nil) {
                XCTFail("はがした所に \(id) が入った（空洞にならない）", file: file, line: line)
            }
        }
        // 2枚が同じ枠に重ならない
        let frames = after.values.map { "\($0.x)/\($0.y)" }
        XCTAssertEqual(Set(frames).count, frames.count, "2枚が同じ置き場に重なった", file: file, line: line)
    }

    // MARK: 描く元の値

    /// 前の不具合の形: 番号を添えずに真ん中の1枚をはがすと、新しいラベルがはがした所へずれる
    func testPeelingWithoutSlotsShiftsTheNewer() {
        let stuck = ["a", "b", "c", "d"].map { label($0) }
        XCTAssertEqual(spots(stuck.filter { $0.id != "c" })["b"], spots(stuck)["c"], "前提: 並びの番号で置き場が決まる")
    }

    /// 🔴 置き場なし4枚の真ん中をはがす: ずれる2枚にだけ番号を添え、ほかは1点も動かず（大きさもそのまま）、はがした所が空く
    func testPeelingAMiddleLooseLabelLeavesAHole() {
        let stuck = ["a", "b", "c", "d"].map { label($0) }
        let slots = TrunkPlacement.slotsBeforeUnstick(stuck, removing: "c")
        XCTAssertEqual(Set(slots.keys), ["a", "b"])
        let next = applying(slots, to: stuck, removing: "c")
        XCTAssertTrue(next.allSatisfy { $0.pos == nil }, "置き場なしのラベルに置き場を与えた")
        assertStayed(spots(stuck), spots(next), except: "c")
    }

    /// 🔴 いちばん古い1枚をはがす（見本の9枚）: 全部の番号がずれる形。ほかは動かない
    func testPeelingTheOldestOfTheSample() {
        let stuck = TrunkSample.stuck
        let oldest = stuck.last!.id
        let slots = TrunkPlacement.slotsBeforeUnstick(stuck, removing: oldest)
        assertStayed(spots(stuck), spots(applying(slots, to: stuck, removing: oldest)), except: oldest)
    }

    /// 🔴 置き場つきの古い1枚をはがす: 置き場なしの新しいラベルの番号がずれる形（`olderPlaced` が減る）
    func testPeelingAnOlderPlacedLabelKeepsTheLooseOnes() {
        let p = TrunkPos(x: 0.5, y: 0.9, rot: 0)
        for s in [[label("n1"), label("n2"), label("old", pos: p), label("n3")],
                  [label("n1"), label("n2"), label("n3"), label("old", pos: p)]] {
            let slots = TrunkPlacement.slotsBeforeUnstick(s, removing: "old")
            assertStayed(spots(s), spots(applying(slots, to: s, removing: "old")), except: "old")
        }
    }

    /// いちばん新しい1枚・置き場つきの1枚をはがしても、ほかがずれないなら番号を添えない（本文を送らない）
    func testNoSlotsWhenNothingMoves() {
        let stuck = ["a", "b", "c"].map { label($0) }
        XCTAssertTrue(TrunkPlacement.slotsBeforeUnstick(stuck, removing: "a").isEmpty)
        let placed = [label("p", pos: TrunkPos(x: 0.3, y: 0.3, rot: 0))] + stuck
        XCTAssertTrue(TrunkPlacement.slotsBeforeUnstick(placed, removing: "p").isEmpty)
        XCTAssertTrue(TrunkPlacement.slotsBeforeUnstick(stuck, removing: "zz").isEmpty, "貼っていないラベルで番号を送った")
    }

    /// 🔴 置き場なしが 14 枚（窓の外に古い3枚）: 窓の中のどれをはがしても、描いていたラベルは同じ枠のまま。
    /// 窓の外から出てくる古いラベルは**空いた所だけ**に出る（番号つきのラベルの上に重ねない）。描くのは 11 枚まで
    func testPeelingWithFourteenLooseLabels() {
        let stuck = (0..<14).map { label("l\($0)") }
        let before = spots(stuck)
        XCTAssertEqual(before.count, 11)
        for removing in ["l0", "l3", "l5", "l9", "l10"] {
            let slots = TrunkPlacement.slotsBeforeUnstick(stuck, removing: removing)
            let after = spots(applying(slots, to: stuck, removing: removing))
            assertStayed(before, after, except: removing, newcomers: true)
            XCTAssertLessThanOrEqual(after.count, 11, "\(removing): 置き場より多く描いた")
            for (id, s) in after where before[id] == nil {
                XCTAssertEqual(s, before[removing], "\(removing): 窓の外の \(id) が空いた所以外に出た")
            }
        }
    }

    /// 🔴 番号つきの置き場が 11 か所すべて埋まっているところへ貼る: 貼った1枚は必ず描く（2026-10-17 判断
    /// 「貼ったばかりのラベルが見えないのは困る」）。いちばん古い番号つきの1枚が置き場を譲って描かれない
    func testNewLabelIsDrawnWhenEverySlotIsTaken() {
        let slotted = (0..<11).map { label("s\($0)", slot: $0) }
        let stuck = [label("new")] + slotted
        let drawn = spots(stuck)
        XCTAssertNotNil(drawn["new"], "貼ったばかりの1枚が描かれない")
        XCTAssertEqual(drawn.count, 11)
        XCTAssertNil(drawn["s10"], "いちばん古い番号つきの1枚が譲っていない")
        XCTAssertEqual(drawn["new"], spots([label("x", slot: 10)])["x"], "譲ってもらった置き場に描いていない")
        // 新しい2枚なら、古い2枚が譲る
        let two = spots([label("n1"), label("n2")] + slotted)
        XCTAssertNotNil(two["n1"])
        XCTAssertNotNil(two["n2"])
        XCTAssertNil(two["s10"])
        XCTAssertNil(two["s9"])
        // 番号つきより古いラベルには譲らない（新しい 11 枚を出す）
        XCTAssertNil(spots(slotted + [label("old")])["old"])
    }

    /// 🔴 置き場なし 14 枚でいちばん新しい l0 をはがしてから1枚貼る: 新しい1枚が空いた所に入る（窓の外の古いラベルではなく）
    func testFourteenPeelThenStickPutsTheNewLabelInTheHole() {
        let stuck = (0..<14).map { label("l\($0)") }
        let before = spots(stuck)
        let slots = TrunkPlacement.slotsBeforeUnstick(stuck, removing: "l0")
        let peeled = applying(slots, to: stuck, removing: "l0")
        // はがした直後: 空いた所には窓の外のうち、いちばん新しい l11
        let afterPeel = spots(peeled)
        XCTAssertEqual(afterPeel["l11"], before["l0"])
        // 貼る（置き場なし・番号は stickSlot に従う）
        let new = label("new")
        let slot = TrunkPlacement.stickSlot(for: new, stuck: peeled)
        let after = spots([new.withSlot(slot)] + peeled)
        XCTAssertNotNil(after["new"], "貼ったばかりの1枚が描かれない")
        XCTAssertEqual(after["new"], before["l0"], "新しい1枚がはがした所に入らない")
        for (id, s) in before where id != "l0" { XCTAssertEqual(after[id], s, "\(id) がずれた") }
        XCTAssertLessThanOrEqual(after.count, 11)
    }

    /// 🔴 同じ番号が2枚に付いていたら（古い画面・別の端末）: 新しい方を番号の所に、古い方は空いた所へ。重ならない
    func testDuplicateSlotsDoNotOverlap() {
        let stuck = [label("a", slot: 3), label("b"), label("c", slot: 3)]
        let drawn = spots(stuck)
        XCTAssertEqual(drawn["a"], spots([label("x", slot: 3)])["x"], "新しい方が番号の所にいない")
        XCTAssertNotNil(drawn["c"])
        XCTAssertNotEqual(drawn["c"], drawn["a"], "同じ番号の2枚が重なった")
        let frames = drawn.values.map { "\($0.x)/\($0.y)" }
        XCTAssertEqual(Set(frames).count, frames.count)
    }

    /// 番号つきのラベルを続けてはがす（2回目の番号は1回目で書いた番号を土台にする）: ずれない・重ならない
    func testRepeatedPeelsOnSlottedLabels() {
        var stuck = (0..<8).map { label("l\($0)") }
        let first = spots(stuck)
        var removed: [String] = []
        for id in ["l6", "l2", "l4"] {
            let slots = TrunkPlacement.slotsBeforeUnstick(stuck, removing: id)
            stuck = applying(slots, to: stuck, removing: id)
            removed.append(id)
            let now = spots(stuck)
            for (k, s) in first where !removed.contains(k) { XCTAssertEqual(now[k], s, "\(id) をはがしたら \(k) がずれた") }
        }
    }

    /// 画面の上だけで動かしている1枚（保存待ち）は、その置き場で描いているので番号を添えない
    func testOverriddenLabelGetsNoSlot() {
        let stuck = ["a", "b", "c"].map { label($0) }
        let slots = TrunkPlacement.slotsBeforeUnstick(stuck, removing: "c", overrides: ["a": TrunkPos(x: 0.1, y: 0.1, rot: 0)])
        XCTAssertEqual(Array(slots.keys), ["b"])
    }

    /// 番号の読み方: 置き場があれば番号は捨てる・範囲の外は読まない・番号の無いトランクは前の版と同じ並び
    func testSlotDecodingAndLegacyLayout() throws {
        let json = #"[{"id":"a","seed":1,"place":{"name":"x"},"slot":4},{"id":"b","seed":1,"place":{"name":"x"},"slot":4,"pos":{"x":0.5,"y":0.5,"rot":0}},{"id":"c","seed":1,"place":{"name":"x"},"slot":11},{"id":"d","seed":1,"place":{"name":"x"},"slot":"z"}]"#
        let labels = try JSONDecoder().decode([TrunkLabel].self, from: Data(json.utf8))
        XCTAssertEqual(labels.map(\.slot), [4, nil, nil, nil])
        XCTAssertNil(label("x", slot: 3).withPos(TrunkPos(x: 0.5, y: 0.5, rot: 0)).slot, "置き場を与えても番号が残った")
        let legacy = (0..<14).map { label("l\($0)") }
        XCTAssertEqual(TrunkPlacement.layout(legacy, stage: 0.6), TrunkSlots.place(legacy, stage: 0.6))
    }

    // MARK: 置き場なしで貼る

    /// 🔴 手で貼ったラベルが乗っている置き場に、置き場なしで貼らない（重ねて隠さない）。空いた所の番号を添える
    func testLooseStickDoesNotCoverAHandPlacedLabel() {
        let loose = [label("o1"), label("o2")]
        let arranged = TrunkPlacement.autoArrange(pocket: (0..<9).map { label("p\($0)") }, stuck: loose)
        let stuck = arranged.reversed().map { label($0.id, pos: $0.pos) } + loose
        let new = label("new")
        // 全部埋まっていれば番号なし（今までどおり）
        XCTAssertNil(TrunkPlacement.stickSlot(for: new, stuck: stuck))
        // 1か所（p0 の所）空いていれば、そこの番号
        let withHole = stuck.filter { $0.id != "p0" }
        let slot = TrunkPlacement.stickSlot(for: new, stuck: withHole)
        XCTAssertNotNil(slot)
        let s = spots([new.withSlot(slot)] + withHole)["new"]!
        let p0 = arranged.first { $0.id == "p0" }!.pos
        XCTAssertEqual(s.x + s.w / 2, TrunkPlacement.point(p0).x, accuracy: 0.5)
        XCTAssertEqual(s.y + s.h / 2, TrunkPlacement.point(p0).y, accuracy: 0.5)
        // 置き場のないトランクは前の版と同じ（番号なし）
        XCTAssertNil(TrunkPlacement.stickSlot(for: new, stuck: loose))
    }

    // MARK: 見本で通しで（はがす → 手持ちから貼り直す → 「ひとつ戻す」の形で戻す）

    /// 🔴 見本の9枚の真ん中をはがす → ほかは動かず、はがした所が空く → 手持ちの「貼る」で貼り直すと元の所（元の枠）に戻る
    @MainActor
    func testPeelAndRestickInThePreview() async {
        let model = TrunkViewModel(preview: .sample, previewPro: true)
        await model.load(offline: false)
        let stuck = model.state!.stuck
        let target = stuck[4].id
        let before = spots(stuck)
        do { let ok = await model.unstick(target); XCTAssertTrue(ok) }
        XCTAssertEqual(model.state?.pocket.first?.id, target)
        XCTAssertTrue(model.state!.stuck.allSatisfy { $0.pos == nil }, "置き場なしのラベルに置き場を与えた")
        assertStayed(before, spots(model.state!.stuck), except: target)
        do { let ok = await model.stick(target); XCTAssertTrue(ok) }
        XCTAssertEqual(spots(model.state!.stuck), before, "貼り直すと元の並びに戻らない")
        XCTAssertNil(model.state!.stuck.first { $0.id == target }?.pos, "置き場なしのラベルを置き場つきで貼り直した")
    }

    /// 🔴 「ひとつ戻す」の形: 置き場なしだったラベルは、置き場なしのまま描いていた番号で戻る
    @MainActor
    func testUndoPeelKeepsALooseLabelLoose() async {
        let model = TrunkViewModel(preview: .sample, previewPro: true)
        await model.load(offline: false)
        let before = TrunkPlacement.layout(model.state!.stuck, stage: 0)
        let target = model.state!.stuck[2].id
        let slot = TrunkPlacement.slotIndex(before.first { $0.id == target }!)
        XCTAssertNotNil(slot)
        do { let ok = await model.unstick(target); XCTAssertTrue(ok) }
        do { let ok = await model.stick(target, slot: slot!); XCTAssertTrue(ok) }
        let back = model.state!.stuck.first { $0.id == target }!
        XCTAssertNil(back.pos)
        XCTAssertEqual(back.slot, slot)
        XCTAssertEqual(spots(model.state!.stuck), spots(before.map(\.label).reversed()), "戻したのに並びが変わった")
    }

    /// 🔴 続けて貼り替える（2枚はがす → 2枚貼る）: 重なりも空きの取り違えも起きない。元の9か所をそのまま使う
    @MainActor
    func testRepeatedSwapsKeepEveryLabelApart() async {
        let model = TrunkViewModel(preview: .sample, previewPro: true)
        await model.load(offline: false)
        let first = spots(model.state!.stuck)
        let a = model.state!.stuck[2].id, b = model.state!.stuck[6].id
        _ = await model.unstick(a)
        _ = await model.unstick(b)
        _ = await model.stick(b)
        _ = await model.stick(a)
        let now = spots(model.state!.stuck)
        XCTAssertEqual(Set(now.keys), Set(first.keys))
        let frames = now.values.map { "\($0.x)/\($0.y)" }
        XCTAssertEqual(Set(frames).count, frames.count, "2枚が同じ所に重なった")
        XCTAssertEqual(Set(now.values.map { "\($0.x)/\($0.y)/\($0.w)" }), Set(first.values.map { "\($0.x)/\($0.y)/\($0.w)" }),
                       "空いているはずの所が埋まらず、別の所・別の大きさで貼った")
    }

    // MARK: 描く側の見分け方（id）

    /// 🔴 描くラベルはラベルの id で見分ける。はがした直後・貼り替えた直後も、同じ id は同じラベル・同じ所
    @MainActor
    func testDrawnLabelsAreIdentifiedByLabelId() async {
        let model = TrunkViewModel(preview: .sample, previewPro: true)
        await model.load(offline: false)
        let target = model.state!.stuck[4].id
        let before = TrunkPlacement.layout(model.state!.stuck, stage: 0)
        _ = await model.unstick(target)
        let peeled = TrunkPlacement.layout(model.state!.stuck, stage: 0)
        _ = await model.stick(target)
        let restuck = TrunkPlacement.layout(model.state!.stuck, stage: 0)
        for drawn in [before, peeled, restuck] {
            XCTAssertEqual(Set(drawn.map(\.id)).count, drawn.count, "描く識別子が重なった")
            XCTAssertTrue(drawn.allSatisfy { $0.id == $0.label.id }, "識別子がラベルの id でない")
        }
        // 前提: 何番目かで見分けると、はがした直後に同じ番目へ別のラベルが入る
        XCTAssertTrue(zip(before, peeled).contains { $0.label.id != $1.label.id }, "前提: はがすと番目とラベルの組が変わる")
        XCTAssertNil(peeled.first { $0.id == target }, "はがした1枚が描かれている")
        let old = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        for p in peeled {
            guard let o = old[p.id] else { return XCTFail("\(p.id) は前に無かった") }
            XCTAssertEqual(p.label.seed, o.label.seed)
            XCTAssertEqual(Spot(x: p.x, y: p.y, w: p.w, h: p.h, rot: p.rot), Spot(x: o.x, y: o.y, w: o.w, h: o.h, rot: o.rot))
        }
        XCTAssertNotNil(restuck.first { $0.id == target }, "貼り直した1枚が描かれない")
    }

    /// 🔴 並びに同じ id が重なっても（応答の重なり・待っている1枚）、描くのは1枚（新しい方）
    func testDuplicateIdsAreDrawnOnce() {
        let newer = label("a", pos: TrunkPos(x: 0.2, y: 0.2, rot: 0))
        let drawn = TrunkPlacement.layout([newer, label("b"), label("a")], stage: 0)
        XCTAssertEqual(drawn.map(\.id).sorted(), ["a", "b"])
        XCTAssertEqual(drawn.first { $0.id == "a" }?.label.pos, newer.pos, "古い方の a を描いた")
    }
}
