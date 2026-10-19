import Foundation

// 集める部品の形（板「部品図鑑」CamperDex・2026-10-18）。33 分類 × 4 つ。どの部品も立体の形で描き分ける
// （色違いだけにしない）。要サーバーの部品（「近日」）も形は作っておく（試着の影絵と、サーバーが用意できた日のため）。
// 置き場所は板の単位・上が +Y（`CamperBuilder` と同じ）。

extension CamperBuilder {

    func k(_ c: CamperCategory) -> String { config.loadout.key(c) }

    // MARK: 窓の形

    /// 窓の形（板の座標の四角 x・y・幅・高さ・角の丸み から）。丸窓は横長なら 2 つ並べる
    func windowShapes(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> [[CV2]] {
        let x0 = x, y0 = 62 - y - h
        switch k(.windowShape) {
        case "porthole":
            let d = min(w, h)
            let count = w > d * 1.7 ? 2 : 1
            return (0..<count).map { i in
                let cx = count == 1 ? x0 + w / 2 : x0 + d / 2 + (w - d) * Double(i)
                return CamperPolygon.circle(CV2(cx, y0 + h / 2), d / 2, count: 24)
            }
        case "arched":
            let a = min(w / 2, h * 0.5)
            var pts = [CV2(x0, y0), CV2(x0 + w, y0), CV2(x0 + w, y0 + h - a)]
            for i in 1..<12 {
                let t = Double(i) / 12 * .pi
                pts.append(CV2(x0 + w / 2 + cos(t) * w / 2, y0 + h - a + sin(t) * a))
            }
            pts.append(CV2(x0, y0 + h - a))
            return [pts]
        case "slider_split":
            return [CamperPolygon.roundedRect(x: x0, y: y0, w: w, h: h, r: 1.2)]
        default:
            return [CamperPolygon.roundedRect(x: x0, y: y0, w: w, h: h, r: r)]
        }
    }

    /// 窓の桟とネジ（引き違いの真ん中の框・アーチの十字・丸窓のネジ 10）
    mutating func windowDetails(_ w: [CV2], z: Double, group: CamperGroup = .body) {
        let xs = w.map(\.x), ys = w.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return }
        let s = z >= 0 ? 1.0 : -1.0
        let wc = CamperCategory.windowShape
        switch k(.windowShape) {
        case "slider_split":
            rbox("window.sash", CV3((x0 + x1) / 2, (y0 + y1) / 2, z - s * 1.6), CV3(1.4, y1 - y0, 1.2), 0.3, .black, group: group, category: wc)
            rbox("window.sash", CV3((x0 + x1) / 2 - (x1 - x0) / 4, y1 - 0.8, z - s * 2.6), CV3((x1 - x0) / 2, 0.8, 0.6), 0.2, .chromeDark,
                 group: group, category: wc)
        case "arched":
            rbox("window.mullion", CV3((x0 + x1) / 2, (y0 + y1) / 2, z - s * 1.8), CV3(x1 - x0, 1, 1), 0.2, .black, group: group, category: wc)
            rbox("window.mullion", CV3((x0 + x1) / 2, (y0 + y1) / 2, z - s * 1.8), CV3(1, y1 - y0, 1), 0.2, .black, group: group, category: wc)
        case "porthole":
            let c = CV2((x0 + x1) / 2, (y0 + y1) / 2), r = (y1 - y0) / 2 + 1.6
            for i in 0..<10 {
                let t = Double(i) / 10 * 2 * .pi
                add("window.screw", .cylinder(radius: 0.5, height: 0.6, segments: 6), .chrome,
                    at: CV3(c.x + cos(t) * r, c.y + sin(t) * r, z + s * 0.9), CQuat.yTo(CV3(0, 0, s)), group: group, category: wc)
            }
        default:
            break
        }
    }

    // MARK: 取っ手

    /// 取っ手（`s` は外の向き ±Z）
    mutating func handle(_ name: String, at c: CV3, s: Double, group: CamperGroup = .body, small: Bool = false) {
        let hc = CamperCategory.handle
        let w = small ? 5.0 : 6.0
        switch k(.handle) {
        case "recessed":
            rbox(name, c + CV3(0, 0, s * 0.1), CV3(w + 1, 3, 0.4), 0.3, .black, group: group, category: hc)
            rbox(name, c + CV3(0, -0.4, s * 0.3), CV3(w - 1, 0.8, 0.6), 0.2, .chrome, group: group, category: hc)
            add(name, .cylinder(radius: 0.8, height: 0.5, segments: 10), .chrome, at: c + CV3(w / 2 + 2, 0, s * 0.25),
                CQuat.yTo(CV3(0, 0, s)), group: group, category: hc)
        case "brass_lever":
            add(name, .cylinder(radius: 1.8, height: 0.8, segments: 16), .brass, at: c + CV3(-w / 2 + 1.5, 0, s * 0.4),
                CQuat.yTo(CV3(0, 0, s)), group: group, category: hc)
            rbox(name, c + CV3(0.6, 0, s * 1.4), CV3(w, 1.2, 1.2), 0.5, .brass, group: group, category: hc)
        case "rope_loop":
            add(name, .torus(ring: 1.6, pipe: 0.4), .brass, at: c + CV3(0, 1.6, s * 0.5), CQuat.yTo(CV3(0, 0, s)), group: group, category: hc)
            add(name, .torus(ring: 2.6, pipe: 0.55), .tint(0xC8A46E), at: c + CV3(0, -1.6, s * 1.2),
                CQuat.yTo(CV3(0, 0, s)) * CQuat.axisAngle(CV3(1, 0, 0), 0.3), group: group, category: hc)
        default:
            rbox(name, c + CV3(0, 0, s * 1.4), CV3(w, 1.4, 1.4), 0.6, .chrome, group: group, category: hc)
            for dx in [-w / 2 + 0.6, w / 2 - 0.6] {
                rbox(name, c + CV3(dx, 0, s * 0.6), CV3(1.2, 1.8, 1.4), 0.3, .chrome, group: group, category: hc)
            }
        }
    }

    // MARK: ミラー

    mutating func mirrors() {
        let mc = CamperCategory.mirror
        let mx = van ? 60.0 : 68.0
        for s in [1.0, -1.0] {
            let base = B(mx, -22, s * BW)
            switch k(.mirror) {
            case "round_chrome":
                rod("ext.mirrorArm", base, base + CV3(-2, 4, s * 10), 0.5, .chrome, category: mc)
                add("ext.mirror", .cylinder(radius: 4.6, height: 1.6, segments: 20), .chrome, at: base + CV3(-2, 6, s * 11),
                    CQuat.yTo(CV3(-1, 0, 0)), category: mc)
                add("ext.mirrorGlass", .cylinder(radius: 4, height: 0.3, segments: 20), .glass, at: base + CV3(-2.9, 6, s * 11),
                    CQuat.yTo(CV3(-1, 0, 0)), category: mc)
            case "tall_tow":
                rod("ext.mirrorArm", base + CV3(0, 6, 0), base + CV3(0, 6, s * 18), 0.6, .black, category: mc)
                rod("ext.mirrorArm", base + CV3(0, -8, 0), base + CV3(0, -6, s * 18), 0.6, .black, category: mc)
                rbox("ext.mirror", base + CV3(0, 0, s * 19), CV3(3, 18, 6), 1.2, .black, category: mc)
                rbox("ext.mirrorGlass", base + CV3(-1.6, 0, s * 19), CV3(0.4, 16, 4.8), 0.2, .chrome, category: mc)
            case "brass_oval":
                rod("ext.mirrorArm", base, base + CV3(-1, 3, s * 9), 0.6, .brass, category: mc)
                add("ext.mirror", .cylinder(radius: 4, height: 1.4, segments: 24), .brass, at: base + CV3(-1.5, 5, s * 10),
                    CQuat.yTo(CV3(-1, 0, 0)), category: mc, scale: CV3(1.45, 1, 1))
                add("ext.mirrorGlass", .cylinder(radius: 3.4, height: 0.3, segments: 24), .glass, at: base + CV3(-2.3, 5, s * 10),
                    CQuat.yTo(CV3(-1, 0, 0)), category: mc, scale: CV3(1.45, 1, 1))
            default:
                rbox("ext.mirrorArm", B(mx, -22, s * (BW + 4)), CV3(3, 1.6, 8), 0.6, .black, category: mc)
                rbox("ext.mirror", B(mx + 1, -22, s * (BW + 9)), CV3(3, 11, 7), 1.6, .black, category: mc)
                rbox("ext.mirrorGlass", B(mx - 0.7, -22, s * (BW + 9)), CV3(0.4, 9, 5.6), 0.2, .chrome, category: mc)
            }
        }
    }

    // MARK: グリル・バンパー

    mutating func grille(_ FX: Double) {
        let gc = CamperCategory.grille
        rbox("front.grille", B(FX + 0.5, 16, 0), CV3(2.4, 11, 52), 1.4, .black, category: gc)
        switch k(.grille) {
        case "vertical_slats":
            for i in 0..<10 {
                rbox("front.grilleBar", B(FX + 1.9, 16, -22.5 + Double(i) * 5), CV3(1, 9.4, 1.2), 0.4, .chrome, category: gc)
            }
        case "honeycomb":
            for row in 0..<4 {
                for col in 0..<12 {
                    let z = -22 + Double(col) * 4 + (row % 2 == 0 ? 0 : 2)
                    guard abs(z) < 24 else { continue }
                    lathe("front.honeycomb", B(FX + 1.4, 12 + Double(row) * 2.6, z), axis: CV3(1, 0, 0), [(1.4, 0), (1.4, 0.8), (1, 0.8), (1, 0)],
                          segments: 6, faceted: true, category: gc) { _ in .chromeDark }
                }
            }
        case "mesh_brass":
            for i in 0..<12 {
                let z = -24 + Double(i) * 4.4
                for d in [-1.0, 1.0] {
                    rbox("front.grilleBar", B(FX + 1.8 + (d > 0 ? 0.3 : 0), 16, z), CV3(0.5, 13, 0.6), 0.1, .brass,
                         CQuat.axisAngle(CV3(1, 0, 0), d * .pi / 4), category: gc)
                }
            }
            for y in [10.8, 21.2] { rbox("front.grilleFrame", B(FX + 2.2, y, 0), CV3(1.2, 1.2, 52), 0.4, .brass, category: gc) }
        default:
            for i in 0..<5 {
                rbox("front.grilleBar", B(FX + 1.9, 11.6 + Double(i) * 2.2, 0), CV3(0.9, 0.8, 48), 0.3, .chrome, category: gc)
            }
        }
    }

