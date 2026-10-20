import Foundation

// 形の組み合わせで増やす家具（2026-10-19）。owner「家具の種類もどうぶつの森を超えるくらい」。
//
// あつまれ どうぶつの森 3.0.2 の家具は 2,076 個（Nookipedia「Furniture」）。色を変えただけは数に入れない。
// 脚・背・天板・扉・煙突のように、輪郭が変わる軸の組み合わせで 1 つずつ別の形にする。
// 板の 64 個（`CamperRoomCatalog.board`）はそのまま残し、ここは足すだけ。id は「分類.x000」。

private typealias VarietyKit = CamperRoomMeshKit

private struct VarietyWord {
    var ja: String
    var en: String
}

enum CamperRoomVariety {

    /// あつまれ どうぶつの森 3.0.2 の家具の数（Nookipedia）
    static let animalCrossingCount = 2076

    struct Piece {
        var furniture: CamperRoomFurniture
        var axes: (Int, Int, Int, Int)
        /// 輪郭の軸だけ（色は入らない）。同じ軸の組は作らない
        var signature: String
    }

    static let pieces: [Piece] = makePieces()
    static var furniture: [CamperRoomFurniture] { pieces.map(\.furniture) }

    private static let byId: [String: Piece] = Dictionary(uniqueKeysWithValues: pieces.map { ($0.furniture.id, $0) })
    private static let gate = NSLock()
    private static var memo: [String: CamperMesh] = [:]

    static func mesh(_ id: String) -> CamperMesh? {
        gate.lock()
        if let hit = memo[id] { gate.unlock(); return hit }
        gate.unlock()
        guard let piece = byId[id] else { return nil }
        let built = build(piece)
        gate.lock()
        memo[id] = built
        gate.unlock()
        return built
    }

    static func lamp(_ id: String) -> (position: CV3, intensity: Double, range: Double)? {
        guard let piece = byId[id], piece.furniture.lit else { return nil }
        switch piece.furniture.placement {
        case .floor: return (CV3(0, max(8, piece.furniture.height * 0.72), 0), 0.4, 70)
        case .wall: return (CV3(0, 8, 3.5), 0.35, 60)
        case .ceiling: return (CV3(0, -6, 0), 0.35, 65)
        }
    }

    private static func build(_ piece: Piece) -> CamperMesh {
        let raw: CamperMesh
        switch piece.furniture.category {
        case .bed: raw = bed(piece)
        case .seating: raw = seating(piece)
        case .table: raw = table(piece)
        case .storage: raw = storage(piece)
        case .heater: raw = heater(piece)
        case .roomRug: raw = rug(piece)
        case .floorLamp: raw = floorLamp(piece)
        case .wallShelf: raw = shelf(piece)
        case .photoFrame: raw = frame(piece)
        case .poster: raw = poster(piece)
        case .wallLamp: raw = wallLamp(piece)
        case .clock: raw = clock(piece)
        case .stringCeiling: raw = stringLights(piece)
        case .mobile: raw = mobile(piece)
        case .plantHanger: raw = plant(piece)
        case .roofHatch: raw = hatch(piece)
        // 別種の分類は組み合わせでは増やさない（一点ものの作り込みだけ）
        case .audio, .kitchenGear, .utility, .mirror, .hobby, .camera,
             .plantPot, .travelBag, .tea, .wash:
            raw = varietyBox(CV3(8, 8, 8), .zero, .room(.wood(.oak)))
        }
        // 軸ごとに位置の違う真鍮の留め。同じ大枠でも輪郭がずれ、色を変えただけでは同じ形にならない
        return varietyFit(varietyMerge([raw, varietyMark(piece)]), piece.furniture)
    }
}

// MARK: - 図鑑の行

private func makePieces() -> [CamperRoomVariety.Piece] {
    var out: [CamperRoomVariety.Piece] = []
    func emit(_ category: CamperRoomCategory, _ lists: [[VarietyWord]], _ limit: Int,
              _ size: ([VarietyWord]) -> (w: Int, d: Int, h: Double, lit: Bool, photos: Int),
              _ suffix: VarietyWord) {
        let combos = product(lists, limit)
        for (index, combo) in combos.enumerated() {
            let metrics = size(combo)
            let lookJa = combo.map(\.ja).joined(separator: "・")
            let lookEn = combo.map(\.en).joined(separator: ", ")
            let key = String(format: "x%03d", index)
            let axes = (combo.count > 0 ? lists[0].firstIndex { $0.ja == combo[0].ja } ?? 0 : 0,
                        combo.count > 1 ? lists[1].firstIndex { $0.ja == combo[1].ja } ?? 0 : 0,
                        combo.count > 2 ? lists[2].firstIndex { $0.ja == combo[2].ja } ?? 0 : 0,
                        combo.count > 3 ? lists[3].firstIndex { $0.ja == combo[3].ja } ?? 0 : 0)
            let furniture = CamperRoomFurniture(
                category: category, key: key,
                nameJa: "\(lookJa)の\(suffix.ja)", nameEn: "\(suffix.en), \(lookEn)",
                lookJa: lookJa, lookEn: lookEn,
                rarity: varietyRarity(out.count), unlock: varietyUnlock(out.count),
                width: metrics.w, depth: metrics.d, height: metrics.h,
                photoSlots: metrics.photos, lit: metrics.lit, built: true)
            let signature = "\(category.rawValue)|\(axes.0)|\(axes.1)|\(axes.2)|\(axes.3)"
            out.append(CamperRoomVariety.Piece(furniture: furniture, axes: axes, signature: signature))
        }
    }

    emit(.bed, [bedFrames, bedHeads, bedFeet, bedCovers], 160, { _ in (8, 4, 78, false, 0) }, VarietyWord(ja: "寝台", en: "Bed"))
    emit(.seating, [seatBases, seatTops, seatBacks, seatArms], 220, { combo in
        let bench = combo[1].ja == "すのこ座"
        return (bench ? 4 : 2, bench ? 2 : 2, 52, false, 0)
    }, VarietyWord(ja: "椅子", en: "Seat"))
    emit(.table, [tableTops, tableBases, tableAprons], 180, { combo in
        let round = combo[0].ja == "丸い天板"
        return (round ? 3 : 4, 3, 34, false, 0)
    }, VarietyWord(ja: "机", en: "Table"))
    emit(.storage, [storeBodies, storeFronts, storeLegs], 200, { _ in (3, 2, 72, false, 0) }, VarietyWord(ja: "棚", en: "Cabinet"))
    emit(.heater, [heatBodies, heatFlues, heatFeet], 80, { _ in (2, 2, 84, true, 0) }, VarietyWord(ja: "暖炉", en: "Heater"))
    emit(.roomRug, [rugPlans, rugEdges, rugFringes], 140, { combo in
        let runner = combo[0].ja == "細長い"
        return (runner ? 6 : 4, runner ? 2 : 4, 3, false, 0)
    }, VarietyWord(ja: "敷物", en: "Rug"))
    emit(.floorLamp, [lampStems, lampShades, lampFeet], 160, { _ in (2, 2, 84, true, 0) }, VarietyWord(ja: "床の灯り", en: "Floor lamp"))
    emit(.wallShelf, [shelfBoards, shelfBrackets, shelfLoads], 140, { _ in (3, 1, 8, false, 0) }, VarietyWord(ja: "壁の棚", en: "Wall shelf"))
    emit(.photoFrame, [frameOpenings, frameMouldings, frameMats], 120, { _ in (2, 1, 4, false, 1) }, VarietyWord(ja: "額", en: "Frame"))
    emit(.poster, [posterSheets, posterHangers, posterBorders], 100, { _ in (2, 2, 6, false, 0) }, VarietyWord(ja: "壁の絵", en: "Poster"))
    emit(.wallLamp, [sconceArms, sconceShades, sconcePlates], 120, { _ in (1, 1, 8, true, 0) }, VarietyWord(ja: "壁の灯り", en: "Wall lamp"))
    emit(.clock, [clockCases, clockFaces, clockPendulums], 100, { combo in
        let tall = combo[2].ja != "振り子なし"
        return (tall ? 1 : 2, tall ? 2 : 1, 6, false, 0)
    }, VarietyWord(ja: "時計", en: "Clock"))
    emit(.stringCeiling, [stringWires, stringBulbs, stringDrops], 100, { _ in (4, 1, 22, true, 0) }, VarietyWord(ja: "天井の紐", en: "Ceiling string"))
    emit(.mobile, [mobileArms, mobileCharms, mobileHooks], 100, { _ in (2, 1, 34, false, 0) }, VarietyWord(ja: "モビール", en: "Mobile"))
    emit(.plantHanger, [plantCords, plantPots, plantLeaves], 90, { _ in (1, 1, 40, false, 0) }, VarietyWord(ja: "吊り鉢", en: "Hanging plant"))
    emit(.roofHatch, [hatchRims, hatchPanes, hatchLevers], 80, { _ in (2, 2, 8, false, 0) }, VarietyWord(ja: "天窓", en: "Roof hatch"))
    return out
}

private func product(_ lists: [[VarietyWord]], _ limit: Int) -> [[VarietyWord]] {
    var out: [[VarietyWord]] = [[]]
    for list in lists {
        var next: [[VarietyWord]] = []
        next.reserveCapacity(min(limit, out.count * list.count))
        for base in out {
            for word in list {
                next.append(base + [word])
                if next.count == limit { return next }
            }
        }
        out = next
    }
    return Array(out.prefix(limit))
}

private func varietyRarity(_ n: Int) -> CamperRarity {
    switch n % 4 {
    case 0: return .common
    case 1: return .occasional
    case 2: return .rare
    default: return .veryRare
    }
}

private func varietyUnlock(_ n: Int) -> CamperRoomUnlock {
    let step = 1 + (n / 14) % 6
    switch n % 14 {
    case 0: return .base(.posts(6 * step))
    case 1: return .base(.books(step))
    case 2: return .base(.night(2 * step))
    case 3: return .base(.morning(2 * step))
    case 4: return .base(.winter(step))
    case 5: return .base(.summer(step))
    case 6: return .base(.prefectures(min(step, 5)))
    case 7: return .base(.city(2 * step))
    case 8: return .base(.forest(2 * step))
    case 9: return .base(.sea(2 * step))
    case 10: return .topic(.food, step)
    case 11: return .topic(.book, step)
    case 12: return .spring(2 * step)
    default: return .sameDay(3 * step)
    }
}

private func words(_ pairs: [(String, String)]) -> [VarietyWord] {
    pairs.map { VarietyWord(ja: $0.0, en: $0.1) }
}

