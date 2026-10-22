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

    /// 脚と組み立てを 1 つずつ作り直した分類（2026-10-22。床の留めを足さない）
    static let craftedLegs: Set<CamperRoomCategory> = [.seating, .table, .bed, .storage, .heater, .floorLamp]

    static let pieces: [Piece] = makePieces()
    static var furniture: [CamperRoomFurniture] { pieces.map(\.furniture) }

    private static let byId: [String: Piece] = Dictionary(uniqueKeysWithValues: pieces.map { ($0.furniture.id, $0) })
    private static let gate = NSLock()
    /// 作った網の控え（2026-10-22 確かめ役「memo を捨てないので図鑑を最後まで見ると 1〜2GB 近く」）。
    /// 実測（試験 `CamperVarietyMeshSizeTests`）: 組み合わせ 2,076 点の三角形は main で 197 万（全部控えると約 400MB）、
    /// 脚を作り直した後で 428 万（約 870MB）。家具の小さな絵の控え（`CamperThumbCache`）と同じ、使った順の古い物から
    /// 捨てる上限つきの控えにする。上限 48MB は寝台（いちばん重い 1 万 600 枚・約 2MB）でも 20 点ほど残る大きさ
    static let memoCostLimit = 48 * 1024 * 1024
    /// 三角形 1 枚の記憶（点 3 つ × 位置・向き 24 バイトずつ・貼り絵 16 バイト ＋ 番号 3 つ × 4 バイト）
    static let bytesPerTriangle = 3 * (24 + 24 + 16) + 3 * 4
    private static var memo = CamperThumbCache<CamperMesh>(costLimit: memoCostLimit)

    static func mesh(_ id: String) -> CamperMesh? {
        gate.lock()
        if let hit = memo.value(id) { gate.unlock(); return hit }
        gate.unlock()
        guard let piece = byId[id] else { return nil }
        let built = build(piece)
        gate.lock()
        memo.insert(built, key: id, cost: built.triangleCount * bytesPerTriangle)
        gate.unlock()
        return built
    }

    /// 控えている網の記憶（バイト）
    static var memoCost: Int {
        gate.lock()
        defer { gate.unlock() }
        return memo.totalCost
    }

    /// 控えを全部捨てる（部屋を閉じたとき・メモリの警告。家具の小さな絵の控えと一緒に）
    static func removeAllMeshes() {
        gate.lock()
        memo.removeAll()
        gate.unlock()
    }

    static func lamp(_ id: String) -> (position: CV3, intensity: Double, range: Double)? {
        guard let piece = byId[id], piece.furniture.lit else { return nil }
        // 2026-10-22（確かめ役）: 前は床の物を高さの 0.72 に固定していて、作り直した電球・火の窓とずれた。形と同じ式で
        switch piece.furniture.category {
        case .floorLamp: return (varietyLampHead(stem: piece.axes.0, foot: piece.axes.2) + varietyBulbAboveHead, 0.4, 70)
        case .heater: return (varietyHeaterFire(body: piece.axes.0, feet: piece.axes.2, hx: varietyHalf(piece.furniture.width)), 0.4, 60)
        default: break
        }
        switch piece.furniture.placement {
        case .floor: return (CV3(0, max(8, piece.furniture.height * 0.72), 0), 0.4, 70)
        case .wall: return (CV3(0, 8, 3.5), 0.35, 60)
        case .ceiling: return (CV3(0, -6, 0), 0.35, 65)
        }
    }

    static func build(_ piece: Piece) -> CamperMesh {
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
        // 軸ごとに位置の違う真鍮の留め。同じ大枠でも輪郭がずれ、色を変えただけでは同じ形にならない。
        // 2026-10-22 判断: 脚を作り直した分類（椅子・机・寝台・棚・暖炉・床の灯り）は軸ごとに輪郭が違うので留めを足さない（床の真ん中に釘が転がって見えた）
        if CamperRoomVariety.craftedLegs.contains(piece.furniture.category) { return varietyFit(raw, piece.furniture) }
        return varietyFit(varietyMerge([raw, varietyMark(piece)]), piece.furniture)
    }
}

// MARK: - 図鑑の行

