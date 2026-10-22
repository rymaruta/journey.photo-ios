import Foundation

// 家具の形・4 の組（2026-10-20）。椅子・机の脚違いではなく、用途そのものが違う分類
// （音・台所道具・便利・鏡・趣味・カメラ）を一点ずつ作り込む。owner「色んなの作りたい」・「カメラ棚あるならカメラも」。

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
        case "camera.rangefinder": return rangefinder()
        case "camera.slr": return slrCamera()
        case "camera.instant": return instantCamera()
        case "camera.twin_lens": return twinLens()
        default: return moreMesh5(id)
        }
    }

    static func moreLamp4(_ id: String) -> (position: CV3, intensity: Double, range: Double)? {
        switch id {
        case "audio.travel_radio": return (CV3(0, 10, 4), 0.25, 45)
        default: return moreLamp5(id)
        }
    }

    // MARK: 音

    /// 蓄音機（木の箱・ターンテーブル・ラッパ・アーム）
    static func phonograph() -> CamperMesh {
        // 2026-10-21 作り直し（Mac run 596）: ラッパが片面の旋盤で、口の内側が裏向きに消えて「木の箱だけ」に見えた。
        // 朝顔のラッパ（外と内の両面・継ぎ目の筋 8・縁の巻き）を後ろの支柱から前へ、箱は框と面取りの板・脚 4・横の巻き手、
        // 盤は溝の輪とラベル、針の腕（サウンドボックス）
        var parts: [CamperMesh] = []
        let walnut = R(.wood(.walnut)), worn = R(.wornWood(.walnut)), brass = R(.brass), aged = R(.agedBrass)
        // 脚 4（丸い玉足）と箱（下の框・胴・上の框）
        for (x, z) in [(-9.5, -6.5), (9.5, -6.5), (-9.5, 6.5), (9.5, 6.5)] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.9, 0.2), CV2(1.1, 0.9), CV2(0.8, 1.6), CV2(0, 1.6)], segments: 12, worn),
                                  at: CV3(x, 0, z)))
        }
        parts.append(K.block(CV3(22, 1.4, 16), at: CV3(0, 1.6, 0), radius: 0.5, worn))
        parts.append(K.block(CV3(20.6, 8.4, 14.6), at: CV3(0, 3.0, 0), radius: 0.4, walnut))
        // 胴の面の鏡板（少し凹んだ枠）
        for z in [-7.35, 7.35] {
            parts.append(K.tube(K.roundedRect(16, 6, r: 0.6).map { CV3($0.x, 7.2 + $0.y, z) }, radius: 0.16, sides: 4, closed: true, worn))
        }
        parts.append(K.block(CV3(22, 1.2, 16), at: CV3(0, 11.4, 0), radius: 0.4, worn))
        // 横の巻き手（軸・腕・木の握り）
        parts.append(K.tube([CV3(10.4, 7.5, 0), CV3(12.2, 7.5, 0)], radius: 0.3, sides: 8, aged))
        parts.append(K.tube([CV3(12.2, 7.5, 0), CV3(12.2, 4.6, 1.6)], radius: 0.25, sides: 6, aged))
        parts.append(K.tube([CV3(12.2, 4.6, 1.6), CV3(13.8, 4.6, 1.6)], radius: 0.45, sides: 8, R(.wood(.darkOak))))
        // 盤（受け・黒い盤の溝の輪・赤いラベル・軸）
        parts.append(K.placed(K.disc(radius: 6.4, height: 0.4, bevel: 0.1, segments: 32, R(.castIron)), at: CV3(-2.5, 12.6, 0)))
        parts.append(K.placed(K.disc(radius: 6.0, height: 0.22, bevel: 0.06, segments: 40, R(.painted(0x141414))), at: CV3(-2.5, 13.0, 0)))
        for r in stride(from: 2.6, through: 5.6, by: 0.75) {
            parts.append(K.tube(K.arc(center: .zero, radius: r, from: 0, to: 2 * .pi, steps: 36).map { CV3($0.x - 2.5, 13.24, $0.y) },
                                radius: 0.03, sides: 3, closed: true, R(.painted(0x2A2A2C))))
        }
        parts.append(K.placed(K.disc(radius: 1.9, height: 0.05, bevel: 0.01, segments: 24, R(.painted(0x9A2A22))), at: CV3(-2.5, 13.22, 0)))
        parts.append(K.placed(K.disc(radius: 0.22, height: 0.6, bevel: 0.05, segments: 8, R(.chrome)), at: CV3(-2.5, 13.2, 0)))
        // 後ろの支柱と針の腕（太い管が盤の上で曲がり、先に丸いサウンドボックス）
        let post = CV3(6.5, 12.6, -5.0)
        parts.append(K.placed(K.disc(radius: 1.3, height: 0.6, bevel: 0.15, segments: 16, aged), at: post))
        parts.append(K.tube([post + CV3(0, 0.6, 0), post + CV3(0, 3.2, 0)], radius: 0.55, sides: 10, brass))
        parts.append(K.tube([post + CV3(0, 3.2, 0), post + CV3(-2.5, 3.6, 2.5), CV3(0.6, 15.6, 1.2)], radius: 0.42, sides: 10, brass))
        let box = CV3(0.2, 15.0, 1.6)
        parts.append(K.placed(K.disc(radius: 1.25, height: 0.7, bevel: 0.2, segments: 18, brass), at: box,
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.placed(K.disc(radius: 0.9, height: 0.1, bevel: 0.02, segments: 16, R(.mica)), at: box + CV3(0, 0, 0.72),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        parts.append(K.tube([box + CV3(0, -1.2, 0), CV3(0.2, 13.35, 1.6)], radius: 0.06, sides: 4, R(.chrome)))
        // 朝顔のラッパ: 支柱の上の曲がりから、前上へ開く（外は真鍮・内は磨いた真鍮の両面。継ぎ目の筋と縁の巻き）
        let base = post + CV3(0, 3.2, 0)
        let neck: [CV3] = [base, base + CV3(0, 3.0, -0.4), base + CV3(-1.2, 5.6, 0.4)]
        parts.append(K.tube(neck, radius: 0.75, sides: 12, brass))
        let mouth = base + CV3(-1.2, 5.6, 0.4)
        let q = CQuat.rotation(from: CV3(0, 1, 0), to: CV3(-0.55, 0.62, 0.56).normalized)
        let outer: [CV2] = [CV2(0.8, 0), CV2(1.1, 2.5), CV2(1.8, 5.5), CV2(3.0, 8.5), CV2(5.0, 11.2), CV2(7.6, 13.0), CV2(9.0, 13.6)]
        let inner = outer.map { CV2(max(0.2, $0.x - 0.18), $0.y + 0.05) }
        parts.append(K.placed(K.lathe(outer, segments: 32, brass, capStart: false, capEnd: false), at: mouth, rotation: q))
        parts.append(K.placed(K.inverted(K.lathe(inner, segments: 32, R(.agedBrass), capStart: false, capEnd: false)), at: mouth, rotation: q))
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            let seam = outer.map { q.rotate(CV3(cos(a) * ($0.x + 0.05), $0.y, sin(a) * ($0.x + 0.05))) + mouth }
            parts.append(K.tube(seam, radius: 0.07, sides: 4, aged))
        }
        parts.append(K.tube(K.arc(center: .zero, radius: 9.0, from: 0, to: 2 * .pi, steps: 40)
                                .map { q.rotate(CV3($0.x, 13.6, $0.y)) + mouth }, radius: 0.22, sides: 6, closed: true, aged))
        return K.merge(parts)
    }

    /// ギタースタンド（木の胴を立て掛ける脚と支え）
    /// ギタースタンド（鉄脚・受け・8 の字の胴・サウンドホール・ブリッジ・フレット・糸・ヘッド）
    static func guitarStand() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak)), dark = R(.wood(.darkOak)), iron = R(.iron)
        let tilt = CQuat.axisAngle(CV3(1, 0, 0), -0.22)
        // スタンド（A 字脚・底の横棒・首の受け）
        for s in [-1.0, 1.0] {
            parts.append(K.tube([CV3(s * 7.0, 0.4, 5.5), CV3(s * 2.2, 26, -0.5), CV3(s * 1.4, 50, -1.8)],
                                radius: 0.5, sides: 8, iron))
            parts.append(K.tube([CV3(s * 7.0, 0.4, 5.5), CV3(s * 6.5, 0.4, -4.5)], radius: 0.42, sides: 7, iron))
        }
        parts.append(K.tube([CV3(-7.0, 0.4, 5.5), CV3(7.0, 0.4, 5.5)], radius: 0.4, sides: 7, iron))
        parts.append(K.tube([CV3(-5.5, 0.4, -3.5), CV3(5.5, 0.4, -3.5)], radius: 0.35, sides: 6, iron))
        // 胴の受け（ゴム）
        parts.append(K.tube([CV3(-4.5, 20, 2.2), CV3(4.5, 20, 2.2)], radius: 0.55, sides: 8, R(.knit(0x2A2A2C))))
        parts.append(K.tube([CV3(-1.8, 50, -1.8), CV3(1.8, 50, -1.8)], radius: 0.45, sides: 7, iron))
        parts.append(K.tube(K.arc(center: CV3(0, 50, -1.0), radius: 2.2, from: .pi * 0.2, to: .pi * 0.8, steps: 10)
                                .map { CV3($0.x, $0.y, -1.0) }, radius: 0.35, sides: 6, R(.knit(0x2A2A2C))))
        // 8 の字に近い胴（下ぶくれ＋上ぶくれ）
        let body = K.lathe([CV2(0, 0), CV2(4.2, 0.6), CV2(7.4, 5), CV2(7.8, 10), CV2(6.6, 14),
                            CV2(5.2, 17), CV2(6.4, 21), CV2(6.0, 25), CV2(3.6, 28), CV2(2.2, 29.5), CV2(0, 29.5)],
                           segments: 32, oak)
        parts.append(K.placed(K.scaled(body, CV3(1, 1, 0.42)), at: CV3(0, 16.5, 1.8), rotation: tilt))
        // サウンドホールとロゼッタ
        parts.append(K.placed(K.disc(radius: 2.35, height: 0.35, bevel: 0.1, segments: 20, dark), at: CV3(0, 31.5, 3.1),
                              rotation: tilt))
        parts.append(K.tube(K.arc(center: CV3(0, 31.5, 3.2), radius: 2.5, from: 0, to: 2 * .pi, steps: 24),
                            radius: 0.12, sides: 5, closed: true, R(.agedBrass)))
        // ブリッジとサドル
        parts.append(K.placed(K.block(CV3(5.2, 0.7, 1.2), at: .zero, radius: 0.15, dark), at: CV3(0, 24.5, 3.4), rotation: tilt))
        parts.append(K.placed(K.block(CV3(4.6, 0.25, 0.35), at: .zero, radius: 0.05, R(.ceramic(0xE8E2D4))),
                              at: CV3(0, 24.9, 3.7), rotation: tilt))
        // ネック・フレット・ヘッド・糸巻き
        parts.append(K.placed(K.block(CV3(2.0, 30, 1.3), at: .zero, radius: 0.28, oak), at: CV3(0, 47, 3.8),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.18)))
        for i in 0..<12 {
            let y = 36.0 + Double(i) * 2.2
            parts.append(K.placed(K.block(CV3(1.9, 0.12, 0.2), at: .zero, radius: 0.03, R(.chrome)),
                                  at: CV3(0, y, 4.35), rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.18)))
        }
        parts.append(K.placed(K.block(CV3(4.8, 5.5, 1.5), at: .zero, radius: 0.4, R(.wornWood(.oak))), at: CV3(0, 64.5, 4.5),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), -0.12)))
        for x in [-1.5, -0.5, 0.5, 1.5] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.35, 0), CV2(0.4, 0.8), CV2(0.25, 1.2), CV2(0, 1.2)],
                                          segments: 8, R(.brass)), at: CV3(x, 66.2, 5.2),
                                  rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        }
        // 糸 6
        for i in 0..<6 {
            let x = -1.25 + Double(i) * 0.5
            parts.append(K.tube([CV3(x, 25.0, 3.75), CV3(x * 0.4, 48, 4.5), CV3(x, 65.5, 5.1)],
                                radius: 0.04, sides: 3, R(.chrome)))
        }
        return K.merge(parts)
    }

    /// 棚のスピーカー（チークの箱・角の面取り・布のグリル・ウーファー／ツイーター・バスレフ・真鍮の銘板）
    static func cabinetSpeaker() -> CamperMesh {
        var parts: [CamperMesh] = []
        let teak = R(.wood(.teak)), worn = R(.wornWood(.teak)), cloth = R(.knit(0xD8CDB8))
        let toFront = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        // 胴（角を丸めた木箱・後面は少し浅い）
        parts.append(K.block(CV3(16, 28, 12), at: .zero, radius: 0.7, teak))
        parts.append(K.block(CV3(15.2, 1.1, 11.4), at: CV3(0, 27.2, 0), radius: 0.35, worn))
        // 前面の布グリル（縁の木枠つき）
        parts.append(K.block(CV3(14.2, 24.5, 0.55), at: CV3(0, 1.8, 5.95), radius: 0.2, cloth))
        let grilleRing = K.roundedRect(14.6, 25.0, r: 0.5, steps: 3)
        parts.append(K.tube(grilleRing.map { CV3($0.x, 14.0 + $0.y, 6.35) }, radius: 0.22, sides: 5, closed: true, worn))
        // グリルの縦糸（布の目）
        for k in 0..<9 {
            let x = -6.0 + Double(k) * 1.5
            parts.append(K.tube([CV3(x, 3.2, 6.35), CV3(x, 25.2, 6.35)], radius: 0.06, sides: 4, cloth))
        }
        // ウーファー（コーン・縁のサラウンド・センターキャップ）
        parts.append(K.placed(K.disc(radius: 4.8, height: 0.55, bevel: 0.18, segments: 24, R(.iron)), at: CV3(0, 16.5, 6.5), rotation: toFront))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.6, 0), CV2(3.2, 0.6), CV2(1.4, 1.1), CV2(0, 1.1)], segments: 22, R(.painted(0x1A1A1A))),
                              at: CV3(0, 16.5, 6.55), rotation: toFront))
        parts.append(K.placed(K.disc(radius: 1.1, height: 0.35, bevel: 0.1, segments: 14, R(.chrome)), at: CV3(0, 16.5, 7.55), rotation: toFront))
        // ツイーター
        parts.append(K.placed(K.disc(radius: 2.0, height: 0.45, bevel: 0.12, segments: 18, R(.iron)), at: CV3(0, 7.2, 6.5), rotation: toFront))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.4, 0), CV2(1.2, 0.5), CV2(0.4, 0.75), CV2(0, 0.75)], segments: 16, R(.painted(0x2A2A2C))),
                              at: CV3(0, 7.2, 6.55), rotation: toFront))
        // バスレフポート（上面の円筒）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.5, 0), CV2(1.55, 0.3), CV2(1.5, 3.4), CV2(1.35, 3.6), CV2(0, 3.6)],
                                      segments: 16, R(.painted(0x141414)), capStart: false), at: CV3(0, 24.2, 3.8)))
        // 真鍮の銘板と角の留め
        parts.append(K.block(CV3(3.2, 1.0, 0.25), at: CV3(0, 25.6, 6.15), radius: 0.12, R(.brass)))
        for (x, y) in [(-7.2, 3.0), (7.2, 3.0), (-7.2, 25.5), (7.2, 25.5)] {
            parts.append(K.placed(K.sphere(radius: 0.28, segments: 8, R(.agedBrass)), at: CV3(x, y, 6.4)))
        }
        // 小さな木の足
        for (x, z) in [(-6.0, -4.0), (6.0, -4.0), (-6.0, 4.0), (6.0, 4.0)] {
            parts.append(K.placed(K.leg(bottom: 0.55, top: 0.7, height: 1.0, teak), at: CV3(x, -0.05, z)))
        }
        return K.merge(parts)
    }

    // MARK: 台所道具

    /// ドリップスタンド（脚付きの木台・真鍮の柱と腕・陶器のドリッパー・ガラスのサーバー・カップ）
    static func dripStand() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak)), brass = R(.brass), china = R(.ceramic(0xE8E2D4))
        // 台（先の細る脚・縁）
        for (x, z) in [(-5.5, -4.5), (5.5, -4.5), (-5.5, 4.5), (5.5, 4.5)] {
            parts.append(K.placed(K.leg(bottom: 0.55, top: 0.75, height: 3.2, oak), at: CV3(x, 0, z)))
        }
        parts.append(K.block(CV3(14.5, 1.6, 12.5), at: CV3(0, 3.2, 0), radius: 0.35, oak))
        parts.append(K.block(CV3(14.8, 0.35, 0.45), at: CV3(0, 4.7, 6.1), radius: 0.1, R(.wornWood(.oak))))
        // 柱と真鍮の腕（継ぎ目の輪）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.15, 0), CV2(1.05, 18), CV2(1.2, 20), CV2(0, 20)], segments: 14, oak),
                              at: CV3(-4.2, 4.8, 0)))
        for y in [10.0, 18.0] {
            parts.append(K.placed(K.disc(radius: 1.35, height: 0.45, bevel: 0.12, segments: 14, brass), at: CV3(-4.2, y, 0)))
        }
        parts.append(K.tube([CV3(-4.2, 22.5, 0), CV3(0.5, 24.2, 0), CV3(4.2, 22.8, 0)], radius: 0.38, sides: 8, brass))
        parts.append(K.placed(K.sphere(radius: 0.55, segments: 8, brass), at: CV3(4.2, 22.8, 0)))
        // ドリッパー（リブ）とフィルター紙
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.4, 0), CV2(2.6, -3.8), CV2(0.7, -5.4), CV2(0, -5.4)], segments: 22, china),
                              at: CV3(4.2, 22.2, 0)))
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            parts.append(K.tube([CV3(4.2 + cos(a) * 3.0, 21.5, sin(a) * 3.0), CV3(4.2 + cos(a) * 0.9, 17.2, sin(a) * 0.9)],
                                radius: 0.08, sides: 4, R(.ceramic(0xD8D0C4))))
        }
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.8, 0), CV2(2.0, -2.8), CV2(0, -2.8)], segments: 16, R(.paper), capStart: false),
                              at: CV3(4.2, 21.8, 0)))
        // サーバー（注ぎ口・持ち手）
        parts.append(K.placed(K.vessel(outer: [CV2(0, 0), CV2(3.5, 0), CV2(3.9, 1.8), CV2(3.3, 8.2), CV2(1.7, 10.2), CV2(1.7, 11.2), CV2(0, 11.2)],
                                       inner: [CV2(0, 0.4), CV2(3.1, 0.4), CV2(3.5, 1.8), CV2(3.0, 7.8), CV2(1.5, 9.8), CV2(0, 9.8)],
                                       segments: 24, R(.clearGlass)), at: CV3(4.2, 4.9, 0)))
        parts.append(K.tube([CV3(4.2, 15.8, 0), CV3(6.8, 17.4, 0.4), CV3(7.6, 14.8, 0.6)], radius: 0.32, sides: 6, R(.clearGlass)))
        parts.append(K.tube([CV3(1.0, 10.5, 0), CV3(-0.4, 12.5, 0), CV3(1.0, 14.5, 0)], radius: 0.28, sides: 6, R(.wood(.walnut))))
        // 横のカップ
        parts.append(CamperRoomShapes.mug(at: CV3(-4.5, 4.9, 3.8), body: china, rim: R(.ceramic(0xC9B79A)), yaw: -0.8))
        return K.merge(parts)
    }

    /// 旅のラジオ（革張り・縫い目・網のスピーカー・ダイヤルの刻み・持ち手）
    static func travelRadio() -> CamperMesh {
        var parts: [CamperMesh] = []
        let leather = R(.leather(0x5E3A24)), dark = R(.leather(0x3E2618)), brass = R(.brass)
        let toFront = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.block(CV3(14.2, 10.2, 7.2), at: CV3(0, 0, 0), radius: 0.75, leather))
        // 縫い目の縁
        let stitch = K.roundedRect(13.6, 9.6, r: 0.6, steps: 3)
        parts.append(K.tube(stitch.map { CV3($0.x, 5.1 + $0.y, 3.55) }, radius: 0.08, sides: 4, closed: true, dark))
        parts.append(K.block(CV3(12.2, 7.6, 0.35), at: CV3(0, 1.2, 3.55), radius: 0.15, R(.painted(0x2A2B2D))))
        // スピーカー網（縦横）
        for col in 0..<7 {
            let x = -5.1 + Double(col) * 1.7
            parts.append(K.tube([CV3(x, 2.0, 3.8), CV3(x, 8.0, 3.8)], radius: 0.07, sides: 4, R(.iron)))
        }
        for row in 0..<5 {
            let y = 2.2 + Double(row) * 1.45
            parts.append(K.tube([CV3(-5.2, y, 3.8), CV3(5.2, y, 3.8)], radius: 0.06, sides: 4, R(.iron)))
        }
        // チューニングダイヤル（刻み）とボリューム
        parts.append(K.placed(K.disc(radius: 1.9, height: 0.55, bevel: 0.15, segments: 18, brass), at: CV3(3.6, 5.2, 3.85), rotation: toFront))
        parts.append(K.placed(K.disc(radius: 1.35, height: 0.25, bevel: 0.08, segments: 16, R(.painted(0xEDE8DE))),
                              at: CV3(3.6, 5.2, 4.2), rotation: toFront))
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            parts.append(K.block(CV3(0.12, 0.45, 0.12), at: CV3(3.6 + cos(a) * 1.55, 5.2 + sin(a) * 1.55, 4.05), radius: 0.03, R(.iron)))
        }
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.7, 0), CV2(0.75, 0.25), CV2(0.55, 0.55), CV2(0, 0.55)], segments: 12, brass),
                              at: CV3(-4.2, 7.8, 3.7), rotation: toFront))
        parts.append(K.placed(K.disc(radius: 0.4, height: 0.35, bevel: 0.1, segments: 10, R(.bulb)),
                              at: CV3(-4.2, 5.5, 3.9), rotation: toFront))
        // 持ち手（リベットつき）
        parts.append(K.tube([CV3(-5.2, 10.0, 0), CV3(-5.2, 12.8, 0), CV3(5.2, 12.8, 0), CV3(5.2, 10.0, 0)],
                            radius: 0.38, sides: 7, dark))
        for x in [-5.2, 5.2] {
            parts.append(K.placed(K.sphere(radius: 0.35, segments: 8, brass), at: CV3(x, 10.0, 0)))
        }
        return K.merge(parts)
    }

    /// まな板台（先の細る脚・胴の引き出し・真鍮の取っ手・厚いまな板と汁溝・上の壺）
    static func boardCart() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak)), worn = R(.wornWood(.oak)), brass = R(.agedBrass)
        // 先の細る脚 4 と足元の桟
        for (x, z) in [(-11.0, -6.0), (11.0, -6.0), (-11.0, 6.0), (11.0, 6.0)] {
            parts.append(K.placed(K.leg(bottom: 0.85, top: 1.15, height: 14, oak), at: CV3(x, 0, z)))
        }
        parts.append(K.tube([CV3(-11, 4.5, -6), CV3(11, 4.5, -6)], radius: 0.35, sides: 6, oak))
        parts.append(K.tube([CV3(-11, 4.5, 6), CV3(11, 4.5, 6)], radius: 0.35, sides: 6, oak))
        parts.append(K.tube([CV3(-11, 4.5, -6), CV3(-11, 4.5, 6)], radius: 0.3, sides: 6, oak))
        parts.append(K.tube([CV3(11, 4.5, -6), CV3(11, 4.5, 6)], radius: 0.3, sides: 6, oak))
        // 胴と引き出しの前板
        parts.append(K.block(CV3(24, 10, 14), at: CV3(0, 14, 0), radius: 0.55, oak))
        parts.append(K.block(CV3(21.5, 7.8, 0.9), at: CV3(0, 15.2, 7.05), radius: 0.3, worn))
        // 真鍮の取っ手（管の弓）
        parts.append(K.tube([CV3(-3.5, 19.2, 7.5), CV3(-3.5, 19.2, 8.6), CV3(3.5, 19.2, 8.6), CV3(3.5, 19.2, 7.5)],
                            radius: 0.28, sides: 7, brass))
        for x in [-3.5, 3.5] {
            parts.append(K.placed(K.sphere(radius: 0.35, segments: 8, brass), at: CV3(x, 19.2, 7.5)))
        }
        // 厚いまな板（縁の面取り・汁溝は細い管で溝の影）
        parts.append(K.block(CV3(24, 2.8, 14), at: CV3(0, 24, 0), radius: 0.45, worn))
        let groove = K.roundedRect(18.5, 9.5, r: 0.8, steps: 4)
        parts.append(K.tube(groove.map { CV3($0.x, 26.85, $0.y) }, radius: 0.12, sides: 5, closed: true, R(.wood(.darkOak))))
        // 陶器の壺と木べら
        parts.append(K.placed(K.vessel(outer: [CV2(0, 0), CV2(1.6, 0), CV2(1.8, 0.6), CV2(1.5, 4.2), CV2(1.1, 4.6), CV2(0, 4.6)],
                                       inner: [CV2(0, 0.35), CV2(1.35, 0.35), CV2(1.5, 0.6), CV2(1.25, 4.0), CV2(0, 4.0)],
                                       segments: 16, R(.ceramic(0xE8E2D4))), at: CV3(-6.5, 26.85, -3.0)))
        parts.append(K.tube([CV3(5.5, 26.9, -2.5), CV3(5.5, 30.5, -2.5)], radius: 0.22, sides: 6, oak))
        parts.append(K.placed(K.block(CV3(2.4, 0.35, 1.0), at: .zero, radius: 0.12, worn), at: CV3(5.5, 30.7, -2.5)))
        return K.merge(parts)
    }

    /// 食器の棚（白樺の枠・斜めの桟・皿とボウルとカップ）
    static func dishRack() -> CamperMesh {
        var parts: [CamperMesh] = []
        let birch = R(.wood(.birch)), worn = R(.wornWood(.birch))
        let ceramics: [UInt32] = [0xE8E2D4, 0xD9CFB8, 0xF2EEE4, 0xC9D4C8]
        // 台と側板（角を丸めた薄い板）
        parts.append(K.block(CV3(26, 1.8, 16), at: .zero, radius: 0.4, birch))
        for x in [-12.2, 12.2] {
            parts.append(K.block(CV3(1.3, 26, 14.5), at: CV3(x, 1.8, 0), radius: 0.3, birch))
        }
        // 天板の桟
        parts.append(K.block(CV3(24.5, 1.0, 14), at: CV3(0, 27.2, 0), radius: 0.25, worn))
        for row in 0..<3 {
            let y = 5.5 + Double(row) * 7.4
            // 棚板と斜めの皿受け桟
            parts.append(K.block(CV3(23.5, 0.7, 12.5), at: CV3(0, y, 0), radius: 0.2, birch))
            for k in 0..<7 {
                let x = -10.5 + Double(k) * 3.5
                parts.append(K.tube([CV3(x, y + 0.7, -5.5), CV3(x, y + 5.2, 5.0)], radius: 0.22, sides: 6, worn))
            }
            // 桟に立てた皿（見込みを前へ向けて立てる・2026-10-21: 上の面が下向きで消え、縁だけの灰の板に見えた）
            for k in 0..<5 {
                let x = -9.0 + Double(k) * 4.5
                let plate = CamperRoomShapes.plate(radius: 3.2, R(.ceramic(ceramics[(row + k) % 4])))
                let stand = CQuat.axisAngle(CV3(0, 1, 0), .pi / 2) * CQuat.axisAngle(CV3(0, 0, 1), 1.3)
                parts.append(K.placed(plate, at: CV3(x, y + 3.6, 0.6), rotation: stand))
            }
        }
        // 下段のボウルとカップ
        parts.append(K.placed(K.vessel(outer: [CV2(0, 0), CV2(2.6, 0), CV2(3.0, 0.8), CV2(2.7, 3.2), CV2(2.2, 3.5), CV2(0, 3.5)],
                                       inner: [CV2(0, 0.3), CV2(2.3, 0.3), CV2(2.6, 0.8), CV2(2.4, 3.0), CV2(0, 3.0)],
                                       segments: 18, R(.ceramic(0xE8E2D4))), at: CV3(-8.5, 6.2, -3.5)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.5, 0), CV2(1.7, 0.4), CV2(1.5, 3.0), CV2(1.7, 3.4), CV2(1.4, 3.6), CV2(0, 3.6)],
                                      segments: 14, R(.ceramic(0xF2EEE4))), at: CV3(8.0, 6.2, -3.8)))
        parts.append(K.tube([CV3(8.0, 8.5, -3.8), CV3(9.6, 9.2, -3.8), CV3(9.8, 7.8, -3.8)], radius: 0.18, sides: 5, R(.ceramic(0xF2EEE4))))
        return K.merge(parts)
    }

    /// ワインラック（松の枠・菱の格子・斜めの瓶・コルクと箔）
    static func wineRack() -> CamperMesh {
        var parts: [CamperMesh] = []
        let pine = R(.wood(.pine)), worn = R(.wornWood(.pine))
        let colors: [UInt32] = [0x3E1A24, 0x2A3A1E, 0x4A2018, 0x1E2A18, 0x5A2830, 0x2E2418]
        let tilt = CQuat.axisAngle(CV3(1, 0, 0), 0.88)
        // 外枠（側板・天板・底板）
        parts.append(K.block(CV3(16, 1.6, 14), at: .zero, radius: 0.4, pine))
        parts.append(K.block(CV3(16, 1.6, 14), at: CV3(0, 34.4, 0), radius: 0.4, pine))
        for x in [-7.4, 7.4] {
            parts.append(K.block(CV3(1.2, 34.4, 13.5), at: CV3(x, 1.6, 0), radius: 0.3, pine))
        }
        // 背面の薄い板
        parts.append(K.block(CV3(14.5, 32, 0.7), at: CV3(0, 2.2, -6.4), radius: 0.2, worn))
        // 菱の格子（管で組む）
        for row in 0..<4 {
            let y = 4.0 + Double(row) * 8.5
            parts.append(K.tube([CV3(-6.5, y, -5), CV3(6.5, y + 4.2, 5)], radius: 0.32, sides: 6, worn))
            parts.append(K.tube([CV3(6.5, y, -5), CV3(-6.5, y + 4.2, 5)], radius: 0.32, sides: 6, worn))
        }
        // 瓶の穴の輪（旋盤の短い筒）
        for row in 0..<3 {
            for col in 0..<2 {
                let x = -3.4 + Double(col) * 6.8
                let y = 7.0 + Double(row) * 9.5
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.35, 0), CV2(2.45, 0.4), CV2(2.35, 1.6), CV2(0, 1.6)],
                                              segments: 16, pine, capStart: false), at: CV3(x, y, 1.5), rotation: tilt))
                // 瓶本体・着色の中身・首・箔・コルク
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.05, 0), CV2(2.2, 1.5), CV2(1.95, 9.5), CV2(1.1, 11.5),
                                               CV2(0.95, 13.5), CV2(1.35, 14.2), CV2(0, 14.2)], segments: 16, R(.tintedGlass(0x24402A))),
                                      at: CV3(x, y, 2.0), rotation: tilt))
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.7, 0), CV2(1.7, 7.2), CV2(0, 7.2)], segments: 12,
                                              R(.tintedGlass(colors[row * 2 + col]))),
                                      at: CV3(x, y + 1.0, 2.9), rotation: tilt))
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.25, 0), CV2(1.25, 1.6), CV2(0, 1.6)], segments: 12, R(.brass)),
                                      at: CV3(x, y + 10.8, 8.8), rotation: tilt))
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.85, 0), CV2(0.9, 1.1), CV2(0, 1.1)], segments: 10, R(.wood(.oak))),
                                      at: CV3(x, y + 12.2, 9.9), rotation: tilt))
            }
        }
        return K.merge(parts)
    }

    // MARK: 便利な物

    /// コート掛け（重い台・旋盤の柱と輪飾り・枝のフック・掛けた上着・帽子）
    static func coatTree() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wood(.oak)), walnut = R(.wood(.walnut)), brass = R(.agedBrass)
        // 重い台（縁の面取り・真鍮の足）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(5.4, 0), CV2(5.6, 0.35), CV2(5.2, 1.1), CV2(4.9, 1.5), CV2(0, 1.5)],
                                      segments: 28, oak), at: .zero))
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + .pi / 4
            parts.append(K.placed(K.sphere(radius: 0.4, segments: 8, brass), at: CV3(cos(a) * 4.8, 0.45, sin(a) * 4.8)))
        }
        // 柱（下太・輪飾り 3）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.85, 0), CV2(1.7, 8), CV2(1.55, 40), CV2(1.45, 58), CV2(1.7, 62), CV2(1.9, 64), CV2(0, 64)],
                                      segments: 18, oak), at: CV3(0, 1.5, 0)))
        for y in [18.0, 36.0, 52.0] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.15, 0), CV2(2.25, 0.35), CV2(2.05, 0.7), CV2(0, 0.7)], segments: 16, walnut),
                                  at: CV3(0, y, 0)))
        }
        // 枝のフック（上ほど短い・先端の真鍮玉）
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi + 0.25
            let y = 46.0 + Double(k % 3) * 5.5
            let reach = 8.5 - Double(k % 3) * 0.6
            let tip = CV3(cos(a) * reach, y - 1.8, sin(a) * reach)
            parts.append(K.tube([CV3(cos(a) * 1.6, y, sin(a) * 1.6),
                                 CV3(cos(a) * reach * 0.55, y - 0.4, sin(a) * reach * 0.55), tip],
                                radius: 0.42, sides: 7, walnut))
            parts.append(K.placed(K.sphere(radius: 0.55, segments: 8, brass), at: tip))
        }
        // 掛けた上着（マス 2×2 に収まるよう、柱の近くへ）
        let coat = R(.velvet(0x2F4A5E))
        parts.append(K.placed(K.roundedBox(CV3(8.5, 2.0, 4.5), radius: 0.9, segments: 2, puff: 0.35, coat),
                              at: CV3(4.8, 52.5, 2.0), yaw: 0.25))
        parts.append(K.placed(K.drape(width: 8, height: 16, folds: 3, depth: 0.3, flare: 0.35, coat),
                              at: CV3(4.8, 36.0, 2.6), yaw: 0.2))
        parts.append(K.placed(K.roundedBox(CV3(7.5, 1.6, 4.0), radius: 0.8, segments: 2, puff: 0.25, R(.velvet(0x5E3A24))),
                              at: CV3(-4.5, 49.5, -2.2), yaw: -0.3))
        parts.append(K.placed(K.drape(width: 7, height: 13, folds: 2, depth: 0.25, flare: 0.3, R(.velvet(0x5E3A24))),
                              at: CV3(-4.5, 36.5, -2.6), yaw: -0.25))
        // 帽子（柱の頭 65.5 に載せる。2026-10-22: 前は柱の上 7 mm の宙に浮いていた）
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(4.2, 0), CV2(4.4, 0.55), CV2(2.3, 0.75), CV2(2.1, 3.6), CV2(0, 3.6)],
                                      segments: 20, R(.knit(0x3A3A3C))), at: CV3(0, 65.5, 0)))
        parts.append(K.tube(K.ringXZ(center: CV3(0, 66.1, 0), radius: 2.15, steps: 20), radius: 0.18, sides: 5, closed: true,
                            R(.knit(0xC9A66B))))
        return K.merge(parts)
    }

    /// 傘立て（釉の帯のある陶器・受け皿・骨と布の傘 2・木の柄）
    static func umbrellaStand() -> CamperMesh {
        var parts: [CamperMesh] = []
        let china = R(.ceramic(0xE8E2D4)), glaze = R(.ceramic(0x6E8FA3))
        // 胴と縁の巻き・釉の帯
        parts.append(K.vessel(outer: [CV2(0, 0), CV2(4.4, 0), CV2(4.9, 1.8), CV2(4.7, 14), CV2(4.55, 22), CV2(4.2, 24.5), CV2(0, 24.5)],
                              inner: [CV2(0, 0.55), CV2(3.8, 0.55), CV2(4.3, 1.8), CV2(4.15, 14), CV2(4.0, 21.5), CV2(0, 21.5)],
                              segments: 28, china))
        parts.append(K.tube(K.arc(center: .zero, radius: 4.5, from: 0, to: 2 * .pi, steps: 28).map { CV3($0.x, 12, $0.y) },
                            radius: 0.35, sides: 6, closed: true, glaze))
        parts.append(K.tube(K.arc(center: .zero, radius: 4.35, from: 0, to: 2 * .pi, steps: 28).map { CV3($0.x, 24.2, $0.y) },
                            radius: 0.28, sides: 6, closed: true, R(.agedBrass)))
        // 底の受け皿
        parts.append(K.placed(K.disc(radius: 3.6, height: 0.45, bevel: 0.12, segments: 20, R(.chrome)), at: CV3(0, 0.7, 0)))
        // 傘 2（2026-10-21 作り直し・Mac run 596: 開いた笠が筒の上に黒い円盤として載っていた。傘立ての傘は畳んである）。
        // 畳んだ布（石突へ細る 8 枚のひだ）・留め帯とボタン・上の軸と J の柄（木と革）
        for (x, z, lean, c, wood) in [(-1.4, -0.6, 0.10, 0x1C2230 as UInt32, CamperRoomWood.walnut), (1.5, 0.7, -0.14, 0x6A2A1E, .oak)] {
            let axis = CV3(lean, 1, lean * 0.4).normalized
            let base = CV3(x, 1.6, z)
            let q = CQuat.rotation(from: CV3(0, 1, 0), to: axis)
            func at(_ h: Double) -> CV3 { base + axis * h }
            // 石突（金具）
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.35, 0), CV2(0.4, 1.2), CV2(0, 1.2)], segments: 10, R(.chrome)), at: base, rotation: q))
            // 畳んだ布: ひだのある細い紡錘（下は細く、上で太く、上端でまた軸へ絞る）
            let gores = 8
            let profile: [(h: Double, r: Double)] = [(1.0, 0.35), (4, 0.9), (9, 1.45), (14, 1.75), (18, 1.7), (21, 1.2), (22.5, 0.45)]
            var cloth = CamperMesh()
            let steps = gores * 4
            for k in 0..<(profile.count - 1) {
                for j in 0..<steps {
                    func pt(_ i: Int, _ jj: Int) -> (CV3, CV3) {
                        let a = Double(jj) / Double(steps) * 2 * .pi
                        // ひだ: 骨のところで出て、間でへこむ
                        let fold = 1 - 0.22 * pow(abs(sin(a * Double(gores) / 2)), 0.7)
                        let r = profile[i].r * fold
                        let local = CV3(cos(a) * r, profile[i].h, sin(a) * r)
                        return (q.rotate(local) + base, q.rotate(CV3(cos(a), 0.1, sin(a)).normalized))
                    }
                    let (a0, n0) = pt(k, j), (a1, n1) = pt(k, j + 1), (b1, nb1) = pt(k + 1, j + 1), (b0, nb0) = pt(k + 1, j)
                    cloth.quad(a0, a1, b1, b0, n0, n1, nb1, nb0, R(.canvas(c)))
                }
            }
            cloth.uvs = cloth.positions.map { CV2(($0.x + $0.z) * 0.25, $0.y * 0.12) }
            parts.append(cloth)
            // 留め帯（布の太い所に巻いた帯）とボタン
            parts.append(K.tube(K.arc(center: .zero, radius: 1.85, from: 0, to: 2 * .pi, steps: 20).map { at(15.5) + q.rotate(CV3($0.x, 0, $0.y)) },
                                radius: 0.32, sides: 5, closed: true, R(.canvas(CamperMaterials.mix(c, 0x000000, 0.25)))))
            parts.append(K.placed(K.sphere(radius: 0.35, segments: 8, R(.chrome)), at: at(15.5) + q.rotate(CV3(1.95, 0, 0.4))))
            // 上の軸・柄の付け根の金具・J の柄
            parts.append(K.tube([at(22.3), at(26.5)], radius: 0.28, sides: 8, R(.chrome)))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.5, 0), CV2(0.45, 0.8), CV2(0, 0.8)], segments: 10, R(.agedBrass)), at: at(26.3), rotation: q))
            let top = at(27)
            let crook = (0...10).map { i -> CV3 in
                let t = Double(i) / 10
                if t < 0.4 { return top + axis * (t / 0.4 * 3.2) }
                let a = (t - 0.4) / 0.6 * .pi
                return top + axis * 3.2 + q.rotate(CV3(1.6 - cos(a) * 1.6, sin(a) * 1.6, 0))
            }
            parts.append(K.tube(crook, radius: 0.5, sides: 9, R(.wood(wood))))
            parts.append(K.placed(K.sphere(radius: 0.5, segments: 9, R(.wood(wood))), at: crook.last!))
        }
        return K.merge(parts)
    }

    /// 踏み台（2 段・先の細る脚・滑り止めの踏板・鉄の取っ手）
    static func stepStool() -> CamperMesh {
        var parts: [CamperMesh] = []
        let pine = R(.wood(.pine)), worn = R(.wornWood(.pine)), iron = R(.iron)
        // 下段の側板と脚（側板の外の面は踏板の端にそろえる。2026-10-22: 前は踏板の外へ 1.6 cm はみ出していた）
        for x in [-7.55, 7.55] {
            parts.append(K.block(CV3(1.4, 8.0, 11.5), at: CV3(x, 0, 0), radius: 0.3, pine))
            parts.append(K.placed(K.leg(bottom: 0.7, top: 0.9, height: 1.2, pine), at: CV3(x, 0, -4.5)))
            parts.append(K.placed(K.leg(bottom: 0.7, top: 0.9, height: 1.2, pine), at: CV3(x, 0, 4.5)))
        }
        // 下段の踏板（溝つき）
        parts.append(K.block(CV3(16.5, 1.4, 11.2), at: CV3(0, 7.2, 0.4), radius: 0.3, worn))
        for z in stride(from: -4.0, through: 4.0, by: 2.0) {
            parts.append(K.tube([CV3(-7.5, 8.55, z), CV3(7.5, 8.55, z)], radius: 0.1, sides: 4, R(.wood(.darkOak))))
        }
        // 上段（少し後ろへ）
        for x in [-6.5, 6.5] {
            parts.append(K.block(CV3(1.3, 8.0, 9.5), at: CV3(x, 8.0, -1.2), radius: 0.28, pine))
        }
        parts.append(K.block(CV3(13.2, 1.3, 9.2), at: CV3(0, 15.5, -0.8), radius: 0.28, worn))
        for z in stride(from: -4.0, through: 3.0, by: 2.0) {
            parts.append(K.tube([CV3(-5.8, 16.75, z - 0.5), CV3(5.8, 16.75, z - 0.5)], radius: 0.09, sides: 4, R(.wood(.darkOak))))
        }
        // 後ろの桟と取っ手
        parts.append(K.tube([CV3(-6.5, 10, -5.2), CV3(6.5, 10, -5.2)], radius: 0.35, sides: 6, pine))
        parts.append(K.tube([CV3(-5.5, 16.8, -4.5), CV3(-5.5, 20.2, -4.5), CV3(5.5, 20.2, -4.5), CV3(5.5, 16.8, -4.5)],
                            radius: 0.38, sides: 7, iron))
        for x in [-5.5, 5.5] {
            parts.append(K.placed(K.sphere(radius: 0.42, segments: 8, R(.agedBrass)), at: CV3(x, 16.8, -4.5)))
        }
        return K.merge(parts)
    }

    /// 洗濯かご（籐の胴・縁の巻き・蝶番付きの蓋・持ち手・中の布）
    static func laundryHamper() -> CamperMesh {
        var parts: [CamperMesh] = []
        let wicker = R(.wicker), oak = R(.wood(.oak))
        // 胴（下すぼみ・口が開く）
        parts.append(K.vessel(outer: [CV2(0, 0), CV2(6.6, 0), CV2(7.8, 2.5), CV2(8.6, 12), CV2(8.4, 22), CV2(7.8, 24), CV2(0, 24)],
                              inner: [CV2(0, 0.55), CV2(6.0, 0.55), CV2(7.2, 2.5), CV2(8.0, 12), CV2(7.85, 21.5), CV2(0, 21.5)],
                              segments: 32, wicker))
        // 縦の籐の筋と縁の巻き
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            let x0 = cos(a) * 7.0, z0 = sin(a) * 7.0
            let x1 = cos(a) * 8.2, z1 = sin(a) * 8.2
            parts.append(K.tube([CV3(x0, 1.5, z0), CV3(x1 * 0.98, 12, z1 * 0.98), CV3(x1 * 0.95, 23.2, z1 * 0.95)],
                                radius: 0.12, sides: 4, wicker))
        }
        for y in [2.0, 12.0, 23.5] {
            let r = y < 8 ? 7.4 : (y < 18 ? 8.35 : 8.0)
            parts.append(K.tube(K.arc(center: .zero, radius: r, from: 0, to: 2 * .pi, steps: 28).map { CV3($0.x, y, $0.y) },
                                radius: 0.28, sides: 6, closed: true, wicker))
        }
        // 蓋（少し後ろへ開いた）と木のつまみ・蝶番
        let lidQ = CQuat.axisAngle(CV3(1, 0, 0), -0.35)
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(8.0, 0), CV2(8.3, 0.9), CV2(5.0, 1.8), CV2(2.0, 2.0), CV2(0, 2.0)],
                                      segments: 28, wicker), at: CV3(0, 24.2, -1.5), rotation: lidQ))
        parts.append(K.placed(K.block(CV3(3.6, 0.55, 1.1), at: .zero, radius: 0.18, oak),
                              at: CV3(0, 26.0, 0.8), rotation: lidQ))
        for x in [-2.5, 2.5] {
            parts.append(K.placed(K.block(CV3(1.2, 0.5, 0.7), at: .zero, radius: 0.12, R(.agedBrass)),
                                  at: CV3(x, 24.3, -6.5)))
        }
        // 側面の持ち手（籐の輪）
        for s in [-1.0, 1.0] {
            parts.append(K.tube([CV3(s * 8.3, 14, -1.5), CV3(s * 9.5, 15.5, 0), CV3(s * 8.3, 17, 1.5)],
                                radius: 0.35, sides: 6, wicker))
        }
        // 中から覗く布
        parts.append(K.placed(K.roundedBox(CV3(7.5, 3.5, 6.5), radius: 1.0, segments: 3, puff: 0.7, R(.knit(0xE8E1D2))),
                              at: CV3(0, 18.5, 0.5)))
        parts.append(K.placed(K.roundedBox(CV3(5.5, 2.2, 4.5), radius: 0.8, segments: 2, puff: 0.5, R(.cotton(0xA8B8C2))),
                              at: CV3(1.5, 20.5, -0.5)))
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
        parts.append(K.placed(K.panel(width: 11.5, height: 33.5, R(.mirror)), at: c + CV3(0, 0, 0.55)))
        parts.append(K.placed(K.panel(width: 13, height: 35, R(.painted(0x3A3430))), at: c + CV3(0, 0, 0.15)))
        for y in stride(from: 4.0, through: 36.0, by: 3.0) {
            parts.append(K.block(CV3(0.5, 1.6, 0.5), at: CV3(-6.8, y, 1.8), radius: 0.1, R(.brass)))
            parts.append(K.block(CV3(0.5, 1.6, 0.5), at: CV3(6.8, y, 1.8), radius: 0.1, R(.brass)))
        }
        parts.append(K.block(CV3(15, 1.2, 2.0), at: CV3(0, 1.5, 1.3), radius: 0.3, R(.wornWood(.oak))))
        parts.append(K.tube(K.roundedRect(14.0, 36.0, r: 0.6).map { CV3($0.x, 20 + $0.y, 2.15) }, radius: 0.12, sides: 4, closed: true, R(.agedBrass)))
        return K.merge(parts)
    }

    /// 丸い真鍮鏡（厚い枠・飾り玉の縁・裏板・吊り輪）
    static func roundBrassMirror() -> CamperMesh {
        var parts: [CamperMesh] = []
        let c = CV3(0, 10, 0)
        let brass = R(.brass), aged = R(.agedBrass)
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        // 裏板と厚い枠
        parts.append(K.placed(K.disc(radius: 5.0, height: 0.55, bevel: 0.15, segments: 36, R(.painted(0x2A2420))),
                              at: c, rotation: toWall))
        // 枠は輪だけ（2026-10-21・run 605: 断面を真ん中まで閉じていて、鏡の面が真鍮の蓋に隠れた）。内の縁は鏡面へ落ちる
        parts.append(K.placed(K.lathe([CV2(4.05, 0.85), CV2(4.9, 0), CV2(5.15, 0.35), CV2(5.0, 1.1), CV2(4.55, 1.35), CV2(4.2, 1.35),
                                       CV2(4.05, 0.85)], segments: 36, brass, capStart: false, capEnd: false), at: c, rotation: toWall))
        // 鏡面と内側の細い縁
        parts.append(K.placed(K.ellipsePanel(rx: 4.05, ry: 4.05, R(.mirror)), at: c + CV3(0, 0, 0.85)))
        parts.append(K.tube(K.arc(center: c + CV3(0, 0, 0.95), radius: 4.25, from: 0, to: 2 * .pi, steps: 36)
                                .map { CV3($0.x, $0.y, 0.95) }, radius: 0.18, sides: 6, closed: true, aged))
        // 枠の飾り玉（等間隔）
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            parts.append(K.placed(K.sphere(radius: 0.32, segments: 8, brass),
                                  at: c + CV3(cos(a) * 5.05, sin(a) * 5.05, 0.7)))
        }
        // 上の吊り輪と壁の金具
        parts.append(K.placed(K.sphere(radius: 0.4, segments: 8, brass), at: c + CV3(0, 5.35, 0.75)))
        parts.append(K.tube(K.arc(center: c + CV3(0, 5.7, 0.75), radius: 0.55, from: 0.15, to: .pi - 0.15, steps: 8)
                                .map { CV3($0.x, $0.y, 0.75) }, radius: 0.12, sides: 5, brass))
        parts.append(K.placed(K.disc(radius: 0.7, height: 0.35, bevel: 0.1, segments: 12, aged),
                              at: c + CV3(0, 6.5, 0.15), rotation: toWall))
        return K.merge(parts)
    }

    /// 三面鏡（中央と折れる翼・蝶番・台）。1 段（高さ ≤ 21）
    static func triFoldMirror() -> CamperMesh {
        var parts: [CamperMesh] = []
        func panel(at x: Double, yaw: Double, w: Double) {
            // 翼を回しても壁の後ろ（z &lt; 0）に出ないよう、付け根を少し前へ
            let c = CV3(x, 10, 1.6)
            let q = CQuat.axisAngle(CV3(0, 1, 0), yaw)
            let ring = K.roundedRect(w, 16, r: 0.4, steps: 3)
            let hole = CamperPolygon.cw(K.roundedRect(w - 2.0, 13.6, r: 0.25, steps: 2))
            let frame = CamperMeshKit.extrude(ring, holes: [hole], depth: 1.1, front: R(.wood(.walnut)), side: R(.wornWood(.walnut)), bevel: 0.28)
            parts.append(K.placed(frame, at: c + q.rotate(CV3(0, 0, 1.1)), rotation: q))
            parts.append(K.placed(K.panel(width: w - 2.0, height: 13.6, R(.mirror)), at: c + q.rotate(CV3(0, 0, 0.45)), rotation: q))
            parts.append(K.placed(K.panel(width: w - 1.2, height: 14.5, R(.painted(0x2A2420))), at: c + q.rotate(CV3(0, 0, 0.15)), rotation: q))
            let bezel = K.roundedRect(w - 1.7, 14.2, r: 0.3)
            parts.append(K.tube(bezel.map { c + q.rotate(CV3($0.x, $0.y, 0.95)) }, radius: 0.1, sides: 4, closed: true, R(.brass)))
        }
        panel(at: 0, yaw: 0, w: 9)
        panel(at: -8.4, yaw: 0.28, w: 7)
        panel(at: 8.4, yaw: -0.28, w: 7)
        for x in [-4.4, 4.4] {
            for y in [5.5, 14.5] {
                parts.append(K.block(CV3(1.4, 1.8, 0.8), at: CV3(x, y, 2.2), radius: 0.15, R(.brass)))
            }
        }
        parts.append(K.block(CV3(22, 1.4, 4.5), at: CV3(0, 1.2, 2.6), radius: 0.3, R(.wood(.walnut))))
        return K.merge(parts)
    }

    /// ひげ剃り鏡（伸びる腕・継ぎ目・両面の丸い鏡）
    /// ひげ剃り鏡（壁座・ビス・伸びる腕 2・球関節・両面の丸い鏡・つまみ）
    static func shavingMirror() -> CamperMesh {
        var parts: [CamperMesh] = []
        let brass = R(.brass), chrome = R(.chrome)
        let toWall = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        parts.append(K.placed(K.disc(radius: 2.2, height: 0.65, bevel: 0.2, segments: 22, brass), at: CV3(0, 11.5, 0), rotation: toWall))
        parts.append(K.placed(K.disc(radius: 1.35, height: 0.4, bevel: 0.12, segments: 16, R(.agedBrass)),
                              at: CV3(0, 11.5, 0.6), rotation: toWall))
        for (dx, dy) in [(-1.1, 1.1), (1.1, 1.1), (-1.1, -1.1), (1.1, -1.1)] {
            parts.append(K.placed(K.sphere(radius: 0.18, segments: 6, R(.agedBrass)), at: CV3(dx, 11.5 + dy, 0.5)))
        }
        let j1 = CV3(0, 11.5, 4.0), j2 = CV3(3.0, 13.8, 7.8)
        parts.append(K.tube([CV3(0, 11.5, 0.7), j1], radius: 0.4, sides: 10, brass))
        parts.append(K.tube([j1, j2], radius: 0.38, sides: 10, brass))
        for j in [j1, j2] {
            parts.append(K.placed(K.sphere(radius: 0.7, segments: 12, brass), at: j))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.75, 0), CV2(0.7, 0.4), CV2(0, 0.4)], segments: 12, chrome), at: j))
        }
        // 鏡枠（表の縁・裏の縁）
        let mirrorAt = j2 + CV3(0, 0, 1.4)
        parts.append(K.placed(K.disc(radius: 3.8, height: 0.85, bevel: 0.28, segments: 32, brass), at: mirrorAt, rotation: toWall))
        parts.append(K.tube(K.arc(center: mirrorAt, radius: 3.55, from: 0, to: 2 * .pi, steps: 28)
                                .map { CV3($0.x, $0.y, mirrorAt.z + 0.2) }, radius: 0.14, sides: 5, closed: true, R(.agedBrass)))
        // 鏡面は枠の円盤（厚み 0.85）の表と裏の外に出す（run 605: 円盤の中に埋もれて真鍮の円盤に見えた）
        parts.append(K.placed(K.ellipsePanel(rx: 3.05, ry: 3.05, R(.mirror)), at: mirrorAt + CV3(0, 0, 0.9)))
        parts.append(K.placed(K.inverted(K.ellipsePanel(rx: 2.85, ry: 2.85, R(.mirror))), at: mirrorAt + CV3(0, 0, -0.05)))
        // 拡大側の印（細い輪）
        parts.append(K.tube(K.arc(center: mirrorAt + CV3(0, 0, -0.4), radius: 2.5, from: 0, to: 2 * .pi, steps: 22)
                                .map { CV3($0.x, $0.y, mirrorAt.z - 0.4) }, radius: 0.08, sides: 4, closed: true, R(.agedBrass)))
        // 上のつまみ
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.5, 0), CV2(0.45, 1.6), CV2(0.7, 1.9), CV2(0, 1.9)],
                                      segments: 12, brass), at: mirrorAt + CV3(0, 3.7, 0),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
        return K.merge(parts)
    }

    // MARK: 趣味

    /// カメラ棚（オークの棚板・鉄のブラケット・小さなボディ 3・横置きレンズ）。壁面より後ろへ出さない
    static func cameraShelf() -> CamperMesh {
        var parts: [CamperMesh] = []
        let oak = R(.wornWood(.oak)), chrome = R(.chrome), iron = R(.iron)
        let toFront = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        // 棚板（縁の面取り）と壁側の裏桟（奥行きの半分が壁を突き抜けないよう手前へ）
        parts.append(K.block(CV3(28, 1.4, 7.2), at: CV3(0, 8.0, 3.8), radius: 0.35, oak))
        parts.append(K.block(CV3(26, 0.7, 1.0), at: CV3(0, 8.0, 0.7), radius: 0.2, R(.wood(.oak))))
        // 鉄のブラケット（L 字・ビス）
        for x in [-10.0, 0.0, 10.0] {
            parts.append(K.tube([CV3(x, 0.6, 0.55), CV3(x, 7.6, 0.55), CV3(x, 7.6, 6.6)], radius: 0.28, sides: 6, iron))
            parts.append(K.placed(K.disc(radius: 0.45, height: 0.25, bevel: 0.08, segments: 10, R(.agedBrass)),
                                  at: CV3(x, 3.5, 0.65), rotation: toFront))
            parts.append(K.placed(K.disc(radius: 0.45, height: 0.25, bevel: 0.08, segments: 10, R(.agedBrass)),
                                  at: CV3(x, 6.5, 0.65), rotation: toFront))
        }
        // 棚上の小さなカメラ（飾り用・camera.* 本体とは別）
        for (x, bodyC, leatherC) in [(-9.0, 0x1A1A1A as UInt32, 0x3E2A1C as UInt32),
                                     (0.0, 0x2A2A2C, 0x2A2420),
                                     (9.0, 0x1E1E20, 0x4A3424)] {
            parts.append(K.block(CV3(5.2, 3.6, 3.4), at: CV3(x, 9.4, 3.4), radius: 0.45, R(.painted(bodyC))))
            parts.append(K.block(CV3(4.6, 0.45, 3.0), at: CV3(x, 13.0, 3.4), radius: 0.15, chrome))
            parts.append(K.block(CV3(4.4, 2.2, 0.3), at: CV3(x, 9.7, 5.05), radius: 0.12, R(.leather(leatherC))))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.35, 0), CV2(1.5, 0.5), CV2(1.4, 2.6), CV2(1.15, 3.0), CV2(0, 3.0)],
                                          segments: 16, chrome), at: CV3(x, 10.8, 5.2), rotation: toFront))
            parts.append(K.placed(K.disc(radius: 0.95, height: 0.25, bevel: 0.08, segments: 12, R(.painted(0x0A0A0A))),
                                  at: CV3(x, 10.8, 8.1), rotation: toFront))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.55, 0), CV2(0.5, 0.9), CV2(0, 0.9)], segments: 10, chrome),
                                  at: CV3(x + 1.8, 13.5, 2.6)))
        }
        // 横置きの単体レンズ
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.15, 0), CV2(1.25, 0.4), CV2(1.2, 4.2), CV2(1.0, 4.6), CV2(0, 4.6)],
                                      segments: 14, R(.painted(0x141414))),
                              at: CV3(-3.5, 10.0, 3.2), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2)))
        parts.append(K.placed(K.disc(radius: 1.0, height: 0.3, bevel: 0.08, segments: 12, chrome),
                              at: CV3(-1.2, 10.0, 3.2), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2)))
        return K.merge(parts)
    }

    /// 釣竿掛け（杉の横桟・鉄のブラケット・竿 3・コルクのグリップ・ガイド）。壁面より後ろへ出さない
    static func rodRack() -> CamperMesh {
        var parts: [CamperMesh] = []
        let cedar = R(.wood(.cedar)), iron = R(.iron)
        // 上下の横桟（奥行きの半分が壁を突き抜けないよう手前へ）
        for y in [5.8, 14.2] {
            parts.append(K.block(CV3(28, 1.3, 3.2), at: CV3(0, y, 1.85), radius: 0.3, cedar))
            for x in [-10.0, 0.0, 10.0] {
                parts.append(K.tube(K.arc(center: CV3(x, y + 1.5, 2.8), radius: 0.7, from: .pi, to: 2 * .pi, steps: 8)
                                        .map { CV3($0.x, $0.y, 2.8) }, radius: 0.15, sides: 5, R(.wornWood(.cedar))))
            }
        }
        // 壁ブラケット
        for x in [-12.0, 12.0] {
            parts.append(K.tube([CV3(x, 4.5, 0.5), CV3(x, 5.8, 1.6), CV3(x, 5.8, 3.2)], radius: 0.28, sides: 6, iron))
            parts.append(K.tube([CV3(x, 12.8, 0.5), CV3(x, 14.2, 1.6), CV3(x, 14.2, 3.2)], radius: 0.28, sides: 6, iron))
        }
        // 竿（緑・オリーブ・茶）・グリップ・リール脚・ガイド
        let rodColors: [UInt32] = [0x2F5A3C, 0x3A4A2E, 0x4A3A28]
        for (i, x) in [-10.0, 0.0, 10.0].enumerated() {
            let tip = CV3(x + 0.4, 19.2, 3.2)
            let butt = CV3(x - 0.2, 6.5, 2.4)
            parts.append(K.tube([butt, CV3(x, 12.5, 2.7), tip], radius: 0.28, sides: 7, R(.painted(rodColors[i]))))
            // コルクのグリップ
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.7, 0), CV2(0.75, 0.3), CV2(0.65, 3.2), CV2(0.55, 3.5), CV2(0, 3.5)],
                                          segments: 12, R(.wood(.oak))), at: butt))
            // リール脚（小さな塊）
            parts.append(K.block(CV3(1.6, 0.7, 1.2), at: CV3(x, 9.2, 2.8), radius: 0.15, R(.chrome)))
            parts.append(K.placed(K.disc(radius: 0.9, height: 0.35, bevel: 0.1, segments: 12, R(.chrome)),
                                  at: CV3(x + 0.9, 9.2, 2.8), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2)))
            // ガイドの輪
            for t in [0.35, 0.55, 0.75] {
                let p = CV3(x + 0.15 * t, 6.5 + (19.2 - 6.5) * t, 2.4 + 0.8 * t)
                parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.35, 0), CV2(0.4, 0.15), CV2(0.35, 0.35), CV2(0, 0.35)],
                                              segments: 8, R(.chrome), capStart: false), at: p))
            }
            // 穂先の小さな玉
            parts.append(K.placed(K.sphere(radius: 0.25, segments: 6, R(.painted(0xC9584A))), at: tip))
        }
        return K.merge(parts)
    }

    /// スキー板（壁掛け・反った先端・ビンディング・ストック 2）。先端は部屋側へ反らせ壁を突き抜けない
    static func skiMount() -> CamperMesh {
        var parts: [CamperMesh] = []
        let cream = R(.painted(0xE8E2D4)), tipRed = R(.painted(0xC9584A)), iron = R(.iron)
        // 壁の木の桟
        for y in [8.5, 27.0] {
            parts.append(K.block(CV3(12, 1.5, 2.0), at: CV3(0, y, 1.15), radius: 0.25, R(.wood(.oak))))
            for x in [-4.0, 4.0] {
                parts.append(K.placed(K.disc(radius: 0.4, height: 0.3, bevel: 0.08, segments: 10, R(.agedBrass)),
                                      at: CV3(x, y + 0.75, 1.25), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
            }
        }
        // スキー板 2（胴は薄い箱・先端は旋盤で部屋側へ反る）
        for x in [-4.0, 4.0] {
            parts.append(K.block(CV3(2.8, 28, 1.15), at: CV3(x, 4.5, 1.9), radius: 0.35, cream))
            // 先端の反り（+X 回転で部屋側 +Z へ）
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.35, 0), CV2(1.4, 1.5), CV2(1.1, 3.2), CV2(0.4, 4.0), CV2(0, 4.0)],
                                          segments: 12, tipRed), at: CV3(x, 32.5, 1.9),
                                  rotation: CQuat.axisAngle(CV3(1, 0, 0), 0.55)))
            // テールの面取り
            parts.append(K.placed(K.block(CV3(2.6, 1.2, 1.1), at: .zero, radius: 0.3, cream), at: CV3(x, 4.2, 1.9)))
            // ビンディング（つま先・かかと）
            parts.append(K.block(CV3(3.6, 1.6, 1.5), at: CV3(x, 14.5, 2.35), radius: 0.25, iron))
            parts.append(K.block(CV3(3.2, 1.4, 1.4), at: CV3(x, 18.5, 2.3), radius: 0.22, iron))
            parts.append(K.tube([CV3(x - 1.4, 15.3, 2.7), CV3(x + 1.4, 15.3, 2.7)], radius: 0.18, sides: 5, R(.chrome)))
            // 側面の細いライン
            parts.append(K.tube([CV3(x + 1.35, 6, 1.9), CV3(x + 1.35, 32, 1.9)], radius: 0.08, sides: 4, tipRed))
        }
        // ストック（バスケットつき）
        for x in [-6.8, 6.8] {
            parts.append(K.tube([CV3(x, 4.5, 1.5), CV3(x, 31.5, 1.5)], radius: 0.28, sides: 7, iron))
            parts.append(K.placed(K.sphere(radius: 0.5, segments: 8, iron), at: CV3(x, 32.0, 1.5)))
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.4, 0), CV2(1.5, 0.25), CV2(0.9, 0.55), CV2(0.35, 0.7), CV2(0, 0.7)],
                                          segments: 14, R(.painted(0x2A2A2C))), at: CV3(x, 5.2, 1.5)))
            parts.append(K.tube([CV3(x, 28.5, 1.5), CV3(x - 0.8, 30.2, 2.0), CV3(x + 0.8, 30.2, 2.0), CV3(x, 28.5, 1.5)],
                                radius: 0.12, sides: 4, R(.leather(0x3E2A1C))))
        }
        return K.merge(parts)
    }

    /// 画架（壁に立て掛け・三脚の木組み・キャンバス枠・絵の具の跡・下の棚）
    static func wallEasel() -> CamperMesh {
        var parts: [CamperMesh] = []
        let pine = R(.wood(.pine)), worn = R(.wornWood(.pine))
        // 前脚 2・後ろの支柱（壁側）
        for s in [-1.0, 1.0] {
            parts.append(K.tube([CV3(s * 5.2, 0.8, 0.6), CV3(s * 2.0, 17, 3.6), CV3(s * 0.4, 34.5, 4.6)],
                                radius: 0.42, sides: 7, pine))
        }
        parts.append(K.tube([CV3(0, 0.8, 0.5), CV3(0, 18, 2.8), CV3(0, 33.5, 4.4)], radius: 0.38, sides: 7, pine))
        // 横桟（下・中・上）と蝶番金具
        for (y, z, w) in [(8.0, 1.8, 9.5), (17.0, 3.8, 11.5), (31.5, 4.5, 4.0)] as [(Double, Double, Double)] {
            parts.append(K.tube([CV3(-w / 2, y, z), CV3(w / 2, y, z)], radius: 0.32, sides: 6, worn))
        }
        for x in [-2.0, 2.0] {
            parts.append(K.placed(K.sphere(radius: 0.35, segments: 7, R(.agedBrass)), at: CV3(x, 17.0, 4.0)))
        }
        // キャンバスを受ける棚板
        parts.append(K.block(CV3(12.5, 1.0, 2.4), at: CV3(0, 16.5, 4.2), radius: 0.22, worn))
        // キャンバス枠（押し出しの額）と布
        let ring = K.roundedRect(11.2, 14.0, r: 0.35, steps: 3)
        let hole = CamperPolygon.cw(K.roundedRect(9.8, 12.6, r: 0.2, steps: 2))
        parts.append(K.placed(CamperMeshKit.extrude(ring, holes: [hole], depth: 0.85,
                                                    front: R(.wood(.birch)), side: worn, bevel: 0.2),
                              at: CV3(0, 23.5, 5.9)))
        parts.append(K.placed(K.panel(width: 9.8, height: 12.6, R(.canvas(0xF2EEE4))), at: CV3(0, 23.5, 5.55)))
        // 絵の具の塊（抽象の風景）
        parts.append(K.placed(K.panel(width: 7.2, height: 4.8, R(.painted(0x6E8FA3))), at: CV3(0, 25.2, 5.65)))
        parts.append(K.placed(K.roundedBox(CV3(3.5, 2.2, 0.35), radius: 0.4, segments: 2, puff: 0.15, R(.painted(0xC9A66B))),
                              at: CV3(-1.5, 21.5, 5.75)))
        parts.append(K.placed(K.roundedBox(CV3(2.8, 1.6, 0.3), radius: 0.35, segments: 2, puff: 0.12, R(.painted(0x5A7A4A))),
                              at: CV3(2.0, 20.8, 5.75)))
        // 下の小さな棚（パレットと筆）
        parts.append(K.block(CV3(8.5, 0.7, 3.0), at: CV3(0, 7.5, 2.2), radius: 0.2, worn))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.2, 0), CV2(2.4, 0.25), CV2(1.8, 0.45), CV2(0, 0.45)],
                                      segments: 16, R(.wood(.oak))), at: CV3(-1.5, 8.2, 2.5)))
        for (dx, c) in [(-0.6, 0xC9584A as UInt32), (0.3, 0x6E8FA3), (1.1, 0xC9A66B)] {
            parts.append(K.placed(K.sphere(radius: 0.35, segments: 6, R(.painted(c))), at: CV3(-1.5 + dx, 8.55, 2.5)))
        }
        parts.append(K.tube([CV3(2.5, 8.3, 2.2), CV3(2.5, 12.5, 3.5)], radius: 0.12, sides: 5, R(.wood(.walnut))))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.25, 0), CV2(0.35, 0.8), CV2(0, 0.9)], segments: 8, R(.knit(0xD8CDB8))),
                              at: CV3(2.5, 12.5, 3.5)))
        return K.merge(parts)
    }

    // MARK: カメラ（床に置く・棚の飾りではなく本体。実機の部品を一点ずつ）

    /// レンズ鏡筒（マウント側 y=0 → 前玉へ。ピント環・絞り環・前玉・反射）。`toFront` で部屋側へ向ける前提
    private static func cameraLensBarrel(mountR: Double, length: Double, rings: Int, chrome: CamperMaterial,
                                         paint: CamperMaterial, glass: CamperMaterial) -> CamperMesh {
        var parts: [CamperMesh] = []
        let toFront = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        // マウントの段と本体の筒
        parts.append(K.lathe([CV2(0, 0), CV2(mountR + 0.35, 0), CV2(mountR + 0.45, 0.35), CV2(mountR + 0.2, 0.7),
                              CV2(mountR, 0.85), CV2(mountR * 0.98, length * 0.55), CV2(mountR * 0.92, length * 0.88),
                              CV2(mountR * 0.78, length), CV2(0, length)], segments: 24, paint))
        // ピント環・絞り環（刻みの筋）
        for i in 0..<rings {
            let t = 0.22 + Double(i) / Double(max(1, rings)) * 0.55
            let y = length * t
            let r = mountR * (0.98 - Double(i) * 0.04)
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(r + 0.22, 0), CV2(r + 0.28, 0.35), CV2(r + 0.18, 0.7), CV2(0, 0.7)],
                                          segments: 22, chrome, capStart: false), at: CV3(0, y, 0)))
            for k in 0..<16 {
                let a = Double(k) / 16 * 2 * .pi
                parts.append(K.block(CV3(0.12, 0.55, 0.18), at: CV3(cos(a) * (r + 0.32), y + 0.1, sin(a) * (r + 0.32)),
                                     radius: 0.04, chrome))
            }
        }
        // 前玉の縁とガラス・反射のハイライト
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(mountR * 0.72, 0), CV2(mountR * 0.78, 0.25), CV2(mountR * 0.55, 0.45), CV2(0, 0.45)],
                                      segments: 22, chrome), at: CV3(0, length - 0.2, 0)))
        parts.append(K.placed(K.disc(radius: mountR * 0.52, height: 0.22, bevel: 0.08, segments: 20, glass),
                              at: CV3(0, length + 0.15, 0)))
        parts.append(K.placed(K.ellipsePanel(rx: mountR * 0.22, ry: mountR * 0.14, steps: 16, R(.chrome)),
                              at: CV3(-mountR * 0.12, length + 0.28, mountR * 0.08), rotation: toFront))
        return K.merge(parts)
    }

    /// ストラップ金具（両肩）
    private static func cameraStrapLug(at p: CV3, chrome: CamperMaterial) -> CamperMesh {
        K.merge([
            K.placed(K.lathe([CV2(0, 0), CV2(0.45, 0), CV2(0.5, 0.25), CV2(0.35, 0.55), CV2(0, 0.55)], segments: 10, chrome), at: p),
            K.tube(K.arc(center: p + CV3(0, 0.7, 0), radius: 0.45, from: 0.2, to: .pi - 0.2, steps: 8)
                       .map { CV3($0.x, $0.y, p.z) }, radius: 0.1, sides: 5, chrome)
        ])
    }

    /// レンジファインダー（銀色の天板・革張り・測距窓／ファインダー・巻き上げレバー・短いレンズ）
    static func rangefinder() -> CamperMesh {
        var parts: [CamperMesh] = []
        let body = R(.painted(0x161618)), chrome = R(.chrome), leather = R(.leather(0x3E2A1C))
        let glass = R(.painted(0x1A2830)), ink = R(.painted(0x0A0A0A))
        let toFront = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        // 本体・底蓋・天板（段差のある銀）
        parts.append(K.block(CV3(13.6, 6.8, 6.4), at: CV3(0, 0.35, 0), radius: 0.55, body))
        parts.append(K.block(CV3(13.9, 0.55, 6.7), at: CV3(0, 0, 0), radius: 0.2, R(.iron)))
        parts.append(K.block(CV3(13.8, 0.85, 6.6), at: CV3(0, 7.15, 0), radius: 0.22, chrome))
        parts.append(K.block(CV3(12.4, 0.2, 5.4), at: CV3(0, 8.0, 0.15), radius: 0.08, R(.agedBrass)))
        // 前面・側面・背面の革張り
        parts.append(K.block(CV3(11.8, 4.6, 0.28), at: CV3(0, 1.4, 3.2), radius: 0.12, leather))
        parts.append(K.block(CV3(11.8, 4.6, 0.28), at: CV3(0, 1.4, -3.2), radius: 0.12, leather))
        for x in [-6.7, 6.7] {
            parts.append(K.block(CV3(0.28, 4.6, 5.6), at: CV3(x, 1.4, 0), radius: 0.1, leather))
        }
        // 測距窓（左）・ファインダー窓（右）・枠線カウンタ窓
        parts.append(K.block(CV3(2.6, 1.7, 0.45), at: CV3(-4.4, 5.35, 3.15), radius: 0.12, chrome))
        parts.append(K.placed(K.panel(width: 2.1, height: 1.25, glass), at: CV3(-4.4, 6.2, 3.4)))
        parts.append(K.block(CV3(1.9, 1.5, 0.45), at: CV3(4.6, 5.45, 3.15), radius: 0.12, chrome))
        parts.append(K.placed(K.panel(width: 1.45, height: 1.05, glass), at: CV3(4.6, 6.2, 3.4)))
        parts.append(K.placed(K.disc(radius: 0.7, height: 0.25, bevel: 0.06, segments: 14, chrome),
                              at: CV3(0.2, 7.95, 2.4), rotation: toFront))
        parts.append(K.placed(K.disc(radius: 0.45, height: 0.12, bevel: 0.04, segments: 12, R(.painted(0xEDE8DE))),
                              at: CV3(0.2, 7.95, 2.55), rotation: toFront))
        // 巻き上げレバー（倒した板）・シャッター・巻き戻しノブ
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.15, 0), CV2(1.2, 0.35), CV2(0.95, 0.7), CV2(0, 0.7)], segments: 14, chrome),
                              at: CV3(5.0, 8.0, -1.4)))
        parts.append(K.placed(K.block(CV3(3.4, 0.35, 1.1), at: .zero, radius: 0.12, chrome),
                              at: CV3(3.4, 8.35, -1.4), rotation: CQuat.axisAngle(CV3(0, 1, 0), 0.35)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.7, 0), CV2(0.75, 0.2), CV2(0.45, 0.35), CV2(0.4, 1.5), CV2(0.55, 1.7), CV2(0, 1.7)],
                                      segments: 12, chrome), at: CV3(-3.2, 8.0, -1.0)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.35, 0), CV2(1.4, 0.4), CV2(1.15, 0.85), CV2(0.9, 1.5), CV2(0, 1.5)],
                                      segments: 16, chrome), at: CV3(-5.4, 8.0, 1.0)))
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            parts.append(K.block(CV3(0.15, 0.7, 0.2), at: CV3(-5.4 + cos(a) * 1.25, 8.4, 1.0 + sin(a) * 1.25), radius: 0.04, R(.iron)))
        }
        // 前面の銘板とレンズ（ヘリカル・前玉）
        parts.append(K.block(CV3(3.6, 0.7, 0.2), at: CV3(0, 6.4, 3.25), radius: 0.08, R(.agedBrass)))
        let lens = cameraLensBarrel(mountR: 2.15, length: 4.0, rings: 2, chrome: chrome, paint: R(.painted(0x1A1A1C)), glass: ink)
        parts.append(K.placed(lens, at: CV3(0, 3.5, 3.25), rotation: toFront))
        // ストラップ金具・底の三脚穴
        parts.append(cameraStrapLug(at: CV3(-6.5, 6.4, 0), chrome: chrome))
        parts.append(cameraStrapLug(at: CV3(6.5, 6.4, 0), chrome: chrome))
        // 底の三脚穴（床より下へ出さない）
        parts.append(K.placed(K.disc(radius: 0.55, height: 0.18, bevel: 0.05, segments: 12, chrome), at: CV3(0, 0.08, 0)))
        parts.append(K.placed(K.disc(radius: 0.28, height: 0.12, bevel: 0.04, segments: 10, R(.iron)), at: CV3(0, 0.2, 0)))
        return K.merge(parts)
    }

    /// 一眼レフ（五角プリズム・ホットシュー・グリップの筋・モード／ISO ダイヤル・多環レンズとフード）
    static func slrCamera() -> CamperMesh {
        var parts: [CamperMesh] = []
        let body = R(.painted(0x121214)), grip = R(.leather(0x2A2A2C)), chrome = R(.chrome)
        let paint = R(.painted(0x1A1A1C)), ink = R(.painted(0x080808)), rubber = R(.leather(0x1E1E20))
        let toFront = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        // ボディとミラーボックスの段（奥行きはマス 2＝22 以内）
        parts.append(K.block(CV3(14.8, 7.6, 8.2), at: CV3(0, 0.2, 0.2), radius: 0.5, body))
        parts.append(K.block(CV3(8.4, 6.8, 5.0), at: CV3(-1.2, 0.6, 2.8), radius: 0.35, body))
        // 五角プリズム（段のある屋根）と接眼・ホットシュー
        parts.append(K.block(CV3(7.2, 3.8, 5.6), at: CV3(-1.4, 7.8, -0.1), radius: 0.35, body))
        parts.append(K.block(CV3(5.2, 1.8, 4.0), at: CV3(-1.4, 11.5, -0.1), radius: 0.25, body))
        parts.append(K.block(CV3(4.0, 0.7, 3.0), at: CV3(-1.4, 13.2, -0.1), radius: 0.15, body))
        parts.append(K.block(CV3(3.4, 1.7, 0.55), at: CV3(-1.4, 10.0, 2.8), radius: 0.12, rubber))
        parts.append(K.placed(K.panel(width: 2.6, height: 1.2, R(.painted(0x0A1820))), at: CV3(-1.4, 10.85, 3.1)))
        parts.append(K.block(CV3(2.8, 0.35, 1.6), at: CV3(-1.4, 13.85, -0.1), radius: 0.08, chrome))
        for x in [-0.7, 0.7] {
            parts.append(K.block(CV3(0.35, 0.25, 1.3), at: CV3(-1.4 + x, 14.05, -0.1), radius: 0.06, R(.iron)))
        }
        // 右グリップ（筋入り）とシャッター周り
        parts.append(K.block(CV3(3.6, 7.0, 7.4), at: CV3(5.9, 0.5, 0.3), radius: 0.65, grip))
        for y in stride(from: 1.4, through: 6.4, by: 0.85) {
            parts.append(K.block(CV3(0.28, 0.28, 6.6), at: CV3(7.55, y, 0.3), radius: 0.08, R(.iron)))
        }
        // モードダイヤル（刻み）・シャッター・フィルム巻き上げ・ISO
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.45, 0), CV2(1.5, 0.35), CV2(1.25, 0.7), CV2(1.1, 1.15), CV2(0, 1.15)],
                                      segments: 18, paint), at: CV3(4.6, 7.9, -2.1)))
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            parts.append(K.block(CV3(0.12, 0.55, 0.18), at: CV3(4.6 + cos(a) * 1.35, 8.35, -2.1 + sin(a) * 1.35), radius: 0.04, chrome))
        }
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.65, 0), CV2(0.7, 0.2), CV2(0.4, 0.35), CV2(0.38, 1.55), CV2(0.55, 1.75), CV2(0, 1.75)],
                                      segments: 12, chrome), at: CV3(2.4, 7.9, -2.5)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.1, 0), CV2(1.15, 0.4), CV2(0.9, 0.9), CV2(0, 0.9)], segments: 14, chrome),
                              at: CV3(5.6, 7.9, 2.2)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.0, 0), CV2(1.05, 0.3), CV2(0.85, 0.65), CV2(0, 0.65)], segments: 14, paint),
                              at: CV3(-5.2, 7.9, -1.9)))
        // 長いレンズ（3 環）と花形フード
        let lens = cameraLensBarrel(mountR: 2.55, length: 8.4, rings: 3, chrome: chrome, paint: paint, glass: ink)
        parts.append(K.placed(lens, at: CV3(-1.3, 4.0, 5.0), rotation: toFront))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.4, 0), CV2(3.55, 0.4), CV2(3.2, 2.1), CV2(2.8, 2.6), CV2(2.5, 2.75), CV2(0, 2.75)],
                                      segments: 20, R(.painted(0x0E0E10)), capStart: false),
                              at: CV3(-1.3, 4.0, 13.5), rotation: toFront))
        // 花形フードの切り欠き風（4 つのくぼみ）
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + .pi / 4
            parts.append(K.placed(K.sphere(radius: 0.75, segments: 8, body),
                                  at: CV3(-1.3 + cos(a) * 3.0, 4.0 + sin(a) * 3.0, 15.7)))
        }
        parts.append(cameraStrapLug(at: CV3(-7.2, 6.2, 0), chrome: chrome))
        parts.append(cameraStrapLug(at: CV3(7.4, 6.2, 0), chrome: chrome))
        return K.merge(parts)
    }

    /// インスタントカメラ（箱・蛇腹のひだ・レンズボード・出す口の印画・ファインダー）
    static func instantCamera() -> CamperMesh {
        var parts: [CamperMesh] = []
        let shell = R(.painted(0xE8E2D6)), accent = R(.painted(0xC9A66B)), dark = R(.painted(0x2A2A2C))
        let bellows = R(.leather(0x1A1A1C)), film = R(.canvas(0xF5F0E6)), chrome = R(.chrome)
        let toFront = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        // 本体の箱・天の真鍮帯・背面の蓋の筋
        parts.append(K.block(CV3(13.6, 15.2, 9.2), at: CV3(0, 0.3, -0.4), radius: 0.65, shell))
        parts.append(K.block(CV3(12.2, 1.1, 8.0), at: CV3(0, 15.5, -0.4), radius: 0.22, accent))
        parts.append(K.block(CV3(11.5, 0.35, 7.2), at: CV3(0, 16.55, -0.4), radius: 0.1, R(.agedBrass)))
        for z in [-3.2, 0.0, 2.4] {
            parts.append(K.block(CV3(10.5, 0.2, 0.35), at: CV3(0, 12.5, z - 0.4), radius: 0.06, R(.wornWood(.oak))))
        }
        // 前面の黒枠と蛇腹（手前へ細くなるひだ）
        parts.append(K.block(CV3(10.2, 8.4, 0.55), at: CV3(0, 5.2, 4.35), radius: 0.18, dark))
        for i in 0..<8 {
            let t = Double(i) / 7
            let z = 4.7 + t * 4.2
            let s = 1.0 - t * 0.42
            // ひだはレンズの芯（y 8.6）を真ん中に（`block` は下の面が `at`。前はひだが 8 cm 上にずれ、角の補強革が宙に浮いた）
            parts.append(K.block(CV3(8.4 * s, 6.8 * s, 0.42), at: CV3(0, 8.6 - 3.4 * s, z), radius: 0.1, bellows))
            // 角の補強革
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
                parts.append(K.block(CV3(0.55, 0.55, 0.28), at: CV3(sx * 3.8 * s, 8.6 + sy * 3.0 * s, z), radius: 0.12, R(.leather(0x3E2A1C))))
            }
        }
        // レンズボード・シャッター筐体・レンズ
        parts.append(K.block(CV3(5.6, 5.6, 0.7), at: CV3(0, 5.8, 9.0), radius: 0.25, dark))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(2.35, 0), CV2(2.5, 0.6), CV2(2.2, 1.5), CV2(1.85, 1.9), CV2(0, 1.9)],
                                      segments: 20, chrome), at: CV3(0, 8.6, 9.35), rotation: toFront))
        parts.append(K.placed(K.disc(radius: 1.45, height: 0.28, bevel: 0.08, segments: 18, R(.painted(0x0A0A0A))),
                              at: CV3(0, 8.6, 11.2), rotation: toFront))
        parts.append(K.placed(K.ellipsePanel(rx: 0.55, ry: 0.35, steps: 12, chrome), at: CV3(-0.35, 8.9, 11.4)))
        // 出す口と覗く印画紙
        parts.append(K.block(CV3(11.2, 2.0, 2.4), at: CV3(0, 0.6, 3.8), radius: 0.28, dark))
        parts.append(K.block(CV3(10.0, 0.45, 2.0), at: CV3(0, 1.55, 4.6), radius: 0.1, R(.iron)))
        parts.append(K.block(CV3(9.2, 0.28, 3.4), at: CV3(0, 1.7, 5.6), radius: 0.08, film))
        parts.append(K.block(CV3(8.4, 0.12, 0.9), at: CV3(0, 1.9, 7.1), radius: 0.04, R(.painted(0xC9584A))))
        // ファインダー塔・レリーズ・側面の帯
        parts.append(K.block(CV3(3.8, 2.6, 2.8), at: CV3(0, 13.8, -2.8), radius: 0.3, dark))
        parts.append(K.placed(K.panel(width: 2.4, height: 1.6, R(.painted(0x0A1820))), at: CV3(0, 15.1, -1.35)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.75, 0), CV2(0.8, 0.25), CV2(0.5, 0.4), CV2(0.45, 1.35), CV2(0.6, 1.55), CV2(0, 1.55)],
                                      segments: 12, chrome), at: CV3(5.4, 15.7, -2.2)))
        parts.append(K.placed(K.sphere(radius: 0.55, segments: 10, R(.painted(0xC9584A))), at: CV3(5.4, 17.3, -2.2)))
        for x in [-6.6, 6.6] {
            parts.append(K.block(CV3(0.45, 10.0, 0.45), at: CV3(x, 3.5, -0.4), radius: 0.12, accent))
        }
        // 2026-10-22: 本体の箱の下が床から 7 mm 浮き、蛇腹のひだの間が空いて前が宙に浮いていた。ひだを厚くし、全体を床へ下ろす
        return K.placed(K.merge(parts), at: CV3(0, -0.3, 0))
    }

    /// 二眼レフ（撮影／ファインダーの二眼・腰レベルフード・ピントノブ・巻き上げクランク）
    static func twinLens() -> CamperMesh {
        var parts: [CamperMesh] = []
        let body = R(.painted(0x1A1A1C)), leather = R(.leather(0x4A3424)), chrome = R(.chrome)
        let ink = R(.painted(0x080808)), dark = R(.painted(0x121214))
        let toFront = CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)
        // 箱本体・革張りパネル・底蓋
        parts.append(K.block(CV3(11.6, 13.2, 11.2), at: CV3(0, 0.25, 0), radius: 0.5, body))
        parts.append(K.block(CV3(11.9, 0.5, 11.5), at: CV3(0, 0, 0), radius: 0.18, R(.iron)))
        parts.append(K.block(CV3(10.4, 9.4, 0.35), at: CV3(0, 2.2, 5.55), radius: 0.12, leather))
        parts.append(K.block(CV3(10.4, 9.4, 0.35), at: CV3(0, 2.2, -5.55), radius: 0.12, leather))
        for x in [-5.7, 5.7] {
            parts.append(K.block(CV3(0.35, 9.4, 10.0), at: CV3(x, 2.2, 0), radius: 0.1, leather))
        }
        // 前面の銘板帯
        parts.append(K.block(CV3(8.5, 1.0, 0.25), at: CV3(0, 7.2, 5.65), radius: 0.08, R(.agedBrass)))
        // 下＝撮影レンズ、上＝ファインダーレンズ（ベゼル・絞り環・前玉）
        for (y, r, ring) in [(4.2, 2.75, true), (9.8, 2.45, false)] as [(Double, Double, Bool)] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(r + 0.35, 0), CV2(r + 0.45, 0.4), CV2(r + 0.15, 0.85),
                                           CV2(r, 1.1), CV2(r - 0.15, 2.0), CV2(r - 0.35, 2.35), CV2(0, 2.35)],
                                          segments: 24, chrome), at: CV3(0, y, 5.5), rotation: toFront))
            if ring {
                for k in 0..<18 {
                    let a = Double(k) / 18 * 2 * .pi
                    parts.append(K.block(CV3(0.1, 0.45, 0.16), at: CV3(cos(a) * (r + 0.2), y, 6.3 + sin(a) * 0.05),
                                         radius: 0.03, R(.iron)))
                }
            }
            parts.append(K.placed(K.disc(radius: r - 0.55, height: 0.28, bevel: 0.08, segments: 18, ink),
                                  at: CV3(0, y, 7.75), rotation: toFront))
            parts.append(K.placed(K.ellipsePanel(rx: r * 0.28, ry: r * 0.18, steps: 14, chrome),
                                  at: CV3(-r * 0.15, y + 0.2, 7.95)))
        }
        // 開いた腰レベルフード（4 枚・内側は黒）とすりガラス
        parts.append(K.block(CV3(9.2, 0.4, 9.2), at: CV3(0, 13.45, 0), radius: 0.12, body))
        parts.append(K.placed(K.panel(width: 7.6, height: 7.6, R(.painted(0xC8C4B8))), at: CV3(0, 13.7, 0),
                              rotation: CQuat.axisAngle(CV3(1, 0, 0), -.pi / 2)))
        for (dx, dz, yaw) in [(0.0, 4.9, 0.0), (0.0, -4.9, .pi), (4.9, 0.0, .pi / 2), (-4.9, 0.0, -.pi / 2)] as [(Double, Double, Double)] {
            let q = CQuat.axisAngle(CV3(0, 1, 0), yaw) * CQuat.axisAngle(CV3(1, 0, 0), -0.62)
            parts.append(K.placed(K.panel(width: 8.8, height: 5.2, dark), at: CV3(dx, 16.2, dz), rotation: q))
            parts.append(K.placed(K.panel(width: 8.2, height: 4.6, ink), at: CV3(dx, 16.2, dz) + q.rotate(CV3(0, 0, -0.08)), rotation: q))
        }
        // 側面のピントノブ（大きい）と巻き上げクランク
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.7, 0), CV2(1.85, 0.45), CV2(1.55, 1.1), CV2(1.3, 2.4), CV2(1.45, 2.7), CV2(0, 2.7)],
                                      segments: 18, chrome), at: CV3(5.9, 6.5, 0), rotation: CQuat.axisAngle(CV3(0, 0, 1), -.pi / 2)))
        for k in 0..<10 {
            let a = Double(k) / 10 * 2 * .pi
            parts.append(K.block(CV3(0.14, 0.9, 0.2), at: CV3(6.4, 6.5 + cos(a) * 1.55, sin(a) * 1.55), radius: 0.04, R(.iron)))
        }
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.2, 0), CV2(1.3, 0.4), CV2(1.0, 1.0), CV2(0, 1.0)], segments: 14, chrome),
                              at: CV3(-5.9, 9.5, 0), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2)))
        parts.append(K.tube([CV3(-7.0, 9.5, 0), CV3(-8.2, 9.5, 1.6), CV3(-8.6, 10.8, 1.6)], radius: 0.22, sides: 6, chrome))
        parts.append(K.placed(K.sphere(radius: 0.55, segments: 10, chrome), at: CV3(-8.6, 10.8, 1.6)))
        // スプール軸の突起（左右）
        for x in [-5.5, 5.5] {
            parts.append(K.placed(K.lathe([CV2(0, 0), CV2(0.55, 0), CV2(0.5, 0.7), CV2(0, 0.7)], segments: 10, chrome),
                                  at: CV3(x, 11.5, -4.8), rotation: toFront))
        }
        return K.merge(parts)
    }
}