    mutating func frontBumper(_ FX: Double) {
        let bc = CamperCategory.bumper
        switch k(.bumper) {
        case "black_steel":
            rbox("front.bumper", B(FX + 3, 32, 0), CV3(6, 7, BW * 2 + 4), 0.6, .steel, category: bc)
            for i in 0..<8 {
                add("front.bolt", .cylinder(radius: 0.8, height: 0.6, segments: 6), .chromeDark, at: B(FX + 6.2, 32, -42 + Double(i) * 12),
                    CQuat.yTo(CV3(1, 0, 0)), category: bc)
            }
        case "wood_beam":
            rbox("front.bumper", B(FX + 3.5, 32, 0), CV3(7, 8, BW * 2 + 6), 1, .woodDark, category: bc)
            for z in [-34.0, 34] { rbox("front.bumperStrap", B(FX + 3.5, 32, z), CV3(7.4, 8.4, 2), 0.3, .chassis, category: bc) }
        case "bullbar":
            rod("front.bumper", B(FX + 6, 34, -(BW - 2)), B(FX + 6, 34, BW - 2), 1.6, .steel, category: bc)
            rod("front.bullbar", B(FX + 7, 6, -22), B(FX + 7, 6, 22), 1.4, .steel, category: bc)
            for z in [-22.0, 22] { rod("front.bullbar", B(FX + 6, 34, z), B(FX + 7, 6, z), 1.4, .steel, category: bc) }
            for z in [-40.0, 40] { rod("front.bullbar", B(FX + 6, 34, z), B(FX + 6.5, 18, z * 0.7), 1.2, .steel, category: bc) }
            for z in [-26.0, 26] { rod("front.bumperMount", B(FX, 31, z), B(FX + 6, 31, z), 1.2, .black, category: bc) }
        default:
            rbox("front.bumper", B(FX + 3, 32, 0), CV3(5, 5, BW * 2 + 4), 2.2, .chrome, category: bc)
        }
    }

    // MARK: はしご

    mutating func ladder(_ BX: Double) {
        let lc = CamperCategory.ladder
        let key = k(.ladder)
        let railMat: CamperMaterial = key == "wood_rungs" ? .wood : (key == "black_alu" ? .black : .chrome)
        for z in [22.0, 40.0] {
            if key == "wood_rungs" {
                rbox("rear.ladderRail", CV3(BX - 4, (62 + 70 + 62 - 26) / 2, z), CV3(2.4, 96, 2.4), 0.5, .wood, category: lc)
            } else {
                rod("rear.ladderRail", B(BX - 4, -70, z), B(BX - 4, 26, z), 1, railMat, category: lc)
            }
        }
        for i in 0..<7 {
            let y = -60 + Double(i) * 12.5
            switch key {
            case "black_alu":
                rbox("rear.ladderRung", B(BX - 4.5, y, 31), CV3(4, 1, 18), 0.3, .black, category: lc)
                for g in 0..<3 {
                    rbox("rear.ladderGrip", B(BX - 4.5, y - 0.6, 25 + Double(g) * 6), CV3(4, 0.3, 0.4), 0.1, .chromeDark, category: lc)
                }
            case "wood_rungs":
                rod("rear.ladderRung", B(BX - 4, y, 22), B(BX - 4, y, 40), 1, .woodDark, segments: 8, category: lc)
            default:
                rod("rear.ladderRung", B(BX - 4, y, 22), B(BX - 4, y, 40), 0.8, .chrome, segments: 8, category: lc)
            }
        }
        if key == "folding" {
            for z in [22.0, 40] { rbox("rear.ladderHinge", B(BX - 4, -22, z), CV3(3, 4, 3), 0.6, .brass, category: lc) }
        }
        let clampMat: CamperMaterial = key == "wood_rungs" ? .brass : (key == "black_alu" ? .chassis : .chrome)
        for y in [-66.0, 20] {
            for z in [22.0, 40] { rbox("rear.ladderClamp", B(BX - 2, y, z), CV3(4, 1.6, 2), 0.5, clampMat, category: lc) }
        }
    }

    // MARK: 泥よけ

    mutating func mudFlaps() {
        let mc = CamperCategory.mudflap
        for cx in wheels {
            for s in [-1.0, 1] {
                let c = CV3(cx - 27, 15, s * (BW - 8))
                switch k(.mudflap) {
                case "logo_brass":
                    rbox("under.mudFlap", c, CV3(1, 12, 14), 0.4, .rubber, category: mc)
                    add("under.mudFlapLogo", .cylinder(radius: 3, height: 0.5, segments: 18), .brass, at: c + CV3(-0.6, 1, 0),
                        CQuat.yTo(CV3(-1, 0, 0)), category: mc)
                case "checker":
                    rbox("under.mudFlap", c, CV3(1, 12, 14), 0.4, .tint(0xEDEAE2), category: mc)
                    for row in 0..<3 {
                        for col in 0..<4 where (row + col) % 2 == 0 {
                            rbox("under.mudFlapCheck", c + CV3(-0.55, -4 + Double(row) * 4, -5.25 + Double(col) * 3.5), CV3(0.2, 4, 3.5), 0,
                                 .tint(0x1B1C1F), category: mc)
                        }
                    }
                case "long_rally":
                    rbox("under.mudFlap", c + CV3(0, -5, 0), CV3(1, 21, 14), 0.4, .rubber, category: mc)
                    rbox("under.mudFlapStripe", c + CV3(-0.55, -11, 0), CV3(0.3, 3, 14), 0.1, .tint(0xA4372B), category: mc)
                default:
                    rbox("under.mudFlap", c, CV3(1, 12, 14), 0.4, .rubber, category: mc)
                }
            }
        }
    }

    // MARK: タイヤの溝・ホイールキャップ

    /// (列, 一周の山の数, 山の割合, 溝の深さ)
    var treadSpec: (rows: [(Double, Double)], pitches: Int, land: Double, depth: Double) {
        switch k(.tireTread) {
        case "all_terrain": return ([(3, 8.2), (8.9, 13.1), (13.8, 19)], 22, 0.66, 1.3)
        case "mud_block": return ([(3, 10.2), (11.8, 19)], 14, 0.55, 1.8)
        case "snow_sipe": return ([(3, 8), (8.6, 13.4), (14, 19)], 34, 0.62, 1.1)
        default: return ([(3, 6.4), (7.4, 10.4), (11.6, 14.6), (15.6, 19)], 40, 0.96, 1)
        }
    }

    /// ホイールの真ん中のキャップ（`face` はホイールの外の面・`axis` は外向き）
    mutating func hubcap(at face: CV3, axis: CV3) {
        let hc = CamperCategory.hubcap
        let q = CQuat.yTo(axis)
        switch k(.hubcap) {
        case "flat_brass":
            add("wheel.hubcap", .cylinder(radius: 4.2, height: 0.8, segments: 24), .brass, at: face + axis * 0.4, q, category: hc)
            for i in 0..<12 {
                let t = Double(i) / 12 * 2 * .pi
                let dir = q.rotate(CV3(cos(t), 0, sin(t)))
                add("wheel.hubcapRib", .box(CV3(0.3, 2.4, 0.3), chamfer: 0), .chromeDark, at: face + axis * 0.9 + dir * 2.6,
                    CQuat.yTo(dir), category: hc)
            }
        case "star_cap":
            var star: [CV2] = []
            for i in 0..<10 {
                let t = Double(i) / 10 * 2 * .pi + .pi / 2
                let r = i % 2 == 0 ? 4.4 : 1.9
                star.append(CV2(cos(t) * r, sin(t) * r))
            }
            let m = CamperMeshKit.extrude(star, depth: 1.2, front: .chrome, side: .chrome, bevel: 0.3)
            add("wheel.hubcap", .mesh(m), .chrome, at: face + axis * 1.2, CQuat.rotation(from: CV3(0, 0, 1), to: axis), category: hc)
        case "baby_moon":
            lathe("wheel.hubcap", face, axis: axis, [(5.6, 0), (5.6, 0.6), (4.4, 0.8)], segments: 28, category: hc) { _ in .whitewall }
            lathe("wheel.hubcapDome", face + axis * 0.6, axis: axis, [(4.4, 0), (3.6, 1.2), (2, 2), (0.01, 2.3)], segments: 24,
                  category: hc) { _ in .chrome }
        default:
            lathe("wheel.hubcap", face, axis: axis, [(3.8, 0), (3.4, 1.4), (2.2, 2.4), (0.01, 2.8)], segments: 20, category: hc) { _ in .chrome }
        }
    }

    // MARK: 自転車の台

    mutating func bikeRack() {
        guard stage != .trailer else { return }
        let rc = CamperCategory.bikeRack
        let key = k(.bikeRack)
        let BX = rear
        if key == "roof_one" {
            // 屋根の台に大きめの 1 台（太陽電池の外の縁）
            let RT = roofTop
            rbox("rear.roofBikeTray", CV3(-80, RT + 1.5, -42), CV3(64, 1.2, 4), 0.3, .chassis, category: rc)
            bicycle(x: -80, y: RT + 2.1, z: -42, alongX: true, color: 0x26385A, scale: 1.1, category: rc)
            return
        }
        for z in [-30.0, 30] { rbox("rear.carrierArm", CV3(BX - 15, 22, z), CV3(30, 2.4, 3), 0.5, .chassis, category: rc) }
        rbox("rear.carrierDeck", CV3(BX - 27, 23.6, 0), CV3(10, 1.2, 76), 0.4, .chassis, category: rc)
        switch key {
        case "rear_two":
            bicycle(x: BX - 26, y: 24.2, z: 0, alongX: false, color: 0xA4372B, scale: 1, category: rc)
            bicycle(x: BX - 33, y: 24.2, z: 0, alongX: false, color: 0x26385A, scale: 1, category: rc)
        case "folding_bike":
            bicycle(x: BX - 27, y: 24.2, z: 0, alongX: false, color: 0xC9A66B, scale: 0.7, category: rc)
        default:
            // 鉄のかごに木箱と布の袋
            for z in [-34.0, 34] { rbox("rear.basketRail", CV3(BX - 27, 32, z), CV3(12, 1.2, 1.2), 0.3, .black, category: rc) }
            for x in [BX - 21.0, BX - 33] { rbox("rear.basketRail", CV3(x, 32, 0), CV3(1.2, 1.2, 68), 0.3, .black, category: rc) }
            for i in 0..<6 {
                let z = -30 + Double(i) * 12
                for x in [BX - 21.0, BX - 33] { rod("rear.basketPost", CV3(x, 24.2, z), CV3(x, 32, z), 0.4, .black, segments: 6, category: rc) }
            }
            rbox("rear.basketCrate", CV3(BX - 27, 31, -14), CV3(11, 13, 26), 0.8, .wood, category: rc)
            lathe("rear.basketSack", CV3(BX - 27, 24.4, 16), axis: CV3(0, 1, 0), [(0.01, 0), (6, 1), (6.4, 6), (5, 11), (2, 13), (2.4, 14.6)],
                  segments: 14, capEnd: .canvasLight, category: rc) { _ in .canvasLight }
        }
    }