private func makePieces() -> [CamperRoomVariety.Piece] {
    var out: [CamperRoomVariety.Piece] = []
    // 板の名前とぶつからないようにする（`CamperRoomCatalog.all` の一意さ）
    var usedJa = Set(CamperRoomCatalog.board.map(\.nameJa))
    var usedEn = Set(CamperRoomCatalog.board.map(\.nameEn))
    /// 同じ「先頭の軸＋分類」の通し番号（2 件目から数字を足して短く一意にする）
    var serial: [String: Int] = [:]

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
            // 棚の升に入る短い名前。軸の全部は look に残す（2026-10-21 owner「名前が長い」）
            let head = combo.first ?? suffix
            let baseJa = "\(head.ja)の\(suffix.ja)"
            let baseEn = "\(suffix.en), \(head.en)"
            let n = (serial[baseJa] ?? 0) + 1
            serial[baseJa] = n
            var nameJa = n == 1 ? baseJa : "\(baseJa)\(n)"
            var nameEn = n == 1 ? baseEn : "\(baseEn) \(n)"
            // 板や他分類とぶつかったら番号を進める
            while usedJa.contains(nameJa) || usedEn.contains(nameEn) {
                let m = (serial[baseJa] ?? n) + 1
                serial[baseJa] = m
                nameJa = "\(baseJa)\(m)"
                nameEn = "\(baseEn) \(m)"
            }
            usedJa.insert(nameJa)
            usedEn.insert(nameEn)
            let furniture = CamperRoomFurniture(
                category: category, key: key,
                nameJa: nameJa, nameEn: nameEn,
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
    // 分類名は短い「灯り」。床／壁の違いは図鑑の段と look で分かる
    emit(.floorLamp, [lampStems, lampShades, lampFeet], 160, { _ in (2, 2, 84, true, 0) }, VarietyWord(ja: "灯り", en: "Lamp"))
    emit(.wallShelf, [shelfBoards, shelfBrackets, shelfLoads], 140, { _ in (3, 1, 8, false, 0) }, VarietyWord(ja: "棚", en: "Shelf"))
    emit(.photoFrame, [frameOpenings, frameMouldings, frameMats], 120, { _ in (2, 1, 4, false, 1) }, VarietyWord(ja: "額", en: "Frame"))
    emit(.poster, [posterSheets, posterHangers, posterBorders], 100, { _ in (2, 2, 6, false, 0) }, VarietyWord(ja: "絵", en: "Poster"))
    emit(.wallLamp, [sconceArms, sconceShades, sconcePlates], 120, { _ in (1, 1, 8, true, 0) }, VarietyWord(ja: "灯り", en: "Sconce"))
    emit(.clock, [clockCases, clockFaces, clockPendulums], 100, { combo in
        let tall = combo[2].ja != "振り子なし"
        return (tall ? 1 : 2, tall ? 2 : 1, 6, false, 0)
    }, VarietyWord(ja: "時計", en: "Clock"))
    emit(.stringCeiling, [stringWires, stringBulbs, stringDrops], 100, { _ in (4, 1, 22, true, 0) }, VarietyWord(ja: "紐", en: "String"))
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

// 2026-10-22 判断（owner の実機「家具によって足が壊れてたりする」）: 寝台を枠の形ごとに作り直した。前は高い柱・天蓋柱の
// 寝台で布団が柱の間の宙に浮き（床板も框も無い）、そり桟・パレットは布団が 7 浮き、入れ子の枠は床から浮いていた。
// いまは 1.9 × 0.9 m・床板の上面 9〜11（22〜28 cm）で、四隅の柱（頭は高く・足は低く・頭に飾りの玉）が床に立ち、
// 框（横の板）が柱の間に入って床板の簀の子を受け、敷き布団はその上に載る。そり桟・パレットは柱がその上に立つ
private func bed(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (frame, head, foot, cover) = piece.axes
    let hx = varietyHalf(piece.furniture.width), hz = varietyHalf(piece.furniture.depth)
    // 掛け布団の色は頭と足の形でも変える（寝具の軸は数の上限で使われず、全部同じ色になっていた）
    let oak = varietyWood(frame), dark = varietyWood(frame + 3), linen = varietyCloth(cover + head + foot * 2), brass = varietyMetal(foot)
    var parts: [CamperMesh] = []
    let L = hx * 2 - 1, W = hz * 2 - 1
    let px = L / 2 - 1.3, pz = W / 2 - 1.3
    // 床板の上面と、柱の立つ高さ（そり桟・パレットは床ではなくその上）
    let deck: Double
    var base = 0.0
    switch frame {
    case 1, 2, 5, 7: deck = 11
    case 4: deck = 9.2
    default: deck = 9
    }
    let railTop = deck + 1.5, railLow = deck - 4.5
    let headTop = head == 4 ? deck + 13 : (frame == 1 ? 40.0 : 33.0)
    let footTop = foot == 2 ? deck + 13 : (foot == 1 ? deck + 7 : railTop)
    let postTop = frame == 5 ? 62.0 : 0
    // 框（柱の間の横の板と端の板）・框の内の受け木・簀の子
    func rails(inset: Double = 0) {
        for z in [-W / 2 + 1.2 + inset, W / 2 - 1.2 - inset] {
            parts.append(VarietyKit.block(CV3(L - 5.2 - inset * 2, railTop - railLow, 2.4), at: CV3(0, railLow, z), radius: 0.5, segments: 1, oak))
            parts.append(varietyBox(CV3(L - 6 - inset * 2, 0.8, 0.8), CV3(0, deck - 1.6, z + (z < 0 ? 1.6 : -1.6)), dark))
        }
        for x in [-L / 2 + 1.2 + inset, L / 2 - 1.2 - inset] {
            parts.append(VarietyKit.block(CV3(2.4, railTop - railLow, W - 5.2 - inset * 2), at: CV3(x, railLow, 0), radius: 0.5, segments: 1, oak))
        }
        let n = 11
        let span = L - 6 - inset * 2
        for k in 0..<n {
            let x = -span / 2 + span * (Double(k) + 0.5) / Double(n)
            parts.append(varietyBox(CV3(span / Double(n) - 1.4, 0.8, W - 4.8 - inset * 2), CV3(x, deck - 0.8, 0), varietyWood(frame + 2)))
        }
    }
    // 柱（四隅。頭の玉）
    func post(_ x: Double, _ z: Double, from y0: Double, to y1: Double, size: Double = 2.8) {
        parts.append(VarietyKit.block(CV3(size, y1 - y0, size), at: CV3(x, y0, z), radius: 0.45, segments: 1, oak))
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(size * 0.42, 0), CV2(size * 0.5, 0.5), CV2(size * 0.32, 1.0),
                                                         CV2(size * 0.42, 1.6), CV2(0, 2.1)], segments: 14, dark), at: CV3(x, y1, z)))
    }
    switch frame {
    case 1:
        // 高い柱（頭の柱 40・足の柱も框より高く）・框・真ん中の脚
        rails()
        for z in [-W / 2 + 1.2, W / 2 - 1.2] { parts.append(varietyBox(CV3(2.4, railLow, 2.4), CV3(0, 0, z), oak)) }
    case 2:
        // そり桟（床の桟は両端で丸く巻き上がる・桟の上に柱と中の束）
        base = 2.2
        rails()
        for z in [-pz, pz] {
            parts.append(VarietyKit.block(CV3(L - 5.6, 2.2, 2.6), at: CV3(0, 0, z), radius: 0.7, segments: 1, oak))
            for s in [-1.0, 1.0] {
                let c = CV3(s * (L / 2 - 2.8), 1.9, z)
                let curl = (0...10).map { k -> CV3 in
                    let a = -Double.pi / 2 + Double(k) / 10 * Double.pi * 1.25
                    return c + CV3(s * cos(a) * 1.8, sin(a) * 1.8, 0)
                }
                parts.append(VarietyKit.tube(curl, radius: 1.0, sides: 10, oak))
            }
            parts.append(varietyBox(CV3(2.4, railLow - base, 2.4), CV3(0, base, z), oak))
        }
    case 3:
        // 舟形（引っ込めた台輪の上に、角を大きく丸めた胴。胴の上が床板）
        parts.append(varietyBox(CV3(L - 6, 1.2, W - 6), .zero, dark))
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(L - 2.6, deck - 1.2, W - 2.6), radius: 2.4, segments: 2, sidePuff: 0.4, oak),
                                       at: CV3(0, 1.2 + (deck - 1.2) / 2, 0)))
        parts.append(VarietyKit.tube(VarietyKit.roundedRect(L - 2.2, W - 2.2, r: 2.6).map { CV3($0.x, deck - 2.5, $0.y) }, radius: 0.3,
                                     sides: 6, closed: true, brass))
    case 4:
        // パレット（2 枚重ね。下の板・ブロック 9・上の板 7）
        base = deck
        for level in 0..<2 {
            let y0 = Double(level) * 4.6
            for z in [-W / 2 + 2, 0, W / 2 - 2] { parts.append(varietyBox(CV3(L - 1, 0.8, 3.6), CV3(0, y0, z), oak)) }
            for x in [-L / 2 + 2.5, 0, L / 2 - 2.5] {
                for z in [-W / 2 + 2, 0, W / 2 - 2] { parts.append(varietyBox(CV3(3.4, 3.0, 3.4), CV3(x, y0 + 0.8, z), dark)) }
            }
            for k in 0..<9 {
                let x = -L / 2 + 2 + (L - 4) * Double(k) / 8
                parts.append(varietyBox(CV3(3.8, 0.8, W - 1), CV3(x, y0 + 3.8, 0), oak))
            }
        }
    case 5:
        // 天蓋柱（四隅の柱 62・上の枠・麻の天蓋）
        rails()
        for z in [-W / 2 + 1.2, W / 2 - 1.2] { parts.append(varietyBox(CV3(2.4, railLow, 2.4), CV3(0, 0, z), oak)) }
        for z in [-pz, pz] { parts.append(varietyBox(CV3(L - 5.2, 1.6, 1.8), CV3(0, postTop - 1.6, z), oak)) }
        for x in [-px, px] { parts.append(varietyBox(CV3(1.8, 1.6, W - 5.2), CV3(x, postTop - 1.6, 0), oak)) }
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(L - 2.6, 0.5, W - 2.6), radius: 0.2, segments: 1, puff: 0.6, linen),
                                       at: CV3(0, postTop + 0.25, 0)))
        for z in [-pz, pz] {
            parts.append(VarietyKit.placed(VarietyKit.drape(width: L - 6, height: 6, folds: 7, depth: 0.5, flare: 0.08, linen),
                                           at: CV3(0, postTop, z + (z < 0 ? -1 : 1)), yaw: z < 0 ? .pi : 0))
        }
    case 6:
        // 入れ子の枠（短い脚 6 の上に外の框、その内に一段高い内の框）
        // 脚は外の框の下に収める（2026-10-22 確かめ役の見張り: 前は框の外へ 1.75 cm 出ていた）
        for x in [-px + 0.7, 0, px - 0.7] { for z in [-pz + 0.7, pz - 0.7] { parts.append(varietyBox(CV3(2.6, 3, 2.6), CV3(x, 0, z), dark)) } }
        for z in [-pz, pz] { parts.append(VarietyKit.block(CV3(L - 1.4, 2.6, 2.6), at: CV3(0, 3, z), radius: 0.5, segments: 1, oak)) }
        for x in [-px, px] { parts.append(VarietyKit.block(CV3(2.6, 2.6, W - 5.2), at: CV3(x, 3, 0), radius: 0.5, segments: 1, oak)) }
        parts.append(VarietyKit.block(CV3(L - 6, deck - 5.6, W - 6), at: CV3(0, 5.6, 0), radius: 0.6, segments: 1, varietyWood(frame + 1)))
    case 7:
        // 船長の框（台輪の上に引き出し 3 の箱・真鍮のつまみ）
        parts.append(varietyBox(CV3(L - 2.6, 0.8, W - 2.6), .zero, dark))
        parts.append(VarietyKit.block(CV3(L - 1.4, deck - 0.8, W - 1.4), at: CV3(0, 0.8, 0), radius: 0.5, segments: 1, oak))
        for k in 0..<3 {
            let x = -L / 3 + Double(k) * L / 3
            let at = CV3(x, 2, W / 2 - 0.5)
            parts.append(VarietyKit.block(CV3(L / 3 - 2, deck - 4, 0.6), at: at, radius: 0.2, segments: 1, varietyWood(frame + 1)))
            parts.append(VarietyKit.placed(VarietyKit.sphere(radius: 0.55, segments: 10, brass), at: at + CV3(0, (deck - 4) / 2, 0.7)))
        }
    default:
        // 低い台（框・真ん中の脚）
        rails()
        for z in [-W / 2 + 1.2, W / 2 - 1.2] { parts.append(varietyBox(CV3(2.4, railLow, 2.4), CV3(0, 0, z), oak)) }
    }
    // 頭の柱と頭板（柱は床か、そり桟・パレットの上に立つ）
    let headX = -px
    let tallPosts = frame == 5
    for z in [-pz, pz] { post(headX, z, from: base, to: tallPosts ? postTop : headTop) }
    let span = W - 5.2
    let panelLow = max(railTop - 1, base + 4)
    switch head {
    case 1:
        // 縦桟（上下の笠木の間に 7 本）
        parts.append(varietyBox(CV3(2.2, 2.2, span), CV3(headX, headTop - 3.4, 0), oak))
        parts.append(varietyBox(CV3(2.2, 2, span), CV3(headX, panelLow, 0), oak))
        for k in 1...7 {
            let z = -span / 2 + span * Double(k) / 8
            parts.append(VarietyKit.block(CV3(1.2, headTop - 3.4 - panelLow - 2, 1.2), at: CV3(headX, panelLow + 2, z), radius: 0.25, segments: 1, oak))
        }
    case 2:
        // アーチ（上の縁が弓なりの板）
        parts.append(VarietyKit.placed(varietyArchedApron(span, height: headTop - 6 - panelLow, rise: 0, crown: 4, thick: 1.8, oak),
                                       at: CV3(headX, panelLow, 0), yaw: .pi / 2))
    case 3:
        // 翼（板と、前へ開く両脇の袖）
        parts.append(VarietyKit.block(CV3(1.8, headTop - 1 - panelLow, span), at: CV3(headX, panelLow, 0), radius: 0.4, segments: 1, oak))
        for s in [-1.0, 1.0] {
            parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(6, 12, 1.4), radius: 0.5, segments: 1, linen),
                                           at: CV3(headX + 3.2, headTop - 8, s * (pz - 0.4)), yaw: s * 0.35))
        }
    case 5:
        // 格子の頭（枠の中に縦 2・横 3 の格子）
        parts.append(varietyBox(CV3(2, 2, span), CV3(headX, headTop - 3, 0), oak))
        parts.append(varietyBox(CV3(2, 2, span), CV3(headX, panelLow, 0), oak))
        for z in [-span / 6, span / 6] { parts.append(varietyBox(CV3(1.2, headTop - 3 - panelLow - 2, 1.2), CV3(headX, panelLow + 2, z), oak)) }
        for k in 1...3 {
            let y = panelLow + 2 + (headTop - 5 - panelLow) * Double(k) / 4
            parts.append(varietyBox(CV3(1.2, 1.2, span), CV3(headX, y - 0.6, 0), oak))
        }
    default:
        // 平らな頭板・低い枕元（一枚板・上の縁に笠木）
        parts.append(VarietyKit.block(CV3(1.8, headTop - 1.2 - panelLow, span), at: CV3(headX, panelLow, 0), radius: 0.4, segments: 1, oak))
        parts.append(VarietyKit.block(CV3(2.6, 1.2, span + 1), at: CV3(headX, headTop - 1.2, 0), radius: 0.5, segments: 1, dark))
    }
    // 足の柱と足板
    let footX = px
    for z in [-pz, pz] { post(footX, z, from: base, to: tallPosts ? postTop : footTop) }
    switch foot {
    case 1:
        // 巻き足（板の上に丸く巻いた笠木）
        parts.append(VarietyKit.block(CV3(1.6, footTop - 1.4 - panelLow, span), at: CV3(footX, panelLow, 0), radius: 0.4, segments: 1, oak))
        parts.append(VarietyKit.tube([CV3(footX + 0.3, footTop - 1.2, -span / 2 - 0.6), CV3(footX + 0.3, footTop - 1.2, span / 2 + 0.6)],
                                     radius: 1.3, sides: 14, dark))
    case 2:
        // 高い足板
        parts.append(VarietyKit.block(CV3(1.8, footTop - panelLow, span), at: CV3(footX, panelLow, 0), radius: 0.4, segments: 1, oak))
    case 3:
        // 箱足（足元の物入れの箱・真鍮の留め）
        let bx = footX - 4.4
        parts.append(VarietyKit.block(CV3(6.2, railTop + 3 - base, span), at: CV3(bx, base, 0), radius: 0.5, segments: 1, varietyWood(frame + 1)))
        parts.append(VarietyKit.block(CV3(1.6, 1.2, 0.5), at: CV3(bx - 3.2, railTop, 0), radius: 0.15, segments: 1, brass))
    default:
        break
    }
    // 敷き布団（縁の縫い目）と寝具
    let mx = L - (foot == 3 ? 14 : 6), mxc = foot == 3 ? -4.0 : 0
    let mw = W - 5, top = deck + 6
    parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(mx, 6, mw), radius: 1.8, segments: 2, puff: 0.4, .room(.cotton(0xE8E1D2))),
                                   at: CV3(mxc, deck + 3, 0)))
    parts.append(VarietyKit.tube(VarietyKit.roundedRect(mx + 0.3, mw + 0.3, r: 2.2).map { CV3($0.x + mxc, deck + 4.8, $0.y) }, radius: 0.3,
                                 sides: 6, closed: true, .room(.cotton(0xCFC6B4))))
    let pillow = CamperMaterial.room(.linen(0xF1EDE4))
    func pillows(_ zs: [Double]) {
        for (k, z) in zs.enumerated() {
            parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(10, 3.4, 14), radius: 1.6, segments: 2, puff: 1.1, sidePuff: 0.4, pillow),
                                           at: CV3(-L / 2 + 9, top + 1.7, z), yaw: k == 0 ? 0.05 : -0.07))
        }
    }
    switch cover {
    case 1:
        // 三つ折り（足の側に畳んだ掛け布団 3 層）
        for k in 0..<3 {
            parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(16 - Double(k), 2.4, mw - 0.6 - Double(k) * 0.6), radius: 1.1, segments: 2,
                                                                 puff: 0.4, linen), at: CV3(mxc + mx / 2 - 10, top + 1.2 + Double(k) * 2.2, 0)))
        }
        pillows([0])
    case 2:
        // 枕二つと掛け布団
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(mx * 0.62, 2.6, mw + 2), radius: 1.2, segments: 2, puff: 0.8, sidePuff: 0.5, linen),
                                       at: CV3(mxc + mx * 0.17, top + 1.3, 0)))
        pillows([-mw / 4, mw / 4])
    case 3:
        // 足元の毛布（編み物を畳んで横へ垂らす）
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(11, 1.6, mw + 3), radius: 0.7, segments: 1, puff: 0.3, sidePuff: 0.3,
                                                             .room(.knit(0xB5653F))), at: CV3(mxc + mx / 2 - 8, top + 0.8, 0)))
        parts.append(VarietyKit.placed(VarietyKit.drape(width: 11, height: 4, folds: 2, depth: 0.4, flare: 0.1, .room(.knit(0xB5653F))),
                                       at: CV3(mxc + mx / 2 - 8, top + 1.4, mw / 2 + 1.5)))
        pillows([0])
    case 4:
        // 片方だけ（掛け布団を半分めくる）
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(mx * 0.6, 2.4, mw / 2 + 1.5), radius: 1.1, segments: 2, puff: 0.7, linen),
                                       at: CV3(mxc + mx * 0.18, top + 1.2, mw / 4 + 0.5)))
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(mx * 0.6, 1.4, 4), radius: 0.6, segments: 1, puff: 0.3, linen),
                                       at: CV3(mxc + mx * 0.18, top + 3.1, -0.5)))
        pillows([-mw / 4, mw / 4])
    default:
        // 折り返し（掛け布団と頭の側の白い折り返し）
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(mx * 0.62, 2.8, mw + 2.4), radius: 1.3, segments: 2, puff: 0.8, sidePuff: 0.6, linen),
                                       at: CV3(mxc + mx * 0.17, top + 1.4, 0)))
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(4.4, 3.2, mw + 2.5), radius: 1.5, segments: 2, puff: 0.4, .room(.linen(0xEDE8DE))),
                                       at: CV3(mxc - mx * 0.15, top + 1.6, 0)))
        pillows([0])
    }
    return varietyMerge(parts)
}

