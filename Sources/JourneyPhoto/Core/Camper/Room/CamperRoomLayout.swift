import Foundation

// とおまわり号の中の部屋の広さ・動かせない物・置く決まり（2026-10-19・板「CamperRoom」と付箋「マス目と寸法」「置く決まり」）。
//
// 長さ（x・後ろから運転席の仕切り）も幅（z・奥の壁から扉の壁）も、車の実寸より広い箱庭。
// 実寸（バン 12×8、キャンピングカー 18×9）だと寝台が 8×4 で、集めた家具が床に並ばない
// （2026-10-19 owner「中もっと広く」「家具を集めても置けない」）。1 マス = 10 ≈ 25 cm。天井は 88 のまま。
// 部屋の座標は左奥が原点: x は後ろ（0）から運転席の仕切りへ、z は奥の壁（0）から扉の壁へ、y は床から上。
// 素の Swift なので Linux でも試験できる。

/// 部屋（車の部屋と、トレーラーつきの 2 つ目の部屋）
enum CamperRoomKind: String, CaseIterable, Codable, Sendable {
    case car
    case trailer

    var name: String {
        switch self {
        case .car: return L("車の部屋", "Camper room")
        case .trailer: return L("トレーラーの部屋", "Trailer room")
        }
    }

    /// その段で入れる部屋（トレーラーの部屋はトレーラーつきから）
    static func rooms(_ stage: CamperStage) -> [CamperRoomKind] { stage == .trailer ? [.car, .trailer] : [.car] }
}

/// 壁の物を掛けられる壁（奥の壁と後ろの壁。扉の壁と運転席の仕切りは使わない）。保存の値は板の `w`（back / left）
enum CamperRoomWall: String, CaseIterable, Codable, Sendable {
    /// 奥の壁（z = 0。横のマスは x）
    case back
    /// 後ろの壁（x = 0。横のマスは z）
    case left
}

/// 窓（壁の穴。上には壁の物を置けない）
struct CamperRoomWindow: Equatable, Sendable {
    var wall: CamperRoomWall
    /// 横のマス（from から to まで）
    var from: Int
    var to: Int
    /// 床からの高さ（板の単位）
    var bottom = 34.0
    var top = 66.0
}

/// マスの四角（x, z から w × d）
struct CamperRoomRect: Equatable, Hashable, Sendable {
    var x: Int
    var z: Int
    var w: Int
    var d: Int

    func contains(_ cx: Int, _ cz: Int) -> Bool { cx >= x && cx < x + w && cz >= z && cz < z + d }
    func intersects(_ o: CamperRoomRect) -> Bool { x < o.x + o.w && o.x < x + w && z < o.z + o.d && o.z < z + d }
    var cells: [CamperRoomCell] { (x..<(x + w)).flatMap { cx in (z..<(z + d)).map { CamperRoomCell(x: cx, z: $0) } } }
}

struct CamperRoomCell: Equatable, Hashable, Sendable {
    var x: Int
    var z: Int
}

/// 部屋の広さと動かせない物
struct CamperRoomLayout: Equatable, Sendable {
    var kind: CamperRoomKind
    /// 横（x）と奥（z）のマスの数
    var width: Int
    var depth: Int
    /// 扉（扉の壁の上の横のマス）。扉の前 3×3 は空けておく
    var door: ClosedRange<Int>
    /// 台所（奥の壁に付いた 6×3。高さ 36）
    var kitchen: CamperRoomRect
    var windows: [CamperRoomWindow]
    /// 置ける数の上限（床／壁／天井）と写真の上限（額とポスターの合計）
    var floorLimit: Int
    var wallLimit: Int
    var ceilingLimit: Int
    var photoLimit: Int
    /// 図鑑の寄りの小さな部屋（台所と扉の口を作らない）
    var isStudio = false

    static let cell = 10.0
    static let ceiling = 88.0
    static let wallThickness = 4.0
    static let kitchenHeight = 36.0
    /// 壁の段（腰・目・上）の下の高さ。段の高さは 20
    static let rowBottoms = [20.0, 40.0, 60.0]
    static let rowHeight = 20.0
    /// 天井の物を吊れない、床の家具の高さ（ストーブの煙突・床の灯り）
    static let tallForCeiling = 50.0

