import Foundation

// 家具の形（2026-10-19）。owner「アーティファクトの家具はホンモノ感が足りないので実装する時気をつけて」:
// 板の家具の絵は種類と置き方の参考にとどめ、形は実物の家具に寄せる。
// - 実寸（1 単位 = 2.5 cm）。寝台 2.0 × 1.0 m・座卓 75 cm・椅子の座面 40 cm・床の灯り 1.4 m
// - 面取り・厚み・脚・取っ手・継ぎ目・縫い目・クッションのふくらみ・布のたわみ・使い込んだ跡
// - 置物を添えて暮らしの気配を出す（机のマグ・棚の本・鞄の上の毛布）
//
// 座標: 床の物はマスの真ん中が原点・y は床から上・r = 0 で横が x。壁の物は壁の面の上の真ん中（段の下が y = 0・
// 壁から +z へ出る）。天井の物は天井が y = 0 で下へ吊る。網の単位は板の単位（SceneKit へは 1/100）。

private typealias K = CamperRoomMeshKit
private func R(_ m: CamperRoomMaterial) -> CamperMaterial { .room(m) }

enum CamperRoomFurnitureModels {

    /// 写真の面の材質（額ごとに画面の側が差し替える。`slot` は額の中の何枚目か）
    static func photoMaterial(_ slot: Int) -> CamperMaterial { .room(.photo("slot\(slot)")) }

    /// 家具の形（形を作り込んだ家具だけ。まだのものは nil）
    static func mesh(_ id: String) -> CamperMesh? {
        let m: CamperMesh?
        switch id {
        case "bed.platform": m = platformBed()
        case "bed.futon": m = futon()
        case "seating.floor_cushion": m = floorCushion()
        case "seating.beanbag": m = beanbag()
        case "table.dinette_post": m = dinetteTable()
        case "table.round_cafe": m = cafeTable()
        case "table.chabudai": m = chabudai()
        case "storage.trunk": m = trunk()
        case "storage.tall_drawers": m = tallDrawers()
        case "storage.wicker_baskets": m = wickerBaskets()
        case "heater.wood_stove": m = woodStove()
        case "heater.kerosene": m = keroseneHeater()
        case "room_rug.runner": m = runnerRug()
        case "room_rug.oval_hooked": m = ovalRug()
        case "room_rug.tatami": m = tatami()
        case "floor_lamp.brass_stem": m = brassStemLamp()
        case "floor_lamp.tripod": m = tripodLamp()
        case "wall_shelf.plank_brackets": m = plankShelf()
        case "photo_frame.landscape": m = landscapeFrame()
        case "photo_frame.square": m = squareFrame()
        case "photo_frame.oval": m = ovalFrame()
        case "poster.tall_print": m = tallPrint()
        case "wall_lamp.glass_sconce": m = glassSconce()
        case "clock.station": m = stationClock()
        case "string_ceiling.globe_string": m = globeString()
        case "mobile.wooden_birds": m = woodenBirds()
        case "plant_hanger.macrame": m = macrame()
        case "roof_hatch.square_vent": m = squareVent()
        default: m = moreMesh(id) ?? moreMesh3(id) ?? CamperRoomVariety.mesh(id)
        }
        return m
    }

    /// 夜に灯る所（家具の原点からの位置・板の単位）と、光の強さの目安。灯りの色は部屋の模様替えの色。
    /// 2026-10-19（Mac run 568）: 部屋は小さい（灯りから家具まで 0.3〜0.9）ので、外の車の室内灯（520）の強さでは
    /// 夜の部屋が白く飛んだ。run 575 で届く距離を 30〜40 に縮めると、縁の硬い真っ白な丸と真っ黒に分かれた（run 576）。
    /// 強さを 10 分の 1 にし、届く距離を 50〜85 に戻して、灯りから離れるほどなだらかに暗くなる溜まりにした
    /// （`CamperRoomBuilder.nightBudget` が合計の上限）
    static func lamp(_ id: String) -> (position: CV3, intensity: Double, range: Double)? {
        switch id {
        case "heater.wood_stove": return (CV3(0, 10, 9), 0.35, 55)
        case "heater.kerosene": return (CV3(0, 9, 0), 0.3, 50)
        case "floor_lamp.brass_stem": return (CV3(0, 47, 0), 0.7, 85)
        case "floor_lamp.tripod": return (CV3(0, 48, 0), 0.7, 85)
        case "wall_lamp.glass_sconce": return (CV3(0, 13, 7), 0.45, 70)
        case "string_ceiling.globe_string": return (CV3(0, -9, 0), 0.45, 75)
        default: return moreLamp(id) ?? moreLamp3(id) ?? CamperRoomVariety.lamp(id)
        }
    }

    // MARK: - 床: 寝台

    /// 木の寝台（2.0 × 1.0 m）。ナラの枠（頭板・足板・横の框・脚）、ふくらんだ敷き布団、掛け布団の折り返し、枕 2、足元の毛布
    static func platformBed() -> CamperMesh {
        let oak = R(.wood(.oak)), worn = R(.wornWood(.oak))
        var parts: [CamperMesh] = []
        // 脚（角を丸めた角材）
        for (x, z) in [(-38.0, -18.0), (38, -18), (-38, 18), (38, 18)] {
            parts.append(K.block(CV3(3.2, 4, 3.2), at: CV3(x, 0, z), radius: 0.6, oak))
        }
        // 横の框（2）と足の框
        for z in [-18.8, 18.8] { parts.append(K.block(CV3(78, 6.5, 2.4), at: CV3(0, 3.5, z), radius: 0.7, oak)) }
        parts.append(K.block(CV3(2.4, 9, 40), at: CV3(38.8, 3.5, 0), radius: 0.7, worn))
        // 頭板（上の縁を丸めた厚い板・真ん中に細い溝 2 本）
        parts.append(K.block(CV3(2.6, 18.5, 40), at: CV3(-38.8, 3.5, 0), radius: 1.1, worn))
        for z in [-7.0, 7.0] { parts.append(K.block(CV3(0.4, 12, 0.5), at: CV3(-37.4, 7, z), radius: 0.1, R(.wood(.darkOak)))) }
        // 床板（框の内の簀の子・隙間から見える）
        for k in 0..<9 { parts.append(K.block(CV3(7, 0.8, 36), at: CV3(-34 + Double(k) * 8.5, 7.5, 0), radius: 0.2, R(.wood(.pine)))) }
        // 敷き布団（ふくらみ・縁の縫い目）
        parts.append(K.placed(K.roundedBox(CV3(75, 5, 36), radius: 2.2, segments: 3, puff: 0.6, R(.cotton(0xE8E1D2))), at: CV3(0.5, 10.8, 0)))
        parts.append(K.tube(K.roundedRect(75.5, 36.5, r: 2.6).map { CV3($0.x + 0.5, 10.8, $0.y) }, radius: 0.35, sides: 6, closed: true,
                            R(.cotton(0xCFC6B4))))
        // 掛け布団（足の側 3 分の 2・横へ垂れる）と、頭の側の折り返し
        parts.append(K.placed(K.roundedBox(CV3(48, 3, 38.5), radius: 1.4, segments: 3, puff: 0.9, sidePuff: 0.6, R(.linen(0x7E8E9B))),
                              at: CV3(13, 14.6, 0)))
        parts.append(K.placed(K.roundedBox(CV3(5, 3.4, 38.6), radius: 1.6, segments: 3, puff: 0.4, R(.linen(0xEDE8DE))),
                              at: CV3(-12, 14.9, 0)))
        // 枕 2（少し向きを崩す）
        for (z, yaw) in [(-9.0, 0.05), (9.0, -0.07)] {
            parts.append(K.placed(K.roundedBox(CV3(12, 3.6, 16), radius: 1.7, segments: 3, puff: 1.3, sidePuff: 0.5, R(.linen(0xF1EDE4))),
                                  at: CV3(-31, 15.2, z), yaw: yaw))
        }
        // 足元の毛布（畳んで掛けた編み物）
        parts.append(K.placed(K.roundedBox(CV3(11, 1.6, 39.5), radius: 0.7, segments: 2, puff: 0.3, sidePuff: 0.3, R(.knit(0xB5653F))),
                              at: CV3(31, 16.6, 0)))
        parts.append(K.placed(K.drape(width: 11, height: 4, folds: 2, depth: 0.4, flare: 0.1, R(.knit(0xB5653F))),
                              at: CV3(31, 16.6, 19.9)))
        return K.merge(parts)
    }

