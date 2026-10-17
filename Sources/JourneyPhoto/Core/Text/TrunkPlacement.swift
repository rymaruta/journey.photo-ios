import Foundation

// 自分の手で貼る（モック Stick.dc.html・2026-10-17 次の版）の置き場の計算。
//
// 置き場はトランクの**正面（胴 360×268）の 0〜1** で、ラベルの真ん中（サーバーの `pos`）。傾きは -30〜30 度。
// 置き場を持たないラベル（前の版で貼ったもの・手持ちの「貼る」）は、今までどおりおまかせの置き場
// （`TrunkSlots`）に並べる。SwiftUI を読まない層（Linux でテストできるように）。

enum TrunkPlacement {

    static var bodyWidth: Double { TrunkLooks.bodyWidth }
    static var bodyHeight: Double { TrunkLooks.bodyHeight }

    /// 回すボタン1回の角度（モックの `rotL`・`rotR` の 8°）
    static let rotateStep: Double = 8
    /// 運んでいる間の傾き（モックの `rot: -6`）。離した所にこの傾きで貼る
    static let carryRotation: Double = -6
    /// 持ち上げたラベルを指の少し上に出す（モックの `- 18`）
    static let liftOffset: Double = 18
    /// 自分の手で貼ったラベルを描く枠（形の比で収める・モックの見本 104×70 前後）
    static let labelBox: (w: Double, h: Double) = (104, 74)
    /// 一度に描く、置き場つきのラベルの数（新しい順・重さの歯止め。2026-10-17 判断）
    static let maxPlaced = 60

    // MARK: 置き場と点

    /// 範囲に収め、サーバーの細かさ（x・y は小数3桁・rot は小数1桁）に丸める
    static func clamp(_ p: TrunkPos) -> TrunkPos {
        func round(_ v: Double, _ k: Double) -> Double { (v * k).rounded() / k }
        let x = p.x.isFinite ? min(1, max(0, p.x)) : 0.5
        let y = p.y.isFinite ? min(1, max(0, p.y)) : 0.5
        let rot = p.rot.isFinite ? min(TrunkPos.rotMax, max(-TrunkPos.rotMax, p.rot)) : 0
        return TrunkPos(x: round(x, 1000), y: round(y, 1000), rot: round(rot, 10))
    }

    /// 胴の上の点（pt）から置き場
    static func pos(x: Double, y: Double, rot: Double) -> TrunkPos {
        clamp(TrunkPos(x: x / bodyWidth, y: y / bodyHeight, rot: rot))
    }

    /// 置き場から胴の上の点（pt）
    static func point(_ p: TrunkPos) -> (x: Double, y: Double) {
        (p.x * bodyWidth, p.y * bodyHeight)
    }

    /// 傾けた置き場（範囲で止める）
    static func rotated(_ p: TrunkPos, by delta: Double) -> TrunkPos {
        clamp(TrunkPos(x: p.x, y: p.y, rot: p.rot + delta))
    }

    /// 動かした置き場（範囲で止める）
    static func moved(_ p: TrunkPos, toX x: Double, y: Double) -> TrunkPos {
        pos(x: x, y: y, rot: p.rot)
    }

    /// 自分の手で貼ったラベルの大きさ（形の縦横の比を保つ）
    static func size(_ label: TrunkLabel) -> (w: Double, h: Double) {
        TrunkLabelDesign.spec(for: label).shape.fitted(maxWidth: labelBox.w, maxHeight: labelBox.h)
    }

    /// 離して貼れるか（胴の縁から左右 10・上 8・下 10 の内側。モックの `over` を胴の座標に）
    static func canDrop(x: Double, y: Double) -> Bool {
        x > 10 && x < bodyWidth - 10 && y > 8 && y < bodyHeight - 10
    }

    // MARK: 並べる

