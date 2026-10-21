import Foundation

// 家具の形・3 の組（2026-10-20）。板の残り 11 点（要サーバー・近日だった分）を、
// `CamperRoomFurnitureModels` / `Models2` と同じ決まりで作り込む。owner「全部作り込んで」。

private typealias K = CamperRoomMeshKit
private func R(_ m: CamperRoomMaterial) -> CamperMaterial { .room(m) }

extension CamperRoomFurnitureModels {

    /// 3 の組の家具の形
    static func moreMesh3(_ id: String) -> CamperMesh? {
        switch id {
        case "bed.daybed": return daybed()
        case "seating.bench_storage": return benchStorage()
        case "heater.tile_hearth": return tileHearth()
        case "floor_lamp.paper_column": return paperColumn()
        case "wall_shelf.floating_corner": return floatingCorner()
        case "poster.postcard_grid": return postcardGrid()
        case "poster.tapestry": return tapestry()
        case "wall_lamp.lantern_hook": return lanternHook()
        case "string_ceiling.bunting": return bunting()
        case "plant_hanger.hanging_basket": return hangingBasket()
        case "plant_hanger.glass_terrarium": return glassTerrarium()
        default: return moreMesh4(id)
        }
    }

    /// 3 の組の灯り
    static func moreLamp3(_ id: String) -> (position: CV3, intensity: Double, range: Double)? {
        switch id {
        case "heater.tile_hearth": return (CV3(0, 14, 6), 0.4, 60)
        case "floor_lamp.paper_column": return (CV3(0, 28, 0), 0.55, 75)
        case "wall_lamp.lantern_hook": return (CV3(0, 6, 5), 0.4, 55)
        default: return moreLamp4(id)
        }
    }

    // MARK: 床

    /// デイベッド（両端に縦格子の枠・座面の布団と背のクッション・足元の毛布）
    static func daybed() -> CamperMesh {
        let oak = R(.wood(.oak)), dark = R(.wornWood(.darkOak))
        var parts: [CamperMesh] = []
        // 脚と框（8×3 マス・高さ 36）
        for (x, z) in [(-38.0, -13.5), (38.0, -13.5), (-38.0, 13.5), (38.0, 13.5)] {
            parts.append(K.block(CV3(3.2, 12, 3.2), at: CV3(x, 0, z), radius: 0.55, oak))
        }
        for z in [-13.8, 13.8] { parts.append(K.block(CV3(74, 5.5, 2.2), at: CV3(0, 6.5, z), radius: 0.55, oak)) }
        for x in [-38.2, 38.2] { parts.append(K.block(CV3(2.2, 5.5, 26), at: CV3(x, 6.5, 0), radius: 0.55, oak)) }
        // 簀の子
        for k in 0..<10 {
            parts.append(K.block(CV3(6.2, 0.7, 24), at: CV3(-33 + Double(k) * 7.3, 9.8, 0), radius: 0.15, R(.wood(.pine))))
        }
        // 両端の縦格子（デイベッドの印）
        for side in [-1.0, 1.0] {
            let x = side * 37.5
            parts.append(K.block(CV3(2.4, 26, 28), at: CV3(x, 10, 0), radius: 0.4, dark))
            for z in stride(from: -11.0, through: 11.0, by: 3.6) {
                parts.append(K.block(CV3(1.1, 22, 1.1), at: CV3(x - side * 0.2, 12, z), radius: 0.25, oak))
            }
            parts.append(K.block(CV3(2.6, 1.4, 26), at: CV3(x, 33.5, 0), radius: 0.35, oak))
            parts.append(K.block(CV3(2.6, 1.2, 26), at: CV3(x, 11.2, 0), radius: 0.3, oak))
        }
        // 布団・背のクッション・枕・毛布
        parts.append(K.placed(K.roundedBox(CV3(68, 5, 24), radius: 2, segments: 3, puff: 0.55, R(.cotton(0xE8E1D2))), at: CV3(0, 13.2, 0)))
        parts.append(K.placed(K.roundedBox(CV3(66, 7, 8), radius: 2.2, segments: 3, puff: 0.9, sidePuff: 0.5, R(.linen(0x8A9A7A))),
                              at: CV3(0, 17.5, -8)))
        for z in [-6.0, 6.0] {
            parts.append(K.placed(K.roundedBox(CV3(10, 4, 12), radius: 1.6, segments: 3, puff: 1.1, R(.linen(0xF1EDE4))),
                                  at: CV3(-28, 16.8, z), yaw: z > 0 ? -0.08 : 0.1))
        }
        parts.append(K.placed(K.roundedBox(CV3(14, 1.8, 24), radius: 0.7, segments: 2, puff: 0.25, R(.knit(0xB5653F))), at: CV3(26, 16.2, 0)))
        parts.append(K.placed(K.drape(width: 14, height: 5, folds: 3, depth: 0.45, flare: 0.12, R(.knit(0xB5653F))), at: CV3(26, 16.2, 12.2)))
        return K.merge(parts)
    }

