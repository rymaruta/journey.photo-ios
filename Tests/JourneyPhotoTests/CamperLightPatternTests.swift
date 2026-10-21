import XCTest
@testable import JourneyPhoto

/// 灯りの型: 用途ごとに減衰が違い、尾灯は空間の光を持たない（2026-10-20）
final class CamperLightPatternTests: XCTestCase {

    /// 型の一覧と、天井・入口・ランタンは急減衰・部屋と焚き火はなだらか
    func testPatternsSplitAttenuation() {
        let sharp = CamperLightPattern.ceiling.attenuation(range: 100, unit: 1)
        XCTAssertEqual(sharp.start, 0)
        XCTAssertEqual(sharp.falloff, 2, accuracy: 0.01)
        let porch = CamperLightPattern.porch.attenuation(range: 100, unit: 1)
        XCTAssertEqual(porch.start, 0)
        XCTAssertEqual(porch.falloff, 2, accuracy: 0.01)
        let room = CamperLightPattern.roomLamp.attenuation(range: 100, unit: 1)
        XCTAssertGreaterThan(room.start, 0)
        XCTAssertLessThan(room.falloff, 2)
        let hearth = CamperLightPattern.hearth.attenuation(range: 100, unit: 1)
        XCTAssertGreaterThan(hearth.start, 0)
        XCTAssertLessThan(hearth.falloff, 2)
        XCTAssertTrue(CamperLightPattern.hearth.flickers)
        XCTAssertFalse(CamperLightPattern.ceiling.flickers)
    }

    /// 夜の組み立て: 各空間灯に正しい型が付き、尾灯の omni は無い
    func testNightBlueprintUsesPatternsAndNoTaillightOmni() {
        var load = CamperLoadout.standard
        load.picks[CamperCategory.outdoorLight.rawValue] = "brass_lantern"
        let lights = CamperBuilder.build(CamperConfig(stage: .camper, mood: .night, loadout: load)).lights
        XCTAssertEqual(lights.first { $0.name == "interior.rear" }?.pattern, .ceiling)
        // 停めた車の前照灯は点けない（2026-10-19 claude/camper-lamps）。入口の灯りは porch
        XCTAssertNil(lights.first { $0.name == "headlight" })
        XCTAssertEqual(lights.first { $0.name == "porch" }?.pattern, .porch)
        XCTAssertFalse(CamperLightPattern.porch.flickers)
        XCTAssertEqual(lights.first { $0.name == "campfire" }?.pattern, .hearth)
        XCTAssertEqual(lights.first { $0.name == "lantern" }?.pattern, .lantern)
        XCTAssertNil(lights.first { $0.name == "taillight" }, "尾灯は marker（面＋溜まり）で、空間の光を置かない")
        // 尾灯は夜も消えている（面も光らせない・足元の赤い溜まりも無い）
        XCTAssertNil(CamperBuilder.build(CamperConfig(stage: .camper, mood: .night)).nodes.first { $0.name == "glow.tail" })
    }

    /// 部屋の家具灯は roomLamp
    func testRoomLampsUseRoomPattern() {
        let layout = CamperRoomLayout.make(.car, stage: .camper)
        let doc = CamperRoomRules.starterDocument(layout)
        let lights = CamperRoomBuilder.lights(CamperRoomBuilder.build(layout, doc: doc).items, style: doc.style, layout: layout)
        XCTAssertFalse(lights.isEmpty)
        XCTAssertTrue(lights.allSatisfy { $0.pattern == .roomLamp })
    }

}