    /// 扉の前の 3×3（敷物は敷ける・家具は置けない）
    var doorClearance: CamperRoomRect { CamperRoomRect(x: door.lowerBound, z: depth - 3, w: door.count, d: 3) }

    /// 床の広さ（板の単位）
    var size: (x: Double, z: Double) { (Double(width) * Self.cell, Double(depth) * Self.cell) }

    /// 壁の横のマスの数
    func columns(_ wall: CamperRoomWall) -> Int { wall == .back ? width : depth }

    /// 集められる家具（床 24・壁 16・天井 13）が、台所と扉の前と通り道を残したまま全部置ける広さ。
    /// バン 18×16、キャンピングカー 22×18、トレーラー 26×20。上限はそれより少し大きい
    /// （床 40/48/60、壁 48/60/72、天井 20/24/32、写真 24/36/48）。
    static func make(_ kind: CamperRoomKind, stage: CamperStage) -> CamperRoomLayout {
        switch (kind, stage) {
        case (.car, .van):
            return CamperRoomLayout(kind: .car, width: 18, depth: 16, door: 15...17, kitchen: CamperRoomRect(x: 12, z: 0, w: 6, d: 3),
                                    windows: [CamperRoomWindow(wall: .back, from: 2, to: 5), CamperRoomWindow(wall: .left, from: 4, to: 9)],
                                    floorLimit: 40, wallLimit: 48, ceilingLimit: 20, photoLimit: 24)
        case (.car, _):
            return CamperRoomLayout(kind: .car, width: 22, depth: 18, door: 19...21, kitchen: CamperRoomRect(x: 16, z: 0, w: 6, d: 3),
                                    windows: [CamperRoomWindow(wall: .back, from: 3, to: 6), CamperRoomWindow(wall: .left, from: 4, to: 10)],
                                    floorLimit: 48, wallLimit: 60, ceilingLimit: 24, photoLimit: 36)
        case (.trailer, _):
            return CamperRoomLayout(kind: .trailer, width: 26, depth: 20, door: 23...25, kitchen: CamperRoomRect(x: 20, z: 0, w: 6, d: 3),
                                    windows: [CamperRoomWindow(wall: .back, from: 4, to: 7), CamperRoomWindow(wall: .back, from: 14, to: 17),
                                              CamperRoomWindow(wall: .left, from: 5, to: 12)],
                                    floorLimit: 60, wallLimit: 72, ceilingLimit: 32, photoLimit: 48)
        }
    }
}

// MARK: - 置いた家具（保存の形は板の付箋「保存する形」）

/// 置いた家具 1 つ。k は図鑑の id（前の camper.room. は省く）。床と天井は x, z（左奥からのマス）と r（90° の回数）、
/// 敷物は l = 0。壁の物は w（back / left）・c（横のマス）・row（段）。p は飾った写真（投稿の写真の id）
struct CamperRoomItem: Codable, Equatable, Sendable, Identifiable {
    /// 端末の中だけの名前（選ぶ・動かすときに見分ける）
    var u: String
    var k: String
    var x: Int?
    var z: Int?
    var r: Int?
    var l: Int?
    var w: CamperRoomWall?
    var c: Int?
    var row: Int?
    var p: String?

    var id: String { u }
    var furniture: CamperRoomFurniture? { CamperRoomCatalog.furniture(k) }
    var turns: Int { ((r ?? 0) % 4 + 4) % 4 }

    static func floor(_ u: String, _ k: String, x: Int, z: Int, r: Int = 0) -> CamperRoomItem {
        let rug = CamperRoomCatalog.furniture(k)?.isRug == true
        return CamperRoomItem(u: u, k: k, x: x, z: z, r: r, l: rug ? 0 : nil)
    }

    static func wall(_ u: String, _ k: String, _ w: CamperRoomWall, c: Int, row: Int, photo: String? = nil) -> CamperRoomItem {
        CamperRoomItem(u: u, k: k, w: w, c: c, row: row, p: photo)
    }

    static func ceiling(_ u: String, _ k: String, x: Int, z: Int, r: Int = 0) -> CamperRoomItem {
        CamperRoomItem(u: u, k: k, x: x, z: z, r: r)
    }

