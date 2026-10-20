import Foundation

// 家具の形・4 の組（2026-10-20）。椅子・机の脚違いではなく、用途そのものが違う分類
// （音・台所道具・便利・鏡・趣味）を一点ずつ作り込む。owner「色んなの作りたい」。

private typealias K = CamperRoomMeshKit
private func R(_ m: CamperRoomMaterial) -> CamperMaterial { .room(m) }

extension CamperRoomFurnitureModels {

    /// 4 の組の家具の形
    static func moreMesh4(_ id: String) -> CamperMesh? {
        switch id {
        case "audio.phonograph": return phonograph()
        case "audio.travel_radio": return travelRadio()
        case "audio.guitar_stand": return guitarStand()
        case "audio.cabinet_speaker": return cabinetSpeaker()
        case "kitchen_gear.drip_stand": return dripStand()
        case "kitchen_gear.board_cart": return boardCart()
        case "kitchen_gear.dish_rack": return dishRack()
        case "kitchen_gear.wine_rack": return wineRack()
        case "utility.coat_tree": return coatTree()
        case "utility.umbrella_stand": return umbrellaStand()
        case "utility.step_stool": return stepStool()
        case "utility.laundry_hamper": return laundryHamper()
        case "mirror.full_length": return fullLengthMirror()
        case "mirror.round_brass": return roundBrassMirror()
        case "mirror.tri_fold": return triFoldMirror()
        case "mirror.shaving": return shavingMirror()
        case "hobby.camera_shelf": return cameraShelf()
        case "hobby.rod_rack": return rodRack()
        case "hobby.ski_mount": return skiMount()
        case "hobby.easel": return wallEasel()
        default: return nil
        }
    }

    static func moreLamp4(_ id: String) -> (position: CV3, intensity: Double, range: Double)? {
        switch id {
        case "audio.travel_radio": return (CV3(0, 10, 4), 0.25, 45)
        default: return nil
        }
    }

    // MARK: 音