    /// 自転車（輪・スポーク・枠・サドル・ハンドル）。`alongX` なら車の前後の向き、でなければ車の幅の向き
    mutating func bicycle(x: Double, y base: Double, z: Double, alongX: Bool, color: UInt32, scale f: Double, category rc: CamperCategory) {
        let r = 10.0 * f, y = base + r
        let dir = alongX ? CV3(1, 0, 0) : CV3(0, 0, 1)
        let side = alongX ? CV3(0, 0, 1) : CV3(1, 0, 0)
        let o = CV3(x, 0, z)
        func at(_ along: Double, _ up: Double) -> CV3 { o + dir * along + CV3(0, up, 0) }
        for a in [-17.0 * f, 17.0 * f] {
            add("rear.bikeTyre", .torus(ring: r, pipe: 0.9 * f), .rubber, at: at(a, y), CQuat.yTo(side), category: rc)
            add("rear.bikeHub", .cylinder(radius: 1, height: 2.4, segments: 10), .chrome, at: at(a, y), CQuat.yTo(side), category: rc)
            for i in 0..<8 {
                let t = Double(i) / 8 * .pi
                rod("rear.bikeSpoke", at(a + sin(t) * r * 0.92, y + cos(t) * r * 0.92), at(a - sin(t) * r * 0.92, y - cos(t) * r * 0.92),
                    0.12, .chrome, segments: 4, category: rc)
            }
        }
        let frame = CamperMaterial.tint(color)
        let seat = at(-7 * f, y + 13 * f), head = at(10 * f, y + 13 * f), crank = at(-2 * f, y)
        rod("rear.bikeFrame", at(-17 * f, y), crank, 0.8, frame, category: rc)
        rod("rear.bikeFrame", crank, seat - CV3(0, 2, 0), 0.8, frame, category: rc)
        rod("rear.bikeFrame", seat - CV3(0, 2, 0), head, 0.8, frame, category: rc)
        rod("rear.bikeFrame", crank, head, 0.8, frame, category: rc)
        rod("rear.bikeFrame", head, at(17 * f, y), 0.7, frame, category: rc)
        rod("rear.bikeFrame", at(-17 * f, y), seat - CV3(0, 2, 0), 0.6, frame, category: rc)
        rbox("rear.bikeSeat", seat, alongX ? CV3(6, 1.4, 3) : CV3(3, 1.4, 6), 0.6, .black, category: rc)
        let bar = head + CV3(0, 2 * f, 0)
        rod("rear.bikeStem", head, bar, 0.6, .chrome, category: rc)
        rod("rear.bikeBar", bar - side * 6, bar + side * 6, 0.5, .chrome, category: rc)
        add("rear.bikeCrank", .cylinder(radius: 2.4, height: 0.6, segments: 14), .chrome, at: crank, CQuat.yTo(side), category: rc)
    }

    // MARK: スペアタイヤのカバー

    mutating func spareCover(_ BX: Double) {
        let sc = CamperCategory.spareCover
        let c = B(BX - 1, -6, -20)
        let out = CQuat.yTo(CV3(-1, 0, 0))
        let ring = CQuat.yTo(CV3(1, 0, 0))
        let profile = [CV2(18.5, 0), CV2(20.6, 1.4), CV2(21, 3), CV2(21, 10.4), CV2(20.2, 12.2), CV2(17, 13.2), CV2(0.01, 13.6)]
        switch k(.spareCover) {
        case "leather":
            let m = CamperMeshKit.lathe(profile, segments: 32, material: { _ in .tint(0x6B3E22) }, capStart: .tint(0x6B3E22))
            add("rear.spareCover", .mesh(m), .tint(0x6B3E22), at: c, out, category: sc)
            add("rear.spareStitch", .torus(ring: 18.2, pipe: 0.25), .tint(0xE8D2A2), at: B(BX - 14.0, -6, -20), ring, category: sc)
            add("rear.spareStitch", .torus(ring: 12, pipe: 0.25), .tint(0xE8D2A2), at: B(BX - 14.6, -6, -20), ring, category: sc)
            rbox("rear.spareBuckle", B(BX - 14.8, -25, -20), CV3(1, 3, 5), 0.3, .brass, category: sc)
        case "hardshell":
            let shell = [CV2(19, 0), CV2(21, 2), CV2(21.2, 9), CV2(19, 12.6), CV2(9, 14.6), CV2(0.01, 15)]
            let m = CamperMeshKit.lathe(shell, segments: 36, material: { _ in .chrome }, capStart: .chrome)
            add("rear.spareCover", .mesh(m), .chrome, at: c, out, category: sc)
            add("rear.spareCenter", .cylinder(radius: 8, height: 1, segments: 28), .black, at: B(BX - 15.6, -6, -20), ring, category: sc)
        case "map_print":
            let m = CamperMeshKit.lathe(profile, segments: 32, material: { _ in .tint(0xE9E2CF) }, capStart: .tint(0xE9E2CF))
            add("rear.spareCover", .mesh(m), .tint(0xE9E2CF), at: c, out, category: sc)
            let pts: [(Double, Double)] = [(-12, -6), (-6, -2), (-2, -8), (4, -4), (8, 4), (3, 9), (-4, 6)]
            for i in 0..<(pts.count - 1) {
                let a = B(BX - 14.7, -6 + pts[i].1, -20 + pts[i].0), b = B(BX - 14.7, -6 + pts[i + 1].1, -20 + pts[i + 1].0)
                rod("rear.spareRoute", a, b, 0.4, .tint(0x7A2E22), segments: 5, category: sc)
                add("rear.spareDot", .sphere(radius: 0.9), .tint(0x2F4F74), at: a, category: sc)
            }
            add("rear.spareRing", .torus(ring: 16.8, pipe: 0.6), .brass, at: B(BX - 14.4, -6, -20), ring, category: sc)
        default:
            let m = CamperMeshKit.lathe(profile, segments: 32, material: { _ in .fabricDark }, capStart: .fabricDark)
            add("rear.spareCover", .mesh(m), .fabricDark, at: c, out, category: sc)
            add("rear.spareRing", .torus(ring: 16.8, pipe: 0.8), .brass, at: B(BX - 14.4, -6, -20), ring, category: sc)
            add("rear.spareStitch", .torus(ring: 18.6, pipe: 0.25), .canvasLight, at: B(BX - 14.0, -6, -20), ring, category: sc)
        }
        rbox("rear.spareMount", B(BX - 0.5, -6, -20), CV3(2, 8, 8), 0.6, .black)
    }

    // MARK: 屋根の積み荷

    mutating func cargo(base y: Double, x cx: Double) {
        let rc = CamperCategory.roofCargo
        switch k(.roofCargo) {
        case "roof_box":
            rbox("cargo.box", CV3(cx, y + 6, 0), CV3(80, 12, 60), 5, .roofBox, category: rc)
            rbox("cargo.boxNose", CV3(cx + 38, y + 4.5, 0), CV3(12, 9, 54), 4, .roofBox, category: rc)
            rbox("cargo.boxSeam", CV3(cx, y + 8.4, 0), CV3(78, 0.5, 60.4), 0.2, .black, category: rc)
            for dx in [-21.0, 21] { rbox("cargo.latch", CV3(cx + dx, y + 8, 30.4), CV3(6, 2, 1), 0.4, .chrome, category: rc) }
            only([.snow]) { $0.rbox("cargo.snow", CV3(cx, y + 13, 0), CV3(76, 2.6, 56), 1.2, .snow) }
        case "canoe":
            let hull = CamperMeshKit.lathe([CV2(0.01, 0), CV2(5, 9), CV2(7.4, 28), CV2(7.8, 46), CV2(7.4, 64), CV2(5, 83), CV2(0.01, 92)],
                                           segments: 18, material: { _ in .wallWood(0xA4532E) })
            add("cargo.canoe", .mesh(hull), .wallWood(0xA4532E), at: CV3(cx - 46, y + 5, 0), CQuat.yTo(CV3(1, 0, 0)), category: rc,
                scale: CV3(1, 0.7, 1))
            for x in [cx - 16, cx + 24] {
                add("cargo.strap", .torus(ring: 8.4, pipe: 0.6), .black, at: CV3(x, y + 5, 0), CQuat.yTo(CV3(1, 0, 0)), category: rc,
                    scale: CV3(1, 1, 0.7))
            }
        case "surfboard":
            let board = CamperMeshKit.lathe([CV2(0.01, 0), CV2(4, 6), CV2(7.5, 20), CV2(8.2, 40), CV2(7, 62), CV2(3.4, 80), CV2(0.01, 88)],
                                            segments: 20, material: { _ in .tint(0xF2EFE6) })
            add("cargo.surfboard", .mesh(board), .tint(0xF2EFE6), at: CV3(cx - 44, y + 1.6, 0), CQuat.yTo(CV3(1, 0, 0)), category: rc,
                scale: CV3(1, 0.14, 1))
            rbox("cargo.surfStripe", CV3(cx, y + 2.8, 0), CV3(80, 0.3, 1.6), 0.1, .tint(0x2F6F9A), category: rc)
            rbox("cargo.surfFin", CV3(cx - 38, y + 0.2, 0), CV3(5, 3, 0.6), 0.2, .tint(0x1B1C1F), category: rc)
            for x in [cx - 14, cx + 18] { rbox("cargo.strap", CV3(x, y + 3.4, 0), CV3(2, 4.6, 20), 0.4, .black, category: rc) }
        default:
            let crate = CV3(cx - 19, y + 8.5, -16)
            rbox("cargo.crate", crate, CV3(26, 17, 36), 1.6, .wood, category: rc)
            for i in 0..<3 {
                rbox("cargo.crateSlat", crate + CV3(0, -5.4 + Double(i) * 5.4, 18.1), CV3(26, 0.6, 0.4), 0.1, .woodDark, category: rc)
            }
            for dx in [-12.4, 12.4] {
                for dz in [-17.6, 17.6] { rbox("cargo.crateCorner", crate + CV3(dx, 0, dz), CV3(1.6, 17.4, 1.6), 0.3, .black, category: rc) }
                for dy in [-6.5, 6.5] { add("cargo.rivet", .sphere(radius: 0.6), .brass, at: crate + CV3(dx, dy, 18.2), category: rc) }
            }
            let mat = CamperMeshKit.lathe([CV2(0.01, 0), CV2(6.5, 0), CV2(6.8, 1.5), CV2(6.8, 46.5), CV2(6.5, 48), CV2(0.01, 48)],
                                          segments: 18, material: { i in i == 0 || i == 4 ? .fabricDark : .fabric })
            add("cargo.mat", .mesh(mat), .fabric, at: CV3(cx + 13, y + 7, -22), CQuat.yTo(CV3(0, 0, 1)), category: rc)
            for z in [-10.0, 14] {
                add("cargo.matStrap", .torus(ring: 7.0, pipe: 0.6), .tint(0x4A2E17), at: CV3(cx + 13, y + 7, z), CQuat.yTo(CV3(0, 0, 1)), category: rc)
            }
            rbox("cargo.jerry", CV3(cx + 31, y + 8, 24), CV3(11, 16, 18), 1.6, .jerry, category: rc)
            rbox("cargo.jerryRib", CV3(cx + 25.4, y + 8, 24), CV3(0.6, 12, 14), 0.2, .jerry, category: rc)
            lathe("cargo.jerryCap", CV3(cx + 33, y + 16, 28), axis: CV3(0, 1, 0), [(1.6, 0), (1.6, 2.6), (0.01, 2.8)], segments: 10,
                  capStart: .black, category: rc) { _ in .black }
            only([.snow]) { $0.rbox("cargo.snow", crate + CV3(0, 10, 0), CV3(27, 3, 37), 1.4, .snow) }
        }
    }