    /// 床・天井の物の占めるマス（回すと横と奥が入れ替わる）
    var rect: CamperRoomRect? {
        guard let f = furniture, f.placement != .wall, let x, let z else { return nil }
        let odd = turns % 2 == 1
        return CamperRoomRect(x: x, z: z, w: odd ? f.depth : f.width, d: odd ? f.width : f.depth)
    }

    /// 壁の物の占める横のマスと段
    var wallSpan: (wall: CamperRoomWall, columns: Range<Int>, rows: Range<Int>)? {
        guard let f = furniture, f.placement == .wall, let w, let c, let row else { return nil }
        return (w, c..<(c + f.width), row..<(row + f.depth))
    }
}

/// 模様替え（壁紙・床・カーテン・灯りの色。部屋ごとに 1 つずつ）。壁と床は外まわりの図鑑の「室内」の部品の key
struct CamperRoomStyle: Codable, Equatable, Sendable {
    var wall = "pine_boards"
    var floor = "oak_planks"
    var curtain = "linen"
    var light = "warm"
}

/// 1 部屋 1 文書（板の付箋「保存する形」: {"v":1,"room":"camper","rev":12,"updatedAt":…,"style":{…},"items":[…],"ceil":[…]}）
struct CamperRoomDocument: Codable, Equatable, Sendable {
    var v = 1
    var room: CamperRoomKind
    var rev = 0
    var updatedAt = ""
    var style = CamperRoomStyle()
    /// 床と壁の物
    var items: [CamperRoomItem] = []
    /// 天井の物
    var ceil: [CamperRoomItem] = []

    init(room: CamperRoomKind) { self.room = room }

    /// 床・壁・天井の全部
    var all: [CamperRoomItem] { items + ceil }

    func item(_ u: String) -> CamperRoomItem? { all.first { $0.u == u } }

    mutating func upsert(_ item: CamperRoomItem) {
        let ceiling = item.furniture?.placement == .ceiling
        if let i = items.firstIndex(where: { $0.u == item.u }) {
            if ceiling { items.remove(at: i); ceil.append(item) } else { items[i] = item }
        } else if let i = ceil.firstIndex(where: { $0.u == item.u }) {
            if ceiling { ceil[i] = item } else { ceil.remove(at: i); items.append(item) }
        } else if ceiling {
            ceil.append(item)
        } else {
            items.append(item)
        }
    }

    mutating func remove(_ u: String) {
        items.removeAll { $0.u == u }
        ceil.removeAll { $0.u == u }
    }

    /// 次の名前（同じ文書の中で重ならない）
    func nextUid() -> String {
        let used = Set(all.map(\.u))
        var n = all.count + 1
        while used.contains("i\(n)") { n += 1 }
        return "i\(n)"
    }
}

// MARK: - 置く決まり（付箋「置く決まり」）

/// 置けるか（置けなければ、ぶつかったマス・理由）
struct CamperRoomCheck: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case outside, overlap, kitchen, doorway, blocksPath, window, tallFurniture, limit, wallBlocked
    }
    var reason: Reason?
    /// 赤で知らせるマス（床・天井）
    var blocked: Set<CamperRoomCell> = []
    var ok: Bool { reason == nil }

    static let fine = CamperRoomCheck()

    var message: String {
        switch reason {
        case nil: return L("置けます", "It fits")
        case .outside: return L("部屋からはみ出します", "It doesn\u{2019}t fit in the room")
        case .overlap: return L("ほかの家具とぶつかります", "It overlaps another piece")
        case .kitchen: return L("台所とぶつかります", "It runs into the kitchen")
        case .doorway: return L("扉の前は空けておきます", "Keep the doorway clear")
        case .blocksPath: return L("扉から奥へ通れなくなります", "It blocks the way through")
        case .window: return L("窓の上には掛けられません", "Not over a window")
        case .tallFurniture: return L("背の高い家具の真上です", "Right above something tall")
        case .limit: return L("この部屋に置ける数を超えます", "This room is full")
        case .wallBlocked: return L("床の家具が壁の段にかかっています", "Furniture below is in the way")
        }
    }
}

enum CamperRoomRules {