    /// 蓄音機（木の箱・ターンテーブル・ラッパ・アーム）
    static func phonograph() -> CamperMesh {
        var parts: [CamperMesh] = []
        let walnut = R(.wood(.walnut))
        parts.append(K.block(CV3(22, 12, 16), at: CV3(0, 0, 0), radius: 0.6, walnut))
        parts.append(K.block(CV3(20, 1.2, 14), at: CV3(0, 12, 0), radius: 0.3, R(.wornWood(.walnut))))
        parts.append(K.placed(K.disc(radius: 6.2, height: 0.5, bevel: 0.15, segments: 28, R(.painted(0x1A1A1A))), at: CV3(-2, 13.0, 0)))
        parts.append(K.placed(K.disc(radius: 5.6, height: 0.35, bevel: 0.1, segments: 28, R(.painted(0x2A1810))), at: CV3(-2, 13.4, 0)))
        parts.append(K.placed(K.disc(radius: 1.0, height: 0.8, bevel: 0.2, segments: 12, R(.brass)), at: CV3(-2, 13.5, 0)))
        // アーム
        parts.append(K.tube([CV3(7, 14, -4), CV3(4, 16, -1), CV3(0, 15.2, 2)], radius: 0.28, sides: 6, R(.agedBrass)))
        parts.append(K.placed(K.sphere(radius: 0.55, segments: 8, R(.agedBrass)), at: CV3(0, 15.2, 2)))
        // ラッパ
        let horn: [CV2] = [CV2(0.8, 0), CV2(1.2, 2), CV2(2.4, 6), CV2(4.5, 11), CV2(6.5, 14)]
        parts.append(K.placed(K.lathe(horn, segments: 24, R(.brass), capStart: false, capEnd: false), at: CV3(6, 18, 2),
                              rotation: CQuat.axisAngle(CV3(0, 0, 1), -0.9) * CQuat.axisAngle(CV3(1, 0, 0), 0.35)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.4, 0), CV2(1.4, 2.2), CV2(0, 2.2)], segments: 12, walnut), at: CV3(5.2, 16.5, 1.5)))
        return K.merge(parts)
    }

    /// 旅のラジオ（革の帯・丸いダイヤル・小さな光）
    static func travelRadio() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(14, 10, 7), at: CV3(0, 0, 0), radius: 0.7, R(.leather(0x5E3A24))))
        parts.append(K.block(CV3(12.5, 8, 0.4), at: CV3(0, 1, 3.6), radius: 0.2, R(.painted(0x2A2B2D))))
        // スピーカー網
        for row in 0..<4 {
            for col in 0..<6 {
                parts.append(K.placed(K.sphere(radius: 0.35, segments: 6, R(.iron)), at: CV3(-4.5 + Double(col) * 1.8, 2.5 + Double(row) * 1.6, 3.85)))
            }
        }
        parts.append(K.placed(K.disc(radius: 1.8, height: 0.5, bevel: 0.15, segments: 16, R(.brass)), at: CV3(3.5, 5, 3.9),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.placed(K.disc(radius: 0.35, height: 0.4, bevel: 0.1, segments: 8, R(.bulb)), at: CV3(-4.5, 8.2, 3.9),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        // 持ち手の帯
        parts.append(K.tube([CV3(-5, 10, 0), CV3(-5, 12.5, 0), CV3(5, 12.5, 0), CV3(5, 10, 0)], radius: 0.35, sides: 6, R(.leather(0x3E2618))))
        return K.merge(parts)
    }

    /// ギタースタンド（木の胴を立て掛ける脚と支え）
    static func guitarStand() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak))
        // スタンド脚
        for s in [-1.0, 1.0] {
            parts.append(K.tube([CV3(s * 6, 0.4, 5), CV3(s * 2, 28, -1), CV3(s * 1.2, 48, -2)], radius: 0.55, sides: 7, R(.iron)))
        }
        parts.append(K.tube([CV3(-6, 0.4, 5), CV3(6, 0.4, 5)], radius: 0.45, sides: 6, R(.iron)))
        parts.append(K.tube([CV3(-1.5, 48, -2), CV3(1.5, 48, -2)], radius: 0.4, sides: 6, R(.iron)))
        // ギター胴（寄せ木のような平たいラテ）
        let body = K.lathe([CV2(0, 0), CV2(5.5, 1), CV2(7.2, 8), CV2(6.8, 16), CV2(5.0, 22), CV2(3.2, 26), CV2(2.4, 28), CV2(0, 28)],
                           segments: 28, oak)
        parts.append(K.placed(K.scaled(body, CV3(1, 1, 0.45)), at: CV3(0, 18, 1.5), rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.25)))
        parts.append(K.placed(K.disc(radius: 2.2, height: 0.4, bevel: 0.1, segments: 16, R(.wood(.darkOak))), at: CV3(0, 30, 2.8),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.25)))
        // ネックとヘッド
        parts.append(K.placed(K.block(CV3(2.2, 28, 1.4), at: .zero, radius: 0.3, oak), at: CV3(0, 48, 3.5),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.2)))
        parts.append(K.placed(K.block(CV3(4.5, 5, 1.6), at: .zero, radius: 0.4, R(.wornWood(.oak))), at: CV3(0, 64, 4.2),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.15)))
        for x in [-1.4, -0.45, 0.45, 1.4] {
            parts.append(K.placed(K.sphere(radius: 0.35, segments: 6, R(.brass)), at: CV3(x, 65.5, 5.0)))
        }
        return K.merge(parts)
    }

    /// 棚のスピーカー（木箱・布の面・ポート）
    static func cabinetSpeaker() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(16, 28, 12), at: CV3(0, 0, 0), radius: 0.5, R(.wood(.teak))))
        parts.append(K.block(CV3(14, 24, 0.5), at: CV3(0, 2, 6.1), radius: 0.15, R(.knit(0xD8CDB8))))
        parts.append(K.placed(K.disc(radius: 4.5, height: 0.6, bevel: 0.2, segments: 20, R(.iron)), at: CV3(0, 16, 6.4),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.placed(K.disc(radius: 2.2, height: 0.5, bevel: 0.15, segments: 16, R(.iron)), at: CV3(0, 7, 6.4),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.4, 0), CV2(1.4, 3), CV2(0, 3)], segments: 12, R(.painted(0x1A1A1A))),
                              at: CV3(0, 24, 4)))
        return K.merge(parts)
    }

    // MARK: 台所道具

    /// ドリップスタンド（木の台・真鍮の腕・ガラスのドリッパーとサーバー）
    static func dripStand() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(14, 2, 12), at: .zero, radius: 0.4, R(.wood(.oak))))
        parts.append(K.block(CV3(2.2, 22, 2.2), at: CV3(-4, 2, 0), radius: 0.3, R(.wood(.oak))))
        parts.append(K.tube([CV3(-4, 22, 0), CV3(2, 24, 0), CV3(4, 22, 0)], radius: 0.35, sides: 8, R(.brass)))
        // ドリッパー
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.2, 0), CV2(2.4, -4), CV2(0.6, -5.5), CV2(0, -5.5)], segments: 20, R(.ceramic(0xE8E2D4))),
                              at: CV3(4, 21.5, 0)))
        // サーバー
        parts.append(K.placed(K.vessel(outer: [CV2(0, 0), CV2(3.4, 0), CV2(3.8, 2), CV2(3.2, 8), CV2(1.6, 10), CV2(1.6, 11), CV2(0, 11)],
                                       inner: [CV2(0, 0.4), CV2(3.0, 0.4), CV2(3.4, 2), CV2(2.9, 7.6), CV2(1.4, 9.6), CV2(0, 9.6)],
                                       segments: 22, R(.glass)), at: CV3(4, 2.2, 0)))
        parts.append(K.tube([CV3(4, 13.2, 0), CV3(6.5, 15, 0), CV3(7.2, 12.5, 0)], radius: 0.35, sides: 6, R(.glass)))
        return K.merge(parts)
    }

    /// まな板台（厚い板・下の引き出し・脚）
    static func boardCart() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak))
        for (x, z) in [(-11.0, -6.0), (11, -6), (-11, 6), (11, 6)] {
            parts.append(K.block(CV3(2.2, 14, 2.2), at: CV3(x, 0, z), radius: 0.35, oak))
        }
        parts.append(K.block(CV3(24, 10, 14), at: CV3(0, 14, 0), radius: 0.5, oak))
        parts.append(K.block(CV3(9, 1.2, 10), at: CV3(0, 18, 7.2), radius: 0.2, R(.brass)))
        parts.append(K.block(CV3(24, 2.8, 14), at: CV3(0, 24, 0), radius: 0.4, R(.wornWood(.oak))))
        // まな板の溝
        parts.append(K.block(CV3(18, 0.3, 0.4), at: CV3(0, 26.9, 4.5), radius: 0.1, R(.wood(.darkOak))))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.4, 0), CV2(1.5, 3.6), CV2(0.9, 4.0), CV2(0, 4.0)], segments: 12, R(.ceramic(0xE8E2D4))),
                              at: CV3(-6, 26.9, -2.5)))
        return K.merge(parts)
    }

    /// 食器の棚（斜めの桟に皿）
    static func dishRack() -> CamperMesh {
        var parts: [CamperMesh] = []
        let birch = R(.wood(.birch))
        parts.append(K.block(CV3(26, 2, 16), at: .zero, radius: 0.35, birch))
        for x in [-12.0, 12.0] {
            parts.append(K.block(CV3(1.4, 26, 14), at: CV3(x, 2, 0), radius: 0.25, birch))
        }
        for row in 0..<3 {
            let y = 6.0 + Double(row) * 7.5
            parts.append(K.block(CV3(24, 0.8, 12), at: CV3(0, y, 0), radius: 0.2, birch))
            for k in 0..<6 {
                let x = -10.0 + Double(k) * 4.0
                let plate = K.lathe([CV2(0, 0), CV2(3.2, 0.2), CV2(3.4, 0.6), CV2(2.8, 0.9), CV2(0, 0.9)], segments: 18,
                                    R(.ceramic([0xE8E2D4, 0xD9CFB8, 0xF2EEE4][k % 3])))
                parts.append(K.placed(plate, at: CV3(x, y + 0.8, 1), rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.55)))
            }
        }
        return K.merge(parts)
    }

    /// ワインラック（斜めの穴に瓶）
    static func wineRack() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(16, 36, 14), at: .zero, radius: 0.5, R(.wood(.pine))))
        let colors: [UInt32] = [0x3E1A24, 0x2A3A1E, 0x4A2018, 0x1E2A18, 0x5A2830, 0x2E2418]
        for row in 0..<3 {
            for col in 0..<2 {
                let x = -3.5 + Double(col) * 7.0
                let y = 6.0 + Double(row) * 10.0
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.0, 0), CV2(2.2, 2), CV2(1.8, 10), CV2(1.0, 12), CV2(0.9, 14), CV2(1.4, 15),
                                               CV2(0, 15)], segments: 14, R(.glass)), at: CV3(x, y, 2),
                                      rotation: CQuat.axisAngle(CV3(1, 0, 0), 0.85)))
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.6, 0), CV2(1.6, 7), CV2(0, 7)], segments: 12, R(.tintedGlass(colors[row * 2 + col]))),
                                      at: CV3(x, y + 1.2, 3.2), rotation: CQuat.axisAngle(CV3(1, 0, 0), 0.85)))
            }
        }
        return K.merge(parts)
    }

    // MARK: 便利な物

    /// コート掛け（柱と枝のフック）
    static func coatTree() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.disc(radius: 5.5, height: 1.4, bevel: 0.4, R(.wood(.oak))))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.6, 0), CV2(1.4, 60), CV2(1.8, 64), CV2(0, 64)], segments: 14, R(.wood(.oak))),
                              at: CV3(0, 1.4, 0)))
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi + 0.2
            let y = 48.0 + Double(k % 3) * 5.0
            let tip = CV3(cos(a) * 9, y - 2, sin(a) * 9)
            parts.append(K.tube([CV3(cos(a) * 1.5, y, sin(a) * 1.5), tip], radius: 0.45, sides: 6, R(.wood(.walnut))))
            parts.append(K.placed(K.sphere(radius: 0.7, segments: 8, R(.wood(.walnut))), at: tip))
        }
        // 帽子
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(4, 0), CV2(4.2, 0.6), CV2(2.2, 0.8), CV2(2.0, 3.5), CV2(0, 3.5)], segments: 18,
                                      R(.knit(0x3A3A3C))), at: CV3(0, 66, 0)))
        return K.merge(parts)
    }

    /// 傘立て（陶器の筒・傘 2）
    static func umbrellaStand() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.vessel(outer: [CV2(0, 0), CV2(4.2, 0), CV2(4.6, 2), CV2(4.4, 22), CV2(4.0, 24), CV2(0, 24)],
                              inner: [CV2(0, 0.5), CV2(3.6, 0.5), CV2(4.0, 2), CV2(3.8, 22), CV2(0, 22)], segments: 24, R(.ceramic(0xE8E2D4))))
        for (x, yaw, c) in [(-1.2, 0.15, 0x1A1A1A as UInt32), (1.2, -0.25, 0x5A2018)] {
            parts.append(K.tube([CV3(x, 4, 0), CV3(x + yaw, 30, yaw * 0.5)], radius: 0.4, sides: 8, R(.painted(c))))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.4, 0), CV2(1.9, 1.0), CV2(1.5, 3.2), CV2(0, 3.2)], segments: 12, R(.painted(c))),
                                  at: CV3(x + yaw, 30, yaw * 0.5)))
            parts.append(K.tube([CV3(x + yaw, 32.8, yaw * 0.5), CV3(x + yaw + 2.2, 34.5, yaw * 0.5 + 0.6)], radius: 0.22, sides: 5, R(.wood(.oak))))
        }
        return K.merge(parts)
    }

    /// 踏み台（2 段と取っ手）
    static func stepStool() -> CamperMesh {
        var parts: [CamperMesh] = []
        let pine = R(.wood(.pine))
        parts.append(K.block(CV3(18, 8, 12), at: .zero, radius: 0.4, pine))
        parts.append(K.block(CV3(14, 8, 10), at: CV3(0, 8, -1), radius: 0.4, pine))
        parts.append(K.block(CV3(16, 1.2, 11), at: CV3(0, 8, 0.5), radius: 0.25, R(.wornWood(.pine))))
        parts.append(K.block(CV3(12, 1.2, 9), at: CV3(0, 16, -0.5), radius: 0.25, R(.wornWood(.pine))))
        parts.append(K.tube([CV3(-6, 16.5, -4), CV3(-6, 20, -4), CV3(6, 20, -4), CV3(6, 16.5, -4)], radius: 0.4, sides: 6, R(.iron)))
        return K.merge(parts)
    }

    /// 洗濯かご（籐・蓋）
    static func laundryHamper() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.vessel(outer: [CV2(0, 0), CV2(7, 0), CV2(8.2, 3), CV2(8.5, 22), CV2(8.0, 24), CV2(0, 24)],
                              inner: [CV2(0, 0.5), CV2(6.4, 0.5), CV2(7.6, 3), CV2(7.9, 22), CV2(0, 22)], segments: 28, R(.wicker)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(8.2, 0), CV2(8.4, 1.2), CV2(4, 2.2), CV2(0, 2.2)], segments: 28, R(.wicker)),
                              at: CV3(0, 24, 0)))
        parts.append(K.placed(K.block(CV3(4, 0.6, 1.2), at: .zero, radius: 0.2, R(.wood(.oak))), at: CV3(0, 26.2, 0)))
        parts.append(K.placed(K.roundedBox(CV3(6, 2, 5), radius: 0.8, segments: 2, puff: 0.4, R(.knit(0xE8E1D2))), at: CV3(0, 20, 0)))
        return K.merge(parts)
    }

    // MARK: 鏡（壁）

    /// 姿見（細い木枠の縦長・2 段）
    static func fullLengthMirror() -> CamperMesh {
        var parts: [CamperMesh] = []
        let c = CV3(0, 20, 0.3)
        let ring = K.roundedRect(14, 36, r: 0.6, steps: 4)
        let hole = CamperPolygon.cw(K.roundedRect(11.5, 33.5, r: 0.3, steps: 4))
        parts.append(K.placed(CamperMeshKit.extrude(ring, holes: [hole], depth: 1.2, front: R(.wood(.oak)), side: R(.wornWood(.oak)), bevel: 0.3),
                              at: c + CV3(0, 0, 1.2)))
        parts.append(K.placed(K.panel(width: 11.5, height: 33.5, R(.chrome)), at: c + CV3(0, 0, 0.55)))
        parts.append(K.placed(K.panel(width: 13, height: 35, R(.painted(0x3A3430))), at: c + CV3(0, 0, 0.15)))
        for y in stride(from: 4.0, through: 36.0, by: 3.0) {
            parts.append(K.block(CV3(0.5, 1.6, 0.5), at: CV3(-6.8, y, 1.8), radius: 0.1, R(.brass)))
            parts.append(K.block(CV3(0.5, 1.6, 0.5), at: CV3(6.8, y, 1.8), radius: 0.1, R(.brass)))
        }
        parts.append(K.block(CV3(15, 1.2, 2.0), at: CV3(0, 1.5, 1.3), radius: 0.3, R(.wornWood(.oak))))
        parts.append(K.tube(K.roundedRect(14.0, 36.0, r: 0.6).map { CV3($0.x, 20 + $0.y, 2.15) }, radius: 0.12, sides: 4, closed: true, R(.agedBrass)))
        return K.merge(parts)
    }

    /// 丸い真鍮鏡
    static func roundBrassMirror() -> CamperMesh {
        var parts: [CamperMesh] = []
        let c = CV3(0, 10, 0)
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(K.disc(radius: 4.8, height: 1.0, bevel: 0.3, segments: 32, R(.brass)), at: c, rotation: toWall))
        parts.append(K.placed(K.ellipsePanel(rx: 4.0, ry: 4.0, R(.chrome)), at: c + CV3(0, 0, 0.7)))
        parts.append(K.tube(K.arc(center: c + CV3(0, 0, 0.85), radius: 4.3, from: 0, to: 2 * .pi, steps: 32).map { CV3($0.x, $0.y, 0.85) },
                            radius: 0.3, sides: 6, closed: true, R(.agedBrass)))
        parts.append(K.placed(K.sphere(radius: 0.45, segments: 8, R(.brass)), at: c + CV3(0, 5.1, 0.9)))
        return K.merge(parts)
    }

    /// 三面鏡（中央と折れる翼）。1 段（高さ ≤ 21）
    static func triFoldMirror() -> CamperMesh {
        var parts: [CamperMesh] = []
        func panel(at x: Double, yaw: Double, w: Double) {
            let c = CV3(x, 10, 1.2)
            let q = CQuat.axisAngle(CV3(0, 1, 0), yaw)
            let ring = K.roundedRect(w, 16, r: 0.35, steps: 2)
            let hole = CamperPolygon.cw(K.roundedRect(w - 1.8, 14, r: 0.2, steps: 2))
            let frame = CamperMeshKit.extrude(ring, holes: [hole], depth: 0.9, front: R(.wood(.walnut)), side: R(.wood(.walnut)), bevel: 0.2)
            parts.append(K.placed(frame, at: c + q.rotate(CV3(0, 0, 0.9)), rotation: q))
            parts.append(K.placed(K.panel(width: w - 1.8, height: 14, R(.chrome)), at: c + q.rotate(CV3(0, 0, 0.4)), rotation: q))
        }
        panel(at: 0, yaw: 0, w: 9)
        panel(at: -8.2, yaw: 0.35, w: 7)
        panel(at: 8.2, yaw: -0.35, w: 7)
        return K.merge(parts)
    }

    /// ひげ剃り鏡（伸びる腕）
    static func shavingMirror() -> CamperMesh {
        var parts: [CamperMesh] = []
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(K.disc(radius: 1.8, height: 0.5, bevel: 0.15, segments: 14, R(.brass)), at: CV3(0, 12, 0), rotation: toWall))
        let j1 = CV3(0, 12, 4), j2 = CV3(3, 14, 8)
        parts.append(K.tube([CV3(0, 12, 0.5), j1], radius: 0.35, sides: 6, R(.brass)))
        parts.append(K.tube([j1, j2], radius: 0.35, sides: 6, R(.brass)))
        for j in [j1, j2] { parts.append(K.placed(K.sphere(radius: 0.55, segments: 8, R(.brass)), at: j)) }
        parts.append(K.placed(K.disc(radius: 3.4, height: 0.7, bevel: 0.2, segments: 24, R(.brass)), at: j2 + CV3(0, 0, 1.2), rotation: toWall))
        parts.append(K.placed(K.ellipsePanel(rx: 2.8, ry: 2.8, R(.chrome)), at: j2 + CV3(0, 0, 1.6)))
        return K.merge(parts)
    }

    // MARK: 趣味

    /// カメラ棚（ボディとレンズ）
    static func cameraShelf() -> CamperMesh {
        var parts: [CamperMesh] = []
        parts.append(K.block(CV3(28, 1.5, 7), at: CV3(0, 8, 3.5), radius: 0.3, R(.wornWood(.oak))))
        for x in [-9.0, 9.0] {
            parts.append(K.tube([CV3(x, 0.5, 0.8), CV3(x, 7.5, 6)], radius: 0.28, sides: 5, R(.iron)))
        }
        // カメラボディ
        for (x, c) in [(-8.0, 0x1A1A1A as UInt32), (0.0, 0x2A2A2C), (8.0, 0x1E1E20)] {
            parts.append(K.block(CV3(5.5, 3.8, 3.5), at: CV3(x, 9.5, 3.2), radius: 0.4, R(.painted(c))))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.4, 0), CV2(1.5, 2.8), CV2(1.2, 3.2), CV2(0, 3.2)], segments: 14, R(.chrome)),
                                  at: CV3(x, 10.5, 5.2), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        }
        // レンズ単体
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.1, 0), CV2(1.2, 4.5), CV2(0, 4.5)], segments: 12, R(.painted(0x141414))),
                              at: CV3(-3, 9.5, 3), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2)))
        return K.merge(parts)
    }

    /// 釣竿掛け
    static func rodRack() -> CamperMesh {
        var parts: [CamperMesh] = []
        for y in [6.0, 14.0] {
            parts.append(K.block(CV3(28, 1.2, 3.5), at: CV3(0, y, 1.8), radius: 0.25, R(.wood(.cedar))))
        }
        for x in [-10.0, 0.0, 10.0] {
            parts.append(K.tube([CV3(x, 0.8, 0.6), CV3(x, 6, 1.5)], radius: 0.25, sides: 5, R(.iron)))
            parts.append(K.tube([CV3(x - 0.3, 7.2, 2.2), CV3(x + 0.3, 18.5, 2.8)], radius: 0.35, sides: 6, R(.painted(0x2F5A3C))))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.6, 0), CV2(0.5, 2), CV2(0, 2)], segments: 8, R(.wood(.oak))),
                                  at: CV3(x, 8.5, 2.3)))
        }
        return K.merge(parts)
    }

    /// スキー板（壁掛け・2 段）
    static func skiMount() -> CamperMesh {
        var parts: [CamperMesh] = []
        for x in [-4.0, 4.0] {
            parts.append(K.block(CV3(3.0, 34, 1.2), at: CV3(x, 3, 1.6), radius: 0.35, R(.painted(0xE8E2D4))))
            parts.append(K.block(CV3(2.6, 3.5, 1.4), at: CV3(x, 34, 1.7), radius: 0.4, R(.painted(0xC9584A))))
            parts.append(K.block(CV3(4.0, 2.0, 1.6), at: CV3(x, 15, 2.0), radius: 0.25, R(.iron)))
        }
        for x in [-6.5, 6.5] {
            parts.append(K.tube([CV3(x, 5, 1.4), CV3(x, 30, 1.4)], radius: 0.3, sides: 6, R(.iron)))
            parts.append(K.placed(K.sphere(radius: 0.55, segments: 8, R(.iron)), at: CV3(x, 30.8, 1.4)))
        }
        parts.append(K.block(CV3(11, 1.4, 2.0), at: CV3(0, 9, 1.2), radius: 0.2, R(.wood(.oak))))
        parts.append(K.block(CV3(11, 1.4, 2.0), at: CV3(0, 27, 1.2), radius: 0.2, R(.wood(.oak))))
        return K.merge(parts)
    }

    /// 画架（壁に立て掛けたキャンバス・2 段）
    static func wallEasel() -> CamperMesh {
        var parts: [CamperMesh] = []
        for s in [-1.0, 1.0] {
            parts.append(K.tube([CV3(s * 5, 1.0, 0.5), CV3(s * 1.8, 16, 3.5), CV3(0, 34, 4.5)], radius: 0.4, sides: 6, R(.wood(.pine))))
        }
        parts.append(K.tube([CV3(0, 1.0, 0.6), CV3(0, 32, 4.6)], radius: 0.35, sides: 6, R(.wood(.pine))))
        parts.append(K.block(CV3(12, 1.1, 1.8), at: CV3(0, 17, 4.0), radius: 0.2, R(.wood(.pine))))
        parts.append(K.block(CV3(11, 14, 0.7), at: CV3(0, 22, 5.5), radius: 0.2, R(.wood(.birch))))
        parts.append(K.placed(K.panel(width: 10, height: 12.5, R(.canvas(0xF2EEE4))), at: CV3(0, 22.5, 5.95)))
        parts.append(K.placed(K.panel(width: 7, height: 5, R(.painted(0x6E8FA3))), at: CV3(0, 23, 6.05)))
        return K.merge(parts)
    }
}
