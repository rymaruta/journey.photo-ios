import Foundation

// 集める部品の形（2026-10-18 owner「部品もっと欲しい」）。どの部品も立体の形で描き分ける（色違いだけにしない）。
// 置き場所は板の単位・上が +Y（`CamperBuilder` と同じ）。

extension CamperBuilder {

    func k(_ c: CamperCategory) -> String { config.loadout.key(c) }

    // MARK: 窓の形

    /// 窓の形（板の座標の四角 x・y・幅・高さ・角の丸み から）。丸窓は横長なら 2 つ並べる
    func windowShapes(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> [[CV2]] {
        let x0 = x, y0 = 62 - y - h
        switch k(.window) {
        case "round":
            let d = min(w, h)
            let count = w > d * 1.7 ? 2 : 1
            return (0..<count).map { i in
                let cx = count == 1 ? x0 + w / 2 : x0 + d / 2 + (w - d) * Double(i)
                return CamperPolygon.circle(CV2(cx, y0 + h / 2), d / 2, count: 24)
            }
        case "arch":
            let a = min(w / 2, h * 0.5)
            var pts = [CV2(x0, y0), CV2(x0 + w, y0), CV2(x0 + w, y0 + h - a)]
            for i in 1..<12 {
                let t = Double(i) / 12 * .pi
                pts.append(CV2(x0 + w / 2 + cos(t) * w / 2, y0 + h - a + sin(t) * a))
            }
            pts.append(CV2(x0, y0 + h - a))
            return [pts]
        case "grid":
            return [CamperPolygon.roundedRect(x: x0, y: y0, w: w, h: h, r: 1)]
        default:
            return [CamperPolygon.roundedRect(x: x0, y: y0, w: w, h: h, r: r)]
        }
    }

    /// 格子の窓の桟（ガラスの手前の十字）
    mutating func windowMullions(_ w: [CV2], z: Double, group: CamperGroup = .body) {
        guard k(.window) == "grid" else { return }
        let xs = w.map(\.x), ys = w.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return }
        let s = z >= 0 ? 1.0 : -1.0
        let depth = z - s * 1.8
        rbox("window.mullion", CV3((x0 + x1) / 2, (y0 + y1) / 2, depth), CV3(x1 - x0, 1, 1), 0.2, .black, group: group,
             category: .window)
        rbox("window.mullion", CV3((x0 + x1) / 2, (y0 + y1) / 2, depth), CV3(1, y1 - y0, 1), 0.2, .black, group: group,
             category: .window)
    }

    // MARK: 取っ手

    /// 取っ手（`s` は外の向き ±Z）
    mutating func handle(_ name: String, at c: CV3, s: Double, group: CamperGroup = .body, small: Bool = false) {
        let hc = CamperCategory.handle
        let w = small ? 5.0 : 6.0
        switch k(.handle) {
        case "lever":
            add(name, .cylinder(radius: 1.2, height: 1.2, segments: 12), .black, at: c + CV3(-w / 2 + 1, 0, s * 0.6),
                CQuat.yTo(CV3(0, 0, s)), group: group, category: hc)
            rbox(name, c + CV3(0, -0.6, s * 1.4), CV3(w, 1.4, 1.2), 0.4, .black,
                 CQuat.axisAngle(CV3(0, 0, 1), -0.25), group: group, category: hc)
        case "ring":
            add(name, .cylinder(radius: 1.8, height: 0.8, segments: 14), .brass, at: c + CV3(0, 1.6, s * 0.4),
                CQuat.yTo(CV3(0, 0, s)), group: group, category: hc)
            add(name, .torus(ring: 2.4, pipe: 0.45), .brass, at: c + CV3(0, -0.8, s * 1.1),
                CQuat.yTo(CV3(0, 0, s)), group: group, category: hc)
        case "wood":
            for dx in [-w / 2, w / 2] {
                add(name, .cylinder(radius: 0.9, height: 1.6, segments: 10), .brass, at: c + CV3(dx, 0, s * 0.8),
                    CQuat.yTo(CV3(0, 0, s)), group: group, category: hc)
            }
            rod(name, c + CV3(-w / 2 - 0.4, 0, s * 1.9), c + CV3(w / 2 + 0.4, 0, s * 1.9), 1.1, .woodDark, group: group, category: hc)
        default:
            rbox(name, c + CV3(0, 0, s * 1.2), CV3(w, 2, 2), 0.8, .chrome, group: group, category: hc)
        }
    }

    // MARK: ミラー