    /// `item` を `doc` に置けるか（同じ `u` の物は自分なので数えない）
    static func check(_ item: CamperRoomItem, in doc: CamperRoomDocument, layout: CamperRoomLayout) -> CamperRoomCheck {
        guard let f = item.furniture else { return CamperRoomCheck(reason: .outside) }
        let others = doc.all.filter { $0.u != item.u }
        if let limit = limitReason(f, others: others, layout: layout) { return CamperRoomCheck(reason: limit) }
        switch f.placement {
        case .floor: return checkFloor(item, f, others: others, layout: layout)
        case .wall: return checkWall(item, f, others: others, layout: layout)
        case .ceiling: return checkCeiling(item, others: others, layout: layout)
        }
    }

    private static func limitReason(_ f: CamperRoomFurniture, others: [CamperRoomItem], layout: CamperRoomLayout) -> CamperRoomCheck.Reason? {
        let same = others.filter { $0.furniture?.placement == f.placement }.count
        let limit: Int
        switch f.placement {
        case .floor: limit = layout.floorLimit
        case .wall: limit = layout.wallLimit
        case .ceiling: limit = layout.ceilingLimit
        }
        if same + 1 > limit { return .limit }
        if f.photoSlots > 0 {
            let photos = others.compactMap(\.furniture).reduce(0) { $0 + $1.photoSlots }
            if photos + f.photoSlots > layout.photoLimit { return .limit }
        }
        return nil
    }

    private static func inside(_ r: CamperRoomRect, _ layout: CamperRoomLayout) -> Bool {
        r.x >= 0 && r.z >= 0 && r.x + r.w <= layout.width && r.z + r.d <= layout.depth
    }

    private static func checkFloor(_ item: CamperRoomItem, _ f: CamperRoomFurniture, others: [CamperRoomItem],
                                   layout: CamperRoomLayout) -> CamperRoomCheck {
        guard let rect = item.rect else { return CamperRoomCheck(reason: .outside) }
        guard inside(rect, layout) else {
            return CamperRoomCheck(reason: .outside, blocked: Set(rect.cells.filter { !(0..<layout.width).contains($0.x) || !(0..<layout.depth).contains($0.z) }))
        }
        if rect.intersects(layout.kitchen) {
            return CamperRoomCheck(reason: .kitchen, blocked: Set(rect.cells.filter { layout.kitchen.contains($0.x, $0.z) }))
        }
        // 床は 2 層: 敷物どうし・家具どうしは重ならない（敷物は家具の下に敷ける）
        let sameLayer = others.filter { o in
            guard let of = o.furniture, of.placement == .floor else { return false }
            return of.isRug == f.isRug
        }
        let hit = sameLayer.compactMap(\.rect).filter { $0.intersects(rect) }
        if !hit.isEmpty {
            return CamperRoomCheck(reason: .overlap, blocked: Set(rect.cells.filter { c in hit.contains { $0.contains(c.x, c.z) } }))
        }
        guard !f.isRug else { return .fine }
        if rect.intersects(layout.doorClearance) {
            return CamperRoomCheck(reason: .doorway, blocked: Set(rect.cells.filter { layout.doorClearance.contains($0.x, $0.z) }))
        }
        // 壁の物の下に背の高い家具を寄せない（付箋: 床の家具の高さが段にかかる所には掛けられない。逆も同じ）
        for o in others {
            guard let span = o.wallSpan else { continue }
            if blocksWall(rect, height: f.height, span: span) {
                return CamperRoomCheck(reason: .wallBlocked, blocked: Set(rect.cells))
            }
        }
        // 天井の物の真下に背の高い家具を置かない
        if f.height > CamperRoomLayout.tallForCeiling {
            let above = others.filter { $0.furniture?.placement == .ceiling }.compactMap(\.rect).filter { $0.intersects(rect) }
            if !above.isEmpty { return CamperRoomCheck(reason: .tallFurniture, blocked: Set(rect.cells)) }
        }
        // 扉から奥（後ろの壁の列）まで、幅 1 マスの道が残る
        var solid = Set(others.filter { $0.furniture?.placement == .floor && $0.furniture?.isRug == false }.compactMap(\.rect).flatMap(\.cells))
        solid.formUnion(rect.cells)
        if !pathRemains(solid: solid, layout: layout) { return CamperRoomCheck(reason: .blocksPath, blocked: Set(rect.cells)) }
        return .fine
    }

