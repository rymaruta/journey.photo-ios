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
            XCTAssertTrue(m.materials.contains(.wallWood(0xD9B98A)), "扉の内側が内装（壁の木・松の板）の色でない")
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
        XCTAssertEqual(count(b, "interior.curtain"), 20, "窓 A・B の左右にひだ 5 つずつ（図鑑の麻のひだ）")
    }

    /// 前・後ろ・横・上（CamperViews の 1〜5）
    func testOutsideParts() {
        let b = build()
        XCTAssertEqual(count(b, "front.grilleBar"), 5, "図鑑: クロームの桟 5 本")
        XCTAssertEqual(count(b, "front.emblem"), 1)
        XCTAssertEqual(count(b, "front.wiper"), 2)
        XCTAssertEqual(count(b, "light.bezel"), 2)
        // 反射板は輪ではなく凹んだお椀 1 つずつ（2026-10-19 作り直し。詳しくは testLampsAreBuiltLikeRealOnes）
        XCTAssertEqual(count(b, "light.reflector"), 2, "反射板のお椀 1 つずつ")
        XCTAssertEqual(count(b, "rear.ladderRung"), 7, "図鑑: 柱 2 と段 7")
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
        XCTAssertEqual(count(with(.wheel, "steel_black"), "wheel.hole"), 24)
        XCTAssertEqual(count(with(.wheel, "whitewall"), "wheel.whitewall"), 4)
        XCTAssertEqual(count(with(.wheel, "brass_spoke"), "wheel.spoke"), 64, "真鍮のスポーク 16 本 × 4")
        XCTAssertEqual(count(with(.headlight, "rally_brass"), "light.rally"), 2)
        XCTAssertEqual(count(with(.headlight, "square"), "light.reflectorRing"), 0)
        XCTAssertEqual(count(with(.roofCargo, "roof_box"), "cargo.box"), 1)
        XCTAssertEqual(count(with(.roofCargo, "roof_box"), "cargo.crate"), 0)
        XCTAssertEqual(count(with(.plant, "monstera"), "interior.leaf"), 6)
        XCTAssertEqual(count(build(), "tent.base"), 0, "ルーフテントは最初は付けない")
        XCTAssertEqual(count(with(.roofTent, "clamshell"), "tent.base"), 1)
        var open = CamperLoadout.standard
        open.awningOpen = true
        XCTAssertEqual(count(build(), "awning.leg"), 0)
        XCTAssertEqual(count(build(loadout: open), "awning.leg"), 2)
        XCTAssertEqual(count(build(loadout: open), "awning.stripe"), 10)
    }

    /// 図鑑の 132 個はどれも形を出し、同じ分類の 4 つは形で見分けられる（色違いだけにしない）
    func testEveryDexPartHasItsOwnShape() {
        for c in CamperCategory.allCases where c.inDex {
            var signatures: [String: String] = [:]
            for part in CamperCatalog.parts(c) {
                var l = CamperLoadout.standard
                l.awningOpen = true
                l.pick(part)
                let nodes = build(loadout: l).nodes.filter { $0.category == c }
                XCTAssertFalse(nodes.isEmpty, "\(part.id) の形が無い")
                // 形の名前・数・面の数・置き場所（材質＝色は入れない）
                let sig = nodes.map { n in
                    "\(n.name)|\(n.triangleEstimate)|\(Int(n.position.x)),\(Int(n.position.y)),\(Int(n.position.z))|\(Int(n.scale.x * 10))"
                }.sorted().joined(separator: ";")
                if let other = signatures[sig] { XCTFail("\(part.id) と \(other) の形が同じ（色違いだけ）") }
                signatures[sig] = part.id
            }
        }
    }

    /// 金の箔押しの縁は縁の素材が替わる
    func testStickerEdge() {
        var l = CamperLoadout.standard
        l.picks[CamperCategory.stickerEdge.rawValue] = "gold_foil"
        let gold = build(loadout: l).nodes.filter { $0.category == .stickerEdge }
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

    /// 夜だけ灯り（室内 2・入口 1・焚き火 1・ランタン 1）。停めている車の前照灯・尾灯は点けない（2026-10-19）
    func testNightLights() {
        XCTAssertTrue(build(mood: .day).lights.isEmpty)
        let lights = build(mood: .night).lights
        XCTAssertEqual(lights.filter { $0.name == "porch" && $0.kind == .spot }.count, 1)
        // 室内の灯りは天井から下向きの spot で影を落とす（omni だと屋根の棒・縁に光の筋が乗った・run 533）
        for stage in CamperStage.allCases {
            let b = build(stage, mood: .night)
            let roof = CamperBuilder(config: CamperConfig(stage: stage)).roofTop
            for l in b.lights where l.inside {
                XCTAssertEqual(l.kind, .spot, l.name)
                XCTAssertTrue(l.castsShadow, l.name)
                XCTAssertLessThan(l.direction.y, -0.99, l.name)
                XCTAssertLessThan(l.position.y, roof - 8, "\(stage) \(l.name): 天井より下")
                XCTAssertLessThan(l.spotOuter / 2, 80, "円錐が上を向かない")
            }
        }
        // 室内 2・入口 1・焚き火 1・外のランタン 1
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

    /// 夜は窓と扉の口から地面へ灯りがこぼれる（光の溜まり。光の数は増やさない）。昼は無い
    func testNightGlowPools() {
        XCTAssertTrue(build(mood: .day).nodes.allSatisfy { $0.group != .glow && $0.group != .doorGlow })
        for stage in CamperStage.allCases {
            let b = build(stage, mood: .night)
            let builder = CamperBuilder(config: CamperConfig(stage: stage, mood: .night))
            // 窓の下の溜まり（前照灯の帯・尾灯・焚き火の溜まりは別の試験 testNightGroundPools）
            let pools = b.nodes.filter { $0.group == .glow && $0.name.hasPrefix("glow.window") }
            XCTAssertEqual(pools.count, builder.windowsNear.count + builder.windowsFar.count, "\(stage)")
            XCTAssertEqual(b.nodes.filter { $0.group == .doorGlow }.count, 1, "\(stage)")
            for p in pools + b.nodes.filter({ $0.group == .doorGlow }) {
                XCTAssertEqual(p.material, .glowPool)
                XCTAssertLessThan(p.position.y, 1, "地面に寝ている")
                XCTAssertGreaterThan(abs(p.position.z), builder.BW, "車の外の地面")
            }
        }
        XCTAssertEqual(CamperMaterials.spec(.glowPool, paint: 0, mood: .night).additive, true)
    }

    /// ステッカーは貼った紙: 厚みがあり、端が壁からわずかに浮いて反る（平らな円盤にしない）
    func testStickerIsCurledPaper() {
        for edge in ["white_cut", "gold_foil", "holo", "signed"] {
            var l = CamperLoadout.standard
            l.picks[CamperCategory.stickerEdge.rawValue] = edge
            let b = build(loadout: l)
            guard let node = b.nodes.first(where: { $0.name == "sticker.0" }), case .mesh(let m) = node.shape else {
                return XCTFail(edge)
            }
            let box = m.bounds
            XCTAssertEqual(box.min.z, 50, accuracy: 0.01, "\(edge): 裏は壁に付く")
            XCTAssertGreaterThan(box.max.z - box.min.z, 1.3, "\(edge): 端が浮いていない")
            XCTAssertLessThan(box.max.z - box.min.z, 3.5, "\(edge): 反りすぎ")
        }
    }

    /// 扉を開けた所は、扉の口を前の側から斜めにのぞく（口の真ん中を狙う・真横から見ない）
    func testDoorFramingLooksIntoTheDoorway() {
        for stage in CamperStage.allCases {
            let a = CamperFraming.door(stage)
            let hole = CamperBuilder(config: CamperConfig(stage: stage)).doorHole
            let xs = hole.map(\.x), ys = hole.map(\.y)
            XCTAssertTrue((xs.min()!...xs.max()!).contains(a.target.x), "\(stage)")
            XCTAssertTrue((ys.min()!...ys.max()!).contains(a.target.y), "\(stage)")
            // 前の側から斜めに（開いた扉の板は口の後ろに立つ）。斜めすぎると口が細い帯になる
            XCTAssertTrue((-40.0)...(-15.0) ~= a.yaw, "前の側から斜めに")
            XCTAssertLessThan(a.target.z, CamperBuilder(config: CamperConfig(stage: stage)).BW, "狙いは口の奥")
            XCTAssertTrue(CamperFraming.zoomRange.contains(a.zoom))
        }
    }

    /// 床は暗い一色で、車から離れるほど透けて消える（絵を貼らない・地平線の線を出さない）
    func testFloorMeltsIntoTheBackdrop() {
        for mood in CamperMood.allCases {
            let f = CamperMaterials.floor(mood)
            let c = CamperTextures.rgb(f.color)
            if mood != .snow { XCTAssertLessThan(max(c.0, c.1, c.2), 0.15, "\(mood) の床が明るい") }
            XCTAssertTrue(f.shaderModifier.contains("smoothstep(\(f.fadeStart), \(f.fadeEnd)"))
            XCTAssertTrue(f.shaderModifier.contains("_output.color *="))
            XCTAssertFalse(f.shaderModifier.contains("#pragma transparent"), "透ける組では太陽の影が落ちない")
            // 車体（半分 1.21）の下は濃く、トレーラーの後ろ（2.9）より先で消える
            XCTAssertGreaterThan(f.fadeStart, 1.21)
            XCTAssertGreaterThan(f.fadeEnd, 2.9)
        }
    }

    /// 映り込みの元: 地平線がくっきりし（空の下端は明るく、すぐ下の地面は暗い）、光の箱がある
    func testEnvironmentHasCrispHorizonAndSoftboxes() {
        let env = CamperTextures.environment(.day)
        let sky = env.pixel(100, 62), ground = env.pixel(100, 66)
        XCTAssertGreaterThan(Int(sky.r) - Int(ground.r), 120)
        let box = env.pixel(128, 14)
        XCTAssertGreaterThan(Int(box.r), 240)
        XCTAssertEqual(CamperMaterials.spec(.paint, paint: 0x5B6168, mood: .day).clearCoat, 1)
        XCTAssertEqual(CamperMaterials.spec(.paint, paint: 0x5B6168, mood: .day).clearCoatRoughness, 0.08)
    }

    /// 夜の主役は窓と扉の口の灯り。焚き火・ランタン・電飾は弱く、近くだけ（run 530: 左 3 分の 1 が白く飛んだ）
    func testNightOutdoorLightsStayModest() {
        var l = CamperLoadout.standard
        for (cat, key) in [(CamperCategory.outdoorLight, "string_lights"), (.outdoorLight, "brass_lantern")] {
            l.picks[cat.rawValue] = key
            let lights = build(mood: .night, loadout: l).lights
            let interior = lights.filter { $0.name.hasPrefix("interior.") }.map(\.intensity).max() ?? 0
            for o in lights where ["campfire", "lantern", "string"].contains(o.name) {
                XCTAssertLessThanOrEqual(o.intensity, interior / 4, "\(o.name) が室内の灯りに迫る")
                XCTAssertLessThanOrEqual(o.range, 72, o.name)
            }
        }
        XCTAssertLessThanOrEqual(CamperMaterials.spec(.ember, paint: 0, mood: .night).emissionIntensity, 1.0)
    }

    /// 扉の口から見えるもの: 台所（天板・やかん）と吊りランプが口の正面にある
    func testKitchenAndLampFaceTheDoorway() {
        let b = build()
        let hole = CamperBuilder(config: CamperConfig(stage: .camper)).doorHole.map(\.x)
        let span = (hole.min()! - 30)...(hole.max()! + 10)
        for name in ["interior.counter", "interior.kettle", "interior.lamp"] {
            guard let n = b.nodes.first(where: { $0.name == name }) else { return XCTFail(name) }
            XCTAssertTrue(span.contains(n.position.x), "\(name) x=\(n.position.x)")
        }
    }

    /// 外の置き物は車の横に潰れず、少し離れた地面に（床が透け始める所より手前）
    func testCampsiteStandsApart() {
        let b = build()
        let bw = CamperBuilder(config: CamperConfig(stage: .camper)).BW
        let fade = CamperMaterials.floor(.day).fadeStart * 100
        for n in b.nodes where [CamperCategory.chair, .table, .firePit].contains(n.category) {
            XCTAssertGreaterThan(n.position.z, bw + 30, n.name)
            XCTAssertLessThan(CV2(n.position.x, n.position.z).length, fade, n.name)
        }
    }

    /// 初めの寄り: 車が画面の横幅の 7〜9 割（画面の横縦は 1.4 前後）
    func testOverviewFillsTheStage() {
        for stage in CamperStage.allCases {
            let a = CamperFraming.overview(stage)
            let b = build(stage)
            let yaw = abs(a.yaw) * .pi / 180
            let car = (b.length.upperBound - b.length.lowerBound) * cos(yaw) + b.halfWidth * 2 * sin(yaw)
            let frame = 1.4 * 2 * CamperFraming.distance(zoom: a.zoom) * tan(CamperFraming.fieldOfView / 2 * .pi / 180) * 100
            XCTAssertGreaterThan(car / frame, 0.65, "\(stage)")
            XCTAssertLessThan(car / frame, 0.9, "\(stage)")
        }
    }

    /// 室内の灯りは室内だけを照らす: 室内の部品と内張りの材質は「室内」、外の殻・縁・扉は「外」に分かれる
    /// （run 532: 影の無い室内の灯りが壁を抜け、屋根の縁・窓枠・荷台の棒に光の筋が乗った）
    func testInteriorLightStaysInside() {
        let b = build(mood: .night)
        var insideMaterials = Set<String>(), outsideMaterials = Set<String>()
        for n in b.nodes {
            let (i, o) = n.splitForInteriorLight()
            if let i, case .mesh(let m) = i.shape { m.materials.forEach { insideMaterials.insert("\($0)") } }
            if let o, case .mesh(let m) = o.shape, !o.name.hasPrefix("interior."), o.group != .door {
                for mat in m.materials { XCTAssertFalse(CamperNodeSpec.isInteriorMaterial(mat), "\(o.name) \(mat)") }
                m.materials.forEach { outsideMaterials.insert("\($0)") }
            }
            let cab = n.position.x >= 66 || (n.position.x >= 30 && n.position.y >= 108)
            if n.name.hasPrefix("interior."), !cab { XCTAssertNil(o, n.name) }
            // 運転席と寝台は室内の灯りの外（フロントガラスの上に橙の筋が出た・run 547）
            if n.name.hasPrefix("interior."), cab { XCTAssertNil(i, n.name) }
            if n.group == .door { XCTAssertNil(i, n.name) }
        }
        XCTAssertTrue(insideMaterials.contains { $0.hasPrefix("wallWood") } && insideMaterials.contains("ceiling")
                      && insideMaterials.contains("floorIn"), "\(insideMaterials.sorted())")
        XCTAssertTrue(outsideMaterials.contains("chrome") && outsideMaterials.contains("paint"))
        for l in b.lights { XCTAssertEqual(l.inside, l.name.hasPrefix("interior."), l.name) }
        // 扉の口のすぐ内に灯りを置かない（口のまわりが白く飛んだ）
        let hole = CamperBuilder(config: CamperConfig(stage: .camper)).doorHole.map(\.x)
        for l in b.lights where l.inside {
            XCTAssertFalse((hole.min()!...hole.max()!).contains(l.position.x) && l.position.z > 0, l.name)
        }
    }

    /// 運転席のガラスは夜も光らない。住む所の窓だけがほのかに光る
    func testOnlyLivingWindowsGlowAtNight() {
        XCTAssertNil(CamperMaterials.spec(.glass, paint: 0, mood: .night).emission)
        // 2026-10-19 作り直し: 窓のガラスは光らない（一色の板になった）。薄い暗い硝子（板 0.38）で、照らされた室内が透け、
        // 表に映り込みが乗る。光るのは室内の灯りに照らされた布（織り目の絵の弱い光）
        let glass = CamperMaterials.spec(.glassLit, paint: 0, mood: .night)
        XCTAssertNil(glass.emission)
        // 夜は 0.22（奥の明かりを見せる・Mac night3）。昼は板どおり 0.62
        XCTAssertEqual(glass.opacity, 0.22, accuracy: 0.001)
        XCTAssertEqual(CamperMaterials.spec(.glassLit, paint: 0, mood: .day).opacity, 0.62, accuracy: 0.001)
        XCTAssertLessThan(glass.roughness, 0.1)
        XCTAssertGreaterThan(glass.clearCoat, 0)
        let curtain = CamperMaterials.spec(.curtain, paint: 0, mood: .night)
        XCTAssertEqual(curtain.emissionTexture, .weave)
        // 布を透ける弱い光（窓が灯って見える強さ・1 より十分小さい）
        XCTAssertGreaterThanOrEqual(curtain.emissionIntensity, 0.3)
        XCTAssertLessThanOrEqual(curtain.emissionIntensity, 0.6)
        let b = build(mood: .night)
        func materials(_ name: String) -> [CamperMaterial] {
            b.nodes.filter { $0.name == name }.flatMap { n -> [CamperMaterial] in
                if case .mesh(let m) = n.shape { return m.materials }
                return [n.material]
            }
        }
        XCTAssertFalse(materials("cabDoor.window").contains(.glassLit))
        XCTAssertTrue(materials("window").contains(.glassLit))
        XCTAssertTrue(materials("door.window").contains(.glassLit))
    }

    /// 夜に光る面は emission 1 まで（にじみ無しで読め、HDR の値が大きくならない・run 533 の黒い四角）。住む所の窓は灯る
    func testNightEmissionStaysModest() {
        let all: [CamperMaterial] = [.glassLit, .lens, .lensAmber, .red, .amber, .lamp, .ember, .curtain]
        for m in all {
            let spec = CamperMaterials.spec(m, paint: 0, mood: .night)
            XCTAssertLessThanOrEqual(spec.emissionIntensity, 1.0, "\(m)")
        }
        // 点いている電球は白い丸にしない: 光る面に明暗の絵
        XCTAssertEqual(CamperMaterials.spec(.lamp, paint: 0, mood: .night).emissionTexture, .lampFace)
        // 足す光（地面の溜まり・炎）の色も、HDR で飛ばない明るさ（どの成分も 0.95 まで）
        for m: CamperMaterial in [.glowPool, .firePool, .flame] {
            let spec = CamperMaterials.spec(m, paint: 0, mood: .night)
            XCTAssertTrue(spec.additive, "\(m)")
            let c = CamperTextures.rgb(spec.color)
            XCTAssertLessThanOrEqual(max(c.0, c.1, c.2), 0.95, "\(m)")
        }
    }

    /// 夜の灯りの色: 月明かりの青と灯りの暖色の対比。室内灯は 2700K 前後、外の火（焚き火・ランタン）は室内灯より赤い、
    /// 前照灯は白に近い（2026-10-19 owner「夜の発光の仕方ひどい」）
    func testNightLightColors() {
        var l = CamperLoadout.standard
        l.picks[CamperCategory.outdoorLight.rawValue] = "brass_lantern"
        let lights = build(mood: .night, loadout: l).lights
        func rgb(_ name: String) -> (Double, Double, Double)? {
            lights.first { $0.name == name }.map { CamperTextures.rgb($0.color) }
        }
        let inside = try? XCTUnwrap(rgb("interior.rear"))
        let lantern = try? XCTUnwrap(rgb("lantern"))
        let fire = try? XCTUnwrap(rgb("campfire"))
        let porch = try? XCTUnwrap(rgb("porch"))
        guard let inside, let lantern, let fire, let porch else { return XCTFail("灯りが無い") }
        // 2700K ≒ (255, 180, 107)
        XCTAssertEqual(inside.1, 180.0 / 255, accuracy: 0.03)
        XCTAssertEqual(inside.2, 107.0 / 255, accuracy: 0.05)
        // 外の火は室内灯より赤い（緑と青が少ない）
        XCTAssertLessThan(lantern.1, inside.1)
        XCTAssertLessThan(fire.1, inside.1)
        // 入口の灯りも 2700K（室内と同じ暖色）
        XCTAssertEqual(porch.1, 180.0 / 255, accuracy: 0.03)
        XCTAssertEqual(porch.2, 107.0 / 255, accuracy: 0.05)
        // 室内の灯りは窓の高さまで届く広い円錐
        for l in lights where l.inside { XCTAssertGreaterThanOrEqual(l.spotOuter, 150, l.name) }
    }

    /// 地面の溜まり: 前照灯の前の光の帯（板の beam）・尾灯の赤・焚き火とランタンの足元。どれも夜だけ・裾がなめらか
    func testNightGroundPools() {
        var l = CamperLoadout.standard
        l.picks[CamperCategory.outdoorLight.rawValue] = "brass_lantern"
        let b = build(mood: .night, loadout: l)
        let builder = CamperBuilder(config: CamperConfig(stage: .camper))
        // 停めている車なので、前照灯の前の光の帯と尾灯の赤い溜まりは無い（2026-10-19）
        XCTAssertNil(b.nodes.first { $0.name == "glow.beam" })
        XCTAssertNil(b.nodes.first { $0.name == "glow.tail" })
        let step = b.nodes.first { $0.name == "glow.step" }
        XCTAssertNotNil(step, "入口の足元の溜まり")
        XCTAssertGreaterThan(step?.position.z ?? 0, builder.BW, "車の外の地面")
        XCTAssertNotNil(b.nodes.first { $0.name == "glow.fire" })
        XCTAssertNotNil(b.nodes.first { $0.name == "glow.lantern" })
        XCTAssertNil(build(mood: .day, loadout: l).nodes.first { $0.name == "glow.step" })
        // 溜まりの絵は縁で 0、真ん中から外へなめらかに減る（硬い円にしない）
        let g = CamperTextures.glow()
        XCTAssertEqual(g.pixel(0, 32).r, 0)
        var last = 256
        for x in 32..<64 {
            let v = Int(g.pixel(x, 32).r)
            XCTAssertLessThanOrEqual(v, last)
            last = v
        }
        // 半径の半ばでは真ん中の 1/4〜3/4（急な段にしない）
        let mid = Double(g.pixel(48, 32).r) / Double(g.pixel(32, 32).r)
        XCTAssertTrue((0.1...0.75).contains(mid), "\(mid)")
    }

    /// 炎は形のある舌（旋盤の形・炎の貼り絵の位置つき）。燠は平たく。ランタンは硝子の中に小さな炎
    func testFlamesHaveShape() {
        var l = CamperLoadout.standard
        l.picks[CamperCategory.outdoorLight.rawValue] = "brass_lantern"
        let b = build(mood: .night, loadout: l)
        let flames = b.nodes.filter { $0.group == .flame }
        XCTAssertGreaterThanOrEqual(flames.filter { $0.name == "fire.flame" }.count, 3)
        XCTAssertEqual(flames.filter { $0.name == "light.lanternFlame" }.count, 1)
        for f in flames {
            guard case .mesh(let m) = f.shape else { return XCTFail(f.name) }
            XCTAssertEqual(m.materials, [.flame])
            XCTAssertTrue(m.uvs.allSatisfy { (0...1).contains($0.y) }, f.name)
            let box = m.bounds
            XCTAssertGreaterThan(box.max.y - box.min.y, (box.max.x - box.min.x) * 1.2, "\(f.name): 縦長の舌でない")
        }
        let glass = b.nodes.first { $0.name == "light.lanternGlass" }
        if case .mesh(let m)? = glass?.shape { XCTAssertEqual(m.materials, [.lanternGlass]) } else { XCTFail("ランタンの硝子") }
        // 炎の貼り絵: 根元は明るく、先は暗い（足しても何も出ない）
        let tex = CamperTextures.flame()
        XCTAssertGreaterThan(Int(tex.pixel(16, 60).r), 200)
        XCTAssertLessThan(Int(tex.pixel(16, 1).r), 40)
    }

    /// 前照灯のレンズは真ん中から外へ 0〜1 の貼り絵の位置（明暗の絵が真ん中に合う）。絵は芯が明るく、輪があり、縁へ暗い
    func testHeadlightLensFace() {
        let b = build(mood: .night)
        let lenses = b.nodes.filter { $0.name == "light.lens" }
        XCTAssertEqual(lenses.count, 2)
        for n in lenses {
            guard case .mesh(let m) = n.shape else { return XCTFail("レンズ") }
            let us = m.uvs.map(\.x), vs = m.uvs.map(\.y)
            XCTAssertEqual(us.min() ?? -1, 0, accuracy: 0.02)
            XCTAssertEqual(us.max() ?? -1, 1, accuracy: 0.02)
            XCTAssertEqual(vs.min() ?? -1, 0, accuracy: 0.02)
            XCTAssertEqual(vs.max() ?? -1, 1, accuracy: 0.02)
        }
        let face = CamperTextures.lampFace()
        let center = Int(face.pixel(32, 32).r), edge = Int(face.pixel(63, 32).r)
        let ring = Int(face.pixel(32 + 12, 32).r), between = Int(face.pixel(32 + 18, 32).r)
        XCTAssertGreaterThan(center, 230)
        XCTAssertLessThan(edge, 90)
        XCTAssertGreaterThan(ring, between, "反射板の輪が見えない")
    }

    /// 夜の住む所の窓: カーテンのすぐ内側に、むらのある弱い光の面（外を向く・ガラスの奥）。昼は無い。
    /// 絵は真ん中が明るく、下半分（家具の影）が暗く、縁は黒へ落ちる（板に見せない・Mac run 547 の後）
    func testWindowGlowPanels() {
        for stage in CamperStage.allCases {
            let b = build(stage, mood: .night)
            let builder = CamperBuilder(config: CamperConfig(stage: stage))
            let panels = b.nodes.filter { $0.name.hasPrefix("interior.windowGlow") }
            XCTAssertEqual(panels.count, builder.windowsNear.count + builder.windowsFar.count, "\(stage)")
            for p in panels {
                XCTAssertEqual(p.material, .windowGlow)
                XCTAssertLessThan(abs(p.position.z), builder.BW - builder.wall, "\(stage): ガラスより奥")
                XCTAssertGreaterThan(abs(p.position.z), builder.BW - builder.wall - 6, "\(stage): カーテンのすぐ内側")
                guard case .mesh(let m) = p.shape else { return XCTFail(p.name) }
                // 外を向く
                XCTAssertTrue(m.normals.allSatisfy { $0.z * p.position.z > 0 }, p.name)
            }
            XCTAssertTrue(build(stage, mood: .day).nodes.allSatisfy { !$0.name.hasPrefix("interior.windowGlow") })
        }
        let spec = CamperMaterials.spec(.windowGlow, paint: 0, mood: .night)
        XCTAssertTrue(spec.additive)
        let c = CamperTextures.rgb(spec.color)
        XCTAssertTrue((0.9...1.0).contains(max(c.0, c.1, c.2)), "強さ 0.95〜1.0")
        // 窓から漏れる光のにじみ: 窓ごとに 1 枚・ガラスの外・窓より一回り大きい・足す光 0.3 ほど
        let nb = build(mood: .night)
        let halos = nb.nodes.filter { $0.name.hasPrefix("glow.halo") }
        let nbuilder = CamperBuilder(config: CamperConfig(stage: .camper))
        XCTAssertEqual(halos.count, nbuilder.windowsNear.count + nbuilder.windowsFar.count)
        for h in halos {
            XCTAssertGreaterThan(abs(h.position.z), nbuilder.BW, "ガラスの外")
            XCTAssertEqual(h.group, .glow)
        }
        let halo = CamperTextures.rgb(CamperMaterials.spec(.windowHalo, paint: 0, mood: .night).color)
        XCTAssertTrue((0.2...0.35).contains(max(halo.0, halo.1, halo.2)))
        let g = CamperTextures.roomGlow()
        let center = Int(g.pixel(32, 18).r), lower = Int(g.pixel(32, 40).r), edge = Int(g.pixel(0, 18).r)
        XCTAssertGreaterThan(center, 200)
        XCTAssertLessThan(lower, center * 3 / 4, "家具の影の帯が無い")
        // 明るいところ（真ん中の 7 割以上）が窓の半分以上
        var bright = 0
        for y in 0..<g.height { for x in 0..<g.width where Int(g.pixel(x, y).r) >= center * 7 / 10 { bright += 1 } }
        XCTAssertGreaterThanOrEqual(Double(bright) / Double(g.width * g.height), 0.5, "明るいところが狭い")
        XCTAssertLessThan(edge, 30, "縁が黒へ落ちない（板に見える）")
        // カーテンのひだ（両側に明暗の筋）
        let folds = (2..<13).map { Int(g.pixel($0, 18).r) }
        XCTAssertGreaterThan((folds.max() ?? 0) - (folds.min() ?? 0), 25)
    }

    // MARK: 灯り（2026-10-19 owner「テールランプとかの灯りが不自然すぎる」）

    /// 停めている車の走る時の灯り（前照灯・尾灯・制動灯・方向指示・車幅灯）は、夜も**消えている**:
    /// 灯り（SceneKit の光）が無く、レンズの材質は夜も光らない。昼と夜でレンズの値は同じ（光の当たり方だけが替わる）
    func testDrivingLampsStayOffWhenParkedAtNight() {
        for stage in CamperStage.allCases {
            for headlight in ["round", "twin_round", "square", "rally_brass"] {
                var l = CamperLoadout.standard
                l.picks[CamperCategory.headlight.rawValue] = headlight
                let names = build(stage, mood: .night, loadout: l).lights.map(\.name)
                for off in ["headlight", "taillight", "brake", "indicator", "marker"] {
                    XCTAssertFalse(names.contains { $0.hasPrefix(off) }, "\(stage) \(headlight): 夜に \(off) が点いている")
                }
            }
        }
        for m: CamperMaterial in [.lens, .lensAmber, .red, .amber, .reflector, .bulbOff] {
            let night = CamperMaterials.spec(m, paint: 0, mood: .night)
            XCTAssertNil(night.emission, "\(m) が夜に光る")
            XCTAssertEqual(night.emissionIntensity, 0, "\(m)")
            XCTAssertEqual(night, CamperMaterials.spec(m, paint: 0, mood: .day), "\(m) の値が夜だけ違う")
        }
        // 前・後ろ・前照灯の分類の部品は、夜もどれも光らない（光ってよいのは室内・入口・足元・外の灯りだけ）
        var l = CamperLoadout.standard
        l.picks[CamperCategory.headlight.rawValue] = "rally_brass"
        let b = build(mood: .night, loadout: l)
        let lamps = b.nodes.filter { $0.category == .headlight || $0.name.hasPrefix("rear.") || $0.name.hasPrefix("front.")
            || $0.name.hasPrefix("ext.marker") }
        XCTAssertGreaterThan(lamps.count, 20)
        for n in lamps {
            let ms: [CamperMaterial]
            if case .mesh(let m) = n.shape { ms = m.materials } else { ms = [n.material] }
            for m in ms {
                XCTAssertNil(CamperMaterials.spec(m, paint: 0, mood: .night).emission, "\(n.name) が夜に光る")
            }
        }
    }

    /// 灯りは実車の作り: 縁の枠・奥の反射板・電球・表の硝子。硝子は透け（前照灯は透明・テールは濃い赤・方向指示は橙）、
    /// 艶は低い粗さと clearCoat。反射板は内側を向くお椀で、硝子より奥にある（白い平らな円盤にしない）
    func testLampsAreBuiltLikeRealOnes() {
        for headlight in ["round", "twin_round", "square"] {
            var l = CamperLoadout.standard
            l.picks[CamperCategory.headlight.rawValue] = headlight
            let b = build(loadout: l)
            let per = headlight == "twin_round" ? 4 : 2
            XCTAssertEqual(count(b, "light.reflector"), per, headlight)
            XCTAssertEqual(count(b, "light.headBulb"), per, headlight)
            XCTAssertEqual(count(b, "light.lens"), per, headlight)
            XCTAssertGreaterThanOrEqual(count(b, "light.bezel"), per, headlight)
            // 反射板・電球は硝子より奥（車体の側）
            let lensX = b.nodes.filter { $0.name == "light.lens" }.map(\.position.x).min() ?? 0
            for n in b.nodes where n.name == "light.reflector" || n.name == "light.headBulb" {
                XCTAssertLessThan(n.position.x, lensX, "\(headlight) \(n.name) が硝子の前に出ている")
            }
        }
        // 丸い反射板は凹んだお椀: 面は軸の側（内側）と口の側を向く（裏返し忘れると外向きで、正面から見えない）
        let b = build()
        guard let bowl = b.nodes.first(where: { $0.name == "light.reflector" }), case .mesh(let m) = bowl.shape else {
            return XCTFail("お椀の反射板が無い")
        }
        // 旋盤の軸は +Y（置く時に +X へ回す）。内向きなら向きの Y は正で、半径の向きとは逆
        let inward = zip(m.positions, m.normals).filter { p, n in
            n.y > 0 && CV3(p.x, 0, p.z).dot(n) < 0
        }.count
        XCTAssertGreaterThan(Double(inward) / Double(max(1, m.normals.count)), 0.9, "反射板が内側を向いていない")

        // 尾灯の組: 赤（尾灯）・橙（方向指示）・透明（後退灯）・反射板・メッキの枠（両側）
        for stage in CamperStage.allCases {
            let r = build(stage)
            for name in ["rear.taillight", "rear.turnLens", "rear.reverseLens", "rear.lampReflector"] {
                XCTAssertEqual(count(r, name), 2, "\(stage) \(name)")
            }
            XCTAssertEqual(count(r, "rear.lampFrame"), 8, "\(stage)")
            let lens = r.nodes.filter { $0.name == "rear.taillight" }.map(\.position.x).max() ?? 0
            let refl = r.nodes.filter { $0.name == "rear.lampReflector" }.map(\.position.x).min() ?? 0
            XCTAssertGreaterThan(refl, lens, "\(stage): 尾灯の反射板がレンズの奥（車体の側）にない")
        }
        // 硝子の値: 透け・艶・色
        XCTAssertLessThan(CamperMaterials.spec(.lens, paint: 0, mood: .day).opacity, 0.4, "前照灯の硝子が白い板（透けない）")
        for m: CamperMaterial in [.lens, .lensAmber, .red, .amber] {
            let spec = CamperMaterials.spec(m, paint: 0, mood: .night)
            XCTAssertLessThan(spec.opacity, 1, "\(m) が透けない")
            XCTAssertLessThanOrEqual(spec.roughness, 0.1, "\(m) の艶")
            XCTAssertGreaterThan(spec.clearCoat, 0.5, "\(m) に映り込みが無い")
        }
        let red = CamperTextures.rgb(CamperMaterials.spec(.red, paint: 0, mood: .day).color)
        XCTAssertGreaterThan(red.0, red.1 * 4, "テールは濃い赤")
        XCTAssertLessThan(red.0, 0.6, "テールは濃い赤（明るい赤の板にしない）")
        let amber = CamperTextures.rgb(CamperMaterials.spec(.amber, paint: 0, mood: .day).color)
        XCTAssertTrue(amber.0 > amber.1 && amber.1 > amber.2, "方向指示は橙")
        XCTAssertEqual(CamperMaterials.spec(.red, paint: 0, mood: .day).texture, .prism)
        XCTAssertEqual(CamperMaterials.spec(.reflector, paint: 0, mood: .day).metalness, 1)
        // プリズムの粒: 升ごとに明るい面と暗い面がある（一色にしない）
        let p = CamperTextures.prism()
        XCTAssertGreaterThan(Int(p.pixel(4, 1).r) - Int(p.pixel(4, 6).r), 60)
    }

    /// 入口の灯り: 扉の上の壁の灯り（光る面）と、下向きの spot（減衰あり・影なし・2700K）が地面と扉の前を照らす。
    /// 外の部品だけを照らす組。バンには無い
    func testPorchLightFallsOnTheGround() {
        for stage in [CamperStage.camper, .trailer] {
            let b = build(stage, mood: .night)
            let builder = CamperBuilder(config: CamperConfig(stage: stage))
            guard let porch = b.lights.first(where: { $0.name == "porch" }) else { return XCTFail("\(stage): 入口の灯りが無い") }
            XCTAssertEqual(porch.kind, .spot)
            XCTAssertFalse(porch.inside, "外の部品を照らす組")
            XCTAssertFalse(porch.castsShadow, "影の計算を増やさない")
            XCTAssertLessThan(porch.direction.y, -0.8, "下を向く")
            XCTAssertGreaterThan(porch.direction.z, 0, "車の外へ")
            XCTAssertLessThanOrEqual(porch.range, 160, "減衰して遠くまで届かない")
            XCTAssertGreaterThan(porch.position.y, builder.doorHole.map { 62 - $0.y }.max() ?? 0, "扉の口の上")
            XCTAssertLessThan(porch.intensity, 1250 / 2, "室内の灯りより弱い")
            XCTAssertEqual(count(b, "ext.porchLamp"), 1)
            XCTAssertEqual(count(b, "ext.stepLamp"), 1)
        }
        XCTAssertNil(build(.van, mood: .night).lights.first { $0.name == "porch" })
        // 光る面は夜だけ光る電球の材質
        let lamp = build(mood: .night).nodes.first { $0.name == "ext.porchLamp" }
        XCTAssertNotNil(CamperMaterials.spec(lamp?.material ?? .black, paint: 0, mood: .night).emission)
        XCTAssertNil(CamperMaterials.spec(lamp?.material ?? .black, paint: 0, mood: .day).emission)
    }
}