// 2026-10-22 判断（owner の実機「椅子とかは家具によって足が壊れてたりする。一個ずつ丁寧に作らないとダメかもね」）:
// 脚の形ごとに作り直した。前は座面の高さ 20 cm の箱を並べたもので、丸座の外の角に脚が浮く・そり脚の脚が桟の無い
// 真ん中に立つ・一本脚に台座が無い、が出ていた。いまは実物の椅子の寸法（座面 42 cm・脚 3.5 cm 角・座の縁から 3.5 cm 内）で、
// 脚の上端は座の下面（すのこ座は受け桟の下面）に必ず届き、脚の芯は座の内に入る。試験 `CamperFurnitureLegsTests` が見張る。
private func seating(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (base, top, back, arms) = piece.axes
    let hx = varietyHalf(piece.furniture.width), hz = varietyHalf(piece.furniture.depth)
    let wood = varietyWood(base), cloth = varietyCloth(top), metal = varietyMetal(base + 2)
    let round = top == 1, slats = top == 5
    var parts: [CamperMesh] = []
    // 座の大きさ（縁は置くマスより 0.4 内）と高さ（座面 17 = 42 cm）
    let w = hx * 2 - 0.8, d = hz * 2 - 0.8, rim = min(w, d) / 2
    let seatT = top == 2 ? 1.7 : (top == 3 ? 1.4 : 1.2)
    let seatTop = 17.0
    // すのこ座は板の下に受け桟（座の両端と真ん中）を通し、脚はその下面で受ける
    let batten = slats ? 1.2 : 0
    let under = seatTop - seatT - batten
    // 脚の芯（角の座は縁から 1.4 内、丸座は円の内に入るよう斜めに寄せる）
    let lx: Double, lz: Double
    if round {
        lx = (rim - 1.6) / 2.squareRoot(); lz = lx
    } else {
        lx = w / 2 - 1.4; lz = d / 2 - 1.4
    }
    let corners = [(-lx, -lz), (lx, -lz), (-lx, lz), (lx, lz)]
    // 幕板（座の下で脚どうしをつなぐ板）。丸座は輪
    func aprons(_ height: Double, thick: Double) {
        if round {
            let r = lx * 2.squareRoot()
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(r - thick / 2, 0), CV2(r + thick / 2, 0), CV2(r + thick / 2, height),
                                                             CV2(r - thick / 2, height), CV2(r - thick / 2, 0)], segments: 24, wood,
                                                            capStart: false, capEnd: false),
                                           at: CV3(0, under - height, 0)))
            return
        }
        for z in [-lz, lz] { parts.append(varietyBox(CV3(lx * 2, height, thick), CV3(0, under - height, z), wood)) }
        for x in [-lx, lx] { parts.append(varietyBox(CV3(thick, height, lz * 2), CV3(x, under - height, 0), wood)) }
    }
    // 脚先のフェルト（床を傷めない黒い当て）
    func glide(_ x: Double, _ z: Double) {
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 0.72, height: 0.2, bevel: 0.08, segments: 8, .room(.leather(0x2A2522))),
                                       at: CV3(x, 0, z)))
    }
    switch base {
    case 1:
        // 先細り脚（挽いた丸脚・足先 1.2 cm 細る・真鍮の沓）と、高さを違えた丸い貫（前後は低く、横は高く）
        for (x, z) in corners {
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.5, 0), CV2(0.58, 0.35), CV2(0.82, under - 2.5),
                                                             CV2(0.86, under), CV2(0, under)], segments: 12, wood), at: CV3(x, 0, z)))
            // 脚先の真鍮の沓（くつ）
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.56, 0), CV2(0.64, 0.12), CV2(0.66, 1.0), CV2(0, 1.0)],
                                                             segments: 12, metal), at: CV3(x, 0, z)))
        }
        aprons(2.2, thick: 0.8)
        for z in [-lz, lz] { parts.append(VarietyKit.tube([CV3(-lx, 4.6, z), CV3(lx, 4.6, z)], radius: 0.32, sides: 8, wood)) }
        for x in [-lx, lx] { parts.append(VarietyKit.tube([CV3(x, 6.4, -lz), CV3(x, 6.4, lz)], radius: 0.32, sides: 8, wood)) }
    case 2:
        // そり脚（鉄の丸棒を曲げた横枠 2。床の桟から立ち上がって座の下を通る）と前後の渡し
        let r = 0.5
        for x in [-lx, lx] {
            let loop = VarietyKit.roundedRect(lz * 2 + 1.6, under - r * 2, r: 1.6, steps: 4)
                .map { CV3(x, under / 2 + $0.y, $0.x) }
            parts.append(VarietyKit.tube(loop, radius: r, sides: 8, closed: true, metal))
        }
        for z in [-lz, lz] { parts.append(VarietyKit.tube([CV3(-lx, under - r, z), CV3(lx, under - r, z)], radius: 0.42, sides: 8, metal)) }
    case 3:
        // 一本脚（床の丸い台座・挽いた柱・座の下の受け板）。長椅子は 2 本
        let posts: [Double] = slats ? [-lx * 0.62, lx * 0.62] : [0]
        let foot = min(rim - 1.2, 6.2)
        for x in posts {
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: foot, height: 0.9, bevel: 0.35, segments: 28, metal), at: CV3(x, 0, 0)))
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(1.9, 0), CV2(1.25, 1.4), CV2(1.0, under - 3), CV2(1.3, under - 1.6),
                                                             CV2(0, under - 1.6)], segments: 18, metal), at: CV3(x, 0.9, 0)))
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: min(rim - 2, 4.4), height: 0.7, bevel: 0.2, segments: 20, metal),
                                           at: CV3(x, under - 0.7, 0)))
        }
    case 4:
        // 交差脚（左右の X の枠は相欠きで同じ面に組む・真ん中の軸・床の前後の桟・座の下の前後の渡し）
        for x in [-lx, lx] {
            parts.append(VarietyKit.tube([CV3(x, 0.6, -lz), CV3(x, under - 0.6, lz)], radius: 0.6, sides: 8, wood))
            parts.append(VarietyKit.tube([CV3(x, 0.6, lz), CV3(x, under - 0.6, -lz)], radius: 0.6, sides: 8, wood))
        }
        parts.append(VarietyKit.tube([CV3(-lx - 0.5, under / 2, 0), CV3(lx + 0.5, under / 2, 0)], radius: 0.35, sides: 8, metal))
        for z in [-lz, lz] {
            parts.append(VarietyKit.tube([CV3(-lx, 0.5, z), CV3(lx, 0.5, z)], radius: 0.5, sides: 8, wood))
            parts.append(VarietyKit.tube([CV3(-lx, under - 0.55, z), CV3(lx, under - 0.55, z)], radius: 0.55, sides: 8, wood))
        }
    case 5:
        // ヘアピン脚（鉄の丸棒を V に曲げた脚 4・座の下の取付け板）
        for (x, z) in corners {
            let s = z < 0 ? -1.0 : 1.0
            let path = [CV3(x, under - 0.35, z - s * 1.4), CV3(x, 3, z - s * 0.5), CV3(x, 0.6, z - s * 0.15), CV3(x, 0.34, z),
                        CV3(x, 0.6, z + s * 0.15), CV3(x, 3, z + s * 0.5), CV3(x, under - 0.35, z + s * 1.4)]
            parts.append(VarietyKit.tube(path, radius: 0.34, sides: 8, metal))
            parts.append(varietyBox(CV3(2.4, 0.35, 3.8), CV3(x, under - 0.35, z), metal))
        }
    case 6:
        // 三本脚（外へ開く丸脚・輪の貫）
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi + .pi / 2
            let dir = CV3(cos(a), 0, sin(a))
            parts.append(VarietyKit.tube([dir * (rim * 0.5) + CV3(0, under - 0.1, 0), dir * (rim * 0.78) + CV3(0, 0.7, 0)],
                                         radius: 0.7, sides: 10, wood))
            glide(dir.x * rim * 0.78, dir.z * rim * 0.78)
        }
        parts.append(VarietyKit.tube(VarietyKit.ringXZ(center: CV3(0, 6, 0), radius: rim * 0.68, steps: 24), radius: 0.3, sides: 6,
                                     closed: true, wood))
    case 7:
        // 揺り脚（弓なりの揺り板 2 に脚 4）
        let curve = 1.6 / (hz * hz)
        for x in [-lx, lx] {
            let path = stride(from: -hz - 1.5, through: hz + 1.5, by: 1).map { z in CV3(x, 0.6 + curve * z * z, z) }
            parts.append(VarietyKit.tube(path, radius: 0.6, sides: 8, wood))
        }
        for (x, z) in corners {
            let foot = 0.6 + curve * z * z + 0.3
            parts.append(varietyBox(CV3(1.4, under - foot, 1.4), CV3(x, foot, z), wood))
        }
        aprons(2.4, thick: 0.9)
    default:
        // まっすぐ脚（3.5 cm 角・角を落とす・脚先にフェルト）・幕板・H の貫
        for (x, z) in corners {
            parts.append(VarietyKit.block(CV3(1.5, under - 0.2, 1.5), at: CV3(x, 0.2, z), radius: 0.3, segments: 1, wood))
            glide(x, z)
        }
        aprons(2.6, thick: 0.9)
        for x in [-lx, lx] { parts.append(varietyBox(CV3(0.9, 1.1, lz * 2), CV3(x, 4.6, 0), wood)) }
        parts.append(varietyBox(CV3(lx * 2, 1.1, 0.9), CV3(0, 5.2, 0), wood))
    }
    // 座
    let seatY = seatTop - seatT
    switch top {
    case 1:
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: rim, height: seatT, bevel: 0.45, segments: 24, wood), at: CV3(0, seatY, 0)))
    case 2:
        // 鞍座（厚い一枚板の縁を大きく落とす）
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(w, seatT, d), radius: 0.8, segments: 2, puff: 0.25, wood),
                                       at: CV3(0, seatY + seatT / 2, 0)))
    case 3:
        // 編み座（木の框に い草を編む）
        for z in [-d / 2 + 0.6, d / 2 - 0.6] { parts.append(varietyBox(CV3(w, seatT, 1.2), CV3(0, seatY, z), wood)) }
        for x in [-w / 2 + 0.6, w / 2 - 0.6] { parts.append(varietyBox(CV3(1.2, seatT, d - 2.4), CV3(x, seatY, 0), wood)) }
        parts.append(varietyBox(CV3(w - 2.2, seatT * 0.8, d - 2.2), CV3(0, seatY + 0.15, 0), .room(.rush)))
    case 4:
        // 厚い座（板の上にふくらんだ座布団）
        parts.append(varietyBox(CV3(w, seatT, d), CV3(0, seatY, 0), wood))
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(w - 0.6, 2.8, d - 0.6), radius: 1.1, segments: 2, puff: 0.7, sidePuff: 0.3,
                                                             cloth), at: CV3(0, seatTop + 1.4, 0)))
    case 5:
        // すのこ座（前後に 5 枚の板・板の間は 1.2 cm・下に受け桟）
        let n = 5, gap = 0.5
        let slat = (d - gap * Double(n - 1)) / Double(n)
        for k in 0..<n {
            let z = -d / 2 + slat / 2 + Double(k) * (slat + gap)
            parts.append(varietyBox(CV3(w, seatT, slat), CV3(0, seatY, z), wood))
        }
        // 受け桟は両端と、脚の上（一本脚の長椅子は柱の上・ほかは真ん中）
        let rails = base == 3 ? [-lx, -lx * 0.62, lx * 0.62, lx] : [-lx, 0, lx]
        for x in rails { parts.append(varietyBox(CV3(1.4, batten, d - 0.6), CV3(x, under, 0), wood)) }
    default:
        parts.append(varietyBox(CV3(w, seatT, d), CV3(0, seatY, 0), wood))
    }
    // 背（後ろの柱は座の上に立つ）
    let backTop = seatTop + 15
    let postZ = round ? -lz : -d / 2 + 1.0
    let postX = lx
    func posts(_ height: Double) {
        for x in [-postX, postX] {
            parts.append(VarietyKit.block(CV3(1.3, height, 1.3), at: CV3(x, seatTop, postZ), radius: 0.3, segments: 1, wood))
        }
    }
    let span = postX * 2
    switch back {
    case 1:
        posts(backTop - seatTop)
        parts.append(VarietyKit.block(CV3(span + 1.3, 3.2, 0.9), at: CV3(0, backTop - 3.2, postZ), radius: 0.35, segments: 1, wood))
    case 2:
        posts(backTop - seatTop)
        for k in 0..<3 {
            parts.append(VarietyKit.block(CV3(span, 1.7, 0.7), at: CV3(0, backTop - 2 - Double(k) * 4, postZ), radius: 0.25, segments: 1, wood))
        }
    case 3:
        posts(backTop - seatTop)
        parts.append(VarietyKit.block(CV3(span, 9, 0.8), at: CV3(0, backTop - 9.5, postZ), radius: 0.3, segments: 1, wood))
        parts.append(varietyBox(CV3(span, 1.2, 0.8), CV3(0, seatTop + 2, postZ), wood))
    case 4:
        // 翼背（布張りの背と両脇の耳）
        let bz = round ? postZ : -d / 2 + 1.4
        let bw = round ? span + 2 : w - 0.4
        parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(bw, backTop - seatTop, 2.6), radius: 1, segments: 2, sidePuff: 0.4, cloth),
                                       at: CV3(0, (seatTop + backTop) / 2, bz)))
        for s in [-1.0, 1.0] {
            parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(1.8, 8, 5), radius: 0.8, segments: 2, sidePuff: 0.3, cloth),
                                           at: CV3(s * (bw / 2 - 0.7), backTop - 4.5, bz + 3.2)))
        }
    case 5:
        // スピンドル（上下の笠木と細い丸棒 5）
        posts(backTop - seatTop)
        parts.append(VarietyKit.block(CV3(span + 1.3, 2.4, 1.0), at: CV3(0, backTop - 2.4, postZ), radius: 0.4, segments: 1, wood))
        parts.append(varietyBox(CV3(span, 1.2, 0.9), CV3(0, seatTop + 2, postZ), wood))
        for k in 1...5 {
            let x = -postX + span * Double(k) / 6
            parts.append(VarietyKit.tube([CV3(x, seatTop + 3, postZ), CV3(x, backTop - 2.4, postZ)], radius: 0.3, sides: 8, wood))
        }
    case 6:
        // 楕円背（楕円の枠に布の張り地・柱は枠の脇まで）
        let ry = 5.5, cy = backTop - ry - 0.5
        posts(cy - seatTop)
        let ring = (0..<32).map { k -> CV3 in
            let a = Double(k) / 32 * 2 * .pi
            return CV3(cos(a) * (postX + 0.1), cy + sin(a) * ry, postZ)
        }
        parts.append(VarietyKit.tube(ring, radius: 0.5, sides: 8, closed: true, wood))
        let pad = VarietyKit.scaled(VarietyKit.disc(radius: 1, height: 0.8, bevel: 0.3, segments: 28, cloth), CV3(postX - 0.3, 1, ry - 0.3))
        parts.append(VarietyKit.placed(pad, at: CV3(0, cy, postZ - 0.4), rotation: CQuat.axisAngle(CV3(1, 0, 0), .pi / 2)))
    default:
        break
    }
    // 肘（前の柱と肘木）
    if arms > 0 {
        let armY = seatTop + (arms == 2 ? 7 : 5.5)
        for x in [-postX, postX] {
            parts.append(VarietyKit.block(CV3(1.1, armY - seatTop, 1.1), at: CV3(x, seatTop, d / 2 - 1.6), radius: 0.3, segments: 1, wood))
            parts.append(VarietyKit.block(CV3(1.6, 1.0, d - 1.6), at: CV3(x, armY, 0.2), radius: 0.4, segments: 1, arms == 2 ? metal : wood))
            if back == 0 || back == 4 {
                parts.append(VarietyKit.block(CV3(1.1, armY - seatTop, 1.1), at: CV3(x, seatTop, postZ), radius: 0.3, segments: 1, wood))
            }
        }
    }
    return varietyMerge(parts)
}