    /// 床の家具が壁の段をふさぐか（壁に付いている面で、高さが段の下より上）
    static func blocksWall(_ rect: CamperRoomRect, height: Double,
                           span: (wall: CamperRoomWall, columns: Range<Int>, rows: Range<Int>)) -> Bool {
        let touches: Bool
        let columns: Range<Int>
        switch span.wall {
        case .back:
            touches = rect.z == 0
            columns = rect.x..<(rect.x + rect.w)
        case .left:
            touches = rect.x == 0
            columns = rect.z..<(rect.z + rect.d)
        }
        guard touches, columns.overlaps(span.columns) else { return false }
        return span.rows.contains { height > CamperRoomLayout.rowBottoms[$0] }
    }

    /// 扉の前から、後ろの壁の列（x = 0）まで通れるか（上下左右に 1 マスずつ）
    static func pathRemains(solid: Set<CamperRoomCell>, layout: CamperRoomLayout) -> Bool {
        func free(_ c: CamperRoomCell) -> Bool {
            (0..<layout.width).contains(c.x) && (0..<layout.depth).contains(c.z) && !solid.contains(c)
                && !layout.kitchen.contains(c.x, c.z)
        }
        var queue = layout.doorClearance.cells.filter(free)
        var seen = Set(queue)
        while let c = queue.popLast() {
            if c.x == 0 { return true }
            for n in [CamperRoomCell(x: c.x - 1, z: c.z), CamperRoomCell(x: c.x + 1, z: c.z),
                      CamperRoomCell(x: c.x, z: c.z - 1), CamperRoomCell(x: c.x, z: c.z + 1)] where free(n) && !seen.contains(n) {
                seen.insert(n)
                queue.append(n)
            }
        }
        return false
    }

    private static func checkWall(_ item: CamperRoomItem, _ f: CamperRoomFurniture, others: [CamperRoomItem],
                                  layout: CamperRoomLayout) -> CamperRoomCheck {
        guard let span = item.wallSpan else { return CamperRoomCheck(reason: .outside) }
        guard span.columns.lowerBound >= 0, span.columns.upperBound <= layout.columns(span.wall),
              span.rows.lowerBound >= 0, span.rows.upperBound <= CamperRoomLayout.rowBottoms.count else {
            return CamperRoomCheck(reason: .outside)
        }
        for o in others {
            guard let s = o.wallSpan, s.wall == span.wall else { continue }
            if s.columns.overlaps(span.columns), s.rows.overlaps(span.rows) { return CamperRoomCheck(reason: .overlap) }
        }
        for win in layout.windows where win.wall == span.wall {
            guard span.columns.overlaps(win.from..<(win.to + 1)) else { continue }
            let hits = span.rows.contains { row in
                let lo = CamperRoomLayout.rowBottoms[row], hi = lo + CamperRoomLayout.rowHeight
                return lo < win.top && hi > win.bottom
            }
            if hits { return CamperRoomCheck(reason: .window) }
        }
        // 台所（高さ 36）は奥の壁の腰の段をふさぐ
        if blocksWall(layout.kitchen, height: CamperRoomLayout.kitchenHeight, span: span) { return CamperRoomCheck(reason: .wallBlocked) }
        for o in others {
            guard let of = o.furniture, of.placement == .floor, !of.isRug, let r = o.rect else { continue }
            if blocksWall(r, height: of.height, span: span) { return CamperRoomCheck(reason: .wallBlocked) }
        }
        return .fine
    }

    private static func checkCeiling(_ item: CamperRoomItem, others: [CamperRoomItem], layout: CamperRoomLayout) -> CamperRoomCheck {
        guard let rect = item.rect else { return CamperRoomCheck(reason: .outside) }
        guard inside(rect, layout) else { return CamperRoomCheck(reason: .outside) }
        let hit = others.filter { $0.furniture?.placement == .ceiling }.compactMap(\.rect).filter { $0.intersects(rect) }
        if !hit.isEmpty {
            return CamperRoomCheck(reason: .overlap, blocked: Set(rect.cells.filter { c in hit.contains { $0.contains(c.x, c.z) } }))
        }
        let tall = others.filter { o in
            guard let of = o.furniture, of.placement == .floor else { return false }
            return of.height > CamperRoomLayout.tallForCeiling
        }.compactMap(\.rect).filter { $0.intersects(rect) }
        if !tall.isEmpty {
            return CamperRoomCheck(reason: .tallFurniture, blocked: Set(rect.cells.filter { c in tall.contains { $0.contains(c.x, c.z) } }))
        }
        return .fine
    }