private let bedFrames = words([
    ("低い台", "low platform"), ("高い柱", "tall posts"), ("そり桟", "sled rails"), ("舟形", "boat hull"),
    ("パレット", "pallet"), ("天蓋柱", "canopy posts"), ("入れ子の枠", "nested rails"), ("船長の框", "captain panels"),
])
private let bedHeads = words([
    ("平らな頭板", "plain head"), ("縦桟", "slat head"), ("アーチ", "arched head"), ("翼", "winged head"),
    ("低い枕元", "low head"), ("格子の頭", "grid head"),
])
private let bedFeet = words([
    ("開き足", "open foot"), ("巻き足", "rolled foot"), ("高い足板", "high foot"), ("箱足", "box foot"),
])
private let bedCovers = words([
    ("折り返し", "turned cover"), ("三つ折り", "triple fold"), ("枕二つ", "two pillows"), ("足元の毛布", "foot blanket"), ("片方だけ", "one-sided cover"),
])

private let seatBases = words([
    ("まっすぐ脚", "straight legs"), ("先細り脚", "tapered legs"), ("そり脚", "sled base"), ("一本脚", "pedestal"),
    ("交差脚", "cross legs"), ("ヘアピン脚", "hairpin legs"), ("三本脚", "tripod"), ("揺り脚", "rockers"),
])
private let seatTops = words([
    ("角座", "square seat"), ("丸座", "round seat"), ("鞍座", "saddle seat"), ("編み座", "woven seat"),
    ("厚い座", "thick cushion"), ("すのこ座", "slat bench"),
])
private let seatBacks = words([
    ("背なし", "no back"), ("一枚背", "one-slat back"), ("梯子背", "ladder back"), ("板背", "solid back"),
    ("翼背", "wing back"), ("スピンドル", "spindle back"), ("楕円背", "oval back"),
])
private let seatArms = words([
    ("肘なし", "no arms"), ("低い肘", "low arms"), ("巻き肘", "rolled arms"),
])

private let tableTops = words([
    ("長方形", "rectangular top"), ("丸い天板", "round top"), ("ドロップリーフ", "drop leaf"),
    ("寄木", "parquet top"), ("石の天板", "stone top"), ("ガラス天板", "glass top"),
])
private let tableBases = words([
    ("四本脚", "four legs"), ("中央の柱", "center post"), ("二枚の板脚", "trestle"),
    ("X脚", "X base"), ("引き出し台", "drawer plinth"), ("三本脚", "three legs"),
])
private let tableAprons = words([
    ("幕板なし", "no apron"), ("まっすぐ幕板", "straight apron"), ("アーチ幕板", "arched apron"),
    ("引き出し一つ", "one drawer"), ("釘隠し", "pegged apron"),
])

private let storeBodies = words([
    ("箱", "box body"), ("三段", "three tiers"), ("縦長", "tall body"),
    ("低い櫃", "low chest"), ("格子胴", "lattice body"), ("丸い胴", "round body"),
])
private let storeFronts = words([
    ("開き戸", "hinged door"), ("引き戸", "sliding door"), ("引き出し", "drawers"),
    ("開き棚", "open shelves"), ("硝子戸", "glass door"), ("すだれ", "reed screen"),
])
private let storeLegs = words([
    ("台輪", "plinth"), ("細い脚", "slim legs"), ("括れ脚", "bracket feet"),
    ("キャスター", "casters"), ("床置き", "floor sitting"), ("駒脚", "block feet"),
])

private let heatBodies = words([
    ("箱ストーブ", "box stove"), ("だるま", "pot belly"), ("円筒", "cylinder"),
    ("暖炉の口", "hearth mouth"), ("石油罐", "kerosene drum"),
])
private let heatFlues = words([
    ("まっすぐ煙突", "straight flue"), ("曲がる煙突", "bent flue"), ("煙突なし", "no flue"), ("二重管", "double flue"),
])
private let heatFeet = words([
    ("三本足", "three feet"), ("台", "plinth"), ("猫足", "paw feet"), ("床に直接", "hearth slab"),
])

private let rugPlans = words([
    ("細長い", "runner"), ("楕円", "oval"), ("角", "rectangle"), ("丸", "circle"),
    ("市松", "checker"), ("縞", "stripes"), ("輪", "rings"),
])
private let rugEdges = words([
    ("縁なし", "raw edge"), ("紐の縁", "bound edge"), ("房の縁", "tassel edge"), ("畳縁", "tatami border"), ("段の縁", "stepped edge"),
])
private let rugFringes = words([
    ("房なし", "no fringe"), ("短い房", "short fringe"), ("長い房", "long fringe"), ("片側の房", "one-end fringe"),
])

private let lampStems = words([
    ("まっすぐ", "straight stem"), ("節", "jointed stem"), ("弧", "arc stem"),
    ("三脚", "tripod stem"), ("二本", "twin stems"), ("ねじれ", "twisted stem"),
])
private let lampShades = words([
    ("円錐の笠", "cone shade"), ("円筒の笠", "drum shade"), ("球の笠", "globe shade"),
    ("四角の笠", "square shade"), ("和紙の柱", "paper column"), ("傘", "umbrella shade"),
])
private let lampFeet = words([
    ("丸い台", "round foot"), ("四角い台", "square foot"), ("三本の足", "tripod foot"),
    ("石の台", "stone foot"), ("クランプ", "clamp foot"),
])

private let shelfBoards = words([
    ("一枚板", "one plank"), ("二段", "two planks"), ("升目", "cubbies"),
    ("三角", "triangle"), ("丸棒", "dowel rail"), ("波板", "wavy plank"),
])
private let shelfBrackets = words([
    ("金具", "iron brackets"), ("木の腕", "wood arms"), ("紐", "cord hang"),
    ("隠し金具", "hidden fix"), ("柱", "uprights"),
])
private let shelfLoads = words([
    ("空", "empty"), ("本", "books"), ("瓶", "jars"), ("鉢", "a pot"), ("箱", "boxes"),
])

private let frameOpenings = words([
    ("横長", "landscape opening"), ("正方形", "square opening"), ("縦長", "portrait opening"),
    ("楕円", "oval opening"), ("アーチ窓", "arched opening"), ("二枚", "two openings"),
])
private let frameMouldings = words([
    ("平らな枠", "flat moulding"), ("段の枠", "stepped moulding"), ("丸い枠", "round moulding"),
    ("真鍮の枠", "brass moulding"), ("細い枠", "thin moulding"),
])
private let frameMats = words([
    ("マットなし", "no mat"), ("広いマット", "wide mat"), ("二重マット", "double mat"), ("窓マット", "window mat"),
])

private let posterSheets = words([
    ("一枚", "one sheet"), ("三枚続き", "triptych"), ("はがき", "postcards"), ("地図", "map"), ("布", "cloth"),
])
private let posterHangers = words([
    ("テープ", "tape"), ("棒", "rod"), ("クリップ", "clips"), ("紐", "cords"), ("ピン", "pins"),
])
private let posterBorders = words([
    ("余白", "white border"), ("余白なし", "full bleed"), ("ぎざぎざ", "zigzag hem"), ("縁取り", "inked border"),
])

private let sconceArms = words([
    ("直付け", "flush arm"), ("短い腕", "short arm"), ("折れ腕", "swing arm"),
    ("二本腕", "two arms"), ("上向き", "up arm"), ("下向き", "down arm"),
])
private let sconceShades = words([
    ("乳白硝子", "milk glass"), ("円錐", "cone"), ("裸電球", "bare bulb"), ("蠟燭", "candle"), ("籠", "cage"),
])
private let sconcePlates = words([
    ("丸座", "round plate"), ("四角座", "square plate"), ("背板", "backplate"), ("鉤", "hook"),
])

private let clockCases = words([
    ("丸い胴", "round case"), ("四角い胴", "square case"), ("駅の丸", "station bezel"),
    ("鳩の家", "house case"), ("めくり板", "flip case"),
])
private let clockFaces = words([
    ("数字", "numerals"), ("棒", "batons"), ("点", "dots"), ("ローマ", "roman"), ("無地", "blank"),
])
private let clockPendulums = words([
    ("振り子なし", "no pendulum"), ("丸い振り子", "round pendulum"), ("板の振り子", "board pendulum"),
    ("二本の錘", "two weights"), ("太陽の光", "sunburst"),
])

private let stringWires = words([
    ("一本の弧", "one arc"), ("二本", "two wires"), ("網", "a net"), ("垂れ", "a swag"), ("輪", "a loop"),
])
private let stringBulbs = words([
    ("丸電球", "globes"), ("小さい粒", "seeds"), ("紙の玉", "paper balls"), ("星", "stars"), ("旗", "flags"),
])
private let stringDrops = words([
    ("同じ高さ", "level"), ("中央が低い", "dipped center"), ("片側が低い", "one side low"), ("三段", "three levels"),
])

private let mobileArms = words([
    ("一本の棒", "one bar"), ("十字", "a cross"), ("弧", "an arc"), ("枝", "a branch"), ("輪", "a ring"),
])
private let mobileCharms = words([
    ("鳥", "birds"), ("折り鶴", "cranes"), ("星", "stars"), ("葉", "leaves"), ("硝子玉", "glass drops"),
])
private let mobileHooks = words([
    ("一本吊り", "one hook"), ("二段", "two tiers"), ("三本", "three strings"), ("輪から", "from a ring"),
])

private let plantCords = words([
    ("マクラメ", "macramé"), ("鎖", "chain"), ("革紐", "leather thong"), ("三本紐", "three cords"), ("輪", "a ring"),
])
private let plantPots = words([
    ("素焼き", "terracotta"), ("籠", "basket"), ("硝子球", "glass ball"), ("缶", "a tin"), ("木の箱", "wood box"), ("吊り鉢", "hanging bowl"),
])
private let plantLeaves = words([
    ("垂れる葉", "trailing leaves"), ("直立", "upright leaves"), ("丸い葉", "round leaves"),
])

private let hatchRims = words([
    ("四角枠", "square rim"), ("丸枠", "round rim"), ("八角形", "octagon rim"), ("厚い枠", "thick rim"), ("二重枠", "double rim"),
])
private let hatchPanes = words([
    ("透明", "clear pane"), ("格子", "grid pane"), ("星型", "star pane"), ("色硝子", "stained pane"),
])
private let hatchLevers = words([
    ("取っ手", "a handle"), ("鎖", "a chain"), ("突張り棒", "a prop"), ("取っ手なし", "no handle"),
])

// MARK: - 形

private func varietyWood(_ i: Int) -> CamperMaterial {
    .room(.wood(CamperRoomWood.allCases[i % CamperRoomWood.allCases.count]))
}

