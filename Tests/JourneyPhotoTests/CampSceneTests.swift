import XCTest
@testable import JourneyPhoto

/// キャンプ場の島の立体（板 Camp・実装の指定「寸法」「回すときの注意」）と、12 の向きの計算
final class CampSceneTests: XCTestCase {

    // MARK: - 形の積み木

    func testTriangulateConcave() {
        // L の字（凹んだ 6 角形）
        let pts = [CampVec2(0, 0), CampVec2(4, 0), CampVec2(4, 1), CampVec2(1, 1), CampVec2(1, 3), CampVec2(0, 3)]
        let tris = CampGeometry.triangulate2D(pts)
        XCTAssertEqual(tris.count, 4)
        let area = tris.reduce(0.0) { s, t in
            s + abs(CampGeometry.area([pts[t.0], pts[t.1], pts[t.2]]))
        }
        XCTAssertEqual(area, abs(CampGeometry.area(pts)), accuracy: 1e-9, "三角に分けても面積が変わらない")
    }

    func testOffsetGrowsAndShrinks() {
        let square = [CampVec2(0, 0), CampVec2(10, 0), CampVec2(10, 10), CampVec2(0, 10)]
        XCTAssertGreaterThan(abs(CampGeometry.area(CampGeometry.outset(square, by: 1))), 100)
        XCTAssertEqual(abs(CampGeometry.area(CampGeometry.offset(square, -1))), 64, accuracy: 1e-6)
        // 板の面取りの輪は、左回りの外形では外へ出る（芝が壁より張り出す・板の島の形）
        XCTAssertGreaterThan(CampGeometry.area(square), 0)
        XCTAssertEqual(abs(CampGeometry.area(CampGeometry.bevelRing(square, by: 1))), 144, accuracy: 1e-6)
        let island = CampSceneBuilder.islandOutline(stage: .camp)
        XCTAssertGreaterThan(abs(CampGeometry.area(CampGeometry.bevelRing(island, by: 3.4))), abs(CampGeometry.area(island)))
    }

    /// 島の外形 9 点を丸めると 36 点（角ごとに 4）
    func testIslandOutline() {
        XCTAssertEqual(CampSceneBuilder.islandBase.count, 9)
        XCTAssertEqual(CampSceneBuilder.islandOutline(stage: .camp).count, 36)
        let small = CampSceneBuilder.islandOutline(stage: .fire)
        let big = CampSceneBuilder.islandOutline(stage: .camp)
        XCTAssertEqual(abs(CampGeometry.area(small)) / abs(CampGeometry.area(big)), 0.62 * 0.62, accuracy: 0.01)
    }

