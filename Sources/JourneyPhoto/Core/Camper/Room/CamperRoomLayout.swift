import Foundation

// とおまわり号の中の部屋の広さ・動かせない物・置く決まり（2026-10-19・板「CamperRoom」と付箋「マス目と寸法」「置く決まり」）。
//
// 1 マス = 10 ≈ 25 cm。天井は 88。床のマスは、その部屋の外の箱を 10 で割った数（`CamperVolumes`）。
// 車の部屋は殻と同じ（バン 12×8、キャンピングカー 18×9）。あつ森の家は 6 部屋なので、どの段も 7 部屋。
// 部屋の座標は左奥が原点: x は後ろ（0）から運転席の仕切りへ、z は奥の壁（0）から扉の壁へ、y は床から上。
// 素の Swift なので Linux でも試験できる。

/// 部屋。車の部屋とトレーラーは殻が外の箱。ほかは外に足した箱
enum CamperRoomKind: String, CaseIterable, Codable, Sendable {
    case car
    case sideRear
    case sideFront
    case porch
    case locker
    case loft
    case bunk
    case trailer

    var name: String {
        switch self {
        case .car: return L("車の部屋", "Camper room")
        case .sideRear: return L("後ろの張り出し", "Rear slide-out")
        case .sideFront: return L("前の張り出し", "Front slide-out")
        case .porch: return L("軒先", "Porch")
        case .locker: return L("荷物室", "Locker")
        case .loft: return L("ロフト", "Loft")
        case .bunk: return L("運転席の上", "Over the cab")
        case .trailer: return L("トレーラー", "Trailer")
        }
    }

    /// その段で入れる部屋。どの段も 7（あつ森の家の 6 より多い）。
    /// 荷物室はトレーラーの胴と重なるので、トレーラーつきではトレーラーの部屋に入れ替える
    static func rooms(_ stage: CamperStage) -> [CamperRoomKind] {
        var list: [CamperRoomKind] = [.car, .sideRear, .sideFront, .porch]
        if stage == .trailer {
            list += [.loft, .bunk, .trailer]
        } else {
            list += [.locker, .loft, .bunk]
        }
        return list
    }
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
    /// 天井の高さ（板の単位）。地面の部屋は 88。屋根の上の部屋は外の箱と同じ
    var ceilingHeight = Self.ceiling
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

    /// 床のマスは外の箱÷10。車の部屋は殻（バン 12×8・ほか 18×9）、トレーラーは殻の内側 11×7。
    /// 張り出しの扉は運転席側の端（寝台 8 マスが扉の前と左右で重ならないようにする）。台所は車の部屋だけ。
    static func make(_ kind: CamperRoomKind, stage: CamperStage) -> CamperRoomLayout {
        switch kind {
        case .car:
            if stage == .van {
                return CamperRoomLayout(kind: .car, width: 12, depth: 8, door: 9...11, kitchen: CamperRoomRect(x: 6, z: 0, w: 6, d: 3),
                                        windows: [CamperRoomWindow(wall: .back, from: 2, to: 5), CamperRoomWindow(wall: .left, from: 3, to: 4)],
                                        floorLimit: 20, wallLimit: 12, ceilingLimit: 6, photoLimit: 6)
            }
            return CamperRoomLayout(kind: .car, width: 18, depth: 9, door: 15...17, kitchen: CamperRoomRect(x: 12, z: 0, w: 6, d: 3),
                                    windows: [CamperRoomWindow(wall: .back, from: 3, to: 6), CamperRoomWindow(wall: .left, from: 3, to: 5)],
                                    floorLimit: 40, wallLimit: 24, ceilingLimit: 12, photoLimit: 12)
        case .trailer:
            return wing(.trailer, width: Int(CamperVolumes.trailerLength / CamperVolumes.cell),
                        depth: Int(CamperVolumes.trailerWidth / CamperVolumes.cell))
        case .sideRear, .sideFront, .porch, .locker, .loft, .bunk:
            let box = CamperVolumes.boxes(stage == .trailer && kind == .locker ? .camper : stage)[kind]
                ?? CamperVolumes.boxes(.camper)[kind]
            let width = Int(((box?.length ?? CamperVolumes.cell) / CamperVolumes.cell).rounded())
            let depth = Int(((box?.width ?? CamperVolumes.cell) / CamperVolumes.cell).rounded())
            return wing(kind, width: width, depth: depth, height: box?.height ?? CamperVolumes.groundHeight)
        }
    }

