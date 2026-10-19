import Foundation

// 家具を置く・動かす・回す・しまう・元に戻す（2026-10-19・板 CamperRoomMain の「置く」と付箋「指の操作と動き」）。
// 置けない動きは決めない（ぶつかったまま指を離すと元の場所へ戻る）。「元に戻す」は 1 手ずつ。素の Swift なので試験できる。

struct CamperRoomEditor: Equatable, Sendable {
    private(set) var doc: CamperRoomDocument
    let layout: CamperRoomLayout
    /// 元に戻すための前の文書（新しいものが後ろ・30 手まで）
    private(set) var history: [CamperRoomDocument] = []
    static let historyLimit = 30

    init(doc: CamperRoomDocument, layout: CamperRoomLayout) {
        self.doc = doc
        self.layout = layout
    }

    var canUndo: Bool { !history.isEmpty }

    private mutating func commit(_ next: CamperRoomDocument) {
        guard next != doc else { return }
        history.append(doc)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        doc = next
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let prev = history.popLast() else { return false }
        doc = prev
        return true
    }

    // MARK: 持ち物（下の棚）

    /// 棚に出す家具（持っていて、まだ置いていないもの。額とポスターは写真の上限まで何枚でも）
    func tray(_ placement: CamperRoomPlacement, owned: Set<String>) -> [CamperRoomFurniture] {
        let placed = Set(doc.all.map(\.k))
        return CamperRoomCatalog.items(placement).filter { f in
            owned.contains(f.id) && (f.reusable || !placed.contains(f.id))
        }
    }

    /// 置いた数（床・壁・天井・写真）
    var counts: (floor: Int, wall: Int, ceiling: Int, photos: Int) {
        let fs = doc.all.compactMap(\.furniture)
        return (fs.filter { $0.placement == .floor }.count, fs.filter { $0.placement == .wall }.count,
                fs.filter { $0.placement == .ceiling }.count, fs.reduce(0) { $0 + $1.photoSlots })
    }

    // MARK: 置く・動かす・回す・しまう

    /// 棚から部屋へ（置ける所を壁際から探す）。置いた物の名前、置けなければ nil
    @discardableResult
    mutating func place(_ f: CamperRoomFurniture, owned: Set<String>) -> String? {
        guard owned.contains(f.id), tray(f.placement, owned: owned).contains(f) else { return nil }
        let uid = doc.nextUid()
        guard let item = CamperRoomRules.firstFit(f, uid: uid, in: doc, layout: layout) else { return nil }
        var next = doc
        next.upsert(item)
        commit(next)
        return uid
    }

    /// 置いてみる（動かしている間の白・赤。文書は変えない）
    func preview(_ item: CamperRoomItem) -> CamperRoomCheck { CamperRoomRules.check(item, in: doc, layout: layout) }

    /// 動かした先に置く（置けなければ何もしない＝元の場所に戻る）
    @discardableResult
    mutating func move(_ item: CamperRoomItem) -> CamperRoomCheck {
        guard doc.item(item.u) != nil else { return CamperRoomCheck(reason: .outside) }
        let check = preview(item)
        guard check.ok else { return check }
        var next = doc
        next.upsert(item)
        commit(next)
        return check
    }

    /// 90° 回す（床と天井の物）。その場で回せなければ、近くの置ける所へずらす。どこにも無ければ回さない
    @discardableResult
    mutating func rotate(_ u: String) -> Bool {
        guard let item = doc.item(u), item.furniture?.placement != .wall, let x = item.x, let z = item.z else { return false }
        var turned = item
        turned.r = (item.turns + 1) % 4
        let offsets = [(0, 0), (-1, 0), (0, -1), (-1, -1), (1, 0), (0, 1), (-2, 0), (0, -2), (-2, -1), (-1, -2), (-2, -2)]
        for (dx, dz) in offsets {
            var candidate = turned
            candidate.x = x + dx
            candidate.z = z + dz
            if preview(candidate).ok {
                var next = doc
                next.upsert(candidate)
                commit(next)
                return true
            }
        }
        return false
    }

    /// しまう（持ち物に戻る。何度でも出せる）
    mutating func stow(_ u: String) {
        guard doc.item(u) != nil else { return }
        var next = doc
        next.remove(u)
        commit(next)
    }

    /// 額に写真を入れる（投稿の写真の id）
    mutating func setPhoto(_ u: String, photoId: String?) {
        guard var item = doc.item(u), (item.furniture?.photoSlots ?? 0) > 0 else { return }
        item.p = photoId
        var next = doc
        next.upsert(item)
        commit(next)
    }

    mutating func setStyle(_ style: CamperRoomStyle) {
        var next = doc
        next.style = style
        commit(next)
    }

    /// 持っていない家具を部屋から外して見せる（写真を読み直す前・数が減ったとき）。**保存する文書は変えない**
    func shown(owned: Set<String>) -> CamperRoomDocument {
        var out = doc
        out.items.removeAll { !owned.contains($0.k) }
        out.ceil.removeAll { !owned.contains($0.k) }
        return out
    }
}

// MARK: - 保存（人ごとにこの端末へ・退会で消す）

/// 部屋の配置を人ごとにこの端末へ覚える（2026-10-19 判断: 第1段は端末だけ。外まわりの `CamperStore` と同じ人ごとの鍵）。
/// 板は Application Support の文書を推すが、外まわりの飾りと同じ `UserDefaults` にそろえた（1 部屋 5 KB 未満）
struct CamperRoomStore {

    static func key(_ userId: String, _ room: CamperRoomKind) -> String { "camper.room.\(userId).\(room.rawValue)" }

    private let defaults: UserDefaults
    let userId: String?

    init(userId: String?, defaults: UserDefaults = .standard) {
        self.userId = userId
        self.defaults = defaults
    }

    /// 覚えている部屋。無ければ最初の並び（`starterDocument`）
    func load(_ layout: CamperRoomLayout) -> CamperRoomDocument {
        guard let userId, let data = defaults.data(forKey: Self.key(userId, layout.kind)),
              let doc = try? JSONDecoder().decode(CamperRoomDocument.self, from: data), doc.v == 1 else {
            return CamperRoomRules.starterDocument(layout)
        }
        return doc
    }

    /// 覚える（rev を 1 つ上げ、時刻を入れる）
    @discardableResult
    func save(_ doc: CamperRoomDocument, now: Date = Date()) -> CamperRoomDocument {
        var out = doc
        out.rev += 1
        out.updatedAt = ISO8601DateFormatter().string(from: now)
        guard let userId, let data = try? JSONEncoder().encode(out) else { return out }
        defaults.set(data, forKey: Self.key(userId, out.room))
        return out
    }

    static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        for room in CamperRoomKind.allCases { defaults.removeObject(forKey: key(userId, room)) }
    }
}