    /// 押し出した島は閉じていて、面がどれも外を向く（芝は上・壁は外・底は下）
    func testIslandFacesOutward() {
        let outline = CampSceneBuilder.islandOutline(stage: .camp)
        let bands = CampGeometry.extrudeY(outline, top: 0, bottom: 24, bevel: 3.4)
        XCTAssertEqual(Set(bands.keys), [0, 1, 2, 3, 4])
        for (key, mesh) in bands {
            XCTAssertFalse(mesh.isEmpty, "帯 \(key)")
            XCTAssertEqual(mesh.normals.count, mesh.positions.count)
            XCTAssertTrue(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
            for t in 0..<mesh.triangleCount {
                let a = mesh.positions[Int(mesh.indices[t * 3])], b = mesh.positions[Int(mesh.indices[t * 3 + 1])]
                let c = mesh.positions[Int(mesh.indices[t * 3 + 2])]
                let n = (b - a).cross(c - a)
                let mid = CampGeometry.centroid([a, b, c])
                XCTAssertGreaterThan(n.dot(mid - CampVec3(0, 12, 0)), 0, "帯 \(key) の三角 \(t) が内を向く")
            }
        }
        // 上の面の法線は上（板の y は下が正）
        XCTAssertTrue(bands[3]!.normals.allSatisfy { $0.y < -0.99 })
        // 壁の貼り絵の v は厚みの割合（地層の線 9 / 14 / 19 を描ける）
        XCTAssertTrue(bands[1]!.uvs.allSatisfy { $0.y >= 0 && $0.y <= 1 })
    }

    func testLatheFacesOutward() {
        let mesh = CampGeometry.lathe(origin: .zero, axis: CampVec3(0, -1, 0), profile: [(2, 0), (2, 10)], segments: 8)
        for (p, n) in zip(mesh.positions, mesh.normals) {
            XCTAssertGreaterThan(n.dot(CampVec3(p.x, 0, p.z)), 0, "筒の法線が内を向く")
        }
    }

    // MARK: - 場面

    private func scene(_ stage: CampStage = .tent, time: CampTime = .evening, season: CampSeason = .summer,
                       focus: CampFocus = .all, cutouts: [CampPlacedCutout] = [], placing: CampPlacedCutout? = nil) -> CampScene {
        CampSceneBuilder.build(CampSceneOptions(stage: stage, season: season, time: time, focus: focus, cutouts: cutouts,
                                                placing: placing))
    }

    private func cutout(_ id: String, spot: Int) -> CampPlacedCutout {
        CampPlacedCutout(id: id, layers: CampLayerSplit.fallback(unitHeight: 498), spot: spot)
    }

    /// 育ちで置く物が増える（焚き火 → テント場 → キャンプ場）
    func testStagesGrow() {
        let fire = scene(.fire)
        XCTAssertTrue(fire.pieces(in: .tent).isEmpty, "焚き火の段にテントは無い")
        XCTAssertTrue(fire.pieces(in: .path).isEmpty)
        XCTAssertFalse(fire.pieces(in: .fire).isEmpty)
        XCTAssertEqual(fire.pieces(in: .trees).filter { if case .pine = $0.material { return true }; return false }.count, 5, "木 1 本（5 段）")
        let tent = scene(.tent)
        XCTAssertFalse(tent.pieces(in: .tent).isEmpty)
        XCTAssertFalse(tent.pieces(in: .tentInside).isEmpty)
        XCTAssertEqual(tent.pieces(in: .path).count, 10, "飛び石 10")
        XCTAssertTrue(tent.pieces(in: .pond).isEmpty)
        XCTAssertTrue(tent.pieces(in: .table).isEmpty)
        XCTAssertEqual(tent.pieces(in: .trees).filter { if case .pine = $0.material { return true }; return false }.count, 10)
        let camp = scene(.camp)
        for g in [CampGroup.pond, .table, .lantern, .woodpile] { XCTAssertFalse(camp.pieces(in: g).isEmpty, g.rawValue) }
        XCTAssertEqual(camp.pieces(in: .trees).filter { if case .pine = $0.material { return true }; return false }.count, 15)
        XCTAssertEqual(camp.pieces(in: .woodpile).count, 6)
    }

    /// テントの中: 寝袋 2（キルトの線 4 ずつ）・枕 2・床・内幕
    func testTentInterior() {
        let inside = scene().pieces(in: .tentInside)
        XCTAssertEqual(inside.filter { $0.material == .pillow }.count, 2)
        XCTAssertEqual(inside.filter { $0.material == .bag1 || $0.material == .bag2 }.count, 2)
        XCTAssertEqual(inside.filter { $0.material == .quilt1 || $0.material == .quilt2 }.count, 8)
        XCTAssertEqual(inside.filter { $0.material == .innerFloor }.count, 1)
        XCTAssertTrue(inside.allSatisfy { !$0.castsShadow })
    }

    /// 扉は本当の穴: 表の妻壁のどの三角も扉の中ほど（扉の下から 10 の高さ）を覆わない。裏の妻壁は穴が無い
    func testTentDoorIsARealHole() {
        let s0 = CampStage.tent.scale
        let tp = CampSceneBuilder.tentPoint(s0)
        let hl = CampTentSpec.halfLength
        guard let front = scene().pieces(in: .tent).first(where: { $0.material == .tentEndFront }),
              case .mesh(let mesh) = front.shape else { return XCTFail("扉のある妻壁が無い") }
        let probe = tp(0, -10, hl)
        func covers(_ m: CampMesh, _ p: CampVec3) -> Bool {
            for t in 0..<m.triangleCount {
                let a = m.positions[Int(m.indices[t * 3])], b = m.positions[Int(m.indices[t * 3 + 1])]
                let c = m.positions[Int(m.indices[t * 3 + 2])]
                let n = (b - a).cross(c - a)
                let s1 = (b - a).cross(p - a).dot(n), s2 = (c - b).cross(p - b).dot(n), s3 = (a - c).cross(p - c).dot(n)
                if s1 >= 0 && s2 >= 0 && s3 >= 0 { return true }
            }
            return false
        }
        XCTAssertFalse(covers(mesh, probe), "扉の穴が塞がっている")
        XCTAssertTrue(covers(mesh, tp(-18, -3, hl)), "扉の横の壁が無い")
        guard let back = scene().pieces(in: .tent).first(where: { $0.material == .tentEnd }),
              case .mesh(let backMesh) = back.shape else { return XCTFail("裏の妻壁が無い") }
        XCTAssertTrue(covers(backMesh, tp(0, -10, -hl)), "裏の妻壁に穴がある")
    }

    /// フライは 6 × 4 の格子で、中央が 1.8 内へ沈む
    func testFlySags() {
        let rows = CampSceneBuilder.flyRows(side: 1, s0: 1)
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.allSatisfy { $0.count == 6 })
        let tp = CampSceneBuilder.tentPoint(1)
        // 中ほどの段の真ん中は、まっすぐな張りより内（テントの軸の側）にある
        let straight = CampVec3.mix(tp(CampTentSpec.halfWidth + 2, 1, 0), tp(0, -CampTentSpec.height, 0), 1.0 / 3)
        let center = tp(0, -12, 0)
        let mid = CampVec3.mix(rows[1][2], rows[1][3], 0.5)
        XCTAssertLessThan((mid - center).length, (straight - center).length)
    }

