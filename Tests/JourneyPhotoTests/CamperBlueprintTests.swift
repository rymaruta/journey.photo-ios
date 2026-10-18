import XCTest
@testable import JourneyPhoto

/// キャンピングカーの組み立て図（板 CamperViews「どこから見てもホンモノ」の「作るもの」が形として在るか・2026-10-18）
final class CamperBlueprintTests: XCTestCase {

    private func build(_ stage: CamperStage = .camper, mood: CamperMood = .day, loadout: CamperLoadout = .standard,
                       silhouette: CamperCategory? = nil) -> CamperBlueprint {
        CamperBuilder.build(CamperConfig(stage: stage, mood: mood, loadout: loadout, posts: 18, silhouette: silhouette))
    }

    /// 名前が同じ部品の数（前方一致にしない: `interior.seat` と `interior.seatBack` を分けて数える）
    private func count(_ b: CamperBlueprint, _ name: String) -> Int {
        name.hasSuffix(".") ? b.nodes(named: name).count : b.nodes.filter { $0.name == name }.count
    }

    /// 性能の目安: どの段・どの飾りでも三角形は 9 万まで（板の注記「回している間は細い線を省く」の代わりに、
    /// 最初から面を抑える。SceneKit は材質ごとに束ねて描く）
    func testTriangleBudget() {
        var all = CamperLoadout.standard
        all.awningOpen = true
        for stage in CamperStage.allCases {
            for mood in CamperMood.allCases {
                let b = build(stage, mood: mood, loadout: all)
                XCTAssertLessThan(b.triangleEstimate, 90_000, "\(stage) \(mood)")
                XCTAssertGreaterThan(b.triangleEstimate, 8_000, "\(stage) \(mood) の面が少なすぎる（部品が抜けている）")
            }
        }
    }

    /// 床下の車台（板の付箋「床下」・CamperViews の 6 下）
    func testUnderbodyIsBuilt() {
        for stage in CamperStage.allCases {
            let b = build(stage)
            XCTAssertEqual(count(b, "under.frame"), 2, "\(stage)")
            XCTAssertEqual(count(b, "under.crossmember"), 4)
            XCTAssertEqual(count(b, "under.axle"), 2)
            XCTAssertEqual(count(b, "under.diff"), 1)
            XCTAssertEqual(count(b, "under.leafSpring"), 8)
            XCTAssertEqual(count(b, "under.propShaft"), 1)
            XCTAssertEqual(count(b, "under.fuelTank"), 1)
            XCTAssertEqual(count(b, "under.waterTank"), 1)
            XCTAssertEqual(count(b, "under.muffler"), 1)
            XCTAssertGreaterThanOrEqual(count(b, "under.exhaust"), 1)
            XCTAssertEqual(count(b, "under.mudFlap"), 4)
            // 底は床板、車輪の切り欠きの内側は筒（下から見て抜けない）
            XCTAssertEqual(count(b, "body.floorPan"), 1)
            XCTAssertEqual(count(b, "body.well"), 4)
        }
    }

    /// 扉（板の付箋: 壁に穴と厚み・扉の板の厚み 2.4・後ろの辺の蝶番・窓と取っ手 2・玄関マット・天井の灯り）
    func testDoorOpensIntoARoom() {
        let b = build()
        let door = b.nodes.filter { $0.group == .door }
        XCTAssertTrue(door.contains { $0.name == "door.panel" })
        XCTAssertTrue(door.contains { $0.name == "door.window" })
        XCTAssertTrue(door.contains { $0.name == "door.handle.out" } && door.contains { $0.name == "door.handle.in" })
        XCTAssertEqual(count(b, "door.hinge"), 2)
        XCTAssertEqual(count(b, "door.screw"), 4)
        XCTAssertEqual(b.doorHinge.x, 33.5, accuracy: 0.01, "蝶番は扉の後ろの辺（x 33.5）")
        XCTAssertEqual(b.doorOpenAngle * 180 / .pi, -100, accuracy: 0.01)
        if case .mesh(let m) = door.first(where: { $0.name == "door.panel" })!.shape {
            let bb = m.bounds
            XCTAssertEqual(bb.max.z - bb.min.z, 2.4, accuracy: 0.01, "扉の板の厚み")
            XCTAssertEqual(m.openEdgeCount, 0, "扉の板が閉じていない")
            XCTAssertTrue(m.materials.contains(.wallWood(0xD9C9A8)), "扉の内側が内装（壁の木）の色でない")
        } else { XCTFail("扉の板が網でない") }
        for name in ["interior.doorMat", "interior.doorLamp", "interior.kitchen", "interior.cupboard", "interior.floor"] {
            XCTAssertGreaterThanOrEqual(count(b, name), 1, name)
        }
    }

