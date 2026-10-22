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

    /// モンステラ（2026-10-21 作り直し・Mac の接写で葉がつぶした球の「緑の豆」だった）。
    /// 釉の鉢（高台・胴・縁の折り返し）と受け皿・土と木のチップ、根元から立つ 7 本の葉柄、
    /// 付け根に耳のあるハート形で、縁から脈へ切れ込み（窓）のある大きな葉。若い巻いた葉 1・気根 2。2×2 マスに収める
    static func monstera() -> CamperMesh {
        var parts: [CamperMesh] = []
        let glaze = R(.ceramic(0xE7E0D2)), stem = R(.painted(0x5C7F43))
        // 受け皿・鉢（釉）・縁の折り返し・土・木のチップ
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(5.6, 0), CV2(6.1, 0.5), CV2(6.0, 1.0), CV2(0, 1.0)], segments: 28, glaze), at: .zero))
        parts.append(K.placed(K.vessel(outer: [CV2(3.6, 0), CV2(4.6, 0.8), CV2(5.3, 6), CV2(5.5, 10.2), CV2(5.8, 10.6), CV2(5.8, 11.4)],
                                       inner: [CV2(3.4, 1.5), CV2(4.8, 6), CV2(5.0, 11.4)], segments: 28, glaze), at: CV3(0, 1, 0)))
        parts.append(K.placed(K.disc(radius: 4.9, height: 0.4, bevel: 0.1, segments: 24, R(.soil)), at: CV3(0, 11.0, 0)))
        for k in 0..<9 {
            let a = Double(k) * 2.4, r = 1.2 + Double(k % 4) * 0.8
            parts.append(K.block(CV3(0.9, 0.25, 0.6), at: CV3(cos(a) * r, 11.35, sin(a) * r), radius: 0.1, R(.wood(.pine))))
        }
        // 葉: 角度・高さ・大きさ（大きな葉ほど外へ倒れる）
        let leaves: [(a: Double, h: Double, out: Double, len: Double, slits: Int)] = [
            (0.3, 35, 4.5, 11, 4), (1.25, 38, 3.8, 12.5, 5), (2.2, 36, 5.0, 10, 3), (3.15, 41, 3.0, 13, 5),
            (4.05, 35.5, 4.8, 11.5, 4), (5.0, 38.5, 4.2, 12, 4), (5.75, 35, 5.5, 8.5, 2),
        ]
        for (i, l) in leaves.enumerated() {
            let dir = CV3(cos(l.a), 0, sin(l.a))
            let base = CV3(dir.x * 0.6, 11.2, dir.z * 0.6)
            let top = CV3(dir.x * l.out, l.h, dir.z * l.out)
            // 葉柄（根元は太く、葉の付け根で少し折れる）
            parts.append(K.tube([base, base + CV3(0, (l.h - 11) * 0.45, 0) + dir * (l.out * 0.25), top - dir * 0.6 + CV3(0, -0.8, 0), top],
                                radius: 0.32, sides: 7, stem))
            let blade = CamperRoomShapes.blade(length: l.len, width: l.len * 0.82, fold: 0.12, droop: 0.22, heart: 0.9,
                                               slits: l.slits, R(.leaf))
            // 中の脈（明るい筋）
            let rib = K.tube((0...6).map { k -> CV3 in
                let u = Double(k) / 6
                return CV3(u * l.len * 0.9, 0.05 - 0.22 * l.len * u * u, 0)
            }, radius: 0.12, sides: 4, R(.painted(0x7FA35E)))
            let leaf = K.merge([blade, rib])
            let tilt = -0.12 - Double(i % 3) * 0.08
            parts.append(CamperRoomShapes.blade(at: top, toward: CV3(dir.x, tilt, dir.z), roll: Double(i % 2 == 0 ? 1 : -1) * 0.18, leaf))
        }
        // 若い巻いた葉（細い円錐）
        parts.append(K.tube([CV3(0, 11.2, 0), CV3(0.4, 30, -0.3), CV3(0.6, 38, -0.4)], radius: 0.28, sides: 6, stem))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.55, 0.5), CV2(0.5, 4.5), CV2(0, 6.5)], segments: 10, R(.painted(0x8DB86A))),
                              at: CV3(0.6, 38, -0.4)))
        // 気根（茶色の細い根が鉢の縁へ垂れる）
        for (a, h) in [(2.6, 19.0), (4.6, 17.0)] {
            let o = CV3(cos(a), 0, sin(a))
            parts.append(K.tube([CV3(o.x * 1.2, h, o.z * 1.2), CV3(o.x * 3.4, h - 3, o.z * 3.4), CV3(o.x * 5.0, 12.5, o.z * 5.0)],
                                radius: 0.16, sides: 5, R(.wornWood(.walnut))))
        }
        return K.merge(parts)
    }

    /// サボテン（縦の畝・小さな棘・素焼き鉢）。1×1 マスに収める
    /// サボテン（釉の鉢・縁・土・縦の畝・腕 3・棘・頂の花）
    static func cactus() -> CamperMesh {
        var parts: [CamperMesh] = []
        let green = R(.painted(0x4A7A45)), pale = R(.painted(0x5E8A58)), clay = R(.terracotta)
        // 鉢（高台・胴・縁の折り返し）と土
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.4, 0), CV2(2.6, 0.5), CV2(2.2, 1.2), CV2(0, 1.2)],
                                      segments: 22, clay), at: .zero))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.4, 0), CV2(4.0, 1.4), CV2(4.1, 5.2), CV2(3.6, 6.4),
                                       CV2(3.9, 6.9), CV2(3.5, 7.4), CV2(0, 7.4)],
                                      segments: 26, clay), at: CV3(0, 1.0, 0)))
        parts.append(K.tube(K.arc(center: .zero, radius: 3.75, from: 0, to: 2 * .pi, steps: 28)
                                .map { CV3($0.x, 7.9, $0.y) }, radius: 0.18, sides: 5, closed: true, R(.ceramic(0xB8925E))))
        parts.append(K.placed(K.disc(radius: 3.2, height: 0.45, bevel: 0.12, segments: 20, R(.soil)), at: CV3(0, 7.5, 0)))
        // 主幹（畝の縦筋）と腕
        func column(at p: CV3, h: Double, r: Double, segs: Int = 18) {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(r * 0.92, 0), CV2(r, h * 0.12), CV2(r * 0.98, h * 0.85),
                                           CV2(r * 0.7, h), CV2(0, h)], segments: segs, green), at: p))
            for k in 0..<8 {
                let a = Double(k) / 8 * 2 * .pi
                parts.append(K.tube([p + CV3(cos(a) * r * 0.88, 0.4, sin(a) * r * 0.88),
                                     p + CV3(cos(a) * r * 0.92, h * 0.9, sin(a) * r * 0.92)],
                                    radius: 0.12, sides: 4, pale))
            }
        }
        column(at: CV3(0, 7.8, 0), h: 24, r: 2.05)
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.35, 0), CV2(1.45, 5.5), CV2(1.1, 7.2), CV2(0, 7.2)],
                                      segments: 14, green), at: CV3(1.85, 16.5, 0.2),
                              rotation: CQuat.axisAngle(CV3(0, 0, 1), -0.95)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.2, 0), CV2(1.3, 4.8), CV2(0.95, 6.2), CV2(0, 6.2)],
                                      segments: 14, green), at: CV3(-1.7, 20.0, 0.4),
                              rotation: CQuat.axisAngle(CV3(0, 0, 1), 1.05)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.05, 0), CV2(1.1, 3.6), CV2(0.8, 4.6), CV2(0, 4.6)],
                                      segments: 12, green), at: CV3(0.4, 24.5, -1.5),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), 0.55)))
        // 棘（白い点）と頂の小さな花
        for k in 0..<48 {
            let a = Double(k) / 48 * 2 * .pi
            let y = 9.5 + Double(k % 10) * 2.15
            let rr = 2.15 + Double(k % 3) * 0.05
            parts.append(K.placed(K.sphere(radius: 0.12, segments: 5, R(.painted(0xE8E2D4))),
                                  at: CV3(cos(a) * rr, y, sin(a) * rr)))
        }
        parts.append(K.placed(K.sphere(radius: 0.55, segments: 10, R(.painted(0xC9584A))), at: CV3(0, 32.4, 0)))
        for k in 0..<5 {
            let a = Double(k) / 5 * 2 * .pi
            parts.append(K.placed(K.scaled(K.sphere(radius: 0.35, segments: 8, R(.painted(0xE8A0A8))), CV3(1.2, 0.45, 0.7)),
                                  at: CV3(cos(a) * 0.55, 32.7, sin(a) * 0.55)))
        }
        return K.merge(parts)
    }

    /// 盆栽（2026-10-21 作り直し・Mac run 596: 緑の球 3 つが棒に刺さったように見えた）。
    /// 長方形の浅い釉の鉢（縁の返し・雲足 4）・苔と小石、根張りから太く細る曲の幹（皮の筋）、
    /// 枝ごとに平たい葉の段（小さな刃の葉を重ねた棚）。黒松の模様木
    static func bonsai() -> CamperMesh {
        var parts: [CamperMesh] = []
        let glaze = R(.ceramic(0x3B4A52)), bark = R(.wornWood(.darkOak)), moss = R(.painted(0x5C7A3A))
        // 鉢（角を丸めた浅い箱・縁の返し）と雲足
        parts.append(K.block(CV3(17, 3.6, 11), at: CV3(0, 0.9, 0), radius: 0.8, glaze))
        parts.append(K.tube(K.roundedRect(17.6, 11.6, r: 1.0).map { CV3($0.x, 4.45, $0.y) }, radius: 0.32, sides: 6, closed: true, glaze))
        for (x, z) in [(-6.8, -3.8), (6.8, -3.8), (-6.8, 3.8), (6.8, 3.8)] {
            parts.append(K.block(CV3(2.2, 1.0, 1.6), at: CV3(x, 0, z), radius: 0.35, glaze))
        }
        // 土・苔の丘・小石
        parts.append(K.block(CV3(15.8, 0.4, 9.8), at: CV3(0, 4.2, 0), radius: 0.2, R(.soil)))
        parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 16, moss), CV3(6.5, 0.9, 4.2)), at: CV3(-1.0, 4.6, 0)))
        for (x, z, r) in [(4.8, 2.6, 0.9), (5.9, 1.5, 0.6), (-5.6, -2.8, 0.7)] {
            parts.append(K.placed(K.scaled(K.sphere(radius: r, segments: 10, R(.painted(0x8A867C))), CV3(1, 0.7, 1)), at: CV3(x, 4.7, z)))
        }
        // 根張り（地を這う根 4）
        for (dx, dz) in [(-2.4, 0.6), (2.0, -0.4), (0.3, 1.9), (-0.5, -1.8)] {
            parts.append(K.tube([CV3(0, 5.6, 0), CV3(dx * 0.6, 5.0, dz * 0.6), CV3(dx, 4.7, dz)], radius: 0.45, sides: 6, bark))
        }
        // 幹（太く始まり細る・左右に振れる）
        let trunk: [CV3] = [CV3(0, 4.8, 0), CV3(-1.4, 8.5, 0.4), CV3(0.6, 11.8, -0.3), CV3(2.6, 14.0, 0.5), CV3(1.2, 17.2, 0.2),
                            CV3(-0.6, 19.6, -0.4), CV3(0.4, 22.0, 0.2)]
        let radii = [1.5, 1.25, 1.05, 0.9, 0.72, 0.55, 0.4]
        for k in 0..<(trunk.count - 1) {
            parts.append(K.tube([trunk[k], trunk[k + 1]], radius: (radii[k] + radii[k + 1]) / 2, sides: 9, bark))
            parts.append(K.placed(K.sphere(radius: radii[k + 1] * 1.02, segments: 9, bark), at: trunk[k + 1]))
        }
        // 皮の筋（幹に沿う細い溝）
        for a in [0.4, 2.2, 4.1] {
            let off = CV3(cos(a), 0, sin(a))
            parts.append(K.tube(trunk.enumerated().map { $0.element + off * (radii[$0.offset] * 0.98) }, radius: 0.08, sides: 3,
                                R(.wood(.walnut))))
        }
        // 枝と葉の段: 枝の先に、平たい楕円の棚を小さな刃の葉で作る（上が明るく下が暗い緑）
        let pads: [(from: Int, tip: CV3, rx: Double, rz: Double)] = [
            (2, CV3(-6.2, 12.6, 1.2), 4.0, 3.0), (3, CV3(6.4, 15.0, -0.8), 3.8, 2.8), (4, CV3(-5.4, 17.8, -1.6), 3.4, 2.5),
            (5, CV3(4.6, 20.2, 1.0), 3.0, 2.3), (6, CV3(0.2, 23.6, 0.2), 3.2, 2.6),
        ]
        let needle = CamperRoomShapes.blade(length: 1.5, width: 0.5, fold: 0.2, droop: 0.08, R(.leaf))
        let dark = CamperRoomShapes.blade(length: 1.4, width: 0.5, fold: 0.2, droop: 0.1, R(.painted(0x2F4A26)))
        for (i, pad) in pads.enumerated() {
            let from = trunk[pad.from]
            let mid = (from + pad.tip) * 0.5 + CV3(0, -0.8, 0)
            parts.append(K.tube([from, mid, pad.tip], radius: max(0.18, radii[pad.from] * 0.45), sides: 6, bark))
            // 下の暗い段（厚み）と、上の明るい葉
            parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 12, R(.painted(0x26401F))), CV3(pad.rx * 0.9, 0.55, pad.rz * 0.9)),
                                  at: pad.tip + CV3(0, 0.2, 0)))
            let count = Int(pad.rx * pad.rz * 2.4)
            for k in 0..<count {
                let t = Double(k) / Double(count)
                let a = t * 2 * .pi * 7.3 + Double(i)
                let r = (0.25 + 0.75 * ((t * 13).truncatingRemainder(dividingBy: 1)))
                let at = pad.tip + CV3(cos(a) * pad.rx * r, 0.55 + 0.25 * sin(a * 3), sin(a) * pad.rz * r)
                let dir = CV3(cos(a + 0.6), 0.35, sin(a + 0.6))
                parts.append(CamperRoomShapes.blade(at: at, toward: dir, roll: 0.3, k % 4 == 0 ? dark : needle))
            }
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
        // 縁の笠木（板の上端を覆う。2026-10-22: 前は板の木口がむき出しで終わっていた）
        for z in [-6.6, 6.6] { parts.append(K.block(CV3(27, 0.7, 1.8), at: CV3(0, 9, z), radius: 0.2, R(.wood(.darkOak)))) }
        for x in [-12.6, 12.6] { parts.append(K.block(CV3(1.8, 0.7, 11.4), at: CV3(x, 9, 0), radius: 0.2, R(.wood(.darkOak)))) }
        let greens: [UInt32] = [0x5E8A4A, 0x4A7A45, 0x6E9A5A]
        for (i, x) in [(-8.0), (0.0), (8.0)].enumerated() {
            parts.append(K.tube([CV3(x, 8, 0), CV3(x, 16, 0)], radius: 0.2, sides: 5, R(.leaf)))
            for k in 0..<8 {
                let a = Double(k) / 8 * 2 * .pi + Double(i) * 0.3
                let tip = CV3(x + cos(a) * 3.5, 12 + Double(k % 3), sin(a) * 3.5)
                // 葉柄（茎から葉へ。2026-10-22: 前は葉が茎から 8 cm 離れて宙に浮いていた）
                parts.append(K.tube([CV3(x, tip.y - 1.6, 0), tip], radius: 0.12, sides: 4, R(.leaf)))
                parts.append(CamperRoomShapes.leaf(at: tip, toward: CV3(cos(a), 0.6, sin(a)), size: 1.8))
                parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 8, R(.painted(greens[i]))), CV3(1.4, 0.2, 0.9)), at: tip))
            }
        }
        return K.merge(parts)
    }

    // MARK: 旅の荷物

    /// 開いたトランク（下箱の角金・立てた蓋・内張り・ヒンジ・留め・中の服）
    static func openSuitcase() -> CamperMesh {
        var parts: [CamperMesh] = []
        let leather = R(.leather(0x5E3A24)), dark = R(.leather(0x3E2618)), brass = R(.brass)
        parts.append(K.block(CV3(24, 7, 14), at: CV3(0, 0, 1), radius: 0.55, leather))
        parts.append(K.block(CV3(22, 0.55, 12), at: CV3(0, 6.15, 1), radius: 0.15, dark))
        // 角金
        for x in [-11.2, 11.2] {
            for z in [-5.2, 7.2] {
                parts.append(K.block(CV3(1.6, 1.8, 1.6), at: CV3(x, 0.2, z), radius: 0.35, brass))
            }
        }
        // 立てた蓋（下箱の後ろの上の縁で蝶番に掛かる。2026-10-22: 前は蝶番が箱の上 6 cm の宙にあり、蓋が浮いていた）
        parts.append(K.placed(K.block(CV3(24, 7, 1.3), at: .zero, radius: 0.55, leather),
                              at: CV3(0, 6.6, -5.6), rotation: CQuat.axisAngle(CV3(1, 0, 0), -1.05)))
        parts.append(K.placed(K.block(CV3(21.5, 5.2, 0.45), at: .zero, radius: 0.2, dark),
                              at: CV3(0, 7.4, -4.95), rotation: CQuat.axisAngle(CV3(1, 0, 0), -1.05)))
        for x in [-7.0, 7.0] {
            parts.append(K.block(CV3(2.2, 0.7, 1.3), at: CV3(x, 6.9, -5.8), radius: 0.15, brass))
        }
        parts.append(K.block(CV3(3.4, 1.3, 1.1), at: CV3(0, 3.5, 7.9), radius: 0.2, brass))
        parts.append(K.placed(K.disc(radius: 0.45, height: 0.35, bevel: 0.1, segments: 10, R(.iron)), at: CV3(0, 4.4, 8.3),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.placed(K.roundedBox(CV3(18, 2.2, 9), radius: 0.7, segments: 2, puff: 0.35, R(.cotton(0xE8E1D2))),
                              at: CV3(0, 8.0, 1)))
        parts.append(K.placed(K.roundedBox(CV3(7, 2.0, 3.5), radius: 0.5, segments: 2, puff: 0.25, R(.knit(0x2F4F74))),
                              at: CV3(-5, 8.5, 3.5)))
        parts.append(K.block(CV3(4.5, 2.2, 7), at: CV3(6.5, 7.2, -1), radius: 0.35, R(.leather(0x1A1A1C))))
        return K.merge(parts)
    }

    /// 背負い袋（キャンバス胴・側面ポケット・蓋の留め・肩紐のパッド・底の革・水筒）
    static func backpack() -> CamperMesh {
        var parts: [CamperMesh] = []
        let canvas = R(.canvas(0x4A5A3A)), leather = R(.leather(0x3E2618)), brass = R(.brass)
        parts.append(K.placed(K.roundedBox(CV3(14, 22, 10), radius: 1.2, segments: 3, puff: 0.4, canvas), at: CV3(0, 11.2, 0)))
        // 底の革と縫い目
        parts.append(K.block(CV3(13.5, 1.4, 9.6), at: CV3(0, 0.1, 0), radius: 0.4, leather))
        parts.append(K.tube(K.roundedRect(13.2, 9.2, r: 1.0).map { CV3($0.x, 22.2, $0.y) }, radius: 0.1, sides: 4, closed: true, leather))
        // 蓋と留め金
        parts.append(K.placed(K.roundedBox(CV3(12.5, 6.5, 8.5), radius: 1.0, segments: 2, puff: 0.35, leather), at: CV3(0, 25.0, 0.5)))
        parts.append(K.tube([CV3(0, 22.2, 5.2), CV3(0, 20.5, 5.8), CV3(0, 19.2, 5.5)], radius: 0.28, sides: 5, leather))
        parts.append(K.block(CV3(2.8, 1.4, 0.9), at: CV3(0, 19.0, 5.6), radius: 0.2, brass))
        parts.append(K.placed(K.sphere(radius: 0.4, segments: 8, brass), at: CV3(0, 19.0, 6.2)))
        // 前面ポケット
        parts.append(K.placed(K.roundedBox(CV3(10, 8.5, 2.8), radius: 0.7, segments: 2, puff: 0.3, canvas), at: CV3(0, 10.0, 5.4)))
        parts.append(K.tube([CV3(-4.5, 13.5, 6.7), CV3(4.5, 13.5, 6.7)], radius: 0.15, sides: 4, leather))
        // 側面ポケット
        for s in [-1.0, 1.0] {
            parts.append(K.placed(K.roundedBox(CV3(2.2, 7, 5), radius: 0.55, segments: 2, puff: 0.2, canvas), at: CV3(s * 7.2, 9.5, 0)))
        }
        // 肩紐（パッドつき）と腰ベルト
        for s in [-1.0, 1.0] {
            parts.append(K.tube([CV3(s * 4.2, 24.0, -3.8), CV3(s * 5.2, 14.0, -4.8), CV3(s * 4.6, 3.0, -3.6)],
                                radius: 0.48, sides: 7, leather))
            parts.append(K.placed(K.roundedBox(CV3(2.8, 6.5, 1.2), radius: 0.5, segments: 2, puff: 0.25, R(.knit(0xD8CDB8))),
                                  at: CV3(s * 5.0, 14.5, -5.2)))
        }
        parts.append(K.tube([CV3(-4.8, 4.5, -3.5), CV3(4.8, 4.5, -3.5)], radius: 0.38, sides: 6, leather))
        parts.append(K.block(CV3(2.2, 1.2, 1.0), at: CV3(0, 4.5, -3.5), radius: 0.2, brass))
        // 横の水筒
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.5, 0), CV2(1.6, 0.4), CV2(1.5, 8), CV2(1.2, 8.5), CV2(0, 8.5)],
                                      segments: 14, R(.chrome)), at: CV3(8.5, 6.5, 1.5)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.1, 0), CV2(1.15, 0.3), CV2(0.9, 1.4), CV2(0, 1.4)], segments: 12, R(.painted(0x2A2A2C))),
                              at: CV3(8.5, 15.0, 1.5)))
        return K.merge(parts)
    }

    /// 帽子箱（紙の胴・蓋の縁・リボンの結び・札・麦わらのつば）
    static func hatBox() -> CamperMesh {
        var parts: [CamperMesh] = []
        let paper = R(.painted(0xE8E0D0)), ribbon = R(.painted(0xC9584A)), straw = R(.canvas(0xD9C27A))
        // 胴（底の面取り・縦の継ぎ）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(7.6, 0), CV2(8.15, 0.8), CV2(8.25, 11.2), CV2(8.0, 12.4), CV2(0, 12.4)],
                                      segments: 32, paper), at: .zero))
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi
            parts.append(K.tube([CV3(cos(a) * 8.2, 1.2, sin(a) * 8.2), CV3(cos(a) * 8.2, 11.5, sin(a) * 8.2)],
                                radius: 0.06, sides: 4, R(.painted(0xD8D0C0))))
        }
        // 蓋（縁がはみ出す・つまみ）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(8.7, 0), CV2(8.95, 0.55), CV2(8.8, 2.0), CV2(7.6, 2.5), CV2(0, 2.5)],
                                      segments: 32, paper), at: CV3(0, 12.3, 0)))
        parts.append(K.placed(K.disc(radius: 1.1, height: 0.55, bevel: 0.15, segments: 14, R(.painted(0xD4C8B0))),
                              at: CV3(0, 14.85, 0)))
        // リボン帯と結び
        parts.append(K.tube(K.arc(center: .zero, radius: 8.2, from: 0, to: 2 * .pi, steps: 36)
                                .map { CV3($0.x, 6.8, $0.y) }, radius: 0.42, sides: 7, closed: true, ribbon))
        parts.append(K.placed(K.roundedBox(CV3(2.8, 1.6, 1.1), radius: 0.35, segments: 2, puff: 0.2, ribbon),
                              at: CV3(8.4, 6.8, 0)))
        for s in [-1.0, 1.0] {
            parts.append(K.placed(K.roundedBox(CV3(3.6, 0.55, 2.4), radius: 0.2, segments: 1, puff: 0.15, ribbon),
                                  at: CV3(9.6, 6.8 + s * 1.1, s * 0.9),
                                  rotation: CQuat.axisAngle(CV3(0, 0, 1), s * 0.35)))
        }
        // 紙の札
        parts.append(K.placed(K.panel(width: 3.6, height: 2.0, R(.paper)), at: CV3(0, 9.5, 8.35)))
        parts.append(K.block(CV3(2.4, 0.25, 0.12), at: CV3(0, 9.7, 8.45), radius: 0.05, R(.painted(0x5E3A24))))
        // 麦わら帽子（つば・クラウン・帯）
        parts.append(K.placed(K.disc(radius: 7.0, height: 0.45, bevel: 0.12, segments: 28, straw), at: CV3(0, 15.0, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.4, 0), CV2(3.7, 1.2), CV2(3.5, 3.4), CV2(2.8, 4.0), CV2(0, 4.0)],
                                      segments: 22, straw), at: CV3(0, 15.2, 0)))
        parts.append(K.tube(K.arc(center: .zero, radius: 3.55, from: 0, to: 2 * .pi, steps: 24)
                                .map { CV3($0.x, 16.4, $0.y) }, radius: 0.2, sides: 5, closed: true, ribbon))
        return K.merge(parts)
    }

    /// 地図立て（木の脚・斜めの地図）
    static func mapStand() -> CamperMesh {
        // 2026-10-21 作り直し（Mac run 596: 生成りの板に色の棒が数本で、地図に見えなかった）。
        // 胡桃の三脚の画架（前の脚 2・後ろの脚・横木・受け棚）に、上下の巻き軸に挟んだ旅の地図（印刷の絵・紙の反り）。
        // 軸の端の真鍮の玉・吊り紐・受け棚のコンパスと鉛筆
        var parts: [CamperMesh] = []
        let walnut = R(.wood(.walnut)), worn = R(.wornWood(.walnut)), brass = R(.agedBrass)
        let lean = -0.22
        let tilt = CQuat.axisAngle(CV3(1, 0, 0), lean)
        // 前の脚 2（床から上へ寄る）と後ろの脚（蝶番から後ろへ）
        for sx in [-1.0, 1.0] {
            parts.append(K.tube([CV3(sx * 7.6, 0.7, 2.0), CV3(sx * 5.6, 20, -1.4), CV3(sx * 4.6, 36, -3.6)], radius: 0.55, sides: 8, walnut))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.75, 0), CV2(0.65, 0.8), CV2(0, 0.8)], segments: 10, R(.painted(0x1A1A1A))),
                                  at: CV3(sx * 7.6, 0, 2.0)))
        }
        parts.append(K.tube([CV3(0, 33.5, -3.4), CV3(0, 16, -6.2), CV3(0, 0.6, -7.6)], radius: 0.5, sides: 8, walnut))
        parts.append(K.tube([CV3(-6.5, 7, 0.4), CV3(6.5, 7, 0.4)], radius: 0.4, sides: 7, worn))
        parts.append(K.tube([CV3(0, 7.2, 0.2), CV3(0, 9.2, -6.4)], radius: 0.32, sides: 6, worn))
        // 受け棚（縁つき）
        parts.append(K.block(CV3(15.5, 0.9, 3.0), at: CV3(0, 13.2, 0.6), radius: 0.25, walnut))
        parts.append(K.block(CV3(15.5, 1.3, 0.5), at: CV3(0, 13.9, 2.0), radius: 0.15, worn))
        // 地図: 上下の巻き軸と、その間の紙（少し反る・旅の地図の印刷）
        let center = CV3(0, 24.6, -1.5)
        let sheet = CamperRoomShapes.paperSheet(width: 15, height: 18, curl: 0.6, R(.mapPrint))
        parts.append(K.placed(sheet, at: center, rotation: tilt))
        for (dy, r) in [(9.4, 0.75), (-9.4, 0.85)] {
            let c = center + tilt.rotate(CV3(0, dy, 0.25))
            parts.append(K.tube([c + CV3(-8.2, 0, 0), c + CV3(8.2, 0, 0)], radius: r, sides: 10, walnut))
            for sx in [-1.0, 1.0] {
                parts.append(K.placed(K.sphere(radius: r * 1.25, segments: 10, brass), at: c + CV3(sx * 8.9, 0, 0)))
            }
        }
        // 吊り紐（上の軸から脚の頭へ）
        let top = center + tilt.rotate(CV3(0, 9.4, 0.25))
        parts.append(K.tube([top + CV3(-7.5, 0, 0), CV3(0, 35.5, -3.0), top + CV3(7.5, 0, 0)], radius: 0.1, sides: 4, R(.rope)))
        // 受け棚の上: 真鍮のコンパスと鉛筆
        parts.append(K.placed(K.disc(radius: 1.4, height: 0.6, bevel: 0.15, segments: 18, brass), at: CV3(4.2, 13.7, 0.8)))
        parts.append(K.placed(K.disc(radius: 1.1, height: 0.05, bevel: 0.01, segments: 18, R(.dial)), at: CV3(4.2, 14.31, 0.8)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.3, 0.6), CV2(0.3, 8), CV2(0, 8)], segments: 6, R(.painted(0x2F5A3A))),
                              at: CV3(-6.5, 14.0, 0.9), rotation: CQuat.axisAngle(CV3(0, 0, 1), -.pi / 2)))
        return K.merge(parts)
    }

    // MARK: お茶

    /// 急須の盆（縁と持ち手のある盆・蓋つき急須・受け皿つき湯呑 2）
    static func teapotTray() -> CamperMesh {
        var parts: [CamperMesh] = []
        let walnut = R(.wood(.walnut)), china = R(.ceramic(0xE8E2D6)), blue = R(.ceramic(0x6E8FA3))
        parts.append(K.block(CV3(17.5, 1.0, 11.5), at: CV3(0, 0.15, 0), radius: 0.35, walnut))
        parts.append(K.block(CV3(17.8, 0.55, 0.5), at: CV3(0, 1.0, 5.6), radius: 0.12, R(.wornWood(.walnut))))
        parts.append(K.block(CV3(17.8, 0.55, 0.5), at: CV3(0, 1.0, -5.6), radius: 0.12, R(.wornWood(.walnut))))
        for x in [-8.6, 8.6] {
            parts.append(K.tube([CV3(x, 1.2, -3.0), CV3(x + (x > 0 ? 0.7 : -0.7), 2.2, 0), CV3(x, 1.2, 3.0)],
                                radius: 0.25, sides: 6, walnut))
        }
        // 急須（胴・蓋・摘み・注ぎ口・取っ手）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.4, 0), CV2(4.0, 1.8), CV2(3.7, 5.2), CV2(2.9, 6.2), CV2(0, 6.2)],
                                      segments: 20, china), at: CV3(-3.5, 1.3, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.6, 0), CV2(2.8, 0.4), CV2(2.2, 1.4), CV2(0.9, 1.7), CV2(0, 1.7)],
                                      segments: 16, china), at: CV3(-3.5, 7.5, 0)))
        parts.append(K.placed(K.sphere(radius: 0.55, segments: 10, R(.wood(.oak))), at: CV3(-3.5, 9.4, 0)))
        parts.append(K.tube([CV3(-3.5, 4.2, 3.6), CV3(-3.5, 4.8, 5.2), CV3(-3.5, 5.8, 5.8)], radius: 0.42, sides: 8, china))
        parts.append(K.tube([CV3(-0.2, 3.8, 0), CV3(1.0, 5.5, 0), CV3(-0.2, 7.0, 0)], radius: 0.32, sides: 8, china))
        // 湯呑と受け皿
        for x in [4.8, 9.2] {
            parts.append(K.placed(K.disc(radius: 2.4, height: 0.35, bevel: 0.1, segments: 16, blue), at: CV3(x, 1.3, 1.2)))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.7, 0), CV2(1.9, 0.35), CV2(1.85, 3.8), CV2(1.6, 4.3), CV2(0, 4.3)],
                                          segments: 16, blue), at: CV3(x, 1.55, 1.2)))
            parts.append(K.tube([CV3(x + 1.75, 3.2, 1.2), CV3(x + 2.6, 4.0, 1.2), CV3(x + 1.75, 4.8, 1.2)],
                                radius: 0.2, sides: 6, blue))
        }
        return K.merge(parts)
    }

    /// 魔法瓶（クローム胴・塗りの帯・ねじ蓋兼カップ・持ち手）
    static func thermos() -> CamperMesh {
        var parts: [CamperMesh] = []
        let chrome = R(.chrome), red = R(.painted(0xC9584A)), dark = R(.painted(0x2A2A2C))
        parts.append(K.placed(K.disc(radius: 3.0, height: 0.45, bevel: 0.12, segments: 16, chrome), at: .zero))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.15, 0), CV2(3.35, 0.8), CV2(3.25, 16), CV2(3.3, 18), CV2(3.15, 20), CV2(0, 20)],
                                      segments: 22, chrome), at: CV3(0, 0.45, 0)))
        // 塗りの帯と細い筋
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.4, 0), CV2(3.4, 4.5), CV2(0, 4.5)], segments: 20, red, capStart: false, capEnd: false),
                              at: CV3(0, 8.5, 0)))
        for y in [8.6, 12.8] {
            parts.append(K.tube(K.arc(center: .zero, radius: 3.38, from: 0, to: 2 * .pi, steps: 24).map { CV3($0.x, y, $0.y) },
                                radius: 0.08, sides: 4, closed: true, dark))
        }
        // ねじ蓋兼カップ（外ねじの筋）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.0, 0), CV2(3.15, 0.4), CV2(2.9, 4.2), CV2(2.6, 4.6), CV2(0, 4.6)],
                                      segments: 18, red), at: CV3(0, 20.5, 0)))
        for k in 0..<6 {
            let y = 20.7 + Double(k) * 0.35
            parts.append(K.tube(K.arc(center: .zero, radius: 3.05, from: 0, to: 2 * .pi, steps: 20).map { CV3($0.x, y, $0.y) },
                                radius: 0.06, sides: 4, closed: true, chrome))
        }
        // 持ち手
        parts.append(K.block(CV3(1.0, 1.2, 0.7), at: CV3(3.5, 9.5, 0), radius: 0.15, dark))
        parts.append(K.block(CV3(1.0, 1.2, 0.7), at: CV3(3.5, 16.5, 0), radius: 0.15, dark))
        parts.append(K.tube([CV3(3.9, 10.0, 0), CV3(5.4, 12.5, 0), CV3(5.4, 15.5, 0), CV3(3.9, 17.0, 0)],
                            radius: 0.32, sides: 7, dark))
        return K.merge(parts)
    }

    /// ケーキ台（3 段の皿）
    static func cakeStand() -> CamperMesh {
        // 2026-10-21 作り直し（Mac run 596: 白い円盤 3 枚と色の玉で、皿にも菓子にも見えなかった）。
        // 縁の立ち上がった磁器の皿 3 段（金の縁）・中を通す真鍮の軸と輪の取っ手、
        // 下段にスコーン、中段にショートケーキと苺、上段にマカロン（2 枚の殻とクリーム）
        var parts: [CamperMesh] = []
        let china = R(.ceramic(0xF7F3EA)), gold = R(.brass)
        let tiers: [(y: Double, r: Double)] = [(1.0, 7.4), (12.5, 6.0), (23.0, 4.4)]
        for t in tiers {
            // 皿（高台・薄い底・立ち上がる縁）
            // 下の面と縁（外向き）と、上の面（皿の内・上向き）を分けて回す。1 本の断面で内へ戻すと上の面が下向きになり、
            // 上から見えなかった（run 605: 金の縁だけが宙に浮いた）
            let under: [CV2] = [CV2(0, 0), CV2(t.r * 0.42, 0), CV2(t.r * 0.45, 0.35), CV2(t.r * 0.8, 0.4), CV2(t.r * 0.97, 0.95),
                                CV2(t.r, 1.15)]
            let top: [CV2] = [CV2(0, 0.62), CV2(t.r * 0.78, 0.7), CV2(t.r * 0.95, 1.15), CV2(t.r, 1.15)]
            parts.append(K.placed(K.lathe(under, segments: 36, china, capEnd: false), at: CV3(0, t.y - 1.0, 0)))
            parts.append(K.placed(K.inverted(K.lathe(top, segments: 36, china, capStart: false, capEnd: false)), at: CV3(0, t.y - 1.0, 0)))
            parts.append(K.tube(K.arc(center: .zero, radius: t.r * 0.985, from: 0, to: 2 * .pi, steps: 40).map { CV3($0.x, t.y + 0.16, $0.y) },
                                radius: 0.1, sides: 4, closed: true, gold))
        }
        // 軸（段の間の真鍮の柱・継ぎの玉）と上の輪の取っ手
        // 軸は上の輪の取っ手の下まで通す（2026-10-22: 前は軸の上端と輪の間が 7 mm 空いていた）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.38, 0), CV2(0.38, 26.7), CV2(0, 26.7)], segments: 12, gold), at: CV3(0, 0, 0)))
        for y in [0.6, 12.1, 22.6] { parts.append(K.placed(K.sphere(radius: 0.7, segments: 12, gold), at: CV3(0, y + 0.3, 0))) }
        parts.append(K.tube(K.arc(center: .zero, radius: 1.5, from: 0, to: 2 * .pi, steps: 20).map { CV3($0.x, 28.0 + $0.y, 0) },
                            radius: 0.22, sides: 6, closed: true, gold))
        // 下段: スコーン 4（割れ目のある丸い焼き菓子）
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + 0.4
            let c = CV3(cos(a) * 4.4, 0.65, sin(a) * 4.4)
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.5, 0), CV2(1.6, 0.9), CV2(1.3, 1.7), CV2(0, 1.9)], segments: 14,
                                          R(.painted(0xC48A4E))), at: c))
            parts.append(K.tube(K.arc(center: .zero, radius: 1.58, from: 0, to: 2 * .pi, steps: 14).map { c + CV3($0.x, 0.95, $0.y) },
                                radius: 0.12, sides: 4, closed: true, R(.painted(0xE8D2A8))))
        }
        // 中段: ショートケーキ 3（スポンジ・クリームの層・上のクリームと苺）
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi + 1.0
            let c = CV3(cos(a) * 3.4, 12.15, sin(a) * 3.4)
            parts.append(K.block(CV3(2.4, 0.9, 2.4), at: c, radius: 0.15, R(.painted(0xE9C98A))))
            parts.append(K.block(CV3(2.4, 0.35, 2.4), at: c + CV3(0, 0.9, 0), radius: 0.1, R(.painted(0xFBF6EC))))
            parts.append(K.block(CV3(2.4, 0.8, 2.4), at: c + CV3(0, 1.25, 0), radius: 0.15, R(.painted(0xE9C98A))))
            parts.append(K.placed(K.scaled(K.sphere(radius: 1, segments: 12, R(.painted(0xFBF6EC))), CV3(1.25, 0.45, 1.25)),
                                  at: c + CV3(0, 2.15, 0)))
            parts.append(K.placed(K.scaled(K.sphere(radius: 0.5, segments: 10, R(.ceramic(0xC8302A))), CV3(1, 1.25, 1)), at: c + CV3(0, 2.85, 0)))
        }
        // 上段: マカロン 5（2 枚の殻とクリーム）
        let colors: [UInt32] = [0xE8A0A8, 0xB8D49A, 0xF0D27A, 0xC9B4E0, 0xE8C4A0]
        for k in 0..<5 {
            let a = Double(k) / 5 * 2 * .pi
            let c = CV3(cos(a) * 2.4, 22.65, sin(a) * 2.4)
            for (dy, h) in [(0.0, 0.55), (0.85, 0.55)] {
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.95, 0), CV2(1.0, h * 0.4), CV2(0.75, h), CV2(0, h * 1.05)], segments: 14,
                                              R(.painted(colors[k]))), at: c + CV3(0, dy, 0)))
            }
            parts.append(K.placed(K.disc(radius: 0.85, height: 0.32, bevel: 0.1, segments: 14, R(.painted(0xFBF3E4))), at: c + CV3(0, 0.55, 0)))
        }
        return K.merge(parts)
    }

    /// 果物鉢（高台つき陶器・内側の釉・りんご 2・オレンジ・バナナ・ぶどう）
    static func fruitBowl() -> CamperMesh {
        var parts: [CamperMesh] = []
        let china = R(.ceramic(0xE8E2D6)), glaze = R(.ceramic(0xC9A66B)), inner = R(.ceramic(0xF2E8D4))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.4, 0), CV2(2.6, 0.45), CV2(2.1, 1.6), CV2(0, 1.6)],
                                      segments: 22, china), at: .zero))
        parts.append(K.placed(K.vessel(outer: [CV2(0, 0), CV2(3.0, 0), CV2(6.0, 1.8), CV2(7.8, 5.4), CV2(7.5, 7.4),
                                               CV2(6.6, 8.1), CV2(0, 8.1)],
                                       inner: [CV2(0, 0.5), CV2(2.6, 0.5), CV2(5.4, 2.0), CV2(7.0, 5.2), CV2(6.8, 7.0),
                                               CV2(0, 7.0)],
                                       segments: 30, china, innerMaterial: inner), at: CV3(0, 1.5, 0)))
        parts.append(K.tube(K.arc(center: .zero, radius: 7.0, from: 0, to: 2 * .pi, steps: 32)
                                .map { CV3($0.x, 9.4, $0.y) }, radius: 0.28, sides: 6, closed: true, glaze))
        // りんご 2
        for (p, c) in [(CV3(-1.6, 10.6, 1.4), 0xC9584A as UInt32), (CV3(2.6, 10.4, 1.0), 0xA8322A)] {
            parts.append(K.placed(K.scaled(K.sphere(radius: 2.1, segments: 16, R(.painted(c))), CV3(1.05, 0.92, 1.0)), at: p))
            parts.append(K.tube([p + CV3(0, 1.85, 0), p + CV3(0.2, 2.85, 0)], radius: 0.1, sides: 4, R(.wood(.darkOak))))
            parts.append(CamperRoomShapes.leaf(at: p + CV3(0.55, 2.65, 0.15), toward: CV3(1, 0.25, 0.15), size: 1.15))
        }
        // オレンジ（筋の印）
        let orange = CV3(-2.4, 10.2, -2.3)
        parts.append(K.placed(K.sphere(radius: 1.9, segments: 16, R(.painted(0xD9A441))), at: orange))
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi
            parts.append(K.tube([orange + CV3(cos(a) * 0.3, 1.7, sin(a) * 0.3),
                                 orange + CV3(cos(a) * 1.7, 0.2, sin(a) * 1.7)],
                                radius: 0.05, sides: 3, R(.painted(0xC48A28))))
        }
        parts.append(K.placed(K.sphere(radius: 0.22, segments: 6, R(.painted(0x5E3A24))), at: orange + CV3(0, 1.85, 0)))
        // バナナ 2 本
        for (ox, oz, sx) in [(3.2, -1.4, 0.15), (4.0, 0.4, -0.2)] as [(Double, Double, Double)] {
            let banana = (0...10).map { k -> CV3 in
                let t = Double(k) / 10
                return CV3(ox + t * sx, 9.4 + sin(t * .pi) * 1.55, oz + t * 3.3)
            }
            parts.append(K.tube(banana, radius: 0.65, sides: 9, R(.painted(0xE8D44A))))
            parts.append(K.placed(K.sphere(radius: 0.32, segments: 6, R(.painted(0x5E3A24))), at: banana[0]))
        }
        // ぶどう（粒の房）
        let grapeRoot = CV3(0.8, 11.2, -2.0)
        for k in 0..<14 {
            let row = k / 4, col = k % 4
            parts.append(K.placed(K.sphere(radius: 0.55, segments: 8, R(.painted(0x6A4A8C))),
                                  at: grapeRoot + CV3(Double(col) * 0.7 - 1.0, -Double(row) * 0.65, Double(row) * 0.15)))
        }
        // 房の付け根の葉（2026-10-22: 前は房の 2.5 cm 上の宙に浮いていた）
        parts.append(CamperRoomShapes.leaf(at: grapeRoot + CV3(-0.2, 0.45, 0.3), toward: CV3(0.4, 0.7, -0.2), size: 1.7))
        return K.merge(parts)
    }

    // MARK: 洗う物（壁）

    /// タオル掛け（壁座・ビス・クロムの棒・端の飾り・掛かったタオル 2）
    static func towelBar() -> CamperMesh {
        var parts: [CamperMesh] = []
        let chrome = R(.chrome), toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        for x in [-9.0, 9.0] {
            parts.append(K.placed(K.disc(radius: 1.15, height: 0.4, bevel: 0.12, segments: 16, chrome),
                                  at: CV3(x, 12, 0.15), rotation: toWall))
            for (dx, dy) in [(-0.55, 0.55), (0.55, 0.55), (-0.55, -0.55), (0.55, -0.55)] {
                parts.append(K.placed(K.sphere(radius: 0.14, segments: 6, R(.agedBrass)), at: CV3(x + dx, 12 + dy, 0.4)))
            }
            parts.append(K.block(CV3(1.5, 1.5, 2.8), at: CV3(x, 12, 1.5), radius: 0.35, chrome))
            parts.append(K.placed(K.sphere(radius: 0.55, segments: 10, chrome), at: CV3(x, 12, 2.9)))
        }
        parts.append(K.tube([CV3(-9, 12, 2.9), CV3(9, 12, 2.9)], radius: 0.42, sides: 12, chrome))
        // 端の細い飾り輪
        for x in [-9.0, 9.0] {
            parts.append(K.tube(K.arc(center: CV3(x, 12, 2.9), radius: 0.85, from: 0, to: 2 * .pi, steps: 14)
                                    .map { CV3($0.x, $0.y, 2.9) }, radius: 0.1, sides: 5, closed: true, R(.agedBrass)))
        }
        // タオル（掛けた所の縫い目つき）。布の上の辺（`drape` の y = 0）を棒の高さ 12 に掛ける。
        // 2026-10-21（owner「家具ぶっ壊れてる」・Mac run 622 の 96e）: 上の辺が y 4〜5 にあり、棒から 7 下で宙に浮いていた。
        // 縫い目は布と同じ置き方で、布の上の辺のすぐ下に
        let towels: [(at: CV3, tilt: Double, width: Double, height: Double, folds: Int, depth: Double, flare: Double, color: UInt32,
                      seam: UInt32)] = [
            (CV3(-0.5, 12.3, 3.5), 0.12, 13, 15, 4, 0.22, 0.45, 0xE8E2D4, 0xD8D0C4),
            (CV3(2.8, 12.2, 3.95), 0.18, 9.5, 12, 3, 0.2, 0.35, 0xA8B8C2, 0x8A9AA4),
        ]
        for t in towels {
            let q = CQuat.axisAngle(CV3(1, 0, 0), t.tilt)
            parts.append(K.placed(K.drape(width: t.width, height: t.height, folds: t.folds, depth: t.depth, flare: t.flare,
                                          R(.cotton(t.color))), at: t.at, rotation: q))
            let half = t.width * 0.48
            parts.append(K.placed(K.tube([CV3(-half, -1.2, t.depth + 0.05), CV3(half, -1.2, t.depth + 0.05)], radius: 0.08, sides: 4,
                                         R(.cotton(t.seam))), at: t.at, rotation: q))
        }
        return K.merge(parts)
    }

    /// 石鹸置き（木の棚・縁・石鹸と小さな瓶）
    static func soapNiche() -> CamperMesh {
        var parts: [CamperMesh] = []
        let teak = R(.wood(.teak))
        parts.append(K.block(CV3(10, 1.3, 5.2), at: CV3(0, 4, 2.6), radius: 0.28, teak))
        parts.append(K.block(CV3(10.2, 0.45, 0.55), at: CV3(0, 4.7, 5.0), radius: 0.1, R(.wornWood(.teak))))
        for x in [-4.7, 4.7] {
            parts.append(K.block(CV3(0.5, 0.45, 5.0), at: CV3(x, 4.7, 2.6), radius: 0.1, teak))
            parts.append(K.tube([CV3(x, 4.2, 0.3), CV3(x, 4.2, 2.0)], radius: 0.18, sides: 5, R(.brass)))
        }
        parts.append(K.placed(K.roundedBox(CV3(3.2, 1.4, 2.2), radius: 0.45, segments: 2, puff: 0.2, R(.ceramic(0xF2EEE6))),
                              at: CV3(-2.2, 5.5, 3.2)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.1, 0), CV2(1.2, 2.8), CV2(0.7, 3.2), CV2(0, 3.2)], segments: 12,
                                      R(.clearGlass)), at: CV3(2.4, 5.3, 3.0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.95, 0), CV2(0.95, 1.8), CV2(0, 1.8)], segments: 10,
                                      R(.linen(0xD9CDB4))), at: CV3(2.4, 5.4, 3.0)))
        return K.merge(parts)
    }

    /// 手洗い器（木の棚とブラケット・陶器の鉢・クロスハンドルの蛇口・排水口・石鹸）
    static func washBasin() -> CamperMesh {
        var parts: [CamperMesh] = []
        let walnut = R(.wood(.walnut)), china = R(.ceramic(0xF5F0E6)), chrome = R(.chrome)
        let toFront = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        // 棚と鉢は壁（z=0）より後ろへ出さない（鉢の半径ぶん前へ）
        parts.append(K.block(CV3(16.5, 1.5, 8.0), at: CV3(0, 0, 5.2), radius: 0.32, walnut))
        for x in [-6.5, 6.5] {
            parts.append(K.tube([CV3(x, 0.6, 0.6), CV3(x, 0.6, 4.2), CV3(x, 0.6, 7.8)], radius: 0.26, sides: 6, R(.iron)))
            parts.append(K.placed(K.disc(radius: 0.5, height: 0.28, bevel: 0.08, segments: 10, R(.agedBrass)),
                                  at: CV3(x, 0.6, 0.7), rotation: toFront))
        }
        // 鉢（内と外）
        parts.append(K.placed(K.vessel(outer: [CV2(0, 0), CV2(5.4, 0), CV2(6.0, 1.0), CV2(5.85, 3.6), CV2(5.1, 4.2), CV2(0, 4.2)],
                                       inner: [CV2(0, 0.4), CV2(4.9, 0.4), CV2(5.45, 1.0), CV2(5.3, 3.3), CV2(0, 3.3)],
                                       segments: 28, china), at: CV3(0, 1.5, 6.6)))
        parts.append(K.placed(K.disc(radius: 0.7, height: 0.25, bevel: 0.08, segments: 12, chrome),
                              at: CV3(0, 2.0, 6.6)))
        // 蛇口（立ち上がり・首・吐水・クロスハンドル 2）
        parts.append(K.tube([CV3(0, 5.6, 2.0), CV3(0, 10.2, 2.0)], radius: 0.38, sides: 8, chrome))
        parts.append(K.placed(K.sphere(radius: 0.55, segments: 10, chrome), at: CV3(0, 10.2, 2.0)))
        parts.append(K.tube([CV3(0, 10.2, 2.0), CV3(0, 10.2, 5.5), CV3(0, 8.8, 7.0)], radius: 0.32, sides: 8, chrome))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.75, 0), CV2(0.65, 1.1), CV2(0, 1.1)], segments: 10, chrome),
                              at: CV3(0, 8.8, 7.0)))
        for x in [-2.6, 2.6] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.9, 0), CV2(0.85, 0.35), CV2(0.35, 0.55), CV2(0.3, 1.3), CV2(0, 1.3)],
                                          segments: 12, chrome), at: CV3(x, 10.2, 2.0)))
            parts.append(K.block(CV3(2.2, 0.35, 0.35), at: CV3(x, 11.4, 2.0), radius: 0.1, chrome))
            parts.append(K.block(CV3(0.35, 0.35, 1.8), at: CV3(x, 11.4, 2.0), radius: 0.1, chrome))
        }
        // 石鹸
        parts.append(K.placed(K.roundedBox(CV3(2.8, 1.2, 1.8), radius: 0.4, segments: 2, puff: 0.15, R(.ceramic(0xF2EEE6))),
                              at: CV3(5.5, 2.3, 8.0)))
        return K.merge(parts)
    }

    /// コップ掛け（オークの桟・真鍮の壁金具・曲がったフック・掛けたコップ 3）
    static func cupRail() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak)), brass = R(.brass)
        parts.append(K.block(CV3(18.5, 1.5, 2.8), at: CV3(0, 12, 1.5), radius: 0.28, oak))
        parts.append(K.block(CV3(18.7, 0.35, 0.4), at: CV3(0, 13.35, 2.75), radius: 0.08, R(.wornWood(.oak))))
        for x in [-7.5, 7.5] {
            parts.append(K.placed(K.disc(radius: 0.7, height: 0.35, bevel: 0.1, segments: 12, brass),
                                  at: CV3(x, 12.7, 0.2), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
            parts.append(K.tube([CV3(x, 12.7, 0.4), CV3(x, 12.7, 2.6)], radius: 0.22, sides: 6, brass))
        }
        let cups: [(Double, UInt32)] = [(-6.2, 0xE8E2D6), (0, 0x6E8FA3), (6.2, 0xC9A66B)]
        for (x, c) in cups {
            // フック（壁から前へ曲がる）
            parts.append(K.tube([CV3(x, 12.2, 2.5), CV3(x, 11.2, 3.3), CV3(x, 10.4, 3.1)], radius: 0.18, sides: 6, R(.iron)))
            parts.append(K.placed(K.sphere(radius: 0.28, segments: 6, R(.iron)), at: CV3(x, 10.4, 3.1)))
            // 取っ手をフックに掛けたコップ
            let cup = R(.ceramic(c))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.7, 0), CV2(1.9, 0.35), CV2(1.8, 4.2), CV2(1.55, 4.7), CV2(0, 4.7)],
                                          segments: 16, cup), at: CV3(x, 5.2, 3.1)))
            parts.append(K.tube([CV3(x + 1.75, 7.8, 3.1), CV3(x + 2.7, 8.8, 3.1), CV3(x + 1.75, 9.8, 3.1), CV3(x + 1.75, 10.2, 3.1)],
                                radius: 0.2, sides: 6, cup))
        }
        return K.merge(parts)
    }
}