    mutating func mirrors() {
        let mc = CamperCategory.mirror
        let mx = van ? 60.0 : 68.0
        for s in [1.0, -1.0] {
            let base = B(mx, -22, s * BW)
            switch k(.mirror) {
            case "round":
                rod("ext.mirrorArm", base, base + CV3(-2, 4, s * 10), 0.5, .chrome, category: mc)
                add("ext.mirror", .cylinder(radius: 4.6, height: 1.6, segments: 20), .chrome, at: base + CV3(-2, 6, s * 11),
                    CQuat.yTo(CV3(-1, 0, 0)), category: mc)
                add("ext.mirrorGlass", .cylinder(radius: 4, height: 0.3, segments: 20), .glass, at: base + CV3(-2.9, 6, s * 11),
                    CQuat.yTo(CV3(-1, 0, 0)), category: mc)
            case "long":
                rod("ext.mirrorArm", base + CV3(0, 2, 0), base + CV3(0, 2, s * 18), 0.6, .black, category: mc)
                rod("ext.mirrorArm", base + CV3(0, -6, 0), base + CV3(0, -2, s * 18), 0.6, .black, category: mc)
                rbox("ext.mirror", base + CV3(0, 0, s * 19), CV3(3, 16, 6), 1.2, .black, category: mc)
                rbox("ext.mirrorGlass", base + CV3(-1.6, 0, s * 19), CV3(0.4, 14, 4.8), 0.2, .chrome, category: mc)
            case "bullet":
                rod("ext.mirrorArm", base, base + CV3(0, 2, s * 7), 0.6, .chrome, category: mc)
                lathe("ext.mirror", base + CV3(-4, 3, s * 9), axis: CV3(1, 0, 0), [(0.01, 0), (3, 1), (3.6, 4), (3, 7), (0.01, 9)],
                      segments: 16, category: mc) { _ in .chrome }
                add("ext.mirrorGlass", .cylinder(radius: 2.8, height: 0.3, segments: 16), .glass, at: base + CV3(-4.4, 3, s * 9),
                    CQuat.yTo(CV3(-1, 0, 0)), category: mc)
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
        case "mesh":
            for i in 0..<5 { rbox("front.grilleBar", B(FX + 1.9, 11.5 + Double(i) * 2.2, 0), CV3(0.6, 0.5, 48), 0.1, .chromeDark, category: gc) }
            for i in 0..<16 {
                rbox("front.grilleBar", B(FX + 1.9, 16, -22.5 + Double(i) * 3), CV3(0.6, 9.6, 0.5), 0.1, .chromeDark, category: gc)
            }
        case "slats":
            for i in 0..<9 {
                rbox("front.grilleBar", B(FX + 1.9, 16, -20 + Double(i) * 5), CV3(1, 9.4, 1.4), 0.4, .chrome, category: gc)
            }
        case "brass":
            for i in 0..<3 { rbox("front.grilleBar", B(FX + 2, 12.6 + Double(i) * 3.4, 0), CV3(1.4, 1.6, 48), 0.5, .brass, category: gc) }
            for (y, h) in [(10.8, 1.2), (21.2, 1.2)] { rbox("front.grilleFrame", B(FX + 2.2, y, 0), CV3(1.2, h, 52), 0.4, .brass, category: gc) }
            for z in [-25.5, 25.5] { rbox("front.grilleFrame", B(FX + 2.2, 16, z), CV3(1.2, 11.6, 1.2), 0.4, .brass, category: gc) }
        default:
            for i in 0..<4 {
                rbox("front.grilleBar", B(FX + 1.9, 12 + Double(i) * 2.6, 0), CV3(0.9, 0.9, 48), 0.3, .chrome, category: gc)
            }
        }
    }

    mutating func frontBumper(_ FX: Double) {
        let bc = CamperCategory.bumper
        switch k(.bumper) {
        case "steel":
            rbox("front.bumper", B(FX + 3, 32, 0), CV3(6, 7, BW * 2 + 4), 0.6, .steel, category: bc)
            for z in [-30.0, 30] {
                add("front.towRing", .torus(ring: 2.2, pipe: 0.7), .steel, at: B(FX + 6.4, 36, z),
                    CQuat.yTo(CV3(0, 0, 1)), category: bc)
            }
        case "wood":
            rbox("front.bumper", B(FX + 3.5, 32, 0), CV3(7, 8, BW * 2 + 6), 1, .woodDark, category: bc)
            for z in [-34.0, 34] { rbox("front.bumperStrap", B(FX + 3.5, 32, z), CV3(7.4, 8.4, 2), 0.3, .chassis, category: bc) }
        case "tube":
            let a = B(FX + 6, 28, -(BW + 1)), b = B(FX + 6, 28, BW + 1)
            rod("front.bumper", a, b, 1.4, .chrome, category: bc)
            rod("front.bumper", B(FX + 6, 35, -(BW - 6)), B(FX + 6, 35, BW - 6), 1.4, .chrome, category: bc)
            for z in [-40.0, -14, 14, 40] { rod("front.bumperPost", B(FX + 6, 27, z), B(FX + 6, 36, z), 1.1, .chrome, category: bc) }
            for z in [-26.0, 26] { rod("front.bumperMount", B(FX, 31, z), B(FX + 6, 31, z), 1.2, .black, category: bc) }
        default:
            rbox("front.bumper", B(FX + 3, 32, 0), CV3(6, 7, BW * 2 + 4), 2.6, .chrome, category: bc)
        }
    }

    // MARK: はしご

    mutating func ladder(_ BX: Double) {
        let lc = CamperCategory.ladder
        let key = k(.ladder)
        let railMat: CamperMaterial = key == "wood" ? .wood : (key == "flat" ? .black : .chrome)
        for z in [22.0, 40.0] {
            if key == "wood" {
                rbox("rear.ladderRail", CV3(BX - 4, (62 + 70 + 62 - 26) / 2, z), CV3(2.4, 96, 2.4), 0.5, .wood, category: lc)
            } else {
                rod("rear.ladderRail", B(BX - 4, -70, z), B(BX - 4, 26, z), 1, railMat, category: lc)
            }
        }
        for i in 0..<8 {
            let y = -62 + Double(i) * 11
            switch key {
            case "flat":
                rbox("rear.ladderRung", B(BX - 4.5, y, 31), CV3(4, 1, 18), 0.3, .black, category: lc)
            case "wood":
                rod("rear.ladderRung", B(BX - 4, y, 22), B(BX - 4, y, 40), 1, .woodDark, segments: 8, category: lc)
            default:
                rod("rear.ladderRung", B(BX - 4, y, 22), B(BX - 4, y, 40), 0.8, .chrome, segments: 8, category: lc)
            }
        }
        let clampMat: CamperMaterial = key == "wood" ? .brass : (key == "flat" ? .chassis : .chrome)
        for y in [-66.0, 20] {
            for z in [22.0, 40] { rbox("rear.ladderClamp", B(BX - 2, y, z), CV3(4, 1.6, 2), 0.5, clampMat, category: lc) }
        }
        if key == "rail" {
            // 上の真鍮の手すり（逆 U の字）
            let top = B(BX - 4, -70, 22).y
            rod("rear.ladderHoop", CV3(BX - 4, top, 22), CV3(BX + 6, top + 9, 22), 0.8, .brass, category: lc)
            rod("rear.ladderHoop", CV3(BX - 4, top, 40), CV3(BX + 6, top + 9, 40), 0.8, .brass, category: lc)
            rod("rear.ladderHoop", CV3(BX + 6, top + 9, 22), CV3(BX + 6, top + 9, 40), 0.8, .brass, category: lc)
        }
    }

    // MARK: 泥よけ

    mutating func mudFlaps() {
        let mc = CamperCategory.mudflap
        for cx in wheels {
            for s in [-1.0, 1] {
                let c = CV3(cx - 27, 15, s * (BW - 8))
                switch k(.mudflap) {
                case "split":
                    for dz in [-3.6, 3.6] { rbox("under.mudFlap", c + CV3(0, 0, dz), CV3(1, 12, 6), 0.4, .rubber, category: mc) }
                case "diamond":
                    rbox("under.mudFlap", c, CV3(1, 12, 14), 0.3, .alu, category: mc)
                    for row in 0..<3 {
                        for col in 0..<3 {
                            rbox("under.mudFlapStud", c + CV3(-0.7, -3.5 + Double(row) * 3.5, -4 + Double(col) * 4),
                                 CV3(0.5, 1.6, 1.6), 0.1, .alu, CQuat.axisAngle(CV3(1, 0, 0), .pi / 4), category: mc)
                        }
                    }
                case "long":
                    rbox("under.mudFlap", c + CV3(0, -5, 0), CV3(1, 21, 14), 0.4, .rubber, category: mc)
                    rbox("under.mudFlapWeight", c + CV3(0, -14.6, 0), CV3(1.6, 1.4, 14.4), 0.3, .brass, category: mc)
                default:
                    rbox("under.mudFlap", c, CV3(1, 12, 14), 0.4, .rubber, category: mc)
                }
            }
        }
    }

    // MARK: タイヤの溝

    /// (列, 一周の山の数, 山の割合, 溝の深さ)
    var treadSpec: (rows: [(Double, Double)], pitches: Int, land: Double, depth: Double) {
        switch k(.tread) {
        case "rib": return ([(3, 6.4), (7.4, 10.4), (11.6, 14.6), (15.6, 19)], 40, 0.96, 1)
        case "block": return ([(3, 8.2), (8.9, 13.1), (13.8, 19)], 16, 0.6, 1.6)
        case "snow": return ([(3, 8), (8.6, 13.4), (14, 19)], 30, 0.62, 1.1)
        default: return ([(3, 10.2), (11.8, 19)], 22, 0.72, 1)
        }
    }

    // MARK: 後ろの荷台

    mutating func rearCarrier() {
        let key = k(.rear)
        guard key != CamperLoadout.none, stage != .trailer else { return }
        let rc = CamperCategory.rear
        let BX = rear
        // 腕 2 と台（後ろのバンパーの下から）
        for z in [-30.0, 30] { rbox("rear.carrierArm", CV3(BX - 15, 22, z), CV3(30, 2.4, 3), 0.5, .chassis, category: rc) }
        rbox("rear.carrierDeck", CV3(BX - 27, 23.6, 0), CV3(10, 1.2, 76), 0.4, .chassis, category: rc)
        switch key {
        case "box":
            rbox("rear.carrierBox", CV3(BX - 27, 34, 0), CV3(14, 19, 66), 1.2, .wood, category: rc)
            rbox("rear.carrierBoxLid", CV3(BX - 27, 44, 0), CV3(15, 1.6, 67), 0.6, .woodDark, category: rc)
            for z in [-24.0, 24] { rbox("rear.carrierBoxStrap", CV3(BX - 27, 34, z), CV3(14.4, 19.4, 2), 0.3, .black, category: rc) }
        case "firewood":
            for z in [-34.0, 34] {
                rod("rear.firewoodFrame", CV3(BX - 21, 24, z), CV3(BX - 21, 50, z), 0.7, .chassis, category: rc)
                rod("rear.firewoodFrame", CV3(BX - 33, 24, z), CV3(BX - 33, 50, z), 0.7, .chassis, category: rc)
            }
            for row in 0..<3 {
                for i in 0..<3 {
                    let y = 28 + Double(row) * 7, x = BX - 23 - Double(i) * 4.2 - Double(row % 2) * 2
                    rod("rear.log", CV3(x, y, -32), CV3(x, y, 32), 3, row % 2 == 0 ? .wood : .woodDark, segments: 9, category: rc)
                }
            }
        default:
            bicycle(x: BX - 26, color: 0xA4372B)
            if key == "bikes" { bicycle(x: BX - 33, color: 0x26385A) }
        }
    }

    /// 自転車（車の幅の向きに立てる。輪・スポーク・枠・サドル・ハンドル）
    mutating func bicycle(x: Double, color: UInt32) {
        let rc = CamperCategory.rear
        let r = 10.0, y = 24.2 + r
        let zs = [-17.0, 17.0]
        for z in zs {
            add("rear.bikeTyre", .torus(ring: r, pipe: 0.9), .rubber, at: CV3(x, y, z), CQuat.yTo(CV3(1, 0, 0)), category: rc)
            add("rear.bikeHub", .cylinder(radius: 1, height: 2.4, segments: 10), .chrome, at: CV3(x, y, z), CQuat.yTo(CV3(1, 0, 0)), category: rc)
            for i in 0..<8 {
                let t = Double(i) / 8 * .pi
                rod("rear.bikeSpoke", CV3(x, y + cos(t) * r * 0.92, z + sin(t) * r * 0.92), CV3(x, y - cos(t) * r * 0.92, z - sin(t) * r * 0.92),
                    0.12, .chrome, segments: 4, category: rc)
            }
        }
        let frame = CamperMaterial.tint(color)
        let seat = CV3(x, y + 13, -7), bar = CV3(x, y + 15, 12), crank = CV3(x, y, -2)
        rod("rear.bikeFrame", CV3(x, y, -17), crank, 0.8, frame, category: rc)
        rod("rear.bikeFrame", crank, seat - CV3(0, 2, 0), 0.8, frame, category: rc)
        rod("rear.bikeFrame", seat - CV3(0, 2, 0), CV3(x, y + 13, 10), 0.8, frame, category: rc)
        rod("rear.bikeFrame", crank, CV3(x, y + 13, 10), 0.8, frame, category: rc)
        rod("rear.bikeFrame", CV3(x, y + 13, 10), CV3(x, y, 17), 0.7, frame, category: rc)
        rod("rear.bikeFrame", CV3(x, y, -17), seat - CV3(0, 2, 0), 0.6, frame, category: rc)
        rbox("rear.bikeSeat", seat, CV3(3, 1.4, 6), 0.6, .black, category: rc)
        rod("rear.bikeStem", CV3(x, y + 13, 10), bar, 0.6, .chrome, category: rc)
        rod("rear.bikeBar", bar + CV3(-6, 0, 0), bar + CV3(6, 0, 0), 0.5, .chrome, category: rc)
        add("rear.bikeCrank", .cylinder(radius: 2.4, height: 0.6, segments: 14), .chrome, at: crank, CQuat.yTo(CV3(1, 0, 0)), category: rc)
    }

    // MARK: 屋根の積み荷（追加の形）

    mutating func cargoExtra(_ key: String, base y: Double, x cx: Double) -> Bool {
        let rc = CamperCategory.roof
        switch key {
        case "basket":
            for z in [-34.0, 34] { rbox("cargo.basketRail", CV3(cx, y + 6, z), CV3(70, 1.6, 1.6), 0.4, .black, category: rc) }
            for x in [cx - 35, cx + 35] { rbox("cargo.basketRail", CV3(x, y + 6, 0), CV3(1.6, 1.6, 70), 0.4, .black, category: rc) }
            for i in 0..<7 {
                let x = cx - 33 + Double(i) * 11
                for z in [-34.0, 34] { rod("cargo.basketPost", CV3(x, y + 0.6, z), CV3(x, y + 6, z), 0.5, .black, segments: 6, category: rc) }
            }
            for i in 0..<5 { rbox("cargo.basketSlat", CV3(cx, y + 0.8, -28 + Double(i) * 14), CV3(70, 0.8, 1.4), 0.2, .black, category: rc) }
            lathe("cargo.bag", CV3(cx - 18, y + 8, -14), axis: CV3(0, 0, 1), [(0.01, 0), (6, 1.5), (7, 6), (7, 28), (6, 32.5), (0.01, 34)],
                  segments: 16, category: rc) { _ in .fabric }
            lathe("cargo.bag", CV3(cx + 14, y + 7, -18), axis: CV3(0, 0, 1), [(0.01, 0), (5, 1.4), (6, 5), (6, 26), (5, 29.6), (0.01, 31)],
                  segments: 16, category: rc) { _ in .tint(0x7A2E22) }
            for x in [cx - 18, cx + 14] { add("cargo.bagStrap", .torus(ring: 7.2, pipe: 0.4), .black, at: CV3(x, y + 7.5, 2), CQuat.yTo(CV3(0, 0, 1)), category: rc) }
        case "surf":
            for (i, col) in [(0, UInt32(0xE9E2CF)), (1, UInt32(0x6E9FB8))] {
                let board = CamperMeshKit.lathe([CV2(0.01, 0), CV2(4, 6), CV2(7.5, 20), CV2(8.2, 40), CV2(7, 62), CV2(3.4, 80), CV2(0.01, 88)],
                                                segments: 20, material: { _ in .tint(col) })
                add("cargo.surfboard", .mesh(board), .tint(col), at: CV3(cx - 44, y + 1.6 + Double(i) * 2.2, -16 + Double(i) * 30),
                    CQuat.yTo(CV3(1, 0, 0)), category: rc, scale: CV3(1, 0.14, 1))
                rbox("cargo.surfFin", CV3(cx - 38, y + 0.2 + Double(i) * 2.2, -16 + Double(i) * 30), CV3(5, 3, 0.6), 0.2, .tint(0x1B1C1F), category: rc)
            }
            for x in [cx - 14, cx + 18] { rbox("cargo.strap", CV3(x, y + 3.4, 0), CV3(2, 5.6, 66), 0.4, .black, category: rc) }
        case "kayak":
            let hull = CamperMeshKit.lathe([CV2(0.01, 0), CV2(4, 10), CV2(8, 30), CV2(9, 50), CV2(8, 72), CV2(4, 92), CV2(0.01, 104)],
                                           segments: 20, material: { _ in .tint(0xE0B23A) })
            add("cargo.kayak", .mesh(hull), .tint(0xE0B23A), at: CV3(cx - 52, y + 5, 0), CQuat.yTo(CV3(1, 0, 0)), category: rc,
                scale: CV3(1, 0.62, 1))
            add("cargo.kayakCockpit", .torus(ring: 6, pipe: 0.8), .black, at: CV3(cx + 2, y + 1.2, 0), category: rc)
            for x in [cx - 18, cx + 20] {
                add("cargo.strap", .torus(ring: 8.6, pipe: 0.5), .black, at: CV3(x, y + 5, 0), CQuat.yTo(CV3(1, 0, 0)), category: rc,
                    scale: CV3(1, 1, 0.65))
            }
        case "tent":
            // 開いた三角のテント（床の箱・布の屋根 2 枚・三角の妻 2 枚）と、降りるはしご
            rbox("cargo.tentBase", CV3(cx, y + 3, 0), CV3(76, 6, 88), 1.6, .tint(0x2E3236), category: rc)
            let ridge = 30.0, half = 42.0, len = 72.0
            let slope = atan2(ridge, half)
            let side = (ridge * ridge + half * half).squareRoot()
            for s in [-1.0, 1] {
                rbox("cargo.tentRoof", CV3(cx, y + 6 + ridge / 2, s * half / 2), CV3(len, 0.6, side), 0.2, .canvas(0x6E7B5A),
                     CQuat.axisAngle(CV3(1, 0, 0), s * slope), category: rc)
            }
            let tri = [CV2(-half, 0), CV2(half, 0), CV2(0, ridge)]
            for s in [-1.0, 1] {
                let end = CamperMeshKit.extrude(tri, depth: 0.5, front: .canvas(0x8A9A6A), side: .canvas(0x8A9A6A))
                let q = CQuat.rotation(from: CV3(0, 0, 1), to: CV3(s, 0, 0))
                add("cargo.tentEnd", .mesh(end), .canvas(0x8A9A6A), at: CV3(cx + s * len / 2, y + 6, 0), q, category: rc)
            }
            rod("cargo.tentLadder", CV3(cx - 20, y + 4, -(BW + 2)), CV3(cx - 20, 2, -(BW + 22)), 0.8, .alu, category: rc)
            rod("cargo.tentLadder", CV3(cx - 4, y + 4, -(BW + 2)), CV3(cx - 4, 2, -(BW + 22)), 0.8, .alu, category: rc)
            for i in 1..<7 {
                let t = Double(i) / 7
                let yy = (y + 4) + (2 - (y + 4)) * t, zz = -(BW + 2) - 20 * t
                rod("cargo.tentRung", CV3(cx - 20, yy, zz), CV3(cx - 4, yy, zz), 0.6, .alu, segments: 6, category: rc)
            }
        default:
            return false
        }
        return true
    }

    // MARK: ソーラー・アンテナ・旗

    mutating func solarPanels() {
        guard !snow, !van else { return }
        let RT = roofTop
        let sc = CamperCategory.solar
        func panel(_ c: CV3, _ w: Double, _ d: Double, _ q: CQuat = .identity) {
            rbox("roof.solarFrame", c, CV3(w, 2.4, d), 1, .solarFrame, q, category: sc)
            rbox("roof.solar", c + q.rotate(CV3(0, 1.3, 0)), CV3(w - 3, 0.4, d - 3), 0.1, .solar, q, category: sc)
        }
        switch k(.solar) {
        case "double":
            panel(CV3(-92, RT + 1.2, 0), 28, 70)
            panel(CV3(-58, RT + 1.2, 0), 28, 70)
        case "wind":
            panel(CV3(-74, RT + 1.2, 0), 62, 70)
            rod("roof.windMast", CV3(-114, RT, -38), CV3(-114, RT + 38, -38), 1, .alu, category: sc)
            add("roof.windHub", .sphere(radius: 2.2), .alu, at: CV3(-114, RT + 39, -38), category: sc)
            rbox("roof.windTail", CV3(-121, RT + 39, -38), CV3(10, 5, 0.5), 0.2, .alu, category: sc)
            for i in 0..<3 {
                let t = Double(i) / 3 * 2 * .pi
                rbox("roof.windBlade", CV3(-111.5, RT + 39 + cos(t) * 8, -38 + sin(t) * 8), CV3(0.6, 14, 2.6), 0.2, .tint(0xEDEAE2),
                     CQuat.axisAngle(CV3(1, 0, 0), -t), category: sc)
            }
        case "full":
            panel(CV3(-74, RT + 1.2, 0), 62, 86)
            // 傾けた 2 枚目（脚 4 で立てる）
            let q = CQuat.axisAngle(CV3(0, 0, 1), 0.3)
            panel(CV3(-74, RT + 12, 0), 50, 60, q)
            for (dx, h) in [(-22.0, 4.0), (22, 18)] {
                for z in [-26.0, 26] { rod("roof.solarLeg", CV3(-74 + dx, RT + 2.4, z), CV3(-74 + dx, RT + 2.4 + h, z), 0.6, .alu, category: sc) }
            }
        default:
            panel(CV3(-74, RT + 1.2, 0), 62, 70)
        }
    }

    mutating func antenna() {
        let key = k(.antenna)
        guard key != CamperLoadout.none else { return }
        let ac = CamperCategory.antenna
        let RT = roofTop
        let base = CV3(van ? 40 : 58, RT, -38)
        switch key {
        case "spring":
            add("roof.antennaBase", .cylinder(radius: 1.6, height: 1.6, segments: 10), .black, at: base + CV3(0, 0.8, 0), category: ac)
            for i in 0..<6 { add("roof.antennaSpring", .torus(ring: 1.1, pipe: 0.3), .chrome, at: base + CV3(0, 2 + Double(i) * 0.8, 0), category: ac) }
            rod("roof.antenna", base + CV3(0, 6.4, 0), base + CV3(-2, 52, 0), 0.25, .chrome, segments: 6, category: ac)
        case "dish":
            rod("roof.antennaMast", base, base + CV3(0, 8, 0), 0.8, .alu, category: ac)
            let dish = CamperMeshKit.lathe([CV2(0.01, 0), CV2(4, 0.6), CV2(7.5, 2.2), CV2(9, 3.6), CV2(8.6, 3.8), CV2(7.1, 2.6), CV2(3.8, 1), CV2(0.01, 0.4)],
                                           segments: 24, material: { _ in .tint(0xE7E3DA) })
            add("roof.antennaDish", .mesh(dish), .tint(0xE7E3DA), at: base + CV3(0, 10, 0),
                CQuat.yTo(CV3(0.5, 0.6, 0.6)), category: ac)
            rod("roof.antennaFeed", base + CV3(0, 10, 0), base + CV3(3, 15, 3), 0.3, .black, segments: 6, category: ac)
        case "fin":
            let fin = [CV2(0, 0), CV2(22, 0), CV2(8, 9), CV2(2, 7)]
            let mesh = CamperMeshKit.extrude(fin, depth: 4, front: .roofBox, side: .roofBox, bevel: 1)
            add("roof.antennaFin", .mesh(mesh), .roofBox, at: CV3(van ? 30 : 50, RT, 2), category: ac)
        default:
            add("roof.antennaBase", .cylinder(radius: 1.4, height: 2, segments: 10), .black, at: base + CV3(0, 1, 0), category: ac)
            rod("roof.antenna", base + CV3(0, 2, 0), base + CV3(-4, 62, 0), 0.25, .chrome, segments: 6, category: ac)
        }
    }

    mutating func flag() {
        let key = k(.flag)
        guard key != CamperLoadout.none else { return }
        let fc = CamperCategory.flag
        let RT = roofTop
        let pole = CV3(rear + 8, RT, -40)
        let top = pole + CV3(0, 44, 0)
        switch key {
        case "bunting":
            guard !van else { fallthrough }
            // オーニングの箱に沿った小旗の列
            let y = 62 + 64.0, z = BW + 8
            rod("flag.string", CV3(-114, y, z), CV3(30, y, z), 0.2, .canvasLight, segments: 4, category: fc)
            let colors: [UInt32] = [0xC9A66B, 0x2F4F74, 0xA4372B, 0x4A5A46]
            for i in 0..<14 {
                let x = -110 + Double(i) * 10.4
                let tri = CamperMeshKit.extrude([CV2(-3.6, 0), CV2(3.6, 0), CV2(0, -7)], depth: 0.3, front: .canvas(colors[i % 4]),
                                                side: .canvas(colors[i % 4]))
                add("flag.bunting", .mesh(tri), .canvas(colors[i % 4]), at: CV3(x, y, z), category: fc)
            }
        case "flag":
            rod("flag.pole", pole, top, 0.6, .alu, category: fc)
            rbox("flag.cloth", top + CV3(9, -6, 0), CV3(18, 12, 0.3), 0.1, .canvas(0x2F4F74), category: fc)
            rbox("flag.stripe", top + CV3(9, -6, 0), CV3(18, 2.4, 0.5), 0.1, .canvasLight, category: fc)
        case "windsock":
            rod("flag.pole", pole, top, 0.6, .alu, category: fc)
            let sock = CamperMeshKit.lathe([CV2(4, 0), CV2(3.4, 6), CV2(2.8, 12), CV2(2.2, 18), CV2(1.6, 24)], segments: 16,
                                           material: { $0 % 2 == 0 ? .canvas(0xD9622B) : .canvasLight })
            add("flag.windsock", .mesh(sock), .canvas(0xD9622B), at: top + CV3(1, -2, 0), CQuat.yTo(CV3(1, -0.15, 0.2)), category: fc)
            add("flag.windsockRing", .torus(ring: 4, pipe: 0.3), .alu, at: top + CV3(1, -2, 0), CQuat.yTo(CV3(1, -0.15, 0.2)), category: fc)
        default:
            rod("flag.pole", pole, top, 0.6, .alu, category: fc)
            let tri = CamperMeshKit.extrude([CV2(0, 0), CV2(0, 10), CV2(20, 5)], depth: 0.3, front: .canvas(0xA4372B), side: .canvas(0xA4372B))
            add("flag.pennant", .mesh(tri), .canvas(0xA4372B), at: top + CV3(0, -11, 0), category: fc)
        }
        add("flag.finial", .sphere(radius: 1), .brass, at: top + CV3(0, 0.8, 0), category: fc)
    }

    // MARK: 外の置き物（扉の側の地面）

    mutating func campsite() {
        let z0 = BW + 34.0
        rug(at: CV3(-40, 0, z0 + 6))
        chairs(z: z0)
        table(at: CV3(-42, 0, z0 + 8))
        outdoorLight(z: z0)
    }

    mutating func rug(at c: CV3) {
        let key = k(.rug)
        guard key != CamperLoadout.none else { return }
        let rc = CamperCategory.rug
        switch key {
        case "round":
            let colors: [UInt32] = [0x8A6D3D, 0xD8CCB4, 0x7A2E22, 0xD8CCB4]
            for (i, col) in colors.enumerated() {
                add("rug.ring", .cylinder(radius: 26 - Double(i) * 6, height: 0.5 + Double(i) * 0.12, segments: 40), .canvas(col),
                    at: c + CV3(0, 0.26 + Double(i) * 0.06, 0), category: rc)
            }
        case "deck":
            for i in 0..<9 {
                rbox("rug.board", c + CV3(-32 + Double(i) * 8, 0.9, 0), CV3(7.2, 1.8, 46), 0.4, .wood, category: rc)
            }
            for z in [-18.0, 18] { rbox("rug.joist", c + CV3(0, 0.3, z), CV3(72, 0.6, 3), 0.2, .woodDark, category: rc) }
        case "fringe":
            rbox("rug.mat", c + CV3(0, 0.3, 0), CV3(60, 0.6, 36), 0.2, .canvas(0x7A3A2A), category: rc)
            rbox("rug.border", c + CV3(0, 0.45, 0), CV3(52, 0.5, 28), 0.2, .canvas(0xD8CCB4), category: rc)
            for i in 0..<12 {
                for s in [-1.0, 1] {
                    rod("rug.tassel", c + CV3(s * 30, 0.3, -16.5 + Double(i) * 3), c + CV3(s * 35, 0.2, -16.5 + Double(i) * 3), 0.35,
                        .canvasLight, segments: 5, category: rc)
                }
            }
        default:
            for i in 0..<6 {
                rbox("rug.stripe", c + CV3(-25 + Double(i) * 10, 0.3, 0), CV3(10, 0.6, 36), 0.1,
                     .canvas(i % 2 == 0 ? 0x2F4F74 : 0xE8E0CC), category: rc)
            }
        }
    }

    mutating func chairs(z: Double) {
        let key = k(.chair)
        guard key != CamperLoadout.none else { return }
        let cc = CamperCategory.chair
        switch key {
        case "stool":
            for (x, dz) in [(-14.0, -2.0), (-64.0, 6.0), (-40.0, 30.0)] {
                add("chair.stool", .cylinder(radius: 5, height: 11, segments: 16), .wood, at: CV3(x, 5.5, z + dz), category: cc)
                add("chair.stoolTop", .cylinder(radius: 4.6, height: 0.4, segments: 16), .tint(0xC8A46E), at: CV3(x, 11.1, z + dz), category: cc)
            }
        case "deck":
            for (x, yaw) in [(-12.0, -0.5), (-70.0, 0.5)] {
                let q = CQuat.axisAngle(CV3(0, 1, 0), yaw)
                let o = CV3(x, 0, z)
                for s in [-1.0, 1] {
                    rod("chair.deckFrame", o + q.rotate(CV3(s * 9, 0.5, -14)), o + q.rotate(CV3(s * 9, 26, 6)), 0.8, .wood, category: cc)
                    rod("chair.deckFrame", o + q.rotate(CV3(s * 9, 0.5, 8)), o + q.rotate(CV3(s * 9, 11, -6)), 0.8, .wood, category: cc)
                }
                rbox("chair.deckCloth", o + q.rotate(CV3(0, 13, -3)), CV3(17, 0.4, 30), 0.1, .canvas(0xA4372B),
                     q * CQuat.axisAngle(CV3(1, 0, 0), -0.95), category: cc)
            }
        case "hammock":
            let c = CV3(-40, 0, z + 18)
            for s in [-1.0, 1] {
                // 弧の台（棒を 6 本つないだ弧）
                var prev = c + CV3(s * 46, 1, 0)
                for i in 1...6 {
                    let t = Double(i) / 6
                    let p = c + CV3(s * (46 - 8 * t), 1 + 34 * sin(t * .pi / 2), 0)
                    rod("chair.hammockStand", prev, p, 1, .woodDark, category: cc)
                    prev = p
                }
                rod("chair.hammockRope", prev, c + CV3(s * 26, 22, 0), 0.25, .canvasLight, segments: 4, category: cc)
            }
            rod("chair.hammockBase", c + CV3(-46, 1, 0), c + CV3(46, 1, 0), 1.2, .woodDark, category: cc)
            // たるんだ網（6 枚の板を弧に）
            for i in 0..<6 {
                let x0 = -26 + Double(i) * 52 / 6, x1 = x0 + 52 / 6
                let y0 = 22 - 8 * sin((x0 + 26) / 52 * .pi), y1 = 22 - 8 * sin((x1 + 26) / 52 * .pi)
                let a = c + CV3(x0, y0, 0), b = c + CV3(x1, y1, 0)
                rbox("chair.hammockNet", (a + b) * 0.5, CV3((b - a).length, 0.5, 16), 0.2, .canvas(0xE8E0CC),
                     CQuat.axisAngle(CV3(0, 0, 1), atan2(y1 - y0, x1 - x0)), category: cc)
            }
        default:
            for (x, yaw) in [(-14.0, -0.6), (-68.0, 0.6)] {
                let q = CQuat.axisAngle(CV3(0, 1, 0), yaw)
                let o = CV3(x, 0, z)
                for s in [-1.0, 1] {
                    rod("chair.leg", o + q.rotate(CV3(s * 7, 0, -6)), o + q.rotate(CV3(s * 7, 14, 6)), 0.5, .black, category: cc)
                    rod("chair.leg", o + q.rotate(CV3(s * 7, 0, 6)), o + q.rotate(CV3(s * 7, 14, -6)), 0.5, .black, category: cc)
                    rod("chair.arm", o + q.rotate(CV3(s * 7.4, 18, -7)), o + q.rotate(CV3(s * 7.4, 18, 7)), 0.6, .woodDark, category: cc)
                }
                rbox("chair.seat", o + q.rotate(CV3(0, 13, 0)), CV3(14, 0.5, 12), 0.1, .canvas(0x4A5A46), q, category: cc)
                rbox("chair.back", o + q.rotate(CV3(0, 22, -6.5)), CV3(14, 12, 0.5), 0.1, .canvas(0x4A5A46),
                     q * CQuat.axisAngle(CV3(1, 0, 0), 0.15), category: cc)
            }
        }
    }

    mutating func table(at c: CV3) {
        let key = k(.table)
        guard key != CamperLoadout.none else { return }
        let tc = CamperCategory.table
        switch key {
        case "firepit":
            for i in 0..<3 {
                let t = Double(i) / 3 * 2 * .pi
                rod("table.firepitLeg", c + CV3(cos(t) * 9, 0, sin(t) * 9), c + CV3(cos(t) * 6, 7, sin(t) * 6), 0.6, .chassis, category: tc)
            }
            let bowl = CamperMeshKit.lathe([CV2(0.01, 0), CV2(6, 0.6), CV2(10, 3), CV2(12, 6), CV2(11.4, 6.2), CV2(9.4, 3.4), CV2(5.6, 1.2), CV2(0.01, 0.8)],
                                           segments: 24, material: { _ in .chassis })
            add("table.firepit", .mesh(bowl), .chassis, at: c + CV3(0, 7, 0), category: tc)
            for i in 0..<4 {
                let t = Double(i) / 4 * .pi
                rod("table.log", c + CV3(cos(t) * 8, 9, sin(t) * 8), c + CV3(-cos(t) * 8, 10, -sin(t) * 8), 1.6, .woodDark, segments: 8, category: tc)
            }
            add("table.ember", .sphere(radius: 3.6), .ember, at: c + CV3(0, 9.6, 0), category: tc)
            if night {
                out.lights.append(CamperLightSpec(name: "campfire", kind: .omni, position: c + CV3(0, 16, 0), color: 0xFF8A3C,
                                                  intensity: 700, range: 90))
            }
        case "log":
            add("table.logTop", .cylinder(radius: 9, height: 40, segments: 18), .wood, at: c + CV3(0, 15, 0), CQuat.yTo(CV3(1, 0, 0)),
                category: tc, scale: CV3(1, 1, 0.55))
            for dx in [-14.0, 14] { add("table.logLeg", .cylinder(radius: 4, height: 12, segments: 12), .woodDark, at: c + CV3(dx, 6, 0), category: tc) }
        case "stove":
            rbox("table.stove", c + CV3(0, 12, 0), CV3(16, 12, 14), 1, .chassis, category: tc)
            rbox("table.stoveDoor", c + CV3(0, 12, 7.2), CV3(8, 7, 0.6), 0.3, .ember, category: tc)
            for dx in [-6.0, 6] { for dz in [-5.0, 5] { rod("table.stoveLeg", c + CV3(dx, 0, dz), c + CV3(dx, 6, dz), 0.6, .chassis, category: tc) } }
            rod("table.chimney", c + CV3(4, 18, -3), c + CV3(4, 48, -3), 1.6, .chassis, category: tc)
            add("table.chimneyCap", .cylinder(radius: 3, height: 0.6, segments: 12), .chassis, at: c + CV3(4, 49, -3), category: tc)
            if night {
                out.lights.append(CamperLightSpec(name: "stove", kind: .omni, position: c + CV3(0, 12, 12), color: 0xFF8A3C,
                                                  intensity: 400, range: 60))
            }
        default:
            rbox("table.top", c + CV3(0, 18, 0), CV3(28, 1.4, 18), 0.4, .wood, category: tc)
            for s in [-1.0, 1] {
                rod("table.leg", c + CV3(s * 12, 0, -7), c + CV3(s * 12, 17.4, 7), 0.5, .alu, category: tc)
                rod("table.leg", c + CV3(s * 12, 0, 7), c + CV3(s * 12, 17.4, -7), 0.5, .alu, category: tc)
            }
            lathe("table.mug", c + CV3(6, 18.7, 3), axis: CV3(0, 1, 0), [(1.6, 0), (1.7, 3.6), (1.5, 3.6), (1.4, 0.4)], segments: 12,
                  capStart: .tint(0xE8E0CC), category: tc) { _ in .tint(0xE8E0CC) }
        }
    }

    mutating func outdoorLight(z: Double) {
        let key = k(.outLight)
        guard key != CamperLoadout.none else { return }
        let oc = CamperCategory.outLight
        switch key {
        case "string":
            let poles = [CV3(-104, 0, z + 34), CV3(24, 0, z + 34)]
            for p in poles { rod("light.stringPole", p, p + CV3(0, 72, 0), 0.8, .woodDark, category: oc) }
            let a = poles[0] + CV3(0, 72, 0), b = poles[1] + CV3(0, 72, 0)
            var prev = a
            for i in 1...14 {
                let t = Double(i) / 14
                let p = a + (b - a) * t + CV3(0, -10 * sin(t * .pi), 0)
                rod("light.stringWire", prev, p, 0.15, .black, segments: 4, category: oc)
                add("light.bulb", .sphere(radius: 1.3), .lamp, at: p + CV3(0, -1.8, 0), category: oc)
                prev = p
            }
            if night {
                out.lights.append(CamperLightSpec(name: "string", kind: .omni, position: CV3(-40, 60, z + 34), color: 0xFFD27A,
                                                  intensity: 500, range: 110))
            }
        case "torch":
            for x in [-100.0, 18] {
                rod("light.torch", CV3(x, 0, z + 20), CV3(x, 52, z + 20), 1.2, .tint(0xB89A5A), category: oc)
                for i in 1..<4 { add("light.torchNode", .torus(ring: 1.25, pipe: 0.3), .tint(0x8A6D3D), at: CV3(x, Double(i) * 13, z + 20), category: oc) }
                lathe("light.torchCup", CV3(x, 52, z + 20), axis: CV3(0, 1, 0), [(1.4, 0), (2.6, 3), (2.6, 4)], segments: 12, category: oc) { _ in .chassis }
                lathe("light.flame", CV3(x, 55.6, z + 20), axis: CV3(0, 1, 0), [(2.2, 0), (1.4, 3), (0.01, 6)], segments: 12, category: oc) { _ in .ember }
            }
            if night {
                out.lights.append(CamperLightSpec(name: "torch", kind: .omni, position: CV3(-40, 58, z + 20), color: 0xFF9A4A,
                                                  intensity: 500, range: 100))
            }
        case "toro":
            let c = CV3(-96, 0, z + 18)
            lathe("light.toroBase", c, axis: CV3(0, 1, 0), [(7, 0), (7, 3), (4, 4), (2.6, 4.4)], segments: 6, faceted: true,
                  capStart: .stone, category: oc) { _ in .stone }
            add("light.toroPost", .cylinder(radius: 2.4, height: 14, segments: 10), .stone, at: c + CV3(0, 11, 0), category: oc)
            rbox("light.toroFire", c + CV3(0, 22, 0), CV3(8, 6, 8), 0.4, .stone, category: oc)
            rbox("light.toroWindow", c + CV3(0, 22, 0), CV3(8.4, 3.2, 3.2), 0.2, .lamp, category: oc)
            lathe("light.toroRoof", c + CV3(0, 25, 0), axis: CV3(0, 1, 0), [(8.6, 0), (7.6, 2), (2, 4.6), (1, 6), (0.01, 7)], segments: 6,
                  faceted: true, capStart: .stone, category: oc) { _ in .stone }
            if night {
                out.lights.append(CamperLightSpec(name: "toro", kind: .omni, position: c + CV3(0, 22, 0), color: 0xFFC27A,
                                                  intensity: 260, range: 50))
            }
        default:
            let c = CV3(-90, 0, z + 14)
            rod("light.stand", c, c + CV3(0, 44, 0), 0.6, .black, category: oc)
            rod("light.standArm", c + CV3(0, 44, 0), c + CV3(8, 46, 0), 0.4, .black, category: oc)
            for (dx, dz) in [(-6.0, 0.0), (3, 5), (3, -5)] { rod("light.standFoot", c, c + CV3(dx, 0, dz), 0.4, .black, category: oc) }
            let l = c + CV3(8, 33, 0)
            lathe("light.lanternTop", l + CV3(0, 9.6, 0), axis: CV3(0, 1, 0), [(3.8, 0), (3.8, 1.4), (0.01, 1.6)], segments: 12,
                  category: oc) { _ in .brass }
            lathe("light.lanternGlass", l + CV3(0, 2.4, 0), axis: CV3(0, 1, 0), [(3, 0), (3.2, 3.6), (3, 7.2)], segments: 12,
                  capStart: .lamp, capEnd: .lamp, category: oc) { _ in .lamp }
            lathe("light.lanternBase", l, axis: CV3(0, 1, 0), [(3.8, 0), (3.8, 2.4)], segments: 12, capStart: .brass, category: oc) { _ in .brass }
            if night {
                out.lights.append(CamperLightSpec(name: "lantern", kind: .omni, position: l + CV3(0, 6, 0), color: 0xFFBE6E,
                                                  intensity: 380, range: 60))
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
            case "roller":
                add("interior.curtainRoll", .cylinder(radius: 1.8, height: width + 2, segments: 12), .curtain, at: CV3(mid, y1 + 2.4, z - 1),
                    CQuat.yTo(CV3(1, 0, 0)), category: cc)
                rbox("interior.curtain", CV3(mid, y1 - 1.6, z - 0.4), CV3(width, 4, 0.4), 0.1, .curtain, category: cc)
                rbox("interior.curtainBar", CV3(mid, y1 - 3.8, z - 0.4), CV3(width, 0.8, 0.8), 0.2, .woodDark, category: cc)
            case "cafe":
                rod("interior.curtainRail", CV3(x0 - 2, y0 + height / 2, z - 0.6), CV3(x1 + 2, y0 + height / 2, z - 0.6), 0.4, .brass, category: cc)
                for i in 0..<Int(width / 3) {
                    rbox("interior.curtain", CV3(x0 + 1.5 + Double(i) * 3, y0 + height / 4, z - 0.4 - Double(i % 2) * 0.6),
                         CV3(3, height / 2, 0.4), 0.1, .curtain, category: cc)
                }
            case "blind":
                let n = max(4, Int(height / 2.4))
                for i in 0..<n {
                    rbox("interior.blindSlat", CV3(mid, y0 + 1 + Double(i) * height / Double(n), z - 0.6), CV3(width, 0.25, 2), 0.05,
                         .tint(0xE8E0D0), CQuat.axisAngle(CV3(1, 0, 0), 0.5), category: cc)
                }
                rbox("interior.blindHead", CV3(mid, y1 + 1.4, z - 0.6), CV3(width + 2, 2, 2.4), 0.4, .tint(0xE8E0D0), category: cc)
            default:
                for xa in [x0 + 1, x1 - 7] {
                    for kk in 0..<3 {
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
        switch k(.cushion) {
        case "round":
            for (i, s) in (spots + [spots[0] + CV3(30, 0, 0)]).enumerated() {
                add("interior.cushion", .cylinder(radius: 5, height: 2.4, segments: 18), .canvas(i % 2 == 0 ? 0xC9A66B : 0x2F4F74),
                    at: s + CV3(0, 2, 0), CQuat.axisAngle(CV3(0, 0, 1), -1.2), category: cc)
            }
        case "bolster":
            for s in spots {
                add("interior.cushion", .cylinder(radius: 3.2, height: 16, segments: 16), .canvas(0x7A2E22), at: s + CV3(0, 1.6, 0),
                    CQuat.yTo(CV3(0, 0, 1)), category: cc)
            }
        case "patch":
            let colors: [UInt32] = [0x7A2E22, 0x2F4F74, 0xC9A66B, 0x4A5A46]
            for s in spots {
                for (i, col) in colors.enumerated() {
                    rbox("interior.cushion", s + CV3(0, 5 + Double(i / 2) * 5 - 2.5, Double(i % 2) * 5 - 2.5), CV3(4, 5, 5), 0.8, .canvas(col),
                         CQuat.axisAngle(CV3(0, 0, 1), -0.3), category: cc)
                }
            }
        default:
            for (i, s) in spots.enumerated() {
                rbox("interior.cushion", s + CV3(0, 5, 0), CV3(4, 10, 10), 1.6, .canvas(i == 0 ? 0x4A5A46 : 0xC9A66B),
                     CQuat.axisAngle(CV3(0, 0, 1), -0.3), category: cc)
            }
        }
    }

    /// 吊りランプ（座卓の上）
    mutating func hangingLamp() {
        let lc = CamperCategory.lamp
        let top = CV3(-89, roofTop - 12, 12)
        let lit: CamperMaterial = night ? .lamp : .brass
        switch k(.lamp) {
        case "bulb":
            rod("interior.lampCord", top, top - CV3(0, 20, 0), 0.25, .black, category: lc)
            add("interior.lampSocket", .cylinder(radius: 1, height: 2.4, segments: 10), .brass, at: top - CV3(0, 21.2, 0), category: lc)
            add("interior.lamp", .sphere(radius: 2.4), night ? .lamp : .glass, at: top - CV3(0, 24.6, 0), category: lc)
        case "paper":
            rod("interior.lampCord", top, top - CV3(0, 12, 0), 0.25, .black, category: lc)
            add("interior.lamp", .sphere(radius: 7), night ? .lamp : .canvasLight, at: top - CV3(0, 19, 0), category: lc, scale: CV3(1, 0.85, 1))
            for i in 0..<4 { add("interior.lampRib", .torus(ring: 6.8 - abs(Double(i) - 1.5) * 1.6, pipe: 0.2), .woodDark,
                                at: top - CV3(0, 15 + Double(i) * 2.6, 0), category: lc) }
        case "chandelier":
            rod("interior.lampCord", top, top - CV3(0, 10, 0), 0.4, .brass, category: lc)
            add("interior.lamp", .torus(ring: 7, pipe: 0.6), .brass, at: top - CV3(0, 12, 0), category: lc)
            for i in 0..<4 {
                let t = Double(i) / 4 * 2 * .pi
                rod("interior.lampArm", top - CV3(0, 10, 0), top + CV3(cos(t) * 7, -12, sin(t) * 7), 0.3, .brass, category: lc)
                add("interior.candle", .cylinder(radius: 0.8, height: 3, segments: 8), .tint(0xF1E3C4), at: top + CV3(cos(t) * 7, -10, sin(t) * 7), category: lc)
                add("interior.flame", .sphere(radius: 0.8), night ? .lamp : .tint(0xF2C66B), at: top + CV3(cos(t) * 7, -7.8, sin(t) * 7), category: lc)
            }
        default:
            rod("interior.lampCord", top, top - CV3(0, 14, 0), 0.3, .black, category: lc)
            lathe("interior.lamp", top - CV3(0, 21, 0), axis: CV3(0, 1, 0), [(0.01, 0), (5.5, 1), (4.5, 5), (0.3, 7)], segments: 14,
                  category: lc) { _ in lit }
        }
    }

    /// 棚（反対側の壁・吊り戸棚の下）
    mutating func shelf() {
        guard !van else { return }
        let sc = CamperCategory.shelf
        let y = 100.0, z = -(BW - wall) + 5, x0 = -62.0
        rbox("interior.shelf", CV3(x0, y, z), CV3(34, 1.2, 10), 0.3, .woodDark, category: sc)
        switch k(.shelf) {
        case "spice":
            for i in 0..<6 {
                lathe("interior.jar", CV3(x0 - 14 + Double(i) * 5.6, y + 0.6, z), axis: CV3(0, 1, 0), [(2, 0), (2, 5), (1.2, 5.6), (1.2, 6.6)],
                      segments: 10, capStart: .glass, capEnd: .tint(0x6E4A2B), category: sc) { _ in .glass }
                add("interior.spice", .cylinder(radius: 1.7, height: 3, segments: 10), .tint([0xA4372B, 0xC9A66B, 0x4A5A46][i % 3]),
                    at: CV3(x0 - 14 + Double(i) * 5.6, y + 2.2, z), category: sc)
            }
        case "mugs":
            rod("interior.mugRail", CV3(x0 - 16, y - 3, z + 3), CV3(x0 + 16, y - 3, z + 3), 0.4, .brass, category: sc)
            for i in 0..<4 {
                let c = CV3(x0 - 12 + Double(i) * 8, y - 9, z + 3)
                lathe("interior.mug", c, axis: CV3(0, 1, 0), [(2.2, 0), (2.4, 5), (2.1, 5), (2, 0.5)], segments: 14,
                      capStart: .tint([0xE8E0CC, 0x2F4F74, 0xA4372B, 0xC9A66B][i]), category: sc) { _ in .tint([0xE8E0CC, 0x2F4F74, 0xA4372B, 0xC9A66B][i]) }
                add("interior.mugHandle", .torus(ring: 1.4, pipe: 0.35), .tint([0xE8E0CC, 0x2F4F74, 0xA4372B, 0xC9A66B][i]),
                    at: c + CV3(2.6, 2.6, 0), CQuat.yTo(CV3(0, 0, 1)), category: sc)
            }
        case "plants":
            for i in 0..<3 {
                let c = CV3(x0 - 10 + Double(i) * 10, y + 0.6, z)
                lathe("interior.shelfPot", c, axis: CV3(0, 1, 0), [(1.8, 0), (2.4, 3.6)], segments: 12, capStart: .tint(0xA4532E), category: sc) { _ in .tint(0xA4532E) }
                for j in 0..<3 { add("interior.shelfLeaf", .sphere(radius: 1.8), .tint(0x5D7A3A), at: c + CV3(Double(j - 1) * 1.2, 5 + Double(j % 2), 0), category: sc) }
            }
        default:
            let colors: [UInt32] = [0x7A2E22, 0x2F4F74, 0xC9A66B, 0x4A5A46, 0xD9D4C7, 0x6E4A2B]
            for i in 0..<12 {
                let h = 7 + Double(i % 3)
                rbox("interior.shelfBook", CV3(x0 - 15 + Double(i) * 2.5, y + 0.6 + h / 2, z), CV3(2, h, 7), 0.2, .tint(colors[i % 6]), category: sc)
            }
        }
    }

    /// 壁の木（内壁の色と、板の継ぎ目の立体の溝）
    var wallMaterial: CamperMaterial {
        switch k(.wall) {
        case "walnut": return .wallWood(0x6B4A32)
        case "shiplap": return .tint(0xEDE8DE)
        case "cedar": return .wallWood(0xA8643E)
        default: return .wallWood(0xD9C9A8)
        }
    }

    mutating func wallSeams() {
        let wc = CamperCategory.wall
        let key = k(.wall)
        let roomX = (rear + 6, van ? 50.0 : 62.0)
        // 幅木（床と壁の境の木の帯。壁の木と同じ木）
        for s in [1.0, -1.0] {
            rbox("interior.skirting", CV3((roomX.0 + roomX.1) / 2, 36, s * (BW - wall - 0.6)), CV3(roomX.1 - roomX.0, 4, 1.2), 0.3,
                 wallMaterial, category: wc)
        }
        guard key != "birch" else { return }
        let yRange = (35.0, roofTop - 6)
        for (s, holes) in [(1.0, windowsNear + [doorHole]), (-1.0, windowsFar + [hatch])] {
            let z = s * (BW - wall - 0.15)
            let boxes = holes.map { h -> (Double, Double, Double, Double) in
                (h.map(\.x).min()! - 1, h.map(\.x).max()! + 1, h.map(\.y).min()! - 1, h.map(\.y).max()! + 1)
            }
            if key == "shiplap" {
                var y = yRange.0 + 8
                while y < yRange.1 {
                    // 窓と扉の所を抜いた区間
                    var spans = [(roomX.0, roomX.1)]
                    for b in boxes where y > b.2 && y < b.3 {
                        spans = spans.flatMap { sp -> [(Double, Double)] in
                            guard b.0 < sp.1, b.1 > sp.0 else { return [sp] }
                            return [(sp.0, b.0), (b.1, sp.1)].filter { $0.1 - $0.0 > 2 }
                        }
                    }
                    for sp in spans {
                        rbox("interior.wallSeam", CV3((sp.0 + sp.1) / 2, y, z), CV3(sp.1 - sp.0, 0.5, 0.3), 0.1, .tint(0xC9C2B4), category: wc)
                    }
                    y += 8
                }
            } else {
                let step = key == "cedar" ? 5.0 : 16.0
                var x = roomX.0 + step
                while x < roomX.1 {
                    var spans = [(yRange.0, yRange.1)]
                    for b in boxes where x > b.0 && x < b.1 {
                        spans = spans.flatMap { sp -> [(Double, Double)] in
                            guard b.2 < sp.1, b.3 > sp.0 else { return [sp] }
                            return [(sp.0, b.2), (b.3, sp.1)].filter { $0.1 - $0.0 > 2 }
                        }
                    }
                    for sp in spans {
                        rbox("interior.wallSeam", CV3(x, (sp.0 + sp.1) / 2, z), CV3(0.4, sp.1 - sp.0, 0.3), 0.1, .tint(0x2A1A10), category: wc)
                    }
                    x += step
                }
            }
        }
    }

    /// 床（材質と、タイルの升の立体）
    var floorMaterial: CamperMaterial {
        switch k(.floor) {
        case "cork": return .tint(0xB08A5A)
        case "checker": return .tint(0xEDEAE2)
        case "terrazzo": return .stone
        default: return .floorIn
        }
    }

    mutating func floorFinish() {
        let fc = CamperCategory.floor
        let zr = BW - wall - 0.5
        let x0 = rear + 5, x1 = van ? 50.0 : 62.0
        switch k(.floor) {
        case "checker":
            var x = x0
            var i = 0
            while x + 8 <= x1 {
                var z = -zr
                var j = 0
                while z + 8 <= zr {
                    if (i + j) % 2 == 0 { rbox("interior.tile", CV3(x + 4, 34.1, z + 4), CV3(8, 0.2, 8), 0, .tint(0x1B1C1F), category: fc) }
                    z += 8
                    j += 1
                }
                x += 8
                i += 1
            }
        case "terrazzo":
            var seed: UInt64 = 11
            func rnd() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double((seed >> 33) & 0xFFFF) / 65535
            }
            for _ in 0..<60 {
                let x = x0 + rnd() * (x1 - x0), z = -zr + rnd() * zr * 2
                add("interior.chip", .cylinder(radius: 0.6 + rnd() * 1.2, height: 0.2, segments: 7),
                    .tint([0x7A2E22, 0x4A5A46, 0x2F4F74, 0x1B1C1F][Int(rnd() * 3.99)]), at: CV3(x, 34.1, z), category: fc)
            }
        case "cork":
            var x = x0 + 12
            while x < x1 { rbox("interior.tileGap", CV3(x, 34.05, 0), CV3(0.3, 0.1, zr * 2), 0, .tint(0x8A6A44), category: fc); x += 12 }
        default:
            var z = -zr + 7
            while z < zr { rbox("interior.boardGap", CV3((x0 + x1) / 2, 34.05, z), CV3(x1 - x0, 0.1, 0.3), 0, .tint(0x4A3220), category: fc); z += 7 }
        }
    }
}
