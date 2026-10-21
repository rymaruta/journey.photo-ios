import Foundation

// 家具の形・2 の組（2026-10-19）。`CamperRoomFurnitureModels` と同じ決まり（実寸・面取り・ふくらみ・置物・座標）。
// 集める楽しさ（owner「部品もたくさん充実させて集める楽しさ必要」）のため、届く家具を増やす。

private typealias K = CamperRoomMeshKit
private func R(_ m: CamperRoomMaterial) -> CamperMaterial { .room(m) }

extension CamperRoomFurnitureModels {

    /// 2 の組の家具の形
    static func moreMesh(_ id: String) -> CamperMesh? {
        switch id {
        case "bed.bunk": return bunkBed()
        case "seating.wingback": return wingback()
        case "table.fold_down": return foldDownTable()
        case "storage.glass_cabinet": return glassCabinet()
        case "heater.pot_belly": return potBelly()
        case "room_rug.shag_round": return shagRug()
        case "floor_lamp.arc": return arcLamp()
        case "wall_shelf.cubby_grid": return cubbyGrid()
        case "wall_shelf.spice_rack": return spiceRack()
        case "photo_frame.triptych": return triptych()
        case "poster.map_poster": return mapPoster()
        case "wall_lamp.swing_arm": return swingArm()
        case "wall_lamp.candle_sconce": return candleSconce()
        case "clock.cuckoo": return cuckooClock()
        case "clock.sunburst": return sunburstClock()
        case "clock.flip": return flipClock()
        case "string_ceiling.fairy_net": return fairyNet()
        case "string_ceiling.paper_garland": return paperGarland()
        case "mobile.paper_cranes": return paperCranes()
        case "mobile.star_mobile": return starMobile()
        case "mobile.driftwood": return driftwood()
        case "plant_hanger.air_ring": return airRing()
        case "roof_hatch.round_hatch": return roundHatch()
        case "roof_hatch.star_window": return starWindow()
        case "roof_hatch.stained_glass": return stainedGlass()
        default: return moreMesh3(id)
        }
    }

    /// 2 の組の灯り
    static func moreLamp(_ id: String) -> (position: CV3, intensity: Double, range: Double)? {
        switch id {
        case "heater.pot_belly": return (CV3(0, 12, 8), 0.35, 55)
        case "floor_lamp.arc": return (CV3(0, 72, 15), 0.7, 85)
        case "wall_lamp.swing_arm": return (CV3(0, 12, 12), 0.45, 70)
        case "wall_lamp.candle_sconce": return (CV3(0, 16, 5), 0.18, 45)
        case "string_ceiling.fairy_net": return (CV3(0, -14, 0), 0.4, 70)
        default: return moreLamp3(id)
        }
    }

    // MARK: 床