    // MARK: ルーフテント（付けないのが普通・屋根の後ろ半分に脚で立てる）

    mutating func roofTent() {
        let key = k(.roofTent)
        guard key != CamperLoadout.none, !van else { return }
        let tc = CamperCategory.roofTent
        let y = roofTop + 8, cx = -74.0, len = 62.0, half = 40.0
        for x in [cx - 26, cx + 26] { for z in [-34.0, 34] { rod("tent.foot", CV3(x, roofTop, z), CV3(x, y, z), 1, .black, category: tc) } }
        rbox("tent.base", CV3(cx, y + 2.5, 0), CV3(len + 2, 5, half * 2 + 2), 1.6, .tint(0x2E3236), category: tc)
        switch key {
        case "clamshell":
            rbox("tent.lid", CV3(cx - 2, y + 18, 0), CV3(len + 2, 2.4, half * 2 + 2), 1.2, .tint(0xEDEAE2),
                 CQuat.axisAngle(CV3(0, 0, 1), 0.42), category: tc)
            for s in [-1.0, 1] {
                let tri = CamperMeshKit.extrude([CV2(-len / 2, 0), CV2(len / 2, 0), CV2(len / 2 - 2, 26)], depth: 0.4,
                                                front: .canvas(0x6E7B5A), side: .canvas(0x6E7B5A))
                add("tent.side", .mesh(tri), .canvas(0x6E7B5A), at: CV3(cx, y + 5, s * half), category: tc)
            }
        case "popup_canvas":
            rbox("tent.canvas", CV3(cx, y + 17, 0), CV3(len - 2, 24, half * 2 - 2), 0.6, .canvas(0xC8B48A), category: tc)
            rbox("tent.roof", CV3(cx, y + 29.5, 0), CV3(len + 2, 2, half * 2 + 2), 1, .tint(0x2E3236), category: tc)
            for i in 0..<3 {
                rbox("tent.window", CV3(cx - 20 + Double(i) * 20, y + 19, half - 0.6), CV3(12, 9, 0.6), 0.4, .glass, category: tc)
            }
        case "triangle_hardtop":
            let ridge = 30.0
            let slope = atan2(ridge, half)
            let side = (ridge * ridge + half * half).squareRoot()
            for s in [-1.0, 1] {
                rbox("tent.roof", CV3(cx, y + 5 + ridge / 2, s * half / 2), CV3(len, 1.2, side), 0.4, .roofBox,
                     CQuat.axisAngle(CV3(1, 0, 0), s * slope), category: tc)
            }
            let tri = [CV2(-half, 0), CV2(half, 0), CV2(0, ridge)]
            for s in [-1.0, 1] {
                let end = CamperMeshKit.extrude(tri, holes: [CamperPolygon.circle(CV2(0, 12), 5, count: 16)], depth: 0.6,
                                                front: .canvas(0x8A9A6A), side: .canvas(0x8A9A6A))
                add("tent.end", .mesh(end), .canvas(0x8A9A6A), at: CV3(cx + s * len / 2, y + 5, 0),
                    CQuat.rotation(from: CV3(0, 0, 1), to: CV3(s, 0, 0)), category: tc)
            }
        default:
            // 翼のタープ: 箱から反対側へ張る布と柱 2
            rbox("tent.box", CV3(cx, y + 9, 0), CV3(len, 8, half * 2), 1.4, .tint(0xEDEAE2), category: tc)
            let a = CV3(cx - len / 2, y + 12, -half), b = CV3(cx + len / 2, y + 12, -half)
            let c2 = CV3(cx + len / 2, 70, -half - 60), d = CV3(cx - len / 2, 70, -half - 60)
            var m = CamperMesh()
            let n = (b - a).cross(d - a).normalized
            m.quad(a, b, c2, d, n, n, n, n, .canvas(0xD9622B))
            m.quad(a - n * 0.4, d - n * 0.4, c2 - n * 0.4, b - n * 0.4, -n, -n, -n, -n, .canvas(0xD9622B))
            add("tent.wing", .mesh(m), .canvas(0xD9622B), at: .zero, category: tc)
            for p in [c2, d] { rod("tent.pole", p, CV3(p.x, 0.5, p.z), 0.8, .alu, category: tc) }
        }
    }

    // MARK: ソーラー・アンテナ・旗

    mutating func solarPanels() {
        guard !van else { return }
        // 雪の日は雪に埋もれて見えない
        only([.day, .night]) { $0.solarPanelsBody() }
    }

    private mutating func solarPanelsBody() {
        let RT = roofTop
        let sc = CamperCategory.solar
        func panel(_ c: CV3, _ w: Double, _ d: Double, _ q: CQuat = .identity) {
            rbox("roof.solarFrame", c, CV3(w, 2.4, d), 1, .solarFrame, q, category: sc)
            rbox("roof.solar", c + q.rotate(CV3(0, 1.3, 0)), CV3(w - 3, 0.4, d - 3), 0.1, .solar, q, category: sc)
        }
        switch k(.solar) {
        case "twin":
            panel(CV3(-92, RT + 1.2, 0), 28, 70)
            panel(CV3(-58, RT + 1.2, 0), 28, 70)
        case "folding_suitcase":
            panel(CV3(-88, RT + 6, 0), 30, 60, CQuat.axisAngle(CV3(0, 0, 1), 0.5))
            panel(CV3(-60, RT + 6, 0), 30, 60, CQuat.axisAngle(CV3(0, 0, 1), -0.5))
            rod("roof.solarHinge", CV3(-74, RT + 0.8, -28), CV3(-74, RT + 0.8, 28), 0.8, .chrome, category: sc)
            rbox("roof.solarHandle", CV3(-74, RT + 1.2, 31), CV3(8, 1.4, 1.4), 0.4, .black, category: sc)
        case "flexible_curve":
            for i in 0..<8 {
                let z = -31.5 + Double(i) * 9
                rbox("roof.solar", CV3(-74, RT + 2.3 - z * z * 0.0015, z), CV3(60, 0.5, 9), 0.1, .solar,
                     CQuat.axisAngle(CV3(1, 0, 0), -z / 120), category: sc)
            }
        default:
            panel(CV3(-74, RT + 1.2, 0), 62, 70)
        }
    }

    mutating func antenna() {
        let ac = CamperCategory.antenna
        let RT = roofTop
        let base = CV3(van ? 40 : 58, RT, -38)
        switch k(.antenna) {
        case "mushroom_gps":
            rod("roof.antennaMast", base, base + CV3(0, 3, 0), 1, .black, category: ac)
            lathe("roof.antennaDome", base + CV3(0, 3, 0), axis: CV3(0, 1, 0), [(4, 0), (3.6, 2), (2, 3.6), (0.01, 4)], segments: 18,
                  capStart: .tint(0xEDEAE2), category: ac) { _ in .tint(0xEDEAE2) }
        case "dish":
            rod("roof.antennaMast", base, base + CV3(0, 8, 0), 0.8, .alu, category: ac)
            let dish = CamperMeshKit.lathe([CV2(0.01, 0), CV2(4, 0.6), CV2(7.5, 2.2), CV2(9, 3.6), CV2(8.6, 3.8), CV2(7.1, 2.6), CV2(3.8, 1), CV2(0.01, 0.4)],
                                           segments: 24, material: { _ in .tint(0xE7E3DA) })
            add("roof.antennaDish", .mesh(dish), .tint(0xE7E3DA), at: base + CV3(0, 10, 0), CQuat.yTo(CV3(0.5, 0.6, 0.6)), category: ac)
            rod("roof.antennaFeed", base + CV3(0, 10, 0), base + CV3(3, 15, 3), 0.3, .black, segments: 6, category: ac)
        case "ham_long":
            add("roof.antennaBase", .cylinder(radius: 1.6, height: 2, segments: 10), .black, at: base + CV3(0, 1, 0), category: ac)
            rod("roof.antenna", base + CV3(0, 2, 0), base + CV3(0, 80, 0), 0.4, .alu, segments: 6, category: ac)
            for i in 0..<5 {
                let y = 40 + Double(i) * 8, w = 14 - Double(i) * 2
                rod("roof.antennaBar", base + CV3(-w / 2, y, 0), base + CV3(w / 2, y, 0), 0.3, .alu, segments: 5, category: ac)
            }
        default:
            add("roof.antennaBase", .cylinder(radius: 1.4, height: 2, segments: 10), .black, at: base + CV3(0, 1, 0), category: ac)
            rod("roof.antenna", base + CV3(0, 2, 0), base + CV3(-4, 62, 0), 0.25, .chrome, segments: 6, category: ac)
        }
    }

    mutating func flag() {
        let fc = CamperCategory.flag
        let pole = CV3(rear + 8, roofTop, -40)
        let top = pole + CV3(0, 44, 0)
        rod("flag.pole", pole, top, 0.6, .alu, category: fc)
        switch k(.flag) {
        case "swallowtail":
            let cloth = CamperMeshKit.extrude([CV2(0, 0), CV2(20, 0), CV2(14, 6), CV2(20, 12), CV2(0, 12)], depth: 0.3,
                                              front: .canvas(0x2F4F74), side: .canvas(0x2F4F74))
            add("flag.swallowtail", .mesh(cloth), .canvas(0x2F4F74), at: top + CV3(0, -13, 0), category: fc)
        case "prayer_line":
            let end = CV3(van ? 40 : 60, roofTop + 12, -40)
            rod("flag.string", top, end, 0.2, .canvasLight, segments: 4, category: fc)
            let colors: [UInt32] = [0x2F4F74, 0xEDEAE2, 0xA4372B, 0x4A5A46, 0xD9B24A, 0x2F4F74]
            for i in 0..<6 {
                let p = top + (end - top) * ((Double(i) + 0.5) / 6)
                rbox("flag.prayer", p + CV3(0, -4, 0), CV3(7, 7, 0.3), 0.1, .canvas(colors[i]), category: fc)
            }
        case "windsock":
            let sock = CamperMeshKit.lathe([CV2(4, 0), CV2(3.4, 6), CV2(2.8, 12), CV2(2.2, 18), CV2(1.6, 24)], segments: 16,
                                           material: { $0 % 2 == 0 ? .canvas(0xD9622B) : .canvasLight })
            add("flag.windsock", .mesh(sock), .canvas(0xD9622B), at: top + CV3(1, -2, 0), CQuat.yTo(CV3(1, -0.15, 0.2)), category: fc)
            add("flag.windsockRing", .torus(ring: 4, pipe: 0.3), .alu, at: top + CV3(1, -2, 0), CQuat.yTo(CV3(1, -0.15, 0.2)), category: fc)
        default:
            let tri = CamperMeshKit.extrude([CV2(0, 0), CV2(0, 10), CV2(20, 5)], depth: 0.3, front: .canvas(0xA4532E), side: .canvas(0xA4532E))
            add("flag.pennant", .mesh(tri), .canvas(0xA4532E), at: top + CV3(0, -11, 0), category: fc)
            rbox("flag.pennantLine", top + CV3(8, -6, 0.2), CV3(14, 0.6, 0.2), 0, .canvasLight, category: fc)
        }
        add("flag.finial", .sphere(radius: 1), .brass, at: top + CV3(0, 0.8, 0), category: fc)
    }