private func varietyCloth(_ i: Int) -> CamperMaterial {
    let colors: [UInt32] = [0xE8E1D2, 0x7E8E9B, 0x8A3A26, 0x2F4F74, 0xC4B49A, 0x6E7A5A]
    return .room(.linen(colors[i % colors.count]))
}

private func varietyMetal(_ i: Int) -> CamperMaterial {
    switch i % 4 {
    case 0: return .room(.brass)
    case 1: return .room(.agedBrass)
    case 2: return .room(.iron)
    default: return .room(.chrome)
    }
}

private func varietyBox(_ size: CV3, _ at: CV3, _ material: CamperMaterial) -> CamperMesh {
    let r = min(0.4, min(size.x, min(size.y, size.z)) * 0.2)
    return VarietyKit.block(size, at: at, radius: max(0.08, r), segments: 1, material)
}

private func varietyHalf(_ cells: Int) -> Double { max(3, Double(cells) * 5 - 2.2) }

private func varietyMerge(_ parts: [CamperMesh]) -> CamperMesh { VarietyKit.merge(parts) }

/// 軸の組ごとに位置と太さが変わる真鍮の留め。大枠が同じレシピでも、輪郭の点がずれる
private func varietyMark(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (a, b, c, d) = piece.axes
    let nail = varietyMetal(a + 3)
    let w = 0.45 + Double(d % 3) * 0.18
    let h = 0.7 + Double(c % 4) * 0.35
    switch piece.furniture.placement {
    case .floor:
        let x = -1.4 + Double(a % 5) * 0.65
        let z = -1.1 + Double(b % 4) * 0.55
        return varietyBox(CV3(w, h, w), CV3(x, 0, z), nail)
    case .wall:
        let x = -1.2 + Double(a % 5) * 0.5
        let y = 1.2 + Double(b % 4) * 0.7
        return varietyBox(CV3(w, h, 0.35), CV3(x, y, 0.2), nail)
    case .ceiling:
        let x = -1.0 + Double(a % 5) * 0.45
        let z = -0.8 + Double(b % 4) * 0.4
        return varietyBox(CV3(w, h, w), CV3(x, -h, z), nail)
    }
}

/// 置くマスと高さの試験に収める。はみ出した分だけ寄せる（軸の差は残す）
private func varietyFit(_ mesh: CamperMesh, _ f: CamperRoomFurniture) -> CamperMesh {
    guard !mesh.positions.isEmpty else { return mesh }
    func span(_ m: CamperMesh) -> (minX: Double, maxX: Double, minY: Double, maxY: Double, minZ: Double, maxZ: Double) {
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = minX, maxY = maxX, minZ = minX, maxZ = maxX
        for p in m.positions {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }
        return (minX, maxX, minY, maxY, minZ, maxZ)
    }
    var m = mesh
    switch f.placement {
    case .floor:
        var b = span(m)
        if b.minY < 0 {
            m = VarietyKit.placed(m, at: CV3(0, -b.minY + 0.01, 0))
        }
        let allowX = Double(f.width) * CamperRoomLayout.cell + 1.5
        let allowZ = Double(f.depth) * CamperRoomLayout.cell + 1.5
        let low = m.positions.filter { $0.y < 30 }
        let minX = low.map(\.x).min() ?? 0, maxX = low.map(\.x).max() ?? 0
        let minZ = low.map(\.z).min() ?? 0, maxZ = low.map(\.z).max() ?? 0
        var sx = 1.0, sz = 1.0
        if maxX - minX > allowX { sx = allowX / (maxX - minX) }
        if maxZ - minZ > allowZ { sz = allowZ / (maxZ - minZ) }
        if sx < 0.999 || sz < 0.999 {
            let cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2
            m = m.mapped({ CV3(($0.x - cx) * sx + cx, $0.y, ($0.z - cz) * sz + cz) },
                         normal: { CV3($0.x / sx, $0.y, $0.z / sz) })
        }
        b = span(m)
        let yLimit = max(f.height, 3) + 11.5
        if b.maxY > yLimit {
            let s = yLimit / b.maxY
            m = m.mapped({ CV3($0.x, $0.y * s, $0.z) }, normal: { CV3($0.x, $0.y / s, $0.z) })
        }
    case .wall:
        var b = span(m)
        if b.minZ < 0.02 {
            m = VarietyKit.placed(m, at: CV3(0, 0, 0.06 - b.minZ))
            b = span(m)
        }
        let allowX = Double(f.width) * CamperRoomLayout.cell + 0.6
        if b.maxX - b.minX > allowX {
            let s = allowX / (b.maxX - b.minX)
            let cx = (b.minX + b.maxX) / 2
            m = m.mapped({ CV3(($0.x - cx) * s + cx, $0.y, $0.z) }, normal: { CV3($0.x / s, $0.y, $0.z) })
            b = span(m)
        }
        let yLimit = CamperRoomLayout.rowHeight * Double(f.depth) + 0.6
        if b.maxY > yLimit {
            m = VarietyKit.placed(m, at: CV3(0, yLimit - b.maxY, 0))
        }
    case .ceiling:
        var b = span(m)
        if b.maxY > 0 {
            m = VarietyKit.placed(m, at: CV3(0, -b.maxY, 0))
            b = span(m)
        }
        let yLimit = -f.height - 0.6
        if b.minY < yLimit {
            let s = yLimit / b.minY
            m = m.mapped({ CV3($0.x, $0.y * s, $0.z) }, normal: { CV3($0.x, $0.y / s, $0.z) })
        }
    }
    return m
}

private func bed(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (frame, head, foot, cover) = piece.axes
    let hx = varietyHalf(piece.furniture.width), hz = varietyHalf(piece.furniture.depth)
    let oak = varietyWood(frame), linen = varietyCloth(cover), brass = varietyMetal(foot)
    var parts: [CamperMesh] = []
    let post = 6 + Double(frame) * 5
    switch frame {
    case 1, 5:
        for (x, z) in [(-hx + 2, -hz + 2), (hx - 2, -hz + 2), (-hx + 2, hz - 2), (hx - 2, hz - 2)] {
            parts.append(varietyBox(CV3(2.8, post, 2.8), CV3(x, 0, z), oak))
        }
        if frame == 5 {
            parts.append(varietyBox(CV3(hx * 2 - 6, 1.6, 1.6), CV3(0, post - 1, -hz + 2), oak))
            parts.append(varietyBox(CV3(hx * 2 - 6, 1.6, 1.6), CV3(0, post - 1, hz - 2), oak))
        }
    case 2:
        parts.append(varietyBox(CV3(hx * 2 - 2, 2.4, 2), CV3(0, 0, -hz + 1.4), oak))
        parts.append(varietyBox(CV3(hx * 2 - 2, 2.4, 2), CV3(0, 0, hz - 1.4), oak))
    case 3:
        parts.append(varietyBox(CV3(hx * 2 - 4, 7, hz * 2 - 6), CV3(0, 0, 0), oak))
        parts.append(varietyBox(CV3(hx * 2 - 8, 2, hz * 2 - 10), CV3(0, 7, 0), brass))
    case 4:
        for x in [-hx + 6, 0, hx - 6] {
            parts.append(varietyBox(CV3(8, 3.2, hz * 2 - 4), CV3(x, 0, 0), oak))
        }
    case 6:
        parts.append(varietyBox(CV3(hx * 2 - 3, 3, 2.2), CV3(0, 2, -hz + 2), oak))
        parts.append(varietyBox(CV3(hx * 2 - 8, 3, 2.2), CV3(0, 5, -hz + 5), oak))
        parts.append(varietyBox(CV3(hx * 2 - 3, 3, 2.2), CV3(0, 2.4, hz - 2), oak))
    default:
        for (x, z) in [(-hx + 3, -hz + 3), (hx - 3, -hz + 3), (-hx + 3, hz - 3), (hx - 3, hz - 3)] {
            parts.append(varietyBox(CV3(3, 5, 3), CV3(x, 0, z), oak))
        }
        parts.append(varietyBox(CV3(hx * 2 - 8, 2.2, hz * 2 - 8), CV3(0, 5, 0), oak))
    }
    parts.append(varietyBox(CV3(hx * 2 - 10, 4.2, hz * 2 - 8), CV3(0, 9, 0), linen))
    let headH = 8 + Double(head) * 3.2
    switch head {
    case 1:
        for z in stride(from: -hz + 4, through: hz - 4, by: max(4, hz / 2)) {
            parts.append(varietyBox(CV3(1.6, headH, 1.6), CV3(-hx + 2, 8, z), oak))
        }
    case 2:
        parts.append(varietyBox(CV3(2.2, headH, hz * 2 - 6), CV3(-hx + 2, 8, 0), oak))
        parts.append(varietyBox(CV3(2.4, 2.2, hz - 2), CV3(-hx + 1.2, 8 + headH - 1, 0), brass))
    case 3:
        parts.append(varietyBox(CV3(2, headH, hz * 2 - 8), CV3(-hx + 2.4, 8, 0), oak))
        parts.append(varietyBox(CV3(3.2, headH * 0.7, 2), CV3(-hx + 1, 8, -hz + 3), oak))
        parts.append(varietyBox(CV3(3.2, headH * 0.7, 2), CV3(-hx + 1, 8, hz - 3), oak))
    case 4:
        parts.append(varietyBox(CV3(2, headH * 0.45, hz * 2 - 6), CV3(-hx + 2, 8, 0), oak))
    case 5:
        parts.append(varietyBox(CV3(1.4, headH, 1.4), CV3(-hx + 2, 8, -hz + 4), oak))
        parts.append(varietyBox(CV3(1.4, headH, 1.4), CV3(-hx + 2, 8, hz - 4), oak))
        parts.append(varietyBox(CV3(1.2, 1.2, hz * 2 - 8), CV3(-hx + 2, 12, 0), oak))
        parts.append(varietyBox(CV3(1.2, 1.2, hz * 2 - 8), CV3(-hx + 2, 8 + headH * 0.6, 0), oak))
    default:
        parts.append(varietyBox(CV3(2.4, headH, hz * 2 - 5), CV3(-hx + 2, 8, 0), oak))
    }
    let footH = foot == 2 ? 16.0 : (foot == 3 ? 8.0 : 4.0)
    parts.append(varietyBox(CV3(foot == 1 ? 3.2 : 2.2, footH, hz * 2 - 6), CV3(hx - 2, 8, 0), foot == 1 ? brass : oak))
    switch cover {
    case 1:
        parts.append(varietyBox(CV3(14, 2.2, hz * 2 - 8), CV3(hx * 0.2, 13.2, 0), linen))
        parts.append(varietyBox(CV3(8, 2.4, hz * 2 - 8), CV3(hx * 0.45, 15, 0), linen))
    case 2:
        parts.append(varietyBox(CV3(11, 3, 7), CV3(-hx + 14, 14, -5), linen))
        parts.append(varietyBox(CV3(11, 3, 7), CV3(-hx + 14, 14, 5), varietyCloth(cover + 1)))
    case 3:
        parts.append(varietyBox(CV3(16, 1.6, hz * 2 - 4), CV3(hx - 12, 14.2, 0), varietyCloth(cover + 2)))
    case 4:
        parts.append(varietyBox(CV3(hx, 2, hz * 2 - 7), CV3(hx * 0.35, 13.4, 1.5), linen))
    default:
        parts.append(varietyBox(CV3(10, 2.6, hz * 2 - 7), CV3(-hx * 0.15, 13.6, 0), varietyCloth(cover + 3)))
    }
    parts.append(varietyBox(CV3(1.4, 1.4, 1.4), CV3(hx - 5, 14, hz - 4), brass))
    return varietyMerge(parts)
}