    /// 貼ったラベル（**新しい順**）を描く並び（古いものが下）。
    ///
    /// - 置き場つき: その置き場に（新しい `maxPlaced` 枚まで）
    /// - 置き場なし: おまかせの置き場（`TrunkSlots`）。**描くのは前の版と同じ「置き場を持たない新しい 11 枚」**。
    ///   どの置き場かは、窓のいちばん古い1枚からの番号で決め、**その間にある置き場つきのラベルも数に入れる**
    ///   （2026-10-17 の見直し 2回目）。こうすると
    ///   - 置き場のないトランクは前の版と同じ並び
    ///   - 1枚に置き場を与えても、ほかの番号は変わらない（跳ばない）
    ///   - 手で貼った新しいラベルは窓の席を取らない（前の版のラベルが胴から消えない）
    ///   番号が 11 か所を越えたとき（置き場つきが間に多く挟まった）は、空いている置き場を `order` の順に使う
    /// - `overrides`: 画面の上だけで動かしている置き場（離した直後・回している最中。サーバーの応答を待たずに出す）
    static func layout(_ stuckNewestFirst: [TrunkLabel], stage st: Double,
                       overrides: [String: TrunkPos] = [:]) -> [TrunkSlots.Placed] {
        var drawn: [(index: Int, x: Double, y: Double, w: Double, h: Double, rot: Double, label: TrunkLabel)] = []
        let loose = stuckNewestFirst.indices.filter { overrides[stuckNewestFirst[$0].id] == nil && stuckNewestFirst[$0].pos == nil }
        let window = Array(loose.prefix(TrunkSlots.capacity))
        if let start = window.last {
            // 窓のいちばん古い1枚より前（古い）にある置き場つきのラベルの数
            let olderPlaced = stuckNewestFirst.indices.filter { $0 > start && !loose.contains($0) }.count
            var used = Set<Int>()
            var overflow: [Int] = []
            var slotOf: [Int: Int] = [:]
            for i in window {
                let k = (start - i) + olderPlaced
                if k < TrunkSlots.capacity {
                    slotOf[i] = TrunkSlots.order[k]
                    used.insert(TrunkSlots.order[k])
                } else {
                    overflow.append(i)
                }
            }
            // 番号のはみ出た分は、空いている置き場へ古いものから
            var free = TrunkSlots.order.filter { !used.contains($0) }.makeIterator()
            for i in overflow.reversed() { slotOf[i] = free.next() }
            for i in window {
                guard let index = slotOf[i] else { continue }
                let slot = TrunkSlots.slots[index]
                drawn.append((i, slot.x, slot.y, slot.w, slot.h, slot.rot, stuckNewestFirst[i]))
            }
        }
        var placedCount = 0
        for (i, label) in stuckNewestFirst.enumerated() {
            guard let pos = overrides[label.id] ?? label.pos, placedCount < maxPlaced else { continue }
            placedCount += 1
            let s = size(label)
            let c = point(pos)
            drawn.append((i, c.x - s.w / 2, c.y - s.h / 2, s.w, s.h, pos.rot, label))
        }
        // 古いもの（番号の大きいもの）が下
        drawn.sort { $0.index > $1.index }
        let n = drawn.count
        return drawn.enumerated().map { k, d in
            TrunkSlots.Placed(label: d.label, x: d.x, y: d.y, w: d.w, h: d.h, rot: d.rot,
                              age: TrunkAging.labelAge(index: k, count: n, stage: st))
        }
    }

    /// 指の点に当たる、いちばん上のラベル（無ければ nil）。傾きを戻した枠で当てる
    static func hit(_ placed: [TrunkSlots.Placed], x: Double, y: Double) -> TrunkLabel? {
        for p in placed.reversed() {
            let cx = p.x + p.w / 2, cy = p.y + p.h / 2
            let rad = -p.rot * .pi / 180
            let dx = x - cx, dy = y - cy
            let lx = dx * cos(rad) - dy * sin(rad), ly = dx * sin(rad) + dy * cos(rad)
            if abs(lx) <= p.w / 2 + 4 && abs(ly) <= p.h / 2 + 4 { return p.label }
        }
        return nil
    }

    /// おまかせで並べる: **空いているおまかせの置き場に、手持ちの新しいものから**貼る置き場を決める
    /// （置き場は `TrunkSlots` の位置と傾き）。空きが無ければ空。
    ///
    /// 2026-10-17 判断: モックは手持ちを全部並べるが、上限 150 枚の手持ちを一度に貼ると胴が埋まって
    /// 下のラベルが見えなくなる。おまかせの 11 か所のうち空いている所だけを埋める
    static func autoArrange(pocket: [TrunkLabel], stuck: [TrunkLabel]) -> [(id: String, pos: TrunkPos)] {
        let placed = layout(stuck, stage: 0)
        var free: [TrunkSlots.Slot] = []
        for index in TrunkSlots.order {
            let slot = TrunkSlots.slots[index]
            let taken = placed.contains { p in
                let cx = p.x + p.w / 2, cy = p.y + p.h / 2
                return cx >= slot.x - 6 && cx <= slot.x + slot.w + 6 && cy >= slot.y - 6 && cy <= slot.y + slot.h + 6
            }
            if !taken { free.append(slot) }
        }
        return zip(pocket, free).map { label, slot in
            (label.id, pos(x: slot.x + slot.w / 2, y: slot.y + slot.h / 2, rot: slot.rot))
        }
    }