// 2026-10-22 判断（owner の実機「家具によって足が壊れてたりする」）: 机を脚の形ごとに作り直した。前は脚の上が天板の下に
// 2（5 cm）届かず全部の机が宙に浮き、引き出し台は高さ 10 の箱の上 16 に天板が浮き、一本脚には台座が無かった。
// いまは天板の上面 28（70 cm）・天板の厚み 4〜5 cm・脚 5 cm 角で、脚・柱・板脚の上端は天板の組の下面（`under`）に届き、
// 脚の芯は天板の固定の部分の内に入る。幕板は脚の間（脚の無い台は内側の枠）に入れる
private func table(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (top, base, apron, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width), hz = varietyHalf(piece.furniture.depth)
    let wood = varietyWood(top), legWood = varietyWood(top + base), metal = varietyMetal(base)
    var parts: [CamperMesh] = []
    let round = top == 1
    let w = hx * 2 - 1, d = hz * 2 - 1, rim = min(w, d) / 2
    let topTop = 28.0
    // 天板の組。`under` は脚の届く下面、`fw`・`fd` は脚を入れてよい固定の部分の大きさ
    var under = topTop - 1.8
    var fw = w, fd = d
    switch top {
    case 1:
        under = topTop - 1.6
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: rim, height: 1.6, bevel: 0.5, segments: 28, wood), at: CV3(0, under, 0)))
        fw = rim * 2; fd = rim * 2
    case 2:
        // ドロップリーフ（真ん中の固定の板・右の板は持ち上げて引き出しの腕で受け、左の板は蝶番で下に垂れる）
        under = topTop - 1.6
        let cw = w * 0.56, leaf = (w - cw) / 2 - 0.15
        parts.append(varietyBox(CV3(cw, 1.6, d), CV3(0, under, 0), wood))
        parts.append(varietyBox(CV3(leaf, 1.6, d), CV3(cw / 2 + 0.15 + leaf / 2, under, 0), wood))
        parts.append(varietyBox(CV3(1.4, leaf, d), CV3(-cw / 2 - 0.15 - 0.7, topTop - 0.2 - leaf, 0), wood))
        for z in [-d / 4, d / 4] {
            parts.append(varietyBox(CV3(leaf + 2, 1.2, 1.4), CV3(cw / 2 + leaf / 2 - 1, under - 1.2, z), legWood))
        }
        fw = cw
    case 3:
        // 寄木（下の板に 2 色の木の小板を市松に）
        under = topTop - 1.45
        parts.append(varietyBox(CV3(w, 1.3, d), CV3(0, under, 0), wood))
        let cols = 6, rows = 4
        let tw = (w - 1.2) / Double(cols), td = (d - 1.2) / Double(rows)
        for i in 0..<cols {
            for j in 0..<rows {
                let x = -w / 2 + 0.6 + tw * (Double(i) + 0.5), z = -d / 2 + 0.6 + td * (Double(j) + 0.5)
                parts.append(varietyBox(CV3(tw - 0.08, 0.15, td - 0.08), CV3(x, under + 1.3, z),
                                        (i + j) % 2 == 0 ? varietyWood(top + 2) : varietyWood(top + 4)))
            }
        }
    case 4:
        // 石の天板（厚い石を木の枠に載せる）
        under = topTop - 2.6
        parts.append(VarietyKit.block(CV3(w, 1.8, d), at: CV3(0, under + 0.8, 0), radius: 0.35, segments: 1, .room(.ceramic(0xD9D3C7))))
        parts.append(varietyBox(CV3(w - 2, 0.8, d - 2), CV3(0, under, 0), wood))
    case 5:
        // ガラス天板（幅の広い木の枠の溝に板硝子）
        under = topTop - 1.9
        let rail = 3.6
        for z in [-d / 2 + rail / 2, d / 2 - rail / 2] { parts.append(varietyBox(CV3(w, 1.4, rail), CV3(0, under, z), wood)) }
        for x in [-w / 2 + rail / 2, w / 2 - rail / 2] { parts.append(varietyBox(CV3(rail, 1.4, d - rail * 2), CV3(x, under, 0), wood)) }
        parts.append(varietyBox(CV3(w - 1.2, 0.5, d - 1.2), CV3(0, under + 1.4, 0), .room(.clearGlass)))
    default:
        parts.append(VarietyKit.block(CV3(w, 1.8, d), at: CV3(0, under, 0), radius: 0.45, segments: 1, wood))
    }
    // 脚の芯（4 本は固定の部分の縁から 2.2 内。丸い天板は斜めに寄せて円の内へ）
    let lx: Double, lz: Double
    if round {
        lx = (rim - 2.6) / 2.squareRoot(); lz = lx
    } else {
        lx = fw / 2 - 2.2; lz = fd / 2 - 2.2
    }
    func drawer(_ at: CV3, width: Double, height: Double) {
        parts.append(VarietyKit.block(CV3(width, height, 0.5), at: at, radius: 0.15, segments: 1, varietyWood(top + base + 1)))
        parts.append(VarietyKit.placed(VarietyKit.sphere(radius: 0.45, segments: 10, metal), at: at + CV3(0, height / 2, 0.6)))
    }
    func peg(_ at: CV3) {
        let s = at.z < 0 ? -1.0 : 1.0
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.35, 0), CV2(0.35, 0.35), CV2(0, 0.4)], segments: 8, varietyWood(top + 3)),
                                       at: at, rotation: CQuat.axisAngle(CV3(1, 0, 0), s * .pi / 2)))
    }
    // 幕板（脚の間・脚の無い台は内側の枠）
    func apronFrame(_ ax: Double, _ az: Double, ring: Double?) {
        guard apron > 0 else { return }
        let h = apron == 3 ? 4.2 : 3.0, t = 1.0
        if let r = ring {
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(r - t / 2, 0), CV2(r + t / 2, 0), CV2(r + t / 2, h), CV2(r - t / 2, h),
                                                             CV2(r - t / 2, 0)], segments: 28, legWood, capStart: false, capEnd: false),
                                           at: CV3(0, under - h, 0)))
            if apron == 3 { drawer(CV3(0, under - h + 0.6, r + t / 2), width: r * 0.8, height: h - 1.2) }
            if apron == 4 { for a in [0.25, 0.75, 1.25, 1.75] { peg(CV3(cos(a * .pi) * (r + t / 2), under - h / 2, sin(a * .pi) * (r + t / 2))) } }
            return
        }
        for z in [-az, az] {
            if apron == 2 {
                parts.append(VarietyKit.placed(varietyArchedApron(ax * 2, height: h, rise: 1.6, thick: t, legWood), at: CV3(0, under - h, z)))
            } else {
                parts.append(varietyBox(CV3(ax * 2, h, t), CV3(0, under - h, z), legWood))
            }
        }
        for x in [-ax, ax] { parts.append(varietyBox(CV3(t, h, az * 2), CV3(x, under - h, 0), legWood)) }
        if apron == 3 { drawer(CV3(0, under - h + 0.6, az + t / 2), width: ax * 0.9, height: h - 1.2) }
        if apron == 4 {
            for x in [-ax + 1.6, ax - 1.6] { for z in [-az - t / 2, az + t / 2] { peg(CV3(x, under - h / 2, z)) } }
        }
    }
    switch base {
    case 1:
        // 中央の柱（十字の脚・挽いた柱・天板の下の十字の受け木）
        let foot = min(fw, fd) * 0.42
        for yaw in [0.0, .pi / 2] {
            parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(foot * 2, 2.2, 2.6), radius: 0.7, segments: 1, legWood),
                                           at: CV3(0, 1.1, 0), yaw: yaw + .pi / 4))
            parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(min(fw, fd) * 0.62, 0.9, 2.2), radius: 0.3, segments: 1, legWood),
                                           at: CV3(0, under - 0.45, 0), yaw: yaw))
        }
        let h = under - 0.9 - 2.2
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(2.7, 0), CV2(2.2, 1.0), CV2(1.6, 3.2), CV2(1.35, h * 0.55),
                                                         CV2(1.7, h - 2.4), CV2(2.2, h - 0.6), CV2(2.2, h), CV2(0, h)], segments: 20, legWood),
                                       at: CV3(0, 2.2, 0)))
        apronFrame(lx, lz, ring: round ? lx * 2.squareRoot() : nil)
    case 2:
        // 二枚の板脚（床の足木・板の脚・天板の下の受け木・通し貫と楔）
        let px = round ? rim * 0.55 : fw / 2 - 3.5
        let zh = round ? (rim * rim - px * px).squareRoot() - 1.5 : fd / 2 - 1.5
        for x in [-px, px] {
            parts.append(VarietyKit.block(CV3(2.6, 2.2, zh * 2), at: CV3(x, 0, 0), radius: 0.6, segments: 1, legWood))
            parts.append(VarietyKit.block(CV3(1.8, under - 1.6 - 2.2, zh), at: CV3(x, 2.2, 0), radius: 0.3, segments: 1, legWood))
            parts.append(VarietyKit.block(CV3(2.4, 1.6, zh * 2 - 1), at: CV3(x, under - 1.6, 0), radius: 0.4, segments: 1, legWood))
            parts.append(varietyBox(CV3(0.7, 2.8, 0.9), CV3(x + (x < 0 ? -1.7 : 1.7), 8.6, 0), varietyWood(top + 3)))
        }
        parts.append(VarietyKit.block(CV3(px * 2 + 3.4, 2.0, 1.6), at: CV3(0, 9, 0), radius: 0.3, segments: 1, legWood))
        apronFrame(px - 1.2, zh - 0.8, ring: nil)
    case 3:
        // X 脚（床の足木の上に鉄の丸管を相欠きで X に・天板の下の受け・真ん中の貫）
        let px = round ? rim * 0.55 : fw / 2 - 3.5
        let zh = round ? (rim * rim - px * px).squareRoot() - 1.8 : fd / 2 - 1.8
        for x in [-px, px] {
            parts.append(VarietyKit.block(CV3(1.8, 1.0, zh * 2 + 1.6), at: CV3(x, 0, 0), radius: 0.3, segments: 1, metal))
            parts.append(VarietyKit.tube([CV3(x, 1.0, -zh), CV3(x, under - 1.4, zh)], radius: 0.75, sides: 10, metal))
            parts.append(VarietyKit.tube([CV3(x, 1.0, zh), CV3(x, under - 1.4, -zh)], radius: 0.75, sides: 10, metal))
            parts.append(VarietyKit.block(CV3(1.8, 1.4, zh * 2 + 1.6), at: CV3(x, under - 1.4, 0), radius: 0.3, segments: 1, metal))
        }
        parts.append(VarietyKit.tube([CV3(-px, (under - 0.65) / 2, 0), CV3(px, (under - 0.65) / 2, 0)], radius: 0.55, sides: 10, metal))
        apronFrame(px - 1.2, zh, ring: nil)
    case 4:
        // 引き出し台（台輪の上の箱・前に引き出し 3 段・真鍮のつまみ）
        let bw = round ? rim * 1.3 : fw - 3, bd = round ? rim * 1.3 : fd - 3
        parts.append(varietyBox(CV3(bw - 1.4, 1.2, bd - 1.4), .zero, legWood))
        parts.append(VarietyKit.block(CV3(bw, under - 1.2, bd), at: CV3(0, 1.2, 0), radius: 0.4, segments: 1, legWood))
        let rowsN = apron == 3 ? 4 : 3
        let rowH = (under - 1.2 - 1.6) / Double(rowsN)
        for k in 0..<rowsN { drawer(CV3(0, 2.0 + Double(k) * rowH, bd / 2), width: bw - 2, height: rowH - 0.5) }
        if apron == 1 || apron == 2 {
            parts.append(varietyBox(CV3(bw + 0.6, 0.6, bd + 0.6), CV3(0, apron == 1 ? 1.2 : under - 0.6, 0), varietyWood(top + 3)))
        } else if apron == 4 {
            for x in [-bw / 2 + 1, bw / 2 - 1] { peg(CV3(x, under - 1.5, bd / 2)) }
        }
    case 5:
        // 三本脚（挽いた丸脚・輪の幕板）
        let rho = round ? rim - 2.6 : min(fw, fd) / 2 - 2.4
        for k in 0..<3 {
            let a = .pi / 2 + Double(k) * 2 * .pi / 3
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.75, 0), CV2(0.85, 0.5), CV2(1.15, under - 4), CV2(1.2, under),
                                                             CV2(0, under)], segments: 14, legWood), at: CV3(cos(a) * rho, 0, sin(a) * rho)))
        }
        if apron > 0 {
            apronFrame(rho, rho, ring: rho)
        } else {
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: rho + 1.4, height: 0.9, bevel: 0.25, segments: 24, legWood), at: CV3(0, under - 0.9, 0)))
        }
    default:
        // 四本脚（5 cm 角・角を落とす）
        for (x, z) in [(-lx, -lz), (lx, -lz), (-lx, lz), (lx, lz)] {
            parts.append(VarietyKit.block(CV3(2.0, under, 2.0), at: CV3(x, 0, z), radius: 0.35, segments: 1, legWood))
        }
        apronFrame(lx, lz, ring: round ? lx * 2.squareRoot() : nil)
    }
    // 天板の上のマグ
    parts.append(CamperRoomShapes.mug(at: CV3(w * 0.16, topTop, -d * 0.18), body: .room(.ceramic(0xEFEAE2)), rim: .room(.ceramic(0xB09A78)), yaw: 0.8))
    return varietyMerge(parts)
}