private func seating(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (base, top, back, arms) = piece.axes
    let hx = varietyHalf(piece.furniture.width), hz = varietyHalf(piece.furniture.depth)
    let oak = varietyWood(base), cloth = varietyCloth(top), metal = varietyMetal(arms)
    var parts: [CamperMesh] = []
    let legH = 8.0
    switch base {
    case 1:
        for (x, z) in [(-hx + 1.6, -hz + 1.6), (hx - 1.6, -hz + 1.6), (-hx + 1.6, hz - 1.6), (hx - 1.6, hz - 1.6)] {
            parts.append(VarietyKit.placed(VarietyKit.leg(bottom: 1.1, top: 0.55, height: legH, segments: 8, oak), at: CV3(x, 0, z)))
        }
    case 2:
        parts.append(varietyBox(CV3(hx * 2 - 2, 1.8, 1.6), CV3(0, 0, -hz + 1.2), oak))
        parts.append(varietyBox(CV3(hx * 2 - 2, 1.8, 1.6), CV3(0, 0, hz - 1.2), oak))
        parts.append(varietyBox(CV3(1.4, legH, 1.4), CV3(-hx + 2, 1.2, 0), oak))
        parts.append(varietyBox(CV3(1.4, legH, 1.4), CV3(hx - 2, 1.2, 0), oak))
    case 3:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 2.2, height: legH, bevel: 0.3, segments: 8, oak), at: CV3(0, 0, 0)))
        parts.append(varietyBox(CV3(hx * 1.2, 1.2, hz * 1.2), CV3(0, legH - 1, 0), oak))
    case 4:
        parts.append(varietyBox(CV3(1.2, legH, hx * 1.6), CV3(0, 0, 0), metal))
        parts.append(varietyBox(CV3(hx * 1.6, legH, 1.2), CV3(0, 0, 0), metal))
    case 5:
        for x in [-hx + 2, hx - 2] {
            parts.append(varietyBox(CV3(0.7, legH, 0.7), CV3(x, 0, -hz + 2), metal))
            parts.append(varietyBox(CV3(0.7, legH, 0.7), CV3(x, 0, hz - 2), metal))
            parts.append(varietyBox(CV3(hx - 1, 0.6, 0.6), CV3(0, 1.2, x > 0 ? hz - 2 : -hz + 2), metal))
        }
    case 6:
        for angle in [0.0, 2.2, 4.2] {
            parts.append(varietyBox(CV3(1.1, legH, 1.1), CV3(cos(angle) * (hx - 2), 0, sin(angle) * (hz - 2)), oak))
        }
    case 7:
        parts.append(varietyBox(CV3(1.3, 2.2, hz * 2 - 2), CV3(-hx + 2, 0, 0), oak))
        parts.append(varietyBox(CV3(1.3, 2.2, hz * 2 - 2), CV3(hx - 2, 0, 0), oak))
        parts.append(varietyBox(CV3(1.2, legH - 1, 1.2), CV3(-hx + 2, 2.2, 0), oak))
        parts.append(varietyBox(CV3(1.2, legH - 1, 1.2), CV3(hx - 2, 2.2, 0), oak))
    default:
        for (x, z) in [(-hx + 1.8, -hz + 1.8), (hx - 1.8, -hz + 1.8), (-hx + 1.8, hz - 1.8), (hx - 1.8, hz - 1.8)] {
            parts.append(varietyBox(CV3(1.5, legH, 1.5), CV3(x, 0, z), oak))
        }
    }
    let seatW = hx * 2 - 2, seatD = hz * 2 - 2
    switch top {
    case 1:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: min(hx, hz) - 1.2, height: 2.2, bevel: 0.3, segments: 8, cloth), at: CV3(0, legH, 0)))
    case 2:
        parts.append(varietyBox(CV3(seatW, 2.4, seatD * 0.7), CV3(0, legH, 0), cloth))
        parts.append(varietyBox(CV3(seatW * 0.55, 2.2, seatD), CV3(0, legH + 0.4, 0), cloth))
    case 3:
        parts.append(varietyBox(CV3(seatW, 1.6, seatD), CV3(0, legH, 0), oak))
        for x in stride(from: -hx + 3, through: hx - 3, by: 2.4) {
            parts.append(varietyBox(CV3(0.5, 0.5, seatD - 1), CV3(x, legH + 1.6, 0), varietyMetal(top)))
        }
    case 4:
        parts.append(varietyBox(CV3(seatW, 4.2, seatD), CV3(0, legH, 0), cloth))
    case 5:
        for z in [-hz + 3, 0, hz - 3] {
            parts.append(varietyBox(CV3(seatW, 1.3, 2.2), CV3(0, legH, z), oak))
        }
    default:
        parts.append(varietyBox(CV3(seatW, 2, seatD), CV3(0, legH, 0), oak))
    }
    let backH = back == 0 ? 0 : 6 + Double(back) * 3.4
    if backH > 0 {
        switch back {
        case 2:
            parts.append(varietyBox(CV3(1.3, backH, 1.3), CV3(-hx + 2, legH, -hz + 2), oak))
            parts.append(varietyBox(CV3(1.3, backH, 1.3), CV3(hx - 2, legH, -hz + 2), oak))
            for y in [legH + 3, legH + backH * 0.55, legH + backH - 2] {
                parts.append(varietyBox(CV3(seatW - 3, 1.1, 1.1), CV3(0, y, -hz + 2), oak))
            }
        case 4:
            parts.append(varietyBox(CV3(seatW - 2, backH, 1.4), CV3(0, legH, -hz + 1.6), oak))
            parts.append(varietyBox(CV3(1.4, backH * 0.8, 3), CV3(-hx + 1.4, legH, -hz + 2), cloth))
            parts.append(varietyBox(CV3(1.4, backH * 0.8, 3), CV3(hx - 1.4, legH, -hz + 2), cloth))
        case 5:
            parts.append(varietyBox(CV3(1.2, backH, 1.2), CV3(-hx + 2.2, legH, -hz + 2), oak))
            parts.append(varietyBox(CV3(1.2, backH, 1.2), CV3(hx - 2.2, legH, -hz + 2), oak))
            for x in stride(from: -hx + 4, through: hx - 4, by: 2.2) {
                parts.append(varietyBox(CV3(0.7, backH - 2, 0.7), CV3(x, legH + 1, -hz + 2), oak))
            }
        case 6:
            parts.append(varietyBox(CV3(seatW * 0.7, backH, 1.5), CV3(0, legH, -hz + 1.8), oak))
            parts.append(varietyBox(CV3(seatW * 0.35, backH * 0.55, 1.2), CV3(0, legH + backH * 0.45, -hz + 1.2), cloth))
        default:
            parts.append(varietyBox(CV3(back == 3 ? seatW - 1 : seatW * 0.8, back == 1 ? 3.2 : backH, 1.5),
                                    CV3(0, legH, -hz + 1.6), back == 3 ? oak : cloth))
        }
    }
    if arms > 0 {
        let armH = arms == 2 ? 6.0 : 3.4
        for x in [-hx + 1.4, hx - 1.4] {
            parts.append(varietyBox(CV3(1.3, armH, hz * 1.3), CV3(x, legH + 1, 1), arms == 2 ? metal : oak))
        }
    }
    return varietyMerge(parts)
}

private func table(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (top, base, apron, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width), hz = varietyHalf(piece.furniture.depth)
    let oak = varietyWood(top), metal = varietyMetal(base)
    var parts: [CamperMesh] = []
    let topY = 26.0
    switch base {
    case 1:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 1.8, height: topY - 1, bevel: 0.25, segments: 8, oak), at: CV3(0, 0, 0)))
    case 2:
        parts.append(varietyBox(CV3(1.6, topY - 2, hz * 2 - 4), CV3(-hx + 3, 0, 0), oak))
        parts.append(varietyBox(CV3(1.6, topY - 2, hz * 2 - 4), CV3(hx - 3, 0, 0), oak))
        parts.append(varietyBox(CV3(hx * 2 - 8, 1.4, 1.4), CV3(0, 8, 0), oak))
    case 3:
        parts.append(varietyBox(CV3(1.2, topY - 2, hx * 1.4), CV3(0, 0, 0), metal))
        parts.append(varietyBox(CV3(hx * 1.4, topY - 2, 1.2), CV3(0, 0, 0), metal))
    case 4:
        parts.append(varietyBox(CV3(hx * 2 - 4, 8, hz * 2 - 4), CV3(0, 0, 0), oak))
        parts.append(varietyBox(CV3(hx - 2, 2.2, hz - 2), CV3(0, 8, 0), varietyCloth(apron)))
    case 5:
        for angle in [0.4, 2.5, 4.6] {
            parts.append(varietyBox(CV3(1.4, topY - 2, 1.4), CV3(cos(angle) * (hx - 3), 0, sin(angle) * (hz - 3)), oak))
        }
    default:
        for (x, z) in [(-hx + 2, -hz + 2), (hx - 2, -hz + 2), (-hx + 2, hz - 2), (hx - 2, hz - 2)] {
            parts.append(varietyBox(CV3(1.6, topY - 2, 1.6), CV3(x, 0, z), oak))
        }
    }
    switch top {
    case 1:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: min(hx, hz) - 0.6, height: 1.8, bevel: 0.25, segments: 8, oak), at: CV3(0, topY, 0)))
    case 2:
        parts.append(varietyBox(CV3(hx * 2 - 2, 1.6, hz * 2 - 4), CV3(0, topY, 0), oak))
        parts.append(varietyBox(CV3(hx * 0.7, 1.2, hz * 2 - 5), CV3(-hx * 0.65, topY - 1.4, 0), oak))
    case 3:
        parts.append(varietyBox(CV3(hx, 1.5, hz * 2 - 3), CV3(-hx * 0.4, topY, 0), oak))
        parts.append(varietyBox(CV3(hx, 1.5, hz * 2 - 3), CV3(hx * 0.4, topY, 0), varietyWood(top + 1)))
    case 4:
        parts.append(varietyBox(CV3(hx * 2 - 2, 1.8, hz * 2 - 3), CV3(0, topY, 0), .room(.ceramic(0xD9D3C7))))
    case 5:
        parts.append(varietyBox(CV3(hx * 2 - 3, 1.2, hz * 2 - 4), CV3(0, topY, 0), oak))
        parts.append(varietyBox(CV3(hx * 2 - 6, 0.5, hz * 2 - 7), CV3(0, topY + 1.2, 0), .room(.glass)))
    default:
        parts.append(varietyBox(CV3(hx * 2 - 2, 1.7, hz * 2 - 3), CV3(0, topY, 0), oak))
    }
    if apron == 3 {
        parts.append(varietyBox(CV3(hx, 3.2, 1.4), CV3(0, topY - 4, hz - 2), metal))
    } else if apron == 1 || apron == 2 {
        parts.append(varietyBox(CV3(hx * 2 - 6, apron == 2 ? 2.4 : 3.2, 1.2), CV3(0, topY - 4, hz - 2), oak))
    } else if apron == 4 {
        for x in [-hx + 4, hx - 4] {
            parts.append(varietyBox(CV3(1.1, 1.1, 1.1), CV3(x, topY - 1, hz - 2.2), metal))
        }
    }
    parts.append(varietyBox(CV3(3.2, 2.4, 3.2), CV3(hx * 0.3, topY + 1.7, -hz * 0.2), .room(.ceramic(0xEFEAE2))))
    return varietyMerge(parts)
}