    /// 二段寝台（ナラの柱 4・上下の床と布団・上の転落防止の柵・横のはしご 5 段）
    static func bunkBed() -> CamperMesh {
        let oak = R(.wood(.oak)), worn = R(.wornWood(.oak))
        var parts: [CamperMesh] = []
        for (x, z) in [(-38.5, -18.5), (38.5, -18.5), (-38.5, 18.5), (38.5, 18.5)] {
            parts.append(K.block(CV3(3, 78, 3), at: CV3(x, 0, z), radius: 0.6, worn))
            parts.append(K.placed(K.sphere(radius: 1.6, segments: 10, oak), at: CV3(x, 78.8, z)))
        }
        for y in [8.0, 46.0] {
            for z in [-18.8, 18.8] { parts.append(K.block(CV3(74, 5, 2.2), at: CV3(0, y, z), radius: 0.6, oak)) }
            for x in [-38.5, 38.5] { parts.append(K.block(CV3(2.2, 5, 35), at: CV3(x, y, 0), radius: 0.6, oak)) }
            parts.append(K.placed(K.roundedBox(CV3(73, 4.4, 35), radius: 2, segments: 3, puff: 0.5, R(.cotton(0xE8E1D2))), at: CV3(0, y + 6.4, 0)))
            parts.append(K.placed(K.roundedBox(CV3(46, 2.6, 36.5), radius: 1.2, segments: 3, puff: 0.8, sidePuff: 0.5,
                                               R(.linen(y < 20 ? 0x8C6E5A : 0x5E7A8C))), at: CV3(12, y + 9.6, 0)))
            parts.append(K.placed(K.roundedBox(CV3(11, 3.2, 15), radius: 1.5, segments: 3, puff: 1.1, R(.linen(0xF1EDE4))), at: CV3(-29, y + 10, 0)))
        }
        // 上の柵（扉の側）とはしご
        parts.append(K.block(CV3(50, 2, 2), at: CV3(-12, 62, 18.8), radius: 0.5, oak))
        for x in [-36.0, 12.0] { parts.append(K.block(CV3(2, 10, 2), at: CV3(x, 52, 18.8), radius: 0.4, oak)) }
        for x in [22.0, 32.0] { parts.append(K.block(CV3(2.2, 66, 2.6), at: CV3(x, 0, 20.4), radius: 0.5, worn)) }
        for k in 0..<5 {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.8, 0), CV2(0.8, 10), CV2(0, 10)], segments: 10, worn),
                                  at: CV3(32, 10 + Double(k) * 11, 20.4), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2)))
        }
        return K.merge(parts)
    }

    /// 耳付きの椅子（ふくらんだ座と背・両脇の耳・巻いた肘・釦の綴じ・縁の玉縁・挽いた木の脚）
    static func wingback() -> CamperMesh {
        let cloth = R(.velvet(0x2F4A5E)), dark = R(.velvet(0x243A4A))
        var parts: [CamperMesh] = []
        for (x, z) in [(-9.0, -9.0), (9.0, -9.0), (-9.0, 9.0), (9.0, 9.0)] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.7, 0), CV2(0.9, 1.2), CV2(1.2, 2.6), CV2(0.9, 4), CV2(1.1, 5.4), CV2(0, 5.4)],
                                          segments: 12, R(.wood(.walnut))), at: CV3(x, 0, z)))
        }
        parts.append(K.placed(K.roundedBox(CV3(24, 8, 22), radius: 1.6, segments: 3, sidePuff: 0.4, cloth), at: CV3(0, 9.4, 0.5)))
        parts.append(K.placed(K.roundedBox(CV3(19, 4.4, 18), radius: 1.8, segments: 3, puff: 1.2, cloth), at: CV3(0, 15.2, 2.5)))
        // 背（後ろへ少し倒す）と釦
        let tilt = CQuat.axisAngle(CV3(1, 0, 0), -0.12)
        parts.append(K.placed(K.roundedBox(CV3(22, 30, 5), radius: 2, segments: 3, sidePuff: 0.8, cloth), at: CV3(0, 30, -9.5), rotation: tilt))
        for (bx, by) in [(-5.0, 6.0), (5.0, 6.0), (0.0, 0.0), (-5.0, -6.0), (5.0, -6.0)] {
            parts.append(K.placed(K.sphere(radius: 0.45, segments: 8, dark), at: CV3(0, 30, -9.5) + tilt.rotate(CV3(bx, by, 2.9))))
        }
        // 耳（両脇の張り出し）と巻いた肘
        for s in [-1.0, 1.0] {
            let wing = CQuat.axisAngle(CV3(0, 1, 0), s * 0.32)
            parts.append(K.placed(K.roundedBox(CV3(3.6, 18, 9), radius: 1.6, segments: 3, sidePuff: 0.5, cloth), at: CV3(s * 10.6, 34, -5.5),
                                  rotation: wing))
            parts.append(K.placed(K.roundedBox(CV3(3.4, 9, 18), radius: 1.6, segments: 3, cloth), at: CV3(s * 10.8, 17.8, 1)))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.4, 0), CV2(2.4, 19), CV2(0, 19)], segments: 16, cloth), at: CV3(s * 10.8, 22.4, -8.5),
                                  rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
            parts.append(K.tube((0...12).map { k -> CV3 in
                let a = Double(k) / 12 * 2 * .pi
                return CV3(s * 10.8 + s * 0.2, 22.4 + sin(a) * 2.5, 10.6 + cos(a) * 2.5 * 0.2)
            }, radius: 0.3, sides: 5, closed: true, dark))
        }
        // 玉縁（座の前の縁）
        parts.append(K.tube([CV3(-11.8, 13.3, 11.6), CV3(11.8, 13.3, 11.6)], radius: 0.4, sides: 6, dark))
        return K.merge(parts)
    }

    /// 壁の折り畳み机（壁の桟とヒンジ・倒した天板の木口・折れる腕 2・カップ）
    static func foldDownTable() -> CamperMesh {
        var parts: [CamperMesh] = []
        let birch = R(.wood(.birch)), worn = R(.wornWood(.birch)), chrome = R(.chrome)
        // 壁の桟（ヒンジ穴の金具つき）
        parts.append(K.block(CV3(38, 4.2, 2.2), at: CV3(0, 27, -9), radius: 0.4, birch))
        for x in [-16.0, -5.0, 5.0, 16.0] {
            parts.append(K.block(CV3(1.8, 1.4, 0.7), at: CV3(x, 28.2, -7.9), radius: 0.15, chrome))
        }
        // 天板（上面・木口の縁）
        parts.append(K.block(CV3(37.2, 1.5, 16.4), at: CV3(0, 28.5, -1.4), radius: 0.45, worn))
        parts.append(K.block(CV3(37.6, 0.45, 0.55), at: CV3(0, 28.2, 6.7), radius: 0.12, birch))
        parts.append(K.block(CV3(37.6, 0.45, 0.55), at: CV3(0, 28.2, -9.4), radius: 0.12, birch))
        for x in [-18.2, 18.2] {
            parts.append(K.block(CV3(0.5, 0.45, 16.2), at: CV3(x, 28.2, -1.4), radius: 0.1, birch))
        }
        // 折れる腕（継ぎ目の球・壁金具）
        for x in [-14.0, 14.0] {
            parts.append(K.block(CV3(2.2, 4.2, 0.7), at: CV3(x, 12, -9.6), radius: 0.2, chrome))
            parts.append(K.tube([CV3(x, 14, -9.4), CV3(x, 21, -3), CV3(x, 28.2, 4)], radius: 0.48, sides: 8, chrome))
            parts.append(K.placed(K.sphere(radius: 0.85, segments: 10, chrome), at: CV3(x, 21, -3)))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.7, 0), CV2(0.65, 0.4), CV2(0, 0.4)], segments: 10, R(.agedBrass)),
                                  at: CV3(x, 21, -3)))
        }
        parts.append(CamperRoomShapes.mug(at: CV3(6, 29.4, 0), body: R(.ceramic(0xC9B79A)), rim: R(.ceramic(0xB09A78)), yaw: 1.2))
        return K.merge(parts)
    }

    /// 硝子戸の棚（脚・下は鏡板の木の戸・上は格子の硝子戸・中の棚に皿と器・上の笠木）
    static func glassCabinet() -> CamperMesh {
        let teak = R(.wood(.teak)), worn = R(.wornWood(.teak))
        var parts: [CamperMesh] = []
        for (x, z) in [(-12.5, -7.5), (12.5, -7.5), (-12.5, 7.5), (12.5, 7.5)] {
            parts.append(K.placed(K.leg(bottom: 0.8, top: 1.2, height: 5, teak), at: CV3(x, 0, z)))
        }
        parts.append(K.block(CV3(28, 2, 17), at: CV3(0, 5, 0), radius: 0.4, teak))
        // 箱（横板 2・背板・上下）
        for x in [-13.4, 13.4] { parts.append(K.block(CV3(1.2, 61, 16), at: CV3(x, 7, 0), radius: 0.3, teak)) }
        parts.append(K.block(CV3(26, 61, 0.8), at: CV3(0, 7, -7.6), radius: 0.2, R(.wood(.walnut))))
        parts.append(K.block(CV3(30, 2.4, 18.4), at: CV3(0, 68, 0.2), radius: 0.6, worn))
        // 下の戸（鏡板・取っ手）
        for x in [-6.6, 6.6] {
            parts.append(K.block(CV3(12.8, 22, 1), at: CV3(x, 7.4, 7.9), radius: 0.3, teak))
            parts.append(K.block(CV3(9, 17, 0.5), at: CV3(x, 9.9, 8.4), radius: 0.4, worn))
            parts.append(K.placed(K.sphere(radius: 0.7, segments: 8, R(.agedBrass)), at: CV3(x > 0 ? 1.6 : -1.6, 22, 8.8)))
        }
        parts.append(K.block(CV3(26, 1.2, 15), at: CV3(0, 29.6, 0), radius: 0.3, teak))
        parts.append(K.block(CV3(26, 1, 14), at: CV3(0, 47.5, -0.5), radius: 0.3, teak))
        // 皿（立てた 3 枚）と碗・瓶
        for (k, x) in [-8.0, -4.5, -1.0].enumerated() {
            parts.append(K.placed(K.disc(radius: 4.2, height: 0.5, bevel: 0.2, segments: 24, R(.ceramic(k == 1 ? 0x6E8FA3 : 0xEDE8DE))),
                                  at: CV3(x, 35, -5), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2 - 0.25)))
        }
        for x in [4.0, 9.0] {
            parts.append(K.placed(K.vessel(outer: [CV2(0, 0), CV2(1.4, 0), CV2(2.6, 2.4)], inner: [CV2(0, 0.4), CV2(1.2, 0.4), CV2(2.4, 2.4)],
                                           segments: 18, R(.ceramic(0xC97A4A))), at: CV3(x, 30.8, 0)))
        }
        for (x, c) in [(-6.0, 0x5E7A5A as UInt32), (2.0, 0x8A5A3A)] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.8, 0), CV2(1.9, 6), CV2(0.8, 7.6), CV2(0.8, 9), CV2(0, 9)], segments: 16,
                                          R(.tintedGlass(c))), at: CV3(x, 48.5, 0)))
        }
        // 上の硝子戸（格子の枠・硝子）
        for x in [-6.6, 6.6] {
            let frame = K.roundedRect(12.8, 36, r: 0.3)
            let hole = CamperPolygon.cw(K.roundedRect(10.4, 33.6, r: 0.2))
            parts.append(K.placed(CamperMeshKit.extrude(frame, holes: [hole], depth: 1, front: teak, side: teak, bevel: 0.25), at: CV3(x, 49, 8.6)))
            parts.append(K.block(CV3(10.4, 0.6, 0.6), at: CV3(x, 48.7, 8.2), radius: 0.15, teak))
            parts.append(K.block(CV3(0.6, 33.6, 0.6), at: CV3(x, 32.2, 8.2), radius: 0.15, teak))
            parts.append(K.placed(K.panel(width: 10.4, height: 33.6, R(.glass)), at: CV3(x, 49, 8.0)))
        }
        return K.merge(parts)
    }

    /// だるまストーブ（鋳物の丸い胴・ふくらんだ腹・小さな雲母の窓・上の蓋と煙突・猫脚 3）
    static func potBelly() -> CamperMesh {
        let iron = R(.castIron)
        var parts: [CamperMesh] = []
        parts.append(K.disc(radius: 9.8, height: 0.9, bevel: 0.3, segments: 32, R(.countertop)))
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi + .pi / 2
            parts.append(K.tube([CV3(cos(a) * 4.5, 5, sin(a) * 4.5), CV3(cos(a) * 6.2, 2.4, sin(a) * 6.2), CV3(cos(a) * 7, 0.9, sin(a) * 7)],
                                radius: 0.9, sides: 8, iron))
        }
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(5.6, 0), CV2(6.2, 1.2), CV2(5.6, 2.4), CV2(7.8, 6), CV2(8.6, 9.6), CV2(7.8, 13.6),
                                       CV2(6, 16.4), CV2(6.6, 17.2), CV2(6.6, 18.4), CV2(4.6, 19), CV2(3, 19.6), CV2(0, 19.6)], segments: 32, iron),
                              at: CV3(0, 4.4, 0)))
        // 窓（腹の前・雲母と奥の火）と枠・つまみ
        parts.append(K.placed(K.panel(width: 4.6, height: 3.6, R(.fire)), at: CV3(0, 13.6, 7.5)))
        parts.append(K.placed(K.panel(width: 4.8, height: 3.8, R(.mica)), at: CV3(0, 13.6, 8.55)))
        parts.append(K.tube(K.roundedRect(5.4, 4.4, r: 0.6).map { CV3($0.x, 13.6 + $0.y, 8.65) }, radius: 0.35, sides: 6, closed: true, iron))
        parts.append(K.placed(K.sphere(radius: 0.55, segments: 8, R(.agedBrass)), at: CV3(3.4, 13.6, 8.9)))
        // 腹の帯（2 本の輪）
        for y in [9.0, 18.0] {
            parts.append(K.tube(K.arc(center: .zero, radius: y < 10 ? 8.15 : 7.9, from: 0, to: 2 * .pi, steps: 32).map { CV3($0.x, y, $0.y) },
                                radius: 0.35, sides: 6, closed: true, iron))
        }
        // 煙突（真上へ天井まで）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.4, 0), CV2(2.4, 64), CV2(0, 64)], segments: 20, R(.iron), capStart: false, capEnd: false),
                              at: CV3(0, 24, 0)))
        for y in [40.0, 64.0] { parts.append(K.placed(K.disc(radius: 2.7, height: 0.8, bevel: 0.2, segments: 20, R(.iron)), at: CV3(0, y, 0))) }
        parts.append(K.placed(K.disc(radius: 4, height: 0.8, bevel: 0.2, segments: 20, R(.iron)), at: CV3(0, 87.2, 0)))
        return K.merge(parts)
    }

    /// 毛足の丸（生成りの丸い敷物・縁がふさふさ）
    /// 毛足の丸（芯の編み・縁のふさ・内側の輪）
    static func shagRug() -> CamperMesh {
        let outline = (0..<48).map { k -> CV2 in
            let a = Double(k) / 48 * 2 * .pi
            return CV2(cos(a) * 17.8, sin(a) * 17.8)
        }
        var parts = [K.rug(outline, thickness: 1.35, top: R(.knit(0xE6DCC8)), edge: R(.knit(0xD8CDB8)))]
        // 内側の薄い輪（模様）
        parts.append(K.tube(K.arc(center: .zero, radius: 10.5, from: 0, to: 2 * .pi, steps: 40)
                                .map { CV3($0.x, 1.25, $0.y) }, radius: 0.35, sides: 5, closed: true, R(.knit(0xC9B89A))))
        parts.append(K.tube(K.arc(center: .zero, radius: 5.2, from: 0, to: 2 * .pi, steps: 28)
                                .map { CV3($0.x, 1.3, $0.y) }, radius: 0.28, sides: 5, closed: true, R(.knit(0xB8A888))))
        for k in 0..<128 {
            let a = Double(k) / 128 * 2 * .pi + (k % 2 == 0 ? 0 : 0.025)
            let r = 17.4 + Double(k % 4) * 0.28
            let base = CV3(cos(a) * r, 1.05, sin(a) * r)
            let out = CV3(cos(a), 0, sin(a))
            let side = CV3(-sin(a), 0, cos(a)) * (Double(k % 5) - 2) * 0.14
            let len = 1.6 + Double(k % 3) * 0.35
            parts.append(K.tube([base, base + out * len * 0.55 + side + CV3(0, 0.35, 0),
                                 base + out * len + side * 1.5 + CV3(0, -0.55, 0)],
                                radius: 0.26, sides: 4, cap: false, R(.knit(k % 4 == 0 ? 0xD8CDB8 : 0xE6DCC8))))
        }
        return K.merge(parts)
    }

    /// 弧の灯り（重い台・継ぎ輪・大きな弧の腕・アルミ笠・電球・コード）。腕は高い所で隣の家具の上へ張り出す
    static func arcLamp() -> CamperMesh {
        var parts: [CamperMesh] = []
        let chrome = R(.chrome), marble = R(.ceramic(0xE4E0D8))
        // 重い台（縁の面取り・フェルト足）
        parts.append(K.block(CV3(12.5, 3.6, 12.5), at: CV3(0, 0, -4), radius: 1.1, marble))
        parts.append(K.block(CV3(11.2, 0.45, 11.2), at: CV3(0, 3.4, -4), radius: 0.35, R(.ceramic(0xD4D0C8))))
        for (x, z) in [(-4.5, -8.0), (4.5, -8.0), (-4.5, 0.0), (4.5, 0.0)] {
            parts.append(K.placed(K.disc(radius: 0.7, height: 0.25, bevel: 0.08, segments: 10, R(.knit(0x2A2A2C))),
                                  at: CV3(x, -0.05, z)))
        }
        // 台から立ち上がって天井の手前で弧を描き、前へ下りる
        let path = (0...32).map { k -> CV3 in
            let t = Double(k) / 32
            return CV3(0, 3.6 + 78 * sin(t * .pi * 0.62), -6.2 + 22 * t * t)
        }
        parts.append(K.tube(path, radius: 0.58, sides: 12, chrome))
        // 継ぎ輪
        for i in [0, 8, 16, 24] {
            let p = path[i]
            parts.append(K.placed(K.disc(radius: 0.85, height: 0.35, bevel: 0.1, segments: 12, R(.agedBrass)), at: p))
        }
        let tip = path.last!
        // 笠の継ぎと笠
        parts.append(K.placed(K.sphere(radius: 0.7, segments: 10, chrome), at: tip))
        parts.append(K.placed(K.lathe([CV2(0.9, 0), CV2(1.9, -0.35), CV2(5.6, -4.0), CV2(7.4, -7.0)], segments: 32,
                                      R(.sinkSteel), capStart: false, capEnd: false), at: tip + CV3(0, 1.8, 0)))
        parts.append(K.placed(K.inverted(K.lathe([CV2(0.8, -0.15), CV2(1.8, -0.5), CV2(5.4, -4.1), CV2(7.2, -7.0)],
                                                 segments: 32, R(.painted(0xF2EEE6)), capStart: false, capEnd: false)),
                              at: tip + CV3(0, 1.8, 0)))
        parts.append(K.tube(K.arc(center: tip + CV3(0, -5.0, 0), radius: 7.15, from: 0, to: 2 * .pi, steps: 28)
                                .map { CV3($0.x, tip.y - 5.0, $0.y) }, radius: 0.15, sides: 5, closed: true, R(.agedBrass)))
        parts.append(K.placed(K.sphere(radius: 1.85, segments: 16, R(.bulb)), at: tip + CV3(0, -2.6, 0)))
        // 台から垂れるコード（低い所はマス内に収める）
        parts.append(K.tube([CV3(0, 3.6, -4), CV3(2.2, 1.4, -2.5), CV3(3.8, 0.35, -0.5), CV3(4.2, 0.2, 1.5)],
                            radius: 0.12, sides: 5, R(.painted(0x1A1A1A))))
        return K.merge(parts)
    }

    // MARK: 壁

    /// 升目の棚（樺の合板 3×3・中に本と瓶と鉢と畳んだ布）
    static func cubbyGrid() -> CamperMesh {
        let ply = R(.wood(.birch))
        var parts: [CamperMesh] = []
        let w = 19.0, h = 19.0, d = 8.0, t = 0.9, y0 = 10.0
        parts.append(K.block(CV3(w, h, 0.5), at: CV3(0, y0, 0.25), radius: 0.1, R(.wood(.oak))))
        for x in [-w / 2 + t / 2, w / 2 - t / 2, -w / 6 + 0.15, w / 6 - 0.15] {
            parts.append(K.block(CV3(t, h, d), at: CV3(x, y0, d / 2), radius: 0.2, ply))
        }
        for y in [y0, y0 + h - t, y0 + h / 3, y0 + 2 * h / 3] {
            parts.append(K.block(CV3(w, t, d), at: CV3(0, y, d / 2), radius: 0.2, ply))
        }
        let cw = w / 3
        // 本（左上）・瓶（真ん中）・鉢（右下）・畳んだ布（左下）・横に寝かせた本（右上）
        for k in 0..<4 {
            parts.append(K.block(CV3(1, 4.6 - Double(k % 2) * 0.6, 4.6), at: CV3(-cw - 2.2 + Double(k) * 1.1, y0 + 2 * h / 3 + t / 2, 3.8), radius: 0.15,
                                 R(.painted([0x7A2E22, 0xD9CDB4, 0x2F4F74, 0x3E5A3C][k]))))
        }
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.3, 0), CV2(1.4, 3.4), CV2(0.9, 4), CV2(0.9, 4.6), CV2(0, 4.6)], segments: 14,
                                      R(.tintedGlass(0xB8925E))), at: CV3(0, y0 + h / 3 + t / 2, 4)))
        parts.append(CamperRoomShapes.pottedPlant(at: CV3(cw, y0 + t / 2, 4), potRadius: 1.5, height: 2.4, leaves: 5, spread: 2.2))
        parts.append(K.placed(K.roundedBox(CV3(4.8, 2.2, 5.6), radius: 0.6, segments: 2, puff: 0.3, R(.knit(0xB5653F))),
                              at: CV3(-cw, y0 + t / 2 + 1.1, 4)))
        parts.append(K.placed(K.roundedBox(CV3(4.6, 0.9, 5.2), radius: 0.15, segments: 1, R(.painted(0x8A6A3A))), at: CV3(cw, y0 + 2 * h / 3 + t / 2 + 0.45, 4)))
        return K.merge(parts)
    }

    /// 小瓶の棚（木の枠・桟 3 段・小瓶 18（中身の色・木の栓））
    static func spiceRack() -> CamperMesh {
        var parts: [CamperMesh] = []
        for x in [-9.4, 9.4] { parts.append(K.block(CV3(1, 17, 4.4), at: CV3(0, 1.5, 2.2) + CV3(x, 0, 0), radius: 0.25, R(.wood(.oak)))) }
        let colors: [UInt32] = [0x9A3A1E, 0xD9A441, 0x5E7A3A, 0x7A4A2A, 0xC9C0A8, 0x3E2A1E]
        for row in 0..<3 {
            let y = 2.0 + Double(row) * 5.4
            parts.append(K.block(CV3(18, 0.7, 4.2), at: CV3(0, y, 2.2), radius: 0.15, R(.wood(.oak))))
            parts.append(K.tube([CV3(-9, y + 2.2, 4.3), CV3(9, y + 2.2, 4.3)], radius: 0.18, sides: 5, R(.brass)))
            for k in 0..<6 {
                let x = -7.5 + Double(k) * 3
                let at = CV3(x, y + 0.7, 2.2)
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.1, 0), CV2(1.15, 2.8), CV2(0.7, 3.3), CV2(0, 3.3)], segments: 12, R(.glass)), at: at))
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.95, 0), CV2(0.95, 2.2), CV2(0, 2.2)], segments: 10,
                                              R(.linen(colors[(row * 6 + k) % colors.count]))), at: at + CV3(0, 0.1, 0)))
                parts.append(K.placed(K.disc(radius: 0.75, height: 0.7, bevel: 0.2, segments: 10, R(.wood(.cedar))), at: at + CV3(0, 3.2, 0)))
            }
        }
        return K.merge(parts)
    }

    /// 三枚続きの額（細い黒い枠 3・マット・1 枚の写真を 3 つに分けて一つの景色に・蝶番）
    static func triptych() -> CamperMesh {
        var parts: [CamperMesh] = []
        for i in 0..<3 {
            let x = -12.6 + Double(i) * 12.6
            let c = CV3(x, 10, 0)
            // 共通の額は slot0 を1枚置くので、ここでは枠・マット・硝子だけ自前で組み、写真は UV 分割の1面だけ
            let depth = 1.35, rim = 1.0
            let outer = CV2(11.6, 13.6), photo = CV2(8.4, 10.2)
            let inner = CV2(outer.x - rim * 2, outer.y - rim * 2)
            // 外枠は薄いモールディングだけ（深いトンネルにしない・共通額と同じ）
            let mould = min(0.5, max(0.32, depth * 0.32))
            let ring = K.roundedRect(outer.x, outer.y, r: 0.45, steps: 3)
            let hole = CamperPolygon.cw(K.roundedRect(inner.x, inner.y, r: 0.3, steps: 2))
            parts.append(K.placed(CamperMeshKit.extrude(ring, holes: [hole], depth: mould, front: R(.painted(0x1C1B1A)),
                                                        side: R(.painted(0x1C1B1A)), bevel: 0.22), at: c + CV3(0, 0, depth)))
            parts.append(K.placed(K.panel(width: outer.x - 0.4, height: outer.y - 0.4, R(.painted(0x3A3430))), at: c + CV3(0, 0, 0.06)))
            parts.append(K.placed(K.panel(width: inner.x + 0.15, height: inner.y + 0.15, R(.mat)), at: c + CV3(0, 0, depth - 0.85)))
            parts.append(K.placed(K.panel(width: photo.x + 0.1, height: photo.y + 0.1, R(.paper)), at: c + CV3(0, 0, depth - 0.62)))
            let matOuter = K.roundedRect(photo.x + 1.4, photo.y + 1.4, r: 0.3, steps: 2)
            let matHole = CamperPolygon.cw(K.roundedRect(photo.x + 0.2, photo.y + 0.2, r: 0.15, steps: 2))
            parts.append(K.placed(CamperMeshKit.extrude(matOuter, holes: [matHole], depth: 0.08, front: R(.mat), side: R(.paper), bevel: 0.06),
                                  at: c + CV3(0, 0, depth - 0.48)))
            var panel = K.panel(width: photo.x, height: photo.y, photoMaterial(0))
            panel.uvs = panel.uvs.map { CV2((Double(i) + $0.x) / 3, $0.y) }
            parts.append(K.placed(panel, at: c + CV3(0, 0, depth - 0.36)))
            parts.append(K.placed(K.panel(width: inner.x + 0.1, height: inner.y + 0.1, R(.frameGlass)), at: c + CV3(0, 0, depth - 0.22)))
        }
        for x in [-6.3, 6.3] {
            for y in [6.0, 14.0] {
                parts.append(K.block(CV3(1.2, 1.6, 0.7), at: CV3(x, y, 1.6), radius: 0.15, R(.brass)))
            }
        }
        return K.merge(parts)
    }

    /// 旅の地図（波打つ紙・道の線・旅の点・画鋲 4・折り目）
    static func mapPoster() -> CamperMesh {
        var parts: [CamperMesh] = []
        let c = CV3(0, 20, 0.15)
        parts.append(K.placed(CamperRoomShapes.paperSheet(width: 27.5, height: 18.5, curl: 1.0, R(.mapPrint)), at: c))
        // 折り目
        parts.append(K.tube([c + CV3(-12, 0, 0.2), c + CV3(12, 0, 0.25)], radius: 0.06, sides: 4, R(.paper)))
        parts.append(K.tube([c + CV3(0, -8, 0.2), c + CV3(0, 8, 0.22)], radius: 0.06, sides: 4, R(.paper)))
        // 道（細い管）と点
        let roads: [[CV3]] = [
            [c + CV3(-10, -5, 0.28), c + CV3(-3, -1, 0.3), c + CV3(4, 2, 0.28), c + CV3(10, 5, 0.3)],
            [c + CV3(-8, 6, 0.28), c + CV3(-2, 3, 0.3), c + CV3(3, -2, 0.28), c + CV3(9, -6, 0.3)]
        ]
        for road in roads {
            parts.append(K.tube(road, radius: 0.14, sides: 5, R(.linen(0x8A5A3A))))
        }
        for (dx, dy) in [(-9.0, -4.0), (-1.0, 2.5), (5.0, -3.0), (9.5, 4.5), (2.0, 6.0)] {
            parts.append(K.placed(K.sphere(radius: 0.35, segments: 8, R(.enamel(0xB0291F))), at: c + CV3(dx, dy, 0.4)))
        }
        for (dx, dy) in [(-12.8, 8.4), (12.8, 8.4), (-12.8, -8.4), (12.8, -8.4)] {
            parts.append(K.placed(K.disc(radius: 0.6, height: 0.55, bevel: 0.2, segments: 12, R(.enamel(0xB0291F))),
                                  at: c + CV3(dx, dy, 0.35), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
            parts.append(K.placed(K.sphere(radius: 0.22, segments: 6, R(.agedBrass)), at: c + CV3(dx, dy, 0.7)))
        }
        return K.merge(parts)
    }

    /// 腕の灯り（ビス付きの座・継ぎ目の輪・琺瑯の笠・縁リング・引き鎖）
    static func swingArm() -> CamperMesh {
        var parts: [CamperMesh] = []
        let brass = R(.brass), enamel = R(.enamel(0x2F5A3C))
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(K.disc(radius: 2.4, height: 0.75, bevel: 0.25, segments: 20, brass), at: CV3(0, 9, 0.05), rotation: toWall))
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + .pi / 4
            parts.append(K.placed(K.sphere(radius: 0.22, segments: 6, R(.agedBrass)),
                                  at: CV3(cos(a) * 1.7, 9 + sin(a) * 1.7, 0.55)))
        }
        let j1 = CV3(2.5, 9.6, 5.5), j2 = CV3(-1, 12.6, 10)
        parts.append(K.tube([CV3(0, 9, 0.75), j1], radius: 0.4, sides: 8, brass))
        parts.append(K.tube([j1, j2], radius: 0.4, sides: 8, brass))
        for j in [j1, j2] {
            parts.append(K.placed(K.sphere(radius: 0.75, segments: 10, brass), at: j))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.7, 0), CV2(0.65, 0.35), CV2(0, 0.35)], segments: 10, R(.agedBrass)), at: j))
        }
        let q = CQuat.rotation(from: CV3(0, -1, 0), to: CV3(0.1, -1, 0.45))
        let outer: [CV2] = [CV2(0.9, 0), CV2(1.5, -0.8), CV2(3.0, -3.0), CV2(3.6, -4.4)]
        let top = j2 + CV3(0, 1.0, 0.6)
        parts.append(K.placed(K.lathe(outer, segments: 24, enamel, capStart: false, capEnd: false), at: top, rotation: q))
        parts.append(K.placed(K.inverted(K.lathe(outer.map { CV2($0.x - 0.15, $0.y - 0.1) }, segments: 24, R(.painted(0xF2EEE6)),
                                                 capStart: false, capEnd: false)), at: top, rotation: q))
        parts.append(K.placed(K.disc(radius: 0.95, height: 0.6, bevel: 0.2, segments: 12, enamel), at: top, rotation: q))
        // 笠の縁リング
        parts.append(K.tube((0..<20).map { k -> CV3 in
            let a = Double(k) / 20 * 2 * .pi
            return top + q.rotate(CV3(cos(a) * 3.55, -4.35, sin(a) * 3.55))
        }, radius: 0.12, sides: 5, closed: true, R(.agedBrass)))
        parts.append(K.placed(K.sphere(radius: 1.0, segments: 10, R(.bulb)), at: top + q.rotate(CV3(0, -2.0, 0))))
        // 引き鎖
        let chainTop = top + q.rotate(CV3(1.2, -0.4, 0))
        for i in 0..<5 {
            parts.append(K.placed(K.sphere(radius: 0.22, segments: 6, brass), at: chainTop + CV3(0, -Double(i) * 0.55, 0.15 * Double(i))))
        }
        return K.merge(parts)
    }

    /// 燭台（飾り座・S 字の腕・受け皿・垂れた蝋・炎・薄い硝子筒）
    static func candleSconce() -> CamperMesh {
        var parts: [CamperMesh] = []
        let brass = R(.agedBrass)
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.0, 0), CV2(2.4, 0.35), CV2(2.1, 0.7), CV2(1.7, 1.0), CV2(0, 1.0)],
                                      segments: 20, brass), at: CV3(0, 8, 0.05), rotation: toWall))
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + .pi / 4
            parts.append(K.placed(K.sphere(radius: 0.2, segments: 6, brass),
                                  at: CV3(cos(a) * 1.6, 8 + sin(a) * 1.6, 0.7)))
        }
        // S 字の腕と葉の飾り
        parts.append(K.tube([CV3(0, 8, 0.9), CV3(0, 7.0, 2.4), CV3(0, 7.6, 3.8), CV3(0, 8.8, 4.8), CV3(0, 9.8, 5.1)],
                            radius: 0.32, sides: 8, brass))
        for (p, s) in [(CV3(0, 7.6, 3.8), 0.45), (CV3(0, 8.8, 4.8), 0.4)] as [(CV3, Double)] {
            parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 8, brass), CV3(s * 1.6, s * 0.35, s)), at: p + CV3(0.7, 0, 0)))
            parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 8, brass), CV3(s * 1.6, s * 0.35, s)), at: p + CV3(-0.7, 0, 0)))
        }
        parts.append(K.placed(K.vessel(outer: [CV2(0, 0), CV2(1.7, 0), CV2(2.8, 0.75)],
                                       inner: [CV2(0, 0.3), CV2(1.5, 0.3), CV2(2.55, 0.75)], segments: 22, brass),
                              at: CV3(0, 9.8, 5.1)))
        // 蝋燭と垂れ
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.05, 0), CV2(1.05, 5.8), CV2(0.85, 6.1), CV2(0, 6.1)], segments: 16, R(.paper)),
                              at: CV3(0, 10.2, 5.1)))
        for (dx, h) in [(0.7, 2.2), (-0.55, 1.6), (0.35, 3.0)] as [(Double, Double)] {
            parts.append(K.tube([CV3(dx, 10.3, 5.1 + 0.9), CV3(dx * 1.1, 10.3 + h * 0.3, 5.1 + 1.0), CV3(dx * 0.9, 10.3 + h, 5.1 + 0.7)],
                                radius: 0.12, sides: 5, R(.paper)))
        }
        // 薄い硝子の筒
        parts.append(K.placed(K.lathe([CV2(1.6, 0), CV2(1.7, 0.3), CV2(1.7, 5.5), CV2(1.55, 5.8)], segments: 18, R(.glass),
                                      capStart: false, capEnd: false), at: CV3(0, 10.4, 5.1)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.4, 0.55), CV2(0.32, 1.2), CV2(0, 1.7)], segments: 10, R(.fire)),
                              at: CV3(0, 16.3, 5.1)))
        return K.merge(parts)
    }

    /// 鳩時計（切妻の屋根・彫りの箱・文字盤・小窓・振り子と松ぼっくりの錘 2）。1 マス × 2 段
    /// 鳩時計（彫りの屋根・文字盤・針・小窓・錘・振り子）。壁面より後ろへ出さない
    static func cuckooClock() -> CamperMesh {
        var parts: [CamperMesh] = []
        let walnut = R(.wood(.walnut)), brass = R(.agedBrass)
        // 奥行きの半分が壁を突き抜けないよう、中心を前へ
        parts.append(K.block(CV3(9.4, 11.2, 4.6), at: CV3(0, 23.5, 2.4), radius: 0.45, walnut))
        parts.append(K.block(CV3(8.6, 0.35, 0.35), at: CV3(0, 28.8, 4.75), radius: 0.08, R(.wornWood(.walnut))))
        parts.append(K.block(CV3(8.6, 0.35, 0.35), at: CV3(0, 18.6, 4.75), radius: 0.08, R(.wornWood(.walnut))))
        let roof = CamperRoomShapes.extrudeAlongX([CV2(-4.0, 0), CV2(4.0, 0), CV2(0, 4.6)], length: 4.6, inset: 0.25, walnut)
        parts.append(K.placed(K.placed(roof, at: .zero, yaw: .pi / 2), at: CV3(0, 34.2, 2.4)))
        for s in [-1.0, 1.0] {
            parts.append(K.placed(K.roundedBox(CV3(7.0, 0.7, 4.8), radius: 0.22, segments: 1, R(.wornWood(.walnut))),
                                  at: CV3(s * 2.8, 36.2, 2.6),
                                  rotation: CQuat.axisAngle(CV3(0, 0, 1), -s * 0.86)))
        }
        parts.append(K.placed(K.sphere(radius: 0.45, segments: 8, brass), at: CV3(0, 39.0, 2.4)))
        parts.append(K.placed(K.ellipsePanel(rx: 2.9, ry: 2.9, R(.dial)), at: CV3(0, 26.5, 4.8)))
        parts.append(K.tube(K.arc(center: CV3(0, 26.5, 4.85), radius: 3.0, from: 0, to: 2 * .pi, steps: 28),
                            radius: 0.22, sides: 6, closed: true, brass))
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            parts.append(K.block(CV3(0.22, 0.55, 0.12),
                                 at: CV3(cos(a) * 2.45, 26.5 + sin(a) * 2.45, 4.95), radius: 0.04, R(.painted(0x141414))))
        }
        parts.append(K.placed(K.roundedBox(CV3(0.28, 1.7, 0.1), radius: 0.04, segments: 1, R(.painted(0x141414))),
                              at: CV3(0.2, 27.2, 5.0), rotation: CQuat.axisAngle(CV3(0, 0, 1), -0.35)))
        parts.append(K.placed(K.roundedBox(CV3(0.22, 2.3, 0.08), radius: 0.03, segments: 1, R(.painted(0x141414))),
                              at: CV3(-0.5, 27.4, 5.05), rotation: CQuat.axisAngle(CV3(0, 0, 1), 0.85)))
        parts.append(K.placed(K.disc(radius: 0.28, height: 0.2, bevel: 0.06, segments: 8, brass),
                              at: CV3(0, 26.5, 5.1), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.block(CV3(2.4, 2.4, 0.45), at: CV3(0, 31.6, 4.85), radius: 0.25, R(.wood(.darkOak))))
        parts.append(K.placed(K.panel(width: 1.6, height: 1.6, R(.painted(0x1A1A1A))), at: CV3(0, 31.6, 5.1)))
        for (dx, len) in [(-2.0, 14.5), (2.0, 11.0)] {
            parts.append(K.tube([CV3(dx, 23.5, 2.4), CV3(dx, 23.5 - len, 2.4)], radius: 0.1, sides: 4, brass))
            for bead in 0..<5 {
                parts.append(K.placed(K.sphere(radius: 0.22, segments: 6, brass),
                                      at: CV3(dx, 23.5 - len * (0.15 + Double(bead) * 0.15), 2.4)))
            }
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.85, 0.35), CV2(1.15, 2.6), CV2(0.7, 4.2), CV2(0, 4.6)],
                                          segments: 12, brass), at: CV3(dx, 23.5 - len - 4.6, 2.4)))
        }
        parts.append(K.tube([CV3(0, 23.5, 3.0), CV3(0, 12.5, 3.0)], radius: 0.16, sides: 5, R(.wood(.darkOak))))
        parts.append(K.placed(K.disc(radius: 1.8, height: 0.4, bevel: 0.12, segments: 18, brass), at: CV3(0, 11.4, 3.0),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.placed(K.disc(radius: 0.9, height: 0.25, bevel: 0.08, segments: 12, R(.brass)), at: CV3(0, 11.4, 3.25),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        return K.merge(parts)
    }

    /// 光の時計（先の細い真鍮の光・縁・文字盤の刻み・針）
    static func sunburstClock() -> CamperMesh {
        var parts: [CamperMesh] = []
        let c = CV3(0, 10, 0.9)
        let brass = R(.brass), toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(K.disc(radius: 3.5, height: 1.1, bevel: 0.3, segments: 30, brass), at: c, rotation: toWall))
        parts.append(K.placed(K.disc(radius: 3.15, height: 0.35, bevel: 0.1, segments: 28, R(.agedBrass)),
                              at: c + CV3(0, 0, 0.85), rotation: toWall))
        parts.append(K.placed(K.ellipsePanel(rx: 2.95, ry: 2.95, R(.dial)), at: c + CV3(0, 0, 1.15)))
        // 時の刻み
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            parts.append(K.block(CV3(0.28, 0.7, 0.15), at: CV3(c.x + cos(a) * 2.45, c.y + sin(a) * 2.45, c.z + 1.25), radius: 0.05,
                                 R(.painted(0x141414))))
        }
        // 針
        parts.append(K.placed(K.roundedBox(CV3(0.35, 2.0, 0.12), radius: 0.05, segments: 1, R(.painted(0x141414))),
                              at: c + CV3(0.15, 0.9, 1.35), rotation: CQuat.axisAngle(CV3(0, 0, 1), -0.4)))
        parts.append(K.placed(K.roundedBox(CV3(0.28, 2.8, 0.1), radius: 0.04, segments: 1, R(.painted(0x141414))),
                              at: c + CV3(-0.55, 1.1, 1.42), rotation: CQuat.axisAngle(CV3(0, 0, 1), 0.9)))
        parts.append(K.placed(K.disc(radius: 0.35, height: 0.25, bevel: 0.08, segments: 10, brass),
                              at: c + CV3(0, 0, 1.5), rotation: toWall))
        // 先の細い光（長短交互・壁マス幅に収める）
        for k in 0..<16 {
            let a = Double(k) / 16 * 2 * .pi
            let len = k % 2 == 0 ? 5.6 : 3.9
            let dir = CV3(cos(a), sin(a), 0)
            let root = c + dir * 3.45 + CV3(0, 0, 0.2)
            let tip = c + dir * (3.45 + len) + CV3(0, 0, 0.2)
            parts.append(K.tube([root, root + dir * len * 0.55, tip], radius: k % 2 == 0 ? 0.28 : 0.2, sides: 6, brass))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.4, 0), CV2(0.22, 0.6), CV2(0, 0.6)], segments: 8, brass),
                                  at: tip, rotation: CQuat.rotation(from: CV3(0, 1, 0), to: dir)))
        }
        return K.merge(parts)
    }

    /// めくる時計（黒い箱・脚・数字の板 2 枚のヒンジ・切れ目・小さなネジ）。壁面より後ろへ出さない
    static func flipClock() -> CamperMesh {
        var parts: [CamperMesh] = []
        let body = R(.painted(0x222326)), card = R(.painted(0xEDE8DE)), ink = R(.painted(0x1A1A1A))
        // 台脚（箱の奥行きの半分が壁を突き抜けないよう、中心を前へ）
        for x in [-3.6, 3.6] {
            parts.append(K.block(CV3(1.4, 1.2, 3.0), at: CV3(x, 5.8, 1.7), radius: 0.25, R(.iron)))
        }
        parts.append(K.block(CV3(9.4, 5.8, 3.6), at: CV3(0, 7.0, 2.0), radius: 0.7, body))
        // 前面の縁
        parts.append(K.block(CV3(9.0, 0.35, 0.35), at: CV3(0, 12.6, 3.85), radius: 0.08, R(.chrome)))
        parts.append(K.block(CV3(9.0, 0.35, 0.35), at: CV3(0, 7.2, 3.85), radius: 0.08, R(.chrome)))
        for x in [-2.15, 2.15] {
            // 上下のフリップ板
            parts.append(K.block(CV3(3.7, 2.05, 0.45), at: CV3(x, 10.0, 3.8), radius: 0.2, card))
            parts.append(K.block(CV3(3.7, 2.05, 0.45), at: CV3(x, 7.85, 3.8), radius: 0.2, card))
            // ヒンジの軸
            parts.append(K.tube([CV3(x - 1.7, 9.9, 4.05), CV3(x + 1.7, 9.9, 4.05)], radius: 0.12, sides: 6, R(.chrome)))
            parts.append(K.block(CV3(3.7, 0.12, 0.25), at: CV3(x, 9.9, 4.1), radius: 0.03, body))
        }
        // 「1」「2」
        parts.append(K.block(CV3(0.4, 2.8, 0.12), at: CV3(-2.15, 8.9, 4.2), radius: 0.05, ink))
        for (dx, dy, w, h) in [(0.0, 2.6, 1.5, 0.32), (0.65, 1.7, 0.32, 1.2), (0.0, 1.2, 1.5, 0.32), (-0.65, 0.4, 0.32, 1.2), (0.0, -0.1, 1.5, 0.32)] {
            parts.append(K.block(CV3(w, h, 0.12), at: CV3(2.15 + dx, 8.6 + dy, 4.2), radius: 0.04, ink))
        }
        for x in [-4.2, 4.2] {
            parts.append(K.placed(K.sphere(radius: 0.22, segments: 6, R(.chrome)), at: CV3(x, 9.9, 3.85)))
        }
        return K.merge(parts)
    }

    // MARK: 天井

    /// 光の網（横棒・斜めの補強・縦の線 6・粒 36・ソケット）
    static func fairyNet() -> CamperMesh {
        var parts: [CamperMesh] = []
        let wire = R(.iron)
        parts.append(K.tube([CV3(-28, -1.2, 0), CV3(28, -1.2, 0)], radius: 0.22, sides: 6, wire))
        for x in [-28.0, 28.0] {
            parts.append(K.placed(K.sphere(radius: 0.45, segments: 8, R(.agedBrass)), at: CV3(x, -1.2, 0)))
        }
        // 斜めの補強線
        parts.append(K.tube([CV3(-22, -1.2, 0), CV3(-8, -8.5, 0.4), CV3(6, -14.0, -0.3), CV3(22, -6.5, 0)],
                            radius: 0.08, sides: 4, wire))
        for s in 0..<6 {
            let x = -25 + Double(s) * 10
            let len = 18 + Double((s * 7) % 5) * 2.4
            let strand = (0...10).map { i -> CV3 in
                let t = Double(i) / 10
                return CV3(x + sin(t * 4 + Double(s)) * 0.55, -1.2 - t * len, sin(t * 3 + Double(s) * 0.4) * 0.35)
            }
            parts.append(K.tube(strand, radius: 0.1, sides: 4, wire))
            for k in 0..<6 {
                let t = (Double(k) + 0.75) / 6.5
                let p = CV3(x + sin(t * 4 + Double(s)) * 0.55, -1.2 - t * len, sin(t * 3 + Double(s) * 0.4) * 0.35)
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.28, 0), CV2(0.3, 0.35), CV2(0, 0.35)],
                                              segments: 8, R(.agedBrass)), at: p + CV3(0, 0.35, 0)))
                parts.append(K.placed(K.sphere(radius: 0.55, segments: 10, R(.bulb)), at: p))
            }
        }
        return K.merge(parts)
    }

    /// 紙の玉（紐に立体の紙の球・ひだと色）
    static func paperGarland() -> CamperMesh {
        var parts: [CamperMesh] = []
        let cord = (0...24).map { k -> CV3 in
            let t = Double(k) / 24
            return CV3(-29 + 58 * t, -1.5 - 6 * sin(t * .pi), 0)
        }
        parts.append(K.tube(cord, radius: 0.12, sides: 4, R(.rope)))
        let colors: [UInt32] = [0xD9A441, 0xC9584A, 0x6E8FA3, 0xEDE8DE, 0x7D8A5E, 0xB5653F]
        for k in 0..<12 {
            let t = (Double(k) + 0.5) / 12
            let p = CV3(-29 + 58 * t, -1.5 - 6 * sin(t * .pi), 0)
            let r = 1.5 + Double(k % 3) * 0.25
            let c = R(.paperColor(colors[k % colors.count]))
            // ひだのある球（緯度帯の薄いリング）。原点に置かず玉の位置へ
            let center = p + CV3(0, -r - 0.2, 0)
            parts.append(K.placed(K.sphere(radius: r * 0.85, segments: 12, c), at: center))
            for band in 0..<4 {
                let y = -r * 0.55 + Double(band) * (r * 0.35)
                let rr = r * (0.95 - abs(Double(band) - 1.5) * 0.08)
                parts.append(K.tube(K.arc(center: .zero, radius: rr, from: 0, to: 2 * .pi, steps: 16)
                                        .map { center + CV3($0.x, y, $0.y) }, radius: 0.08, sides: 4, closed: true, c))
            }
            parts.append(K.placed(K.sphere(radius: 0.25, segments: 6, R(.rope)), at: p + CV3(0, -0.15, 0)))
        }
        return K.merge(parts)
    }

    /// 折り鶴（樺の横木・節の玉・色紙の鶴 3 羽・房と折り目）
    static func paperCranes() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube([CV3(0, 0, 0), CV3(0, -4, 0), CV3(0, -12, 0)], radius: 0.1, sides: 5, R(.rope)))
        parts.append(K.placed(K.sphere(radius: 0.55, segments: 10, R(.wood(.walnut))), at: CV3(0, -4, 0)))
        // 横木（少し反った丸棒）と端の金具
        let bar = (0...12).map { i -> CV3 in
            let t = Double(i) / 12
            return CV3(-7 + 14 * t, -12 - 0.35 * sin(t * .pi), 0.15 * sin(t * .pi * 2))
        }
        parts.append(K.tube(bar, radius: 0.38, sides: 10, R(.wood(.birch))))
        for x in [-7.0, 7.0] {
            parts.append(K.placed(K.disc(radius: 0.55, height: 0.35, bevel: 0.1, segments: 10, R(.brass)),
                                  at: CV3(x, -12, 0), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2)))
        }
        for (x, drop, yaw, c) in [(-5.6, 6.0, 0.6, 0xC9584A as UInt32), (0, 10.0, -1.2, 0x2F4F74), (5.6, 7.0, 2.4, 0xEDE8DE)] {
            parts.append(K.tube([CV3(x, -12, 0), CV3(x, -12 - drop, 0)], radius: 0.07, sides: 4, R(.paper)))
            for yOff in [drop * 0.25, drop * 0.55] as [Double] {
                parts.append(K.placed(K.sphere(radius: 0.38, segments: 10, R(.wood(.cedar))), at: CV3(x, -12 - yOff, 0)))
            }
            let craneAt = CV3(x, -12 - drop - 1.1, 0)
            parts.append(K.placed(CamperRoomShapes.crane(R(.paperColor(c))), at: craneAt, yaw: yaw))
            // 翼の影になる薄い折り紙
            parts.append(K.placed(K.panel(width: 2.4, height: 1.1, R(.paperColor(c))), at: craneAt + CV3(0.2, 0.4, 0.35),
                                  rotation: CQuat.axisAngle(CV3(0, 1, 0), yaw + 0.4)))
            // 下の房（糸束）
            for k in 0..<5 {
                let a = Double(k) / 5 * 2 * .pi
                parts.append(K.tube([craneAt + CV3(0, -1.2, 0),
                                     craneAt + CV3(cos(a) * 0.45, -3.6 - Double(k % 2) * 0.4, sin(a) * 0.45)],
                                    radius: 0.08, sides: 4, R(.paperColor(c))))
            }
        }
        return K.merge(parts)
    }

    /// 星（真鍮の二重弧・玉・押し出した星 5・細い鎖）
    static func starMobile() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube([CV3(0, 0, 0), CV3(0, -10, 0)], radius: 0.1, sides: 5, R(.rope)))
        parts.append(K.placed(K.sphere(radius: 0.5, segments: 10, R(.brass)), at: CV3(0, -3.2, 0)))
        let arc = K.arc(center: CV3(0, -4, 0), radius: 7.2, from: .pi * 1.15, to: .pi * 1.85, steps: 20)
        parts.append(K.tube(arc, radius: 0.28, sides: 8, R(.brass)))
        // 内側の細い弧
        let arc2 = K.arc(center: CV3(0, -3.6, 0), radius: 5.4, from: .pi * 1.2, to: .pi * 1.8, steps: 16)
        parts.append(K.tube(arc2, radius: 0.14, sides: 6, R(.agedBrass)))
        let hang: [(Int, Double)] = [(0, 4.5), (5, 7.5), (10, 9.0), (15, 6.5), (19, 4.0)]
        for (idx, drop) in hang {
            let p = arc[min(idx, arc.count - 1)]
            parts.append(K.tube([p, p + CV3(0, -drop, 0)], radius: 0.07, sides: 4, R(.paper)))
            for bead in 0..<3 {
                parts.append(K.placed(K.sphere(radius: 0.28, segments: 8, R(.brass)),
                                      at: p + CV3(0, -drop * (0.2 + Double(bead) * 0.18), 0)))
            }
            let outer = 1.6 + Double(idx % 3) * 0.25
            let star = (0..<10).map { k -> CV2 in
                let a = Double(k) / 10 * 2 * .pi + .pi / 2
                let r = k % 2 == 0 ? outer : outer * 0.42
                return CV2(cos(a) * r, sin(a) * r)
            }
            parts.append(K.placed(CamperMeshKit.extrude(star, depth: 0.55, front: R(.brass), side: R(.agedBrass), bevel: 0.12),
                                  at: p + CV3(0, -drop - outer, 0.2),
                                  rotation: CQuat.axisAngle(CV3(0, 1, 0), Double(idx) * 0.55)))
            // 星の中心の鋲
            parts.append(K.placed(K.sphere(radius: 0.22, segments: 8, R(.agedBrass)),
                                  at: p + CV3(0, -drop - outer, 0.55)))
        }
        return K.merge(parts)
    }

    /// 流木（節のある枝・樹皮の筋・硝子の雫 5・木の玉）
    static func driftwood() -> CamperMesh {
        var parts: [CamperMesh] = []
        for x in [-8.0, 8.0] {
            parts.append(K.tube([CV3(x, 0, 0), CV3(x, -9, 0)], radius: 0.08, sides: 4, R(.rope)))
            parts.append(K.placed(K.sphere(radius: 0.4, segments: 8, R(.wood(.walnut))), at: CV3(x, -4.5, 0)))
        }
        let segments: [(CV3, CV3, Double)] = [
            (CV3(-14, -9, 0.4), CV3(-6, -9.6, 0), 0.95), (CV3(-6, -9.6, 0), CV3(3, -9, -0.3), 1.15),
            (CV3(3, -9, -0.3), CV3(13, -10.2, 0.2), 0.85), (CV3(5, -9.2, -0.2), CV3(9, -7.6, 1.2), 0.5),
            (CV3(-8, -9.4, 0.2), CV3(-4, -7.8, -1.0), 0.4)
        ]
        for (a, b, r) in segments {
            let mid = (a + b) * 0.5 + CV3(0, 0.35, 0.25)
            parts.append(K.tube([a, mid, b], radius: r, sides: 10, R(.wornWood(.birch))))
            // 樹皮の筋
            parts.append(K.tube([a + CV3(0, r * 0.6, 0), mid + CV3(0.1, r * 0.7, 0), b + CV3(0, r * 0.5, 0)],
                                radius: r * 0.18, sides: 5, R(.wornWood(.walnut))))
        }
        let glass: [UInt32] = [0x6E9FB0, 0xB8D4D0, 0x4E7A8C, 0xD8E6E0, 0x8FB8A8]
        for (i, x) in [-11.0, -5.0, 1.0, 6.0, 11.0].enumerated() {
            let drop = [5.0, 8.5, 6.0, 9.5, 4.5][i]
            parts.append(K.tube([CV3(x, -10, 0), CV3(x, -10 - drop, 0)], radius: 0.05, sides: 3, R(.paper)))
            parts.append(K.placed(K.sphere(radius: 0.35, segments: 8, R(.wood(.cedar))), at: CV3(x, -10 - drop * 0.35, 0)))
            parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 14, R(.tintedGlass(glass[i]))),
                                           CV3(0.85, 1.7, 0.85)), at: CV3(x, -10 - drop - 1.5, 0)))
            parts.append(K.placed(K.sphere(radius: 0.2, segments: 6, R(.brass)), at: CV3(x, -10 - drop - 0.15, 0)))
        }
        return K.merge(parts)
    }

    /// 真鍮の輪（吊り紐・二重の輪・麻の巻き・葉 12・エアプランツ・苔）
    static func airRing() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube([CV3(0, 0, 0), CV3(0, -6, 0), CV3(0, -14, 0)], radius: 0.1, sides: 5, R(.rope)))
        parts.append(K.placed(K.sphere(radius: 0.5, segments: 10, R(.brass)), at: CV3(0, -6, 0)))
        let center = CV3(0, -22, 0)
        let ring = K.arc(center: center, radius: 8.2, from: 0, to: 2 * .pi, steps: 48)
        parts.append(K.tube(ring, radius: 0.35, sides: 10, closed: true, R(.brass)))
        // 内側の細い輪
        parts.append(K.tube(K.arc(center: center, radius: 6.4, from: 0, to: 2 * .pi, steps: 36),
                            radius: 0.16, sides: 7, closed: true, R(.agedBrass)))
        // 麻の巻き（下半分）
        for k in 0..<10 {
            let a = .pi * 0.15 + Double(k) / 10 * .pi * 0.7
            let p = center + CV3(cos(a) * 8.2, sin(a) * 8.2, 0)
            parts.append(K.tube([p + CV3(0, 0, -0.5), p + CV3(0, 0, 0.5)], radius: 0.22, sides: 5, R(.rope)))
        }
        for k in 0..<12 {
            let a = -.pi / 2 + (Double(k) - 5.5) * 0.16
            let p = center + CV3(cos(a) * 8.2, sin(a) * 8.2, 0)
            let toward = CV3(cos(a + .pi / 2) * (k % 2 == 0 ? 1 : -1), 0.25, k % 2 == 0 ? 0.7 : -0.7)
            parts.append(CamperRoomShapes.leaf(at: p, toward: toward, size: 2.0 + Double(k % 3) * 0.25))
            if k % 3 == 0 {
                parts.append(CamperRoomShapes.leaf(at: p + toward * 0.8, toward: toward + CV3(0, 0.2, 0), size: 1.4))
            }
        }
        // エアプランツの束
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            parts.append(K.tube([center + CV3(0, -7.2, 0),
                                 center + CV3(cos(a) * 2.2, -5.5 + Double(k % 3) * 0.4, sin(a) * 2.2)],
                                radius: 0.16, sides: 4, R(.paperColor(0x9DB08A))))
        }
        parts.append(K.placed(K.scaled(K.sphere(radius: 1.4, segments: 12, R(.painted(0x6E8A5A))), CV3(1.1, 0.7, 1.1)),
                              at: center + CV3(0, -6.8, 0)))
        return K.merge(parts)
    }

    /// 丸い天窓（厚い枠・内縁の真鍮・丸い硝子の覆い・留めネジ）
    static func roundHatch() -> CamperMesh {
        var parts: [CamperMesh] = []
        let down = CQuat.axisAngle(CV3(1, 0, 0), .pi)
        parts.append(K.placed(K.disc(radius: 9.6, height: 2.4, bevel: 0.55, segments: 40, R(.painted(0xE9E6DF))), at: .zero, rotation: down))
        parts.append(K.placed(K.disc(radius: 7.8, height: 0.6, bevel: 0.2, segments: 36, R(.painted(0xDAD6CC))), at: CV3(0, -0.3, 0), rotation: down))
        parts.append(K.tube(K.arc(center: .zero, radius: 7.7, from: 0, to: 2 * .pi, steps: 40).map { CV3($0.x, -2.35, $0.y) }, radius: 0.42, sides: 8,
                            closed: true, R(.brass)))
        parts.append(K.tube(K.arc(center: .zero, radius: 8.8, from: 0, to: 2 * .pi, steps: 40).map { CV3($0.x, -0.4, $0.y) }, radius: 0.22, sides: 6,
                            closed: true, R(.chrome)))
        parts.append(K.placed(K.lathe([CV2(0, -0.5), CV2(4.8, -0.7), CV2(7.0, -1.6), CV2(7.3, -2.0)], segments: 36, R(.glass),
                                      capStart: false, capEnd: false), at: CV3(0, -0.5, 0)))
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            parts.append(K.placed(K.sphere(radius: 0.35, segments: 8, R(.brass)), at: CV3(cos(a) * 8.9, -0.55, sin(a) * 8.9)))
        }
        return K.merge(parts)
    }

    /// 星の天窓（厚い枠・内縁の真鍮・十字の桟・夜は星が映る硝子）
    static func starWindow() -> CamperMesh {
        var parts: [CamperMesh] = []
        let toDown = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        let ring = K.roundedRect(19, 19, r: 2.2, steps: 4)
        let hole = K.roundedRect(13.6, 13.6, r: 1.2, steps: 3)
        parts.append(K.placed(CamperMeshKit.extrude(ring, holes: [hole], depth: 2.8, front: R(.wood(.walnut)), side: R(.wornWood(.walnut)), bevel: 0.5),
                              at: CV3(0, -2.8, 0), rotation: toDown))
        // 内縁の真鍮の縁
        parts.append(K.tube(K.roundedRect(13.8, 13.8, r: 1.2).map { CV3($0.x, -0.35, $0.y) }, radius: 0.28, sides: 6, closed: true, R(.brass)))
        // 十字の桟
        parts.append(K.placed(K.block(CV3(13.2, 0.7, 0.55), at: .zero, radius: 0.15, R(.wood(.walnut))), at: CV3(0, -0.9, 0), rotation: toDown))
        parts.append(K.placed(K.block(CV3(0.7, 13.2, 0.55), at: .zero, radius: 0.15, R(.wood(.walnut))), at: CV3(0, -0.9, 0), rotation: toDown))
        parts.append(K.placed(K.panel(width: 13.4, height: 13.4, R(.windowView)), at: CV3(0, -0.15, 0), rotation: toDown))
        parts.append(K.placed(K.panel(width: 13.4, height: 13.4, R(.glass)), at: CV3(0, -1.35, 0), rotation: toDown))
        // 四隅の留め
        for (x, z) in [(-8.2, -8.2), (8.2, -8.2), (-8.2, 8.2), (8.2, 8.2)] {
            parts.append(K.placed(K.sphere(radius: 0.45, segments: 8, R(.brass)), at: CV3(x, -0.5, z)))
        }
        return K.merge(parts)
    }

    /// 色硝子（厚い枠・内縁の真鍮・8 色の扇・鉛の桟・中心の花・留めネジ）
    static func stainedGlass() -> CamperMesh {
        var parts: [CamperMesh] = []
        let toDown = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        let ring = K.roundedRect(19, 19, r: 2.2, steps: 4)
        let hole = K.roundedRect(13.6, 13.6, r: 1.2, steps: 3)
        parts.append(K.placed(CamperMeshKit.extrude(ring, holes: [hole], depth: 2.8, front: R(.wood(.walnut)),
                                                    side: R(.wornWood(.walnut)), bevel: 0.5),
                              at: CV3(0, -2.8, 0), rotation: toDown))
        parts.append(K.tube(K.roundedRect(13.8, 13.8, r: 1.2).map { CV3($0.x, -0.35, $0.y) },
                            radius: 0.28, sides: 6, closed: true, R(.brass)))
        let colors: [UInt32] = [0xC9584A, 0xD9A441, 0x5E8A4A, 0x2F6A8C, 0x6A4A8C, 0xB5653F, 0x3E8A8A, 0xD9C27A]
        let rOut = 6.2
        for k in 0..<8 {
            let a0 = Double(k) / 8 * 2 * .pi + .pi / 8
            let a1 = Double(k + 1) / 8 * 2 * .pi + .pi / 8
            // 天井座標で扇を直接組む（押し出し＋回転だと y>0 に食み出す）
            let p0 = CV3(0, -0.2, 0)
            let p1 = CV3(cos(a0) * rOut, -0.2, sin(a0) * rOut)
            let p2 = CV3(cos(a1) * rOut, -0.2, sin(a1) * rOut)
            var fan = CamperMesh()
            fan.tri(p0, p1, p2, normal: CV3(0, 1, 0), R(.paperColor(colors[k])))
            fan.tri(p0, p2, p1, normal: CV3(0, -1, 0), R(.paperColor(colors[k])))
            parts.append(fan)
            let q0 = CV3(0, -1.25, 0)
            let q1 = CV3(cos(a0) * rOut, -1.25, sin(a0) * rOut)
            let q2 = CV3(cos(a1) * rOut, -1.25, sin(a1) * rOut)
            var glaze = CamperMesh()
            glaze.tri(q0, q1, q2, normal: CV3(0, 1, 0), R(.tintedGlass(colors[k])))
            glaze.tri(q0, q2, q1, normal: CV3(0, -1, 0), R(.tintedGlass(colors[k])))
            parts.append(glaze)
            parts.append(K.tube([CV3(0, -0.85, 0), CV3(cos(a0) * rOut, -0.85, sin(a0) * rOut)],
                                radius: 0.14, sides: 5, R(.iron)))
        }
        parts.append(K.tube((0..<36).map { i -> CV3 in
            let a = Double(i) / 36 * 2 * .pi
            return CV3(cos(a) * rOut, -0.85, sin(a) * rOut)
        }, radius: 0.16, sides: 5, closed: true, R(.iron)))
        parts.append(K.placed(K.disc(radius: 1.5, height: 0.25, bevel: 0.08, segments: 16, R(.brass)),
                              at: CV3(0, -0.35, 0), rotation: toDown))
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi
            parts.append(K.placed(K.sphere(radius: 0.35, segments: 8, R(.paperColor(0xD9C27A))),
                                  at: CV3(cos(a) * 0.9, -0.55, sin(a) * 0.9)))
        }
        for (x, z) in [(-8.2, -8.2), (8.2, -8.2), (-8.2, 8.2), (8.2, 8.2)] {
            parts.append(K.placed(K.sphere(radius: 0.4, segments: 8, R(.brass)), at: CV3(x, -0.5, z)))
        }
        let merged = K.merge(parts)
        // 念のため天井より上へ出た分だけ下げる
        let top = merged.positions.map(\.y).max() ?? 0
        return top > 0.05 ? merged.translated(CV3(0, -top, 0)) : merged
    }
}