    /// 窓越しの室内（板の付箋「窓越しの室内の並び」）
    func testInteriorFurniture() {
        let b = build()
        XCTAssertEqual(count(b, "interior.bench"), 2, "長椅子 2")
        XCTAssertEqual(count(b, "interior.benchBack"), 1)
        for name in ["interior.table", "interior.counter", "interior.kettle", "interior.lamp", "interior.bunk", "interior.mattress",
                     "interior.dash", "interior.steering"] {
            XCTAssertGreaterThanOrEqual(count(b, name), 1, name)
        }
        XCTAssertEqual(count(b, "interior.seat"), 2)
        XCTAssertEqual(count(b, "interior.seatBack"), 2)
        XCTAssertEqual(count(b, "interior.curtain"), 12, "窓 A・B の左右にひだ 3 枚ずつ")
    }

    /// 前・後ろ・横・上（CamperViews の 1〜5）
    func testOutsideParts() {
        let b = build()
        XCTAssertEqual(count(b, "front.grilleBar"), 4)
        XCTAssertEqual(count(b, "front.emblem"), 1)
        XCTAssertEqual(count(b, "front.wiper"), 2)
        XCTAssertEqual(count(b, "light.bezel"), 2)
        XCTAssertEqual(count(b, "light.reflectorRing"), 4, "反射板の輪 2 ずつ")
        XCTAssertEqual(count(b, "rear.ladderRung"), 8)
        XCTAssertEqual(count(b, "rear.ladderRail"), 2)
        XCTAssertEqual(count(b, "rear.ladderClamp"), 4)
        XCTAssertEqual(count(b, "rear.taillight"), 2)
        XCTAssertEqual(count(b, "rear.spareCover"), 1)
        XCTAssertEqual(count(b, "awning.rivet"), 9)
        XCTAssertEqual(count(b, "ext.stepGroove"), 5)
        XCTAssertEqual(count(b, "ext.ventSlat"), 8, "冷蔵庫の換気口 2（桟 4 ずつ）")
        XCTAssertEqual(count(b, "roof.rackBar"), 3)
        XCTAssertEqual(count(b, "roof.rackFoot"), 4)
        XCTAssertEqual(count(b, "wheel.tyre"), 4)
        XCTAssertEqual(count(b, "wheel.tread"), 4)
        XCTAssertEqual(count(b, "wheel.nut"), 24, "ナット 6 × 4")
        XCTAssertEqual(count(b, "ext.mirror"), 2)
        XCTAssertEqual(count(b, "ext.mirrorGlass"), 2)
        XCTAssertEqual(count(b, "window"), 4, "窓 A・B と反対側の 2")
        XCTAssertEqual(count(b, "rear.window"), 1)
        XCTAssertEqual(count(b, "front.plate.number"), 1)
        XCTAssertEqual(count(b, "rear.plate.number"), 1)
    }

    /// 横の壁は閉じた板（窓は穴で、厚みの壁がある）。窓の穴は扉の側に 2、反対側に 2
    func testSideWallsAreClosedWithHoles() {
        let b = build()
        for name in ["body.side.near", "body.side.far", "body.rearWall"] {
            guard case .mesh(let m)? = b.nodes(named: name).first?.shape else { return XCTFail(name) }
            XCTAssertEqual(m.openEdgeCount, 0, "\(name) の縁が開いている")
            XCTAssertTrue(m.materials.contains(.reveal), "\(name) に窓の厚みが無い")
            XCTAssertTrue(m.materials.contains(.pinstripe), "\(name) に真鍮の線が無い")
            XCTAssertTrue(m.materials.contains(.cap) && m.materials.contains(.deep), "\(name) が 2 色に塗り分けられていない")
        }
    }

    /// 段: バンはオーニングも寝台も無く、トレーラーは最後の段だけ
    func testStagesDiffer() {
        XCTAssertEqual(count(build(.van), "trailer."), 0)
        XCTAssertEqual(count(build(.camper), "trailer."), 0)
        XCTAssertGreaterThan(count(build(.trailer), "trailer."), 10)
        XCTAssertEqual(count(build(.van), "awning.case"), 0)
        XCTAssertEqual(count(build(.van), "rear.ladderRung"), 0)
        XCTAssertGreaterThan(count(build(.van), "interior.mattress"), 0)
        XCTAssertEqual(count(build(.trailer), "wheel.tyre"), 6)
    }