    /// 新しく置く場所を探す（壁際から。床は回さない向きを先に）。置ける所が無ければ nil
    static func firstFit(_ f: CamperRoomFurniture, uid: String, in doc: CamperRoomDocument, layout: CamperRoomLayout) -> CamperRoomItem? {
        switch f.placement {
        case .floor, .ceiling:
            for r in [0, 1] {
                for z in 0..<layout.depth {
                    for x in 0..<layout.width {
                        let item = f.placement == .floor ? CamperRoomItem.floor(uid, f.id, x: x, z: z, r: r)
                            : CamperRoomItem.ceiling(uid, f.id, x: x, z: z, r: r)
                        if check(item, in: doc, layout: layout).ok { return item }
                    }
                }
            }
        case .wall:
            for wall in CamperRoomWall.allCases {
                for row in [1, 0, 2] {
                    for c in 0..<layout.columns(wall) {
                        let item = CamperRoomItem.wall(uid, f.id, wall, c: c, row: row)
                        if check(item, in: doc, layout: layout).ok { return item }
                    }
                }
            }
        }
        return nil
    }

    /// 初めて入ったときの部屋（最初から持っている家具を並べておく。板 CamperRoomMain の「家具 10 / 40」の様子）
    static func starterDocument(_ layout: CamperRoomLayout) -> CamperRoomDocument {
        var doc = CamperRoomDocument(room: layout.kind)
        let wanted: [CamperRoomItem]
        switch (layout.kind, layout.width) {
        case (.car, 18):
            wanted = [
                .floor("i1", "bed.platform", x: 0, z: 4),
                .floor("i2", "heater.wood_stove", x: 0, z: 0),
                .floor("i3", "seating.floor_cushion", x: 3, z: 1),
                .floor("i4", "room_rug.runner", x: 4, z: 3),
                .wall("i5", "photo_frame.landscape", .back, c: 7, row: 1),
                .wall("i6", "wall_lamp.glass_sconce", .back, c: 6, row: 1),
                .wall("i7", "clock.station", .left, c: 10, row: 1),
                .ceiling("i8", "string_ceiling.globe_string", x: 3, z: 4),
                .ceiling("i9", "plant_hanger.macrame", x: 9, z: 4),
            ]
        case (.car, _):
            wanted = [
                .floor("i1", "bed.platform", x: 0, z: 0, r: 1),
                .floor("i2", "table.dinette_post", x: 6, z: 0),
                .floor("i3", "seating.floor_cushion", x: 7, z: 3),
                .floor("i4", "heater.wood_stove", x: 10, z: 0),
                .floor("i5", "room_rug.runner", x: 6, z: 5),
                .floor("i6", "floor_lamp.brass_stem", x: 4, z: 0),
                .floor("i7", "storage.trunk", x: 13, z: 3),
                .wall("i8", "photo_frame.landscape", .back, c: 7, row: 1),
                .wall("i9", "photo_frame.square", .left, c: 1, row: 1),
                .wall("i10", "clock.station", .back, c: 13, row: 1),
                .wall("i11", "wall_lamp.glass_sconce", .left, c: 12, row: 1),
                .wall("i12", "wall_shelf.plank_brackets", .back, c: 14, row: 2),
                .ceiling("i13", "string_ceiling.globe_string", x: 5, z: 4),
                .ceiling("i14", "mobile.wooden_birds", x: 2, z: 6),
                .ceiling("i15", "plant_hanger.macrame", x: 12, z: 6),
                .ceiling("i16", "roof_hatch.square_vent", x: 7, z: 1),
            ]
        case (.trailer, _):
            wanted = [
                .floor("i1", "bed.platform", x: 0, z: 0),
                .floor("i2", "table.dinette_post", x: 9, z: 0),
                .floor("i3", "heater.wood_stove", x: 14, z: 0),
                .floor("i4", "room_rug.runner", x: 9, z: 5),
                .wall("i5", "photo_frame.landscape", .back, c: 10, row: 1),
                .wall("i6", "wall_lamp.glass_sconce", .left, c: 13, row: 1),
                .ceiling("i7", "string_ceiling.globe_string", x: 8, z: 4),
            ]
        }
        for item in wanted where check(item, in: doc, layout: layout).ok { doc.upsert(item) }
        return doc
    }
}