    /// 夜: 焚き火は芯＋広がり・テントの中の灯り。キャンプ場の夜はランタンも灯る。昼は焚き火 0.35
    func testNightLights() {
        let night = scene(time: .night)
        let fires = night.lights.filter { $0.position.x == CampLighting.firePosition.x && $0.position.z == CampLighting.firePosition.z }
        XCTAssertEqual(fires.count, 2, "夜の焚き火は芯と広がりの2つ")
        XCTAssertEqual(fires.map(\.intensity).max()!, 0.52, accuracy: 0.001)
        XCTAssertEqual(fires.map(\.range).min()!, 30, accuracy: 0.001)
        XCTAssertEqual(fires.map(\.range).max()!, CampLighting.fireFillRange, accuracy: 0.001)
        XCTAssertEqual(night.lights.count, 3, "焚き火2＋テントの中")
        guard let tentLamp = night.lights.first(where: { $0.position.x != CampLighting.firePosition.x || $0.position.z != CampLighting.firePosition.z }) else {
            return XCTFail("テントの中の灯りが無い")
        }
        XCTAssertEqual(tentLamp.intensity, 0.36, accuracy: 0.001)
        XCTAssertNotNil(night.sparks)
        XCTAssertNil(night.smoke, "夜は煙を出さない")
        let campNight = scene(.camp, time: .night)
        XCTAssertTrue(campNight.lights.contains { $0.position == CampLighting.lanternPosition })
        XCTAssertEqual(CampLighting.lanternIntensity, 0.32, accuracy: 0.001)
        let day = scene(time: .day)
        XCTAssertEqual(day.lights.filter { $0.position == CampLighting.firePosition }.count, 1)
        XCTAssertEqual(day.lights.first { $0.position == CampLighting.firePosition }?.intensity, 0.35)
        XCTAssertNil(day.sparks)
        XCTAssertEqual(day.flame?.height, 20)
    }