    /// 物入れの長椅子（ナラの箱・真鍮の蝶番と取っ手・座面のクッション・中に畳んだ毛布が見える隙）
    static func benchStorage() -> CamperMesh {
        let oak = R(.wood(.oak))
        var parts: [CamperMesh] = []
        // 5×2 マス・高さ 18
        parts.append(K.block(CV3(46, 11, 18), at: CV3(0, 0.4, 0), radius: 0.7, oak))
        // 蓋の縁と蝶番
        parts.append(K.block(CV3(46.4, 1.2, 18.4), at: CV3(0, 11.4, 0), radius: 0.35, R(.wornWood(.oak))))
        for x in [-14.0, 0.0, 14.0] {
            parts.append(K.block(CV3(3.2, 0.5, 1.2), at: CV3(x, 12.5, -8.6), radius: 0.15, R(.brass)))
            parts.append(K.tube([CV3(x - 1.2, 12.5, -8.6), CV3(x + 1.2, 12.5, -8.6)], radius: 0.18, sides: 6, R(.agedBrass)))
        }
        // 前面の取っ手と細い隙間（中の布）
        parts.append(K.block(CV3(8, 0.6, 1.4), at: CV3(0, 6.2, 9.2), radius: 0.2, R(.brass)))
        parts.append(K.tube([CV3(-3.2, 6.2, 9.5), CV3(-3.2, 6.2, 10.6), CV3(3.2, 6.2, 10.6), CV3(3.2, 6.2, 9.5)], radius: 0.22, sides: 6,
                            R(.agedBrass)))
        parts.append(K.block(CV3(40, 1.6, 0.3), at: CV3(0, 9.6, 8.9), radius: 0.1, R(.knit(0xC9A66B))))
        // 脚
        for (x, z) in [(-20.0, -7.5), (20.0, -7.5), (-20.0, 7.5), (20.0, 7.5)] {
            parts.append(K.block(CV3(2.8, 3.2, 2.8), at: CV3(x, 0, z), radius: 0.4, R(.wornWood(.oak))))
        }
        // 座面のクッション
        parts.append(K.placed(K.roundedBox(CV3(44, 4.2, 16.5), radius: 1.8, segments: 3, puff: 0.7, sidePuff: 0.4, R(.linen(0xD9CFB8))),
                              at: CV3(0, 14.2, 0)))
        parts.append(K.tube(K.roundedRect(44.5, 17, r: 1.9).map { CV3($0.x, 14.2, $0.y) }, radius: 0.28, sides: 6, closed: true,
                            R(.linen(0xC4B89E))))
        return K.merge(parts)
    }