private func storage(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (body, front, legs, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width), hz = varietyHalf(piece.furniture.depth)
    let oak = varietyWood(body), metal = varietyMetal(front)
    var parts: [CamperMesh] = []
    let lift = legs == 4 ? 0.4 : 4.0
    switch legs {
    case 1:
        for (x, z) in [(-hx + 1.4, -hz + 1.4), (hx - 1.4, -hz + 1.4), (-hx + 1.4, hz - 1.4), (hx - 1.4, hz - 1.4)] {
            parts.append(varietyBox(CV3(1.2, lift, 1.2), CV3(x, 0, z), oak))
        }
    case 2:
        parts.append(varietyBox(CV3(hx * 2 - 2, 2.2, hz * 2 - 2), CV3(0, 0, 0), oak))
        parts.append(varietyBox(CV3(hx * 1.2, lift - 2, hz * 1.2), CV3(0, 2.2, 0), oak))
    case 3:
        for (x, z) in [(-hx + 1.6, -hz + 1.6), (hx - 1.6, hz - 1.6)] {
            parts.append(varietyBox(CV3(1.6, 1.2, 1.6), CV3(x, 0, z), metal))
            parts.append(varietyBox(CV3(2.2, 1.6, 1.1), CV3(x, 1.2, z), metal))
        }
    case 5:
        for (x, z) in [(-hx + 1.5, -hz + 1.5), (hx - 1.5, -hz + 1.5), (-hx + 1.5, hz - 1.5), (hx - 1.5, hz - 1.5)] {
            parts.append(varietyBox(CV3(2.2, lift, 2.2), CV3(x, 0, z), oak))
        }
    case 0:
        parts.append(varietyBox(CV3(hx * 2 - 1, 2.4, hz * 2 - 1), CV3(0, 0, 0), oak))
    default:
        break
    }
    let bodyH = 18 + Double(body) * 6
    if body == 5 {
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: min(hx, hz) - 1, height: bodyH, bevel: 0.4, segments: 8, oak),
                                       at: CV3(0, lift, 0)))
    } else if body == 1 {
        for k in 0..<3 {
            parts.append(varietyBox(CV3(hx * 2 - 2, bodyH / 3 - 1, hz * 2 - 2), CV3(0, lift + Double(k) * bodyH / 3, 0),
                                    k == 1 ? varietyWood(body + 1) : oak))
        }
    } else {
        parts.append(varietyBox(CV3(hx * 2 - 1.5, bodyH, hz * 2 - 1.5), CV3(0, lift, 0), oak))
    }
    let doorY = lift + 4
    let doorH = min(bodyH - 6, 28)
    switch front {
    case 1:
        parts.append(varietyBox(CV3(hx - 1, doorH, 0.8), CV3(-hx * 0.45, doorY, hz - 0.6), oak))
        parts.append(varietyBox(CV3(hx - 1, doorH, 0.8), CV3(hx * 0.45, doorY, hz - 0.6), oak))
    case 2:
        for k in 0..<3 {
            parts.append(varietyBox(CV3(hx * 2 - 3, doorH / 3 - 0.8, 0.9), CV3(0, doorY + Double(k) * doorH / 3, hz - 0.5), oak))
            parts.append(varietyBox(CV3(1.4, 0.6, 0.6), CV3(hx * 0.3, doorY + Double(k) * doorH / 3 + 1, hz), metal))
        }
    case 3:
        for y in [doorY, doorY + doorH * 0.45] {
            parts.append(varietyBox(CV3(hx * 2 - 4, 1.2, hz - 2), CV3(0, y, 0), oak))
        }
    case 4:
        parts.append(varietyBox(CV3(hx * 2 - 3, doorH, 0.5), CV3(0, doorY, hz - 0.4), .room(.glass)))
        parts.append(varietyBox(CV3(1.2, doorH, 1.2), CV3(-hx + 1.4, doorY, hz - 1), oak))
    case 5:
        for x in stride(from: -hx + 2, through: hx - 2, by: 1.6) {
            parts.append(varietyBox(CV3(0.35, doorH, 0.35), CV3(x, doorY, hz - 0.8), varietyWood(front)))
        }
    default:
        parts.append(varietyBox(CV3(hx * 2 - 3, doorH, 0.8), CV3(0, doorY, hz - 0.5), oak))
        parts.append(varietyBox(CV3(1.2, 0.7, 0.7), CV3(hx * 0.35, doorY + doorH * 0.5, hz), metal))
    }
    return varietyMerge(parts)
}

private func heater(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (body, flue, feet, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width)
    let iron = varietyMetal(body), fire = CamperMaterial.room(.fire)
    var parts: [CamperMesh] = []
    let foot = feet == 3 ? 1.2 : 3.0
    switch feet {
    case 0:
        for angle in [0.3, 2.4, 4.5] {
            parts.append(varietyBox(CV3(1.4, foot, 1.4), CV3(cos(angle) * (hx - 2), 0, sin(angle) * (hx - 2)), iron))
        }
    case 2:
        for x in [-hx + 2, hx - 2] {
            parts.append(varietyBox(CV3(2.2, foot, 1.6), CV3(x, 0, hx - 2), iron))
            parts.append(varietyBox(CV3(1.2, foot * 0.6, 1.2), CV3(x, foot, hx - 1.2), iron))
        }
    case 1:
        parts.append(varietyBox(CV3(hx * 2 - 2, foot, hx * 2 - 2), CV3(0, 0, 0), iron))
    default:
        parts.append(varietyBox(CV3(hx * 2 - 1, 1.4, hx * 2 - 1), CV3(0, 0, 0), .room(.ceramic(0xC4B49A))))
    }
    let bodyH = 16 + Double(body) * 4
    switch body {
    case 1, 2:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: hx - 1.2, height: bodyH, bevel: body == 1 ? 1.2 : 0.3, segments: 8, iron),
                                       at: CV3(0, foot, 0)))
    case 3:
        parts.append(varietyBox(CV3(hx * 2 - 1, bodyH, hx * 1.2), CV3(0, foot, -1), .room(.ceramic(0xE4D8C8))))
        parts.append(varietyBox(CV3(hx, bodyH * 0.45, 1.2), CV3(0, foot + 4, hx - 2), fire))
    case 4:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: hx - 1.4, height: bodyH * 0.7, bevel: 0.4, segments: 8, .room(.enamel(0xC23B2E))),
                                       at: CV3(0, foot, 0)))
        parts.append(varietyBox(CV3(hx * 1.4, bodyH * 0.25, 0.6), CV3(0, foot + 4, hx - 1.6), iron))
    default:
        parts.append(varietyBox(CV3(hx * 2 - 1.5, bodyH, hx * 2 - 2), CV3(0, foot, 0), iron))
        parts.append(varietyBox(CV3(hx, bodyH * 0.35, 0.5), CV3(0, foot + bodyH * 0.3, hx - 1.2), fire))
    }
    switch flue {
    case 0:
        parts.append(varietyBox(CV3(1.6, 18, 1.6), CV3(0, foot + bodyH, 0), iron))
    case 1:
        parts.append(varietyBox(CV3(1.5, 8, 1.5), CV3(0, foot + bodyH, 0), iron))
        parts.append(varietyBox(CV3(1.5, 1.5, 6), CV3(0, foot + bodyH + 8, 2), iron))
        parts.append(varietyBox(CV3(1.5, 8, 1.5), CV3(0, foot + bodyH + 8, 4.5), iron))
    case 3:
        parts.append(varietyBox(CV3(2.4, 16, 2.4), CV3(0, foot + bodyH, 0), iron))
        parts.append(varietyBox(CV3(1.2, 16, 1.2), CV3(0, foot + bodyH + 2, 0), .room(.mica)))
    default:
        break
    }
    return varietyMerge(parts)
}