    /// 切り絵の箱庭: 1 つに 3 枚（表・裏・縁）・留め具 6・台 1。置く前は 9 浮いて、点線の輪と影が出る
    func testCutoutDiorama() {
        let s = scene(cutouts: [cutout("a", spot: 0)])
        let pieces = s.pieces(in: .cutout).filter { $0.cutout == "a" }
        XCTAssertEqual(pieces.filter { if case .cutoutFront = $0.material { return true }; return false }.count, 3)
        XCTAssertEqual(pieces.filter { $0.material == .paperBack }.count, 3)
        XCTAssertEqual(pieces.filter { $0.material == .paperEdge }.count, 3)
        XCTAssertEqual(pieces.filter { $0.material == .brass }.count, 6)
        XCTAssertEqual(pieces.filter { $0.material == .woodDark }.count, 1)
        XCTAssertNil(s.placeRing)
        // 紙の表は表の側（+nz）、裏は逆を向く
        if case .mesh(let front) = pieces.first(where: { $0.material == .cutoutFront("a", 0) })!.shape,
           case .mesh(let back) = pieces.first(where: { $0.material == .paperBack })!.shape {
            let ang = CampSceneBuilder.cutoutAngle * .pi / 180
            let nz = CampVec3(sin(ang), 0, cos(ang))
            XCTAssertGreaterThan(front.normals[0].dot(nz), 0.99)
            XCTAssertLessThan(back.normals[0].dot(nz), -0.99)
        } else {
            XCTFail("紙の形が網でない")
        }
        let placing = scene(cutouts: [cutout("a", spot: 0)], placing: cutout("b", spot: 0))
        XCTAssertTrue(placing.pieces(in: .cutout).allSatisfy { $0.cutout == "b" }, "同じ場所に置く前の切り絵だけ出す")
        XCTAssertNotNil(placing.placeRing)
        XCTAssertEqual(placing.placeRing?.rx, 34)
        XCTAssertEqual(placing.placeShadow?.rx, 30)
        let lifted = placing.pieces(in: .cutout).compactMap { p -> Double? in
            if case .box(let c, _, _, _, _, _) = p.shape, p.material == .woodDark { return c.y }
            return nil
        }
        XCTAssertEqual(lifted.first ?? 0, -2.2 - 9, accuracy: 1e-9, "置く前の箱庭が浮いていない")
    }

    /// 見せ方の絞り込み（部品の板・12 の向き）
    func testFocus() {
        let tent = scene(focus: .tent)
        XCTAssertTrue(tent.pieces(in: .rocks).isEmpty, "テントに寄った図は岩を出さない")
        XCTAssertTrue(tent.pieces(in: .fire).isEmpty)
        XCTAssertFalse(tent.pieces(in: .tent).isEmpty)
        let fire = scene(focus: .fire)
        XCTAssertTrue(fire.pieces(in: .tent).isEmpty)
        XCTAssertFalse(fire.pieces(in: .fire).isEmpty)
        XCTAssertFalse(fire.pieces(in: .island).isEmpty, "どの図も島は出す")
    }

    /// 冬: 草は出さず、岩とテントの屋根に雪
    func testWinter() {
        let w = scene(.camp, time: .day, season: .winter)
        XCTAssertTrue(w.pieces(in: .scatter).isEmpty)
        XCTAssertFalse(w.pieces.filter { $0.material == .snow && $0.group == .tent }.isEmpty)
        XCTAssertFalse(w.pieces.filter { $0.material == .snow && $0.group == .rocks }.isEmpty)
        XCTAssertEqual(CampMaterials.spec(.grass, season: .winter, time: .day).color, 0xE9EEF3)
        XCTAssertEqual(CampMaterials.spec(.pineUnder, season: .winter, time: .day).color, 0x8E9CA6)
    }

    /// 網はどれも番号が正しく、法線が点と同じ数
    func testAllMeshesAreWellFormed() {
        for s in [scene(), scene(.camp, time: .night), scene(.camp, season: .winter), scene(.fire, time: .morning)] {
            for p in s.pieces {
                guard case .mesh(let m) = p.shape else { continue }
                XCTAssertEqual(m.normals.count, m.positions.count)
                XCTAssertEqual(m.uvs.count, m.positions.count)
                XCTAssertTrue(m.colors.isEmpty || m.colors.count == m.positions.count)
                XCTAssertEqual(m.indices.count % 3, 0)
                XCTAssertTrue(m.indices.allSatisfy { $0 >= 0 && Int($0) < m.positions.count })
                XCTAssertTrue(m.normals.allSatisfy { abs($0.length - 1) < 1e-6 })
            }
        }
    }

    /// 針葉樹の段の裏は下を向く（下から見ても閉じている）
    func testPineUndersideFacesDown() {
        for p in scene().pieces where p.material == .pineUnder {
            guard case .mesh(let m) = p.shape else { continue }
            XCTAssertTrue(m.normals.allSatisfy { $0.y > 0 }, "段の裏が上を向いている")
        }
    }

    // MARK: - 時刻と季節・育ち

