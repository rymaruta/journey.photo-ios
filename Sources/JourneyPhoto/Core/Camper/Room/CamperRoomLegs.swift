import Foundation

// 脚のある家具の組み立ての見張り（2026-10-22）。owner の実機（TestFlight 1.1.37）「椅子とかは家具によって足が壊れてたりする。
// 一個ずつ丁寧に作らないとダメかもね」。
//
// 家具の網は部品（角を丸めた箱・管・旋盤）を足し合わせたもので、部品どうしは点を共有しない。だから同じ位置の点を
// つないで部品に分け、部品の外枠（軸にそろえた箱）どうしで組み立てを確かめる:
// - 床から浮いた部品が無い（床に着いた部品から、触れている部品をたどって全部に届く）
// - 脚（床に着いた細長い部品）の上端が、何か（座面・天板・框・貫）に届いている。届かず空中で終わる・突き抜けるのは壊れ
// - 脚が載せた物の外へはみ出さない・同じ物を支える脚の長さがそろう・脚が細すぎて消えない
//
// 2026-10-22 判断: 外枠で見るので、斜めの脚・曲がった管は大きめの箱になり甘く通る。見逃しは接写（一つずつ目で見る）で拾う。

enum CamperRoomLegs {

    /// 触れているとみなす距離（板の単位・1 = 2.5 cm。0.25 = 6 mm）
    static let touch = 0.25
    /// 脚の最小の太さ（0.5 = 1.25 cm。これより細いと画面で消える）
    static let thinnest = 0.5

    /// 接写の 4 方向（正面・斜め・横・下から。度）。`scenePitch` は Mac の本物の絵（図鑑の小部屋）の見下ろし。
    /// 小部屋には床があるので「下から」は狙いを床の近く（`low`）へ下げ、浅い角度（12°）で脚の付け根と足先を覗く。
    /// 手元の絵（`CamperRoomRaster`）は床が無く真下寄りから。
    /// 2026-10-22（Mac run 677）: 狙いを下げて 3° にすると、目が小部屋の床の板の縁より下になり灰色の板しか写らなかった
    static let views: [(name: String, yaw: Double, pitch: Double, scenePitch: Double, low: Bool)] = [
        ("正面", 0, 6, 8, false), ("斜め", 34, 26, 26, false), ("横", 90, 6, 8, false), ("下から", 28, -24, 12, true),
    ]

    /// 脚の接写の一覧に並べる家具（Mac の `testCapturesCamperFurnitureLegs`）。板と別種の脚のある床の家具全部と、
    /// 組み合わせの家具は「分類 × 脚の形」ごとに 1 つ（同じ脚の形は同じ作りなので、1 つ見れば残りも同じ）
    static var sheet: [CamperRoomFurniture] {
        let board = CamperRoomCatalog.board.filter { $0.placement == .floor && $0.category != .roomRug && hasLegs($0) }
        var groups: [String: [CamperRoomFurniture]] = [:]
        var order: [String] = []
        for p in CamperRoomVariety.pieces {
            guard let axis = legAxis(p) else { continue }
            let key = "\(p.furniture.category.rawValue)|\(axis)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(p.furniture)
        }
        // 同じ脚の形の真ん中の 1 つ（天板・背の違いも頁ごとに散らす）
        return board + order.compactMap { k in groups[k].map { $0[$0.count / 2] } }
    }

    /// 組み合わせの家具の「脚の形」の軸（脚の無い分類は nil）
    static func legAxis(_ p: CamperRoomVariety.Piece) -> Int? {
        switch p.furniture.category {
        case .seating, .bed: return p.axes.0
        case .table: return p.axes.1
        case .storage, .heater, .floorLamp: return p.axes.2
        default: return nil
        }
    }

    /// 部品（同じ位置の点でつながった三角形の塊）の外枠
    struct Part: Equatable {
        var lo: CV3
        var hi: CV3
        var triangles: Int
        /// 上端（いちばん高い点のまわり 0.3 の点の真ん中）。斜めの脚は外枠の真ん中ではなく、ここが上の物に届くかを見る
        var top: CV3 = .zero
        /// 上端の断面の広がり（いちばん高い点のまわり 0.3 の点の外枠の xz）
        var topLo: CV3 = .zero
        var topHi: CV3 = .zero

        var size: CV3 { hi - lo }
        var center: CV3 { (lo + hi) * 0.5 }
        /// 床に着いた細長い部品（脚・柱・板脚）
        var isLeg: Bool {
            let s = size, narrow = min(s.x, s.z)
            return lo.y <= CamperRoomLegs.touch && s.y >= 2 && narrow <= 5 && s.y >= narrow * 0.9
        }

        func touches(_ o: Part, slack: Double = CamperRoomLegs.touch) -> Bool {
            lo.x <= o.hi.x + slack && o.lo.x <= hi.x + slack &&
                lo.y <= o.hi.y + slack && o.lo.y <= hi.y + slack &&
                lo.z <= o.hi.z + slack && o.lo.z <= hi.z + slack
        }