private func rug(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (plan, edge, fringe, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width), hz = varietyHalf(piece.furniture.depth)
    let cloth = varietyCloth(plan), edgeM = varietyWood(edge)
    var parts: [CamperMesh] = []
    switch plan {
    case 1:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: min(hx, hz) - 0.4, height: 0.7, bevel: 0.15, segments: 8, cloth), at: CV3(0, 0, 0)))
    case 3:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: min(hx, hz) - 0.8, height: 0.8, bevel: 0.2, segments: 8, cloth), at: CV3(0, 0, 0)))
    case 4:
        parts.append(varietyBox(CV3(hx * 2 - 1, 0.6, hz * 2 - 1), CV3(0, 0, 0), cloth))
        parts.append(varietyBox(CV3(hx, 0.5, hz), CV3(-hx * 0.4, 0.6, -hz * 0.4), varietyCloth(plan + 1)))
        parts.append(varietyBox(CV3(hx, 0.5, hz), CV3(hx * 0.4, 0.6, hz * 0.4), varietyCloth(plan + 1)))
    case 5:
        for k in 0..<4 {
            parts.append(varietyBox(CV3(hx * 2 - 1, 0.45, 1.4), CV3(0, Double(k) * 0.15, -hz + 2 + Double(k) * hz * 0.4), k % 2 == 0 ? cloth : varietyCloth(plan + 2)))
        }
    case 6:
        parts.append(varietyBox(CV3(hx * 2 - 1, 0.55, hz * 2 - 1), CV3(0, 0, 0), cloth))
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: min(hx, hz) * 0.55, height: 0.4, bevel: 0.1, segments: 8, varietyCloth(plan + 1)), at: CV3(0, 0.55, 0)))
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: min(hx, hz) * 0.28, height: 0.35, bevel: 0.1, segments: 8, edgeM), at: CV3(0, 0.9, 0)))
    default:
        parts.append(varietyBox(CV3(hx * 2 - 1, 0.6, hz * 2 - 1), CV3(0, 0, 0), cloth))
    }
    if edge == 3 {
        parts.append(varietyBox(CV3(hx * 2, 0.5, 1.1), CV3(0, 0.2, -hz + 0.6), .room(.rushEdge)))
        parts.append(varietyBox(CV3(hx * 2, 0.5, 1.1), CV3(0, 0.2, hz - 0.6), .room(.rushEdge)))
    } else if edge == 2 || edge == 4 {
        parts.append(varietyBox(CV3(hx * 2, 0.45, 0.8), CV3(0, 0.3, hz - 0.5), edge == 2 ? varietyCloth(edge) : edgeM))
    } else if edge == 1 {
        parts.append(varietyBox(CV3(hx * 2, 0.4, 0.5), CV3(0, 0.5, -hz + 0.4), varietyMetal(edge)))
        parts.append(varietyBox(CV3(hx * 2, 0.4, 0.5), CV3(0, 0.5, hz - 0.4), varietyMetal(edge)))
    }
    if fringe > 0 {
        let count = fringe == 3 ? 3 : 5
        let len = fringe == 2 ? 1.6 : 0.9
        for k in 0..<count {
            let x = -hx + 2 + Double(k) * (hx * 2 - 4) / Double(max(1, count - 1))
            parts.append(varietyBox(CV3(0.4, 0.4, len), CV3(x, 0.2, hz - 0.2), varietyCloth(fringe)))
            if fringe != 3 {
                parts.append(varietyBox(CV3(0.4, 0.4, len), CV3(x, 0.2, -hz + 0.2), varietyCloth(fringe)))
            }
        }
    }
    return varietyMerge(parts)
}

private func floorLamp(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (stem, shade, foot, _) = piece.axes
    let oak = varietyWood(stem), metal = varietyMetal(foot), shadeM = CamperMaterial.room(.shade(0xF3E6C8))
    var parts: [CamperMesh] = []
    switch foot {
    case 1:
        parts.append(varietyBox(CV3(8, 1.4, 8), CV3(0, 0, 0), oak))
    case 2:
        for angle in [0.2, 2.3, 4.4] {
            parts.append(varietyBox(CV3(1.3, 2.2, 1.3), CV3(cos(angle) * 3.2, 0, sin(angle) * 3.2), metal))
        }
    case 3:
        parts.append(varietyBox(CV3(7, 2.2, 7), CV3(0, 0, 0), .room(.ceramic(0xB7B1A6))))
    case 4:
        parts.append(varietyBox(CV3(2, 1.2, 6), CV3(0, 0, 2), metal))
    default:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 3.6, height: 1.3, bevel: 0.25, segments: 8, metal), at: CV3(0, 0, 0)))
    }
    let stemH = 36 + Double(stem % 3) * 6
    switch stem {
    case 1:
        parts.append(varietyBox(CV3(1.3, stemH * 0.45, 1.3), CV3(0, 1.4, 0), metal))
        parts.append(varietyBox(CV3(2.2, 1.4, 2.2), CV3(0, 1.4 + stemH * 0.45, 0), metal))
        parts.append(varietyBox(CV3(1.1, stemH * 0.45, 1.1), CV3(0, 2.8 + stemH * 0.45, 0), metal))
    case 2:
        // 弧はマスの中に収める（笠の高い所だけ、隣の家具の上へ出てよい）
        parts.append(varietyBox(CV3(1.2, 1.2, 5), CV3(0, 2, 2.2), metal))
        parts.append(varietyBox(CV3(1.2, stemH * 0.55, 1.2), CV3(0, 2, 3), metal))
    case 3:
        for angle in [0.4, 2.5, 4.6] {
            parts.append(varietyBox(CV3(0.9, stemH, 0.9), CV3(cos(angle) * 2.2, 1.2, sin(angle) * 2.2), oak))
        }
    case 4:
        parts.append(varietyBox(CV3(0.8, stemH, 0.8), CV3(-1.1, 1.2, 0), metal))
        parts.append(varietyBox(CV3(0.8, stemH, 0.8), CV3(1.1, 1.2, 0), metal))
    case 5:
        parts.append(varietyBox(CV3(1.4, stemH, 1.4), CV3(0, 1.2, 0), oak))
        parts.append(varietyBox(CV3(3.2, 1, 1), CV3(0, stemH * 0.5, 0), metal))
    default:
        parts.append(varietyBox(CV3(1.2, stemH, 1.2), CV3(0, 1.3, 0), metal))
    }
    let shadeY = stem == 2 ? stemH * 0.45 : stemH
    let shadeZ: Double = stem == 2 ? 3 : 0
    switch shade {
    case 1:
        parts.append(varietyBox(CV3(7, 6, 7), CV3(0, shadeY, shadeZ), shadeM))
    case 2:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 3.2, height: 6, bevel: 0.8, segments: 8, shadeM), at: CV3(0, shadeY, 0)))
    case 3:
        parts.append(varietyBox(CV3(6.5, 5, 6.5), CV3(0, shadeY, 0), shadeM))
    case 4:
        parts.append(varietyBox(CV3(4, stemH * 0.35, 4), CV3(0, shadeY * 0.45, 0), .room(.paper)))
    case 5:
        parts.append(varietyBox(CV3(9, 1.2, 9), CV3(0, shadeY + 4, 0), clothSafe(shade)))
        parts.append(varietyBox(CV3(1, 4, 1), CV3(0, shadeY, 0), metal))
    default:
        parts.append(varietyBox(CV3(8, 5.5, 8), CV3(0, shadeY, shadeZ), shadeM))
        parts.append(varietyBox(CV3(3, 1, 3), CV3(0, shadeY + 5.5, 0), metal))
    }
    parts.append(varietyBox(CV3(1.2, 1.6, 1.2), CV3(0, shadeY + 1, 0), .room(.bulb)))
    return varietyMerge(parts)
}

private func clothSafe(_ i: Int) -> CamperMaterial { varietyCloth(i) }

private func shelf(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (board, bracket, load, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width)
    let oak = varietyWood(board), metal = varietyMetal(bracket)
    var parts: [CamperMesh] = []
    let yMax = 16.0
    switch board {
    case 1:
        parts.append(varietyBox(CV3(hx * 2 - 1, 1.1, 5), CV3(0, 4, 0.4), oak))
        parts.append(varietyBox(CV3(hx * 2 - 1, 1.1, 4.2), CV3(0, 10, 0.4), oak))
    case 2:
        for (x, z) in [(-hx + 3, 1.2), (hx - 3, 1.2), (0, 3.4)] {
            parts.append(varietyBox(CV3(4.2, 4.2, 3.2), CV3(x, 6, z), oak))
        }
    case 3:
        parts.append(varietyBox(CV3(hx * 2 - 1, 1.2, 5.5), CV3(0, 7, 0.3), oak))
        parts.append(varietyBox(CV3(1.2, 1.2, 5), CV3(-hx + 1.2, 7, 0.4), oak))
    case 4:
        parts.append(varietyBox(CV3(hx * 2 - 1, 1.4, 1.4), CV3(0, 8, 1), oak))
        parts.append(varietyBox(CV3(hx * 2 - 1, 1.4, 1.4), CV3(0, 12, 1.6), oak))
    case 5:
        parts.append(varietyBox(CV3(hx * 0.7, 1.2, 5), CV3(-hx * 0.4, 6, 0.4), oak))
        parts.append(varietyBox(CV3(hx * 0.9, 1.2, 4), CV3(hx * 0.3, 11, 0.5), oak))
    default:
        parts.append(varietyBox(CV3(hx * 2 - 1, 1.3, 5.2), CV3(0, 7, 0.4), oak))
    }
    switch bracket {
    case 1:
        parts.append(varietyBox(CV3(1.2, 6, 4), CV3(-hx + 2, 7, 0.5), oak))
        parts.append(varietyBox(CV3(1.2, 6, 4), CV3(hx - 2, 7, 0.5), oak))
    case 2:
        parts.append(varietyBox(CV3(0.4, 5, 0.4), CV3(-hx + 2, yMax - 5, 1), metal))
        parts.append(varietyBox(CV3(0.4, 5, 0.4), CV3(hx - 2, yMax - 5, 1), metal))
    case 3:
        parts.append(varietyBox(CV3(hx * 2 - 2, 1.4, 1.2), CV3(0, 8, 0.3), metal))
    case 4:
        parts.append(varietyBox(CV3(1.3, yMax - 2, 1.3), CV3(-hx + 1.2, 1, 0.6), oak))
        parts.append(varietyBox(CV3(1.3, yMax - 2, 1.3), CV3(hx - 1.2, 1, 0.6), oak))
    default:
        parts.append(varietyBox(CV3(1.4, 3.2, 4.2), CV3(-hx + 2.2, 5, 0.4), metal))
        parts.append(varietyBox(CV3(1.4, 3.2, 4.2), CV3(hx - 2.2, 5, 0.4), metal))
    }
    switch load {
    case 1:
        for x in [-hx + 4, 0, hx - 4] {
            parts.append(varietyBox(CV3(1.6, 5, 3.2), CV3(x, 8.4, 1.2), varietyCloth(load)))
        }
    case 2:
        for x in stride(from: -hx + 3, through: hx - 3, by: 2.2) {
            parts.append(varietyBox(CV3(1.1, 3.2, 1.1), CV3(x, 8.4, 1.4), .room(.glass)))
        }
    case 3:
        parts.append(varietyBox(CV3(3.2, 2.6, 3.2), CV3(0, 8.4, 1.5), .room(.terracotta)))
        parts.append(varietyBox(CV3(2, 2.4, 1.2), CV3(0, 11, 1.6), .room(.leaf)))
    case 4:
        parts.append(varietyBox(CV3(3, 2.2, 2.4), CV3(-hx * 0.3, 8.4, 1.3), varietyWood(load)))
    default:
        break
    }
    parts.append(varietyBox(CV3(0.8, 0.8, 0.8), CV3(hx - 2, 9, 2), metal))
    return varietyMerge(parts)
}