    /// 畳む布団（床に直に敷く・敷き布団の厚み 12 cm・掛け布団を足の側で三つ折り・そば殻の枕）
    static func futon() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.placed(K.roundedBox(CV3(76, 4.6, 37), radius: 2.2, segments: 3, puff: 0.5, sidePuff: 0.3, R(.cotton(0xE6DED0))),
                              at: CV3(0, 2.5, 0)))
        parts.append(K.tube(K.roundedRect(76.4, 37.4, r: 2.6).map { CV3($0.x, 2.4, $0.y) }, radius: 0.3, sides: 6, closed: true,
                            R(.cotton(0xC9BFAC))))
        // 三つ折りの掛け布団（3 層・上ほど少し小さく、折り目は丸い）
        for k in 0..<3 {
            let y = 4.6 + Double(k) * 2.6
            parts.append(K.placed(K.roundedBox(CV3(22 - Double(k), 2.8, 36.5 - Double(k) * 0.6), radius: 1.3, segments: 3, puff: 0.5,
                                               R(.linen(0x9E5B47))), at: CV3(24, y + 1.4, 0)))
        }
        parts.append(K.placed(K.roundedBox(CV3(4, 7.6, 36.5), radius: 1.9, segments: 3, R(.linen(0x9E5B47))), at: CV3(35, 8.2, 0)))
        // そば殻の枕（俵形）
        parts.append(K.placed(K.roundedBox(CV3(9, 4, 16), radius: 2, segments: 3, puff: 0.8, sidePuff: 0.6, R(.linen(0xD9CDB4))),
                              at: CV3(-31, 6.7, 0)))
        // 枕元の文庫本
        parts.append(K.placed(K.roundedBox(CV3(4.4, 0.8, 6.2), radius: 0.2, segments: 1, R(.painted(0x2F4F74))), at: CV3(-33, 0.4, 14), yaw: 0.3))
        return K.merge(parts)
    }

    // MARK: - 床: 椅子

    /// 座布団（丸い・真ん中を綴じた窪み・房 4）
    static func floorCushion() -> CamperMesh {
        let velvet = R(.velvet(0x7A3B2E))
        // 縁から真ん中へゆるく盛り上がる（綴じの窪みは真ん中の釦で見せる。旋盤の面は外へ向くよう、上り坂だけで作る）
        var profile: [CV2] = [CV2(0, 5.2)]
        for k in 1...14 {
            let t = Double(k) / 14
            profile.append(CV2(t * 9, 1.6 + 3.6 * pow(max(0, 1 - t * t), 0.5)))
        }
        profile.append(CV2(9.3, 1.3))
        profile.append(CV2(9.0, 0.4))
        profile.append(CV2(7.5, 0))
        profile.append(CV2(0, 0))
        // 旋盤の断面は下の真ん中から外へ・上へ・上の真ん中へ（向きが外を向く）
        var parts = [K.lathe(Array(profile.reversed()), segments: 36, velvet, capStart: false, capEnd: false)]
        parts.append(K.placed(K.scaled(K.sphere(radius: 0.7, segments: 10, velvet), CV3(1, 0.55, 1)), at: CV3(0, 5.1, 0)))
        // 縁の縫い目
        parts.append(K.tube(K.arc(center: .zero, radius: 9.25, from: 0, to: 2 * .pi, steps: 40).map { CV3($0.x, 1.35, $0.y) },
                            radius: 0.22, sides: 5, closed: true, R(.velvet(0x5E2A20))))
        // 房（金の糸束・4 つ）
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            let p = CV3(cos(a) * 9.2, 1.3, sin(a) * 9.2), out = CV3(cos(a), 0, sin(a))
            // 房: 縁から垂れる細い糸束（床に寝る）
            parts.append(K.tube([p, p + out * 0.5 + CV3(0, -0.6, 0), p + out * 1.0 + CV3(0, -1.15, 0)], radius: 0.16, sides: 5, R(.canvas(0xC9A15A))))
            for k2 in 0..<5 {
                let spread = CV3(-out.z, 0, out.x) * (Double(k2) - 2) * 0.18
                parts.append(K.tube([p + out * 1.0 + CV3(0, -1.15, 0), p + out * 1.6 + spread + CV3(0, -1.2, 0)], radius: 0.09, sides: 4,
                                    R(.canvas(0xC9A15A))))
            }
        }
        return K.merge(parts)
    }

    /// ビーズの袋（形の決まらない袋・座った窪み・しわ・縫い目）
    static func beanbag() -> CamperMesh {
        let cloth = R(.velvet(0x7D8A5E))
        let rows = 16, cols = 40
        var mesh = CamperMesh()
        func point(_ i: Int, _ j: Int) -> CV3 {
            let a = Double(i) / Double(cols) * 2 * .pi
            let t = Double(j) / Double(rows)
            // 下は平らに広がり、上は窪む
            let r = 14.5 * sin(t * .pi * 0.92 + 0.1) * (1 + 0.04 * sin(a * 7 + t * 9) * sin(t * .pi))
            var y = 21 * (1 - cos(t * .pi)) / 2
            // 座った窪み（前寄り）と、高い背（後ろ）
            let back = max(0, -cos(a)) * 4.5 * t
            let seat = 5.5 * exp(-pow((t - 1) * 2.4, 2)) * max(0, 0.6 + 0.4 * cos(a))
            y += back - seat
            if j == rows { return CV3(-2, y, 0) }
            return CV3(cos(a) * r - 1, y, sin(a) * r)
        }
        let grid = (0...rows).map { j in (0...cols).map { i in point(i, j) } }
        for j in 0..<rows {
            for i in 0..<cols {
                let a = grid[j][i], b = grid[j][i + 1], c = grid[j + 1][i + 1], d = grid[j + 1][i]
                let nn = (d - a).cross(b - a)
                mesh.quad(a, b, c, d, nn, nn, nn, nn, cloth)
            }
        }
        mesh = CamperRoomShapes.smoothNormals(mesh)
        var parts = [mesh]
        // 縫い目（横の 2 本）
        for j in [5, 10] {
            parts.append(K.tube((0...cols).map { grid[j][$0] + (grid[j][$0] - CV3(-1, grid[j][$0].y, 0)).normalized * 0.15 }, radius: 0.25,
                                sides: 5, closed: true, R(.velvet(0x5E6A45))))
        }
        // 持ち手（後ろの革の輪）
        let top = grid[13][cols / 2]
        parts.append(K.tube(K.arc(center: top + CV3(-0.8, 0.5, 0), radius: 1.6, from: 0, to: .pi, steps: 8).map { CV3($0.x, $0.y, $0.z) },
                            radius: 0.45, sides: 6, R(.leather(0x5B3A22))))
        return K.merge(parts)
    }

    // MARK: - 床: 机

    /// 一本脚の座卓（キャンピングカーの食卓。ナラの天板 90 × 65 cm・クロームの柱と座金・マグと本）
    static func dinetteTable() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.disc(radius: 6.5, height: 0.8, bevel: 0.3, R(.chrome)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.5, 0), CV2(1.5, 26.6), CV2(0, 26.6)], segments: 20, R(.chrome)), at: CV3(0, 0.8, 0)))
        parts.append(K.placed(K.disc(radius: 1.9, height: 2.2, bevel: 0.4, R(.chrome)), at: CV3(0, 0.8, 0)))
        parts.append(K.placed(K.disc(radius: 5, height: 0.8, bevel: 0.3, R(.chrome)), at: CV3(0, 26.8, 0)))
        // 天板（縁は丸く・木口は少し濃い）と、その下の補強の桟
        parts.append(K.placed(K.roundedBox(CV3(36, 2.2, 26), radius: 1, segments: 3, material: { $0.y > 0.5 ? R(.wood(.oak)) : R(.wornWood(.oak)) }),
                              at: CV3(0, 28.7, 0)))
        for z in [-8.0, 8.0] { parts.append(K.block(CV3(30, 1.2, 2), at: CV3(0, 26.4, z), radius: 0.3, R(.wood(.oak)))) }
        // 琺瑯のマグ（白に紺の縁）と、開いた本
        parts.append(CamperRoomShapes.mug(at: CV3(8, 29.8, 4), body: R(.enamel(0xF2F0EA)), rim: R(.enamel(0x22324A)), yaw: 0.6))
        parts.append(K.placed(K.roundedBox(CV3(9, 0.9, 6.4), radius: 0.25, segments: 1, R(.paper)), at: CV3(-7, 30.25, -2), yaw: -0.2))
        parts.append(K.placed(K.roundedBox(CV3(9.4, 0.5, 6.8), radius: 0.15, segments: 1, R(.painted(0x7A2E22))), at: CV3(-7, 29.95, -2), yaw: -0.2))
        return K.merge(parts)
    }

    /// 丸いカフェ机（チークの丸い天板・鉄の三本脚の弧・輪の貫・小さな花瓶）
    static func cafeTable() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.placed(K.disc(radius: 12.5, height: 1.6, bevel: 0.6, segments: 40, R(.wood(.teak))), at: CV3(0, 28.4, 0)))
        parts.append(K.placed(K.disc(radius: 4, height: 1, bevel: 0.3, R(.iron)), at: CV3(0, 27.4, 0)))
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi
            let dir = CV3(cos(a), 0, sin(a))
            let path = (0...10).map { s -> CV3 in
                let t = Double(s) / 10
                // 上は真ん中に集まり、下で外へ反る
                let r = 2.5 + 8.5 * pow(t, 1.6)
                return dir * r + CV3(0, 27.6 - t * 27.2, 0)
            }
            parts.append(K.tube(path, radius: 0.55, sides: 8, R(.iron)))
            parts.append(K.placed(K.disc(radius: 0.9, height: 0.5, bevel: 0.2, segments: 10, R(.iron)), at: dir * 11))
        }
        parts.append(K.tube(K.arc(center: .zero, radius: 6.6, from: 0, to: 2 * .pi, steps: 36).map { CV3($0.x, 11, $0.y) }, radius: 0.35,
                            sides: 6, closed: true, R(.iron)))
        // 小さな花瓶と花
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.3, 0), CV2(1.8, 1.6), CV2(1.2, 4.2), CV2(0.7, 5), CV2(0.9, 5.4), CV2(0, 5.4)],
                                      segments: 18, R(.ceramic(0x6E8FA3))), at: CV3(3, 30, -2)))
        for k in 0..<3 {
            let a = Double(k) * 2.1
            let top = CV3(3 + cos(a) * 1.4, 39 + Double(k), -2 + sin(a) * 1.4)
            parts.append(K.tube([CV3(3, 34, -2), top], radius: 0.15, sides: 4, R(.leaf)))
            parts.append(K.placed(K.sphere(radius: 0.9, segments: 8, R(.linen(0xE8C35A))), at: top))
        }
        return K.merge(parts)
    }

    /// ちゃぶ台（胡桃の丸い天板・幕板の輪・脚 4・急須と湯呑み 2）
    static func chabudai() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.placed(K.disc(radius: 13, height: 1.4, bevel: 0.5, segments: 40, R(.wood(.walnut))), at: CV3(0, 11.6, 0)))
        parts.append(K.placed(K.lathe([CV2(10.5, 0), CV2(11, 0), CV2(11, 1.8), CV2(10.5, 1.8)], segments: 36, R(.wood(.walnut)),
                                      capStart: false, capEnd: false), at: CV3(0, 9.8, 0)))
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            parts.append(K.placed(K.roundedBox(CV3(1.8, 10.5, 1.8), radius: 0.4, segments: 2, R(.wornWood(.walnut))),
                                  at: CV3(cos(a) * 8.6, 5.25, sin(a) * 8.6), yaw: a))
        }
        // 急須（胴・注ぎ口・蓋・横の持ち手）と湯呑み
        let tea = R(.ceramic(0x3E5A4A))
        let pot = CV3(-3, 13, 2)
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.6, 0), CV2(2.6, 1.2), CV2(2.6, 2.6), CV2(1.6, 3.6), CV2(1.2, 3.8), CV2(0, 3.8)],
                                      segments: 20, tea), at: pot))
        parts.append(K.placed(K.sphere(radius: 0.5, segments: 8, tea), at: pot + CV3(0, 4.1, 0)))
        parts.append(K.tube([pot + CV3(2.2, 1.2, 0), pot + CV3(3.6, 2.4, 0), pot + CV3(4.3, 3.4, 0)], radius: 0.45, sides: 8, tea))
        parts.append(K.tube([pot + CV3(-1.4, 2, 1.8), pot + CV3(-2.6, 2.2, 3.2)], radius: 0.5, sides: 8, tea))
        for (x, z) in [(4.0, -3.0), (6.0, 2.0)] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.9, 0), CV2(1.2, 0.3), CV2(1.3, 2.4), CV2(1.15, 2.4), CV2(1.0, 0.6), CV2(0, 0.6)],
                                          segments: 16, R(.ceramic(0xD9CFBD))), at: CV3(x, 13, z)))
        }
        return K.merge(parts)
    }

    // MARK: - 床: しまう物

    /// 旅の鞄（革を張った箱・丸い蓋・真鍮の帯 2・角金・留め金・両端の革の持ち手・上に畳んだ毛布）
    static func trunk() -> CamperMesh {
        let leather = R(.leather(0x6A4428)), brass = R(.agedBrass), slat = R(.wornWood(.cedar))
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(28, 11, 18), at: .zero, radius: 0.8, leather))
        // 丸い蓋（弧の断面を横へ押し出す）
        let arch = CamperRoomShapes.archOutline(width: 18, base: 1.2, rise: 4.2)
        parts.append(K.placed(CamperRoomShapes.extrudeAlongX(arch, length: 28, inset: 0.4, leather), at: CV3(0, 11, 0)))
        // 蓋と胴の木の桟（横 2・蓋の上 3）
        for y in [1.2, 9.6] {
            for z in [-9.05, 9.05] { parts.append(K.block(CV3(27, 1.2, 0.5), at: CV3(0, y, z), radius: 0.15, slat)) }
        }
        for z in [-5.0, 0.0, 5.0] {
            let top = 11 + 1.2 + 4.2 * sqrt(max(0, 1 - pow(z / 9, 2)))
            parts.append(K.block(CV3(27.4, 0.6, 1.4), at: CV3(0, top - 0.1, z), radius: 0.2, slat))
        }
        // 真鍮の帯 2（胴をぐるりと・蓋の弧に沿って）
        for x in [-8.0, 8.0] {
            parts.append(K.block(CV3(1.3, 11.1, 18.5), at: CV3(x, 0, 0), radius: 0.3, brass))
            parts.append(K.placed(CamperRoomShapes.extrudeAlongX(CamperRoomShapes.archOutline(width: 18.5, base: 1.3, rise: 4.45), length: 1.3,
                                                                 inset: 0.2, brass), at: CV3(x, 10.9, 0)))
        }
        // 角金 8
        for x in [-13.6, 13.6] {
            for z in [-8.6, 8.6] {
                for y in [0.0, 9.0] { parts.append(K.block(CV3(1.6, 2, 1.6), at: CV3(x, y, z), radius: 0.5, brass)) }
            }
        }
        // 留め金（前の真ん中）
        parts.append(K.block(CV3(2.4, 3, 0.8), at: CV3(0, 9, 9.3), radius: 0.3, brass))
        parts.append(K.placed(K.disc(radius: 0.5, height: 0.4, bevel: 0.1, segments: 10, R(.iron)), at: CV3(0, 10.5, 9.7),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        // 両端の革の持ち手
        for x in [-14.4, 14.4] {
            let s = x < 0 ? -1.0 : 1.0
            parts.append(K.tube([CV3(x, 8, -3), CV3(x + s * 0.9, 7.2, -1.5), CV3(x + s * 1.1, 7, 0), CV3(x + s * 0.9, 7.2, 1.5), CV3(x, 8, 3)],
                                radius: 0.5, sides: 6, R(.leather(0x3E2616))))
        }
        // 上に畳んだ毛布（蓋の弧に沿ってたわむ）
        parts.append(K.placed(K.drape(width: 10, height: 2, folds: 1, depth: 0.15, flare: 0, R(.knit(0x8A9A8C))),
                              at: CV3(-6, 17.6, 0), rotation: CQuat.axisAngle(CV3(1, 0, 0), -.pi / 2)))
        parts.append(K.placed(K.roundedBox(CV3(10, 1.4, 12), radius: 0.6, segments: 2, puff: 0.3, R(.knit(0x8A9A8C))), at: CV3(-6, 17.1, 0)))
        return K.merge(parts)
    }

    /// 背の高い引き出し（脚・側板と背板・引き出し 4 段の隙間と前板・真鍮の取っ手・上の笠木と鉢植え）
    static func tallDrawers() -> CamperMesh {
        let teak = R(.wood(.teak)), worn = R(.wornWood(.teak)), brass = R(.agedBrass)
        var parts: [CamperMesh] = []
        for (x, z) in [(-8.2, -7.6), (8.2, -7.6), (-8.2, 7.6), (8.2, 7.6)] {
            parts.append(K.placed(K.leg(bottom: 0.65, top: 1.15, height: 4.2, teak), at: CV3(x, 0, z)))
        }
        parts.append(K.block(CV3(19.2, 1.2, 16.6), at: CV3(0, 4.2, 0), radius: 0.35, teak))
        for x in [-9.2, 9.2] { parts.append(K.block(CV3(1.1, 40.5, 16.4), at: CV3(x, 5.4, 0), radius: 0.28, teak)) }
        parts.append(K.block(CV3(17.2, 40.5, 0.9), at: CV3(0, 5.4, -7.6), radius: 0.2, R(.wood(.darkOak))))
        parts.append(K.block(CV3(20.2, 1.6, 17.6), at: CV3(0, 45.6, 0.25), radius: 0.45, worn))
        parts.append(K.block(CV3(20.6, 0.45, 0.55), at: CV3(0, 47.0, 8.6), radius: 0.12, worn))
        for k in 0..<4 {
            let y = 5.6 + Double(k) * 9.7
            parts.append(K.block(CV3(17.0, 0.35, 15.6), at: CV3(0, y - 0.2, 0.2), radius: 0.08, R(.wood(.darkOak))))
            parts.append(K.block(CV3(17.2, 8.9, 1.05), at: CV3(0, y, 8.5), radius: 0.32, teak))
            parts.append(K.block(CV3(14.6, 6.6, 0.45), at: CV3(0, y + 1.15, 9.05), radius: 0.35, worn))
            for x in [-8.4, 8.4] {
                parts.append(K.block(CV3(0.35, 8.6, 14.8), at: CV3(x, y, 0.3), radius: 0.08, R(.iron)))
            }
            for x in [-4.2, 4.2] {
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.85, 0), CV2(0.85, 0.28), CV2(0.4, 0.55), CV2(0.65, 1.35), CV2(0, 1.45)],
                                              segments: 14, brass), at: CV3(x, y + 4.4, 9.15),
                                      rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
            }
        }
        parts.append(CamperRoomShapes.pottedPlant(at: CV3(3.2, 47.2, 0), potRadius: 2.5, height: 3.4, leaves: 7, spread: 4.8))
        return K.merge(parts)
    }

    /// 籐の籠 3（大中小・縦の編み筋・縁の巻き・持ち手・中に毛布とタオル）
    static func wickerBaskets() -> CamperMesh {
        var parts: [CamperMesh] = []
        for (x, r, h) in [(-9.5, 4.6, 11.0), (1.0, 4.0, 9.0), (10.0, 3.6, 7.0)] {
            let body = K.vessel(outer: [CV2(0, 0), CV2(r * 0.86, 0), CV2(r, h * 0.2), CV2(r * 1.06, h)],
                                inner: [CV2(0, 0.6), CV2(r * 0.78, 0.6), CV2(r * 0.9, h * 0.2), CV2(r * 0.98, h)], segments: 28, R(.wicker))
            parts.append(K.placed(body, at: CV3(x, 0, 0)))
            parts.append(K.tube(K.arc(center: .zero, radius: r * 1.04, from: 0, to: 2 * .pi, steps: 28).map { CV3(x + $0.x, h, $0.y) }, radius: 0.45,
                                sides: 6, closed: true, R(.wicker)))
            // 縦の編み筋
            for k in 0..<12 {
                let a = Double(k) / 12 * 2 * .pi
                parts.append(K.tube([CV3(x + cos(a) * r * 0.95, 0.8, sin(a) * r * 0.95),
                                     CV3(x + cos(a) * r * 1.02, h * 0.95, sin(a) * r * 1.02)], radius: 0.12, sides: 4, R(.wicker)))
            }
            // 持ち手
            parts.append(K.tube([CV3(x - r * 0.7, h * 0.7, 0), CV3(x - r * 0.55, h + 2.2, 0), CV3(x + r * 0.55, h + 2.2, 0),
                                 CV3(x + r * 0.7, h * 0.7, 0)], radius: 0.28, sides: 5, R(.wicker)))
        }
        parts.append(K.placed(K.roundedBox(CV3(7.6, 3, 7), radius: 1.4, segments: 3, puff: 0.8, R(.knit(0xD8CFC0))), at: CV3(-9.5, 10.2, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.5, 0), CV2(1.5, 6.4), CV2(0, 6.4)], segments: 14, R(.cotton(0xA8B8C2))),
                              at: CV3(4.2, 8.6, 0), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2)))
        return K.merge(parts)
    }

    // MARK: - 床: 暖める物

    /// 薪ストーブ（鋳物の箱・猫脚 4・雲母の窓の奥に燠と炎・扉の枠と取っ手・上の鉄板・煙突は天井まで・下に石の炉台）
    static func woodStove() -> CamperMesh {
        let iron = R(.castIron)
        var parts: [CamperMesh] = []
        // 炉台（石の板）
        parts.append(K.block(CV3(20, 0.9, 20), at: .zero, radius: 0.4, R(.countertop)))
        // 猫脚
        for (x, z) in [(-6.0, -5.5), (6, -5.5), (-6, 5.5), (6, 5.5)] {
            parts.append(K.tube([CV3(x, 5, z), CV3(x * 1.08, 3, z * 1.08), CV3(x * 1.18, 1.2, z * 1.18), CV3(x * 1.25, 0.9, z * 1.25)],
                                radius: 0.8, sides: 8, iron))
        }
        // 胴（下の段・上の段で少し出っ張る）
        parts.append(K.block(CV3(15, 12.5, 13), at: CV3(0, 4.6, 0), radius: 0.8, iron))
        parts.append(K.block(CV3(16.2, 1.2, 14.2), at: CV3(0, 4.2, 0), radius: 0.4, iron))
        parts.append(K.block(CV3(16.6, 1.4, 14.6), at: CV3(0, 17, 0), radius: 0.5, iron))
        // 横の放熱の筋
        for k in 0..<5 {
            for x in [-7.6, 7.6] { parts.append(K.block(CV3(0.4, 9, 0.6), at: CV3(x, 6.4, -4.8 + Double(k) * 2.4), radius: 0.15, iron)) }
        }
        // 扉（枠・雲母の窓・奥の火・取っ手）
        parts.append(K.block(CV3(11.6, 9.4, 0.9), at: CV3(0, 6.2, 6.7), radius: 0.4, iron))
        parts.append(K.placed(K.panel(width: 8.4, height: 6.4, R(.fire)), at: CV3(0, 11, 6.2)))
        parts.append(K.placed(K.panel(width: 8.6, height: 6.6, R(.mica)), at: CV3(0, 11, 7.25)))
        parts.append(K.tube(K.roundedRect(9, 7, r: 0.8).map { CV3($0.x, 11 + $0.y, 7.3) }, radius: 0.35, sides: 6, closed: true, iron))
        parts.append(K.tube([CV3(5, 13.8, 7.3), CV3(5.6, 13.8, 8.4), CV3(7.6, 13.8, 8.6)], radius: 0.35, sides: 6, R(.iron)))
        parts.append(K.placed(K.sphere(radius: 0.6, segments: 8, R(.agedBrass)), at: CV3(7.9, 13.8, 8.6)))
        // 空気の取り入れ（下の丸いつまみ）
        parts.append(K.placed(K.disc(radius: 1.1, height: 0.6, bevel: 0.2, segments: 14, R(.agedBrass)), at: CV3(0, 5.6, 7.1),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        // 煙突（継ぎ目の輪・ダンパーのつまみ・天井の座）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.6, 0), CV2(2.6, 70.6), CV2(0, 70.6)], segments: 22, R(.iron), capStart: false, capEnd: false),
                              at: CV3(0, 17.4, -2)))
        for y in [30.0, 52.0, 74.0] {
            parts.append(K.placed(K.disc(radius: 2.85, height: 0.8, bevel: 0.2, segments: 22, R(.iron)), at: CV3(0, y, -2)))
        }
        parts.append(K.tube([CV3(-3.6, 36, -2), CV3(3.6, 36, -2)], radius: 0.25, sides: 6, R(.iron)))
        parts.append(K.placed(K.sphere(radius: 0.55, segments: 8, R(.agedBrass)), at: CV3(3.8, 36, -2)))
        parts.append(K.placed(K.disc(radius: 4.2, height: 0.8, bevel: 0.2, segments: 22, R(.iron)), at: CV3(0, 87.2, -2)))
        return K.merge(parts)
    }

    /// 石油ストーブ（丸い赤い琺瑯の胴・上の網・覗き窓の炎・クロームの輪・持ち手・上にやかん）
    static func keroseneHeater() -> CamperMesh {
        let red = R(.enamel(0xA8322A))
        var parts: [CamperMesh] = []
        parts.append(K.lathe([CV2(0, 0), CV2(7.6, 0), CV2(7.8, 0.4), CV2(7.8, 1.2), CV2(7.2, 1.4), CV2(0, 1.4)], segments: 32, R(.chrome)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(6.8, 0), CV2(7, 0.6), CV2(7, 7.6), CV2(6.6, 8), CV2(0, 8)], segments: 32, red), at: CV3(0, 1.4, 0)))
        // 覗き窓（燃える芯の明かり）と窓の枠
        parts.append(K.placed(K.panel(width: 3.4, height: 1.6, R(.fire)), at: CV3(0, 5.6, 7.06)))
        parts.append(K.tube(K.roundedRect(3.8, 2, r: 0.5).map { CV3($0.x, 5.6 + $0.y, 7.15) }, radius: 0.2, sides: 5, closed: true, R(.chrome)))
        // 上の網の筒（縦の線と輪）と天板
        let top = 9.4
        for k in 0..<24 {
            let a = Double(k) / 24 * 2 * .pi
            parts.append(K.tube([CV3(cos(a) * 5.6, top, sin(a) * 5.6), CV3(cos(a) * 5.4, top + 8, sin(a) * 5.4)], radius: 0.12, sides: 4, R(.iron)))
        }
        for y in [top + 0.3, top + 4, top + 7.8] {
            parts.append(K.tube(K.arc(center: .zero, radius: 5.55, from: 0, to: 2 * .pi, steps: 28).map { CV3($0.x, y, $0.y) }, radius: 0.18,
                                sides: 5, closed: true, R(.chrome)))
        }
        parts.append(K.placed(K.panel(width: 7.2, height: 7.2, R(.fire)), at: CV3(0, top + 3.4, 0), rotation: CQuat.axisAngle(CV3(0, 1, 0), 0.4)))
        parts.append(K.placed(K.disc(radius: 6.2, height: 0.7, bevel: 0.25, segments: 30, R(.chrome)), at: CV3(0, top + 8, 0)))
        // 持ち手
        parts.append(K.tube(K.arc(center: CV3(0, top + 8.7, 0), radius: 4, from: 0, to: .pi, steps: 10).map { CV3($0.x, $0.y, 0) }, radius: 0.3,
                            sides: 6, R(.chrome)))
        // 上のやかん
        let k0 = CV3(-1, top + 8.7, 1.5)
        let kettle = R(.enamel(0xE8E3D6))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.6, 0), CV2(3, 1), CV2(2.6, 2.6), CV2(1.2, 3.4), CV2(1.2, 3.8), CV2(0, 3.8)], segments: 22,
                                      kettle), at: k0))
        parts.append(K.tube([k0 + CV3(2.4, 1.2, 0), k0 + CV3(3.8, 2.4, 0), k0 + CV3(4.4, 3.4, 0)], radius: 0.4, sides: 6, kettle))
        parts.append(K.tube(K.arc(center: k0 + CV3(0, 3.8, 0), radius: 2, from: 0.2, to: .pi - 0.2, steps: 8).map { CV3($0.x, $0.y, k0.z) },
                            radius: 0.2, sides: 5, R(.iron)))
        return K.merge(parts)
    }

    // MARK: - 床: 敷物

    /// 細長い敷物（織りの縞と菱の文様・両端の房）
    static func runnerRug() -> CamperMesh {
        var parts = [K.rug(K.roundedRect(56, 18, r: 0.8), thickness: 0.55, top: R(.runner), edge: R(.runner))]
        for side in [-1.0, 1.0] {
            for k in 0..<14 {
                let z = -8 + Double(k) * (16.0 / 13)
                let x = side * 28
                parts.append(K.tube([CV3(x, 0.3, z), CV3(x + side * 1.2, 0.2, z + 0.15), CV3(x + side * 2.2, 0.15, z - 0.1)], radius: 0.18, sides: 4,
                                    R(.cotton(0xE6DCC6))))
            }
        }
        return K.merge(parts)
    }

    /// 楕円の輪の敷物（編んだ縄を 5 重に巻いた楕円）
    static func ovalRug() -> CamperMesh {
        let outline = (0..<48).map { k -> CV2 in
            let a = Double(k) / 48 * 2 * .pi
            return CV2(cos(a) * 28.5, sin(a) * 18.5)
        }
        // 縁は編んだ縄をもう一巻き（太さ 1 cm・撚りの筋）
        let rim = (0..<72).map { k -> CV3 in
            let a = Double(k) / 72 * 2 * .pi
            return CV3(cos(a) * 28.2, 0.55, sin(a) * 18.2)
        }
        return K.merge([K.rug(outline, thickness: 0.8, top: R(.ovalRug), edge: R(.linen(0x8A3D2C))),
                        K.tube(rim, radius: 0.5, sides: 6, closed: true, R(.rope))])
    }

    /// 置き畳（畳床の厚み・藺草の目の筋・黒い縁布 4 辺・角の縫い）
    static func tatami() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(36.0, 1.15, 37.6), at: CV3(0, 0, 0), radius: 0.25, R(.wood(.cedar))))
        parts.append(K.block(CV3(35.2, 0.45, 36.8), at: CV3(0, 1.15, 0), radius: 0.2, R(.rush)))
        for i in 0..<18 {
            let x = -16.0 + Double(i) * 1.85
            parts.append(K.block(CV3(0.35, 0.12, 35.6), at: CV3(x, 1.55, 0), radius: 0.05, R(.rush)))
        }
        for i in 0..<12 {
            let z = -16.5 + Double(i) * 3.0
            parts.append(K.block(CV3(34.5, 0.08, 0.18), at: CV3(0, 1.58, z), radius: 0.03, R(.rushEdge)))
        }
        for z in [-18.9, 18.9] {
            parts.append(K.block(CV3(38.2, 1.55, 1.7), at: CV3(0, 0.05, z), radius: 0.25, R(.rushEdge)))
        }
        for x in [-18.7, 18.7] {
            parts.append(K.block(CV3(1.5, 1.52, 36.2), at: CV3(x, 0.05, 0), radius: 0.22, R(.rushEdge)))
        }
        for (x, z) in [(-18.5, -18.5), (18.5, -18.5), (-18.5, 18.5), (18.5, 18.5)] {
            parts.append(K.block(CV3(2.2, 1.6, 2.2), at: CV3(x, 0.08, z), radius: 0.35, R(.rushEdge)))
        }
        return K.merge(parts)
    }

    // MARK: - 床: 灯り

    /// 真鍮の一本足（鉄の重い台・真鍮の柱・緑の硝子の笠に乳白の内側・電球・引き紐）
    static func brassStemLamp() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.disc(radius: 4.6, height: 1.2, bevel: 0.5, R(.iron)))
        parts.append(K.placed(K.disc(radius: 1.6, height: 1.2, bevel: 0.4, segments: 16, R(.brass)), at: CV3(0, 1.2, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.45, 0), CV2(0.45, 44), CV2(0, 44)], segments: 12, R(.brass)), at: CV3(0, 2.4, 0)))
        for y in [16.0, 32.0] { parts.append(K.placed(K.disc(radius: 0.75, height: 0.6, bevel: 0.2, segments: 12, R(.brass)), at: CV3(0, y, 0))) }
        // 笠（外は緑の硝子・内は乳白）。縁は巻いた真鍮
        let shade: [CV2] = [CV2(1.4, 55), CV2(2.2, 54.6), CV2(4.4, 52.6), CV2(6.4, 49.4), CV2(7.2, 47.2)]
        parts.append(K.lathe(shade, segments: 28, R(.enamel(0x2F5A3C)), capStart: false, capEnd: false))
        parts.append(K.inverted(K.lathe(shade.map { CV2($0.x - 0.25, $0.y - 0.25) }, segments: 28, R(.milkGlass), capStart: false, capEnd: false)))
        parts.append(K.tube(K.arc(center: .zero, radius: 7.2, from: 0, to: 2 * .pi, steps: 28).map { CV3($0.x, 47.2, $0.y) }, radius: 0.3,
                            sides: 6, closed: true, R(.brass)))
        parts.append(K.placed(K.disc(radius: 1.5, height: 1.4, bevel: 0.3, segments: 12, R(.brass)), at: CV3(0, 54.6, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.9, 0), CV2(0.9, 1.6), CV2(0, 1.6)], segments: 12, R(.brass)), at: CV3(0, 48.6, 0)))
        parts.append(K.placed(K.sphere(radius: 1.8, segments: 14, R(.bulb)), at: CV3(0, 47.4, 0)))
        parts.append(K.tube([CV3(1.2, 48.8, 0), CV3(1.4, 42.5, 0)], radius: 0.08, sides: 4, R(.brass)))
        parts.append(K.placed(K.sphere(radius: 0.35, segments: 8, R(.brass)), at: CV3(1.4, 42.2, 0)))
        return K.merge(parts)
    }

    /// 三脚の灯り（木の脚 3・真鍮の継ぎ手・麻の筒の笠・電球）
    static func tripodLamp() -> CamperMesh {
        var parts: [CamperMesh] = []
        let apex = CV3(0, 43, 0)
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi + 0.4
            let foot = CV3(cos(a) * 8.6, 0.6, sin(a) * 8.6)
            parts.append(K.tube([foot, foot * 0.5 + apex * 0.5, apex], radius: 0.6, sides: 8, R(.wood(.walnut))))
            parts.append(K.tube([foot, foot + (apex - foot).normalized * 1.4], radius: 0.7, sides: 8, R(.brass)))
        }
        parts.append(K.placed(K.disc(radius: 1.3, height: 2, bevel: 0.3, segments: 12, R(.brass)), at: apex + CV3(0, -1, 0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.9, 0), CV2(0.9, 2.6), CV2(0, 2.6)], segments: 12, R(.brass)), at: apex + CV3(0, 1, 0)))
        parts.append(K.placed(K.sphere(radius: 1.9, segments: 14, R(.bulb)), at: apex + CV3(0, 5, 0)))
        // 笠（麻の筒・上下の縁の巻き）
        parts.append(K.lathe([CV2(7.4, 44), CV2(7.4, 56)], segments: 32, R(.shade(0xE7DCC7)), capStart: false, capEnd: false))
        parts.append(K.inverted(K.lathe([CV2(7.15, 44), CV2(7.15, 56)], segments: 32, R(.shade(0xE7DCC7)), capStart: false, capEnd: false)))
        for y in [44.0, 56.0] {
            parts.append(K.tube(K.arc(center: .zero, radius: 7.3, from: 0, to: 2 * .pi, steps: 32).map { CV3($0.x, y, $0.y) }, radius: 0.22,
                                sides: 5, closed: true, R(.shade(0xD8CBB2))))
        }
        // 笠の中の骨
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi
            parts.append(K.tube([apex + CV3(0, 3, 0), CV3(cos(a) * 7.1, 54, sin(a) * 7.1)], radius: 0.1, sides: 4, R(.brass)))
        }
        return K.merge(parts)
    }

    // MARK: - 壁

    /// 板と金具（一枚板・鉄の受け 2・本 4 冊と硝子の瓶と鉢植え）
    static func plankShelf() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(28, 1.6, 7.4), at: CV3(0, 7.2, 3.7), radius: 0.35, R(.wornWood(.oak))))
        for x in [-9.5, 9.5] {
            let l: [CV2] = [CV2(0, 0), CV2(0.8, 0), CV2(0.8, 6.4), CV2(6.6, 6.4), CV2(6.6, 7.2), CV2(0, 7.2)]
            parts.append(K.placed(CamperRoomShapes.extrudeAlongX(l.map { CV2($0.x, $0.y) }, length: 1, inset: 0.15, R(.iron)), at: CV3(x, 0, 0),
                                  rotation: .identity))
            parts.append(K.tube([CV3(x, 0.6, 0.8), CV3(x, 6.2, 6.2)], radius: 0.3, sides: 5, R(.iron)))
        }
        // 本（背の色と高さが違う・最後の 1 冊は傾ける）
        let books: [(Double, Double, Double, UInt32)] = [(-12, 7.4, 1.4, 0x7A2E22), (-10.4, 8.2, 1.6, 0x2F4F74), (-8.6, 6.8, 1.1, 0xD9CDB4),
                                                         (-7.3, 7.6, 1.5, 0x3E5A3C)]
        for (x, h, w, c) in books {
            parts.append(K.block(CV3(w, h, 5.4), at: CV3(x, 8.8, 3.6), radius: 0.2, R(.painted(c))))
        }
        parts.append(K.placed(K.roundedBox(CV3(1.3, 7, 5.4), radius: 0.2, segments: 1, R(.painted(0xA8572E))), at: CV3(-5.4, 12.2, 3.6),
                              rotation: CQuat.axisAngle(CV3(0, 0, 1), -0.32)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.6, 0), CV2(1.7, 4), CV2(1.2, 4.6), CV2(1.2, 5.2), CV2(0, 5.2)], segments: 16, R(.glass)),
                              at: CV3(2, 8.8, 3.6)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.3, 0), CV2(1.3, 3), CV2(0, 3)], segments: 12, R(.linen(0xC9A15A))), at: CV3(2, 8.8, 3.6)))
        parts.append(CamperRoomShapes.pottedPlant(at: CV3(9, 8.8, 4.2), potRadius: 2, height: 3, leaves: 6, spread: 3.0))
        return K.merge(parts)
    }

    /// 横長の額（黒い木の枠・白いマット・写真・表の硝子・吊り紐）。2 マス × 1 段の真ん中
    static func landscapeFrame() -> CamperMesh {
        var parts = [CamperRoomShapes.frame(outer: CV2(17, 12.4), photo: CV2(11.4, 7.6), depth: 1.6, rim: 1.15, at: CV3(0, 10, 0),
                                            frame: R(.painted(0x1C1B1A)))]
        parts.append(K.tube([CV3(-5.5, 15.8, 0.5), CV3(0, 18.8, 0.7), CV3(5.5, 15.8, 0.5)], radius: 0.12, sides: 5, R(.rope)))
        parts.append(K.placed(K.disc(radius: 0.4, height: 0.55, bevel: 0.12, segments: 12, R(.brass)), at: CV3(0, 18.9, 0.15),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        return K.merge(parts)
    }

    /// 正方形の額（ナラの枠・マット・写真・吊り紐と釘・側面の溝）
    static func squareFrame() -> CamperMesh {
        var parts = [CamperRoomShapes.frame(outer: CV2(13, 13), photo: CV2(8.6, 8.6), depth: 1.8, rim: 1.35, at: CV3(0, 9, 0.2), frame: R(.wood(.oak)))]
        parts.append(K.tube([CV3(-4.5, 15.2, 0.5), CV3(0, 18.8, 0.7), CV3(4.5, 15.2, 0.5)], radius: 0.12, sides: 5, R(.rope)))
        parts.append(K.placed(K.disc(radius: 0.45, height: 0.6, bevel: 0.15, segments: 12, R(.brass)), at: CV3(0, 18.9, 0.15),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        // 枠の側面の細い溝（木の厚み）
        for s in [-1.0, 1.0] {
            parts.append(K.block(CV3(0.25, 10.5, 0.35), at: CV3(s * 6.6, 9, 1.4), radius: 0.08, R(.wornWood(.oak))))
        }
        return K.merge(parts)
    }

    /// 楕円の額（真鍮の二重の縁・マット・写真・背板・吊り環）
    static func ovalFrame() -> CamperMesh {
        var parts: [CamperMesh] = []
        let c = CV3(0, 10, 0)
        parts.append(K.placed(K.ellipsePanel(rx: 4.6, ry: 6.8, R(.wood(.walnut))), at: c + CV3(0, 0, 0.25)))
        parts.append(K.placed(K.ellipsePanel(rx: 4.0, ry: 6.0, R(.mat)), at: c + CV3(0, 0, 0.55)))
        parts.append(K.placed(K.ellipsePanel(rx: 3.4, ry: 5.3, R(.paper)), at: c + CV3(0, 0, 0.7)))
        parts.append(K.placed(K.ellipsePanel(rx: 3.35, ry: 5.25, photoMaterial(0)), at: c + CV3(0, 0, 0.82)))
        parts.append(K.placed(K.ellipsePanel(rx: 4.15, ry: 6.15, R(.frameGlass)), at: c + CV3(0, 0, 1.05)))
        let ring = (0..<56).map { k -> CV3 in
            let a = Double(k) / 56 * 2 * .pi
            return c + CV3(cos(a) * 4.05, sin(a) * 6.05, 1.15)
        }
        parts.append(K.tube(ring, radius: 0.5, sides: 10, closed: true, R(.brass)))
        parts.append(K.tube(ring.map { CV3(c.x + ($0.x - c.x) * 1.12, c.y + ($0.y - c.y) * 1.1, 0.55) },
                            radius: 0.28, sides: 8, closed: true, R(.agedBrass)))
        // 吊り環
        parts.append(K.tube(K.arc(center: c + CV3(0, 7.2, 1.0), radius: 0.7, from: 0.2, to: .pi - 0.2, steps: 12)
                                .map { CV3($0.x, $0.y, 1.0) }, radius: 0.12, sides: 6, R(.brass)))
        parts.append(K.placed(K.sphere(radius: 0.35, segments: 8, R(.brass)), at: c + CV3(0, 6.5, 1.0)))
        return K.merge(parts)
    }

    /// 縦長の写真（白い余白のある印画紙・マスキングテープ 4 枚）。2 マス × 2 段
    static func tallPrint() -> CamperMesh {
        var parts: [CamperMesh] = []
        let c = CV3(0, 20, 0.15)
        // 印画紙はわずかに波打ち、下の角が壁から浮く（平らな板にしない）
        parts.append(K.placed(CamperRoomShapes.paperSheet(width: 15, height: 21, curl: 0.9, R(.paper)), at: c))
        parts.append(K.placed(CamperRoomShapes.paperSheet(width: 12.6, height: 17, curl: 0.75, photoMaterial(0)), at: c + CV3(0, 0.8, 0.06)))
        for (dx, dy, a) in [(-7.0, 10.0, 0.5), (7.0, 10.0, -0.45), (-7.0, -10.0, -0.5), (7.0, -10.0, 0.4)] {
            parts.append(K.placed(K.panel(width: 4, height: 1.3, R(.linen(0xE8DDB8))), at: c + CV3(dx, dy, 0.12),
                                  rotation: CQuat.axisAngle(CV3(0, 0, 1), a)))
        }
        return K.merge(parts)
    }

    /// 硝子の壁灯（真鍮の座・曲がった腕・乳白のチューリップの笠・電球）
    static func glassSconce() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.placed(K.disc(radius: 2.4, height: 0.7, bevel: 0.25, segments: 20, R(.brass)), at: CV3(0, 9, 0),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.tube([CV3(0, 9, 0.6), CV3(0, 9, 3.2), CV3(0, 9.8, 5.4), CV3(0, 11.6, 6.6)], radius: 0.45, sides: 8, R(.brass)))
        parts.append(K.placed(K.disc(radius: 1, height: 1.2, bevel: 0.25, segments: 12, R(.brass)), at: CV3(0, 11.4, 6.8)))
        parts.append(K.placed(K.sphere(radius: 1.3, segments: 12, R(.bulb)), at: CV3(0, 13.6, 6.8)))
        let tulip: [CV2] = [CV2(1.1, 12.4), CV2(2.4, 12.9), CV2(3.4, 14.6), CV2(3.8, 16.8), CV2(3.5, 17.4)]
        let cup = tulip.map { CV2($0.x, $0.y - 12.4) }
        parts.append(K.placed(K.lathe(cup, segments: 26, R(.milkGlass), capStart: false, capEnd: false), at: CV3(0, 12.4, 6.8)))
        parts.append(K.placed(K.inverted(K.lathe(cup.map { CV2($0.x - 0.2, $0.y + 0.1) }, segments: 26, R(.milkGlass), capStart: false, capEnd: false)),
                              at: CV3(0, 12.4, 6.8)))
        return K.merge(parts)
    }

    /// 駅の時計（黒い鉄の縁・白い文字盤・針 3・表の硝子）
    static func stationClock() -> CamperMesh {
        var parts: [CamperMesh] = []
        let c = CV3(0, 10, 0)
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(K.vessel(outer: [CV2(0, 0), CV2(4.6, 0), CV2(4.8, 0.4), CV2(4.8, 2.2), CV2(4.5, 2.6)],
                                       inner: [CV2(0, 0.6), CV2(4.0, 0.6), CV2(4.0, 2.6)], segments: 40, R(.castIron)), at: c, rotation: toWall))
        parts.append(K.placed(K.ellipsePanel(rx: 4.0, ry: 4.0, R(.dial)), at: c + CV3(0, 0, 0.62)))
        let hands: [(Double, Double, Double, CamperMaterial)] = [(-0.9, 2.4, 0.42, R(.painted(0x141414))), (0.55, 3.4, 0.3, R(.painted(0x141414))),
                                                                 (2.3, 3.6, 0.1, R(.painted(0xB0291F)))]
        for (i, (angle, len, w, m)) in hands.enumerated() {
            let q = CQuat.axisAngle(CV3(0, 0, 1), angle)
            parts.append(K.placed(K.roundedBox(CV3(w, len, 0.12), radius: 0.04, segments: 1, m), at: c + q.rotate(CV3(0, len / 2 - 0.5, 0)) + CV3(0, 0, 0.75 + Double(i) * 0.08),
                                  rotation: q))
        }
        parts.append(K.placed(K.disc(radius: 0.4, height: 0.3, bevel: 0.1, segments: 10, R(.painted(0x141414))), at: c + CV3(0, 0, 0.9),
                              rotation: toWall))
        parts.append(K.placed(K.lathe([CV2(0, 0.3), CV2(2.4, 0.25), CV2(4.0, 0)], segments: 32, R(.glass), capStart: false, capEnd: false),
                              at: c + CV3(0, 0, 1.4), rotation: toWall))
        return K.merge(parts)
    }

    // MARK: - 天井

    /// 電球の紐（両端の鉤から垂れる紐・丸い電球 8 つ・黒い受け口）
    static func globeString() -> CamperMesh {
        var parts: [CamperMesh] = []
        let n = 24
        let cord = (0...n).map { k -> CV3 in
            let t = Double(k) / Double(n)
            return CV3(-29 + 58 * t, -1.5 - 7 * sin(t * .pi), 0)
        }
        parts.append(K.tube(cord, radius: 0.2, sides: 5, R(.iron)))
        for x in [-29.0, 29.0] {
            parts.append(K.tube(K.arc(center: CV3(x, -1.0, 0), radius: 0.8, from: 0, to: 2 * .pi, steps: 10), radius: 0.15, sides: 4, closed: true,
                                R(.agedBrass)))
        }
        for k in 0..<8 {
            let t = (Double(k) + 0.5) / 8
            let p = CV3(-29 + 58 * t, -1.5 - 7 * sin(t * .pi), 0)
            parts.append(K.tube([p, p + CV3(0, -1.6, 0)], radius: 0.12, sides: 4, R(.iron)))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.55, 0), CV2(0.55, 1.2), CV2(0, 1.2)], segments: 10, R(.iron)), at: p + CV3(0, -2.8, 0)))
            parts.append(K.placed(K.sphere(radius: 1.35, segments: 12, R(.bulb)), at: p + CV3(0, -4.0, 0)))
        }
        return K.merge(parts)
    }

    /// 木の鳥（天井の糸・樺の横木・木の鳥 3 羽が高さを変えて）
    static func woodenBirds() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube([CV3(0, 0, 0), CV3(0, -12, 0)], radius: 0.06, sides: 3, R(.paper)))
        parts.append(K.tube([CV3(-6, -12, 0), CV3(6, -12, 0)], radius: 0.28, sides: 6, R(.wood(.birch))))
        for (x, drop, yaw, wood) in [(-5.6, 7.0, 0.4, CamperRoomWood.walnut), (0, 11.5, -0.9, .birch), (5.6, 6.0, 2.2, .teak)] {
            parts.append(K.tube([CV3(x, -12, 0), CV3(x, -12 - drop, 0)], radius: 0.05, sides: 3, R(.paper)))
            parts.append(K.placed(CamperRoomShapes.bird(R(.wood(wood))), at: CV3(x, -12 - drop - 1.2, 0), yaw: yaw))
        }
        return K.merge(parts)
    }

    /// マクラメ（天井の鉤と真鍮の輪・結んだ紐 4 本・陶器の鉢・垂れるつるの葉）
    static func macrame() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.tube(K.arc(center: CV3(0, -1.6, 0), radius: 1, from: 0, to: 2 * .pi, steps: 14).map { CV3($0.x, $0.y, 0) }, radius: 0.22,
                            sides: 6, closed: true, R(.brass)))
        let potTop = -20.0
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + .pi / 4
            let mid = CV3(cos(a) * 2.6, -12, sin(a) * 2.6), low = CV3(cos(a) * 4.6, potTop + 0.5, sin(a) * 4.6)
            parts.append(K.tube([CV3(0, -2.6, 0), mid, low, CV3(cos(a) * 3.2, potTop - 6.6, sin(a) * 3.2), CV3(0, potTop - 8.4, 0)],
                                radius: 0.22, sides: 5, R(.rope)))
            // 結び目
            parts.append(K.placed(K.sphere(radius: 0.55, segments: 8, R(.rope)), at: mid))
        }
        parts.append(K.placed(K.sphere(radius: 0.9, segments: 10, R(.rope)), at: CV3(0, -3.2, 0)))
        parts.append(K.placed(K.lathe([CV2(0, -9.6), CV2(0.5, -9.6), CV2(0.3, -12), CV2(0, -12)], segments: 6, R(.rope)), at: CV3(0, potTop, 0)))
        // 鉢と土と葉
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.6, 0), CV2(3.9, 2), CV2(4.2, 6), CV2(3.8, 6), CV2(3.6, 2.3), CV2(0, 2.3)], segments: 26,
                                      R(.ceramic(0xE8E2D6)), capStart: false, capEnd: false), at: CV3(0, potTop - 6, 0)))
        parts.append(K.placed(K.disc(radius: 3.7, height: 0.4, bevel: 0.1, segments: 22, R(.soil)), at: CV3(0, potTop - 0.8, 0)))
        parts.append(CamperRoomShapes.trailingVines(at: CV3(0, potTop - 0.4, 0), count: 6, length: 16))
        return K.merge(parts)
    }

    /// 四角い換気窓（厚い枠・内縁の真鍮・桟・煙った硝子・ヒンジと取っ手）
    static func squareVent() -> CamperMesh {
        var parts: [CamperMesh] = []
        let toDown = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        let ring = K.roundedRect(19, 19, r: 2.0, steps: 4)
        let hole = K.roundedRect(13.4, 13.4, r: 1.1, steps: 3)
        parts.append(K.placed(CamperMeshKit.extrude(ring, holes: [hole], depth: 2.6, front: R(.painted(0xE9E6DF)), side: R(.painted(0xDAD6CC)),
                                                    bevel: 0.45), at: CV3(0, -2.6, 0), rotation: toDown))
        parts.append(K.tube(K.roundedRect(13.6, 13.6, r: 1.1).map { CV3($0.x, -0.35, $0.y) }, radius: 0.22, sides: 6, closed: true, R(.brass)))
        for z in [-3.6, 0.0, 3.6] {
            parts.append(K.placed(K.block(CV3(12.8, 0.55, 0.5), at: .zero, radius: 0.12, R(.painted(0xBDB8AE))), at: CV3(0, -1.1, z), rotation: toDown))
        }
        parts.append(K.placed(K.panel(width: 13.2, height: 13.2, R(.glass)), at: CV3(0, -0.2, 0), rotation: toDown))
        parts.append(K.placed(K.panel(width: 13.2, height: 13.2, R(.windowView)), at: CV3(0, -1.5, 0), rotation: toDown))
        for x in [-5.5, 5.5] {
            parts.append(K.block(CV3(1.6, 0.55, 0.7), at: CV3(x, -2.8, 8.6), radius: 0.12, R(.chrome)))
        }
        parts.append(K.tube([CV3(-2.2, -2.9, 6.2), CV3(-2.2, -4.4, 6.2), CV3(2.2, -4.4, 6.2), CV3(2.2, -2.9, 6.2)],
                            radius: 0.32, sides: 6, R(.painted(0x2A2B2E))))
        for (x, z) in [(-8.0, -8.0), (8.0, -8.0), (-8.0, 8.0), (8.0, 8.0)] {
            parts.append(K.placed(K.sphere(radius: 0.4, segments: 8, R(.brass)), at: CV3(x, -0.55, z)))
        }
        return K.merge(parts)
    }
}