    func testClock() {
        XCTAssertEqual(CampClock.slot(hour: 4), .predawn)
        XCTAssertEqual(CampClock.slot(hour: 7), .morning)
        XCTAssertEqual(CampClock.slot(hour: 12), .day)
        XCTAssertEqual(CampClock.slot(hour: 17), .evening)
        XCTAssertEqual(CampClock.slot(hour: 22), .night)
        XCTAssertEqual(CampClock.slot(hour: 2), .night)
        XCTAssertEqual(CampClock.season(month: 3), .spring)
        XCTAssertEqual(CampClock.season(month: 8), .summer)
        XCTAssertEqual(CampClock.season(month: 11), .autumn)
        XCTAssertEqual(CampClock.season(month: 1), .winter)
        XCTAssertEqual(CampTime(slot: .predawn), .morning)
    }

    func testStageThresholds() {
        XCTAssertEqual(CampStage.stage(cutouts: 0), .fire)
        XCTAssertEqual(CampStage.stage(cutouts: 1), .tent)
        XCTAssertEqual(CampStage.stage(cutouts: 5), .tent)
        XCTAssertEqual(CampStage.stage(cutouts: 6), .camp)
        XCTAssertEqual(CampStage.remaining(cutouts: 2), 4)
        XCTAssertNil(CampStage.remaining(cutouts: 9))
        XCTAssertEqual(CampStage.fire.scale, 0.62)
        XCTAssertEqual(CampStage.tent.scale, 0.86)
    }

    /// 灯りの付箋の値（朝・昼・夕・夜と冬）
    func testLightingValues() {
        let morning = CampLighting.of(time: .morning, season: .summer)
        XCTAssertEqual(morning.ambient, 0.36)
        XCTAssertEqual(morning.shadow, 0x2A3A5A)
        let noon = CampLighting.of(time: .day, season: .summer)
        XCTAssertEqual(noon.diffuse, 0.6)
        XCTAssertEqual(noon.shadowOpacity, 0.42)
        let winter = CampLighting.of(time: .day, season: .winter)
        XCTAssertEqual(winter.ambient, 0.42 + 0.14, accuracy: 1e-9)
        XCTAssertEqual(winter.shadow, 0x3A5068)
        XCTAssertEqual(winter.shadowOpacity, 0.32)
        let night = CampLighting.of(time: .night, season: .summer)
        XCTAssertEqual(night.shadowOpacity, 0, "夜は落ち影を出さない")
        XCTAssertTrue(night.tentGlows)
        XCTAssertEqual(night.diffuse, 0.04, accuracy: 1e-9, "月は青白い縁光だけ")
        XCTAssertEqual(night.fireIntensity, 0.52, accuracy: 1e-9, "焚き火の芯")
        XCTAssertEqual(CampLighting.fireFillIntensity, 0.34, accuracy: 1e-9, "焚き火の広がり")
        XCTAssertEqual(night.fireGlow?.0, 54)
        XCTAssertEqual(CampLighting.of(time: .evening, season: .summer).fireGlow?.0, 46)
        XCTAssertNil(noon.fireGlow)
        XCTAssertEqual(night.mist, 0x1A2638)
        // テントは透光図つき（平らな橙の板にしない）
        let tent = CampMaterials.spec(.tentEnd, season: .summer, time: .night)
        XCTAssertEqual(tent.emissionTexture, .tentLit)
        XCTAssertEqual(tent.emissionIntensity, 0.55, accuracy: 1e-9)
        XCTAssertEqual(CampMaterials.spec(.fly, season: .summer, time: .night).emissionTexture, .tentLit)
        XCTAssertLessThanOrEqual(CampMaterials.spec(.glassLit, season: .summer, time: .night).emissionIntensity, 1)
    }

    // MARK: - 12 の向き・回す

    func testTwelveViews() {
        let views = CampView.all()
        XCTAssertEqual(views.map(\.number), Array(1...12))
        XCTAssertEqual(views[0].angle, CampAngle(rx: -30, ry: -36))
        XCTAssertEqual(views[1].angle, CampAngle(rx: -14, ry: 144))
        XCTAssertEqual(views[2].angle, CampAngle(rx: -8, ry: -100))
        XCTAssertEqual(views[3].angle, CampAngle(rx: -80, ry: -20))
        XCTAssertEqual(views[4].angle, CampAngle(rx: 18, ry: -30), "下の図だけ +18°")
        XCTAssertEqual(views[4].focus, .island)
        XCTAssertEqual(views[5].angle, CampAngle(rx: -18, ry: -40), "テントの寄りの既定")
        XCTAssertEqual(views[5].time, .day)
        XCTAssertEqual(views[6].angle.ry, 140)
        XCTAssertEqual(views[7].time, .night)
        XCTAssertEqual(views[9].angle, CampAngle(rx: -10, ry: 150))
        XCTAssertEqual(views[10].stage, .camp)
        XCTAssertEqual(views[11].season, .winter)
        XCTAssertEqual(views[11].time, .day)
    }