    // MARK: 外の置き物（扉の側の地面）

    mutating func campsite() {
        // 2026-10-18（Mac の絵 run 530）: BW + 34 では車の横に小さく潰れて見えた。車から離し（カメラの側へ出す）、
        // 椅子・机・焚き火が車の影と重ならずに読める所へ。床が透け始める 190 より手前に収める
        let z0 = BW + 50.0
        rug(at: CV3(-40, 0, z0 + 6))
        chairs(z: z0)
        table(at: CV3(-48, 0, z0 + 8))
        firePit(at: CV3(-40, 0, z0 + 36))
        outdoorLight(z: z0)
    }

    mutating func rug(at c: CV3) {
        let rc = CamperCategory.rug
        switch k(.rug) {
        case "striped":
            for i in 0..<8 {
                rbox("rug.stripe", c + CV3(-28 + Double(i) * 8, 0.3, 0), CV3(8, 0.6, 36), 0.1, .canvas(i % 2 == 0 ? 0x2F4F74 : 0xA4372B), category: rc)
            }
        case "round_braided":
            let colors: [UInt32] = [0x8A6D3D, 0xD8CCB4, 0x7A2E22, 0xD8CCB4]
            for (i, col) in colors.enumerated() {
                add("rug.ring", .cylinder(radius: 26 - Double(i) * 6, height: 0.5 + Double(i) * 0.12, segments: 40), .canvas(col),
                    at: c + CV3(0, 0.26 + Double(i) * 0.06, 0), category: rc)
            }
        case "kilim":
            rbox("rug.mat", c + CV3(0, 0.3, 0), CV3(60, 0.6, 36), 0.2, .canvas(0x8E2A22), category: rc)
            for i in 0..<5 {
                rbox("rug.diamond", c + CV3(-24 + Double(i) * 12, 0.65, 0), CV3(6, 0.2, 6), 0, .canvas(0xC9A66B),
                     CQuat.axisAngle(CV3(0, 1, 0), .pi / 4), category: rc)
            }
            for s in [-1.0, 1] { rbox("rug.border", c + CV3(0, 0.62, s * 15), CV3(58, 0.2, 2), 0, .canvas(0xC9A66B), category: rc) }
        default:
            rbox("rug.mat", c + CV3(0, 0.3, 0), CV3(60, 0.6, 36), 0.2, .wallWood(0xC8A96A), category: rc)
            for i in 0..<9 { rbox("rug.weave", c + CV3(-28 + Double(i) * 7, 0.62, 0), CV3(0.6, 0.2, 34), 0, .tint(0x8A6D3D), category: rc) }
        }
    }

    mutating func chairs(z: Double) {
        let cc = CamperCategory.chair
        switch k(.chair) {
        case "director_chair":
            for (x, yaw) in [(-14.0, -0.6), (-78.0, 0.6)] {
                let q = CQuat.axisAngle(CV3(0, 1, 0), yaw)
                let o = CV3(x, 0, z)
                for s in [-1.0, 1] {
                    rod("chair.leg", o + q.rotate(CV3(s * 8, 0, -6)), o + q.rotate(CV3(s * 8, 14, 6)), 0.7, .woodDark, category: cc)
                    rod("chair.leg", o + q.rotate(CV3(s * 8, 0, 6)), o + q.rotate(CV3(s * 8, 14, -6)), 0.7, .woodDark, category: cc)
                    rod("chair.post", o + q.rotate(CV3(s * 8, 14, -6)), o + q.rotate(CV3(s * 8, 30, -6)), 0.7, .woodDark, category: cc)
                    rod("chair.arm", o + q.rotate(CV3(s * 8, 20, -6)), o + q.rotate(CV3(s * 8, 20, 7)), 0.7, .woodDark, category: cc)
                }
                rbox("chair.seat", o + q.rotate(CV3(0, 14, 0)), CV3(16, 0.5, 12), 0.1, .canvas(0x2F4F74), q, category: cc)
                rbox("chair.back", o + q.rotate(CV3(0, 26, -6)), CV3(16, 6, 0.5), 0.1, .canvas(0x2F4F74), q, category: cc)
            }
        case "wooden_stool":
            for (x, dz) in [(-14.0, -2.0), (-76.0, 6.0)] {
                let c = CV3(x, 0, z + dz)
                add("chair.stoolSeat", .cylinder(radius: 6, height: 1.6, segments: 20), .wood, at: c + CV3(0, 14, 0), category: cc)
                for i in 0..<4 {
                    let t = Double(i) / 4 * 2 * .pi + .pi / 4
                    rod("chair.stoolLeg", c + CV3(cos(t) * 4, 13.4, sin(t) * 4), c + CV3(cos(t) * 5.6, 0, sin(t) * 5.6), 0.7, .woodDark, category: cc)
                }
            }
        case "hammock":
            let c = CV3(-40, 0, z + 60)
            for s in [-1.0, 1] {
                rod("chair.hammockPost", c + CV3(s * 40, 0, 0), c + CV3(s * 40, 34, 0), 1.4, .woodDark, category: cc)
                rod("chair.hammockRope", c + CV3(s * 40, 30, 0), c + CV3(s * 26, 22, 0), 0.25, .canvasLight, segments: 4, category: cc)
            }
            for i in 0..<6 {
                let x0 = -26 + Double(i) * 52 / 6, x1 = x0 + 52 / 6
                let y0 = 22 - 8 * sin((x0 + 26) / 52 * .pi), y1 = 22 - 8 * sin((x1 + 26) / 52 * .pi)
                let a = c + CV3(x0, y0, 0), b = c + CV3(x1, y1, 0)
                rbox("chair.hammockNet", (a + b) * 0.5, CV3((b - a).length, 0.5, 16), 0.2, .canvas(0xD9622B),
                     CQuat.axisAngle(CV3(0, 0, 1), atan2(y1 - y0, x1 - x0)), category: cc)
            }
        default:
            for (x, yaw) in [(-14.0, -0.6), (-78.0, 0.6)] {
                let q = CQuat.axisAngle(CV3(0, 1, 0), yaw)
                let o = CV3(x, 0, z)
                for s in [-1.0, 1] {
                    rod("chair.leg", o + q.rotate(CV3(s * 7, 0, -6)), o + q.rotate(CV3(s * 7, 14, 6)), 0.5, .black, category: cc)
                    rod("chair.leg", o + q.rotate(CV3(s * 7, 0, 6)), o + q.rotate(CV3(s * 7, 14, -6)), 0.5, .black, category: cc)
                    rod("chair.arm", o + q.rotate(CV3(s * 7.4, 18, -7)), o + q.rotate(CV3(s * 7.4, 18, 7)), 0.6, .black, category: cc)
                }
                rbox("chair.seat", o + q.rotate(CV3(0, 13, 0)), CV3(14, 0.5, 12), 0.1, .canvas(0x4A5A46), q, category: cc)
                rbox("chair.back", o + q.rotate(CV3(0, 22, -6.5)), CV3(14, 12, 0.5), 0.1, .canvas(0x4A5A46),
                     q * CQuat.axisAngle(CV3(1, 0, 0), 0.15), category: cc)
                rbox("chair.seam", o + q.rotate(CV3(0, 13.3, 0)), CV3(13, 0.2, 0.3), 0, .canvasLight, q, category: cc)
            }
        }
    }

    mutating func table(at c: CV3) {
        let tc = CamperCategory.table
        var top = 18.6
        switch k(.table) {
        case "rolltop":
            for i in 0..<9 { rbox("table.slat", c + CV3(-14 + Double(i) * 3.5, 18, 0), CV3(3.2, 1, 18), 0.4, .wood, category: tc) }
            for s in [-1.0, 1] {
                rod("table.rollLeg", c + CV3(s * 12, 0, 0), c + CV3(s * 12, 17.4, 0), 0.6, .alu, category: tc)
                rod("table.rollFoot", c + CV3(s * 12, 0.5, -7), c + CV3(s * 12, 0.5, 7), 0.6, .alu, category: tc)
            }
            top = 18.5
        case "wooden_crate_table":
            rbox("table.crate", c + CV3(0, 8, 0), CV3(24, 16, 16), 1, .wood, category: tc)
            for i in 0..<3 { rbox("table.crateSlat", c + CV3(0, 3 + Double(i) * 5, 8.1), CV3(24, 0.5, 0.4), 0.1, .woodDark, category: tc) }
            rbox("table.top", c + CV3(0, 16.8, 0), CV3(32, 1.6, 22), 0.5, .woodDark, category: tc)
            top = 17.6
        case "camp_cube":
            rbox("table.cube", c + CV3(0, 9, 0), CV3(22, 18, 16), 2.4, .tint(0x2F4F74), category: tc)
            rbox("table.cubeLid", c + CV3(0, 18.4, 0), CV3(22.6, 1.6, 16.6), 0.6, .canvasLight, category: tc)
            for s in [-1.0, 1] { rbox("table.cubeHandle", c + CV3(s * 11.6, 13, 0), CV3(1, 2, 8), 0.4, .black, category: tc) }
            top = 19.2
        default:
            rbox("table.top", c + CV3(0, 18, 0), CV3(28, 1.2, 18), 0.4, .alu, category: tc)
            for s in [-1.0, 1] {
                rod("table.leg", c + CV3(s * 12, 0, -7), c + CV3(s * 12, 17.4, 7), 0.5, .alu, category: tc)
                rod("table.leg", c + CV3(s * 12, 0, 7), c + CV3(s * 12, 17.4, -7), 0.5, .alu, category: tc)
            }
        }
        // 机の上のマグ（室内のマグと同じ形）
        mugShape("table.mug", at: c + CV3(6, top, 3))
    }

