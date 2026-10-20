import Foundation

// 家具の形・5 の組（2026-10-20）。鉢植え・旅の荷物・お茶・洗う物を一点ずつ作り込む。
// owner「もっと色々家具など増やしたいな／専用メッシュももっと作りたいね」。

private typealias K = CamperRoomMeshKit
private func R(_ m: CamperRoomMaterial) -> CamperMaterial { .room(m) }

extension CamperRoomFurnitureModels {

    /// 5 の組の家具の形
    static func moreMesh5(_ id: String) -> CamperMesh? {
        switch id {
        case "plant_pot.monstera": return monstera()
        case "plant_pot.cactus": return cactus()
        case "plant_pot.bonsai": return bonsai()
        case "plant_pot.herb_box": return herbBox()
        case "travel_bag.open_suitcase": return openSuitcase()
        case "travel_bag.backpack": return backpack()
        case "travel_bag.hat_box": return hatBox()
        case "travel_bag.map_stand": return mapStand()
        case "tea.teapot_tray": return teapotTray()
        case "tea.thermos": return thermos()
        case "tea.cake_stand": return cakeStand()
        case "tea.fruit_bowl": return fruitBowl()
        case "wash.towel_bar": return towelBar()
        case "wash.soap_niche": return soapNiche()
        case "wash.wash_basin": return washBasin()
        case "wash.cup_rail": return cupRail()
        default: return nil
        }
    }

    static func moreLamp5(_ id: String) -> (position: CV3, intensity: Double, range: Double)? {
        _ = id
        return nil
    }

    // MARK: 鉢植え