    /// 張り出し（台所なし・扉は端・窓は奥の壁に 1 つ）。上限はマスの数で、1 つ置く前には止まらない。
    /// 天井は外の箱の高さ。低い部屋の窓は天井の下に収める
    private static func wing(_ kind: CamperRoomKind, width: Int, depth: Int, height: Double = CamperRoomLayout.ceiling) -> CamperRoomLayout {
        let doorStart = max(0, width - 3)
        let windowTo = min(4, max(1, width - 4))
        var window = CamperRoomWindow(wall: .back, from: 1, to: windowTo)
        if height < Self.ceiling {
            window.bottom = 16
            window.top = height - 8
        }
        var layout = CamperRoomLayout(kind: kind, width: width, depth: depth, door: doorStart...(doorStart + 2),
                                      kitchen: CamperRoomRect(x: 0, z: 0, w: 0, d: 0),
                                      windows: width >= 6 ? [window] : [],
                                      floorLimit: width * depth, wallLimit: (width + depth) * 4,
                                      ceilingLimit: width * depth, photoLimit: width * depth)
        layout.ceilingHeight = height
        return layout
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
        case outside, overlap, kitchen, doorway, blocksPath, window, tallFurniture, limit, wallBlocked, tooTall
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
        case .tooTall: return L("天井より高いです", "Taller than the ceiling")
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
        if !f.isRug, f.height > layout.ceilingHeight {
            return CamperRoomCheck(reason: .tooTall)
        }
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
        func blocked(_ x: Int, _ z: Int) -> Bool {
            solid.contains(CamperRoomCell(x: x, z: z)) || layout.kitchen.contains(x, z)
        }
        // 扉の前の列が、そのまま x = 0 まで空いていれば通れる（広い部屋で毎回全体を探さない）
        let mouth = layout.doorClearance
        for z in mouth.z..<(mouth.z + mouth.d) {
            var clear = true
            for x in 0...layout.door.lowerBound where blocked(x, z) {
                clear = false
                break
            }
            if clear { return true }
        }
        let w = layout.width, d = layout.depth
        var grid = [UInt8](repeating: 0, count: w * d)
        for c in solid where (0..<w).contains(c.x) && (0..<d).contains(c.z) { grid[c.x * d + c.z] = 1 }
        let k = layout.kitchen
        for x in k.x..<(k.x + k.w) where (0..<w).contains(x) {
            for z in k.z..<(k.z + k.d) where (0..<d).contains(z) { grid[x * d + z] = 1 }
        }
        var queue: [Int] = []
        var seen = [UInt8](repeating: 0, count: w * d)
        for c in mouth.cells where (0..<w).contains(c.x) && (0..<d).contains(c.z) && grid[c.x * d + c.z] == 0 {
            let i = c.x * d + c.z
            if seen[i] == 0 { seen[i] = 1; queue.append(i) }
        }
        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            let x = i / d, z = i % d
            if x == 0 { return true }
            for (nx, nz) in [(x - 1, z), (x + 1, z), (x, z - 1), (x, z + 1)] {
                guard nx >= 0, nz >= 0, nx < w, nz < d else { continue }
                let n = nx * d + nz
                if grid[n] == 0, seen[n] == 0 {
                    seen[n] = 1
                    queue.append(n)
                }
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
        let aboveCeiling = span.rows.contains { CamperRoomLayout.rowBottoms[$0] + CamperRoomLayout.rowHeight > layout.ceilingHeight }
        if aboveCeiling { return CamperRoomCheck(reason: .tooTall) }
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
        if let f = item.furniture, f.height > layout.ceilingHeight { return CamperRoomCheck(reason: .tooTall) }
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

    /// 新しく置く場所を探す（壁際から。床は回さない向きを先に）。置ける所が無ければ nil。
    /// 広い部屋でも、埋まっているマスは飛ばしてから決まりを確かめる
    static func firstFit(_ f: CamperRoomFurniture, uid: String, in doc: CamperRoomDocument, layout: CamperRoomLayout) -> CamperRoomItem? {
        switch f.placement {
        case .floor, .ceiling:
            let depth = layout.depth
            var blocked = [Bool](repeating: false, count: layout.width * depth)
            func mark(_ rect: CamperRoomRect) {
                let x0 = max(0, rect.x), x1 = min(layout.width, rect.x + rect.w)
                let z0 = max(0, rect.z), z1 = min(depth, rect.z + rect.d)
                for x in x0..<x1 {
                    let row = x * depth
                    for z in z0..<z1 { blocked[row + z] = true }
                }
            }
            if f.placement == .floor {
                mark(layout.kitchen)
                if !f.isRug { mark(layout.doorClearance) }
                for o in doc.items {
                    guard let of = o.furniture, of.placement == .floor, of.isRug == f.isRug, let rect = o.rect else { continue }
                    mark(rect)
                }
                // 背の高い家具は、すでに吊ってある天井の物の真下を最初から飛ばす
                if f.height > CamperRoomLayout.tallForCeiling {
                    for o in doc.ceil { if let rect = o.rect { mark(rect) } }
                }
            } else {
                for o in doc.ceil { if let rect = o.rect { mark(rect) } }
                for o in doc.items {
                    guard let of = o.furniture, of.placement == .floor, of.height > CamperRoomLayout.tallForCeiling,
                          let rect = o.rect else { continue }
                    mark(rect)
                }
            }
            func occupied(_ x: Int, _ z: Int, _ w: Int, _ d: Int) -> Bool {
                for cx in x..<(x + w) {
                    let row = cx * depth
                    for cz in z..<(z + d) where blocked[row + cz] { return true }
                }
                return false
            }
            for r in [0, 1] {
                let w = r % 2 == 1 ? f.depth : f.width
                let d = r % 2 == 1 ? f.width : f.depth
                if w > layout.width || d > depth { continue }
                for z in 0...(depth - d) {
                    for x in 0...(layout.width - w) {
                        if blocked[x * depth + z] { continue }
                        if occupied(x, z, w, d) { continue }
                        let item = f.placement == .floor ? CamperRoomItem.floor(uid, f.id, x: x, z: z, r: r)
                            : CamperRoomItem.ceiling(uid, f.id, x: x, z: z, r: r)
                        if check(item, in: doc, layout: layout).ok { return item }
                    }
                }
            }
        case .wall:
            let spans = doc.all.compactMap(\.wallSpan)
            var rowBlocked: [CamperRoomWall: [[Bool]]] = [:]
            for wall in CamperRoomWall.allCases {
                rowBlocked[wall] = Array(repeating: Array(repeating: false, count: layout.columns(wall)), count: 3)
            }
            func cover(_ wall: CamperRoomWall, _ rect: CamperRoomRect, _ height: Double) {
                let touches: Bool
                let columns: Range<Int>
                switch wall {
                case .back:
                    touches = rect.z == 0
                    columns = rect.x..<(rect.x + rect.w)
                case .left:
                    touches = rect.x == 0
                    columns = rect.z..<(rect.z + rect.d)
                }
                guard touches else { return }
                for row in 0..<3 where height > CamperRoomLayout.rowBottoms[row] {
                    for c in columns where rowBlocked[wall]![row].indices.contains(c) {
                        rowBlocked[wall]![row][c] = true
                    }
                }
            }
            cover(.back, layout.kitchen, CamperRoomLayout.kitchenHeight)
            for o in doc.items {
                guard let of = o.furniture, of.placement == .floor, !of.isRug, let rect = o.rect else { continue }
                cover(.back, rect, of.height)
                cover(.left, rect, of.height)
            }
            for wall in CamperRoomWall.allCases {
                let columns = layout.columns(wall)
                for row in [1, 0, 2] {
                    let rows = row..<(row + f.depth)
                    if rows.upperBound > CamperRoomLayout.rowBottoms.count { continue }
                    var c = 0
                    while c + f.width <= columns {
                        let cols = c..<(c + f.width)
                        let floorHit = rows.contains { r in cols.contains { rowBlocked[wall]![r][$0] } }
                        let busy = spans.contains { $0.wall == wall && $0.columns.overlaps(cols) && $0.rows.overlaps(rows) }
                        let window = layout.windows.contains { win in
                            guard win.wall == wall, cols.overlaps(win.from..<(win.to + 1)) else { return false }
                            return rows.contains { r in
                                let lo = CamperRoomLayout.rowBottoms[r], hi = lo + CamperRoomLayout.rowHeight
                                return lo < win.top && hi > win.bottom
                            }
                        }
                        if !busy, !window, !floorHit {
                            let item = CamperRoomItem.wall(uid, f.id, wall, c: c, row: row)
                            if check(item, in: doc, layout: layout).ok { return item }
                        }
                        c += 1
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
        switch layout.kind {
        case .car where layout.width <= 12:
            wanted = [
                .floor("i1", "bed.platform", x: 0, z: 4),
                .floor("i2", "heater.wood_stove", x: 0, z: 0),
                .floor("i3", "seating.floor_cushion", x: 3, z: 1),
                .floor("i4", "room_rug.runner", x: 4, z: 3),
                .wall("i5", "photo_frame.landscape", .back, c: 7, row: 1),
                .wall("i6", "wall_lamp.glass_sconce", .back, c: 6, row: 1),
                .wall("i7", "clock.station", .left, c: 6, row: 1),
                .ceiling("i8", "string_ceiling.globe_string", x: 3, z: 4),
                .ceiling("i9", "plant_hanger.macrame", x: 9, z: 4),
            ]
        case .car:
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
                .wall("i11", "wall_lamp.glass_sconce", .left, c: 6, row: 1),
                .wall("i12", "wall_shelf.plank_brackets", .back, c: 14, row: 2),
                .ceiling("i13", "string_ceiling.globe_string", x: 5, z: 4),
                .ceiling("i14", "mobile.wooden_birds", x: 2, z: 6),
                .ceiling("i15", "plant_hanger.macrame", x: 12, z: 6),
                .ceiling("i16", "roof_hatch.square_vent", x: 7, z: 1),
            ]
        case .trailer:
            wanted = [
                .floor("i1", "bed.platform", x: 0, z: 0),
                .floor("i2", "room_rug.runner", x: 0, z: 5),
                .wall("i3", "photo_frame.landscape", .back, c: 9, row: 1),
                .ceiling("i4", "mobile.wooden_birds", x: 8, z: 1),
            ]
        case .sideRear, .sideFront, .porch, .locker, .loft, .bunk:
            wanted = []
        }
        for item in wanted where check(item, in: doc, layout: layout).ok { doc.upsert(item) }
        return doc
    }
}