    mutating func firePit(at c: CV3) {
        let fc = CamperCategory.firePit
        var emberAt = c + CV3(0, 9.6, 0)
        switch k(.firePit) {
        case "stone_ring":
            for i in 0..<9 {
                let t = Double(i) / 9 * 2 * .pi
                add("fire.stone", .sphere(radius: 3.4), .stone, at: c + CV3(cos(t) * 11, 1.6, sin(t) * 11), category: fc, scale: CV3(1, 0.6, 1))
            }
            for i in 0..<3 {
                let t = Double(i) / 3 * 2 * .pi
                rod("fire.log", c + CV3(cos(t) * 8, 1, sin(t) * 8), c + CV3(0, 7, 0), 1.4, .woodDark, segments: 8, category: fc)
            }
            emberAt = c + CV3(0, 3, 0)
        case "brazier":
            let bowl = CamperMeshKit.lathe([CV2(0.01, 0), CV2(6, 0.6), CV2(10, 4), CV2(10.6, 10), CV2(10, 10.2), CV2(9.4, 4.4), CV2(5.6, 1.2), CV2(0.01, 0.8)],
                                           segments: 24, material: { _ in .chrome })
            add("fire.brazier", .mesh(bowl), .chrome, at: c + CV3(0, 3, 0), category: fc)
            for i in 0..<12 {
                let t = Double(i) / 12 * 2 * .pi
                add("fire.hole", .cylinder(radius: 1, height: 0.8, segments: 8), .well, at: c + CV3(cos(t) * 10.4, 9, sin(t) * 10.4),
                    CQuat.yTo(CV3(cos(t), 0, sin(t))), category: fc)
            }
            for i in 0..<3 {
                let t = Double(i) / 3 * 2 * .pi
                rod("fire.leg", c + CV3(cos(t) * 8, 0, sin(t) * 8), c + CV3(cos(t) * 6, 4, sin(t) * 6), 0.6, .chassis, category: fc)
            }
            emberAt = c + CV3(0, 9, 0)
        case "tripod_kettle":
            for i in 0..<3 {
                let t = Double(i) / 3 * 2 * .pi
                rod("fire.tripod", c + CV3(cos(t) * 14, 0, sin(t) * 14), c + CV3(0, 34, 0), 0.7, .chassis, category: fc)
            }
            rod("fire.chain", c + CV3(0, 34, 0), c + CV3(0, 18, 0), 0.3, .chassis, segments: 5, category: fc)
            lathe("fire.pot", c + CV3(0, 10, 0), axis: CV3(0, 1, 0), [(0.01, 0), (5, 0.4), (6.4, 3), (6, 7), (5, 7.6)], segments: 18,
                  category: fc) { _ in .chassis }
            add("fire.potHandle", .torus(ring: 5.2, pipe: 0.3), .chassis, at: c + CV3(0, 17, 0), CQuat.yTo(CV3(0, 0, 1)), category: fc)
            for i in 0..<3 {
                let t = Double(i) / 3 * .pi
                rod("fire.log", c + CV3(cos(t) * 8, 1.4, sin(t) * 8), c + CV3(-cos(t) * 8, 1.4, -sin(t) * 8), 1.4, .woodDark, segments: 8, category: fc)
            }
            emberAt = c + CV3(0, 3, 0)
        default:
            let bowl = CamperMeshKit.lathe([CV2(0.01, 0), CV2(6, 0.6), CV2(10, 3), CV2(12, 6), CV2(11.4, 6.2), CV2(9.4, 3.4), CV2(5.6, 1.2), CV2(0.01, 0.8)],
                                           segments: 24, material: { _ in .chassis })
            add("fire.bowl", .mesh(bowl), .chassis, at: c + CV3(0, 7, 0), category: fc)
            for s in [-1.0, 1] {
                rod("fire.leg", c + CV3(s * 10, 0, -6), c + CV3(s * 6, 7, 0), 0.7, .chassis, category: fc)
                rod("fire.leg", c + CV3(s * 10, 0, 6), c + CV3(s * 6, 7, 0), 0.7, .chassis, category: fc)
            }
            for i in 0..<4 {
                let t = Double(i) / 4 * .pi
                rod("fire.log", c + CV3(cos(t) * 8, 9, sin(t) * 8), c + CV3(-cos(t) * 8, 10, -sin(t) * 8), 1.6, .woodDark, segments: 8, category: fc)
            }
        }
        // 燠（薪の下の赤い熱・平たく）と、形のある炎の舌 3 つ（高さ・傾きを変える。夜はゆっくり小さく揺れる）
        add("fire.ember", .sphere(radius: 2.6), .ember, at: emberAt, category: fc, scale: CV3(1, 0.45, 1))
        flameTongue("fire.flame", at: emberAt + CV3(0, 0.6, 0), height: 12, radius: 2.6, category: fc)
        flameTongue("fire.flame", at: emberAt + CV3(1.6, 0.4, 1.0), height: 8.5, radius: 1.9, lean: CV3(0.18, 1, 0.1), category: fc)
        flameTongue("fire.flame", at: emberAt + CV3(-1.4, 0.4, -1.2), height: 7, radius: 1.6, lean: CV3(-0.15, 1, -0.12), category: fc)
        // 2026-10-18（run 530）: 700・90 では白く飛んだ。2026-10-19: 光の溜まりが硬い円に見えた（owner）ので、光は弱く広くし、
        // 足元の明るさは裾のなめらかな溜まり（足す光）で出す。外の火は室内灯より赤い
        only([.night]) {
            $0.out.lights.append(CamperLightSpec(name: "campfire", kind: .omni, position: emberAt + CV3(0, 14, 0), color: 0xFF8A42,
                                                 intensity: 130, range: 42))
            $0.add("glow.fire", .mesh($0.glowQuad(width: 96, depth: 96, material: .firePool)), .firePool,
                   at: CV3(emberAt.x, 0.5, emberAt.z), group: .glow)
        }
    }

    mutating func outdoorLight(z: Double) {
        let oc = CamperCategory.outdoorLight
        switch k(.outdoorLight) {
        case "string_lights":
            let poles = [CV3(-104, 0, z + 44), CV3(24, 0, z + 44)]
            for p in poles { rod("light.stringPole", p, p + CV3(0, 72, 0), 0.8, .woodDark, category: oc) }
            let a = poles[0] + CV3(0, 72, 0), b = poles[1] + CV3(0, 72, 0)
            var prev = a
            for i in 1...9 {
                let t = Double(i) / 9
                let p = a + (b - a) * t + CV3(0, -10 * sin(t * .pi), 0)
                rod("light.stringWire", prev, p, 0.15, .black, segments: 4, category: oc)
                // 球は小さく（夜に筋ではなく点の並びに見えるよう・run 533）
                if i < 9 { add("light.bulb", .sphere(radius: 1.0), .lamp, at: p + CV3(0, -1.6, 0), category: oc) }
                prev = p
            }
            only([.night]) {
                $0.out.lights.append(CamperLightSpec(name: "string", kind: .omni, position: CV3(-40, 60, z + 44), color: 0xFFD27A,
                                                     intensity: 200, range: 70))
            }
        case "paper_lantern":
            let c = CV3(-96, 0, z + 14)
            rod("light.stand", c, c + CV3(0, 46, 0), 0.6, .woodDark, category: oc)
            rod("light.standArm", c + CV3(0, 46, 0), c + CV3(10, 46, 0), 0.4, .woodDark, category: oc)
            add("light.paperLantern", .sphere(radius: 6), .byNight(.tint(0xC23B22)), at: c + CV3(10, 36, 0), category: oc,
                scale: CV3(1, 1.25, 1))
            for y in [43.0, 29] { add("light.paperRim", .cylinder(radius: 3, height: 1.2, segments: 14), .black, at: c + CV3(10, y, 0), category: oc) }
        case "oil_lamp":
            let c = CV3(-54, 19, z + 8)
            lathe("light.oilBase", c, axis: CV3(0, 1, 0), [(3.4, 0), (3.8, 1), (3.2, 3.6), (1.6, 4.6)], segments: 16, capStart: .brass,
                  category: oc) { _ in .brass }
            lathe("light.oilChimney", c + CV3(0, 4.6, 0), axis: CV3(0, 1, 0), [(1.4, 0), (2.6, 2.6), (2.2, 5.4), (1.4, 8)], segments: 16,
                  category: oc) { _ in .glass }
            flameTongue("light.oilFlame", at: c + CV3(0, 5.4, 0), height: 3.2, radius: 0.7, category: oc)
        default:
            let c = CV3(-96, 0, z + 14)
            rod("light.stand", c, c + CV3(0, 44, 0), 0.6, .black, category: oc)
            rod("light.standArm", c + CV3(0, 44, 0), c + CV3(8, 46, 0), 0.4, .black, category: oc)
            for (dx, dz) in [(-6.0, 0.0), (3, 5), (3, -5)] { rod("light.standFoot", c, c + CV3(dx, 0, dz), 0.4, .black, category: oc) }
            let l = c + CV3(8, 33, 0)
            lathe("light.lanternTop", l + CV3(0, 9.6, 0), axis: CV3(0, 1, 0), [(3.8, 0), (3.8, 1.4), (0.01, 1.6)], segments: 12,
                  category: oc) { _ in .brass }
            // 硝子は透明の円筒で、中に小さな炎（硝子一面を光らせない・2026-10-19）
            lathe("light.lanternGlass", l + CV3(0, 2.4, 0), axis: CV3(0, 1, 0), [(3, 0), (3.2, 3.6), (3, 7.2)], segments: 16,
                  category: oc) { _ in .lanternGlass }
            lathe("light.lanternWick", l + CV3(0, 2.4, 0), axis: CV3(0, 1, 0), [(0.9, 0), (0.9, 1.2), (0.01, 1.4)], segments: 10,
                  capStart: .brass, category: oc) { _ in .brass }
            flameTongue("light.lanternFlame", at: l + CV3(0, 3.8, 0), height: 3.8, radius: 0.9, category: oc)
            lathe("light.lanternBase", l, axis: CV3(0, 1, 0), [(3.8, 0), (3.8, 2.4)], segments: 12, capStart: .brass, category: oc) { _ in .brass }
            only([.night]) {
                // ランタンは室内灯より赤み（板 255,190,110 より赤く）。足元は裾のなめらかな溜まり
                $0.out.lights.append(CamperLightSpec(name: "lantern", kind: .omni, position: l + CV3(0, 6, 0), color: 0xFF9A4A,
                                                     intensity: 90, range: 34))
                $0.add("glow.lantern", .mesh($0.glowQuad(width: 64, depth: 64, material: .firePool)), .firePool,
                       at: CV3(c.x + 8, 0.5, c.z), group: .glow)
            }
        }
    }

    // MARK: 室内の飾り