/// 弓形の板（長さ `length` は x・厚み `thick` は z・下の端が y = 0）。下の縁が真ん中で `rise` 上がる（幕板）か、
/// 上の縁が真ん中で `crown` 上がる（寝台の頭板）
private func varietyArchedApron(_ length: Double, height: Double, rise: Double, crown: Double = 0, thick: Double,
                                _ m: CamperMaterial) -> CamperMesh {
    var mesh = CamperMesh()
    let n = 16
    func bow(_ x: Double) -> Double {
        let u = 2 * x / length
        return max(0, 1 - u * u)
    }
    for k in 0..<n {
        let x0 = -length / 2 + length * Double(k) / Double(n), x1 = -length / 2 + length * Double(k + 1) / Double(n)
        let b0 = rise * bow(x0), b1 = rise * bow(x1)
        let t0 = height + crown * bow(x0), t1 = height + crown * bow(x1)
        for s in [1.0, -1.0] {
            let nn = CV3(0, 0, s), z = s * thick / 2
            mesh.quad(CV3(x0, b0, z), CV3(x1, b1, z), CV3(x1, t1, z), CV3(x0, t0, z), nn, nn, nn, nn, m)
        }
        let nb = CV3(b1 - b0, -(x1 - x0), 0).normalized
        mesh.quad(CV3(x0, b0, -thick / 2), CV3(x1, b1, -thick / 2), CV3(x1, b1, thick / 2), CV3(x0, b0, thick / 2), nb, nb, nb, nb, m)
        let nt = CV3(-(t1 - t0), x1 - x0, 0).normalized
        mesh.quad(CV3(x0, t0, -thick / 2), CV3(x1, t1, -thick / 2), CV3(x1, t1, thick / 2), CV3(x0, t0, thick / 2), nt, nt, nt, nt, m)
    }
    for s in [1.0, -1.0] {
        let nn = CV3(s, 0, 0), x = s * length / 2
        mesh.quad(CV3(x, 0, -thick / 2), CV3(x, height, -thick / 2), CV3(x, height, thick / 2), CV3(x, 0, thick / 2), nn, nn, nn, nn, m)
    }
    return mesh
}