    /// 縦は −75°〜0°。指 1pt で横 0.6°・縦 0.4°
    func testDragging() {
        let a = CampOrbit.dragged(from: .resting, dx: 10, dy: 0)
        XCTAssertEqual(a.ry, -30, accuracy: 1e-9)
        XCTAssertEqual(CampOrbit.dragged(from: .resting, dx: 0, dy: -1000).rx, 0)
        XCTAssertEqual(CampOrbit.dragged(from: .resting, dx: 0, dy: 1000).rx, -75)
        XCTAssertEqual(CampOrbit.dragged(from: .resting, dx: 0, dy: 10).rx, -34, accuracy: 1e-9)
    }

    /// 板の投影を SceneKit のカメラに置き換える値（目の距離 = 900 / 倍率・画角 = 2 atan(H / 1800)）
    func testCameraMatchesBoardProjection() {
        XCTAssertEqual(CampOrbit.cameraDistance(scale: 1), 900)
        XCTAssertEqual(CampOrbit.cameraDistance(scale: 2), 450)
        XCTAssertEqual(CampOrbit.fieldOfView(height: 360), 2 * atan(0.2) * 180 / .pi, accuracy: 1e-9)
        // 寄る先は画面の真ん中に来る
        let p = CampOrbit.project(CampVec3(10, 20, 30), angle: CampAngle(rx: -30, ry: -36), target: CampVec3(10, 20, 30),
                                  scale: 1.2, width: 370, height: 360)
        XCTAssertEqual(p.x, 185, accuracy: 1e-9)
        XCTAssertEqual(p.y, 180, accuracy: 1e-9)
        // 板の座標の 1 単位は、原点の深さで scale px
        let q = CampOrbit.project(CampVec3(1, 0, 0), angle: CampAngle(rx: 0, ry: 0), target: .zero, scale: 2, width: 100, height: 100)
        XCTAssertEqual(q.x - 50, 2, accuracy: 1e-9)
        // SceneKit の回し方: 縦は逆・横はそのまま
        let e = CampOrbit.sceneEuler(CampAngle(rx: -30, ry: -36))
        XCTAssertEqual(e.pitch, 30 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(e.yaw, -36 * .pi / 180, accuracy: 1e-9)
        // 板の rX → SceneKit の Rx(−rx): y を返した点を回すと、回した点の y を返したものと一致する
        let v = CampVec3(3, 4, 5)
        let board = CampOrbit.toScene(v.rotatedY(-36).rotatedX(-30))
        let sv = CampOrbit.toScene(v)
        let yaw = -36.0 * .pi / 180, pitch = 30.0 * .pi / 180
        let ry = CampVec3(sv.x * cos(yaw) + sv.z * sin(yaw), sv.y, -sv.x * sin(yaw) + sv.z * cos(yaw))
        let rxv = CampVec3(ry.x, ry.y * cos(pitch) - ry.z * sin(pitch), ry.y * sin(pitch) + ry.z * cos(pitch))
        XCTAssertEqual(board.x, rxv.x, accuracy: 1e-9)
        XCTAssertEqual(board.y, rxv.y, accuracy: 1e-9)
        XCTAssertEqual(board.z, rxv.z, accuracy: 1e-9)
    }

    /// 夕の太陽はいつもの向きで空に見える（夜の月も）
    func testSunPlacement() {
        let dusk = CampLighting.of(time: .evening, season: .summer)
        let s = CampOrbit.sunOnScreen(light: dusk.sun, angle: .resting, width: 370, height: 360)
        XCTAssertTrue(s.visible)
        XCTAssertGreaterThan(s.x, 185, "夕日は右")
        XCTAssertEqual(CampFocus.all.zoom(stage: .fire), 1.3)
        XCTAssertEqual(CampOrbit.scale(focus: .all, stage: .camp, width: 370, height: 360), 0.94, accuracy: 1e-9)
    }
}