    /// カーテン（扉の側の窓）
    mutating func curtains() {
        let cc = CamperCategory.curtain
        let z = BW - wall - 1
        for w in windowsNear {
            let xs = w.map(\.x), ys = w.map(\.y)
            guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { continue }
            let mid = (x0 + x1) / 2, width = x1 - x0, height = y1 - y0
            switch k(.curtain) {
            case "cafe_short":
                rod("interior.curtainRail", CV3(x0 - 2, y0 + height / 2, z - 0.6), CV3(x1 + 2, y0 + height / 2, z - 0.6), 0.4, .brass, category: cc)
                for i in 0..<Int(width / 3) {
                    rbox("interior.curtain", CV3(x0 + 1.5 + Double(i) * 3, y0 + height / 4, z - 0.4 - Double(i % 2) * 0.6),
                         CV3(3, height / 2, 0.4), 0.1, .canvasLight, category: cc)
                }
            case "roman_blind":
                for i in 0..<4 {
                    rbox("interior.blindFold", CV3(mid, y1 - 2 - Double(i) * 2.6, z - 0.6 - Double(i % 2) * 0.4), CV3(width, 2.8, 1.2), 0.5,
                         .canvas(0x4A5A46), category: cc)
                }
            case "beaded":
                let strands = max(4, Int(width / 2.5))
                let colors: [CamperMaterial] = [.brass, .tint(0xC23B22), .tint(0x2F4F74)]
                for i in 0..<strands {
                    let x = x0 + 1 + Double(i) * (width - 2) / Double(strands - 1)
                    for j in 0..<Int(height / 2.2) {
                        add("interior.bead", .sphere(radius: 0.7), colors[(i + j) % 3], at: CV3(x, y1 - 1 - Double(j) * 2.2, z - 0.6), category: cc)
                    }
                }
                rod("interior.curtainRail", CV3(x0 - 2, y1 + 1, z - 0.6), CV3(x1 + 2, y1 + 1, z - 0.6), 0.4, .brass, category: cc)
            default:
                for xa in [x0 + 1, x1 - 11] {
                    for kk in 0..<5 {
                        rbox("interior.curtain", CV3(xa + Double(kk) * 2 + 1, (y0 + y1) / 2 - 1, z - Double(kk % 2)), CV3(2, height + 2, 0.5),
                             0.2, .curtain, category: cc)
                    }
                }
                rod("interior.curtainRail", CV3(x0 - 2, y1 + 2, z - 0.5), CV3(x1 + 2, y1 + 2, z - 0.5), 0.4, .brass, category: cc)
            }
        }
    }

    /// クッション（長椅子の上・バンは寝台の上）
    mutating func cushions() {
        let cc = CamperCategory.cushion
        let seatY = van ? 60.0 : 62.6
        let spots: [CV3] = van ? [CV3(-86, seatY, -20), CV3(-86, seatY, 0)] : [CV3(-104, seatY, 30), CV3(-104, seatY, -10)]
        let lean = CQuat.axisAngle(CV3(0, 0, 1), -0.3)
        switch k(.cushion) {
        case "bolster_round":
            for s in spots {
                add("interior.cushion", .cylinder(radius: 3.2, height: 16, segments: 16), .canvas(0x4A5A46), at: s + CV3(0, 1.6, 0),
                    CQuat.yTo(CV3(0, 0, 1)), category: cc)
                for dz in [-6.0, 6] {
                    add("interior.cushionBand", .torus(ring: 3.25, pipe: 0.3), .brass, at: s + CV3(0, 1.6, dz), CQuat.yTo(CV3(0, 0, 1)), category: cc)
                }
            }
        case "knitted":
            for s in spots {
                rbox("interior.cushion", s + CV3(0, 5, 0), CV3(4, 10, 10), 1.8, .canvas(0xD9622B), lean, category: cc)
                for dz in [-2.5, 0, 2.5] {
                    rod("interior.cable", s + CV3(2.2, 0.6, dz), s + CV3(-0.6, 9.6, dz), 0.6, .canvas(0xE07A3E), segments: 6, category: cc)
                }
            }
        case "tasseled":
            for s in spots {
                rbox("interior.cushion", s + CV3(0, 5, 0), CV3(4, 10, 10), 1.6, .canvas(0x2F4F74), lean, category: cc)
                for (dy, dz) in [(0.6, -5.4), (0.6, 5.4), (10, -5.4), (10, 5.4)] {
                    lathe("interior.tassel", s + CV3(0.6 - dy * 0.3, dy, dz), axis: CV3(0, -1, 0), [(0.4, 0), (1, 2), (0.01, 2.6)], segments: 8,
                          category: cc) { _ in .brass }
                }
            }
        default:
            for (i, s) in spots.enumerated() {
                rbox("interior.cushion", s + CV3(0, 5, 0), CV3(4, 10, 10), 1.6, .canvas(i == 0 ? 0xE8E0CC : 0xD8CCB4), lean, category: cc)
            }
        }
    }

    /// 吊りランプ（座卓の上）
    mutating func hangingLamp() {
        let lc = CamperCategory.hangingLamp
        // キャンピングカーは扉の口の奥（台所の手前の通路の上）に吊る。開けた扉から見える灯り（2026-10-18 run 530）
        let top = van ? CV3(-89, roofTop - 12, 12) : CV3(28, roofTop - 12, -8)
        switch k(.hangingLamp) {
        case "enamel_cone":
            rod("interior.lampCord", top, top - CV3(0, 14, 0), 0.25, .black, category: lc)
            lathe("interior.lamp", top - CV3(0, 22, 0), axis: CV3(0, 1, 0), [(6, 0), (6.2, 0.6), (1.2, 8)], segments: 18,
                  category: lc) { _ in .tint(0x3E6B4A) }
            add("interior.lampRim", .torus(ring: 6.1, pipe: 0.35), .tint(0xEDEAE2), at: top - CV3(0, 22, 0), category: lc)
            add("interior.lampBulb", .sphere(radius: 1.6), .byNight(.glass), at: top - CV3(0, 20.6, 0), category: lc)
        case "rattan":
            rod("interior.lampCord", top, top - CV3(0, 12, 0), 0.25, .black, category: lc)
            lathe("interior.lamp", top - CV3(0, 22, 0), axis: CV3(0, 1, 0), [(7, 0), (6.6, 4), (4.6, 8), (1, 10)], segments: 20,
                  category: lc) { _ in .wallWood(0xC8A46E) }
            for i in 0..<4 {
                add("interior.lampWeave", .torus(ring: 6.9 - Double(i) * 0.7, pipe: 0.25), .tint(0x8A6D3D),
                    at: top - CV3(0, 21 - Double(i) * 2.4, 0), category: lc)
            }
            only([.night]) { $0.add("interior.lampBulb", .sphere(radius: 2), .lamp, at: top - CV3(0, 19, 0), category: lc) }
        case "glass_globe":
            rod("interior.lampCord", top, top - CV3(0, 12, 0), 0.25, .black, category: lc)
            add("interior.lampCap", .cylinder(radius: 1.4, height: 2, segments: 12), .brass, at: top - CV3(0, 13, 0), category: lc)
            add("interior.lamp", .sphere(radius: 6.4), .byNight(.tint(0xF1EEE6)), at: top - CV3(0, 20, 0), category: lc)
        default:
            rod("interior.lampCord", top, top - CV3(0, 14, 0), 0.3, .black, category: lc)
            lathe("interior.lamp", top - CV3(0, 21, 0), axis: CV3(0, 1, 0), [(0.01, 0), (5.5, 1), (4.5, 5), (0.3, 7)], segments: 14,
                  category: lc) { _ in .byNight(.brass) }
        }
    }

    /// 観葉植物（台所の天板の上。吊るしたつるは天井から）
    mutating func plant() {
        let pc = CamperCategory.plant
        let c = van ? CV3(-24, 52, -30) : CV3(8, 59.2, -40)
        switch k(.plant) {
        case "monstera":
            lathe("interior.pot", c, axis: CV3(0, 1, 0), [(3.4, 0), (4.4, 6)], segments: 14, capStart: .tint(0xEDEAE2), category: pc) { _ in .tint(0xEDEAE2) }
            for i in 0..<6 {
                let t = Double(i) / 6 * 2 * .pi
                let tip = c + CV3(cos(t) * 7, 13 + Double(i % 2) * 3, sin(t) * 5)
                rod("interior.stem", c + CV3(0, 5, 0), tip, 0.3, .tint(0x3E6B30), segments: 5, category: pc)
                add("interior.leaf", .sphere(radius: 3.6), .tint(0x2F6B2E), at: tip, CQuat.yTo(CV3(cos(t), 2, sin(t))), category: pc,
                    scale: CV3(1, 0.2, 1.4))
            }
        case "hanging_ivy":
            let hang = CV3(-60, roofTop - 14, 20)
            rod("interior.ivyCord", hang + CV3(0, 10, 0), hang + CV3(0, 4, 0), 0.25, .canvasLight, category: pc)
            lathe("interior.pot", hang, axis: CV3(0, 1, 0), [(2.6, 0), (3.4, 4)], segments: 14, capStart: .tint(0xA4532E), category: pc) { _ in .tint(0xA4532E) }
            for v in 0..<4 {
                let t = Double(v) / 4 * 2 * .pi
                for j in 0..<7 {
                    add("interior.ivyLeaf", .sphere(radius: 1), .tint(0x3E7B34),
                        at: hang + CV3(cos(t) * (3 + Double(j) * 0.3), 3 - Double(j) * 2.4, sin(t) * (3 + Double(j) * 0.3)), category: pc,
                        scale: CV3(1, 0.5, 1))
                }
            }
        case "bonsai":
            rbox("interior.bonsaiTray", c + CV3(0, 1, 0), CV3(12, 2, 7), 0.5, .tint(0x1B1C1F), category: pc)
            rod("interior.trunk", c + CV3(-2, 2, 0), c + CV3(1, 6, 0), 0.9, .woodDark, category: pc)
            rod("interior.trunk", c + CV3(1, 6, 0), c + CV3(-1, 10, 0), 0.7, .woodDark, category: pc)
            for (dx, dy) in [(-1.0, 11.0), (3, 8), (-4, 9)] {
                add("interior.foliage", .sphere(radius: 2.6), .tint(0x3E6B30), at: c + CV3(dx, dy, 0), category: pc, scale: CV3(1.4, 0.6, 1))
            }
        default:
            lathe("interior.pot", c, axis: CV3(0, 1, 0), [(2.6, 0), (3.4, 4.6)], segments: 14, capStart: .tint(0xA4532E), category: pc) { _ in .tint(0xA4532E) }
            add("interior.cactus", .cylinder(radius: 2, height: 10, segments: 10), .tint(0x4E7A3A), at: c + CV3(0, 9.6, 0), category: pc)
            add("interior.cactusTop", .sphere(radius: 2), .tint(0x4E7A3A), at: c + CV3(0, 14.6, 0), category: pc)
            for s in [-1.0, 1] {
                rod("interior.cactusArm", c + CV3(s * 1.6, 9, 0), c + CV3(s * 4, 9, 0), 1, .tint(0x4E7A3A), category: pc)
                rod("interior.cactusArm", c + CV3(s * 4, 8.6, 0), c + CV3(s * 4, 12 + s, 0), 1, .tint(0x4E7A3A), category: pc)
            }
            add("interior.flower", .sphere(radius: 0.9), .tint(0xE0607A), at: c + CV3(0, 16.4, 0), category: pc)
        }
    }