        func contains(_ p: CV3, slack: Double) -> Bool {
            p.x >= lo.x - slack && p.x <= hi.x + slack && p.y >= lo.y - slack && p.y <= hi.y + slack &&
                p.z >= lo.z - slack && p.z <= hi.z + slack
        }
    }

    /// 網を部品に分ける（同じ位置の点をつなぐ）
    static func parts(_ m: CamperMesh) -> [Part] {
        // 2026-10-22（Mac run 676）: 床の家具 1000 点を 1 分の試験の枠で見られるよう、辞書と構造体を避けて配列で数える
        let n = m.positions.count
        guard n > 0 else { return [] }
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        // 同じ位置の点をつなぐ（位置を 0.001 で丸めて 1 つの整数に詰める）
        var first = [Int: Int](minimumCapacity: n)
        for i in 0..<n {
            let p = m.positions[i]
            let qx = Int((p.x * 1000).rounded()) & 0x1FFFFF, qy = Int((p.y * 1000).rounded()) & 0x1FFFFF
            let qz = Int((p.z * 1000).rounded()) & 0x1FFFFF
            let key = qx | (qy << 21) | (qz << 42)
            if let j = first[key] {
                let a = find(i), b = find(j)
                if a != b { parent[a] = b }
            } else {
                first[key] = i
            }
        }
        var used = [Bool](repeating: false, count: n)
        for g in m.groups {
            var i = 0
            let idx = g.indices
            while i + 2 < idx.count {
                let a = Int(idx[i]), b = Int(idx[i + 1]), c = Int(idx[i + 2])
                i += 3
                guard a < n, b < n, c < n else { continue }
                let ra = find(a), rb = find(b)
                if ra != rb { parent[ra] = rb }
                let rc = find(c), rb2 = find(b)
                if rc != rb2 { parent[rc] = rb2 }
                used[a] = true; used[b] = true; used[c] = true
            }
        }
        // 部品ごとの外枠
        var slot = [Int](repeating: -1, count: n)
        var lo: [CV3] = [], hi: [CV3] = [], tris: [Int] = []
        for i in 0..<n where used[i] {
            let r = find(i), p = m.positions[i]
            if slot[r] < 0 {
                slot[r] = lo.count
                lo.append(p); hi.append(p); tris.append(0)
            } else {
                let k = slot[r]
                if p.x < lo[k].x { lo[k].x = p.x }
                if p.y < lo[k].y { lo[k].y = p.y }
                if p.z < lo[k].z { lo[k].z = p.z }
                if p.x > hi[k].x { hi[k].x = p.x }
                if p.y > hi[k].y { hi[k].y = p.y }
                if p.z > hi[k].z { hi[k].z = p.z }
            }
        }
        for g in m.groups {
            var i = 0
            while i + 2 < g.indices.count {
                let a = Int(g.indices[i])
                i += 3
                if a < n, used[a] { tris[slot[find(a)]] += 1 }
            }
        }
        // 上端（いちばん高い点のまわり 0.3 の点の真ん中）
        var sum = [CV3](repeating: .zero, count: lo.count), cnt = [Double](repeating: 0, count: lo.count)
        var tlo = hi, thi = lo
        for i in 0..<n where used[i] {
            let k = slot[find(i)], p = m.positions[i]
            if p.y >= hi[k].y - 0.3 {
                sum[k] = sum[k] + p; cnt[k] += 1
                tlo[k] = CV3(min(tlo[k].x, p.x), 0, min(tlo[k].z, p.z))
                thi[k] = CV3(max(thi[k].x, p.x), 0, max(thi[k].z, p.z))
            }
        }
        var out: [Part] = []
        out.reserveCapacity(lo.count)
        for k in lo.indices {
            out.append(Part(lo: lo[k], hi: hi[k], triangles: tris[k], top: sum[k] * (1 / max(1, cnt[k])), topLo: tlo[k], topHi: thi[k]))
        }
        return out.sorted { ($0.lo.y, $0.lo.x, $0.lo.z) < ($1.lo.y, $1.lo.x, $1.lo.z) }
    }

    /// 床の家具で、脚（床に着いた細長い部品）を持つもの
    static func hasLegs(_ f: CamperRoomFurniture) -> Bool {
        guard f.placement == .floor, f.category != .roomRug, let m = CamperRoomFurnitureModels.rawMesh(f.id) else { return false }
        return !legs(parts(m)).isEmpty
    }

    /// 脚の番号（床に着いた細長い部品のうち、胴の横に沿って上る帯・縫い目・板を除く。
    /// 2026-10-22 判断: 旅のラジオの前の縫い目の輪が床すれすれまで下りていて「細すぎる脚」と読んだ。脚は胴の外で上端に何かを受ける物。旅の鞄の角金も同じ）
    static func legs(_ ps: [Part]) -> [Int] {
        ps.indices.filter { i in
            let leg = ps[i]
            guard leg.isLeg else { return false }
            let top = CV3(leg.top.x, leg.hi.y, leg.top.z)
            let above = ps.indices.filter { j in j != i && ps[j].contains(top, slack: touch) && ps[j].hi.y > leg.hi.y - touch }
            // 床から脚より高くまである胴の外枠の中にある物（旅の鞄の角金・胴の帯）は、胴の飾り
            let alongside = above.contains { ps[$0].lo.y <= leg.lo.y + touch && ps[$0].hi.y >= leg.hi.y }
            return !alongside
        }
    }

