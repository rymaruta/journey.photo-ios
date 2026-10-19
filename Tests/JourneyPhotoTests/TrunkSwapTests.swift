import XCTest
@testable import JourneyPhoto

/// トランクのラベルをはがす・貼り替える（2026-10-19 の直し・owner「取って付け替えたときに、空洞のところが空洞に
/// なっていない」）。置き場なしのラベルは並びの番号でおまかせの置き場が決まるので、1枚はがすとほかがずれて、
/// はがした所にほかのラベルが入り、別の所が空いていた。描く元の値（`TrunkPlacement.layout`）で確かめる
final class TrunkSwapTests: XCTestCase {

    private func label(_ id: String, pos: TrunkPos? = nil) -> TrunkLabel {
        TrunkLabel(id: id, photoId: id, kind: .place, place: .init(name: id, latin: nil, country: nil), seed: 1,
                   at: "2026-01-01T00:00:00Z", pos: pos)
    }

    private struct Spot: Equatable {
        let cx: Double, cy: Double, rot: Double
    }

    /// 描いている所（真ん中と傾き。置き場を与えたラベルは大きさが形の比に変わるので、真ん中で比べる）
    private func spots(_ stuck: [TrunkLabel]) -> [String: Spot] {
        var out: [String: Spot] = [:]
        for p in TrunkPlacement.layout(stuck, stage: 0) {
            out[p.label.id] = Spot(cx: ((p.x + p.w / 2) * 10).rounded() / 10, cy: ((p.y + p.h / 2) * 10).rounded() / 10,
                                   rot: p.rot)
        }
        return out
    }

