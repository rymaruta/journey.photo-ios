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
        // 脚と框（8×3 マス・高さ 36）。2026-10-22: 脚は両端の格子の真下に（前は格子と框の外へ 2 cm はみ出した）
        for (x, z) in [(-37.5, -12.9), (37.5, -12.9), (-37.5, 12.9), (37.5, 12.9)] {
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
        // 煙突の笠（煙突の上端 85.4 に載せる。2026-10-22: 前は 2 cm 浮いていた）
        parts.append(K.block(CV3(12, 1.4, 9), at: CV3(0, 85.4, -1.5), radius: 0.3, R(.castIron)))
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
        // 電球は上の蓋から下げた受け口と紐で吊る（2026-10-22: 前は筒の真ん中の宙に浮いていた）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.9, 0), CV2(0.9, 1.8), CV2(0.5, 2.2), CV2(0, 2.2)], segments: 12, R(.brass)),
                              at: CV3(0, 29.6, 0)))
        parts.append(K.tube([CV3(0, 31.6, 0), CV3(0, 51.8, 0)], radius: 0.2, sides: 6, R(.iron)))
        parts.append(K.block(CV3(8.2, 1.4, 8.2), at: CV3(0, 51.6, 0), radius: 0.35, cedar))
        parts.append(K.placed(K.disc(radius: 1.2, height: 0.6, bevel: 0.2, segments: 12, R(.brass)), at: CV3(0, 53.0, 0)))
        return K.merge(parts)
    }

    // MARK: 壁

    /// 角の棚（壁の角に三角の板 2・真鍮の受け・小さな鉢と本）
    /// 角の棚（三角板 2・縁の面取り・真鍮支え・鉢・本・小さな瓶）
    static func floatingCorner() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak)), worn = R(.wornWood(.oak)), brass = R(.brass)
        // 1 マス × 1 段。壁面（z≈0）から外へ三角。xs は ±5 以内
        for (y, size) in [(5.2, 8.4), (13.2, 6.8)] {
            let tri: [CV2] = [CV2(-size / 2, 0.15), CV2(size / 2, 0.15), CV2(0, size * 0.88)]
            let shelf = CamperMeshKit.extrude(tri, depth: 0.95, front: oak, side: worn, bevel: 0.2)
            parts.append(K.placed(shelf, at: CV3(0, y + 0.95, 0), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
            // 前縁の細い帯
            parts.append(K.tube([CV3(-size / 2 + 0.4, y + 0.95, size * 0.12),
                                 CV3(0, y + 0.95, size * 0.82),
                                 CV3(size / 2 - 0.4, y + 0.95, size * 0.12)],
                                radius: 0.1, sides: 4, worn))
            for s in [-1.0, 1.0] {
                parts.append(K.tube([CV3(s * (size / 2 - 0.6), y - 0.2, 0.35),
                                     CV3(s * (size / 2 - 0.6), y - 0.2, size * 0.55)],
                                    radius: 0.18, sides: 6, brass))
                parts.append(K.placed(K.sphere(radius: 0.28, segments: 8, brass),
                                      at: CV3(s * (size / 2 - 0.6), y - 0.2, 0.35)))
            }
        }
        parts.append(CamperRoomShapes.pottedPlant(at: CV3(0.2, 6.15, 3.0), potRadius: 1.15, height: 1.8, leaves: 5, spread: 1.55))
        parts.append(K.block(CV3(1.15, 3.4, 2.5), at: CV3(-1.5, 14.15, 2.3), radius: 0.15, R(.painted(0x5E3A2A))))
        parts.append(K.block(CV3(0.95, 3.0, 2.3), at: CV3(-0.25, 14.15, 2.3), radius: 0.15, R(.painted(0x2F4F74))))
        parts.append(K.block(CV3(0.85, 2.6, 2.1), at: CV3(0.9, 14.15, 2.1), radius: 0.12, R(.painted(0xD9CDB4))))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.7, 0), CV2(0.75, 2.2), CV2(0.45, 2.6), CV2(0, 2.6)],
                                      segments: 12, R(.clearGlass)), at: CV3(1.6, 6.15, 2.0)))
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
        let field = R(.canvas(0xC9A66B))
        let dark = R(.canvas(0x5C4030))
        // 棒（節のある丸棒）・吊りひも・釘
        parts.append(K.tube((0...16).map { i -> CV3 in
            let t = Double(i) / 16
            return CV3(-14 + 28 * t, 35.5, 0.7 + 0.12 * sin(t * .pi * 3))
        }, radius: 0.55, sides: 10, R(.wood(.walnut))))
        for x in [-12.0, 12.0] {
            parts.append(K.placed(K.disc(radius: 0.7, height: 0.4, bevel: 0.12, segments: 10, R(.brass)),
                                  at: CV3(x, 35.5, 0.7), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2)))
            parts.append(K.tube([CV3(x, 36.1, 0.7), CV3(x * 0.35, 38.2, 0.8), CV3(0, 39.2, 0.85)],
                                radius: 0.14, sides: 5, R(.rope)))
        }
        parts.append(K.placed(K.disc(radius: 0.55, height: 0.5, bevel: 0.15, segments: 12, R(.brass)),
                              at: CV3(0, 39.3, 0.55), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        // 布の地・縁取り・中央の文様（幾何を押し出し）
        parts.append(K.placed(K.panel(width: 24, height: 24, cloth), at: CV3(0, 22.5, 0.5)))
        parts.append(K.placed(CamperMeshKit.extrude(K.roundedRect(22, 22, r: 0.3), holes: [K.roundedRect(18.5, 18.5, r: 0.2)],
                                                    depth: 0.25, front: dark, side: dark, bevel: 0.06),
                              at: CV3(0, 22.5, 0.7)))
        parts.append(K.placed(K.panel(width: 17, height: 11, field), at: CV3(0, 24.5, 0.72)))
        for row in 0..<3 {
            for col in 0..<5 {
                let x = -6.5 + Double(col) * 3.25
                let y = 21.5 + Double(row) * 2.6
                let diamond: [CV2] = [CV2(0, 1.05), CV2(0.95, 0), CV2(0, -1.05), CV2(-0.95, 0)]
                // 浮かせた文様（穴に見えないよう地より手前・色を分ける）
                parts.append(K.placed(CamperMeshKit.extrude(diamond, depth: 0.28, front: R(.canvas(0x6B4423)),
                                                            side: R(.canvas(0x4A3220)), bevel: 0.05),
                                      at: CV3(x, y, 0.9)))
            }
        }
        // 横の縫い目
        for y in [12.5, 32.5] as [Double] {
            parts.append(K.tube([CV3(-11.5, y, 0.75), CV3(11.5, y, 0.75)], radius: 0.1, sides: 4, R(.rope)))
        }
        // 裾のぎざぎざ（厚みと房）
        for k in 0..<9 {
            let x = -12.0 + Double(k) * 3.0
            let tri: [CV2] = [CV2(-1.4, 0), CV2(1.4, 0), CV2(0, -3.0)]
            parts.append(K.placed(CamperMeshKit.extrude(tri, depth: 0.35, front: cloth, side: dark, bevel: 0.06),
                                  at: CV3(x, 10.5, 0.7)))
            for f in 0..<3 {
                parts.append(K.tube([CV3(x - 0.6 + Double(f) * 0.6, 10.5 - 2.8, 0.7),
                                     CV3(x - 0.6 + Double(f) * 0.6, 8.2 - Double(f % 2) * 0.4, 0.75)],
                                    radius: 0.08, sides: 4, R(.rope)))
            }
        }
        return K.merge(parts)
    }

    /// 掛けたランタン（壁座・鉤・鎖・屋根・硝子枠・換気穴・炎）
    static func lanternHook() -> CamperMesh {
        var parts: [CamperMesh] = []
        let iron = R(.iron), cast = R(.castIron)
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(K.disc(radius: 1.8, height: 0.55, bevel: 0.18, segments: 18, iron), at: CV3(0, 17.5, 0), rotation: toWall))
        for (dx, dy) in [(-0.9, 0.9), (0.9, 0.9), (-0.9, -0.9), (0.9, -0.9)] {
            parts.append(K.placed(K.sphere(radius: 0.16, segments: 6, R(.agedBrass)), at: CV3(dx, 17.5 + dy, 0.45)))
        }
        parts.append(K.tube([CV3(0, 17.5, 0.45), CV3(0, 17.5, 3.4), CV3(0, 15.8, 4.8), CV3(0, 13.8, 5.1)],
                            radius: 0.3, sides: 9, iron))
        parts.append(K.tube(K.arc(center: CV3(0, 12.4, 5.1), radius: 1.5, from: .pi * 0.12, to: .pi * 0.88, steps: 12)
                                .map { CV3($0.x, $0.y, 5.1) }, radius: 0.24, sides: 7, iron))
        // 短い鎖
        for i in 0..<3 {
            parts.append(K.placed(K.tube(K.arc(center: .zero, radius: 0.45, from: 0, to: 2 * .pi, steps: 10),
                                         radius: 0.08, sides: 5, closed: true, R(.agedBrass)),
                                  at: CV3(0, 12.0 - Double(i) * 0.7, 5.1),
                                  rotation: CQuat.axisAngle(CV3(0, 0, 1), Double(i) * 0.5)))
        }
        let base = CV3(0, 3.8, 5.1)
        parts.append(K.placed(K.block(CV3(5.4, 1.3, 5.4), at: .zero, radius: 0.35, iron), at: base))
        parts.append(K.placed(K.block(CV3(4.7, 7.8, 4.7), at: CV3(0, 1.3, 0), radius: 0.28, cast), at: base))
        // ピラミッド屋根
        let roof = CamperRoomShapes.extrudeAlongX([CV2(-3.2, 0), CV2(3.2, 0), CV2(0, 2.4)], length: 5.6, inset: 0.2, iron)
        parts.append(K.placed(K.placed(roof, at: .zero, yaw: .pi / 2), at: base + CV3(0, 9.2, 0)))
        parts.append(K.placed(K.sphere(radius: 0.4, segments: 8, R(.agedBrass)), at: base + CV3(0, 14.4, 0)))
        // 換気穴
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi
            parts.append(K.placed(K.disc(radius: 0.22, height: 0.15, bevel: 0.05, segments: 8, R(.painted(0x0A0A0A))),
                                  at: base + CV3(cos(a) * 1.8, 9.6, sin(a) * 1.8),
                                  rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        }
        // 角柱と硝子
        for (nx, nz) in [(1.0, 1.0), (1.0, -1.0), (-1.0, 1.0), (-1.0, -1.0)] {
            parts.append(K.tube([base + CV3(nx * 2.15, 1.3, nz * 2.15), base + CV3(nx * 2.15, 9.0, nz * 2.15)],
                                radius: 0.18, sides: 5, iron))
        }
        for (nx, nz) in [(0.0, 1.0), (0.0, -1.0), (1.0, 0.0), (-1.0, 0.0)] {
            let q = abs(nx) > 0.5 ? CQuat.axisAngle(CV3(0, 1, 0), .pi / 2) : .identity
            parts.append(K.placed(K.panel(width: 3.5, height: 6.4, R(.mica)),
                                  at: base + CV3(nx * 2.4, 5.0, nz * 2.4), rotation: q))
        }
        parts.append(K.placed(K.panel(width: 2.8, height: 4.2, R(.fire)), at: base + CV3(0, 4.6, 2.05)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.55, 0.5), CV2(0.4, 1.8), CV2(0, 2.5)], segments: 12, R(.fire)),
                              at: base + CV3(0, 2.2, 0)))
        parts.append(K.tube(K.arc(center: base + CV3(0, 11.8, 0), radius: 1.55, from: 0.15, to: .pi - 0.15, steps: 14)
                                .map { CV3($0.x, $0.y, base.z) }, radius: 0.2, sides: 6, R(.agedBrass)))
        return K.merge(parts)
    }

    // MARK: 天井

    /// 小さな旗（太い紐・両端の輪・厚みのある三角旗 9・縫い代と小さな房）
    static func bunting() -> CamperMesh {
        var parts: [CamperMesh] = []
        let cord = (0...32).map { k -> CV3 in
            let t = Double(k) / 32
            return CV3(-29 + 58 * t, -1.5 - 5.2 * sin(t * .pi), 0.2 * sin(t * .pi * 2))
        }
        parts.append(K.tube(cord, radius: 0.22, sides: 6, R(.rope)))
        // 両端の輪は天井より上へ出さない（y ≤ 0）
        for x in [-29.0, 29.0] {
            parts.append(K.tube(K.arc(center: CV3(x, -1.3, 0), radius: 1.0, from: 0, to: 2 * .pi, steps: 14)
                                    .map { CV3($0.x, $0.y, 0) }, radius: 0.16, sides: 5, closed: true, R(.brass)))
        }
        let colors: [UInt32] = [0xC9584A, 0xD9A441, 0x2F6A8C, 0xEDE8DE, 0x5E8A4A, 0xB5653F, 0x6A4A8C, 0x3E8A8A, 0xD9C27A]
        for k in 0..<9 {
            let t = (Double(k) + 0.5) / 9
            let p = CV3(-29 + 58 * t, -1.5 - 5.2 * sin(t * .pi), 0)
            let c = R(.paperColor(colors[k]))
            // 少しひらいた三角（表と裏で色の向き）
            let tri: [CV2] = [CV2(-2.4, 0.15), CV2(2.4, 0.15), CV2(0.15, -5.8), CV2(-0.15, -5.8)]
            parts.append(K.placed(CamperMeshKit.extrude(tri, depth: 0.45, front: c, side: R(.paperColor(colors[(k + 3) % 9])),
                                                        bevel: 0.08), at: p + CV3(0, -0.15, 0)))
            // 上縁の縫い代
            parts.append(K.tube([p + CV3(-2.3, 0.05, 0.2), p + CV3(2.3, 0.05, 0.2)], radius: 0.14, sides: 5, R(.rope)))
            parts.append(K.placed(K.sphere(radius: 0.28, segments: 8, R(.wood(.cedar))), at: p + CV3(0, 0.1, 0.15)))
            // 先端の小さな房
            for f in 0..<3 {
                let a = Double(f) / 3 * 2 * .pi
                parts.append(K.tube([p + CV3(0, -5.7, 0), p + CV3(cos(a) * 0.35, -7.0, sin(a) * 0.35)],
                                    radius: 0.07, sides: 3, c))
            }
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

    /// 硝子の球（真鍮の吊り・二重の輪・透明の球・山・木・石・小さな池）
    static func glassTerrarium() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube([CV3(0, 0, 0), CV3(0, -4, 0), CV3(0, -8.5, 0)], radius: 0.12, sides: 5, R(.rope)))
        parts.append(K.placed(K.sphere(radius: 0.45, segments: 10, R(.brass)), at: CV3(0, -4, 0)))
        parts.append(K.tube(K.arc(center: CV3(0, -10.2, 0), radius: 2.4, from: 0, to: 2 * .pi, steps: 24),
                            radius: 0.28, sides: 8, closed: true, R(.brass)))
        parts.append(K.tube(K.arc(center: CV3(0, -10.2, 0), radius: 1.5, from: 0, to: 2 * .pi, steps: 18),
                            radius: 0.14, sides: 6, closed: true, R(.agedBrass)))
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi
            parts.append(K.tube([CV3(0, -10.2, 0), CV3(cos(a) * 4.0, -16.2, sin(a) * 4.0)], radius: 0.14, sides: 5, R(.brass)))
        }
        let ball = CV3(0, -20.2, 0)
        parts.append(K.placed(K.sphere(radius: 7.4, segments: 32, R(.globeGlass)), at: ball))
        // 映りの筋（上の斜めに細い弧 2 本・向かい合わせ。どちらから見ても 1 本は見える）
        for side in [0.0, Double.pi] {
            parts.append(CamperRoomShapes.sphereBand(center: ball, radius: 7.46, latitudes: 0.55...0.72,
                                                     longitudes: (side + 2.0)...(side + 2.9), R(.globeGlint)))
        }
        // 赤道の真鍮帯
        parts.append(K.tube(K.ringXZ(center: ball, radius: 7.35, steps: 36), radius: 0.12, sides: 5, closed: true, R(.agedBrass)))
        // 地形
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(4.8, 0), CV2(3.6, 1.4), CV2(2.0, 3.2), CV2(0.8, 4.6), CV2(0, 5.0)],
                                      segments: 24, R(.soil)), at: ball + CV3(0, -5.4, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.4, 0), CV2(1.6, 2.0), CV2(0.6, 3.4), CV2(0, 3.8)],
                                      segments: 16, R(.ceramic(0x8A8A82))), at: ball + CV3(1.4, -3.4, -1.0)))
        // 小さな池
        parts.append(K.placed(K.disc(radius: 1.6, height: 0.25, bevel: 0.08, segments: 16, R(.tintedGlass(0x6E9FB0))),
                              at: ball + CV3(-2.0, -4.9, 1.6)))
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi + 0.3
            let p = ball + CV3(cos(a) * 2.6, -2.6, sin(a) * 2.6)
            parts.append(K.tube([p, p + CV3(0, 3.0 + Double(k % 2) * 0.8, 0)], radius: 0.16, sides: 6, R(.wood(.pine))))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.5, 0), CV2(0.9, 1.6), CV2(0.2, 3.4), CV2(0, 3.4)],
                                          segments: 12, R(.leaf)), at: p + CV3(0, 2.4, 0)))
        }
        // 石
        for (dx, dz, r) in [(-1.5, -2.0, 0.7), (2.2, 1.0, 0.55), (0.5, 2.4, 0.45)] as [(Double, Double, Double)] {
            parts.append(K.placed(K.scaled(K.sphere(radius: r, segments: 10, R(.ceramic(0x9A9688))), CV3(1.2, 0.7, 1.0)),
                                  at: ball + CV3(dx, -4.6, dz)))
        }
        parts.append(CamperRoomShapes.leaf(at: ball + CV3(-2.2, -0.8, 1.6), toward: CV3(-0.5, 0.25, 0.3), size: 1.5))
        parts.append(CamperRoomShapes.leaf(at: ball + CV3(2.4, -0.6, -1.2), toward: CV3(0.6, 0.15, -0.4), size: 1.3))
        return K.merge(parts)
    }
}