    /// 部品を替えると形が替わる（集める部品が本当に車に付く）
    func testPartsChangeTheModel() {
        func with(_ c: CamperCategory, _ key: String) -> CamperBlueprint {
            var l = CamperLoadout.standard
            l.picks[c.rawValue] = key
            return build(loadout: l)
        }
        XCTAssertEqual(count(build(), "wheel.hole"), 0)
        XCTAssertEqual(count(with(.wheel, "steel"), "wheel.hole"), 24)
        XCTAssertEqual(count(with(.wheel, "whitewall"), "wheel.whitewall"), 4)
        XCTAssertEqual(count(with(.light, "rally"), "light.rally"), 2)
        XCTAssertEqual(count(with(.light, "rally"), "light.rallyLens"), 2)
        XCTAssertEqual(count(with(.light, "square"), "light.reflectorRing"), 0)
        XCTAssertEqual(count(with(.roof, "box"), "cargo.box"), 1)
        XCTAssertEqual(count(with(.roof, "box"), "cargo.crate"), 0)
        XCTAssertEqual(count(with(.trinket, "guitar"), "trinket.guitarNeck"), 1)
        XCTAssertEqual(count(with(.trinket, "globe"), "trinket.globe"), 1)
        XCTAssertEqual(count(with(.trinket, "globe"), "trinket.globeMeridian"), 1)
        XCTAssertEqual(count(with(.trinket, "books"), "trinket.book"), 5)
        var open = CamperLoadout.standard
        open.awningOpen = true
        XCTAssertEqual(count(build(), "awning.leg"), 0)
        XCTAssertEqual(count(build(loadout: open), "awning.leg"), 2)
        XCTAssertEqual(count(build(loadout: open), "awning.stripe"), 10)
        // 全部の部品が、少なくとも 1 つの形を出す（データだけの部品を作らない）
        for part in CamperCatalog.all where part.category != .paint && part.category != .stickerEdge {
            var l = CamperLoadout.standard
            l.awningOpen = true
            l.pick(part)
            let b = build(loadout: l)
            XCTAssertFalse(b.nodes.filter { $0.category == part.category }.isEmpty, part.id)
        }
    }

    /// 金の箔押しの縁は縁の素材が替わる
    func testStickerEdge() {
        var l = CamperLoadout.standard
        l.picks[CamperCategory.stickerEdge.rawValue] = "gold"
        let gold = build(loadout: l).nodes.filter { $0.category == .sticker }
        XCTAssertFalse(gold.isEmpty)
        XCTAssertTrue(gold.allSatisfy { $0.material == .foil })
    }

    /// まだ持っていない部品は、その分類だけ影絵にする
    func testSilhouetteOnlyTouchesItsCategory() {
        let b = build(silhouette: .wheel)
        let wheels = b.nodes.filter { $0.category == .wheel }
        XCTAssertFalse(wheels.isEmpty)
        XCTAssertTrue(wheels.allSatisfy { $0.material == .silhouette })
        XCTAssertFalse(b.nodes.filter { $0.category != .wheel }.contains { $0.material == .silhouette })
    }

    /// 夜だけ灯り（室内 2・前照灯 2・尾灯 1）
    func testNightLights() {
        XCTAssertTrue(build(mood: .day).lights.isEmpty)
        let lights = build(mood: .night).lights
        XCTAssertEqual(lights.filter { $0.kind == .spot }.count, 2)
        XCTAssertEqual(lights.count, 5)
        XCTAssertLessThanOrEqual(lights.count + 1, 8, "SceneKit の1つの物に効く光は 8 まで（月を足して）")
    }

    /// 寸法（板の図面: 全長 242・車幅 100・全高 134・ホイールベース 158・タイヤ半径 22）
    func testDimensions() {
        let b = build()
        XCTAssertEqual(b.length.upperBound - b.length.lowerBound, 242, accuracy: 0.01)
        XCTAssertEqual(b.halfWidth * 2, 100)
        let builder = CamperBuilder(config: CamperConfig(stage: .camper))
        XCTAssertEqual(builder.roofTop, 134)
        XCTAssertEqual(builder.wheels[1] - builder.wheels[0], 158)
        XCTAssertEqual(builder.wheelR, 22)
    }
}