// 2026-10-22 判断（owner の実機「家具によって足が壊れてたりする」）: 棚を脚の形ごとに作り直した。前はキャスターの棚に
// 車輪が無く胴が床から 1 cm 浮き、括れ脚は対角の 2 本だけで胴の 3 cm 下で終わり、台輪は胴に 4 cm 届かなかった。
// いまは胴の下面（`lift`）に、台輪・細い脚（真鍮の沓）・括れ脚（隅の L の板 4）・キャスター（取付け板・金具・車輪）・
// 床置き（裾の幅木）・駒脚（挽いた玉 4）のどれかが必ず届く。胴は箱・三段・縦長・低い櫃・格子・丸、前は戸・引き戸・
// 引き出し・開いた棚（中に本）・硝子戸（中に器）・すだれ
private func storage(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (body, front, legs, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width), hz = varietyHalf(piece.furniture.depth)
    let oak = varietyWood(body), trim = varietyWood(body + 3), metal = varietyMetal(front)
    var parts: [CamperMesh] = []
    let round = body == 5
    let bw = hx * 2 - 1.5, bd = hz * 2 - 1.5
    let rr = min(bw, bd) / 2
    let bodyH: Double
    switch body {
    case 1: bodyH = 30
    case 2: bodyH = 44
    case 3: bodyH = 16
    case 4: bodyH = 26
    default: bodyH = 24
    }
    let lift: Double
    switch legs {
    case 1: lift = 6
    case 2: lift = 3
    case 3: lift = 3.2
    case 4: lift = 0
    case 5: lift = 2.2
    default: lift = 2.4
    }
    // 脚の芯（胴の隅から 1.4 内。丸い胴は斜めに）
    let corner: [(Double, Double)] = round
        ? [(-rr * 0.6, -rr * 0.6), (rr * 0.6, -rr * 0.6), (-rr * 0.6, rr * 0.6), (rr * 0.6, rr * 0.6)]
        : [(-bw / 2 + 1.4, -bd / 2 + 1.4), (bw / 2 - 1.4, -bd / 2 + 1.4), (-bw / 2 + 1.4, bd / 2 - 1.4), (bw / 2 - 1.4, bd / 2 - 1.4)]
    switch legs {
    case 1:
        for (x, z) in corner {
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.5, 0), CV2(0.56, 0.4), CV2(0.78, lift - 0.6), CV2(0.85, lift),
                                                             CV2(0, lift)], segments: 12, trim), at: CV3(x, 0, z)))
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.56, 0), CV2(0.62, 0.1), CV2(0.62, 0.8), CV2(0, 0.8)],
                                                             segments: 12, metal), at: CV3(x, 0, z)))
        }
    case 2:
        // 括れ脚（隅に L 字に組んだ 2 枚の板。外の面は下で括れる）
        for (x, z) in corner {
            let sx = x < 0 ? -1.0 : 1.0, sz = z < 0 ? -1.0 : 1.0
            let cx = round ? x : sx * (bw / 2 - 1.6), cz = round ? z : sz * (bd / 2 - 1.6)
            parts.append(VarietyKit.placed(varietyArchedApron(3.2, height: lift, rise: 1.0, thick: 0.9, trim),
                                           at: CV3(cx, 0, cz + sz * 1.15)))
            parts.append(VarietyKit.placed(varietyArchedApron(3.2, height: lift, rise: 1.0, thick: 0.9, trim),
                                           at: CV3(cx + sx * 1.15, 0, cz), yaw: .pi / 2))
        }
    case 3:
        // キャスター（取付け板・鉄の金具・ゴムの車輪）
        for (x, z) in corner {
            parts.append(varietyBox(CV3(2.4, 0.3, 2.4), CV3(x, lift - 0.3, z), .room(.iron)))
            parts.append(varietyBox(CV3(1.4, 1.7, 1.2), CV3(x, 1.2, z), .room(.iron)))
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: 1.25, height: 0.8, bevel: 0.25, segments: 16, .room(.leather(0x1E1E1E))),
                                           at: CV3(x + 0.4, 1.25, z), rotation: CQuat.axisAngle(CV3(0, 0, 1), .pi / 2)))
        }
    case 4:
        // 床置き（裾に一回り大きい幅木）
        if round {
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: rr + 0.3, height: 1.2, bevel: 0.2, segments: 28, trim), at: .zero))
        } else {
            parts.append(varietyBox(CV3(bw + 0.6, 1.2, bd + 0.6), .zero, trim))
        }
    case 5:
        // 駒脚（挽いた玉の足 4）
        for (x, z) in corner {
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.9, 0), CV2(1.3, 0.6), CV2(1.25, 1.3), CV2(0.85, 1.8), CV2(1.0, lift),
                                                             CV2(0, lift)], segments: 14, trim), at: CV3(x, 0, z)))
        }
    default:
        // 台輪（胴より引っ込めた台）
        if round {
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: rr - 0.8, height: lift, bevel: 0.2, segments: 28, trim), at: .zero))
        } else {
            parts.append(varietyBox(CV3(bw - 1.6, lift, bd - 1.6), .zero, trim))
        }
    }
    // 胴（開いた棚・硝子戸・格子胴は中の見える箱。それ以外は詰まった箱）
    let open = front == 3 || front == 4 || body == 4
    let top = lift + bodyH
    let t = 0.8
    if round {
        // 丸い胴（前だけ平らな面を出して戸・引き出しを付ける）
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: rr, height: bodyH, bevel: 0.4, segments: 24, oak), at: CV3(0, lift, 0)))
        parts.append(VarietyKit.block(CV3(rr * 1.2, bodyH - 0.8, rr * 0.92), at: CV3(0, lift + 0.4, rr * 0.46), radius: 0.4, segments: 1, oak))
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: rr + 0.5, height: 0.9, bevel: 0.3, segments: 24, trim), at: CV3(0, top, 0)))
    } else if open {
        parts.append(varietyBox(CV3(bw, t, bd), CV3(0, lift, 0), oak))
        for x in [-bw / 2 + t / 2, bw / 2 - t / 2] { parts.append(varietyBox(CV3(t, bodyH - t, bd), CV3(x, lift + t, 0), oak)) }
        parts.append(varietyBox(CV3(bw - t * 2, bodyH - t, 0.6), CV3(0, lift + t, -bd / 2 + 0.3), trim))
        parts.append(VarietyKit.block(CV3(bw + 0.8, 1.0, bd + 0.6), at: CV3(0, top, 0.2), radius: 0.3, segments: 1, oak))
        // 中の棚板と、本・器
        let shelves = max(1, Int(bodyH / 11))
        for k in 1...shelves {
            let y = lift + t + (bodyH - t) * Double(k) / Double(shelves + 1)
            parts.append(varietyBox(CV3(bw - t * 2, 0.6, bd - 1), CV3(0, y - 0.6, 0.2), oak))
        }
        for k in 0..<5 {
            let x = -bw / 2 + 2.5 + Double(k) * 1.5
            parts.append(varietyBox(CV3(1.2, 5 + Double(k % 3), bd * 0.55), CV3(x, lift + t, -1), .room(.painted([0x7A2E22, 0x2F4F74, 0xC9B79A, 0x4E6B4A, 0x8C6E5A][k]))))
        }
        parts.append(CamperRoomShapes.mug(at: CV3(bw / 4, lift + t, 0), body: .room(.ceramic(0xEFEAE2)), rim: .room(.ceramic(0xB09A78)), yaw: 0.4))
        if body == 4 {
            // 格子胴（両脇の格子）
            for x in [-bw / 2 - 0.2, bw / 2 + 0.2] {
                for k in 1...4 {
                    let z = -bd / 2 + bd * Double(k) / 5
                    parts.append(varietyBox(CV3(0.4, bodyH - 2, 0.5), CV3(x, lift + 1, z), trim))
                }
            }
        }
    } else {
        if body == 1 {
            // 三段（段ごとに少しずつ幅を詰める・段の継ぎ目。奥行きはそろえて前の戸が段から離れない）
            for k in 0..<3 {
                let inset = Double(k) * 0.6
                parts.append(VarietyKit.block(CV3(bw - inset, bodyH / 3, bd), at: CV3(0, lift + Double(k) * bodyH / 3, 0), radius: 0.35,
                                              segments: 1, oak))
            }
        } else {
            parts.append(VarietyKit.block(CV3(bw, bodyH, bd), at: CV3(0, lift, 0), radius: 0.4, segments: 1, oak))
        }
        parts.append(VarietyKit.block(CV3(bw + 0.8, 1.0, bd + 0.6), at: CV3(0, top, 0.2), radius: 0.3, segments: 1, body == 3 ? trim : oak))
        if body == 3 {
            // 低い櫃（上の四隅に真鍮の角金具）
            for x in [-bw / 2 + 0.7, bw / 2 - 0.7] {
                for z in [-bd / 2 + 0.7, bd / 2 - 0.5] { parts.append(varietyBox(CV3(1.8, 1.8, 1.8), CV3(x, top - 1.2, z), metal)) }
            }
        }
    }
    // 前
    let zf = round ? rr * 0.92 : bd / 2
    let fw = round ? rr * 1.2 - 1 : bw - 2
    let doorY = lift + (open && !round ? t + 0.3 : 1.2)
    let doorH = bodyH - (open && !round ? t + 0.6 : 2.4)
    switch front {
    case 1:
        // 引き戸（前後にずらした 2 枚・引き手の窪み）
        for (k, s) in [-1.0, 1.0].enumerated() {
            let z = zf + (k == 0 ? 0.25 : 0.7)
            parts.append(VarietyKit.block(CV3(fw / 2 + 0.4, doorH, 0.45), at: CV3(s * fw / 4, doorY, z), radius: 0.12, segments: 1, varietyWood(body + 2)))
            parts.append(varietyBox(CV3(0.5, 1.6, 0.2), CV3(s * (fw / 2 - 1.4), doorY + doorH / 2 - 0.8, z + 0.25), .room(.iron)))
        }
    case 2:
        // 引き出し（段ごとの前板と真鍮の取っ手）
        let n = bodyH > 30 ? 5 : (bodyH > 20 ? 3 : 2)
        let h = doorH / Double(n)
        for k in 0..<n {
            let y = doorY + Double(k) * h
            parts.append(VarietyKit.block(CV3(fw, h - 0.4, 0.5), at: CV3(0, y + 0.2, zf + 0.2), radius: 0.15, segments: 1, varietyWood(body + 2)))
            parts.append(VarietyKit.tube([CV3(-1.6, y + h / 2, zf + 0.75), CV3(1.6, y + h / 2, zf + 0.75)], radius: 0.22, sides: 8, metal))
        }
    case 3:
        break
    case 4:
        // 硝子戸（框の戸 2 枚に板硝子・つまみ）
        for s in [-1.0, 1.0] {
            let cx = s * fw / 4
            for x in [cx - fw / 4 + 0.6, cx + fw / 4 - 0.6] { parts.append(varietyBox(CV3(1.2, doorH, 0.6), CV3(x, doorY, zf + 0.3), oak)) }
            for y in [doorY, doorY + doorH - 1.2] { parts.append(varietyBox(CV3(fw / 2 - 2.4, 1.2, 0.6), CV3(cx, y, zf + 0.3), oak)) }
            parts.append(varietyBox(CV3(fw / 2 - 2.4, doorH - 2.4, 0.2), CV3(cx, doorY + 1.2, zf + 0.3), .room(.clearGlass)))
            parts.append(VarietyKit.placed(VarietyKit.sphere(radius: 0.4, segments: 10, metal), at: CV3(s * 1.4, doorY + doorH / 2, zf + 0.9)))
        }
    case 5:
        // すだれ（細い竹を縦に並べ、上の巻きと紐）
        let n = Int(fw / 0.9)
        for k in 0..<n {
            let x = -fw / 2 + 0.45 + Double(k) * fw / Double(n)
            parts.append(VarietyKit.tube([CV3(x, doorY, zf + 0.5), CV3(x, doorY + doorH - 1.2, zf + 0.5)], radius: 0.2, sides: 5, .room(.rush)))
        }
        parts.append(VarietyKit.tube([CV3(-fw / 2, doorY + doorH - 0.7, zf + 0.6), CV3(fw / 2, doorY + doorH - 0.7, zf + 0.6)],
                                     radius: 0.6, sides: 10, .room(.rushEdge)))
    default:
        // 開き戸（鏡板の戸 2 枚・つまみ）
        for s in [-1.0, 1.0] {
            let cx = s * fw / 4
            parts.append(VarietyKit.block(CV3(fw / 2 - 0.2, doorH, 0.6), at: CV3(cx, doorY, zf + 0.2), radius: 0.15, segments: 1, varietyWood(body + 2)))
            parts.append(VarietyKit.block(CV3(fw / 2 - 2.4, doorH - 2.4, 0.3), at: CV3(cx, doorY + 1.2, zf + 0.6), radius: 0.3, segments: 1, oak))
            parts.append(VarietyKit.placed(VarietyKit.sphere(radius: 0.45, segments: 10, metal), at: CV3(s * 1.2, doorY + doorH / 2, zf + 1.0)))
        }
    }
    return varietyMerge(parts)
}