    /// タイルの暖炉（市松の炉台と胴・アーチの口・中の火・マントルピース・煙突）
    static func tileHearth() -> CamperMesh {
        var parts: [CamperMesh] = []
        let cream = R(.ceramic(0xE8E2D4)), soot = R(.ceramic(0x3A3530)), brick = R(.ceramic(0xA8573A))
        // 炉台
        parts.append(K.block(CV3(28, 1.2, 18), at: .zero, radius: 0.3, cream))
        for row in 0..<2 {
            for col in 0..<6 {
                let light = (row + col) % 2 == 0
                parts.append(K.block(CV3(4.4, 0.25, 4.4), at: CV3(-11.5 + Double(col) * 4.6, 1.2, -4.5 + Double(row) * 4.6), radius: 0.05,
                                     light ? cream : soot))
            }
        }
        // 胴（市松のタイル）
        parts.append(K.block(CV3(24, 28, 12), at: CV3(0, 1.2, -1), radius: 0.4, brick))
        for row in 0..<7 {
            for col in 0..<5 {
                let light = (row + col) % 2 == 0
                parts.append(K.block(CV3(4.2, 3.6, 0.35), at: CV3(-8.4 + Double(col) * 4.2, 3.2 + Double(row) * 3.7, 5.1), radius: 0.05,
                                     light ? cream : soot))
            }
        }
        // アーチの口と中の火
        let arch = CamperRoomShapes.archOutline(width: 14, base: 10, rise: 5, steps: 12)
        parts.append(K.placed(CamperRoomShapes.extrudeAlongX(arch, length: 2.2, inset: 0.2, R(.castIron)), at: CV3(-1.1, 1.6, 4.2)))
        parts.append(K.placed(K.panel(width: 11, height: 12, R(.fire)), at: CV3(0, 9, 3.6)))
        parts.append(K.placed(K.panel(width: 11.2, height: 12.2, R(.mica)), at: CV3(0, 9, 4.5)))
        // 薪
        for (x, yaw) in [(-2.5, 0.2), (1.8, -0.35), (0.2, 0.9)] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.9, 0), CV2(0.9, 6), CV2(0, 6)], segments: 10, R(.wornWood(.oak))),
                                  at: CV3(x, 2.4, 2.2), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2) * CQuat.axisAngle(CV3(0, 1, 0), yaw)))
        }
        // マントルと上の置物
        parts.append(K.block(CV3(26, 2.2, 8), at: CV3(0, 29.2, 0), radius: 0.4, R(.wood(.walnut))))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.4, 0), CV2(1.5, 4), CV2(0.9, 4.6), CV2(0, 4.6)], segments: 14, R(.brass)),
                              at: CV3(-7, 31.4, 1)))
        parts.append(K.placed(K.roundedBox(CV3(4, 2.2, 3.2), radius: 0.4, segments: 2, R(.wood(.birch))), at: CV3(6, 32.2, 0.5)))
        // 煙突
        parts.append(K.block(CV3(10, 54, 8), at: CV3(0, 31.4, -1.5), radius: 0.3, brick))
        for row in 0..<12 {
            for col in 0..<2 {
                let light = (row + col) % 2 == 0
                parts.append(K.block(CV3(4.4, 4, 0.3), at: CV3(-2.2 + Double(col) * 4.4, 33 + Double(row) * 4.2, 2.6), radius: 0.05,
                                     light ? cream : soot))
            }
        }
        parts.append(K.block(CV3(12, 1.4, 9), at: CV3(0, 86.2, -1.5), radius: 0.3, R(.castIron)))
        return K.merge(parts)
    }

    /// 和紙の柱（木の台と枠・和紙の四角い筒・中の電球・上の木の蓋）
    static func paperColumn() -> CamperMesh {
        var parts: [CamperMesh] = []
        let cedar = R(.wood(.cedar))
        parts.append(K.block(CV3(8.4, 1.6, 8.4), at: .zero, radius: 0.4, cedar))
        // 四隅の柱と桟
        for (x, z) in [(-3.2, -3.2), (3.2, -3.2), (-3.2, 3.2), (3.2, 3.2)] {
            parts.append(K.block(CV3(1.0, 50, 1.0), at: CV3(x, 1.6, z), radius: 0.15, cedar))
        }
        for y in [1.6, 18.0, 34.0, 50.0] {
            for (a, b) in [((-3.2, -3.2), (3.2, -3.2)), ((-3.2, 3.2), (3.2, 3.2)), ((-3.2, -3.2), (-3.2, 3.2)), ((3.2, -3.2), (3.2, 3.2))] {
                parts.append(K.tube([CV3(a.0, y, a.1), CV3(b.0, y, b.1)], radius: 0.22, sides: 5, cedar))
            }
        }
        // 和紙の面 4（少し内側）
        for (nx, nz) in [(0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0)] {
            let c = CV3(nx * 3.0, 26.6, nz * 3.0)
            let q = abs(nx) > 0.5 ? CQuat.axisAngle(CV3(0, 1, 0), .pi / 2) : .identity
            parts.append(K.placed(K.panel(width: 5.8, height: 48, R(.shade(0xF2EEE4))), at: c, rotation: q))
            parts.append(K.placed(K.panel(width: 5.6, height: 47.6, R(.paper)), at: c + CV3(nx * 0.08, 0, nz * 0.08), rotation: q))
        }
        parts.append(K.placed(K.sphere(radius: 2.2, segments: 14, R(.bulb)), at: CV3(0, 28, 0)))
        parts.append(K.block(CV3(8.2, 1.4, 8.2), at: CV3(0, 51.6, 0), radius: 0.35, cedar))
        parts.append(K.placed(K.disc(radius: 1.2, height: 0.6, bevel: 0.2, segments: 12, R(.brass)), at: CV3(0, 53.0, 0)))
        return K.merge(parts)
    }

    // MARK: 壁

    /// 角の棚（壁の角に三角の板 2・真鍮の受け・小さな鉢と本）
    static func floatingCorner() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak))
        // 1 マス × 1 段。壁面（z≈0）から外へ三角。xs は ±5 以内
        for (y, size) in [(5.5, 8.0), (13.5, 6.5)] {
            // 横断面（x–z）の三角を薄い押し出しにして水平の棚にする
            let tri: [CV2] = [CV2(-size / 2, 0.2), CV2(size / 2, 0.2), CV2(0, size * 0.85)]
            let shelf = CamperMeshKit.extrude(tri, depth: 0.7, front: oak, side: R(.wornWood(.oak)), bevel: 0.15)
            // extrude は XY・厚み Z → X まわり +90° で z=輪郭の y（壁から外へ）、厚みは −Y。y を棚の高さへ上げる
            parts.append(K.placed(shelf, at: CV3(0, y + 0.7, 0), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
            parts.append(K.tube([CV3(-size / 2 + 0.7, y - 0.35, 0.4), CV3(-size / 2 + 0.7, y - 0.35, size * 0.5)], radius: 0.16, sides: 5, R(.brass)))
            parts.append(K.tube([CV3(size / 2 - 0.7, y - 0.35, 0.4), CV3(size / 2 - 0.7, y - 0.35, size * 0.5)], radius: 0.16, sides: 5, R(.brass)))
        }
        parts.append(CamperRoomShapes.pottedPlant(at: CV3(0, 6.2, 2.8), potRadius: 1.0, height: 1.6, leaves: 4, spread: 1.4))
        parts.append(K.block(CV3(1.1, 3.2, 2.4), at: CV3(-1.4, 14.2, 2.2), radius: 0.15, R(.painted(0x5E3A2A))))
        parts.append(K.block(CV3(0.9, 2.8, 2.2), at: CV3(-0.2, 14.2, 2.2), radius: 0.15, R(.painted(0x2F4F74))))
        return K.merge(parts)
    }

    /// 絵はがきの列（6 枚をマスキングテープで・少し傾きと重なり）
    static func postcardGrid() -> CamperMesh {
        var parts: [CamperMesh] = []
        let colors: [UInt32] = [0xD9CDB4, 0xE8E1D2, 0xC9B89A, 0xF2EEE4, 0xDED2BC, 0xE6DCC6]
        let y0 = 10.0
        for k in 0..<6 {
            let col = k % 3, row = k / 3
            let x = -9.5 + Double(col) * 9.5
            let y = y0 + (row == 0 ? 4.5 : -4.5)
            let yaw = (Double(k) - 2.5) * 0.04
            let c = CV3(x, y, 0.2 + Double(k) * 0.04)
            parts.append(K.placed(CamperRoomShapes.paperSheet(width: 8.2, height: 5.6, curl: 0.35, R(.paperColor(colors[k]))), at: c,
                                  rotation: CQuat.axisAngle(CV3(0, 0, 1), yaw)))
            // 写真面（絵はがきの印画）
            parts.append(K.placed(CamperRoomShapes.paperSheet(width: 7.0, height: 4.4, curl: 0.3, R(.mapPrint)), at: c + CV3(0, 0, 0.05),
                                  rotation: CQuat.axisAngle(CV3(0, 0, 1), yaw)))
            // テープ
            parts.append(K.placed(K.panel(width: 2.4, height: 0.9, R(.linen(0xE8DDB8))), at: c + CV3(-2.8, 2.4, 0.1),
                                  rotation: CQuat.axisAngle(CV3(0, 0, 1), yaw + 0.5)))
            parts.append(K.placed(K.panel(width: 2.4, height: 0.9, R(.linen(0xE8DDB8))), at: c + CV3(2.8, -2.4, 0.1),
                                  rotation: CQuat.axisAngle(CV3(0, 0, 1), yaw - 0.4)))
        }
        return K.merge(parts)
    }

    /// タペストリー（木の棒・麻ひも・布・裾のぎざぎざ）。2 段（高さ ≤ 41）
    static func tapestry() -> CamperMesh {
        var parts: [CamperMesh] = []
        let cloth = R(.canvas(0x8A6A4A))
        // 棒（横）・吊りひも・釘。布の中心 y=22。横幅は 3 マス（≤ 31）
        parts.append(K.block(CV3(28, 1.0, 1.0), at: CV3(0, 35.5, 0.7), radius: 0.35, R(.wood(.walnut))))
        for x in [-11.0, 11.0] {
            parts.append(K.tube([CV3(x, 36.2, 0.7), CV3(x, 38.0, 0.75), CV3(0, 39.0, 0.8)], radius: 0.12, sides: 4, R(.rope)))
        }
        parts.append(K.placed(K.disc(radius: 0.4, height: 0.45, bevel: 0.12, segments: 10, R(.brass)), at: CV3(0, 39.1, 0.55),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.placed(K.panel(width: 24, height: 24, cloth), at: CV3(0, 22.5, 0.55)))
        parts.append(K.placed(K.panel(width: 18, height: 12, R(.canvas(0xC9A66B))), at: CV3(0, 24, 0.62)))
        for k in 0..<8 {
            let x = -10.5 + Double(k) * 3.0
            let tri: [CV2] = [CV2(-1.3, 0), CV2(1.3, 0), CV2(0, -2.6)]
            parts.append(K.placed(CamperMeshKit.extrude(tri, depth: 0.2, front: cloth, side: cloth, bevel: 0.04),
                                  at: CV3(x, 10.6, 0.7)))
        }
        return K.merge(parts)
    }

    /// 掛けたランタン（鉄の鉤・黒いランタン・硝子の面・中の炎）
    static func lanternHook() -> CamperMesh {
        var parts: [CamperMesh] = []
        let iron = R(.iron)
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        // 壁の座と鉤
        parts.append(K.placed(K.disc(radius: 1.6, height: 0.5, bevel: 0.15, segments: 14, iron), at: CV3(0, 16, 0), rotation: toWall))
        parts.append(K.tube([CV3(0, 16, 0.4), CV3(0, 16, 3.2), CV3(0, 14.5, 4.5), CV3(0, 12.5, 4.8)], radius: 0.28, sides: 8, iron))
        parts.append(K.tube(K.arc(center: CV3(0, 11.2, 4.8), radius: 1.4, from: .pi * 0.15, to: .pi * 0.85, steps: 10).map { CV3($0.x, $0.y, 4.8) },
                            radius: 0.22, sides: 6, iron))
        // ランタン本体
        let base = CV3(0, 4.5, 4.8)
        parts.append(K.placed(K.block(CV3(5.2, 1.2, 5.2), at: .zero, radius: 0.3, iron), at: base))
        parts.append(K.placed(K.block(CV3(4.6, 7.5, 4.6), at: CV3(0, 1.2, 0), radius: 0.25, R(.castIron)), at: base))
        parts.append(K.placed(K.block(CV3(5.4, 1.0, 5.4), at: CV3(0, 8.6, 0), radius: 0.3, iron), at: base))
        // 硝子 4 面と中の炎
        for (nx, nz) in [(0.0, 1.0), (0.0, -1.0), (1.0, 0.0), (-1.0, 0.0)] {
            let q = abs(nx) > 0.5 ? CQuat.axisAngle(CV3(0, 1, 0), .pi / 2) : .identity
            parts.append(K.placed(K.panel(width: 3.6, height: 6.2, R(.mica)), at: base + CV3(nx * 2.35, 4.8, nz * 2.35), rotation: q))
        }
        parts.append(K.placed(K.panel(width: 3.0, height: 4.5, R(.fire)), at: base + CV3(0, 4.5, 2.0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.5, 0.6), CV2(0.35, 1.6), CV2(0, 2.2)], segments: 10, R(.fire)), at: base + CV3(0, 2.4, 0)))
        // 持ち手の輪
        parts.append(K.tube(K.arc(center: base + CV3(0, 10.2, 0), radius: 1.5, from: 0.2, to: .pi - 0.2, steps: 12).map { CV3($0.x, $0.y, base.z) },
                            radius: 0.2, sides: 5, R(.agedBrass)))
        return K.merge(parts)
    }

    // MARK: 天井

    /// 小さな旗（紐に三角の旗 9）
    static func bunting() -> CamperMesh {
        var parts: [CamperMesh] = []
        let cord = (0...24).map { k -> CV3 in
            let t = Double(k) / 24
            return CV3(-29 + 58 * t, -1.5 - 5 * sin(t * .pi), 0)
        }
        parts.append(K.tube(cord, radius: 0.14, sides: 4, R(.rope)))
        let colors: [UInt32] = [0xC9584A, 0xD9A441, 0x2F6A8C, 0xEDE8DE, 0x5E8A4A, 0xB5653F, 0x6A4A8C, 0x3E8A8A, 0xD9C27A]
        for k in 0..<9 {
            let t = (Double(k) + 0.5) / 9
            let p = CV3(-29 + 58 * t, -1.5 - 5 * sin(t * .pi), 0)
            let tri: [CV2] = [CV2(-2.2, 0), CV2(2.2, 0), CV2(0, -5.5)]
            parts.append(K.placed(CamperMeshKit.extrude(tri, depth: 0.2, front: R(.paperColor(colors[k])), side: R(.paperColor(colors[k])),
                                                        bevel: 0.05), at: p + CV3(0, -0.2, 0)))
            parts.append(K.tube([p + CV3(-2.0, 0, 0), p + CV3(2.0, 0, 0)], radius: 0.1, sides: 4, R(.rope)))
        }
        return K.merge(parts)
    }

    /// 吊り籠（天井のひも・籐の籠・垂れるつる）
    static func hangingBasket() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube(K.arc(center: CV3(0, -1.4, 0), radius: 0.9, from: 0, to: 2 * .pi, steps: 12).map { CV3($0.x, $0.y, 0) }, radius: 0.18,
                            sides: 5, closed: true, R(.brass)))
        let pot = -18.0
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi
            parts.append(K.tube([CV3(0, -2.2, 0), CV3(cos(a) * 3.5, pot + 2, sin(a) * 3.5)], radius: 0.2, sides: 5, R(.rope)))
        }
        let outer: [CV2] = [CV2(0, 0), CV2(4.2, 0), CV2(5.2, 2), CV2(5.6, 5.5), CV2(5.2, 6), CV2(0, 6)]
        let inner: [CV2] = [CV2(0, 0.4), CV2(3.8, 0.4), CV2(4.8, 2), CV2(5.1, 5.4), CV2(0, 5.4)]
        parts.append(K.placed(K.vessel(outer: outer, inner: inner, segments: 28, R(.wicker)), at: CV3(0, pot, 0)))
        parts.append(K.placed(K.disc(radius: 4.8, height: 0.35, bevel: 0.1, segments: 22, R(.soil)), at: CV3(0, pot + 5.2, 0)))
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            let tip = CV3(cos(a) * 3.5, pot + 9 + Double(k % 3), sin(a) * 3.5)
            parts.append(K.tube([CV3(0, pot + 5.4, 0), tip], radius: 0.08, sides: 4, R(.leaf)))
            parts.append(CamperRoomShapes.leaf(at: tip, toward: CV3(cos(a), 0.4, sin(a)), size: 2.0))
        }
        parts.append(CamperRoomShapes.trailingVines(at: CV3(0, pot + 5.0, 0), count: 7, length: 14))
        return K.merge(parts)
    }

    /// 硝子の球（真鍮の輪・透明の球・中の小さな山と木）
    static func glassTerrarium() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube([CV3(0, 0, 0), CV3(0, -8, 0)], radius: 0.08, sides: 3, R(.paper)))
        parts.append(K.tube(K.arc(center: CV3(0, -10, 0), radius: 2.2, from: 0, to: 2 * .pi, steps: 20), radius: 0.25, sides: 6, closed: true,
                            R(.brass)))
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi
            parts.append(K.tube([CV3(0, -10, 0), CV3(cos(a) * 3.8, -16, sin(a) * 3.8)], radius: 0.12, sides: 4, R(.brass)))
        }
        let ball = CV3(0, -20, 0)
        parts.append(K.placed(K.sphere(radius: 7.2, segments: 28, R(.glass)), at: ball))
        // 中の地形
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(4.5, 0), CV2(3.2, 1.6), CV2(1.5, 3.4), CV2(0, 4.2)], segments: 20, R(.soil)),
                              at: ball + CV3(0, -5.2, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.2, 0), CV2(1.4, 2.2), CV2(0, 3.6)], segments: 14, R(.ceramic(0x8A8A82))),
                              at: ball + CV3(1.2, -3.6, -0.8)))
        for k in 0..<5 {
            let a = Double(k) / 5 * 2 * .pi + 0.4
            let p = ball + CV3(cos(a) * 2.4, -2.5, sin(a) * 2.4)
            parts.append(K.tube([p, p + CV3(0, 2.8 + Double(k % 2), 0)], radius: 0.15, sides: 5, R(.wood(.pine))))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.4, 0), CV2(0.2, 3.2), CV2(0, 3.2)], segments: 10, R(.leaf)),
                                  at: p + CV3(0, 2.2, 0)))
        }
        parts.append(CamperRoomShapes.leaf(at: ball + CV3(-2, -1, 1.5), toward: CV3(-0.5, 0.2, 0.3), size: 1.4))
        parts.append(CamperRoomShapes.leaf(at: ball + CV3(2.2, -0.8, -1), toward: CV3(0.6, 0.1, -0.4), size: 1.2))
        return K.merge(parts)
    }
}