    /// 脚のある家具の組み立ての崩れ（無ければ空）
    static func problems(_ m: CamperMesh) -> [String] {
        let ps = parts(m)
        var out: [String] = []
        // 床から浮いた部品
        var reached = ps.map { $0.lo.y <= touch }
        var queue = ps.indices.filter { reached[$0] }
        var left = ps.indices.filter { !reached[$0] }
        while let i = queue.popLast(), !left.isEmpty {
            let a = ps[i]
            left.removeAll { j in
                let b = ps[j]
                guard a.lo.x <= b.hi.x + touch, b.lo.x <= a.hi.x + touch, a.lo.y <= b.hi.y + touch, b.lo.y <= a.hi.y + touch,
                      a.lo.z <= b.hi.z + touch, b.lo.z <= a.hi.z + touch else { return false }
                reached[j] = true
                queue.append(j)
                return true
            }
        }
        let floating = ps.indices.filter { !reached[$0] }
        if !floating.isEmpty {
            let low = floating.map { ps[$0].lo.y }.min() ?? 0
            out.append("浮いた部品 \(floating.count)（いちばん下 y \(fmt(low))）")
        }
        // 脚ごと
        var carried: [Int: [Int]] = [:]
        for i in legs(ps) {
            let leg = ps[i]
            let s = leg.size
            if min(s.x, s.z) < thinnest { out.append("細すぎる脚 \(fmt(min(s.x, s.z)))（\(where_(leg))）") }
            let top = CV3(leg.top.x, leg.hi.y, leg.top.z)
            // 上端が届く物（脚より上へ伸びる物・脚の上端を外枠に含む）
            let above = ps.indices.filter { j in
                j != i && ps[j].contains(top, slack: touch) && ps[j].hi.y > leg.hi.y - touch
            }
            if above.isEmpty {
                // すき間か、突き抜けか
                let column = ps.indices.filter { j in
                    j != i && top.x >= ps[j].lo.x - touch && top.x <= ps[j].hi.x + touch &&
                        top.z >= ps[j].lo.z - touch && top.z <= ps[j].hi.z + touch
                }
                if let j = column.filter({ ps[$0].lo.y > leg.hi.y }).min(by: { ps[$0].lo.y < ps[$1].lo.y }) {
                    out.append("脚の上にすき間 \(fmt(ps[j].lo.y - leg.hi.y))（\(where_(leg))）")
                } else if column.contains(where: { ps[$0].hi.y < leg.hi.y - touch && ps[$0].hi.y > leg.lo.y + 1 }) {
                    out.append("脚が突き抜けて上に出る（\(where_(leg))）")
                } else {
                    out.append("脚の上に何も無い（\(where_(leg))）")
                }
                continue
            }
            // 脚の上端が、それを受ける部品（下面が上端のすぐ上 1.5 以内にあり、上端を外枠に含む物＝座・天板・框・受け木）の
            // 外へはみ出さない。外へ開く脚の足先は見ない（灯りの三本足・ウィンザーの開き脚）。
            // 2026-10-22（確かめ役）: 前は上にある部品全部の外枠と比べていて、背・笠など脚と関係ない物で甘くなっていた
            let hosts = above.filter { ps[$0].lo.y >= leg.hi.y - 1.5 }
            if !hosts.isEmpty {
                let minX = hosts.map { ps[$0].lo.x }.min()!, maxX = hosts.map { ps[$0].hi.x }.max()!
                let minZ = hosts.map { ps[$0].lo.z }.min()!, maxZ = hosts.map { ps[$0].hi.z }.max()!
                let out_ = max(0, minX - leg.topLo.x, leg.topHi.x - maxX, minZ - leg.topLo.z, leg.topHi.z - maxZ)
                if out_ > 0.6 { out.append("脚が座・天板の外へ \(fmt(out_))（\(where_(leg))）") }
            }
            // 長さをそろえるのは、上端で下面を受ける物ごと（胴の横を上る帯・框に差し込んだ柱は比べない）
            for j in hosts { carried[j, default: []].append(i) }
        }
        var uneven = Set<String>()
        for (_, legs) in carried where legs.count >= 2 {
            let tops = legs.map { ps[$0].hi.y }
            if let a = tops.min(), let b = tops.max(), b - a > 0.6 {
                uneven.insert("同じ物を支える脚の長さが違う \(fmt(a))〜\(fmt(b))")
            }
        }
        out += uneven.sorted()
        return out
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func where_(_ p: Part) -> String { "x \(fmt(p.center.x)) z \(fmt(p.center.z)) 高さ \(fmt(p.size.y))" }
}
