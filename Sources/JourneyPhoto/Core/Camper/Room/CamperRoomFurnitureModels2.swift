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
        default: return nil
        }
    }

    /// 2 の組の灯り
    static func moreLamp(_ id: String) -> (position: CV3, intensity: Double, range: Double)? {
        switch id {
        case "heater.pot_belly": return (CV3(0, 12, 8), 3, 28)
        case "floor_lamp.arc": return (CV3(0, 72, 15), 6, 44)
        case "wall_lamp.swing_arm": return (CV3(0, 12, 12), 4, 34)
        case "wall_lamp.candle_sconce": return (CV3(0, 16, 5), 1.5, 22)
        case "string_ceiling.fairy_net": return (CV3(0, -14, 0), 3.5, 36)
        default: return nil
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

    /// 壁の折り畳み机（壁の桟・倒した天板・折れる腕 2・カップ）
    static func foldDownTable() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(38, 4, 2), at: CV3(0, 27, -9), radius: 0.4, R(.wood(.birch))))
        parts.append(K.block(CV3(38, 1.8, 17), at: CV3(0, 28.4, -1.5), radius: 0.6, R(.wornWood(.birch))))
        for x in [-14.0, 14.0] {
            parts.append(K.tube([CV3(x, 14, -9.4), CV3(x, 21, -3), CV3(x, 28.2, 4)], radius: 0.5, sides: 8, R(.chrome)))
            parts.append(K.placed(K.sphere(radius: 0.8, segments: 8, R(.chrome)), at: CV3(x, 21, -3)))
            parts.append(K.block(CV3(2, 4, 0.6), at: CV3(x, 12, -9.6), radius: 0.2, R(.chrome)))
        }
        parts.append(CamperRoomShapes.mug(at: CV3(6, 29.3, 0), body: R(.ceramic(0xC9B79A)), rim: R(.ceramic(0xB09A78)), yaw: 1.2))
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
    static func shagRug() -> CamperMesh {
        let outline = (0..<40).map { k -> CV2 in
            let a = Double(k) / 40 * 2 * .pi
            return CV2(cos(a) * 17.5, sin(a) * 17.5)
        }
        var parts = [K.rug(outline, thickness: 1.2, top: R(.knit(0xE6DCC8)), edge: R(.knit(0xD8CDB8)))]
        for k in 0..<96 {
            let a = Double(k) / 96 * 2 * .pi + (k % 2 == 0 ? 0 : 0.02)
            let r = 17.2 + Double(k % 3) * 0.3
            let base = CV3(cos(a) * r, 0.9, sin(a) * r)
            let out = CV3(cos(a), 0, sin(a))
            let side = CV3(-sin(a), 0, cos(a)) * (Double(k % 5) - 2) * 0.12
            parts.append(K.tube([base, base + out * 1.0 + side + CV3(0, 0.3, 0), base + out * 1.9 + side * 1.6 + CV3(0, -0.6, 0)], radius: 0.28,
                                sides: 4, cap: false, R(.knit(0xE6DCC8))))
        }
        return K.merge(parts)
    }

    /// 弧の灯り（大理石の台・大きな弧の腕・アルミの丸い笠・電球）。腕は高い所で隣の家具の上へ張り出す
    static func arcLamp() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(11, 3.2, 11), at: CV3(0, 0, -4), radius: 1, R(.ceramic(0xE4E0D8))))
        // 台から立ち上がって天井の手前で弧を描き、前へ下りる（先は 1.9 m ほど・前へ 55 cm）
        let path = (0...24).map { k -> CV3 in
            let t = Double(k) / 24
            return CV3(0, 3.2 + 78 * sin(t * .pi * 0.62), -6 + 22 * t * t)
        }
        parts.append(K.tube(path, radius: 0.55, sides: 10, R(.chrome)))
        let tip = path.last!
        parts.append(K.placed(K.lathe([CV2(0.9, 0), CV2(1.8, -0.4), CV2(5.4, -4.2), CV2(7.2, -7.2)], segments: 28, R(.sinkSteel), capStart: false,
                                      capEnd: false), at: tip + CV3(0, 2, 0)))
        parts.append(K.placed(K.inverted(K.lathe([CV2(0.8, -0.2), CV2(1.7, -0.6), CV2(5.2, -4.3), CV2(7.0, -7.2)], segments: 28,
                                                 R(.painted(0xF2EEE6)), capStart: false, capEnd: false)), at: tip + CV3(0, 2, 0)))
        parts.append(K.placed(K.sphere(radius: 1.9, segments: 14, R(.bulb)), at: tip + CV3(0, -2.4, 0)))
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

    /// 三枚続きの額（細い黒い枠 3・1 枚の写真を 3 つに分けて一つの景色に）
    static func triptych() -> CamperMesh {
        var parts: [CamperMesh] = []
        for i in 0..<3 {
            let x = -12.6 + Double(i) * 12.6
            let c = CV3(x, 10, 0)
            let ring = K.roundedRect(11.6, 13.6, r: 0.4, steps: 2)
            let hole = CamperPolygon.cw(K.roundedRect(9.8, 11.8, r: 0.2, steps: 2))
            parts.append(K.placed(CamperMeshKit.extrude(ring, holes: [hole], depth: 1.2, front: R(.painted(0x1C1B1A)), side: R(.painted(0x1C1B1A)),
                                                        bevel: 0.25), at: c + CV3(0, 0, 1.2)))
            var photo = K.panel(width: 9.8, height: 11.8, photoMaterial(0))
            photo.uvs = photo.uvs.map { CV2((Double(i) + $0.x) / 3, $0.y) }
            parts.append(K.placed(photo, at: c + CV3(0, 0, 0.6)))
            parts.append(K.placed(K.panel(width: 9.9, height: 11.9, R(.glass)), at: c + CV3(0, 0, 0.9)))
            parts.append(K.placed(K.panel(width: 11, height: 13, R(.painted(0x3A3430))), at: c + CV3(0, 0, 0.05)))
        }
        return K.merge(parts)
    }

    /// 旅の地図（印刷した紙・画鋲 4）
    static func mapPoster() -> CamperMesh {
        var parts: [CamperMesh] = []
        let c = CV3(0, 20, 0.15)
        parts.append(K.placed(CamperRoomShapes.paperSheet(width: 27, height: 18, curl: 0.8, R(.mapPrint)), at: c))
        for (dx, dy) in [(-12.6, 8.2), (12.6, 8.2), (-12.6, -8.2), (12.6, -8.2)] {
            parts.append(K.placed(K.disc(radius: 0.55, height: 0.5, bevel: 0.2, segments: 10, R(.enamel(0xB0291F))), at: c + CV3(dx, dy, 0.3),
                                  rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        }
        return K.merge(parts)
    }

    /// 腕の灯り（真鍮の座・折れる腕 2 つと継ぎ目・緑の琺瑯の笠・電球）
    static func swingArm() -> CamperMesh {
        var parts: [CamperMesh] = []
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(K.disc(radius: 2.2, height: 0.7, bevel: 0.25, segments: 18, R(.brass)), at: CV3(0, 9, 0), rotation: toWall))
        let j1 = CV3(2.5, 9.6, 5.5), j2 = CV3(-1, 12.6, 10)
        parts.append(K.tube([CV3(0, 9, 0.7), j1], radius: 0.4, sides: 8, R(.brass)))
        parts.append(K.tube([j1, j2], radius: 0.4, sides: 8, R(.brass)))
        for j in [j1, j2] { parts.append(K.placed(K.sphere(radius: 0.75, segments: 10, R(.brass)), at: j)) }
        // 笠（下前を向く円錐・外は緑の琺瑯、内は白）。断面は上の細い所から下へ広がる
        let q = CQuat.rotation(from: CV3(0, -1, 0), to: CV3(0.1, -1, 0.45))
        let outer: [CV2] = [CV2(0.9, 0), CV2(1.5, -0.8), CV2(3.0, -3.0), CV2(3.6, -4.4)]
        let top = j2 + CV3(0, 1.0, 0.6)
        parts.append(K.placed(K.lathe(outer, segments: 24, R(.enamel(0x2F5A3C)), capStart: false, capEnd: false), at: top, rotation: q))
        parts.append(K.placed(K.inverted(K.lathe(outer.map { CV2($0.x - 0.15, $0.y - 0.1) }, segments: 24, R(.painted(0xF2EEE6)), capStart: false,
                                                 capEnd: false)), at: top, rotation: q))
        parts.append(K.placed(K.disc(radius: 0.95, height: 0.6, bevel: 0.2, segments: 12, R(.enamel(0x2F5A3C))), at: top, rotation: q))
        parts.append(K.placed(K.sphere(radius: 1.0, segments: 10, R(.bulb)), at: top + q.rotate(CV3(0, -2.0, 0))))
        return K.merge(parts)
    }

    /// 燭台（真鍮の座と腕・受け皿・蝋燭と炎）
    static func candleSconce() -> CamperMesh {
        var parts: [CamperMesh] = []
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.8, 0), CV2(2.2, 0.4), CV2(1.6, 0.9), CV2(0, 0.9)], segments: 18, R(.agedBrass)),
                              at: CV3(0, 8, 0), rotation: toWall))
        parts.append(K.tube([CV3(0, 8, 0.8), CV3(0, 7.2, 3), CV3(0, 8.2, 4.8), CV3(0, 9.6, 5)], radius: 0.35, sides: 8, R(.agedBrass)))
        parts.append(K.placed(K.vessel(outer: [CV2(0, 0), CV2(1.6, 0), CV2(2.6, 0.7)], inner: [CV2(0, 0.3), CV2(1.4, 0.3), CV2(2.4, 0.7)], segments: 20,
                                       R(.agedBrass)), at: CV3(0, 9.6, 5)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1, 0), CV2(1, 5.6), CV2(0.8, 5.9), CV2(0, 5.9)], segments: 16, R(.paper)), at: CV3(0, 9.9, 5)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.38, 0.5), CV2(0.3, 1.1), CV2(0, 1.6)], segments: 10, R(.fire)), at: CV3(0, 15.9, 5)))
        return K.merge(parts)
    }

    /// 鳩時計（切妻の屋根・彫りの箱・文字盤・小窓・振り子と松ぼっくりの錘 2）。1 マス × 2 段
    static func cuckooClock() -> CamperMesh {
        var parts: [CamperMesh] = []
        let walnut = R(.wood(.walnut))
        parts.append(K.block(CV3(9, 10, 4.6), at: CV3(0, 24, 2.3), radius: 0.4, walnut))
        let roof = CamperRoomShapes.extrudeAlongX([CV2(-3.6, 0), CV2(3.6, 0), CV2(0, 4.2)], length: 4.6, inset: 0.2, walnut)
        parts.append(K.placed(K.placed(roof, at: .zero, yaw: .pi / 2), at: CV3(0, 34, 2.3)))
        for s in [-1.0, 1.0] {
            parts.append(K.placed(K.roundedBox(CV3(6.6, 0.6, 5.0), radius: 0.2, segments: 1, R(.wornWood(.walnut))), at: CV3(s * 2.6, 35.9, 2.6),
                                  rotation: CQuat.axisAngle(CV3(0, 0, 1), -s * 0.86)))
        }
        parts.append(K.placed(K.ellipsePanel(rx: 2.8, ry: 2.8, R(.dial)), at: CV3(0, 28, 4.65)))
        parts.append(K.tube(K.arc(center: CV3(0, 28, 4.7), radius: 2.9, from: 0, to: 2 * .pi, steps: 24), radius: 0.25, sides: 5, closed: true, R(.agedBrass)))
        parts.append(K.block(CV3(2, 2.2, 0.4), at: CV3(0, 31.3, 4.7), radius: 0.2, R(.wood(.darkOak))))
        for (dx, len) in [(-1.8, 14.0), (1.8, 10.0)] {
            parts.append(K.tube([CV3(dx, 24, 2.3), CV3(dx, 24 - len, 2.3)], radius: 0.08, sides: 3, R(.agedBrass)))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.7, 0.4), CV2(1, 2.4), CV2(0.6, 4), CV2(0, 4.4)], segments: 10, R(.agedBrass)),
                                  at: CV3(dx, 24 - len - 4.4, 2.3)))
        }
        parts.append(K.tube([CV3(0, 24, 3), CV3(0, 13, 3)], radius: 0.15, sides: 4, R(.wood(.darkOak))))
        parts.append(K.placed(K.disc(radius: 1.6, height: 0.3, bevel: 0.1, segments: 14, R(.agedBrass)), at: CV3(0, 12, 3),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        return K.merge(parts)
    }

    /// 光の時計（真鍮の光 16 本・真ん中の文字盤）
    static func sunburstClock() -> CamperMesh {
        var parts: [CamperMesh] = []
        let c = CV3(0, 10, 0.8)
        parts.append(K.placed(K.disc(radius: 3.4, height: 1, bevel: 0.3, segments: 28, R(.brass)), at: c, rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.placed(K.ellipsePanel(rx: 2.9, ry: 2.9, R(.dial)), at: c + CV3(0, 0, 1.05)))
        for k in 0..<16 {
            let a = Double(k) / 16 * 2 * .pi
            let len = k % 2 == 0 ? 6.3 : 4.6
            let dir = CV3(cos(a), sin(a), 0)
            parts.append(K.tube([c + dir * 3.4, c + dir * (3.4 + len)], radius: 0.28, sides: 6, R(.brass)))
            parts.append(K.placed(K.sphere(radius: 0.5, segments: 8, R(.brass)), at: c + dir * (3.4 + len)))
        }
        return K.merge(parts)
    }

    /// めくる時計（黒い箱・数字の板 2 枚・真ん中の切れ目・台の脚）
    static func flipClock() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(9, 5.6, 3.6), at: CV3(0, 7, 1.8), radius: 0.8, R(.painted(0x222326))))
        for x in [-2.1, 2.1] {
            parts.append(K.block(CV3(3.6, 4.2, 0.4), at: CV3(x, 7.7, 3.6), radius: 0.3, R(.painted(0xEDE8DE))))
            parts.append(K.block(CV3(3.6, 0.15, 0.2), at: CV3(x, 9.73, 4.0), radius: 0.03, R(.painted(0x222326))))
        }
        // 数字（「1」と「2」を細い棒で）
        parts.append(K.block(CV3(0.4, 3, 0.1), at: CV3(-2.1, 8.3, 4.05), radius: 0.05, R(.painted(0x1A1A1A))))
        for (dx, dy, w, h) in [(0.0, 3.0, 1.6, 0.35), (0.7, 2.0, 0.35, 1.3), (0.0, 1.5, 1.6, 0.35), (-0.7, 0.6, 0.35, 1.3), (0.0, 0.0, 1.6, 0.35)] {
            parts.append(K.block(CV3(w, h, 0.1), at: CV3(2.1 + dx, 8.3 + dy - h / 2, 4.05), radius: 0.05, R(.painted(0x1A1A1A))))
        }
        return K.merge(parts)
    }

    // MARK: 天井

    /// 光の網（上の紐から縦の線 6 本・粒 36）
    static func fairyNet() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube([CV3(-28, -1.5, 0), CV3(28, -1.5, 0)], radius: 0.18, sides: 5, R(.iron)))
        for s in 0..<6 {
            let x = -25 + Double(s) * 10
            let len = 18 + Double((s * 7) % 5) * 2.4
            parts.append(K.tube((0...8).map { CV3(x + sin(Double($0) * 0.8 + Double(s)) * 0.4, -1.5 - Double($0) / 8 * len, 0) }, radius: 0.08, sides: 3,
                                R(.iron)))
            for k in 0..<6 {
                let y = -1.5 - (Double(k) + 0.8) / 6.4 * len
                parts.append(K.placed(K.sphere(radius: 0.5, segments: 8, R(.bulb)), at: CV3(x + sin(Double(k) + Double(s)) * 0.4, y, 0)))
            }
        }
        return K.merge(parts)
    }

    /// 紙の玉（紐に色紙の丸 12 枚）
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
            let r = 1.6 + Double(k % 3) * 0.3
            parts.append(K.placed(K.ellipsePanel(rx: r, ry: r, steps: 24, R(.paperColor(colors[k % colors.count]))), at: p + CV3(0, -r - 0.3, 0),
                                  rotation: CQuat.axisAngle(CV3(0, 1, 0), Double(k) * 0.7)))
        }
        return K.merge(parts)
    }

    /// 折り鶴（樺の横木・色紙の鶴 3 羽）
    static func paperCranes() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube([CV3(0, 0, 0), CV3(0, -12, 0)], radius: 0.06, sides: 3, R(.paper)))
        parts.append(K.tube([CV3(-6, -12, 0), CV3(6, -12, 0)], radius: 0.25, sides: 6, R(.wood(.birch))))
        for (x, drop, yaw, c) in [(-5.6, 6.0, 0.6, 0xC9584A as UInt32), (0, 10.0, -1.2, 0x2F4F74), (5.6, 7.0, 2.4, 0xEDE8DE)] {
            parts.append(K.tube([CV3(x, -12, 0), CV3(x, -12 - drop, 0)], radius: 0.05, sides: 3, R(.paper)))
            // 糸の上の木の玉と、鶴の下の小さな房
            parts.append(K.placed(K.sphere(radius: 0.45, segments: 10, R(.wood(.cedar))), at: CV3(x, -12 - drop * 0.4, 0)))
            parts.append(K.placed(CamperRoomShapes.crane(R(.paperColor(c))), at: CV3(x, -12 - drop - 1, 0), yaw: yaw))
            parts.append(K.tube([CV3(x, -12 - drop - 1.4, 0), CV3(x, -12 - drop - 3.4, 0)], radius: 0.12, sides: 5, R(.paperColor(c))))
        }
        return K.merge(parts)
    }

    /// 星（真鍮の弧・押し出した星 3）
    static func starMobile() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube([CV3(0, 0, 0), CV3(0, -10, 0)], radius: 0.06, sides: 3, R(.paper)))
        let arc = K.arc(center: CV3(0, -4, 0), radius: 7, from: .pi * 1.2, to: .pi * 1.8, steps: 14)
        parts.append(K.tube(arc, radius: 0.22, sides: 6, R(.brass)))
        for (i, p) in [arc.first!, arc[7], arc.last!].enumerated() {
            let drop = [5.0, 8.0, 4.0][i]
            parts.append(K.tube([p, p + CV3(0, -drop, 0)], radius: 0.05, sides: 3, R(.paper)))
            let star = (0..<10).map { k -> CV2 in
                let a = Double(k) / 10 * 2 * .pi + .pi / 2
                let r = k % 2 == 0 ? 2.4 : 1.0
                return CV2(cos(a) * r, sin(a) * r)
            }
            parts.append(K.placed(CamperMeshKit.extrude(star, depth: 0.5, front: R(.brass), side: R(.agedBrass), bevel: 0.15),
                                  at: p + CV3(0, -drop - 2.4, 0.25), rotation: CQuat.axisAngle(CV3(0, 1, 0), Double(i) * 0.8)))
        }
        return K.merge(parts)
    }

    /// 流木（太さの揃わない流木・硝子の粒 4）
    static func driftwood() -> CamperMesh {
        var parts: [CamperMesh] = []
        for x in [-8.0, 8.0] { parts.append(K.tube([CV3(x, 0, 0), CV3(x, -9, 0)], radius: 0.06, sides: 3, R(.paper))) }
        let segments: [(CV3, CV3, Double)] = [(CV3(-14, -9, 0.4), CV3(-6, -9.6, 0), 0.9), (CV3(-6, -9.6, 0), CV3(3, -9, -0.3), 1.1),
                                              (CV3(3, -9, -0.3), CV3(13, -10.2, 0.2), 0.8), (CV3(5, -9.2, -0.2), CV3(9, -7.6, 1.2), 0.45)]
        for (a, b, r) in segments {
            parts.append(K.tube([a, (a + b) * 0.5 + CV3(0, 0.3, 0.2), b], radius: r, sides: 9, R(.wornWood(.birch))))
        }
        for (i, x) in [-10.0, -3.0, 4.0, 10.0].enumerated() {
            let drop = [5.0, 9.0, 6.5, 4.0][i]
            parts.append(K.tube([CV3(x, -10, 0), CV3(x, -10 - drop, 0)], radius: 0.04, sides: 3, R(.paper)))
            parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 12, R(.tintedGlass([0x6E9FB0, 0xB8D4D0, 0x4E7A8C, 0xD8E6E0][i]))),
                                           CV3(1, 1.5, 1)), at: CV3(x, -10 - drop - 1.4, 0)))
        }
        return K.merge(parts)
    }

    /// 真鍮の輪（輪に絡む葉 10・小さなエアプランツ）
    static func airRing() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube([CV3(0, 0, 0), CV3(0, -14, 0)], radius: 0.06, sides: 3, R(.paper)))
        let ring = K.arc(center: CV3(0, -22, 0), radius: 8, from: 0, to: 2 * .pi, steps: 40)
        parts.append(K.tube(ring, radius: 0.3, sides: 8, closed: true, R(.brass)))
        for k in 0..<10 {
            let a = -.pi / 2 + (Double(k) - 4.5) * 0.17
            let p = CV3(0, -22, 0) + CV3(cos(a) * 8, sin(a) * 8, 0)
            parts.append(CamperRoomShapes.leaf(at: p, toward: CV3(cos(a + .pi / 2) * (k % 2 == 0 ? 1 : -1), 0.3, k % 2 == 0 ? 0.6 : -0.6), size: 2.2))
        }
        for k in 0..<9 {
            let a = Double(k) / 9 * 2 * .pi
            parts.append(K.tube([CV3(0, -29.5, 0), CV3(cos(a) * 1.8, -28 + Double(k % 3), sin(a) * 1.8)], radius: 0.18, sides: 4, R(.paperColor(0x9DB08A))))
        }
        return K.merge(parts)
    }

    /// 丸い天窓（白い枠・磨いた縁の輪・丸い硝子の覆い）
    static func roundHatch() -> CamperMesh {
        var parts: [CamperMesh] = []
        let down = CQuat.axisAngle(CV3(1, 0, 0), .pi)
        parts.append(K.placed(K.disc(radius: 9.4, height: 2.2, bevel: 0.5, segments: 36, R(.painted(0xE9E6DF))), at: .zero, rotation: down))
        parts.append(K.tube(K.arc(center: .zero, radius: 7.6, from: 0, to: 2 * .pi, steps: 36).map { CV3($0.x, -2.3, $0.y) }, radius: 0.5, sides: 8,
                            closed: true, R(.chrome)))
        parts.append(K.placed(K.lathe([CV2(0, -0.6), CV2(5, -0.9), CV2(7.2, -1.8)], segments: 32, R(.glass), capStart: false, capEnd: false),
                              at: CV3(0, -0.6, 0)))
        return K.merge(parts)
    }

    /// 星の天窓（枠と、夜は星が映る硝子）
    static func starWindow() -> CamperMesh {
        var parts: [CamperMesh] = []
        let ring = K.roundedRect(19, 19, r: 2)
        let hole = K.roundedRect(14, 14, r: 1.4)
        parts.append(K.placed(CamperMeshKit.extrude(ring, holes: [hole], depth: 2.4, front: R(.wood(.walnut)), side: R(.wood(.walnut)), bevel: 0.4),
                              at: CV3(0, -2.4, 0), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.placed(K.panel(width: 14.2, height: 14.2, R(.windowView)), at: CV3(0, -0.2, 0), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.placed(K.panel(width: 14.2, height: 14.2, R(.glass)), at: CV3(0, -1.2, 0), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        return K.merge(parts)
    }

    /// 色硝子（枠・8 色の扇の硝子と鉛の線）
    static func stainedGlass() -> CamperMesh {
        var parts: [CamperMesh] = []
        let ring = K.roundedRect(19, 19, r: 2)
        let hole = K.roundedRect(14, 14, r: 1.4)
        let toDown = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(CamperMeshKit.extrude(ring, holes: [hole], depth: 2.4, front: R(.wood(.walnut)), side: R(.wood(.walnut)), bevel: 0.4),
                              at: CV3(0, -2.4, 0), rotation: toDown))
        let colors: [UInt32] = [0xC9584A, 0xD9A441, 0x5E8A4A, 0x2F6A8C, 0x6A4A8C, 0xB5653F, 0x3E8A8A, 0xD9C27A]
        for k in 0..<8 {
            let a0 = Double(k) / 8 * 2 * .pi, a1 = Double(k + 1) / 8 * 2 * .pi
            var fan = CamperMesh()
            let r = 7.0
            let pts = [CV3(0, 0, 0), CV3(cos(a0) * r * 1.42, sin(a0) * r * 1.42, 0), CV3(cos(a1) * r * 1.42, sin(a1) * r * 1.42, 0)]
                .map { CV3(max(-7, min(7, $0.x)), max(-7, min(7, $0.y)), 0) }
            fan.tri(pts[0], pts[1], pts[2], normal: CV3(0, 0, 1), R(.tintedGlass(colors[k])))
            parts.append(K.placed(fan, at: CV3(0, -1.0, 0), rotation: toDown))
            let lead = CV3(cos(a0) * 9.9, sin(a0) * 9.9, 0)
            parts.append(K.placed(K.tube([.zero, CV3(max(-7, min(7, lead.x)), max(-7, min(7, lead.y)), 0)], radius: 0.18, sides: 4, R(.iron)),
                                  at: CV3(0, -1.1, 0), rotation: toDown))
        }
        return K.merge(parts)
    }
}