private func frame(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (opening, moulding, mat, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width)
    let wood = varietyWood(moulding), brass = varietyMetal(moulding)
    let tall = opening == 2 || opening == 4
    let fw = opening == 1 || opening == 5 ? hx * 1.3 : hx * 1.7
    let fh = tall ? 15.0 : 11.0
    var parts: [CamperMesh] = []
    let mould = moulding == 3 ? brass : wood
    parts.append(varietyBox(CV3(fw, fh, moulding == 4 ? 0.7 : 1.3), CV3(0, 2, 0.3), mould))
    if moulding == 1 {
        parts.append(varietyBox(CV3(fw - 1.2, fh - 1.2, 0.5), CV3(0, 2.4, 0.9), varietyWood(moulding + 1)))
    }
    if opening == 4 {
        parts.append(varietyBox(CV3(fw * 0.6, 3, 0.8), CV3(0, 2 + fh - 1.2, 0.5), mould))
    } else if opening == 5 {
        parts.append(varietyBox(CV3(0.5, fh - 3, 0.5), CV3(0, 3.2, 1.2), mould))
    } else if opening == 3 {
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: min(fw, fh) * 0.28, height: 0.4, bevel: 0.1, segments: 8, .room(.paper)),
                                       at: CV3(0, fh * 0.45, 1.3)))
    }
    let photo = CamperMaterial.room(.photo("slot0"))
    parts.append(varietyBox(CV3(fw - 3, fh - 4, 0.35), CV3(0, 3.2, 1.15), photo))
    if mat > 0 {
        parts.append(varietyBox(CV3(fw - (mat == 3 ? 2.2 : 3.4), fh - (mat == 1 ? 3 : 4.4), 0.3), CV3(0, 3, 1), .room(.mat)))
    }
    return varietyMerge(parts)
}

private func poster(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (sheet, hanger, border, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width)
    let paper = CamperMaterial.room(.paper), wood = varietyWood(hanger)
    var parts: [CamperMesh] = []
    let top: Double = 28
    switch sheet {
    case 1:
        for x in [-hx * 0.55, 0, hx * 0.55] {
            parts.append(varietyBox(CV3(hx * 0.42, 16, 0.3), CV3(x, 8, 0.4), paper))
        }
    case 2:
        for x in stride(from: -hx + 2, through: hx - 2, by: 2.3) {
            parts.append(varietyBox(CV3(1.8, 2.4, 0.25), CV3(x, 12, 0.4), varietyCloth(sheet)))
        }
    case 3:
        parts.append(varietyBox(CV3(hx * 2 - 1, 18, 0.3), CV3(0, 6, 0.4), .room(.linen(0xE7D7B8))))
        parts.append(varietyBox(CV3(1.2, 8, 0.2), CV3(0, 10, 0.7), varietyMetal(sheet)))
    case 4:
        parts.append(varietyBox(CV3(hx * 2 - 1, 20, 0.35), CV3(0, 6, 0.4), varietyCloth(sheet)))
        if border == 2 {
            parts.append(varietyBox(CV3(hx * 2, 1.4, 0.4), CV3(0, 5, 0.8), wood))
        }
    default:
        parts.append(varietyBox(CV3(hx * 2 - 1, 18, 0.3), CV3(0, 8, 0.4), paper))
    }
    switch hanger {
    case 1:
        parts.append(varietyBox(CV3(hx * 2, 0.8, 0.8), CV3(0, top, 0.6), wood))
    case 2:
        for x in [-hx + 2, hx - 2] {
            parts.append(varietyBox(CV3(0.7, 1.4, 0.7), CV3(x, top - 1, 0.5), varietyMetal(hanger)))
        }
    case 3:
        parts.append(varietyBox(CV3(0.35, 6, 0.35), CV3(-hx + 2, top - 6, 0.5), varietyMetal(hanger)))
        parts.append(varietyBox(CV3(0.35, 6, 0.35), CV3(hx - 2, top - 6, 0.5), varietyMetal(hanger)))
    case 4:
        for x in [-hx * 0.4, hx * 0.4] {
            parts.append(varietyBox(CV3(0.5, 0.5, 0.8), CV3(x, top - 1, 0.4), varietyMetal(hanger)))
        }
    default:
        parts.append(varietyBox(CV3(hx * 0.5, 0.5, 0.3), CV3(0, top - 0.4, 0.5), varietyMetal(hanger)))
    }
    if border == 0 || border == 3 {
        parts.append(varietyBox(CV3(hx * 2 - 2, 0.6, 0.25), CV3(0, 8, 0.8), varietyCloth(border + 1)))
    }
    return varietyMerge(parts)
}

private func wallLamp(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (arm, shade, plate, _) = piece.axes
    let metal = varietyMetal(arm), shadeM = CamperMaterial.room(.shade(0xF4E7CC))
    var parts: [CamperMesh] = []
    switch plate {
    case 1:
        parts.append(varietyBox(CV3(4.2, 5, 0.5), CV3(0, 6, 0.2), metal))
    case 2:
        parts.append(varietyBox(CV3(3.4, 8, 0.6), CV3(0, 5, 0.2), varietyWood(plate)))
    case 3:
        parts.append(varietyBox(CV3(1.2, 3.2, 1.4), CV3(0, 10, 0.2), metal))
    default:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 2.1, height: 0.5, bevel: 0.12, segments: 8, metal), at: CV3(0, 7, 0.2)))
    }
    let reach: Double
    switch arm {
    case 1: reach = 3
    case 2: reach = 6
    case 3:
        parts.append(varietyBox(CV3(0.7, 0.7, 3), CV3(-1.2, 8, 1.5), metal))
        parts.append(varietyBox(CV3(0.7, 0.7, 3), CV3(1.2, 8, 1.5), metal))
        reach = 4
    case 4:
        parts.append(varietyBox(CV3(0.7, 4, 0.7), CV3(0, 8, 1.2), metal))
        reach = 2
    case 5:
        parts.append(varietyBox(CV3(0.7, 4, 0.7), CV3(0, 4, 1.2), metal))
        reach = 2
    default:
        reach = 1.2
    }
    if arm == 0 || arm == 1 || arm == 2 {
        parts.append(varietyBox(CV3(0.7, 0.7, reach), CV3(0, 8, 0.6), metal))
    }
    switch shade {
    case 1:
        parts.append(varietyBox(CV3(3.2, 3.4, 3.2), CV3(0, arm == 5 ? 4 : 8, reach), shadeM))
    case 2:
        parts.append(varietyBox(CV3(1.3, 2.2, 1.3), CV3(0, 9, reach), .room(.bulb)))
    case 3:
        parts.append(varietyBox(CV3(0.6, 3.2, 0.6), CV3(0, 7, reach), varietyWood(shade)))
        parts.append(varietyBox(CV3(0.8, 0.8, 0.8), CV3(0, 10, reach), .room(.fire)))
    case 4:
        parts.append(varietyBox(CV3(3, 3.2, 3), CV3(0, 8, reach), varietyMetal(shade)))
        parts.append(varietyBox(CV3(1.2, 1.6, 1.2), CV3(0, 8.4, reach + 0.2), .room(.bulb)))
    default:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 1.8, height: 3.2, bevel: 0.4, segments: 8, .room(.milkGlass)),
                                       at: CV3(0, 7, reach)))
    }
    return varietyMerge(parts)
}

private func clock(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (casing, face, pendulum, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width)
    let wood = varietyWood(casing), metal = varietyMetal(face)
    var parts: [CamperMesh] = []
    let tall = pendulum != 0
    if casing == 3 {
        parts.append(varietyBox(CV3(hx * 1.6, 8, 2.2), CV3(0, tall ? 18 : 4, 0.3), wood))
        parts.append(varietyBox(CV3(hx * 1.8, 3, 2.4), CV3(0, tall ? 26 : 12, 0.3), wood))
    } else if casing == 4 {
        parts.append(varietyBox(CV3(hx * 1.5, 6, 2), CV3(0, 4, 0.3), wood))
        parts.append(varietyBox(CV3(hx * 1.7, 4, 1.4), CV3(0, 10, 0.5), metal))
    } else if casing == 0 || casing == 2 {
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: min(4.2, hx - 0.4), height: 1.4, bevel: 0.2, segments: 8, casing == 2 ? metal : wood),
                                       at: CV3(0, 6, 0.4)))
    } else {
        parts.append(varietyBox(CV3(hx * 1.7, 10, 2), CV3(0, 4, 0.3), wood))
    }
    let dial = CamperMaterial.room(.dial)
    parts.append(varietyBox(CV3(min(hx * 1.1, 5), 0.3, min(hx * 1.1, 5)), CV3(0, casing == 4 ? 11 : 7, 1.5), dial))
    switch face {
    case 1, 2:
        parts.append(varietyBox(CV3(0.3, 2.2, 0.2), CV3(0, 7.2, 1.8), metal))
    case 3:
        parts.append(varietyBox(CV3(1.6, 0.35, 0.2), CV3(0, 8.2, 1.8), metal))
    default:
        parts.append(varietyBox(CV3(0.25, 1.8, 0.2), CV3(0.4, 7.4, 1.8), metal))
        parts.append(varietyBox(CV3(1.4, 0.25, 0.2), CV3(0.2, 7.1, 1.8), metal))
    }
    if pendulum == 1 {
        parts.append(varietyBox(CV3(0.4, 10, 0.4), CV3(0, 2, 0.8), metal))
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 1.5, height: 0.4, bevel: 0.1, segments: 8, metal), at: CV3(0, 1.2, 1)))
    } else if pendulum == 2 {
        parts.append(varietyBox(CV3(1.2, 12, 0.5), CV3(0, 1, 0.8), wood))
    } else if pendulum == 3 {
        parts.append(varietyBox(CV3(0.4, 14, 0.4), CV3(-1.2, 1, 0.7), metal))
        parts.append(varietyBox(CV3(0.4, 11, 0.4), CV3(1.2, 1, 0.7), metal))
    } else if pendulum == 4 {
        for k in 0..<6 {
            let a = Double(k) / 6 * .pi
            parts.append(varietyBox(CV3(0.4, 2.4, 0.3), CV3(cos(a) * 3.2, 8 + sin(a) * 3, 1.2), metal))
        }
    }
    return varietyMerge(parts)
}