    /// マグの形（分類の部品）
    mutating func mugShape(_ name: String, at c: CV3) {
        let mc = CamperCategory.mug
        switch k(.mug) {
        case "tin_cup":
            lathe(name, c, axis: CV3(0, 1, 0), [(1.8, 0), (1.8, 3.4), (1.6, 3.4), (1.6, 0.3)], segments: 14, capStart: .alu, category: mc) { _ in .alu }
            rod(name + "Handle", c + CV3(1.8, 2.8, 0), c + CV3(3.4, 2.6, 0), 0.2, .alu, segments: 4, category: mc)
        case "ceramic_glazed":
            lathe(name, c, axis: CV3(0, 1, 0), [(1.4, 0), (2.2, 1), (2.4, 2.4), (2, 4), (1.8, 4), (1.8, 0.4)], segments: 16,
                  capStart: .tint(0x2F6F9A), category: mc) { _ in .tint(0x2F6F9A) }
            add(name + "Handle", .torus(ring: 1.2, pipe: 0.35), .tint(0x2F6F9A), at: c + CV3(2.6, 2.2, 0), CQuat.yTo(CV3(0, 0, 1)), category: mc)
        case "double_wall":
            lathe(name, c, axis: CV3(0, 1, 0), [(2, 0), (2.2, 4.6), (1.9, 4.6), (1.7, 0.6)], segments: 18, capStart: .glass, category: mc) { _ in .glass }
            add(name + "Coffee", .cylinder(radius: 1.6, height: 2.6, segments: 14), .tint(0x3B2412), at: c + CV3(0, 2, 0), category: mc)
        default:
            lathe(name, c, axis: CV3(0, 1, 0), [(1.9, 0), (1.9, 3.6), (1.7, 3.6), (1.6, 0.4)], segments: 14, capStart: .tint(0xF2EFE6),
                  category: mc) { _ in .tint(0xF2EFE6) }
            add(name + "Rim", .torus(ring: 1.8, pipe: 0.18), .tint(0x2F4F74), at: c + CV3(0, 3.6, 0), category: mc)
            add(name + "Handle", .torus(ring: 1.2, pipe: 0.3), .tint(0xF2EFE6), at: c + CV3(2.3, 1.9, 0), CQuat.yTo(CV3(0, 0, 1)), category: mc)
        }
    }

    /// 室内のマグ（座卓の上・バンは保冷箱の上）
    mutating func mug() {
        mugShape("interior.mug", at: van ? CV3(-24, 52.2, -26) : CV3(-84, 61.1, 20))
    }

    /// 本棚（反対側の壁・吊り戸棚の下）
    mutating func bookshelf() {
        guard !van else { return }
        let sc = CamperCategory.bookshelf
        let z = -(BW - wall) + 5, x0 = -62.0
        let colors: [UInt32] = [0x7A2E22, 0x2F4F74, 0xC9A66B, 0x4A5A46, 0xD9D4C7, 0x6E4A2B]
        switch k(.bookshelf) {
        case "wall_rack":
            for y in [100.0, 90] { rbox("interior.shelf", CV3(x0, y, z), CV3(34, 1, 8), 0.3, .woodDark, category: sc) }
            lathe("interior.shelfJar", CV3(x0 - 10, 100.5, z), axis: CV3(0, 1, 0), [(2, 0), (2, 5), (1, 6)], segments: 10, capEnd: .brass,
                  category: sc) { _ in .glass }
            add("interior.shelfClock", .cylinder(radius: 3, height: 1, segments: 18), .brass, at: CV3(x0 + 6, 104, z - 3),
                CQuat.yTo(CV3(0, 0, 1)), category: sc)
            for i in 0..<5 {
                rbox("interior.shelfBook", CV3(x0 - 4 + Double(i) * 2.4, 94, z), CV3(2, 7, 6), 0.2, .tint(colors[i]), category: sc)
            }
        case "crate_stack":
            for (i, p) in [(-10.0, 72.0), (6, 72), (-2, 86)].enumerated() {
                rbox("interior.crate", CV3(x0 + p.0, p.1, z), CV3(14, 13, 10), 0.6, i == 2 ? .woodDark : .wood, category: sc)
                for j in 0..<3 {
                    rbox("interior.crateBook", CV3(x0 + p.0 - 3 + Double(j) * 3, p.1 - 1, z + 2), CV3(2.4, 9, 5), 0.2, .tint(colors[i + j]), category: sc)
                }
            }
        case "map_drawer":
            rbox("interior.drawerCase", CV3(x0, 92, z), CV3(30, 18, 10), 0.8, .woodDark, category: sc)
            for i in 0..<4 {
                rbox("interior.drawerGap", CV3(x0, 85.5 + Double(i) * 4.4, z + 5.05), CV3(28, 0.4, 0.2), 0, .black, category: sc)
                rbox("interior.drawerPull", CV3(x0, 87.6 + Double(i) * 4.4, z + 5.6), CV3(4, 0.8, 0.8), 0.3, .brass, category: sc)
            }
            rbox("interior.map", CV3(x0, 101.2, z), CV3(24, 0.3, 8), 0, .tint(0xE9E2CF), CQuat.axisAngle(CV3(0, 1, 0), 0.08), category: sc)
        default:
            for y in [100.0, 88] { rbox("interior.shelf", CV3(x0, y, z), CV3(34, 1.2, 10), 0.3, .woodDark, category: sc) }
            for i in 0..<17 {
                let shelfY = i < 9 ? 100.6 : 88.6
                let j = i < 9 ? i : i - 9
                let h = 7 + Double(i % 3)
                rbox("interior.shelfBook", CV3(x0 - 15 + Double(j) * 3.4, shelfY + h / 2, z), CV3(2.6, h, 7), 0.2, .tint(colors[i % 6]), category: sc)
            }
        }
    }

    /// 壁の木（内壁の色と、板の継ぎ目の立体の溝）
    var wallMaterial: CamperMaterial {
        switch k(.wallWood) {
        case "plywood_birch": return .wallWood(0xE3D6BA)
        case "dark_walnut": return .wallWood(0x6B4A32)
        case "herringbone": return .wallWood(0xB8875A)
        default: return .wallWood(0xD9B98A)
        }
    }

    mutating func wallSeams() {
        let wc = CamperCategory.wallWood
        let key = k(.wallWood)
        let roomX = (rear + 6, van ? 50.0 : 62.0)
        let yRange = (35.0, roofTop - 6)
        // 幅木（床と壁の境の木の帯。壁の木と同じ木）
        for s in [1.0, -1.0] {
            rbox("interior.skirting", CV3((roomX.0 + roomX.1) / 2, 36, s * (BW - wall - 0.6)), CV3(roomX.1 - roomX.0, 4, 1.2), 0.3,
                 wallMaterial, category: wc)
        }
        guard key != "plywood_birch" else { return }
        for (s, holes) in [(1.0, windowsNear + [doorHole]), (-1.0, windowsFar + [hatch])] {
            let z = s * (BW - wall - 0.15)
            let boxes = holes.map { h -> (Double, Double, Double, Double) in
                (h.map(\.x).min()! - 1, h.map(\.x).max()! + 1, h.map(\.y).min()! - 1, h.map(\.y).max()! + 1)
            }
            func clear(_ x: Double, _ y: Double) -> Bool { !boxes.contains { x > $0.0 && x < $0.1 && y > $0.2 && y < $0.3 } }
            switch key {
            case "dark_walnut":
                var y = yRange.0 + 9
                while y < yRange.1 {
                    var x = roomX.0
                    while x < roomX.1 {
                        let x1 = min(roomX.1, x + 8)
                        if clear((x + x1) / 2, y) {
                            rbox("interior.wallSeam", CV3((x + x1) / 2, y, z), CV3(x1 - x, 0.5, 0.3), 0, .tint(0x2A1A10), category: wc)
                        }
                        x = x1
                    }
                    y += 9
                }
            case "herringbone":
                var y = yRange.0 + 6, row = 0
                while y < yRange.1 {
                    var x = roomX.0 + 4
                    while x < roomX.1 {
                        if clear(x, y) {
                            rbox("interior.wallSeam", CV3(x, y, z), CV3(8, 0.4, 0.3), 0, .tint(0x5A3A22),
                                 CQuat.axisAngle(CV3(0, 0, 1), (row % 2 == 0 ? 1 : -1) * .pi / 4), category: wc)
                        }
                        x += 8
                    }
                    y += 6
                    row += 1
                }
            default:
                // 松の縦張り（縦の継ぎ目と節）
                var x = roomX.0 + 9, i = 0
                while x < roomX.1 {
                    var y = yRange.0 + 1
                    while y < yRange.1 {
                        let y1 = min(yRange.1, y + 6)
                        if clear(x, (y + y1) / 2) {
                            rbox("interior.wallSeam", CV3(x, (y + y1) / 2, z), CV3(0.4, y1 - y, 0.3), 0, .tint(0x7A5A34), category: wc)
                        }
                        y = y1
                    }
                    let ky = yRange.0 + 20 + Double(i * 37 % 60)
                    if clear(x - 4, ky) {
                        add("interior.knot", .cylinder(radius: 0.9, height: 0.2, segments: 8), .tint(0x7A5A34), at: CV3(x - 4, ky, z),
                            CQuat.yTo(CV3(0, 0, -s)), category: wc)
                    }
                    x += 9
                    i += 1
                }
            }
        }
    }

    /// 床（材質と、板・升・矢の立体の継ぎ目）
    var floorMaterial: CamperMaterial {
        switch k(.floor) {
        case "cork": return .tint(0xB08A5A)
        case "checker_tiles": return .tint(0xEDEAE2)
        case "chevron": return .wallWood(0xB8875A)
        default: return .floorIn
        }
    }

    mutating func floorFinish() {
        let fc = CamperCategory.floor
        let zr = BW - wall - 0.5
        let x0 = rear + 5, x1 = van ? 50.0 : 62.0
        switch k(.floor) {
        case "checker_tiles":
            var x = x0, i = 0
            while x + 8 <= x1 {
                var z = -zr, j = 0
                while z + 8 <= zr {
                    if (i + j) % 2 == 0 { rbox("interior.tile", CV3(x + 4, 34.1, z + 4), CV3(8, 0.2, 8), 0, .tint(0x1B1C1F), category: fc) }
                    z += 8
                    j += 1
                }
                x += 8
                i += 1
            }
        case "chevron":
            var x = x0 + 4
            while x < x1 {
                var z = -zr + 3
                while z < zr {
                    for d in [-1.0, 1.0] {
                        rbox("interior.chevron", CV3(x, 34.06, z + d * 1.5), CV3(6, 0.12, 0.3), 0, .tint(0x6E4A2B),
                             CQuat.axisAngle(CV3(0, 1, 0), d * .pi / 4), category: fc)
                    }
                    z += 6
                }
                x += 6
            }
        case "cork":
            var seed: UInt64 = 11
            func rnd() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double((seed >> 33) & 0xFFFF) / 65535
            }
            for _ in 0..<70 {
                add("interior.corkGrain", .cylinder(radius: 0.4 + rnd() * 0.6, height: 0.12, segments: 6), .tint(0x8A6A44),
                    at: CV3(x0 + rnd() * (x1 - x0), 34.06, -zr + rnd() * zr * 2), category: fc)
            }
        default:
            var z = -zr + 7
            while z < zr {
                rbox("interior.boardGap", CV3((x0 + x1) / 2, 34.05, z), CV3(x1 - x0, 0.1, 0.3), 0, .tint(0x4A3220), category: fc)
                z += 7
            }
        }
    }
}