    /// 置き場を与えたあとの貼ったラベル（サーバーと同じ: 置き場を書き、はがした1枚を除く）
    private func applying(_ pins: [(id: String, pos: TrunkPos)], to stuck: [TrunkLabel], removing id: String) -> [TrunkLabel] {
        let byId = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0.pos) })
        return stuck.filter { $0.id != id }.map { l in byId[l.id].map { l.withPos($0) } ?? l }
    }

    /// - Parameter newcomers: はがした所に入ってよい（前は描いていなかった）ラベルがあるか（窓の外の古いラベル）
    private func assertStayed(_ before: [String: Spot], _ after: [String: Spot], except removed: String,
                              newcomers: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        for (id, spot) in before where id != removed {
            guard let now = after[id] else { XCTFail("\(id) が描かれなくなった", file: file, line: line); continue }
            XCTAssertEqual(now.cx, spot.cx, accuracy: 0.5, "\(id) が横にずれた", file: file, line: line)
            XCTAssertEqual(now.cy, spot.cy, accuracy: 0.5, "\(id) が縦にずれた", file: file, line: line)
            XCTAssertEqual(now.rot, spot.rot, accuracy: 0.05, "\(id) の傾きが変わった", file: file, line: line)
        }
        // はがした所は空く（ほかのラベルの真ん中が来ない）
        if let hole = before[removed] {
            let filled = after.filter { abs($0.value.cx - hole.cx) < 6 && abs($0.value.cy - hole.cy) < 6 }
            for id in filled.keys where !newcomers || before[id] != nil {
                XCTFail("はがした所に \(id) が入った（空洞にならない）", file: file, line: line)
            }
        }
    }

    // MARK: 描く元の値

    /// 前の不具合の形: 置き場を与えずに真ん中の1枚をはがすと、新しいラベルがはがした所へずれる
    func testPeelingWithoutPinsShiftsTheNewer() {
        let stuck = ["a", "b", "c", "d"].map { label($0) }
        let before = spots(stuck)
        let after = spots(stuck.filter { $0.id != "c" })
        XCTAssertEqual(after["b"], before["c"], "前提: 置き場なしのラベルは並びの番号で置き場が決まる")
    }

    /// 🔴 置き場なし4枚の真ん中をはがす: ほかは1点も動かず、はがした所が空く
    func testPeelingAMiddleLooseLabelLeavesAHole() {
        let stuck = ["a", "b", "c", "d"].map { label($0) }
        let pins = TrunkPlacement.pinsBeforeUnstick(stuck, removing: "c")
        XCTAssertEqual(Set(pins.map(\.id)), ["a", "b"], "ずれる2枚（はがした1枚より新しい）にだけ置き場を与える")
        assertStayed(spots(stuck), spots(applying(pins, to: stuck, removing: "c")), except: "c")
    }

    /// 🔴 いちばん古い1枚をはがす（見本の9枚）: 全部の番号がずれる形。ほかは動かない
    func testPeelingTheOldestOfTheSample() {
        let stuck = TrunkSample.stuck
        let oldest = stuck.last!.id
        let pins = TrunkPlacement.pinsBeforeUnstick(stuck, removing: oldest)
        assertStayed(spots(stuck), spots(applying(pins, to: stuck, removing: oldest)), except: oldest)
    }

    /// 🔴 置き場つきの古い1枚をはがす: 置き場なしの新しいラベルの番号がずれる形（`olderPlaced` が減る）
    func testPeelingAnOlderPlacedLabelKeepsTheLooseOnes() {
        // 置き場つきが間にある並びと、いちばん古い並び（窓のいちばん古い n3 より古い）
        let stuck = [label("n1"), label("n2"), label("old", pos: TrunkPos(x: 0.5, y: 0.9, rot: 0)), label("n3")]
        let stuck2 = [label("n1"), label("n2"), label("n3"), label("old", pos: TrunkPos(x: 0.5, y: 0.9, rot: 0))]
        for s in [stuck, stuck2] {
            let pins = TrunkPlacement.pinsBeforeUnstick(s, removing: "old")
            assertStayed(spots(s), spots(applying(pins, to: s, removing: "old")), except: "old")
        }
    }

    /// いちばん新しい1枚・置き場つきの1枚をはがしても、ほかがずれないなら何も送らない（書き込みを増やさない）
    func testNoPinsWhenNothingMoves() {
        let stuck = ["a", "b", "c"].map { label($0) }
        XCTAssertTrue(TrunkPlacement.pinsBeforeUnstick(stuck, removing: "a").isEmpty)
        let placed = [label("p", pos: TrunkPos(x: 0.3, y: 0.3, rot: 0))] + stuck
        XCTAssertTrue(TrunkPlacement.pinsBeforeUnstick(placed, removing: "p").isEmpty)
        XCTAssertTrue(TrunkPlacement.pinsBeforeUnstick(stuck, removing: "zz").isEmpty, "貼っていないラベルで置き場を送った")
    }

    /// 置き場なしが 11 枚を越える（窓の外に古いラベルがある）: 窓の中の1枚をはがしても、描いていたラベルは動かない。
    /// 前は窓の外で描いていなかった古いラベルが出てくることはある（置き場を与えたラベルが窓の席を空けるため）が、
    /// **出てきても、描いていたラベルの下**（古いものが下）に描く。空いた所には出てよい（前の版の「新しい 11 枚」と同じ）
    func testPeelingWithMoreThanElevenLooseLabels() {
        let stuck = (0..<14).map { label("l\($0)") }
        let before = spots(stuck)
        for removing in ["l0", "l5", "l10"] {
            let pins = TrunkPlacement.pinsBeforeUnstick(stuck, removing: removing)
            let next = applying(pins, to: stuck, removing: removing)
            assertStayed(before, spots(next), except: removing, newcomers: true)
            let order = TrunkPlacement.layout(next, stage: 0).map(\.label.id)
            for newcomer in order where before[newcomer] == nil {
                for old in before.keys where old != removing {
                    XCTAssertLessThan(order.firstIndex(of: newcomer)!, order.firstIndex(of: old)!,
                                      "窓の外から出てきた \(newcomer) が \(old) の上に描かれた")
                }
            }
        }
    }

    /// 画面の上だけで動かしている1枚（保存待ち）は、その置き場で描いているので置き場を与えない
    func testOverriddenLabelIsNotPinned() {
        let stuck = ["a", "b", "c"].map { label($0) }
        let pins = TrunkPlacement.pinsBeforeUnstick(stuck, removing: "c", overrides: ["a": TrunkPos(x: 0.1, y: 0.1, rot: 0)])
        XCTAssertEqual(pins.map(\.id), ["b"])
    }

    // MARK: 置き場なしで貼る

    /// 🔴 手で貼ったラベルが乗っている置き場に、置き場なしで貼らない（重ねて隠さない）
    func testLooseStickDoesNotCoverAHandPlacedLabel() {
        let loose = [label("o1"), label("o2")]
        // おまかせで並べた（空いている置き場に置き場つきで貼った）9 枚
        let arranged = TrunkPlacement.autoArrange(pocket: (0..<9).map { label("p\($0)") }, stuck: loose)
        let stuck = arranged.reversed().map { label($0.id, pos: $0.pos) } + loose
        let new = label("new")
        // 前の不具合の形: 置き場なしで貼ると、手で貼った1枚の上に重なる
        let naive = spots([new] + stuck)
        XCTAssertTrue(stuck.contains { $0.pos != nil && spots(stuck)[$0.id].map { abs($0.cx - naive["new"]!.cx) < 6 } == true },
                      "前提: 置き場なしの番号の置き場は、手で貼ったラベルが使っている")
        // 全部埋まっていれば置き場なしのまま（今までどおり）
        XCTAssertNil(TrunkPlacement.stickPos(for: new, stuck: stuck))
        // 1か所空いていれば、そこに貼る
        let withHole = stuck.filter { $0.id != "p0" }
        let pos = TrunkPlacement.stickPos(for: new, stuck: withHole)
        XCTAssertEqual(pos, TrunkPlacement.autoArrange(pocket: [new], stuck: withHole).first?.pos)
        XCTAssertNotNil(pos)
        // 置き場のないトランクは前の版と同じ（置き場なしで貼る）
        XCTAssertNil(TrunkPlacement.stickPos(for: new, stuck: loose))
    }

    // MARK: 見本で通しで（はがす → 手持ちから貼り直す）

    /// 🔴 見本の9枚の真ん中をはがす → ほかは動かず、はがした所が空く → 手持ちの「貼る」で貼り直すと元の所に戻る
    @MainActor
    func testPeelAndRestickInThePreview() async {
        let model = TrunkViewModel(preview: .sample, previewPro: true)
        await model.load(offline: false)
        let stuck = model.state!.stuck
        let target = stuck[4].id
        let before = spots(stuck)
        let ok = await model.unstick(target)
        XCTAssertTrue(ok)
        XCTAssertEqual(model.state?.pocket.first?.id, target)
        assertStayed(before, spots(model.state!.stuck), except: target)
        // 空いた所は、おまかせで並べるの空きとして見える
        let hole = before[target]!
        let free = TrunkPlacement.autoArrange(pocket: [label("x")], stuck: model.state!.stuck).first!.pos
        let c = TrunkPlacement.point(free)
        XCTAssertEqual(c.x, hole.cx, accuracy: 0.5, "空いた所が空きとして扱われない")
        XCTAssertEqual(c.y, hole.cy, accuracy: 0.5)
        // 手持ちから貼り直す（置き場なしの「貼る」）: 手で置き場を与えた1枚の上に重ねず、空いた所に戻る
        let restuck = await model.stick(target)
        XCTAssertTrue(restuck)
        let again = spots(model.state!.stuck)
        XCTAssertEqual(again[target]?.cx ?? -1, hole.cx, accuracy: 0.5, "貼り直した1枚が元の所に戻らない")
        XCTAssertEqual(again[target]?.cy ?? -1, hole.cy, accuracy: 0.5)
        for (id, spot) in before where id != target {
            XCTAssertEqual(again[id]?.cx ?? -1, spot.cx, accuracy: 0.5, "\(id) がずれた")
            XCTAssertEqual(again[id]?.cy ?? -1, spot.cy, accuracy: 0.5, "\(id) がずれた")
        }
    }

    /// 🔴 続けて貼り替える（2枚はがす → 2枚貼る）: 重なりも空きの取り違えも起きない
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
        let centers = now.values.map { "\(Int($0.cx.rounded()))/\(Int($0.cy.rounded()))" }
        XCTAssertEqual(Set(centers).count, centers.count, "2枚が同じ所に重なった")
        // 元の9か所をそのまま使う（並びは入れ替わってもよい）
        let was = Set(first.values.map { "\(Int($0.cx.rounded()))/\(Int($0.cy.rounded()))" })
        XCTAssertEqual(Set(centers), was, "空いているはずの所が埋まらず、別の所に貼った")
    }
}