// 2026-10-22 判断（owner の実機「家具によって足が壊れてたりする」）: 暖炉を足の形ごとに作り直した。前は猫足が前の 2 本だけで
// 胴の後ろが宙に浮き、暖炉の口の火と石油罐の窓は胴から離れて浮き、丸い胴は八角の箱だった。いまは胴の下面（`foot`）に
// 三本足（鋳物の挽き足）・台・猫足 4・床の炉台のどれかが必ず届き、火の窓は胴の前の面に付く。胴は旋盤で丸く挽く
private func heater(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (body, flue, feet, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width)
    let iron = varietyMetal(body), cast = CamperMaterial.room(.castIron), fire = CamperMaterial.room(.fire)
    var parts: [CamperMesh] = []
    let round = body == 1 || body == 2 || body == 4
    let r = hx - 1.4
    let bw = hx * 2 - 2, bd = hx * 2 - 3
    let foot = feet == 3 ? 1.2 : 3.0
    // 足
    switch feet {
    case 0:
        // 三本足（鋳物の挽き足。胴の縁の内）
        for k in 0..<3 {
            let a = .pi / 2 + Double(k) * 2 * .pi / 3
            let p = CV3(cos(a) * r * 0.62, 0, sin(a) * r * 0.62)
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(1.0, 0), CV2(1.1, 0.4), CV2(0.6, 1.2), CV2(0.75, 2.4), CV2(1.0, foot),
                                                             CV2(0, foot)], segments: 12, cast), at: p))
        }
    case 1:
        // 台（胴より一回り小さい鉄の台）
        if round {
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: r - 0.8, height: foot, bevel: 0.3, segments: 28, cast), at: .zero))
        } else {
            parts.append(VarietyKit.block(CV3(bw - 1.6, foot, bd - 1.6), at: .zero, radius: 0.3, segments: 1, cast))
        }
    case 2:
        // 猫足（四隅の玉を掴む足 4）
        let c = round ? r * 0.55 : 1.0
        let corners = round ? [(-c, -c), (c, -c), (-c, c), (c, c)]
            : [(-bw / 2 + 1.6, -bd / 2 + 1.6), (bw / 2 - 1.6, -bd / 2 + 1.6), (-bw / 2 + 1.6, bd / 2 - 1.6), (bw / 2 - 1.6, bd / 2 - 1.6)]
        for (x, z) in corners {
            parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.9, 0), CV2(1.15, 0.5), CV2(0.95, 1.2), CV2(0.55, 1.6), CV2(0.7, 2.4),
                                                             CV2(1.1, foot), CV2(0, foot)], segments: 12, cast), at: CV3(x, 0, z)))
        }
    default:
        // 床の炉台（石の板。胴より広く、前へ張り出す）
        parts.append(VarietyKit.block(CV3(hx * 2 - 0.6, foot, hx * 2 - 0.6), at: .zero, radius: 0.3, segments: 1, .room(.ceramic(0xC4B49A))))
    }
    // 胴
    let bodyH = 16 + Double(body) * 3
    let top = foot + bodyH
    let frontZ: Double
    switch body {
    case 1:
        // だるま（腹のふくらんだ鋳物の胴）
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(r * 0.7, 0), CV2(r * 0.95, bodyH * 0.25), CV2(r, bodyH * 0.45),
                                                         CV2(r * 0.85, bodyH * 0.75), CV2(r * 0.6, bodyH * 0.95), CV2(r * 0.62, bodyH), CV2(0, bodyH)],
                                                        segments: 28, cast), at: CV3(0, foot, 0)))
        frontZ = r * 0.97
    case 2, 4:
        // 円筒（鉄の筒と上下の帯）・石油罐（琺瑯の筒）
        let skin = body == 4 ? CamperMaterial.room(.enamel(0xC23B2E)) : iron
        let h = body == 4 ? bodyH * 0.8 : bodyH
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: r, height: h, bevel: 0.6, segments: 28, skin), at: CV3(0, foot, 0)))
        for y in [foot + 1.2, foot + h - 2.2] {
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: r + 0.25, height: 1.0, bevel: 0.2, segments: 28, cast), at: CV3(0, y, 0)))
        }
        frontZ = r
    case 3:
        // 暖炉の口（煉瓦色の箱と、上の棚板）
        parts.append(VarietyKit.block(CV3(bw, bodyH, bd), at: CV3(0, foot, 0), radius: 0.4, segments: 1, .room(.ceramic(0xB4664A))))
        parts.append(VarietyKit.block(CV3(bw + 1.2, 1.2, bd + 0.8), at: CV3(0, top, 0.2), radius: 0.3, segments: 1, .room(.wood(.darkOak))))
        frontZ = bd / 2
    default:
        // 箱ストーブ（鋳物の箱・上の鉄板）
        parts.append(VarietyKit.block(CV3(bw, bodyH, bd), at: CV3(0, foot, 0), radius: 0.5, segments: 1, cast))
        parts.append(VarietyKit.block(CV3(bw + 0.8, 0.8, bd + 0.8), at: CV3(0, top, 0), radius: 0.25, segments: 1, iron))
        frontZ = bd / 2
    }
    // 火の窓（前の面に枠と雲母、その奥に火）
    let winW = body == 3 ? bw * 0.6 : (round ? r * 0.8 : bw * 0.55)
    let winH = bodyH * (body == 3 ? 0.5 : 0.36)
    let winY = foot + (body == 3 ? 1.6 : bodyH * 0.3)
    if body == 3 {
        // 暖炉の口（黒い炉の奥に薪の火・口の上に弓形の縁）
        parts.append(varietyBox(CV3(winW, winH, 0.3), CV3(0, winY, frontZ + 0.05), cast))
        parts.append(varietyBox(CV3(winW * 0.7, winH * 0.45, 0.3), CV3(0, winY + 0.3, frontZ + 0.3), fire))
        parts.append(VarietyKit.placed(varietyArchedApron(winW + 1.2, height: 1.0, rise: 0, crown: 1.8, thick: 0.6, .room(.ceramic(0x9A5038))),
                                       at: CV3(0, winY + winH + 0.6, frontZ + 0.3)))
    } else {
        parts.append(varietyBox(CV3(winW, winH, 0.3), CV3(0, winY, frontZ + 0.05), fire))
        parts.append(varietyBox(CV3(winW, winH, 0.1), CV3(0, winY, frontZ + 0.3), .room(.mica)))
    }
    for y in [winY - 0.6, winY + winH] { parts.append(varietyBox(CV3(winW + 1.2, 0.6, 0.5), CV3(0, y, frontZ + 0.25), iron)) }
    for x in [-winW / 2 - 0.3, winW / 2 + 0.3] { parts.append(varietyBox(CV3(0.6, winH, 0.5), CV3(x, winY, frontZ + 0.25), iron)) }
    // 扉の取っ手
    parts.append(VarietyKit.tube([CV3(winW / 2 + 0.3, winY + winH * 0.5, frontZ + 0.5), CV3(winW / 2 + 1.6, winY + winH * 0.5, frontZ + 0.9)],
                                 radius: 0.22, sides: 6, .room(.brass)))
    // 煙突（上の面から天井へ向けて。曲がる煙突は後ろへ折れてから上る）
    let fy = body == 3 ? top + 1.2 : (body == 4 ? foot + bodyH * 0.8 : top + (body == 0 ? 0.8 : 0))
    let pipe: CamperMaterial = .room(.iron)
    switch flue {
    case 0:
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(1.0, 0), CV2(1.0, 20), CV2(0, 20)], segments: 16, pipe), at: CV3(0, fy - 0.2, -1)))
    case 1:
        let path = [CV3(0, fy - 0.2, -1), CV3(0, fy + 6, -1), CV3(0, fy + 7.4, -1.6), CV3(0, fy + 8, -3), CV3(0, fy + 8.6, -4.4),
                    CV3(0, fy + 10, -5), CV3(0, fy + 20, -5)]
        parts.append(VarietyKit.tube(path, radius: 1.0, sides: 14, pipe))
    case 3:
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(1.5, 0), CV2(1.5, 18), CV2(0, 18)], segments: 18, pipe), at: CV3(0, fy - 0.2, -1)))
        for y in [fy + 4, fy + 11] {
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: 1.8, height: 0.6, bevel: 0.15, segments: 18, iron), at: CV3(0, y, -1)))
        }
    default:
        // 煙突なし（上の面の蓋とつまみ）
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 2.4, height: 0.6, bevel: 0.2, segments: 20, iron), at: CV3(0, fy - 0.1, 0)))
        parts.append(VarietyKit.placed(VarietyKit.sphere(radius: 0.6, segments: 10, .room(.brass)), at: CV3(0, fy + 0.9, 0)))
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

// 2026-10-22 判断（owner の実機「家具によって足が壊れてたりする」）: 床の灯りを足と柱の形ごとに作り直した。前は箱を
// 積んだだけで、弧の柱の笠と電球が柱から離れて浮き、三本の足は柱に届かず、和紙の柱は笠と柱が別の所に立っていた。
// いまは台（丸・四角・三本足・石・十字の足）の上面（`base`）に柱が立ち、柱の頭（`head`）に受け口と電球、
// 笠は受け口から出した細い腕で吊る（板の三脚の灯りと同じ作り）
/// 床の灯りの台の上面（足の形ごと）。形と光の位置（`CamperRoomVariety.lamp`）が同じ式を使う
private func varietyLampBase(_ foot: Int) -> Double {
    switch foot {
    case 1: return 1.6
    case 2: return 4.4
    case 3: return 2.4
    default: return 2.0
    }
}

/// 床の灯りの柱の頭（受け口の下の面）。弧の柱は前へ張り出して先で下を向く
private func varietyLampHead(stem: Int, foot: Int) -> CV3 {
    let base = varietyLampBase(foot), stemH = 38 + Double(stem % 3) * 5
    guard stem == 2 else { return CV3(0, base + stemH, 0) }
    let rise = base + stemH * 0.72, a = Double.pi * 0.75
    return CV3(0, rise + sin(a) * 6, 6 - cos(a) * 6) + CV3(0, -0.4, 0.4)
}

/// 電球の芯は受け口の下の面から 3.6 上
private let varietyBulbAboveHead = CV3(0, 3.6, 0)

/// 暖炉の火の窓の真ん中（前の面の少し前）。形と光の位置が同じ式を使う
private func varietyHeaterFire(body: Int, feet: Int, hx: Double) -> CV3 {
    let foot = feet == 3 ? 1.2 : 3.0, bodyH = 16 + Double(body) * 3
    let r = hx - 1.4, bd = hx * 2 - 3
    let frontZ = body == 1 ? r * 0.97 : (body == 2 || body == 4 ? r : bd / 2)
    let winH = bodyH * (body == 3 ? 0.5 : 0.36), winY = foot + (body == 3 ? 1.6 : bodyH * 0.3)
    // 暖炉の口は炉の奥の下に薪の火（窓の下 45%）
    return CV3(0, body == 3 ? winY + 0.3 + winH * 0.225 : winY + winH / 2, frontZ + 0.2)
}