    /// 動かしたラベルのよれ（0〜1）。**動かした回数が増えるほど少し強く**（2026-10-17 判断: 3回で止める）
    static func wrinkle(moves: Int) -> Double {
        min(1, Double(max(0, moves)) / 3)
    }

    /// よれの折れ目（ラベルの枠の割合で、始まりと終わり）。**同じ種・同じ強さなら同じ線**。
    /// 強いほど本数が増える（1〜3 本）
    static func creases(seed: Int, wrinkle: Double) -> [(x0: Double, y0: Double, x1: Double, y1: Double)] {
        guard wrinkle > 0 else { return [] }
        let count = wrinkle > 0.67 ? 3 : wrinkle > 0.34 ? 2 : 1
        var out: [(x0: Double, y0: Double, x1: Double, y1: Double)] = []
        var h = UInt64(truncatingIfNeeded: max(0, seed)) &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491
        func next() -> Double {
            h ^= h >> 33
            h = h &* 0xFF51_AFD7_ED55_8CCD
            h ^= h >> 33
            return Double(h % 10_000) / 10_000
        }
        for _ in 0..<count {
            // 斜めに横切る線（上の辺のどこかから、下の辺のどこかへ）
            let a = 0.1 + next() * 0.8, b = 0.1 + next() * 0.8
            out.append((a, 0.05, b, 0.95))
        }
        return out
    }
}

// MARK: - 自分の手で貼る画面の組み

/// 自分の手で貼る画面の、トランクの置き方（幅に合わせて縮める・指の点を胴の座標へ）
struct TrunkStickLayout: Equatable {
    /// 360×300 の絵を縮める比
    let scale: Double
    /// 絵（360×300）の左上（画面の座標）
    let originX: Double
    let originY: Double

    /// - Parameters:
    ///   - width: 画面の幅
    ///   - top: トランクの絵を置く上の位置（モック: 見出し 56 ＋ 28）
    ///   - maxHeight: トランクに使える高さ（小さい画面で縮める）
    init(width: Double, top: Double, maxHeight: Double = .infinity) {
        let byWidth = (width - 30) / TrunkLooks.canvasWidth
        let byHeight = maxHeight / TrunkLooks.canvasHeight
        scale = max(0.5, min(1, byWidth, byHeight))
        originX = (width - TrunkLooks.canvasWidth * scale) / 2
        originY = top
    }

    /// 絵の大きさ（画面の pt）
    var size: (w: Double, h: Double) { (TrunkLooks.canvasWidth * scale, TrunkLooks.canvasHeight * scale) }

    /// 画面の点 → 胴の座標（持ち上げのずらしを引いてから）
    func bodyPoint(screenX x: Double, screenY y: Double, lifted: Bool) -> (x: Double, y: Double) {
        let lift = lifted ? TrunkPlacement.liftOffset : 0
        return ((x - originX) / scale, (y - lift - originY) / scale - TrunkLooks.bodyTop)
    }

    /// 胴の座標 → 画面の点
    func screenPoint(bodyX x: Double, bodyY y: Double) -> (x: Double, y: Double) {
        (originX + x * scale, originY + (y + TrunkLooks.bodyTop) * scale)
    }
}

/// 保存を待っている置き場（回した・動かした。**ラベルごとに**持つ・2026-10-17 の見直し）。
///
/// 以前は保存の予定を1つしか持たず、別のラベルを回すと前のラベルの保存が消えた。閉じるときは
/// ここに残っている分を全部送る（`TrunkStickView.flush`）
struct TrunkPendingPlaces: Equatable {
    struct Item: Equatable {
        /// 動かし始める前の置き場（戻す1手に使う）
        let from: TrunkPos
        /// 送る置き場（いちばん新しい値）
        var to: TrunkPos
    }

    private(set) var items: [String: Item] = [:]

    var isEmpty: Bool { items.isEmpty }
    /// 送る順（id の順・決まった順）
    var ids: [String] { items.keys.sorted() }

    subscript(id: String) -> Item? { items[id] }

    /// 動かした（はじめの置き場は最初の1回だけ覚える）
    mutating func note(_ id: String, from: TrunkPos, to: TrunkPos) {
        if var item = items[id] {
            item.to = to
            items[id] = item
        } else {
            items[id] = Item(from: from, to: to)
        }
    }

    /// 送れた・断られた。**送ったあとにまた動かしていたら消さない**（新しい値をあとで送る）
    mutating func done(_ id: String, sent: TrunkPos) {
        guard let item = items[id], TrunkPlacement.clamp(item.to) == TrunkPlacement.clamp(sent) else { return }
        items[id] = nil
    }

    /// 画面の上に出す置き場
    var overrides: [String: TrunkPos] { items.mapValues(\.to) }
}