    /// モンステラ（テラコッタ鉢・太い茎・切れ込み葉）。2×2 マスに収める
    static func monstera() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(4.2, 0), CV2(4.8, 2), CV2(5.0, 9), CV2(4.6, 10), CV2(0, 10)],
                                      segments: 22, R(.terracotta)), at: .zero))
        parts.append(K.placed(K.disc(radius: 4.2, height: 0.35, bevel: 0.1, segments: 18, R(.soil)), at: CV3(0, 9.2, 0)))
        parts.append(K.tube([CV3(0, 9.5, 0), CV3(0, 26, 0), CV3(0.8, 34, 0.4)], radius: 0.5, sides: 7, R(.leaf)))
        for (i, a) in [0.2, 1.2, 2.2, 3.2, 4.2, 5.2].enumerated() {
            let y = 16.0 + Double(i) * 2.8
            let tip = CV3(cos(a) * 5.2, y + 1.5, sin(a) * 5.2)
            parts.append(K.tube([CV3(0, y - 1.5, 0), CV3(tip.x * 0.5, y, tip.z * 0.5), tip], radius: 0.16, sides: 5, R(.leaf)))
            parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 12, R(.leaf)), CV3(3.6, 0.3, 2.6)),
                                  at: tip + CV3(cos(a) * 1.2, 0.3, sin(a) * 1.2)))
            parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 8, R(.leaf)), CV3(1.6, 0.22, 1.2)),
                                  at: tip + CV3(cos(a + 0.5) * 2.6, -0.15, sin(a + 0.5) * 2.6)))
            parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 8, R(.leaf)), CV3(1.5, 0.22, 1.1)),
                                  at: tip + CV3(cos(a - 0.5) * 2.4, 0.2, sin(a - 0.5) * 2.4)))
        }
        return K.merge(parts)
    }

    /// サボテン（縦の畝・小さな棘・素焼き鉢）。1×1 マスに収める
    static func cactus() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.2, 0), CV2(3.6, 1.2), CV2(3.6, 6), CV2(3.2, 7), CV2(0, 7)],
                                      segments: 18, R(.terracotta)), at: .zero))
        parts.append(K.placed(K.disc(radius: 2.9, height: 0.3, bevel: 0.08, segments: 14, R(.soil)), at: CV3(0, 6.5, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.8, 0), CV2(2.0, 3), CV2(1.9, 18), CV2(1.5, 22), CV2(0, 22)],
                                      segments: 16, R(.painted(0x4A7A45))), at: CV3(0, 7, 0)))
        // 短い腕（マス内）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.2, 0), CV2(1.3, 5), CV2(1.0, 6), CV2(0, 6)],
                                      segments: 12, R(.painted(0x4A7A45))), at: CV3(1.6, 14, 0),
                              rotation: CQuat.axisAngle(CV3(0, 0, 1), -0.85)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.1, 0), CV2(1.2, 4), CV2(0.9, 5), CV2(0, 5)],
                                      segments: 12, R(.painted(0x4A7A45))), at: CV3(-1.4, 17, 0.3),
                              rotation: CQuat.axisAngle(CV3(0, 0, 1), 0.95)))
        for k in 0..<18 {
            let a = Double(k) / 18 * 2 * .pi
            let y = 9.0 + Double(k % 6) * 2.2
            parts.append(K.placed(K.sphere(radius: 0.15, segments: 5, R(.painted(0xE8E2D4))),
                                  at: CV3(cos(a) * 1.95, y, sin(a) * 1.95)))
        }
        return K.merge(parts)
    }

    /// 盆栽（浅い鉢・曲がった幹・小さな葉群）
    static func bonsai() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(7.5, 0), CV2(8.2, 1.2), CV2(7.8, 3.5), CV2(7.0, 4), CV2(0, 4)],
                                      segments: 24, R(.ceramic(0x2A2A2C))), at: .zero))
        parts.append(K.placed(K.disc(radius: 6.8, height: 0.3, bevel: 0.08, segments: 18, R(.soil)), at: CV3(0, 3.5, 0)))
        // 曲がった幹
        parts.append(K.tube([CV3(0, 3.8, 0), CV3(-1.5, 10, 0.5), CV3(2, 16, -0.5), CV3(0.5, 22, 0.8)],
                            radius: 0.7, sides: 8, R(.wornWood(.darkOak))))
        parts.append(K.tube([CV3(0.5, 18, 0.5), CV3(5, 20, 1.5), CV3(7, 21.5, 2)], radius: 0.35, sides: 6, R(.wornWood(.darkOak))))
        parts.append(K.tube([CV3(0.5, 18, 0.5), CV3(-4, 21, -1), CV3(-6, 22.5, -1.5)], radius: 0.3, sides: 6, R(.wornWood(.darkOak))))
        for (c, r) in [(CV3(0.5, 23.5, 0.8), 4.5), (CV3(7.2, 22.5, 2), 3.2), (CV3(-6.2, 23.5, -1.5), 3.0)] as [(CV3, Double)] {
            for k in 0..<10 {
                let a = Double(k) / 10 * 2 * .pi
                parts.append(CamperRoomShapes.leaf(at: c + CV3(cos(a) * r * 0.5, Double(k % 3) * 0.4, sin(a) * r * 0.5),
                                                   toward: CV3(cos(a), 0.4, sin(a)), size: 1.6))
            }
            parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 10, R(.leaf)), CV3(r * 0.7, r * 0.35, r * 0.7)), at: c))
        }
        return K.merge(parts)
    }

    /// ハーブ箱（木箱・土・3 株の葉）
    static func herbBox() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak))
        parts.append(K.block(CV3(26, 8, 14), at: CV3(0, 0, 0), radius: 0.4, oak))
        parts.append(K.block(CV3(24, 1.2, 12), at: CV3(0, 7.2, 0), radius: 0.2, R(.soil)))
        for x in [-12.5, 12.5] { parts.append(K.block(CV3(1.2, 9, 14), at: CV3(x, 0, 0), radius: 0.25, oak)) }
        for z in [-6.5, 6.5] { parts.append(K.block(CV3(26, 9, 1.2), at: CV3(0, 0, z), radius: 0.25, oak)) }
        let greens: [UInt32] = [0x5E8A4A, 0x4A7A45, 0x6E9A5A]
        for (i, x) in [(-8.0), (0.0), (8.0)].enumerated() {
            parts.append(K.tube([CV3(x, 8, 0), CV3(x, 16, 0)], radius: 0.2, sides: 5, R(.leaf)))
            for k in 0..<8 {
                let a = Double(k) / 8 * 2 * .pi + Double(i) * 0.3
                let tip = CV3(x + cos(a) * 3.5, 12 + Double(k % 3), sin(a) * 3.5)
                parts.append(CamperRoomShapes.leaf(at: tip, toward: CV3(cos(a), 0.6, sin(a)), size: 1.8))
                parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 8, R(.painted(greens[i]))), CV3(1.4, 0.2, 0.9)), at: tip))
            }
        }
        return K.merge(parts)
    }

    // MARK: 旅の荷物

    /// 開いたトランク（下箱・立てた蓋・中の服）。奥行きは 3 マス
    static func openSuitcase() -> CamperMesh {
        var parts: [CamperMesh] = []
        let leather = R(.leather(0x5E3A24)), dark = R(.leather(0x3E2618)), brass = R(.brass)
        parts.append(K.block(CV3(24, 7, 14), at: CV3(0, 0, 1), radius: 0.5, leather))
        parts.append(K.block(CV3(22, 0.6, 12), at: CV3(0, 6.2, 1), radius: 0.15, dark))
        // 立てた蓋（後ろへ開く・マス内）
        parts.append(K.placed(K.block(CV3(24, 7, 1.2), at: .zero, radius: 0.5, leather),
                              at: CV3(0, 9.5, -6.5), rotation: CQuat.axisAngle(CV3(1, 0, 0), -1.05)))
        parts.append(K.placed(K.block(CV3(22, 5.5, 0.5), at: .zero, radius: 0.2, dark),
                              at: CV3(0, 10, -5.9), rotation: CQuat.axisAngle(CV3(1, 0, 0), -1.05)))
        for x in [-7.0, 7.0] {
            parts.append(K.block(CV3(2.0, 0.6, 1.2), at: CV3(x, 6.8, -5.8), radius: 0.15, brass))
        }
        parts.append(K.block(CV3(3.2, 1.2, 1.0), at: CV3(0, 3.5, 7.8), radius: 0.2, brass))
        parts.append(K.placed(K.roundedBox(CV3(18, 2.2, 9), radius: 0.7, segments: 2, puff: 0.35, R(.cotton(0xE8E1D2))),
                              at: CV3(0, 8.0, 1)))
        parts.append(K.placed(K.roundedBox(CV3(7, 2.0, 3.5), radius: 0.5, segments: 2, puff: 0.25, R(.knit(0x2F4F74))),
                              at: CV3(-5, 8.5, 3.5)))
        parts.append(K.block(CV3(4.5, 2.2, 7), at: CV3(6.5, 7.2, -1), radius: 0.35, R(.leather(0x1A1A1C))))
        return K.merge(parts)
    }

    /// 背負い袋（胴・蓋・肩紐）
    static func backpack() -> CamperMesh {
        var parts: [CamperMesh] = []
        let canvas = R(.canvas(0x4A5A3A)), leather = R(.leather(0x3E2618)), brass = R(.brass)
        parts.append(K.placed(K.roundedBox(CV3(14, 22, 10), radius: 1.2, segments: 3, puff: 0.35, canvas), at: CV3(0, 11.2, 0)))
        parts.append(K.placed(K.roundedBox(CV3(12, 6, 8), radius: 1.0, segments: 2, puff: 0.4, leather), at: CV3(0, 25.2, 0.4)))
        parts.append(K.block(CV3(4, 1.2, 1.0), at: CV3(0, 22.7, 5.0), radius: 0.2, brass))
        parts.append(K.placed(K.roundedBox(CV3(10, 8, 2.5), radius: 0.7, segments: 2, puff: 0.25, canvas), at: CV3(0, 10.2, 5.2)))
        for s in [-1.0, 1.0] {
            parts.append(K.tube([CV3(s * 4, 24.2, -3.5), CV3(s * 5, 12.2, -4.5), CV3(s * 4.5, 2.2, -3.5)],
                                radius: 0.5, sides: 6, leather))
        }
        parts.append(K.tube([CV3(-4.5, 5.2, -3.5), CV3(4.5, 5.2, -3.5)], radius: 0.35, sides: 6, leather))
        return K.merge(parts)
    }

    /// 帽子箱（丸い蓋・リボン・中の麦わら）
    static func hatBox() -> CamperMesh {
        var parts: [CamperMesh] = []
        let paper = R(.painted(0xE8E0D0)), ribbon = R(.painted(0xC9584A))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(8, 0), CV2(8.2, 1), CV2(8.2, 12), CV2(8.0, 13), CV2(0, 13)],
                                      segments: 28, paper), at: .zero))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(8.6, 0), CV2(8.8, 0.8), CV2(8.6, 2.2), CV2(0, 2.2)],
                                      segments: 28, paper), at: CV3(0, 13, 0)))
        let band = K.arc(center: .zero, radius: 8.15, from: 0, to: 2 * .pi, steps: 32).map { CV3($0.x, 7, $0.y) }
        parts.append(K.tube(band, radius: 0.35, sides: 6, closed: true, ribbon))
        parts.append(K.block(CV3(3.5, 0.5, 6), at: CV3(8.8, 7, 0), radius: 0.15, ribbon))
        parts.append(K.block(CV3(3.5, 0.5, 6), at: CV3(-8.8, 7, 0), radius: 0.15, ribbon))
        // 中の帽子のつば（蓋の下に少し見える想定で上に）
        parts.append(K.placed(K.disc(radius: 6.5, height: 0.4, bevel: 0.1, segments: 20, R(.canvas(0xD9C27A))),
                              at: CV3(0, 14.5, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.2, 0), CV2(3.4, 2.5), CV2(0, 2.5)], segments: 16, R(.canvas(0xD9C27A))),
                              at: CV3(0, 14.7, 0)))
        return K.merge(parts)
    }

    /// 地図立て（木の脚・斜めの地図）
    static func mapStand() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak))
        for s in [-1.0, 1.0] {
            parts.append(K.tube([CV3(s * 6, 0.4, 3), CV3(s * 2, 18, -1), CV3(s * 1.5, 32, -2)], radius: 0.45, sides: 6, oak))
            parts.append(K.tube([CV3(s * 6, 0.4, 3), CV3(s * 5, 0.4, -4)], radius: 0.4, sides: 6, oak))
        }
        parts.append(K.tube([CV3(-6, 0.4, 3), CV3(6, 0.4, 3)], radius: 0.4, sides: 6, oak))
        parts.append(K.block(CV3(14, 1.0, 1.6), at: CV3(0, 20, -0.5), radius: 0.2, oak))
        parts.append(K.placed(K.panel(width: 16, height: 20, R(.canvas(0xE8E2D4))), at: CV3(0, 26, 0.5),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.35)))
        // 地図の線（薄い帯）
        for y in [22.0, 26.0, 30.0] {
            parts.append(K.placed(K.block(CV3(12, 0.25, 0.15), at: .zero, radius: 0.05, R(.painted(0x6E8FA3))),
                                  at: CV3(0, y, 1.2), rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.35)))
        }
        for x in [-4.0, 0.0, 4.0] {
            parts.append(K.placed(K.block(CV3(0.25, 14, 0.15), at: .zero, radius: 0.05, R(.painted(0xC9584A))),
                                  at: CV3(x, 26, 1.2), rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.35)))
        }
        return K.merge(parts)
    }

    // MARK: お茶

    /// 急須の盆（盆・急須・湯呑 2）
    static func teapotTray() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(18, 1.2, 12), at: CV3(0, 0, 0), radius: 0.4, R(.wood(.walnut))))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.2, 0), CV2(3.8, 2), CV2(3.5, 5), CV2(2.8, 6), CV2(0, 6)],
                                      segments: 18, R(.ceramic(0xE8E2D6))), at: CV3(-3, 1.2, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.6, 0), CV2(1.4, 1.5), CV2(0, 1.5)], segments: 12, R(.ceramic(0xE8E2D6))),
                              at: CV3(-3, 7.2, 0)))
        parts.append(K.tube([CV3(-3, 4, 3.5), CV3(-3, 4.5, 5), CV3(-3, 5.5, 5.5)], radius: 0.45, sides: 8, R(.ceramic(0xE8E2D6))))
        parts.append(K.tube([CV3(-0.2, 3.5, 0), CV3(0.8, 5, 0), CV3(-0.2, 6.5, 0)], radius: 0.35, sides: 8, R(.ceramic(0xE8E2D6))))
        for x in [5.0, 9.0] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.8, 0), CV2(2.0, 0.4), CV2(1.9, 4), CV2(1.7, 4.5), CV2(0, 4.5)],
                                          segments: 14, R(.ceramic(0x6E8FA3))), at: CV3(x, 1.2, 1)))
        }
        return K.merge(parts)
    }

    /// 魔法瓶（細い筒・ねじ蓋・持ち手）
    static func thermos() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.2, 0), CV2(3.4, 1), CV2(3.3, 22), CV2(3.0, 24), CV2(0, 24)],
                                      segments: 20, R(.chrome)), at: .zero))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.8, 0), CV2(3.0, 0.5), CV2(2.6, 3), CV2(0, 3)],
                                      segments: 16, R(.painted(0xC9584A))), at: CV3(0, 24, 0)))
        parts.append(K.block(CV3(1.2, 10, 0.6), at: CV3(3.6, 10, 0), radius: 0.2, R(.painted(0x2A2A2C))))
        parts.append(K.tube([CV3(3.8, 8, 0), CV3(5.2, 12, 0), CV3(5.2, 16, 0), CV3(3.8, 18, 0)],
                            radius: 0.35, sides: 6, R(.painted(0x2A2A2C))))
        parts.append(K.placed(K.disc(radius: 2.6, height: 0.3, bevel: 0.08, segments: 14, R(.chrome)), at: CV3(0, 0.2, 0)))
        return K.merge(parts)
    }

    /// ケーキ台（3 段の皿）
    static func cakeStand() -> CamperMesh {
        var parts: [CamperMesh] = []
        let china = R(.ceramic(0xF5F0E6)), stem = R(.chrome)
        parts.append(K.placed(K.disc(radius: 6, height: 0.8, bevel: 0.2, segments: 24, china), at: .zero))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.2, 0), CV2(1.0, 12), CV2(0, 12)], segments: 12, stem), at: CV3(0, 0.8, 0)))
        parts.append(K.placed(K.disc(radius: 7.5, height: 0.7, bevel: 0.2, segments: 24, china), at: CV3(0, 13, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.0, 0), CV2(0.85, 10), CV2(0, 10)], segments: 12, stem), at: CV3(0, 13.7, 0)))
        parts.append(K.placed(K.disc(radius: 5.5, height: 0.65, bevel: 0.2, segments: 24, china), at: CV3(0, 24, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.7, 0), CV2(0.55, 5), CV2(0, 5)], segments: 10, stem), at: CV3(0, 24.7, 0)))
        parts.append(K.placed(K.sphere(radius: 0.9, segments: 10, R(.brass)), at: CV3(0, 30.2, 0)))
        // 段の上の小さな菓子
        for (y, r, n) in [(1.0, 4.5, 5), (14.0, 5.5, 6), (24.8, 3.5, 4)] as [(Double, Double, Int)] {
            for k in 0..<n {
                let a = Double(k) / Double(n) * 2 * .pi
                parts.append(K.placed(K.sphere(radius: 0.7, segments: 8, R(.painted([0xC9584A, 0xD9A441, 0x6E8FA3, 0x5E8A4A][k % 4]))),
                                      at: CV3(cos(a) * r * 0.55, y, sin(a) * r * 0.55)))
            }
        }
        return K.merge(parts)
    }

    /// 果物鉢（深い鉢・実 5）
    static func fruitBowl() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.5, 0), CV2(5.5, 1.5), CV2(7.5, 5), CV2(7.2, 7), CV2(6.5, 7.5), CV2(0, 7.5)],
                                      segments: 24, R(.ceramic(0xE8E2D6)), capStart: true, capEnd: false), at: .zero))
        let fruits: [(CV3, Double, UInt32)] = [
            (CV3(0, 8.5, 0), 2.2, 0xC9584A),
            (CV3(-3, 8.2, 2), 1.8, 0xD9A441),
            (CV3(3.2, 8.3, 1.5), 1.7, 0xC9584A),
            (CV3(-2, 8.4, -2.5), 1.9, 0x6E8FA3),
            (CV3(2.5, 8.1, -2), 1.6, 0x5E8A4A),
        ]
        for (p, r, c) in fruits {
            parts.append(K.placed(K.sphere(radius: r, segments: 12, R(.painted(c))), at: p))
        }
        parts.append(K.tube([CV3(0, 10.5, 0), CV3(0, 12.5, 0)], radius: 0.12, sides: 4, R(.leaf)))
        parts.append(CamperRoomShapes.leaf(at: CV3(0.8, 12.2, 0.3), toward: CV3(1, 0.2, 0.3), size: 1.4))
        return K.merge(parts)
    }

    // MARK: 洗う物（壁）

    /// タオル掛け（棒・金具・掛かった布）。壁の後ろ（z &lt; 0）に出さない
    static func towelBar() -> CamperMesh {
        var parts: [CamperMesh] = []
        for x in [-12.0, 12.0] {
            parts.append(K.block(CV3(1.6, 1.6, 2.5), at: CV3(x, 10, 1.25), radius: 0.3, R(.chrome)))
            parts.append(K.tube([CV3(x, 10, 1.5), CV3(x, 10, 3.8)], radius: 0.35, sides: 8, R(.chrome)))
        }
        parts.append(K.tube([CV3(-12, 10, 3.8), CV3(12, 10, 3.8)], radius: 0.4, sides: 10, R(.chrome)))
        parts.append(K.placed(K.roundedBox(CV3(18, 14, 1.2), radius: 0.3, segments: 2, puff: 0.15, R(.cotton(0xE8E1D2))),
                              at: CV3(0, 3, 4.5)))
        parts.append(K.placed(K.roundedBox(CV3(16, 2, 1.0), radius: 0.25, segments: 2, puff: 0.2, R(.cotton(0xC9A66B))),
                              at: CV3(0, 9.5, 4.8)))
        return K.merge(parts)
    }

    /// 石けん棚（小さな棚・石けん・小皿）
    static func soapNiche() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(9, 1.2, 5), at: CV3(0, 4, 2.5), radius: 0.25, R(.wood(.teak))))
        for x in [-4.0, 4.0] {
            parts.append(K.tube([CV3(x, 4.5, 0.4), CV3(x, 4.5, 4.5)], radius: 0.25, sides: 6, R(.iron)))
        }
        parts.append(K.placed(K.roundedBox(CV3(5, 0.5, 3.2), radius: 0.2, segments: 2, puff: 0.1, R(.ceramic(0xF5F0E6))),
                              at: CV3(0, 5.5, 2.8)))
        parts.append(K.placed(K.roundedBox(CV3(3.5, 1.8, 2.2), radius: 0.4, segments: 2, puff: 0.25, R(.painted(0xE8E2D4))),
                              at: CV3(0, 6.2, 2.8)))
        return K.merge(parts)
    }

    /// 手洗い器（丸い鉢・蛇口・下の支え）。鉢の半径ぶん前に出す
    static func washBasin() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(16, 1.4, 8), at: CV3(0, 0, 5), radius: 0.3, R(.wood(.walnut))))
        for x in [-6.0, 6.0] {
            parts.append(K.tube([CV3(x, 0.5, 0.5), CV3(x, 0.5, 7)], radius: 0.3, sides: 6, R(.iron)))
        }
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(5.5, 0), CV2(6.2, 1), CV2(6.0, 3.5), CV2(5.2, 4), CV2(0, 4)],
                                      segments: 24, R(.ceramic(0xF5F0E6)), capStart: true, capEnd: false),
                              at: CV3(0, 1.4, 6.5)))
        parts.append(K.tube([CV3(0, 5.5, 2.0), CV3(0, 10, 2.0), CV3(0, 10, 5.5), CV3(0, 8.5, 6.8)],
                            radius: 0.35, sides: 8, R(.chrome)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.8, 0), CV2(0.7, 1.2), CV2(0, 1.2)], segments: 10, R(.chrome)),
                              at: CV3(0, 8.5, 6.8)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.0, 0), CV2(0.9, 1.0), CV2(0, 1.0)], segments: 10, R(.chrome)),
                              at: CV3(-2.5, 10, 2.0)))
        return K.merge(parts)
    }

    /// コップ掛け（レール・フック・コップ 3）
    static func cupRail() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(18, 1.4, 2.5), at: CV3(0, 12, 1.25), radius: 0.25, R(.wood(.oak))))
        for x in [-7.0, 7.0] {
            parts.append(K.tube([CV3(x, 12.5, 0.4), CV3(x, 12.5, 2.5)], radius: 0.25, sides: 6, R(.iron)))
        }
        let cups: [(Double, UInt32)] = [(-6, 0xE8E2D6), (0, 0x6E8FA3), (6, 0xC9A66B)]
        for (x, c) in cups {
            parts.append(K.tube([CV3(x, 12, 2.2), CV3(x, 9.5, 3.0)], radius: 0.2, sides: 6, R(.iron)))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.6, 0), CV2(1.8, 0.3), CV2(1.7, 4), CV2(1.5, 4.5), CV2(0, 4.5)],
                                          segments: 14, R(.ceramic(c))), at: CV3(x, 4.5, 3.0)))
            parts.append(K.tube([CV3(x + 1.7, 7, 3.0), CV3(x + 2.6, 8, 3.0), CV3(x + 1.7, 9, 3.0)],
                                radius: 0.22, sides: 6, R(.ceramic(c))))
        }
        return K.merge(parts)
    }
}