private func floorLamp(_ piece: CamperRoomVariety.Piece) -> CamperMesh {
    let (stem, shade, foot, _) = piece.axes
    let oak = varietyWood(stem), metal = varietyMetal(foot + stem), shadeM = CamperMaterial.room(.shade(0xF3E6C8))
    var parts: [CamperMesh] = []
    // 台
    let base = varietyLampBase(foot)
    switch foot {
    case 1:
        parts.append(VarietyKit.block(CV3(8, 1.6, 8), at: .zero, radius: 0.5, segments: 1, oak))
    case 2:
        // 三本の足（外へ開く短い脚と革の当て・真ん中の受け）
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi + .pi / 6
            let tip = CV3(cos(a) * 4.6, 0.5, sin(a) * 4.6)
            parts.append(VarietyKit.tube([tip, CV3(cos(a) * 0.9, 3.6, sin(a) * 0.9)], radius: 0.45, sides: 8, metal))
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: 0.75, height: 0.45, bevel: 0.12, segments: 10, .room(.leather(0x2A2522))),
                                           at: CV3(tip.x, 0, tip.z)))
        }
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(1.2, 0), CV2(1.3, 0.6), CV2(1.0, 1.4), CV2(0, 1.4)], segments: 14, metal),
                                       at: CV3(0, 3.0, 0)))
    case 3:
        parts.append(VarietyKit.block(CV3(7, 2.4, 7), at: .zero, radius: 0.8, segments: 2, .room(.ceramic(0xB7B1A6))))
    case 4:
        // 十字の足（床の 2 本の桟と真ん中の座）
        for yaw in [0.0, .pi / 2] {
            parts.append(VarietyKit.placed(VarietyKit.roundedBox(CV3(10, 1.2, 1.6), radius: 0.4, segments: 1, metal), at: CV3(0, 0.6, 0), yaw: yaw + .pi / 4))
        }
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 1.6, height: 1.0, bevel: 0.3, segments: 16, metal), at: CV3(0, 1.0, 0)))
    default:
        // 丸い台（縁を落とした鉄の円盤と、柱の受けの盛り上がり）
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(4.2, 0), CV2(4.3, 0.5), CV2(3.9, 1.1), CV2(1.6, 1.5), CV2(1.0, 2.0),
                                                         CV2(0, 2.0)], segments: 28, metal), at: .zero))
    }
    // 柱（頭の位置 `head` を決める。弧の柱は前へ張り出す）
    let stemH = 38 + Double(stem % 3) * 5
    let head = varietyLampHead(stem: stem, foot: foot)
    switch stem {
    case 1:
        // 節（下と上の管を真ん中の玉の継ぎ手でつなぐ）
        let mid = base + stemH * 0.5
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.65, 0), CV2(0.6, mid - base), CV2(0, mid - base)], segments: 12, metal),
                                       at: CV3(0, base, 0)))
        parts.append(VarietyKit.placed(VarietyKit.sphere(radius: 1.1, segments: 14, .room(.brass)), at: CV3(0, mid, 0)))
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.55, 0), CV2(0.5, head.y - mid), CV2(0, head.y - mid)], segments: 12, metal),
                                       at: CV3(0, mid, 0)))
    case 2:
        // 弧（まっすぐ上ってから前へ曲がり、先で下を向く）
        let rise = base + stemH * 0.72
        var path = [CV3(0, base, 0), CV3(0, rise, 0)]
        for k in 1...8 {
            let a = Double(k) / 8 * .pi * 0.75
            path.append(CV3(0, rise + sin(a) * 6, 6 - cos(a) * 6))
        }
        parts.append(VarietyKit.tube(path, radius: 0.55, sides: 10, metal))
    case 3:
        // 三脚（台の縁から柱の頭へ集まる 3 本の木の棒と、頭の継ぎ輪）
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi + 0.5
            parts.append(VarietyKit.tube([CV3(cos(a) * 1.4, base - 0.3, sin(a) * 1.4), head + CV3(cos(a) * 0.5, -1.2, sin(a) * 0.5)],
                                         radius: 0.5, sides: 8, oak))
        }
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 1.2, height: 1.4, bevel: 0.3, segments: 14, metal), at: head + CV3(0, -1.4, 0)))
    case 4:
        // 二本（平行の細い棒 2 と上下の渡し）
        for x in [-1.0, 1.0] {
            parts.append(VarietyKit.tube([CV3(x, base - 0.2, 0), CV3(x, head.y - 0.6, 0)], radius: 0.35, sides: 8, metal))
        }
        for y in [base + 0.4, base + stemH * 0.5, head.y - 0.4] {
            parts.append(VarietyKit.block(CV3(2.8, 0.8, 1.0), at: CV3(0, y - 0.4, 0), radius: 0.2, segments: 1, metal))
        }
    case 5:
        // ねじれ（挽いた木の柱に、ねじれの段を刻む）
        var profile = [CV2(0, 0), CV2(0.9, 0)]
        let n = 22
        for k in 0...n {
            let y = stemH * Double(k) / Double(n)
            profile.append(CV2(k % 2 == 0 ? 0.95 : 0.7, y))
        }
        profile.append(CV2(0, stemH))
        parts.append(VarietyKit.placed(VarietyKit.lathe(profile, segments: 14, oak), at: CV3(0, base, 0)))
    default:
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.7, 0), CV2(0.55, 1.2), CV2(0.5, stemH), CV2(0, stemH)], segments: 12, metal),
                                       at: CV3(0, base, 0)))
    }
    // 受け口と電球（頭の上）
    parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(0, 0), CV2(0.85, 0), CV2(0.85, 2.0), CV2(0.6, 2.4), CV2(0, 2.4)], segments: 14, .room(.brass)),
                                   at: head))
    let bulb = head + varietyBulbAboveHead
    parts.append(VarietyKit.placed(VarietyKit.sphere(radius: 1.5, segments: 14, .room(.bulb)), at: bulb))
    // 笠と、受け口から笠の縁へ出す細い腕
    func arms(_ rimY: Double, _ r: Double) {
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi
            parts.append(VarietyKit.tube([head + CV3(0, 2.2, 0), CV3(head.x + cos(a) * r, rimY, head.z + sin(a) * r)], radius: 0.1, sides: 4, .room(.brass)))
        }
    }
    func ring(_ lo: Double, _ hi: Double, _ r0: Double, _ r1: Double) {
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(r0, 0), CV2(r1, hi - lo)], segments: 24, shadeM, capStart: false, capEnd: false),
                                       at: CV3(head.x, lo, head.z)))
        parts.append(VarietyKit.placed(VarietyKit.inverted(VarietyKit.lathe([CV2(r0 - 0.2, 0), CV2(r1 - 0.2, hi - lo)], segments: 24, shadeM,
                                                                            capStart: false, capEnd: false)), at: CV3(head.x, lo, head.z)))
        for (y, r) in [(lo, r0), (hi, r1)] {
            parts.append(VarietyKit.tube(VarietyKit.ringXZ(center: CV3(head.x, y, head.z), radius: r - 0.1, steps: 32), radius: 0.18, sides: 5,
                                         closed: true, .room(.shade(0xD8CBB2))))
        }
        arms(hi - 0.4, r1 - 0.3)
    }
    switch shade {
    case 1:
        ring(bulb.y - 4, bulb.y + 4, 5.4, 5.4)
    case 2:
        // 球の笠（乳白の硝子の玉を受け口の上に）
        parts.append(VarietyKit.placed(VarietyKit.sphere(radius: 4, segments: 20, .room(.milkGlass)), at: bulb + CV3(0, 0.8, 0)))
    case 3:
        // 四角の笠（4 枚の布張りの板と上下の枠）
        let w = 9.0, h = 7.0, y0 = bulb.y - 3.5
        for (dx, dz, sx, sz) in [(0.0, w / 2, w, 0.3), (0.0, -w / 2, w, 0.3), (w / 2, 0.0, 0.3, w), (-w / 2, 0.0, 0.3, w)] {
            parts.append(varietyBox(CV3(sx, h, sz), CV3(head.x + dx, y0, head.z + dz), shadeM))
        }
        arms(y0 + h - 0.4, w / 2 - 0.2)
    case 4:
        // 和紙の筒（受け口の皿に立てた四角い紙の筒・上の木の蓋）
        let w = 6.0, h = 14.0, y0 = head.y + 2.4
        parts.append(VarietyKit.block(CV3(w + 0.6, 0.6, w + 0.6), at: CV3(head.x, y0 - 0.6, head.z), radius: 0.2, segments: 1, oak))
        for (dx, dz, sx, sz) in [(0.0, w / 2, w, 0.2), (0.0, -w / 2, w, 0.2), (w / 2, 0.0, 0.2, w), (-w / 2, 0.0, 0.2, w)] {
            parts.append(varietyBox(CV3(sx, h, sz), CV3(head.x + dx, y0, head.z + dz), .room(.paper)))
        }
        parts.append(VarietyKit.block(CV3(w + 0.6, 0.7, w + 0.6), at: CV3(head.x, y0 + h, head.z), radius: 0.2, segments: 1, oak))
    case 5:
        // 傘（浅い円錐の布と、頂の飾り）
        let lo = bulb.y + 0.6
        parts.append(VarietyKit.placed(VarietyKit.lathe([CV2(8, 0), CV2(1.0, 3.2)], segments: 24, clothSafe(shade + stem), capStart: false, capEnd: false),
                                       at: CV3(head.x, lo, head.z)))
        parts.append(VarietyKit.placed(VarietyKit.inverted(VarietyKit.lathe([CV2(7.9, -0.15), CV2(0.9, 3.05)], segments: 24, clothSafe(shade + stem),
                                                                            capStart: false, capEnd: false)), at: CV3(head.x, lo, head.z)))
        parts.append(VarietyKit.placed(VarietyKit.sphere(radius: 0.6, segments: 10, .room(.brass)), at: CV3(head.x, lo + 3.4, head.z)))
        parts.append(VarietyKit.tube([head + CV3(0, 2.2, 0), CV3(head.x, lo + 3.2, head.z)], radius: 0.18, sides: 6, .room(.brass)))
        arms(lo + 0.2, 7.4)
    default:
        // 円錐の笠（上が細く下が広い）
        ring(bulb.y - 3.5, bulb.y + 3.5, 6.6, 3.4)
    }
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
            parts.append(varietyBox(CV3(1.1, 3.2, 1.1), CV3(x, 8.4, 1.4), .room(.clearGlass)))
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
    // 無穴の直方体に写真を重ねると、段枠・桟が印画を覆って「飾っても載らない」に見える。
    // 共通の額（穴付きマット・写真・硝子）に寄せ、飾りは印画の外だけに足す（2026-10-20）
    let (opening, moulding, _, _) = piece.axes
    let hx = varietyHalf(piece.furniture.width)
    let wood = varietyWood(moulding), brass = varietyMetal(moulding)
    let tall = opening == 2 || opening == 4
    let fw = opening == 1 || opening == 5 ? hx * 1.3 : hx * 1.7
    let fh = tall ? 15.0 : 11.0
    let mould = moulding == 3 ? brass : wood
    let depth = moulding == 4 ? 1.25 : 1.6
    let rim = moulding == 1 ? 1.45 : 1.15
    let photo = CV2(max(4.5, fw - rim * 2 - 2.2), max(4.5, fh - rim * 2 - 2.2))
    let center = CV3(0, max(8, fh * 0.55 + 1.2), 0)
    var parts = [CamperRoomShapes.frame(outer: CV2(fw, fh), photo: photo, depth: depth, rim: rim, at: center, frame: mould)]
    if opening == 4 {
        // 上縁の飾り（印画の上の外枠側）
        parts.append(varietyBox(CV3(fw * 0.55, 1.4, 0.55), CV3(0, center.y + fh / 2 - 0.9, depth + 0.4), mould))
    } else if opening == 5 {
        // 外枠の脇の細い飾り（印画の真ん中は跨がない）
        parts.append(varietyBox(CV3(0.45, fh - 4, 0.45), CV3(fw / 2 - 0.4, center.y, depth + 0.35), mould))
    } else if opening == 3 {
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 0.55, height: 0.35, bevel: 0.1, segments: 8, brass),
                                       at: CV3(0, center.y + fh / 2 - 0.6, depth + 0.5)))
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
            parts.append(VarietyKit.placed(VarietyKit.disc(radius: 0.8, height: 0.5, bevel: 0.15, segments: 8, .room(.clearGlass)), at: CV3(x, y, 0)))
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
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: 2.2, height: 3.4, bevel: 0.5, segments: 8, .room(.clearGlass)), at: CV3(0, potY, 0)))
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
        parts.append(VarietyKit.placed(VarietyKit.disc(radius: hx * 0.62, height: 0.5, bevel: 0.1, segments: 8, .room(.clearGlass)), at: CV3(0, -0.8, 0)))
    case 2:
        parts.append(varietyBox(CV3(hx * 1.5, 1.8, hx * 1.5), CV3(0, -1.8, 0), wood))
        parts.append(varietyBox(CV3(hx, 0.4, hx), CV3(0, -0.6, 0), .room(.clearGlass)))
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