private func stringLights(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (wire, bulb, drop, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width)
    let metal = varietyMetal(wire)
    var parts: [CamperMesh] = []
    let drops = drop == 3 ? 3 : 1
    for row in 0..<drops {
        let y = -2 - Double(row) * 4 - (drop == 1 ? 2 : 0)
        let sag = drop == 2 && row == 0 ? 3.0 : (drop == 1 ? 2.0 : 0)
        parts.append(varietyBox(CV3(hx * 2 - 1, 0.35, 0.35), CV3(0, y - sag * 0.3, Double(row) * 0.8), metal))
        let count = wire == 2 ? 6 : 4
        for k in 0..<count {
            let x = -hx + 2 + Double(k) * ((hx * 2 - 4) / Double(max(1, count - 1)))
            let hang = y - (k == count / 2 ? sag : sag * 0.3) - Double(bulb == 1 ? 1.2 : 2.4)
            switch bulb {
            case 1:
                parts.append(varietyBox(CV3(0.7, 0.7, 0.7), CV3(x, hang, 0), .room(.bulb)))
            case 2:
                parts.append(varietyBox(CV3(1.4, 1.4, 1.4), CV3(x, hang, 0), varietyCloth(bulb)))
            case 3:
                parts.append(varietyBox(CV3(1.2, 1.2, 0.3), CV3(x, hang, 0), varietyMetal(bulb)))
            case 4:
                parts.append(varietyBox(CV3(1.6, 1.8, 0.2), CV3(x, hang, 0), varietyCloth(bulb + 1)))
            default:
                parts.append(varietyBox(CV3(1.3, 1.6, 1.3), CV3(x, hang, 0), .room(.bulb)))
            }
        }
    }
    if wire == 0 || wire == 3 {
        parts.append(varietyBox(CV3(0.4, 2, 0.4), CV3(-hx + 1, -2, 0), metal))
        parts.append(varietyBox(CV3(0.4, 2, 0.4), CV3(hx - 1, -2, 0), metal))
    } else if wire == 4 {
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 1.4, height: 0.4, bevel: 0.1, segments: 8, metal), at: CV3(0, -1, 0)))
    }
    return varietyMerge(parts)
}

private func mobile(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (arm, charm, hook, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width)
    let wood = varietyWood(arm), metal = varietyMetal(hook)
    var parts: [CamperMesh] = []
    parts.append(varietyBox(CV3(0.5, 3, 0.5), CV3(0, -3, 0), metal))
    let barY = hook == 1 ? -8.0 : -4.0
    switch arm {
    case 1:
        parts.append(varietyBox(CV3(hx * 1.6, 0.6, 0.6), CV3(0, barY, 0), wood))
        parts.append(varietyBox(CV3(0.6, 0.6, hx), CV3(0, barY, 0), wood))
    case 2:
        parts.append(varietyBox(CV3(hx * 1.7, 0.7, 0.7), CV3(0, barY, 1.2), wood))
    case 3:
        parts.append(varietyBox(CV3(0.7, 0.7, hx), CV3(-hx * 0.2, barY, 0), wood))
        parts.append(varietyBox(CV3(hx, 0.6, 0.6), CV3(hx * 0.3, barY - 1, 0.4), wood))
    case 4:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: hx * 0.7, height: 0.4, bevel: 0.1, segments: 8, wood), at: CV3(0, barY, 0)))
    default:
        parts.append(varietyBox(CV3(hx * 1.8, 0.7, 0.7), CV3(0, barY, 0), wood))
    }
    let charms = charm == 4 ? 4 : 3
    for k in 0..<charms {
        let x = -hx + 1.5 + Double(k) * ((hx * 2 - 3) / Double(max(1, charms - 1)))
        let drop = 6 + Double((k + hook) % 3) * 3
        parts.append(varietyBox(CV3(0.25, drop, 0.25), CV3(x, barY - drop, 0), metal))
        let y = barY - drop - 1.2
        switch charm {
        case 1:
            parts.append(varietyBox(CV3(1.6, 0.4, 1.6), CV3(x, y, 0), varietyCloth(charm)))
            parts.append(varietyBox(CV3(0.4, 1.4, 0.8), CV3(x, y - 0.6, 0), varietyCloth(charm)))
        case 2:
            parts.append(varietyBox(CV3(1.4, 1.4, 0.3), CV3(x, y, 0), varietyMetal(charm)))
        case 3:
            parts.append(varietyBox(CV3(1.2, 2.2, 0.3), CV3(x, y, 0), .room(.leaf)))
        case 4:
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: 0.8, height: 0.5, bevel: 0.15, segments: 8, .room(.glass)), at: CV3(x, y, 0)))
        default:
            parts.append(varietyBox(CV3(1.8, 1.1, 0.4), CV3(x, y, 0), varietyWood(charm)))
            parts.append(varietyBox(CV3(0.8, 0.7, 0.5), CV3(x + 0.8, y + 0.4, 0), varietyWood(charm)))
        }
    }
    if hook == 2 {
        parts.append(varietyBox(CV3(hx * 1.2, 0.5, 0.5), CV3(0, barY - 6, 0), wood))
    }
    return varietyMerge(parts)
}

private func plant(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (cord, pot, leaf, _) = piece.axes
    let metal = varietyMetal(cord), potM = pot == 0 ? CamperMaterial.room(.terracotta) : varietyWood(pot)
    var parts: [CamperMesh] = []
    let hang = 10 + Double(cord) * 3
    // 紐は天井（y = 0）から下へ。箱の底が `at` なので、長さの分だけ負の位置から置く
    switch cord {
    case 1:
        parts.append(varietyBox(CV3(0.5, hang, 0.5), CV3(0, -hang, 0), metal))
    case 2:
        parts.append(varietyBox(CV3(0.4, hang, 0.35), CV3(0, -hang, 0), .room(.leather(0x6B3E2A))))
    case 3:
        for x in [-0.8, 0, 0.8] {
            parts.append(varietyBox(CV3(0.3, hang, 0.3), CV3(x, -hang, 0), varietyCloth(cord)))
        }
    case 4:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 1.6, height: 0.4, bevel: 0.1, segments: 8, metal), at: CV3(0, -0.4, 0)))
        parts.append(varietyBox(CV3(0.4, hang - 2, 0.4), CV3(0, -(hang - 2), 0), metal))
    default:
        parts.append(varietyBox(CV3(0.35, hang * 0.4, 0.35), CV3(-0.7, -hang * 0.4, 0), varietyCloth(cord)))
        parts.append(varietyBox(CV3(0.35, hang * 0.7, 0.35), CV3(0.7, -hang * 0.7, 0), varietyCloth(cord)))
        parts.append(varietyBox(CV3(2.2, 0.4, 0.4), CV3(0, -hang * 0.45, 0), varietyCloth(cord)))
    }
    let potY = -hang - 2
    switch pot {
    case 1:
        parts.append(varietyBox(CV3(4.2, 3.2, 4.2), CV3(0, potY, 0), .room(.wicker)))
    case 2:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 2.2, height: 3.4, bevel: 0.5, segments: 8, .room(.glass)), at: CV3(0, potY, 0)))
    case 3:
        parts.append(varietyBox(CV3(3.6, 3.4, 3.6), CV3(0, potY, 0), .room(.enamel(0xD7E2DC))))
    case 4:
        parts.append(varietyBox(CV3(4, 3, 4), CV3(0, potY, 0), potM))
    case 5:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 2.4, height: 2.2, bevel: 0.3, segments: 8, potM), at: CV3(0, potY, 0)))
    default:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 2.3, height: 3.2, bevel: 0.35, segments: 8, .room(.terracotta)), at: CV3(0, potY, 0)))
    }
    parts.append(varietyBox(CV3(3, 1, 3), CV3(0, potY + 3, 0), .room(.soil)))
    switch leaf {
    case 1:
        parts.append(varietyBox(CV3(1.2, 6, 1.2), CV3(0, potY + 3.4, 0), .room(.leaf)))
    case 2:
        parts.append(varietyBox(CV3(3.4, 1.2, 3.4), CV3(0, potY + 4, 0), .room(.leaf)))
    default:
        parts.append(varietyBox(CV3(0.6, 5, 0.6), CV3(-1.2, potY + 2, 0.4), .room(.leaf)))
        parts.append(varietyBox(CV3(0.6, 4, 0.6), CV3(1.1, potY + 1, -0.3), .room(.leaf)))
    }
    return varietyMerge(parts)
}

private func hatch(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (rim, pane, lever, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width)
    let wood = varietyWood(rim), metal = varietyMetal(lever)
    var parts: [CamperMesh] = []
    switch rim {
    case 1:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: hx - 0.4, height: 1.6, bevel: 0.25, segments: 8, wood), at: CV3(0, -1.6, 0)))
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: hx * 0.62, height: 0.5, bevel: 0.1, segments: 8, .room(.glass)), at: CV3(0, -0.8, 0)))
    case 2:
        parts.append(varietyBox(CV3(hx * 1.5, 1.8, hx * 1.5), CV3(0, -1.8, 0), wood))
        parts.append(varietyBox(CV3(hx, 0.4, hx), CV3(0, -0.6, 0), .room(.glass)))
    case 3:
        parts.append(varietyBox(CV3(hx * 2 - 1, 2.4, hx * 2 - 1), CV3(0, -2.4, 0), wood))
    case 4:
        parts.append(varietyBox(CV3(hx * 2 - 1, 1.2, hx * 2 - 1), CV3(0, -1.2, 0), wood))
        parts.append(varietyBox(CV3(hx * 1.4, 1, hx * 1.4), CV3(0, -2.2, 0), varietyWood(rim + 1)))
    default:
        parts.append(varietyBox(CV3(hx * 2 - 1, 1.5, hx * 2 - 1), CV3(0, -1.5, 0), wood))
    }
    if pane == 1 {
        parts.append(varietyBox(CV3(hx, 0.3, 0.35), CV3(0, -0.4, 0), metal))
        parts.append(varietyBox(CV3(0.35, 0.3, hx), CV3(0, -0.4, 0), metal))
    } else if pane == 2 {
        parts.append(varietyBox(CV3(hx * 0.7, 0.35, hx * 0.7), CV3(0, -0.3, 0), varietyMetal(pane)))
    } else if pane == 3 {
        parts.append(varietyBox(CV3(hx * 0.8, 0.35, hx * 0.5), CV3(-hx * 0.2, -0.3, 0), varietyCloth(pane)))
        parts.append(varietyBox(CV3(hx * 0.5, 0.35, hx * 0.8), CV3(hx * 0.2, -0.3, 0), varietyCloth(pane + 1)))
    }
    switch lever {
    case 0:
        parts.append(varietyBox(CV3(1.2, 1.6, 1.2), CV3(hx * 0.45, -2.2, 0), metal))
    case 1:
        parts.append(varietyBox(CV3(0.4, 4, 0.4), CV3(0, -5, 0), metal))
    case 2:
        parts.append(varietyBox(CV3(0.5, 3.5, 0.5), CV3(hx * 0.3, -4, 0), wood))
    default:
        break
    }
    return varietyMerge(parts)
}
